import Foundation

enum DeepSeekSearchError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidQuery
    case invalidResponse
    case unauthorized
    case insufficientBalance
    case rateLimited
    case serverError(Int)
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "请先配置 DeepSeek API Key"
        case .invalidQuery: "DeepSeek Search 搜索词须为 1 至 128 个字符"
        case .invalidResponse: "DeepSeek Search 返回数据无法解析"
        case .unauthorized: "DeepSeek API Key 无效或无搜索权限"
        case .insufficientBalance: "DeepSeek 账户余额不足，无法使用搜索"
        case .rateLimited: "DeepSeek Search 请求频率受限，请稍后重试"
        case let .serverError(status): "DeepSeek Search 暂时不可用（\(status)）"
        case .requestFailed: "DeepSeek Search 连接失败，请稍后重试"
        }
    }
}

final class DeepSeekSearchClient: WebSearching, @unchecked Sendable {
    static let shared = DeepSeekSearchClient()
    static let endpoint = URL(string: "https://api.deepseek.com/v1/tools/search")!
    static let maximumResponseBytes = 2_000_000
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: configuration, delegate: DeepSeekSearchRedirectPolicy(), delegateQueue: nil)
        }
    }

    func makeRequest(query: String, apiKey: String, count: Int = SearchExecutionPolicy.requestedResultCount) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: \.isNewline) else { throw DeepSeekSearchError.missingAPIKey }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.unicodeScalars.count <= 128 else { throw DeepSeekSearchError.invalidQuery }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Request(query: query, count: min(max(count, 1), 50), needContent: false))
        return request
    }

    func search(query: String, positions: [Position], configuration _: SearchConfiguration, apiKey: String) async throws -> [AssetResearchSource] {
        let request = try makeRequest(query: query, apiKey: apiKey)
        do {
            for attempt in 0...1 {
                try Task.checkCancellation()
                let (bytes, response) = try await session.bytes(for: request)
                defer { bytes.task.cancel() }
                guard let http = response as? HTTPURLResponse else { throw DeepSeekSearchError.invalidResponse }
                if attempt == 0, [408, 429, 500, 502, 503, 504].contains(http.statusCode) {
                    bytes.task.cancel()
                    // Search is read-only; retry transient failures once without exposing response bodies.
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                try Self.validateStatus(http.statusCode)
                var data = Data()
                for try await byte in bytes {
                    guard data.count < Self.maximumResponseBytes else { throw DeepSeekSearchError.invalidResponse }
                    data.append(byte)
                }
                return try Self.parse(data, positions: positions)
            }
            throw DeepSeekSearchError.invalidResponse
        } catch let error as DeepSeekSearchError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw DeepSeekSearchError.requestFailed
        }
    }

    static func validateStatus(_ status: Int) throws {
        switch status {
        case 200: return
        case 401, 403: throw DeepSeekSearchError.unauthorized
        case 402: throw DeepSeekSearchError.insufficientBalance
        case 429: throw DeepSeekSearchError.rateLimited
        default: throw DeepSeekSearchError.serverError(status)
        }
    }

    static func parse(_ data: Data, positions: [Position]) throws -> [AssetResearchSource] {
        guard data.count <= maximumResponseBytes,
              let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw DeepSeekSearchError.invalidResponse
        }
        var seen = Set<String>()
        let results = response.results.prefix(50).compactMap { result -> TavilySearchResult? in
            guard let components = try? LLMBaseURLValidator.validatedComponents(from: result.url),
                  components.scheme == "https", let url = components.url,
                  seen.insert(url.absoluteString).inserted else { return nil }
            let content = [result.summary, result.snippet].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            return TavilySearchResult(title: result.title, url: url.absoluteString, content: content, publishedDate: result.date)
        }
        return TavilyClient.sources(from: TavilySearchResponse(query: "", results: results), positions: positions)
    }

    private struct Request: Encodable {
        let query: String
        let count: Int
        let needContent: Bool
        enum CodingKeys: String, CodingKey { case query, count; case needContent = "need_content" }
    }

    private struct Response: Decodable { let results: [Result] }
    private struct Result: Decodable {
        let title: String
        let url: String
        let summary: String?
        let snippet: String?
        let date: String?
        let rerankScore: Double?
        enum CodingKeys: String, CodingKey { case title, url, summary, snippet, date; case rerankScore = "rerank_score" }
    }
}

private final class DeepSeekSearchRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
