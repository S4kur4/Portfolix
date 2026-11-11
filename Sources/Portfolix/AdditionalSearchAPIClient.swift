import Foundation

enum AdditionalSearchAPIError: LocalizedError, Equatable {
    case missingAPIKey(SearchProviderOption)
    case invalidAPIKey(SearchProviderOption)
    case invalidQuery
    case invalidResponse(SearchProviderOption)
    case http(SearchProviderOption, Int)
    case network(SearchProviderOption)

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider): "尚未配置 \(provider.rawValue) API Key"
        case let .invalidAPIKey(provider): "\(provider.rawValue) API Key 格式无效"
        case .invalidQuery: "搜索词为空或过长"
        case let .invalidResponse(provider): "\(provider.rawValue) 返回数据无法解析"
        case let .http(provider, status):
            switch status {
            case 401, 403: "\(provider.rawValue) API Key 无效或已失效"
            case 402: "\(provider.rawValue) 搜索额度不足，请检查账户余额"
            case 429: "\(provider.rawValue) 请求已达到频率限制"
            default: "\(provider.rawValue) 搜索服务暂时不可用（\(status)）"
            }
        case let .network(provider): "\(provider.rawValue) 搜索请求失败，请稍后重试"
        }
    }
}

final class AdditionalSearchAPIClient: WebSearching, @unchecked Sendable {
    private let provider: SearchProviderOption
    private let session: URLSession
    private let maximumResponseBytes = 2 * 1024 * 1024

    init(provider: SearchProviderOption, session: URLSession? = nil) {
        self.provider = provider
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func makeRequest(query: String, quality: SearchQuality, apiKey: String) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AdditionalSearchAPIError.missingAPIKey(provider) }
        guard key.count <= 4096, key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
            throw AdditionalSearchAPIError.invalidAPIKey(provider)
        }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 128 else { throw AdditionalSearchAPIError.invalidQuery }
        let endpoint: URL
        let body: [String: Any]
        switch provider {
        case .exa:
            endpoint = URL(string: "https://api.exa.ai/search")!
            body = ["query": query, "type": quality == .advanced ? "deep" : "auto",
                    "numResults": SearchExecutionPolicy.requestedResultCount, "contents": ["highlights": true]]
        case .anysearch:
            endpoint = URL(string: "https://api.anysearch.com/v1/search")!
            body = ["query": query, "max_results": SearchExecutionPolicy.requestedResultCount]
        default: throw AdditionalSearchAPIError.invalidResponse(provider)
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if provider == .exa { request.setValue(key, forHTTPHeaderField: "x-api-key") }
        else { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func search(query: String, positions: [Position], configuration: SearchConfiguration, apiKey: String) async throws -> [AssetResearchSource] {
        try Task.checkCancellation()
        let request = try makeRequest(query: query, quality: configuration.quality, apiKey: apiKey)
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: SearchAPIRedirectPolicy.shared)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw AdditionalSearchAPIError.invalidResponse(provider) }
            // AnySearch may return credentials in error bodies, including HTTP 402.
            // Never consume, log or pass those bodies to the Agent.
            guard response.statusCode == 200 else { throw AdditionalSearchAPIError.http(provider, response.statusCode) }
            guard response.expectedContentLength <= maximumResponseBytes else { throw AdditionalSearchAPIError.invalidResponse(provider) }
            var data = Data()
            for try await byte in bytes {
                guard data.count < maximumResponseBytes else { throw AdditionalSearchAPIError.invalidResponse(provider) }
                data.append(byte)
            }
            try Task.checkCancellation()
            return try sources(from: data, positions: positions)
        } catch is CancellationError { throw CancellationError() }
        catch let error as AdditionalSearchAPIError { throw error }
        catch {
            try Task.checkCancellation()
            throw AdditionalSearchAPIError.network(provider)
        }
    }

    func sources(from data: Data, positions: [Position]) throws -> [AssetResearchSource] {
        guard data.count <= maximumResponseBytes else { throw AdditionalSearchAPIError.invalidResponse(provider) }
        let results: [TavilySearchResult]
        do {
            switch provider {
            case .exa:
                let response = try JSONDecoder().decode(ExaResponse.self, from: data)
                results = response.results.prefix(50).map { result in
                    let highlights = (result.highlights ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
                    let content = [highlights, result.text ?? "", result.summary ?? ""].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
                    return TavilySearchResult(title: result.title ?? "", url: result.url, content: content, publishedDate: result.publishedDate)
                }
            case .anysearch:
                let response = try JSONDecoder().decode(AnySearchResponse.self, from: data)
                guard response.code == 0, let payload = response.data else { throw AdditionalSearchAPIError.invalidResponse(provider) }
                results = payload.results.prefix(50).map { result in
                    let content = [result.snippet ?? "", result.content ?? ""].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
                    return TavilySearchResult(title: result.title, url: result.url, content: content, publishedDate: nil)
                }
            default: throw AdditionalSearchAPIError.invalidResponse(provider)
            }
        } catch { throw AdditionalSearchAPIError.invalidResponse(provider) }
        var seenURLs = Set<String>()
        let safe = results.filter {
            (try? LLMBaseURLValidator.validatedComponents(from: $0.url)) != nil
                && seenURLs.insert($0.url).inserted
        }
        return TavilyClient.sources(from: TavilySearchResponse(query: "", results: safe), positions: positions)
    }

    private struct ExaResponse: Decodable {
        let results: [Result]
        struct Result: Decodable {
            let title: String?
            let url: String
            let publishedDate: String?
            let highlights: [String]?
            let text: String?
            let summary: String?
        }
    }
    private struct AnySearchResponse: Decodable {
        let code: Int
        let data: Payload?
        struct Payload: Decodable { let results: [Result] }
        struct Result: Decodable {
            let title: String
            let url: String
            let snippet: String?
            let content: String?
        }
    }
}

final class SearchAPIRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = SearchAPIRedirectPolicy()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
