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
    func harnessResearchesOnlyPublicAssetIdentityAndBuildsVerifiedExposure() async throws {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let sourceURL = "https://fund.example.com/reports/123456"
        let llm = InvestmentProfileMockLLM(responses: [
            """
            {
              "tool_calls":[{
                "id":"web_search_1",
                "query":"某某精选混合 123456 基金季报 投资范围 地区配置",
                "position_refs":["position_\(position.id.uuidString)"]
              }],
              "status":"continue",
              "limitations":[]
            }
            """,
            """
            {
              "profiles":[{
                "position_ref":"position_\(position.id.uuidString)",
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
            """,
        ])
        let search = InvestmentProfileMockSearch(sourceURL: sourceURL)
        let result = await InvestmentProfileHarness(llm: llm, search: search).enrich(
            positions: [position],
            cachedExposures: [],
            llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, provider: .tavily, quality: .basic),
            llmKey: "llm-key",
            searchKey: "search-key"
        )

        let exposure = try #require(result.exposures.first)
        #expect(result.searchedAssetCount == 1)
        #expect((exposure.regionWeights[InvestmentProfileRegion.unitedStates.rawValue] ?? 0) == 0.8)
        #expect(exposure.evidence.first?.url == sourceURL)
        let query = try #require(await search.queries().first)
        #expect(query.contains("123456"))
        #expect(!query.contains("某某精选混合"))
        #expect(!query.localizedCaseInsensitiveContains("持仓"))
        #expect(!query.localizedCaseInsensitiveContains("成本"))
        #expect(!query.localizedCaseInsensitiveContains("市值"))
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
    func invalidLLMCalibrationFallsBackToDeterministicLookThroughProfile() async throws {
        let position = makePosition(
            name: "广发纳斯达克100ETF联接(QDII)A",
            symbol: "270042",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let context = makeContext(positions: [position])
        let localExposures = InvestmentProfileEngine.localExposureProfiles(positions: [position])
        let localScores = InvestmentProfileEngine.score(
            positions: [position],
            exposures: localExposures,
            context: context
        ).scores
        let agent = AIAnalysisAgent(
            llm: InvestmentProfileMockLLM(responses: ["not-json"]),
            search: InvestmentProfileMockSearch(sourceURL: "https://fund.example.com/unused"),
            credentialStore: InvestmentProfileMockCredentialStore(keys: [.llm: "llm-key"])
        )

        let profile = try await agent.generateInvestmentProfile(
            positions: [position],
            localScores: localScores,
            storeContext: context,
            llmConfiguration: .default,
            inputFingerprint: "look-through-test"
        )

        #expect(profile.dimensions == localScores)
        #expect(profile.assetExposures?.count == 1)
        #expect((profile.exposureCoverage ?? 0) > 0.8)
        #expect(profile.summary.contains("AI 解释暂时不可用"))
    }

    @Test
    func connectedAgentCompletesPlanningSearchExtractionAndCalibration() async throws {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let positionRef = InvestmentProfileEngine.positionRef(for: position)
        let sourceURL = "https://fund.example.com/reports/123456"
        let context = makeContext(positions: [position])
        let localScores = InvestmentProfileEngine.score(
            positions: [position],
            exposures: InvestmentProfileEngine.localExposureProfiles(positions: [position]),
            context: context
        ).scores
        let llm = InvestmentProfileMockLLM(responses: [
            toolPlanJSON(
                positionRef: positionRef,
                query: "某某精选混合 123456 基金季报 投资范围 地区配置"
            ),
            exposureJSON(positionRef: positionRef, sourceURL: sourceURL),
            """
            {
              "dimensions":[
                {"id":"growth","score":78,"reason":"底层权益与科技暴露提升成长属性"},
                {"id":"global","score":82,"reason":"底层资产主要分布在美国及其他海外市场"},
                {"id":"diversification","score":45,"reason":"单一基金仍存在管理人与基准集中"},
                {"id":"defense","score":40,"reason":"权益仓位较高，防御属性有限"},
                {"id":"cashflow","score":30,"reason":"组合主要依赖资本增值"},
                {"id":"activity","score":72,"reason":"成长与科技暴露带来较高波动活跃度"}
              ],
              "summary":"穿透画像已结合公开基金资料校准",
              "confidence":"high"
            }
            """,
        ])
        let search = InvestmentProfileMockSearch(sourceURL: sourceURL)
        let agent = AIAnalysisAgent(
            llm: llm,
            search: search,
            credentialStore: InvestmentProfileMockCredentialStore(keys: [
                .llm: "llm-key",
                .tavily: "search-key",
            ])
        )

        let profile = try await agent.generateInvestmentProfile(
            positions: [position],
            localScores: localScores,
            storeContext: context,
            llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, provider: .tavily, quality: .basic),
            inputFingerprint: "connected-end-to-end"
        )

        #expect(profile.summary == "穿透画像已结合公开基金资料校准")
        #expect(profile.dimensions.count == 6)
        #expect(profile.assetExposures?.first?.evidence.first?.url == sourceURL)
        #expect(profile.evidenceSourceCount == 1)
        #expect((profile.exposureCoverage ?? 0) > 0.8)
        #expect(await llm.requestCount() == 3)
        #expect(await search.queries().count == 1)
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
            searchKey: nil
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
            searchKey: "search-key"
        )

        #expect(result.exposures.first?.evidence.first?.url == sourceURL)
        #expect(result.searchedAssetCount == 0)
        #expect(await llm.requestCount() == 0)
        #expect(await search.queries().isEmpty)
    }

    @Test
    func emptySearchResultsDegradeToLocalExposureWithoutFailure() async {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let ref = InvestmentProfileEngine.positionRef(for: position)
        let llm = InvestmentProfileMockLLM(responses: [
            toolPlanJSON(positionRef: ref, query: "某某精选混合 123456 基金季报 地区配置"),
            toolPlanJSON(positionRef: ref, query: "某某精选混合 123456 业绩比较基准 行业配置"),
        ])
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
            searchKey: "search-key"
        )

        #expect(result.searchedAssetCount == 0)
        #expect(result.exposures.first?.evidence.first?.source == "portfolix_native_resolver")
        #expect(!result.limitations.isEmpty)
        #expect(await llm.requestCount() == 2)
        #expect(await search.queries().count == 2)
    }

    @Test
    func malformedExtractionTriggersASecondResearchRound() async throws {
        let position = makePosition(
            name: "某某精选混合",
            symbol: "123456",
            category: .fund,
            quoteCurrency: .cny,
            marketValue: 100_000
        )
        let ref = InvestmentProfileEngine.positionRef(for: position)
        let sourceURL = "https://fund.example.com/reports/123456"
        let llm = InvestmentProfileMockLLM(responses: [
            toolPlanJSON(positionRef: ref, query: "某某精选混合 123456 基金季报 地区配置"),
            "not-json",
            toolPlanJSON(positionRef: ref, query: "某某精选混合 123456 业绩比较基准 行业配置"),
            exposureJSON(positionRef: ref, sourceURL: sourceURL),
        ])
        let search = InvestmentProfileMockSearch(sourceURL: sourceURL)
        let result = await InvestmentProfileHarness(llm: llm, search: search).enrich(
            positions: [position],
            cachedExposures: [],
            llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, provider: .tavily, quality: .basic),
            llmKey: "llm-key",
            searchKey: "search-key"
        )

        #expect(result.searchedAssetCount == 1)
        #expect(result.exposures.first?.evidence.first?.url == sourceURL)
        #expect(result.limitations.contains("公开资料未能转换为可信的结构化底层暴露"))
        #expect(await llm.requestCount() == 4)
        #expect(await search.queries().count == 2)
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
    private var capturedRequestCount = 0

    init(responses: [String]) {
        self.responses = responses
    }

    func completeJSON(
        systemPrompt _: String,
        userPrompt _: String,
        configuration _: AIProviderConfiguration,
        apiKey _: String
    ) async throws -> String {
        capturedRequestCount += 1
        guard !responses.isEmpty else { throw LLMClientError.invalidResponse }
        return responses.removeFirst()
    }

    func requestCount() -> Int { capturedRequestCount }
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
