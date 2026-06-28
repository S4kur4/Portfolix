import Foundation

enum TavilyClientError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "尚未配置 Tavily API Key"
        case .invalidResponse:
            "Tavily 返回数据无法解析"
        case .unauthorized:
            "Tavily API Key 无效或已失效"
        case .rateLimited:
            "Tavily 请求已达到频率或额度限制"
        case let .serverError(status):
            "Tavily 服务暂时不可用（\(status)）"
        case let .requestFailed(message):
            "Tavily 请求失败：\(message)"
        }
    }
}

protocol WebSearching: Sendable {
    func search(
        query: String,
        positions: [Position],
        configuration: SearchConfiguration,
        apiKey: String
    ) async throws -> [AssetResearchSource]
}

typealias TavilySearching = WebSearching

final class SearchProviderClient: WebSearching, @unchecked Sendable {
    static let shared = SearchProviderClient()

    private let tavily: TavilyClient
    private let bocha: BochaAIClient

    init(tavily: TavilyClient = .shared, bocha: BochaAIClient = .shared) {
        self.tavily = tavily
        self.bocha = bocha
    }

    func search(
        query: String,
        positions: [Position],
        configuration: SearchConfiguration,
        apiKey: String
    ) async throws -> [AssetResearchSource] {
        switch configuration.provider {
        case .tavily:
            try await tavily.search(
                query: query,
                positions: positions,
                configuration: configuration,
                apiKey: apiKey
            )
        case .bocha:
            try await bocha.search(
                query: query,
                positions: positions,
                configuration: configuration,
                apiKey: apiKey
            )
        }
    }
}

final class TavilyClient: WebSearching, @unchecked Sendable {
    static let shared = TavilyClient()

    private let endpoint = URL(string: "https://api.tavily.com/search")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        position: Position,
        configuration: SearchConfiguration,
        apiKey: String
    ) async throws -> AssetResearchResult {
        let query = Self.query(for: position)
        let sources = try await search(
            query: query,
            positions: [position],
            configuration: configuration,
            apiKey: apiKey
        )
        return AssetResearchResult(
            positionRef: "position_\(position.id.uuidString)",
            assetName: position.name,
            symbol: position.symbol,
            category: position.category.aiCode,
            query: query,
            searchedAt: .now,
            status: sources.isEmpty ? "empty" : "ok",
            sourceCount: sources.count,
            results: sources
        )
    }

    func search(
        query: String,
        positions: [Position],
        configuration: SearchConfiguration,
        apiKey: String
    ) async throws -> [AssetResearchSource] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw TavilyClientError.missingAPIKey
        }

        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            TavilySearchRequest(
                query: query,
                topic: "finance",
                searchDepth: configuration.searchDepth.rawValue,
                maxResults: configuration.maxResults,
                includeAnswer: false,
                includeRawContent: false
            )
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TavilyClientError.invalidResponse
            }
            switch httpResponse.statusCode {
            case 200:
                let response = try JSONDecoder().decode(TavilySearchResponse.self, from: data)
                return Self.sources(from: response, positions: positions)
            case 401, 403:
                throw TavilyClientError.unauthorized
            case 429:
                throw TavilyClientError.rateLimited
            case 500...599:
                throw TavilyClientError.serverError(httpResponse.statusCode)
            default:
                throw TavilyClientError.serverError(httpResponse.statusCode)
            }
        } catch let error as TavilyClientError {
            throw error
        } catch {
            throw TavilyClientError.requestFailed(error.localizedDescription)
        }
    }

    static func query(for position: Position) -> String {
        switch position.category {
        case .fund:
            return "\"\(position.name)\" \(position.symbol) 基金公告 最新季报 风险"
        default:
            let category = position.category.title(language: .chinese)
            return "\"\(position.name)\" \(position.symbol) \(category) 最新公告 风险 财经新闻"
        }
    }

    static func researchResult(
        from response: TavilySearchResponse,
        position: Position,
        query: String,
        searchedAt: Date = .now
    ) -> AssetResearchResult {
        let sources = response.results.prefix(8).compactMap { result -> AssetResearchSource? in
            let url = result.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let components = URLComponents(string: url),
                components.scheme?.lowercased() == "https",
                components.host != nil,
                !containsInstructionLikeContent("\(result.title) \(result.content)"),
                isRelevant(result, to: position)
            else { return nil }
            let domain = domain(from: url)
            let snippet = sanitizedSnippet(result.content)
            guard !snippet.isEmpty else { return nil }
            return AssetResearchSource(
                title: sanitizedTitle(result.title),
                url: url,
                domain: domain,
                publishedDate: result.publishedDate,
                snippet: snippet,
                credibility: credibility(for: domain)
            )
        }

        return AssetResearchResult(
            positionRef: "position_\(position.id.uuidString)",
            assetName: position.name,
            symbol: position.symbol,
            category: position.category.aiCode,
            query: query,
            searchedAt: searchedAt,
            status: sources.isEmpty ? "empty" : "ok",
            sourceCount: sources.count,
            results: Array(sources)
        )
    }

    static func sources(from response: TavilySearchResponse, positions: [Position]) -> [AssetResearchSource] {
        let sources = response.results.prefix(10).compactMap { result -> AssetResearchSource? in
            let url = result.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let components = URLComponents(string: url),
                components.scheme?.lowercased() == "https",
                components.host != nil,
                !containsInstructionLikeContent("\(result.title) \(result.content)"),
                positions.contains(where: { isRelevant(result, to: $0) })
            else { return nil }
            let domain = domain(from: url)
            let snippet = sanitizedSnippet(result.content)
            guard !snippet.isEmpty else { return nil }
            return AssetResearchSource(
                title: sanitizedTitle(result.title),
                url: url,
                domain: domain,
                publishedDate: result.publishedDate,
                snippet: snippet,
                credibility: credibility(for: domain)
            )
        }
        return Array(
            sources
                .sorted { credibilityRank($0.credibility) < credibilityRank($1.credibility) }
                .prefix(SearchExecutionPolicy.acceptedSourceCount)
        )
    }

    static func sanitizedSnippet(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        return String(collapsed.prefix(360))
    }

    static func sanitizedTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "Untitled" : trimmed).prefix(120))
    }

    static func domain(from url: String) -> String {
        guard let host = URL(string: url)?.host(percentEncoded: false) else {
            return "unknown"
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    static func credibility(for domain: String) -> SourceCredibility {
        let lowercased = domain.lowercased()
        let officialHints = [
            "sec.gov", "hkex.com", "sse.com.cn", "szse.cn", "nasdaq.com",
            "nyse.com", "okx.com", "fund.eastmoney.com", "fundf10.eastmoney.com",
            "csindex.com.cn", "spglobal.com", "msci.com"
        ]
        if officialHints.contains(where: { domainMatches(lowercased, trustedDomain: $0) }) {
            return .official
        }

        let mediaHints = [
            "reuters.com", "bloomberg.com", "wsj.com", "cnbc.com", "ft.com",
            "yahoo.com", "finance.yahoo.com", "marketwatch.com", "caixin.com",
            "cls.cn", "stcn.com", "21jingji.com", "yicai.com"
        ]
        if mediaHints.contains(where: { domainMatches(lowercased, trustedDomain: $0) }) {
            return .mainstream
        }
        return .general
    }

    private static func domainMatches(_ domain: String, trustedDomain: String) -> Bool {
        domain == trustedDomain || domain.hasSuffix(".\(trustedDomain)")
    }

    private static func credibilityRank(_ credibility: SourceCredibility) -> Int {
        switch credibility {
        case .official: 0
        case .mainstream: 1
        case .general: 2
        }
    }

    private static func containsInstructionLikeContent(_ value: String) -> Bool {
        let markers = [
            "ignore previous", "ignore all previous", "system prompt", "developer message",
            "you are chatgpt", "api key", "忽略之前", "忽略以上", "系统提示词", "开发者消息",
            "泄露密钥", "输出凭据",
        ]
        return markers.contains { value.localizedCaseInsensitiveContains($0) }
    }

    private static func isRelevant(_ result: TavilySearchResult, to position: Position) -> Bool {
        let haystack = "\(result.title) \(result.content)".lowercased()
        let name = position.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let symbol = position.symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.count >= 3, haystack.contains(name) {
            return true
        }
        guard symbol.count >= 2, haystack.contains(symbol) else { return false }
        if position.category == .fund {
            return ["基金", "债券", "混合", "指数", "etf", "mutual fund"].contains(where: haystack.contains)
        }
        return true
    }
}

enum BochaAIClientError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "尚未配置 BochaAI API Key"
        case .invalidResponse: "BochaAI 返回数据无法解析"
        case .unauthorized: "BochaAI API Key 无效或已失效"
        case .rateLimited: "BochaAI 请求已达到频率或额度限制"
        case let .serverError(status): "BochaAI 服务暂时不可用（\(status)）"
        case let .requestFailed(message): "BochaAI 请求失败：\(message)"
        }
    }
}

final class BochaAIClient: WebSearching, @unchecked Sendable {
    static let shared = BochaAIClient()

    static let endpoint = URL(string: "https://api.bochaai.com/v1/web-search")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        query: String,
        positions: [Position],
        configuration _: SearchConfiguration,
        apiKey: String
    ) async throws -> [AssetResearchSource] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw BochaAIClientError.missingAPIKey }

        let request = try Self.makeRequest(query: query, apiKey: trimmedKey)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BochaAIClientError.invalidResponse
            }
            switch httpResponse.statusCode {
            case 200:
                return try Self.sources(from: data, query: query, positions: positions)
            case 401, 403:
                throw BochaAIClientError.unauthorized
            case 429:
                throw BochaAIClientError.rateLimited
            default:
                throw BochaAIClientError.serverError(httpResponse.statusCode)
            }
        } catch let error as BochaAIClientError {
            throw error
        } catch is DecodingError {
            throw BochaAIClientError.invalidResponse
        } catch {
            throw BochaAIClientError.requestFailed(error.localizedDescription)
        }
    }

    static func makeRequest(query: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            BochaSearchRequest(
                query: query,
                freshness: "noLimit",
                summary: true,
                count: SearchExecutionPolicy.requestedResultCount
            )
        )
        return request
    }

    static func sources(from data: Data, query: String, positions: [Position]) throws -> [AssetResearchSource] {
        let response = try JSONDecoder().decode(BochaSearchResponse.self, from: data)
        if let code = response.code, code != 200 {
            throw BochaAIClientError.serverError(code)
        }
        let normalized = TavilySearchResponse(
            query: query,
            results: response.results.map {
                TavilySearchResult(
                    title: $0.name ?? "",
                    url: $0.url ?? "",
                    content: $0.summary?.nilIfBlank ?? $0.snippet ?? "",
                    publishedDate: $0.datePublished
                )
            }
        )
        return TavilyClient.sources(from: normalized, positions: positions)
    }
}

private struct BochaSearchRequest: Encodable {
    let query: String
    let freshness: String
    let summary: Bool
    let count: Int
}

private struct BochaSearchResponse: Decodable {
    let code: Int?
    let data: BochaSearchData?
    let webPages: BochaWebPages?

    var results: [BochaWebPage] {
        data?.webPages?.value ?? webPages?.value ?? []
    }
}

private struct BochaSearchData: Decodable {
    let webPages: BochaWebPages?
}

private struct BochaWebPages: Decodable {
    let value: [BochaWebPage]
}

private struct BochaWebPage: Decodable {
    let name: String?
    let url: String?
    let snippet: String?
    let summary: String?
    let datePublished: String?
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

struct TavilySearchRequest: Encodable {
    let query: String
    let topic: String
    let searchDepth: String
    let maxResults: Int
    let includeAnswer: Bool
    let includeRawContent: Bool

    enum CodingKeys: String, CodingKey {
        case query
        case topic
        case searchDepth = "search_depth"
        case maxResults = "max_results"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
    }
}

struct TavilySearchResponse: Decodable {
    let query: String
    let results: [TavilySearchResult]
}

struct TavilySearchResult: Decodable {
    let title: String
    let url: String
    let content: String
    let publishedDate: String?

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case content
        case publishedDate = "published_date"
    }
}
