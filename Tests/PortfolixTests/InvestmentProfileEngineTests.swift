import Foundation
import Testing
@testable import Portfolix

@Suite("Investment profile look-through engine")
struct InvestmentProfileEngineTests {
    @Test
    func cnyNasdaqQDIIContributesUnderlyingUSExposure() {
        let position = makePosition(
            name: "广发纳斯达克100ETF联接(QDII)A",
            symbol: "270042",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let exposures = InvestmentProfileEngine.localExposureProfiles(positions: [position])
        let result = InvestmentProfileEngine.score(
            positions: [position],
            exposures: exposures,
            context: makeContext(positions: [position])
        )

        #expect((result.snapshot.regionPercentages[InvestmentProfileRegion.unitedStates.rawValue] ?? 0) > 90)
        #expect((result.scores.first { $0.id == "global" }?.score ?? 0) > 65)
        #expect(result.scores.first { $0.id == "global" }?.reason.contains("不以计价币种") == true)
    }

    @Test
    func bShareForeignQuoteCurrencyDoesNotBecomeOverseasEconomicExposure() {
        let position = makePosition(
            name: "上海市场B股",
            symbol: "900901",
            category: .bStock,
            quoteCurrency: .usd,
            marketValue: 100_000
        )
        let exposures = InvestmentProfileEngine.localExposureProfiles(positions: [position])
        let result = InvestmentProfileEngine.score(
            positions: [position],
            exposures: exposures,
            context: makeContext(positions: [position])
        )

        #expect((result.snapshot.regionPercentages[InvestmentProfileRegion.china.rawValue] ?? 0) == 100)
        #expect((result.scores.first { $0.id == "global" }?.score ?? 100) < 15)
    }

    @Test
    func bondFundIsMoreDefensiveThanTechnologyQDII() {
        let bond = makePosition(
            name: "中短债债券A",
            symbol: "012345",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let technology = makePosition(
            name: "全球半导体芯片ETF联接(QDII)",
            symbol: "067890",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let bondScore = score("defense", positions: [bond])
        let technologyScore = score("defense", positions: [technology])

        #expect(bondScore > technologyScore + 30)
    }

    @Test
    func repeatedIndexFundsDoNotCreateFalseDiversification() {
        let repeated = (0..<10).map { index in
            makePosition(
                name: "纳斯达克100ETF联接(QDII)\(index)",
                symbol: "NQ\(index)",
                category: .fund,
                quoteCurrency: .cny,
                marketValue: 10_000
            )
        }
        let distinct = (0..<10).map { index in
            makePosition(
                name: "US Stock \(index)",
                symbol: "US\(index)",
                category: .usStock,
                quoteCurrency: .usd,
                marketValue: 10_000
            )
        }

        #expect(score("diversification", positions: distinct) > score("diversification", positions: repeated) + 10)
    }

    @Test
    func harnessUsesConfiguredExternalSearchWithoutBuiltInModelSearch() async throws {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let positionRef = InvestmentProfileEngine.positionRef(for: position)
        let sourceURL = "https://fund.example.com/reports/123456"
        let llm = InvestmentProfileMockLLM(
            responses: [
                toolPlanJSON(positionRef: positionRef, query: "123456 基金季报 投资范围 地区配置"),
                exposureJSON(positionRef: positionRef, sourceURL: sourceURL),
            ]
        )
        let search = InvestmentProfileMockSearch(sourceURL: sourceURL)
        let result = await InvestmentProfileHarness(llm: llm, search: search).enrich(
            positions: [position],
            cachedExposures: [],
            llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, provider: .tavily, quality: .basic),
            llmKey: "llm-key",
            searchKeys: [.tavily: "search-key"]
        )

        let exposure = try #require(result.exposures.first)
        #expect(result.searchedAssetCount == 1)
        #expect((exposure.regionWeights[InvestmentProfileRegion.unitedStates.rawValue] ?? 0) > 0)
        #expect(exposure.evidence.contains { $0.url == sourceURL })
        let queries = await search.queries()
        #expect(queries.count == 1)
        #expect(queries.first?.contains("123456") == true)
        #expect(await llm.webSearchEnabledValues().isEmpty)
        #expect(await llm.userPrompts().count == 2)
    }

    @Test
    func exposureValidationRejectsUnreturnedSourceURL() throws {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let candidate = InvestmentProfileExposureCandidate(
            positionRef: InvestmentProfileEngine.positionRef(for: position),
            assetClassWeights: ["equity": 1],
            regionWeights: ["US": 1],
            sectorWeights: [:],
            growthStyleScore: 0.7,
            incomeScore: 0.2,
            volatilityScore: 0.6,
            benchmarkKey: "index:test",
            confidence: 0.8,
            rationale: "公开资料显示主要投资美国股票",
            sourceURLs: ["https://untrusted.example/invented"]
        )
        let sources = [
            AssetResearchSource(
                title: "Official report",
                url: "https://fund.example.com/123456",
                domain: "fund.example.com",
                publishedDate: "2026-06-30",
                snippet: "Public fund allocation report",
                credibility: .official
            ),
        ]

        #expect(throws: AIAnalysisAgentError.self) {
            try InvestmentProfileHarness.validatedExposure(candidate, position: position, sources: sources)
        }
    }

    @Test
    func disabledSearchSkipsPlanningAndToolExecution() async {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let llm = InvestmentProfileMockLLM(responses: [])
        let search = InvestmentProfileMockSearch(sourceURL: "https://fund.example.com/unused")
        let result = await InvestmentProfileHarness(llm: llm, search: search).enrich(
            positions: [position],
            cachedExposures: [],
            llmConfiguration: .default,
            searchConfiguration: .default,
            llmKey: "llm-key",
            searchKeys: [:]
        )

        #expect(result.searchedAssetCount == 0)
        #expect(result.exposures.first?.evidence.first?.source == "portfolix_native_resolver")
        #expect(await llm.requestCount() == 0)
        #expect(await search.queries().isEmpty)
    }

    @Test
    func freshVerifiedCacheSkipsRepeatedResearch() async throws {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let sourceURL = "https://fund.example.com/reports/123456"
        let source = AssetResearchSource(
            title: "Fund quarterly report",
            url: sourceURL,
            domain: "fund.example.com",
            publishedDate: "2026-06-30",
            snippet: "The fund primarily invests in overseas technology equities.",
            credibility: .official
        )
        let candidate = InvestmentProfileExposureCandidate(
            positionRef: InvestmentProfileEngine.positionRef(for: position),
            assetClassWeights: ["equity": 0.92, "cash": 0.08],
            regionWeights: ["US": 0.8, "GLOBAL_OTHER": 0.2],
            sectorWeights: ["technology": 0.55, "other": 0.45],
            growthStyleScore: 0.82,
            incomeScore: 0.18,
            volatilityScore: 0.72,
            benchmarkKey: "index:global_technology",
            confidence: 0.9,
            rationale: "基金公开资料显示其主要投资海外科技权益资产",
            sourceURLs: [sourceURL]
        )
        let cached = try InvestmentProfileHarness.validatedExposure(
            candidate,
            position: position,
            sources: [source],
            now: Date()
        )
        let llm = InvestmentProfileMockLLM(responses: [])
        let search = InvestmentProfileMockSearch(sourceURL: sourceURL)
        let result = await InvestmentProfileHarness(llm: llm, search: search).enrich(
            positions: [position],
            cachedExposures: [cached],
            llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, provider: .tavily, quality: .basic),
            llmKey: "llm-key",
            searchKeys: [.tavily: "search-key"]
        )

        #expect(result.exposures.first?.evidence.first?.url == sourceURL)
        #expect(result.searchedAssetCount == 0)
        #expect(await llm.requestCount() == 0)
        #expect(await search.queries().isEmpty)
    }

    @Test(.disabled("DeepSeek removed the built-in web_search tool; retain for the future external search adapter."))
    func builtInSearchWithoutCitationsKeepsLocalExposure() async throws {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let ref = InvestmentProfileEngine.positionRef(for: position)
        let llm = InvestmentProfileMockLLM(
            responses: [],
            completionResults: [
                LLMCompletionResult(
                    content: exposureJSON(
                        positionRef: ref,
                        sourceURL: "https://fund.example.com/unused"
                    ),
                    webSearchCallCount: 1,
                    webSearchQueries: ["123456 基金季报 地区配置"]
                ),
            ]
        )
        let search = InvestmentProfileMockSearch(
            sourceURL: "https://fund.example.com/unused",
            returnsResults: false
        )
        let result = await InvestmentProfileHarness(llm: llm, search: search).enrich(
            positions: [position],
            cachedExposures: [],
            llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, provider: .tavily, quality: .basic),
            llmKey: "llm-key",
            searchKeys: [.tavily: "search-key"]
        )

        let exposure = try #require(result.exposures.first)
        #expect(result.searchedAssetCount == 0)
        #expect(exposure.evidence.first?.source == "portfolix_native_resolver")
        #expect(result.limitations.contains {
            $0.contains("未获得可验证的公开资料")
        })
        #expect(await llm.requestCount() == 1)
        #expect(await llm.webSearchEnabledValues() == [true])
        #expect(await search.queries().isEmpty)
    }

    @Test(.disabled("DeepSeek removed the built-in web_search tool; retain for the future external search adapter."))
    func builtInSearchRejectsPrivateAttributedSourceURLs() async {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let ref = InvestmentProfileEngine.positionRef(for: position)
        let llm = InvestmentProfileMockLLM(
            responses: [],
            completionResults: [
                LLMCompletionResult(
                    content: exposureJSON(
                        positionRef: ref,
                        sourceURL: "https://127.0.0.1/private"
                    ),
                    webSearchCallCount: 1,
                    webSearchQueries: ["123456 基金季报 地区配置"]
                ),
            ]
        )
        let result = await InvestmentProfileHarness(
            llm: llm,
            search: InvestmentProfileMockSearch(sourceURL: "https://fund.example.com/unused")
        ).enrich(
            positions: [position],
            cachedExposures: [],
            llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, provider: .tavily, quality: .basic),
            llmKey: "llm-key",
            searchKeys: [:]
        )

        #expect(result.searchedAssetCount == 0)
        #expect(result.exposures.first?.evidence.first?.source == "portfolix_native_resolver")
        #expect(!result.limitations.isEmpty)
    }

    @Test(.disabled("DeepSeek removed the built-in web_search tool; retain for the future external search adapter."))
    func malformedBuiltInSearchResponseFallsBackWithoutExternalSearch() async throws {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let sourceURL = "https://fund.example.com/reports/123456"
        let llm = InvestmentProfileMockLLM(
            responses: [],
            completionResults: [
                LLMCompletionResult(
                    content: "not-json",
                    webSearchCallCount: 1,
                    webSearchQueries: ["123456 基金季报 地区配置"],
                    citations: [LLMWebCitation(title: "Fund quarterly report", url: sourceURL)]
                ),
            ]
        )
        let search = InvestmentProfileMockSearch(sourceURL: sourceURL)
        let result = await InvestmentProfileHarness(llm: llm, search: search).enrich(
            positions: [position],
            cachedExposures: [],
            llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, provider: .tavily, quality: .basic),
            llmKey: "llm-key",
            searchKeys: [.tavily: "search-key"]
        )

        #expect(result.searchedAssetCount == 0)
        #expect(result.exposures.first?.evidence.first?.source == "portfolix_native_resolver")
        #expect(result.limitations.contains("公开资料未能转换为可信的结构化底层暴露"))
        #expect(await llm.requestCount() == 1)
        #expect(await llm.webSearchEnabledValues() == [true])
        #expect(await search.queries().isEmpty)
    }

    @Test(.disabled("DeepSeek removed the built-in web_search tool; retain for the future external search adapter."))
    func liveDeepSeekBuiltInSearchEnrichesQDIIExposureUsingEnvironmentCredential() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PORTFOLIX_RUN_LIVE_DEEPSEEK_PROFILE_TEST"] == "1" else { return }
        let apiKey = try #require(environment["PORTFOLIX_DEEPSEEK_API_KEY"])
        let model = environment["PORTFOLIX_DEEPSEEK_MODEL"] ?? LLMProviderOption.deepSeek.defaultModel
        let position = makePosition(
            name: "广发纳斯达克100ETF联接(QDII)A",
            symbol: "270042",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let configuration = AIProviderConfiguration(
            provider: LLMProviderOption.deepSeek.rawValue,
            baseURL: LLMProviderOption.deepSeek.defaultBaseURL,
            model: model,
            isEnabled: true,
            requestTimeout: 180,
            maxOutputTokens: LLMOutputTokenPolicy.standard
        )
        let result = await InvestmentProfileHarness(
            llm: DeepSeekResponsesClient.shared,
            search: InvestmentProfileMockSearch(sourceURL: "https://example.com/unused")
        ).enrich(
            positions: [position],
            cachedExposures: [],
            llmConfiguration: configuration,
            searchConfiguration: SearchConfiguration(isEnabled: true, provider: .tavily, quality: .basic),
            llmKey: apiKey,
            searchKeys: [:]
        )

        let exposure = try #require(result.exposures.first)
        #expect(result.searchedAssetCount == 1)
        #expect(exposure.evidence.contains { $0.source != "portfolix_native_resolver" })
        #expect((exposure.regionWeights[InvestmentProfileRegion.unitedStates.rawValue] ?? 0) > 0.5)
    }

    private func toolPlanJSON(positionRef: String, query: String) -> String {
        """
        {
          "tool_calls":[{
            "id":"web_search_1",
            "query":"\(query)",
            "position_refs":["\(positionRef)"]
          }],
          "status":"continue",
          "limitations":[]
        }
        """
    }

    private func exposureJSON(positionRef: String, sourceURL: String) -> String {
        """
        {
          "profiles":[{
            "position_ref":"\(positionRef)",
            "asset_class_weights":{"equity":0.92,"cash":0.08},
            "region_weights":{"US":0.8,"GLOBAL_OTHER":0.15,"UNKNOWN":0.05},
            "sector_weights":{"technology":0.55,"other":0.45},
            "growth_style_score":0.82,
            "income_score":0.18,
            "volatility_score":0.72,
            "benchmark_key":"index:global_technology",
            "confidence":0.9,
            "rationale":"基金公开资料显示其主要投资海外科技权益资产",
            "source_urls":["\(sourceURL)"]
          }]
        }
        """
    }

    private func score(_ id: String, positions: [Position]) -> Double {
        let exposures = InvestmentProfileEngine.localExposureProfiles(positions: positions)
        return InvestmentProfileEngine.score(
            positions: positions,
            exposures: exposures,
            context: makeContext(positions: positions)
        ).scores.first { $0.id == id }?.score ?? 0
    }

    private func makePosition(
        name: String,
        symbol: String,
        category: AssetCategory,
        quoteCurrency: DisplayCurrency,
        marketValue: Decimal
    ) -> Position {
        Position(
            name: name,
            symbol: symbol,
            category: category,
            quoteCurrency: quoteCurrency,
            quantity: marketValue,
            averageCost: 1,
            latestPrice: 1,
            marketValueCNY: marketValue,
            profitRate: 0,
            weeklyTrend: Array(repeating: 1, count: 7),
            source: "Test",
            quoteTime: "2026-07-18",
            freshness: .updated
        )
    }

    private func makeContext(positions: [Position]) -> AIAnalysisStoreContext {
        let total = max(positions.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue }, 0.001)
        let largest = positions.max { $0.marketValueCNY < $1.marketValueCNY }
        let crypto = positions.filter { $0.category == .crypto }.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue } / total * 100
        let nonCNY = positions.filter { $0.quoteCurrency != .cny }.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue } / total * 100
        let cash = positions.filter { $0.category == .cash }.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue } / total * 100
        let evaluation = RiskConstraintEvaluation(
            largestPositionName: largest?.name,
            largestPositionPercent: (largest?.marketValueCNY.doubleValue ?? 0) / total * 100,
            cryptoAllocationPercent: crypto,
            nonCNYAllocationPercent: nonCNY,
            cashAllocationPercent: cash,
            positionLimit: 30,
            cryptoLimit: 15,
            foreignCurrencyLimit: 50,
            liquidityMinimum: 10
        )
        return AIAnalysisStoreContext(
            displayCurrency: .cny,
            convertedTotalValue: Decimal(total),
            convertedTotalProfit: 0,
            totalProfitRate: 0,
            riskProfileConfigured: true,
            riskProfileVersion: 1,
            riskLevel: "balanced",
            positionLimit: 30,
            cryptoLimit: 15,
            foreignCurrencyLimit: 50,
            liquidityMinimum: 10,
            riskConstraintEvaluation: evaluation
        )
    }
}

private actor InvestmentProfileMockLLM: LLMCompleting {
    private var responses: [String]
    private var completionResults: [LLMCompletionResult]
    private var capturedRequestCount = 0
    private var capturedUserPrompts: [String] = []
    private var capturedWebSearchEnabled: [Bool] = []

    init(responses: [String], completionResults: [LLMCompletionResult] = []) {
        self.responses = responses
        self.completionResults = completionResults
    }

    func completeJSON(
        systemPrompt _: String,
        userPrompt: String,
        configuration _: AIProviderConfiguration,
        apiKey _: String
    ) async throws -> String {
        capturedRequestCount += 1
        capturedUserPrompts.append(userPrompt)
        guard !responses.isEmpty else { throw LLMClientError.invalidResponse }
        return responses.removeFirst()
    }

    func completeJSONResult(
        systemPrompt _: String,
        userPrompt: String,
        configuration _: AIProviderConfiguration,
        apiKey _: String,
        webSearchEnabled: Bool,
        webSearchProgress _: LLMWebSearchProgressHandler?
    ) async throws -> LLMCompletionResult {
        capturedRequestCount += 1
        capturedUserPrompts.append(userPrompt)
        capturedWebSearchEnabled.append(webSearchEnabled)
        guard !completionResults.isEmpty else { throw LLMClientError.invalidResponse }
        return completionResults.removeFirst()
    }

    func requestCount() -> Int { capturedRequestCount }
    func userPrompts() -> [String] { capturedUserPrompts }
    func webSearchEnabledValues() -> [Bool] { capturedWebSearchEnabled }
}

private actor InvestmentProfileMockSearch: WebSearching {
    private let sourceURL: String
    private let returnsResults: Bool
    private var capturedQueries: [String] = []

    init(sourceURL: String, returnsResults: Bool = true) {
        self.sourceURL = sourceURL
        self.returnsResults = returnsResults
    }

    func search(
        query: String,
        positions _: [Position],
        configuration _: SearchConfiguration,
        apiKey _: String
    ) async throws -> [AssetResearchSource] {
        capturedQueries.append(query)
        guard returnsResults else { return [] }
        return [
            AssetResearchSource(
                title: "Fund quarterly report",
                url: sourceURL,
                domain: "fund.example.com",
                publishedDate: "2026-06-30",
                snippet: "The fund primarily invests in overseas technology equities.",
                credibility: .official
            ),
        ]
    }

    func queries() -> [String] { capturedQueries }
}

private final class InvestmentProfileMockCredentialStore: ProviderCredentialStoring, @unchecked Sendable {
    private var keys: [ProviderCredentialKind: String]

    init(keys: [ProviderCredentialKind: String]) {
        self.keys = keys
    }

    func read(kind: ProviderCredentialKind) throws -> String? { keys[kind] }
    func save(_ value: String, kind: ProviderCredentialKind) throws { keys[kind] = value }
    func delete(kind: ProviderCredentialKind) throws { keys.removeValue(forKey: kind) }
    func readValidationState(kind _: ProviderCredentialKind) throws -> ProviderCredentialValidationState { .unknown }
    func saveValidationState(_: ProviderCredentialValidationState, kind _: ProviderCredentialKind) throws {}
}
