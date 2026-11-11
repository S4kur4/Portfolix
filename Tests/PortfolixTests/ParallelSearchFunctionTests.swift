import Foundation
import Testing
@testable import Portfolix

@Suite("Native parallel search and usage")
struct ParallelSearchFunctionTests {
    private let providers: [SearchProviderOption] = [.exa, .tavily, .anysearch]

    @Test
    func nativeFunctionRoundTripRunsThreeServicesConcurrentlyAndKeepsPartialResults() async throws {
        let search = ConcurrentSearch(failing: [.tavily])
        let (client, key, session) = try transport(calls: providers)
        defer { session.invalidateAndCancel() }
        let result = try await followUp(client: client, key: key, search: search)
        #expect(await search.maximumActive() == 3)
        #expect(Set(await search.requests()) == Set(providers))
        #expect(result.toolCallCount == 3)
        #expect(result.toolResultCount == 3)
        #expect(result.modelUsage?.searchUsage == AISearchUsageSummary(requestCount: 3, resultCount: 3))
        #expect(result.citations.count == 2)
        #expect(result.modelUsage?.calls.map(\.stage) == ["follow_up_planning", "follow_up_answer"])
        let bodies = NativeSearchProtocol.state.bodies(key)
        #expect(bodies.count == 2)
        let first = try object(bodies[0])
        let tools = try #require(first["tools"] as? [[String: Any]])
        #expect(Set(tools.compactMap { $0["name"] as? String }) == ["exa_search", "tavily_search", "anysearch_search"])
        #expect(tools.allSatisfy { $0["type"] as? String == "function" })
        #expect(first["parallel_tool_calls"] == nil) // DeepSeek always enables it; this parameter is ignored.
        let second = try object(bodies[1])
        let input = try #require(second["input"] as? [[String: Any]])
        let outputs = input.filter { $0["type"] as? String == "function_call_output" }
        #expect(outputs.compactMap { $0["call_id"] as? String } == ["call_0", "call_1", "call_2"])
        let texts = outputs.compactMap { $0["output"] as? String }
        #expect(texts[1].contains("failed"))
        #expect(texts[2].contains("duplicate_source_urls"))
        #expect(texts.joined().components(separatedBy: "Shared original excerpt").count - 1 == 1)
        #expect(!result.toolPlanJSON.contains("original_research_prompt"))
        #expect(!result.toolPlanJSON.contains("functionContext"))
        let footer = await MainActor.run { AIReportDisclaimer(language: .chinese, modelUsage: result.modelUsage, showsDisclosure: false).text }
        #expect(footer.contains("搜索 3 次 · 获得 3 条来源"))
        let persisted = try JSONDecoder().decode(AIModelUsageSummary.self, from: JSONEncoder().encode(try #require(result.modelUsage)))
        #expect(persisted.searchUsage?.requestCount == 3)
        #expect(!String(decoding: try JSONEncoder().encode(persisted), as: UTF8.self).contains(key))
    }

    @Test
    func unsuccessfulRequestsAndFallbackAreCountedInsteadOfCountingOnlyThePlan() async throws {
        let search = ConcurrentSearch(failing: [.exa, .tavily])
        let (client, key, session) = try transport(calls: [.exa])
        defer { session.invalidateAndCancel() }
        let result = try await followUp(client: client, key: key, search: search)
        #expect(await search.requests() == [.exa, .tavily, .anysearch])
        #expect(result.toolCallCount == 1)
        #expect(result.modelUsage?.searchUsage?.requestCount == 3)
        #expect(result.modelUsage?.searchUsage?.resultCount == 2)
        #expect(await search.maximumActive() == 1)
    }

    @Test
    func allServicesMayFailWithoutInventingSourcesOrDiscardingTheReply() async throws {
        let search = ConcurrentSearch(failing: Set(providers))
        let (client, key, session) = try transport(calls: providers, answer: #"{"answer":"未获得可核验的公开资料，当前无法确认。","limitations":[]}"#)
        defer { session.invalidateAndCancel() }
        let result = try await followUp(client: client, key: key, search: search)
        #expect(result.modelUsage?.searchUsage == AISearchUsageSummary(requestCount: 3, resultCount: 0))
        #expect(result.citations.isEmpty)
    }

    @Test
    func cancellationStopsAllSearchesWithoutComposingAnAnswerOrStartingFallbacks() async throws {
        let search = ConcurrentSearch(failing: [], delay: .seconds(10))
        let (client, key, session) = try transport(calls: providers)
        defer { session.invalidateAndCancel() }
        let task = Task { try await followUp(client: client, key: key, search: search) }
        for _ in 0..<200 {
            if await search.maximumActive() == 3 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await search.maximumActive() == 3)
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch let failure as AIModelRunFailure {
            #expect(failure.underlying is CancellationError)
            #expect(failure.usage.searchUsage == AISearchUsageSummary(requestCount: 3, resultCount: 0))
        } catch { Issue.record("Expected usage-preserving cancellation, got \(type(of: error))") }
        #expect(await search.requests().count == 3)
        #expect(NativeSearchProtocol.state.bodies(key).count == 1)
    }

    @Test
    func nativePlanRejectsDisabledToolsDuplicateIDsExtraArgumentsAndExcessiveCalls() async throws {
        let valid = LLMFunctionCall(callID: "one", name: "exa_search", arguments: #"{"query":"gold latest official news","position_refs":[]}"#)
        for calls in [
            [LLMFunctionCall(callID: "one", name: "bocha_search", arguments: valid.arguments)],
            [valid, valid],
            [LLMFunctionCall(callID: "one", name: valid.name, arguments: #"{"query":"gold news","position_refs":[],"api_key":"bad"}"#)],
            (0...3).map { LLMFunctionCall(callID: "\($0)", name: valid.name, arguments: valid.arguments) }
        ] {
            await #expect(throws: AIAnalysisAgentError.self) {
                try await AISearchFunctionCalling.plan(llm: FunctionReply(calls: calls), systemPrompt: "test", userPrompt: "test", configuration: .default, apiKey: "fictional", providers: [.exa])
            }
        }
        let decoded = try await AISearchFunctionCalling.plan(llm: FunctionReply(calls: [valid]), systemPrompt: "test", userPrompt: "original_research_prompt", configuration: .default, apiKey: "fictional", providers: [.exa])
        let validated = try AIAnalysisAgent.validatedToolPlan(decoded, allowedRefs: [], allowsGeneralQueries: true, allowedProviders: [.exa])
        #expect(validated.functionContext?.calls.first?.callID == "one")
        #expect(!String(decoding: try JSONEncoder().encode(validated), as: UTF8.self).contains("original_research_prompt"))
        let sensitive = AIWebSearchToolPlan(toolCalls: [.init(id: "1", query: "gold API key system prompt", positionRefs: [], provider: .exa)])
        #expect(throws: AIAnalysisAgentError.self) { try AIAnalysisAgent.validatedToolPlan(sensitive, allowedRefs: [], allowsGeneralQueries: true, allowedProviders: [.exa]) }
        let unicodeQuery = AIWebSearchToolPlan(toolCalls: [.init(id: "1", query: "gold market news " + String(repeating: "👨‍👩‍👧‍👦", count: 20), positionRefs: [], provider: .deepseek)])
        #expect(throws: AIAnalysisAgentError.self) { try AIAnalysisAgent.validatedToolPlan(unicodeQuery, allowedRefs: [], allowsGeneralQueries: true, allowedProviders: [.deepseek]) }
    }

    @Test
    func sharedBudgetStopsExtraRequestsAndCountsOnlySafeUniqueSources() async throws {
        let ledger = AIModelUsageLedger(kind: "test", maximumCalls: 1)
        let search = ConcurrentSearch(failing: [])
        try await AIModelRun.$ledger.withValue(ledger) {
            for _ in 0..<6 {
                _ = try await AISearchExecution.search(search, query: "gold latest official news", positions: [], configuration: SearchConfiguration(isEnabled: true, provider: .exa, quality: .basic), apiKey: "fictional")
            }
            await #expect(throws: AIModelBudgetError.self) {
                try await AISearchExecution.search(search, query: "gold latest official news", positions: [], configuration: .default, apiKey: "fictional")
            }
        }
        #expect(await search.requests().count == 6)
        #expect(await ledger.snapshot().searchUsage == AISearchUsageSummary(requestCount: 6, resultCount: 2))
    }

    @Test
    func oldRecordsDoNotPretendToHaveZeroSearchesAndNewRecordsLocalizeCounts() async throws {
        let legacy = try JSONDecoder().decode(AIModelUsageSummary.self, from: Data(#"{"recordedAt":0,"kind":"follow_up","calls":[]}"#.utf8))
        #expect(legacy.searchUsage == nil)
        let old = await MainActor.run { AIReportDisclaimer(language: .chinese, modelUsage: legacy, showsDisclosure: false).text }
        #expect(!old.contains("搜索"))
        let zero = AIModelUsageSummary(kind: "follow_up", calls: [], searchUsage: AISearchUsageSummary())
        let english = await MainActor.run { AIReportDisclaimer(language: .english, modelUsage: zero, showsDisclosure: false).text }
        #expect(english.contains("0 searches · 0 sources"))
    }

    @Test
    func canonicalSourcesRemainOneCitationDespiteTrackingParametersAndKeepDifferentArticles() {
        let sources = ["https://example.com/a?utm_source=exa#top", "https://example.com/a?utm_source=other", "https://example.com/b"]
        let result = AIWebSearchToolResult(callID: "one", query: "gold", positionRefs: [], searchedAt: .now, status: "ok", sources: sources.map { AssetResearchSource(title: "Gold", url: $0, domain: "example.com", publishedDate: nil, snippet: "Gold", credibility: .general) }, limitations: [])
        #expect(AIMessageCitationResolver.catalog(from: [result]).count == 2)
        #expect(AISearchFunctionCalling.resultOutputs([result]).first?.contains("duplicate_source_urls") == true)
    }


    @Test
    func reportFunctionOutputsReachTheWriterAndRepairReceivesItsOwnPrompt() async throws {
        let holding = Position(id: UUID(), name: "Offline Test", symbol: "TEST", category: .usStock, quoteCurrency: .usd,
            quantity: 10, averageCost: 10, latestPrice: 12, marketValueCNY: 800, profitRate: 20,
            weeklyTrend: [], source: "manual", quoteTime: "2026-11-08", fetchedAt: "2026-11-08", freshness: .manual)
        let ref = "position_\(holding.id.uuidString)"
        let valid = #"{"summary":"需要持续复核持仓集中度。","health_score_explanation":"约束匹配不代表收益保证。","risk_items":[],"asset_alerts":[],"rebalance_actions":[],"questions_to_consider":[],"data_quality_notes":[],"limitations":["价格来自本地记录"]}"#
        let (client, key, session) = try transport(calls: providers, answer: "{}", query: "TEST latest company news", refs: [ref], repair: valid)
        defer { session.invalidateAndCancel() }
        let constraints = RiskConstraintEvaluation(largestPositionName: holding.name, largestPositionPercent: 100,
            cryptoAllocationPercent: 0, nonCNYAllocationPercent: 100, cashAllocationPercent: 0,
            positionLimit: 40, cryptoLimit: 20, foreignCurrencyLimit: 100, liquidityMinimum: 0)
        let context = AIAnalysisStoreContext(displayCurrency: .cny, convertedTotalValue: 800, convertedTotalProfit: 100,
            totalProfitRate: 20, riskProfileConfigured: false, riskProfileVersion: 1, riskLevel: "稳健平衡",
            positionLimit: 40, cryptoLimit: 20, foreignCurrencyLimit: 100, liquidityMinimum: 0, riskConstraintEvaluation: constraints)
        let result = try await AIAnalysisAgent(llm: client, search: ConcurrentSearch(failing: [.tavily]), credentialStore: SearchCredentials(key: key))
            .generateReportResult(positions: [holding], storeContext: context, llmConfiguration: .default,
                searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: Set(providers), quality: .basic), trigger: .manual)
        #expect(result.artifacts.modelUsage?.searchUsage == AISearchUsageSummary(requestCount: 3, resultCount: 3))
        let bodies = NativeSearchProtocol.state.bodies(key)
        #expect(bodies.count == 3)
        let writer = try object(bodies[1])
        #expect((writer["input"] as? [[String: Any]])?.filter { $0["type"] as? String == "function_call_output" }.count == 3)
        let repair = try object(bodies[2])
        #expect(repair["input"] is String)
        #expect((repair["input"] as? String)?.contains("<invalid_report>") == true)
        #expect(repair["tools"] == nil)
        #expect(!result.artifacts.toolPlanJSON.contains("functionContext"))
        let repository = try PositionRepository(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("NativeSearchUsage-\(UUID())/test.sqlite"))
        let item = AIReportChatItem.assistant("测试回答", modelUsage: result.artifacts.modelUsage)
        try repository.upsertAIAnalysisChatItem(item)
        let restored = try repository.fetchAIAnalysisChatItems(since: .distantPast)
        #expect(restored.first?.responseModelUsage?.searchUsage == result.artifacts.modelUsage?.searchUsage)
    }

    private func followUp(client: LLMCompleting, key: String, search: WebSearching) async throws -> AIAnalysisFollowUpResult {
        try await AIAnalysisAgent(llm: client, search: search, credentialStore: SearchCredentials(key: key)).answerFollowUp(question: "请交叉核验今天黄金市场的最新消息", report: nil, artifacts: nil, positions: [], llmConfiguration: .default, searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: Set(providers), quality: .basic))
    }
    private func transport(calls: [SearchProviderOption], answer: String = #"{"answer":"不同来源的口径仍需核对。[[cite:source_1]][[cite:source_2]]","limitations":[]}"#, query: String = "gold latest official news", refs: [String] = [], repair: String? = nil) throws -> (DeepSeekResponsesClient, String, URLSession) {
        let key = UUID().uuidString
        let functions = calls.enumerated().map { index, provider in
            ["type": "function_call", "call_id": "call_\(index)", "name": AISearchFunctionCalling.toolName(provider), "arguments": String(decoding: try! JSONSerialization.data(withJSONObject: ["query": query, "position_refs": refs]), as: UTF8.self)]
        }
        func response(_ output: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["status": "completed", "id": UUID().uuidString, "output": output, "usage": ["input_tokens": 100, "output_tokens": 20]])
        }
        var responses = [try response(functions), try response([["type": "message", "role": "assistant", "content": [["type": "output_text", "text": answer]]]])]
        if let repair { responses.append(try response([["type": "message", "role": "assistant", "content": [["type": "output_text", "text": repair]]]])) }
        NativeSearchProtocol.state.register(key, responses: responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeSearchProtocol.self]
        let session = URLSession(configuration: configuration)
        return (DeepSeekResponsesClient(session: session), key, session)
    }
    private func object(_ data: Data) throws -> [String: Any] { try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]) }
}

private struct SearchCredentials: ProviderCredentialStoring {
    let key: String
    func read(kind: ProviderCredentialKind) throws -> String? { kind == .llm ? key : "fictional-search-key" }
    func save(_: String, kind _: ProviderCredentialKind) throws {}
    func delete(kind _: ProviderCredentialKind) throws {}
    func readValidationState(kind _: ProviderCredentialKind) throws -> ProviderCredentialValidationState { .valid }
    func saveValidationState(_: ProviderCredentialValidationState, kind _: ProviderCredentialKind) throws {}
}

private struct FunctionReply: LLMCompleting {
    let calls: [LLMFunctionCall]
    func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String { "{}" }
    func completeJSONResult(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String, webSearchEnabled: Bool, webSearchProgress: LLMWebSearchProgressHandler?) async throws -> LLMCompletionResult { .init(content: "", functionCalls: calls) }
}

private actor ConcurrentSearch: WebSearching {
    let failing: Set<SearchProviderOption>
    let delay: Duration
    private var active = 0
    private var peak = 0
    private var providers: [SearchProviderOption] = []
    init(failing: Set<SearchProviderOption>, delay: Duration = .milliseconds(20)) { self.failing = failing; self.delay = delay }
    func search(query: String, positions: [Position], configuration: SearchConfiguration, apiKey: String) async throws -> [AssetResearchSource] {
        active += 1; peak = max(peak, active); providers.append(configuration.provider)
        defer { active -= 1 }
        try await Task.sleep(for: delay)
        if failing.contains(configuration.provider) { throw URLError(.timedOut) }
        return [
            AssetResearchSource(title: "Gold original", url: "https://example.com/original?utm_source=\(configuration.provider.rawValue)", domain: "example.com", publishedDate: "2026-11-08", snippet: "Shared original excerpt", credibility: .general),
            AssetResearchSource(title: "Gold independent", url: "https://\(configuration.provider == .exa ? "sec.gov" : "reuters.com")/gold", domain: configuration.provider == .exa ? "sec.gov" : "reuters.com", publishedDate: "2026-11-08", snippet: "Independent gold source", credibility: .official)
        ]
    }
    func maximumActive() -> Int { peak }
    func requests() -> [SearchProviderOption] { providers }
}

private final class NativeSearchProtocol: URLProtocol, @unchecked Sendable {
    static let state = State()
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [String: [Data]] = [:]
        private var requests: [String: [Data]] = [:]
        func register(_ key: String, responses: [Data]) { lock.withLock { self.responses[key] = responses } }
        func bodies(_ key: String) -> [Data] { lock.withLock { requests[key] ?? [] } }
        func next(_ key: String, request: URLRequest) -> Data {
            lock.withLock {
                var body = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        body.append(contentsOf: buffer.prefix(count))
                    }
                }
                requests[key, default: []].append(body)
                guard var queue = responses[key], !queue.isEmpty else { return Data(#"{"status":"failed"}"#.utf8) }
                let first = queue.removeFirst(); responses[key] = queue; return first
            }
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst(7))
        let data = Self.state.next(key, request: request)
        let envelope = "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":\(String(decoding: data, as: UTF8.self))}\n\n"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(envelope.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
