import Foundation
import PortfolixCore
import PortfolixMCPKit
import Testing
@testable import Portfolix

@Suite("Technical debt and hardening regressions")
struct TechnicalDebtRegressionTests {
    @Test
    func usSymbolNormalizerPreservesDotShareClassesAndStripsExchangePrefixes() {
        #expect(USSymbolNormalizer.normalize("BRK.B") == "BRK.B")
        #expect(USSymbolNormalizer.normalize("bf.b") == "BF.B")
        #expect(USSymbolNormalizer.normalize("105.AAPL") == "AAPL")
        #expect(USSymbolNormalizer.normalize("106.BRK.B") == "BRK.B")
        #expect(USSymbolNormalizer.normalize("AAPL.US") == "AAPL")
        #expect(USSymbolNormalizer.normalize("US.NVDA") == "NVDA")
        #expect(NativeMarketDataAdapter.eastmoneySECID(symbol: "BRK.B", category: .usStock) == "105.BRK.B")
        #expect(NativeMarketDataAdapter.eastmoneySECID(symbol: "105.AAPL", category: .usStock) == "105.AAPL")
    }

    @Test
    func sharedExchangeRatesMatchDisplayCurrencyRates() {
        for currency in DisplayCurrency.allCases {
            #expect(currency.rateFromCNY == CurrencyExchangeRate.rateFromCNY(for: currency.rawValue))
        }
    }

    @Test
    func positionCostCNYNormalizesMixedCurrenciesForSorting() {
        let cnyStock = Position(
            name: "CNY Asset", symbol: "600519", category: .cnStock, quoteCurrency: .cny,
            quantity: 10, totalCost: 1000, averageCost: 100, latestPrice: 100,
            marketValueCNY: 1000, profitRate: 0, weeklyTrend: [100],
            source: "manual", quoteTime: "now", freshness: .manual
        )
        let usdStock = Position(
            name: "USD Asset", symbol: "AAPL", category: .usStock, quoteCurrency: .usd,
            quantity: 10, totalCost: 200, averageCost: 20, latestPrice: 20,
            marketValueCNY: 200 / DisplayCurrency.usd.rateFromCNY, profitRate: 0, weeklyTrend: [20],
            source: "manual", quoteTime: "now", freshness: .manual
        )
        // Raw numbers: 20 < 100 and 200 < 1000, but in CNY USD 20 (~135.85 CNY) > 100 CNY.
        #expect(usdStock.averageCost < cnyStock.averageCost)
        #expect(usdStock.averageCostCNY > cnyStock.averageCostCNY)
        #expect(usdStock.totalCostCNY > cnyStock.totalCostCNY)
    }

    @Test
    func aiInputRespectsUnknownCostStatusAndPassesSchemaValidation() throws {
        let unknownCostPosition = Position(
            name: "Unreconciled Equity", symbol: "NVDA", category: .usStock, quoteCurrency: .usd,
            quantity: 5, totalCost: 500, averageCost: 100, latestPrice: 120,
            marketValueCNY: 600 / DisplayCurrency.usd.rateFromCNY, profitRate: 20, weeklyTrend: [120],
            source: "manual", quoteTime: "2026-11-22T00:00:00Z", freshness: .manual, costIsKnown: false
        )
        let knownCostPosition = Position(
            name: "Known Equity", symbol: "AAPL", category: .usStock, quoteCurrency: .usd,
            quantity: 10, totalCost: 2000, averageCost: 200, latestPrice: 210,
            marketValueCNY: 2100 / DisplayCurrency.usd.rateFromCNY, profitRate: 5, weeklyTrend: [210],
            source: "manual", quoteTime: "2026-11-22T00:00:00Z", freshness: .manual, costIsKnown: true
        )
        let positions = [unknownCostPosition, knownCostPosition]
        let context = AIAnalysisStoreContext(
            displayCurrency: .cny,
            convertedTotalValue: positions.reduce(0) { $0 + $1.marketValueCNY },
            convertedTotalProfit: 0,
            totalProfitRate: 0,
            riskProfileConfigured: false,
            riskProfileVersion: 1,
            riskLevel: "未配置",
            positionLimit: 30,
            cryptoLimit: 15,
            foreignCurrencyLimit: 50,
            liquidityMinimum: 10,
            riskConstraintEvaluation: RiskConstraintEvaluation(
                largestPositionName: "Known Equity",
                largestPositionPercent: 77.8,
                cryptoAllocationPercent: 0,
                nonCNYAllocationPercent: 100,
                cashAllocationPercent: 0,
                positionLimit: 30,
                cryptoLimit: 15,
                foreignCurrencyLimit: 50,
                liquidityMinimum: 10
            ),
            positionPerformance: [:]
        )

        let input = AIAnalysisAgent.makeInput(
            positions: positions,
            context: context,
            configuration: .default,
            trigger: .manual,
            generatedAt: Date(timeIntervalSince1970: 1_795_300_000),
            analysisMode: "basic_standard"
        )
        try AIAnalysisSchemaValidator.validate(input: input)

        let unknownContext = try #require(input.metrics.positions.first { $0.symbol == "NVDA" })
        #expect(unknownContext.costStatus == "unknown")
        #expect(unknownContext.averageCost == nil)
        #expect(unknownContext.totalCostQuote == nil)
        #expect(unknownContext.unrealizedProfitQuote == nil)
        #expect(unknownContext.unrealizedProfitRatePct == nil)

        let knownContext = try #require(input.metrics.positions.first { $0.symbol == "AAPL" })
        #expect(knownContext.costStatus == "known")
        #expect(knownContext.averageCost == "200")
        #expect(knownContext.totalCostQuote == "2000")
        #expect(knownContext.unrealizedProfitQuote == "100")

        #expect(input.snapshot.holdingReturnText == "—")
        #expect(input.snapshot.holdingReturnRateText == "—")
    }

    @Test
    func sanitizerPreservesOrdinaryEnglishWordsWithSharedSubstrings() {
        let english = "Unparalleled growth while harnessing schematic insights and examples."
        #expect(AIUserFacingTextSanitizer.sanitize(english, language: .english) == english)

        let internalTerms = "Fetched via Parallel, deepseek_search, bocha_search, parallel_search, and Harness schema."
        let sanitized = AIUserFacingTextSanitizer.sanitize(internalTerms, language: .english)
        #expect(!sanitized.contains("Parallel"))
        #expect(!sanitized.contains("deepseek_search"))
        #expect(!sanitized.contains("bocha_search"))
        #expect(!sanitized.contains("parallel_search"))
        #expect(!sanitized.contains("Harness"))
        #expect(!sanitized.contains("schema"))
    }

    @Test
    func followUpParserAllowsQuotedOpeningProseWhileRejectingRawJSONFragments() throws {
        let prose = "\"黄金\"近期波动较大，建议关注仓位控制。"
        let parsed = try AIAnalysisAgent.validatedFollowUpPayload(prose)
        #expect(parsed.answer == prose)

        #expect(AIFollowUpResponseParser.decode("\"hello\"") == nil)
        #expect(AIFollowUpResponseParser.decode("\"answer\": \"leaked\"") == nil)
    }

    @Test
    func tavilySourcesRejectLoopbackAndPrivateURLs() {
        let response = TavilySearchResponse(
            query: "AAPL",
            results: [
                TavilySearchResult(title: "Local", url: "https://127.0.0.1/secret", content: "AAPL local endpoint", publishedDate: nil),
                TavilySearchResult(title: "Private", url: "https://10.0.0.1/internal", content: "AAPL private endpoint", publishedDate: nil),
                TavilySearchResult(title: "Reuters AAPL", url: "https://www.reuters.com/markets/aapl", content: "AAPL quarterly earnings update.", publishedDate: nil),
            ]
        )
        let sources = TavilyClient.sources(from: response, positions: [])
        #expect(sources.count == 1)
        #expect(sources.first?.url == "https://www.reuters.com/markets/aapl")
    }

    @Test @MainActor
    func investmentCloudNegativeCompactLabelPlacesMinusBeforeCurrencySymbol() {
        let position = Position(
            name: "Loss Asset", symbol: "TEST", category: .cnStock, quoteCurrency: .cny,
            quantity: 100, totalCost: 100_000, averageCost: 1000, latestPrice: 875,
            marketValueCNY: 87_500, profitRate: -12.5, weeklyTrend: [1000, 875],
            source: "manual", quoteTime: "now", freshness: .manual
        )
        let item = InvestmentCloudItem(position: position, dailyProfitCNY: -12_500)
        let treemap = InvestmentCloudTreemap(items: [item], currency: .cny, language: .english)
        // Narrow rect forces compact notation.
        let label = treemap.amountLabelText(item, rect: CGRect(x: 0, y: 0, width: 64, height: 60))
        #expect(label.hasPrefix("-¥"))
        #expect(!label.contains("¥-"))
    }

    @Test
    func reversedReconciliationsRestoreHistoryCompleteInMCPAndAITools() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReversedReconcile-\(UUID())/test.sqlite3")
        let repo = try PositionRepository(databaseURL: dbURL)
        let now = Date(timeIntervalSince1970: 1_795_300_000)
        let position = Position(
            name: "Sample Stock", symbol: "600519", category: .cnStock, quoteCurrency: .cny,
            quantity: 10, totalCost: 1000, averageCost: 100, latestPrice: 110,
            marketValueCNY: 1100, profitRate: 10, weeklyTrend: [100, 110],
            source: "manual", quoteTime: "now", fetchedAt: ISO8601DateFormatter().string(from: now), freshness: .manual
        )
        try repo.insert(position)
        let record = try repo.reconcilePosition(
            expected: position, quantity: 12, totalCost: nil, reason: "check", now: now
        )
        try repo.reverseReconciliation(id: record.id, now: now.addingTimeInterval(60))
        try repo.setAppSetting(key: MCPAccess.settingKey, value: "true")

        let server = PortfolioMCPServer(databaseURL: dbURL)
        func rpc(_ payload: [String: Any]) throws -> [String: Any] {
            let requestData = try JSONSerialization.data(withJSONObject: payload)
            let responseData = try #require(server.respond(to: requestData))
            return try #require(JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        }
        _ = try rpc([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "Test", "version": "1"]],
        ])
        let initialized = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        _ = server.respond(to: initialized)

        let summaryResponse = try rpc([
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": "get_portfolio_summary", "arguments": [:]],
        ])
        let result = try #require(summaryResponse["result"] as? [String: Any])
        let structured = try #require(result["structuredContent"] as? [String: Any])
        #expect(structured["history_complete"] as? String == "no_known_reconciliation_gaps")

        let aiSnapshot = AIPortfolioToolSnapshot(
            positions: try repo.fetchPositions(),
            reconciliations: try repo.fetchReconciliations(),
            asOf: now
        )
        let aiRequest = try AIPortfolioToolRequest(
            call: LLMFunctionCall(callID: "call_1", name: "get_portfolio_summary", arguments: "{}")
        )
        let aiSummaryText = AIPortfolioDataToolExecutor.execute(aiRequest, snapshot: aiSnapshot)
        let aiSummary = try #require(JSONSerialization.jsonObject(with: Data(aiSummaryText.utf8)) as? [String: Any])
        #expect(aiSummary["history_complete"] as? Bool == true)
    }

    @Test
    func backgroundUpdaterExitsCleanlyWithoutCrashingWhenDatabaseIsMissing() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helper = root.appendingPathComponent(".build/debug/PortfolixPriceUpdater")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return }

        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingUpdaterDB-\(UUID())/nonexistent.sqlite3").path
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--once"]
        process.environment = ["PORTFOLIX_DATABASE_PATH": missingPath, "PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == 0)
    }
}
