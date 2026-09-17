import Foundation

enum ParallelSearchMCPError: LocalizedError, Equatable {
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case protocolError(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Parallel 返回数据无法解析"
        case .unauthorized:
            "Parallel Search 免费搜索服务暂时不可用"
        case .rateLimited:
            "Parallel Search 免费搜索服务已达到频率限制"
        case let .serverError(status):
            "Parallel 服务暂时不可用（\(status)）"
        case let .protocolError(message):
            "Parallel MCP 返回错误：\(message)"
        case let .requestFailed(message):
            "Parallel 请求失败：\(message)"
        }
    }
}

final class ParallelSearchMCPClient: WebSearching, @unchecked Sendable {
    static let shared = ParallelSearchMCPClient()

    private static let maximumResponseBytes = 2_000_000
    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://search.parallel.ai/mcp")!,
        session: URLSession? = nil
    ) {
        self.endpoint = endpoint
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func search(
        query: String,
        positions: [Position],
        configuration _: SearchConfiguration,
        apiKey _: String
    ) async throws -> [AssetResearchSource] {
        let normalizedQuery = query
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty, normalizedQuery.count <= 180 else {
            throw ParallelSearchMCPError.invalidResponse
        }

        var sessionID: String?
        do {
            let initialize = try await send(
                body: [
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": [
                        "protocolVersion": "2025-06-18",
                        "capabilities": [:],
                        "clientInfo": ["name": "Portfolix", "version": "0.1"],
                    ],
                ],
                sessionID: nil,
                acceptsEmptyBody: false
            )
            sessionID = initialize.sessionID
            guard let sessionID, !sessionID.isEmpty else {
                throw ParallelSearchMCPError.invalidResponse
            }

            _ = try await send(
                body: [
                    "jsonrpc": "2.0",
                    "method": "notifications/initialized",
                ],
                sessionID: sessionID,
                acceptsEmptyBody: true
            )

            let searchSessionID = UUID().uuidString.lowercased()
            let response = try await send(
                body: [
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "tools/call",
                    "params": [
                        "name": "web_search",
                        "arguments": [
                            "objective": normalizedQuery,
                            "search_queries": [normalizedQuery],
                            "session_id": searchSessionID,
                        ],
                    ],
                ],
                sessionID: sessionID,
                acceptsEmptyBody: false
            )
            try? await close(sessionID: sessionID)
            return Self.sources(from: response.payload, positions: positions)
        } catch let error as ParallelSearchMCPError {
            if let sessionID { try? await close(sessionID: sessionID) }
            throw error
        } catch {
            if let sessionID { try? await close(sessionID: sessionID) }
            throw ParallelSearchMCPError.requestFailed(error.localizedDescription)
        }
    }

    private func send(
        body: [String: Any],
        sessionID: String?,
        acceptsEmptyBody: Bool
    ) async throws -> (payload: Any, sessionID: String?) {
        var request = URLRequest(url: endpoint, timeoutInterval: 24)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Portfolix/0.1", forHTTPHeaderField: "User-Agent")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
            request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ParallelSearchMCPError.invalidResponse
        }
        try Self.validateStatus(httpResponse.statusCode)
        guard data.count <= Self.maximumResponseBytes else {
            throw ParallelSearchMCPError.invalidResponse
        }
        if data.isEmpty, acceptsEmptyBody {
            return ([:], httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id"))
        }
        let payload = try Self.decodePayload(data)
        if let object = payload as? [String: Any],
           let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "unknown_error"
            throw ParallelSearchMCPError.protocolError(String(message.prefix(180)))
        }
        return (payload, httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id"))
    }

    private func close(sessionID: String) async throws {
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.httpMethod = "DELETE"
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        _ = try await session.data(for: request)
    }

    private static func validateStatus(_ status: Int) throws {
        switch status {
        case 200...299: return
        case 401, 403: throw ParallelSearchMCPError.unauthorized
        case 429: throw ParallelSearchMCPError.rateLimited
        case 500...599: throw ParallelSearchMCPError.serverError(status)
        default: throw ParallelSearchMCPError.serverError(status)
        }
    }

    private static func decodePayload(_ data: Data) throws -> Any {
        if let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParallelSearchMCPError.invalidResponse
        }
        let eventPayloads = text
            .split(whereSeparator: \Character.isNewline)
            .compactMap { line -> String? in
                let value = String(line)
                guard value.hasPrefix("data:") else { return nil }
                return String(value.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        for payload in eventPayloads.reversed() {
            if let payloadData = payload.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: payloadData) {
                return object
            }
        }
        throw ParallelSearchMCPError.invalidResponse
    }

    static func sources(from payload: Any, positions: [Position]) -> [AssetResearchSource] {
        var candidates: [[String: Any]] = []
        collectSourceObjects(in: payload, into: &candidates)
        var seenURLs = Set<String>()
        let sources = candidates.compactMap { candidate -> AssetResearchSource? in
            guard let rawURL = candidate["url"] as? String else { return nil }
            let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (try? LLMBaseURLValidator.validatedComponents(from: url)) != nil,
                  seenURLs.insert(url).inserted else { return nil }

            let title = TavilyClient.sanitizedTitle((candidate["title"] as? String) ?? "Untitled")
            let excerpts = candidate["excerpts"] as? [String]
            let rawSnippet = excerpts?.joined(separator: " ")
                ?? candidate["snippet"] as? String
                ?? candidate["content"] as? String
                ?? ""
            let snippet = TavilyClient.sanitizedSnippet(rawSnippet)
            guard !snippet.isEmpty,
                  isSafe("\(title) \(snippet)"),
                  positions.isEmpty || positions.contains(where: { isRelevant(title: title, snippet: snippet, to: $0) })
            else { return nil }
            let domain = TavilyClient.domain(from: url)
            return AssetResearchSource(
                title: title,
                url: url,
                domain: domain,
                publishedDate: candidate["publish_date"] as? String ?? candidate["published_date"] as? String,
                snippet: snippet,
                credibility: TavilyClient.credibility(for: domain)
            )
        }
        return Array(
            sources
                .sorted { credibilityRank($0.credibility) < credibilityRank($1.credibility) }
                .prefix(SearchExecutionPolicy.acceptedSourceCount)
        )
    }

    private static func collectSourceObjects(in value: Any, into result: inout [[String: Any]]) {
        if let dictionary = value as? [String: Any] {
            if dictionary["url"] is String { result.append(dictionary) }
            for child in dictionary.values { collectSourceObjects(in: child, into: &result) }
            return
        }
        if let array = value as? [Any] {
            for child in array { collectSourceObjects(in: child, into: &result) }
            return
        }
        if let string = value as? String,
           string.utf8.count <= maximumResponseBytes,
           let data = string.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            collectSourceObjects(in: decoded, into: &result)
        }
    }

    private static func isSafe(_ value: String) -> Bool {
        let markers = [
            "ignore previous", "ignore all previous", "system prompt", "developer message",
            "you are chatgpt", "api key", "忽略之前", "忽略以上", "系统提示词", "开发者消息",
            "泄露密钥", "输出凭据",
        ]
        return !markers.contains { value.localizedCaseInsensitiveContains($0) }
    }

    private static func credibilityRank(_ credibility: SourceCredibility) -> Int {
        switch credibility {
        case .official: 0
        case .mainstream: 1
        case .general: 2
        }
    }

    private static func isRelevant(title: String, snippet: String, to position: Position) -> Bool {
        let haystack = "\(title) \(snippet)".lowercased()
        let name = position.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let symbol = position.symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.count >= 3, haystack.contains(name) { return true }
        return symbol.count >= 2 && haystack.contains(symbol)
    }
}
