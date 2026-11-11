import CSQLite
import Darwin
import Foundation
import Testing
@testable import Portfolix

@Suite("Opt-in public search quality campaign")
struct SearchIntentLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTFOLIX_RUN_SEARCH_INTENT_LIVE"] == "1"))
    func publicQuestionsAndContextualFollowUpsUseRelevantSources() async throws {
        let directory = try SearchCampaignLedger.directory()
        let credentials = try SearchCampaignCredentials()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchCampaignProtocol.self]
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let agent = AIAnalysisAgent(llm: DeepSeekResponsesClient(session: session), search: SearchProviderClient(
            tavily: TavilyClient(session: session), parallel: ParallelSearchMCPClient(session: session),
            deepseek: DeepSeekSearchClient(session: session)), credentialStore: credentials)
        let election = "美国中期选举现在出结果了吗，对后续股市会有什么影响？请核对最新公开来源。"
        let all: Set<SearchProviderOption> = [.parallel, .deepseek, .tavily]

        func run(_ name: String, question: String, providers: Set<SearchProviderOption>, history: [AIReportChatItem] = [], needsSearch: Bool = true) async throws -> String {
            let output = directory.appendingPathComponent("\(name).json")
            if FileManager.default.fileExists(atPath: output.path) {
                let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any]
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let rawResults = try JSONSerialization.data(withJSONObject: saved?["results"] ?? [])
                let results = try decoder.decode([AIWebSearchToolResult].self, from: rawResults)
                let answer = saved?["answer"] as? String ?? ""
                let replay = AIMessageCitationResolver.resolve(answer, catalog: AIMessageCitationResolver.catalog(from: results))
                let citations = (saved?["citation_count"] as? Int ?? 0) + replay.citations.count
                #expect(!replay.text.isEmpty)
                #expect(!replay.text.contains("[[source_"))
                if needsSearch { #expect(citations > 0) }
                else { #expect(saved?["search_requests"] as? Int == 0) }
                print("Search campaign scenario=\(name) resumed_without_requests")
                print("Search campaign scenario=\(name) replay_citations=\(citations)")
                return replay.text
            }
            print("Search campaign scenario=\(name) started")
            let result = try await agent.answerFollowUp(question: question, report: nil, artifacts: nil,
                chatHistory: history, positions: [], llmConfiguration: .default,
                searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: providers, quality: .basic))
            let results = try JSONSerialization.jsonObject(with: Data(result.toolResultsJSON.utf8)) as? [[String: Any]] ?? []
            let plans = try JSONSerialization.jsonObject(with: Data(result.toolPlanJSON.utf8))
            let sources = results.flatMap { $0["sources"] as? [[String: Any]] ?? [] }
            let summary: [String: Any] = ["scenario": name, "question": question, "answer": result.answer,
                "plans": plans, "results": results, "search_mode": result.searchMode,
                "search_requests": result.modelUsage?.searchUsage?.requestCount ?? 0,
                "unique_sources": result.modelUsage?.searchUsage?.resultCount ?? 0,
                "citation_count": result.citations.count, "model_calls": result.modelUsage?.calls.count ?? 0,
                "stages": result.modelUsage?.calls.map(\.stage) ?? [],
                "tokens": result.modelUsage?.knownTotalTokens ?? 0]
            try SearchCampaignLedger.write(summary, to: output)
            #expect(!result.answer.isEmpty)
            if needsSearch {
                #expect(result.toolCallCount > 0)
                #expect(!sources.isEmpty)
                #expect(result.citations.count > 0)
            } else {
                #expect(result.toolCallCount == 0)
            }
            if name.hasPrefix("election") {
                #expect(results.allSatisfy { ($0["position_refs"] as? [String])?.isEmpty == true })
                #expect(results.contains { ($0["query"] as? String ?? "").range(of: "election|midterm|选举|计票", options: [.regularExpression, .caseInsensitive]) != nil })
            }
            print("Search campaign scenario=\(name) model_calls=\(result.modelUsage?.calls.count ?? 0) search_requests=\(result.modelUsage?.searchUsage?.requestCount ?? 0) sources=\(sources.count) citations=\(result.citations.count)")
            return result.answer
        }

        let first = try await run("election_initial", question: election, providers: all)
        _ = try await run("election_follow_up", question: "你帮我查一下？", providers: all,
            history: [.user(election, createdAt: Date(timeIntervalSince1970: 1)), .assistant(first, createdAt: Date(timeIntervalSince1970: 2))])
        _ = try await run("us_market", question: "美股最近几个交易日下跌的主要原因是什么？请核对报道日期和不同来源。", providers: [.deepseek, .tavily])
        _ = try await run("gold_market", question: "最近黄金价格变化主要受哪些因素影响？请查本周权威报道，区分事实和推断。", providers: [.parallel, .tavily])
        _ = try await run("general_knowledge", question: "请用两句话解释复利，不需要搜索或持仓信息。", providers: all, needsSearch: false)
        _ = try await run("deepseek_search_only", question: "请搜索美联储最近一次利率决定的日期和决定内容，使用官方来源。", providers: [.deepseek])
        if ProcessInfo.processInfo.environment["PORTFOLIX_SEARCH_INTENT_LIVE_RETEST"] == "1" {
            _ = try await run("citation_retest", question: "请查本周黄金价格变化的主要原因。用三句话回答并附来源，注明报道日期，不需要持仓信息。", providers: [.parallel, .tavily])
        }
    }
}

// Only credential rows are read. No portfolio tables or persistent settings are loaded or modified.
private struct SearchCampaignCredentials: ProviderCredentialStoring {
    let values: [ProviderCredentialKind: String]
    init() throws {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/app.portfolix.mac/portfolix.sqlite3").path
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else { throw ProviderCredentialError.unavailable }
        defer { sqlite3_close(handle) }
        var values: [ProviderCredentialKind: String] = [:]
        for kind in [ProviderCredentialKind.llm, .tavily] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT value FROM app_settings WHERE key = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK, let statement else { throw ProviderCredentialError.unavailable }
            defer { sqlite3_finalize(statement) }
            _ = kind.databaseKey.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw ProviderCredentialError.unavailable }
            values[kind] = String(cString: text)
        }
        self.values = values
    }
    func read(kind: ProviderCredentialKind) throws -> String? { values[kind] }
    func save(_: String, kind _: ProviderCredentialKind) throws { throw ProviderCredentialError.unavailable }
    func delete(kind _: ProviderCredentialKind) throws { throw ProviderCredentialError.unavailable }
    func readValidationState(kind _: ProviderCredentialKind) throws -> ProviderCredentialValidationState { .valid }
    func saveValidationState(_: ProviderCredentialValidationState, kind _: ProviderCredentialKind) throws { throw ProviderCredentialError.unavailable }
}

private enum SearchCampaignLedger {
    static func directory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["PORTFOLIX_SEARCH_INTENT_LIVE_DIRECTORY"] else { throw AIModelBudgetError.exhausted }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"),
              try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AIModelBudgetError.exhausted }
        return url
    }
    static func write(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func reserve(provider: String, kind: String) throws -> Int {
        let directory = try directory()
        let lock = open(directory.appendingPathComponent("budget.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw AIModelBudgetError.exhausted }
        defer { _ = close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw AIModelBudgetError.exhausted }
        defer { _ = flock(lock, LOCK_UN) }
        let url = directory.appendingPathComponent("budget.json")
        var ledger = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var requests = ledger["requests"] as? [[String: Any]] ?? []
        let maximum = kind == "model" ? 16 : 18
        guard requests.filter({ $0["kind"] as? String == kind }).count < maximum else { throw AIModelBudgetError.exhausted }
        let id = requests.count + 1
        requests.append(["id": id, "kind": kind, "provider": provider, "reserved_at": ISO8601DateFormatter().string(from: .now)])
        ledger["requests"] = requests
        try write(ledger, to: url)
        print("Search campaign reserved kind=\(kind) provider=\(provider) count=\(requests.filter { $0["kind"] as? String == kind }.count)/\(maximum)")
        return id
    }
}

// Count at the HTTP boundary, including retries, before sending any billable request.
// The forwarding session has no interception, cookies, cache, stored credentials or redirects.
private final class SearchCampaignProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var work: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let task = Task { @Sendable [self] in
            do {
                var forward = request
                if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var body = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count < 0 { throw URLError(.cannotDecodeContentData) }
                        if count == 0 { break }
                        body.append(contentsOf: buffer.prefix(count))
                        guard body.count <= 1_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
                    }
                    forward.httpBodyStream = nil
                    forward.httpBody = body
                }
                guard let url = forward.url, url.scheme == "https", url.user == nil, url.password == nil else { throw URLError(.unsupportedURL) }
                switch (url.host, url.path) {
                case ("api.deepseek.com", let path) where path.hasSuffix("/responses"):
                    _ = try SearchCampaignLedger.reserve(provider: "DeepSeek", kind: "model")
                case ("api.deepseek.com", "/v1/tools/search"):
                    _ = try SearchCampaignLedger.reserve(provider: "DeepSeek Search", kind: "search")
                case ("api.tavily.com", "/search"):
                    _ = try SearchCampaignLedger.reserve(provider: "Tavily", kind: "search")
                case ("search.parallel.ai", "/mcp"):
                    let body = forward.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    if body?["method"] as? String == "tools/call" { _ = try SearchCampaignLedger.reserve(provider: "Parallel", kind: "search") }
                default: throw URLError(.unsupportedURL)
                }
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = []
                config.urlCache = nil; config.urlCredentialStorage = nil
                config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
                config.timeoutIntervalForResource = 120
                let session = URLSession(configuration: config, delegate: SearchCampaignRedirectPolicy(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(for: forward)
                try Task.checkCancellation()
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        lock.withLock { work = task }
    }
    override func stopLoading() { lock.withLock { work?.cancel(); work = nil } }
}

private final class SearchCampaignRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
