import CSQLite
import Foundation
import Testing
@testable import Portfolix

@Suite("Demo mode & first-run experience")
@MainActor
struct DemoModeTests {
    private func databaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Portfolix.DemoModeTests.\(UUID())/portfolio.sqlite")
    }

    private func realHolding(symbol: String = "MSFT") -> Position {
        Position(
            name: "Microsoft",
            symbol: symbol,
            category: .usStock,
            quoteCurrency: .usd,
            quantity: 10,
            averageCost: 400,
            latestPrice: 420,
            marketValueCNY: 4_200 / DisplayCurrency.usd.rateFromCNY,
            profitRate: 5,
            weeklyTrend: [410, 415, 420],
            source: "手工价格",
            quoteTime: "2026-11-28",
            freshness: .manual
        )
    }

    @Test
    func demoDatasetIsAroundOneMillionCoversAllClassesAndPassesAllGuardrails() throws {
        let now = Date(timeIntervalSince1970: 1_795_867_200) // 2026-11-28
        let dataset = DemoPortfolio.build(language: .chinese, now: now)

        #expect(dataset.positions.count == 8)
        #expect(dataset.positions.allSatisfy { !$0.name.contains("示例") && !$0.name.contains("Sample") })
        #expect(Set(dataset.positions.map(\.category.assetClass)) == [.stock, .fund, .crypto, .cash])
        #expect(Set(dataset.positions.map(\.quoteCurrency)) == [.cny, .usd, .hkd, .usdt])
        #expect(dataset.snapshotHistory.count == 30)
        #expect(dataset.dailyProfitHistory.count == 29)
        #expect(dataset.dailyProfitHistory.contains { $0.amountCNY > 0 })
        #expect(dataset.dailyProfitHistory.contains { $0.amountCNY < 0 })

        let totalValue = dataset.positions.reduce(Decimal.zero) { $0 + $1.marketValueCNY }
        #expect(totalValue >= 950_000 && totalValue <= 1_150_000)

        let riskData = PerformanceRiskChartData(
            snapshots: dataset.snapshotHistory,
            dailyProfit: dataset.dailyProfitHistory,
            range: .month,
            calendar: .current,
            now: now
        )
        #expect(riskData.summary.maxDrawdownCNY < 0)
        #expect(riskData.summary.annualizedVolatility != nil)
        #expect(riskData.summary.worstDayCNY != nil)

        let repo = try PositionRepository(databaseURL: databaseURL())
        let store = PortfolioStore(
            positionRepository: repo,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )
        let evaluation = store.riskConstraintEvaluation
        #expect(evaluation.breachCount == 0)
        #expect(evaluation.approachingCount == 0)
        #expect(evaluation.normalCount == 6)
        #expect(evaluation.passedCount == 6)
    }

    @Test
    func freshInstallEnablesDemoModeWithoutWritingDemoRowsToSQLite() throws {
        let url = databaseURL()
        let repo = try PositionRepository(databaseURL: url)
        let store = PortfolioStore(
            positionRepository: repo,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )

        #expect(store.isDemoMode)
        #expect(store.positions.count == 8)
        #expect(store.snapshotHistory.count == 30)
        #expect(store.dailyProfitHistory.count == 29)
        #expect(!store.investmentCloudDailyProfitItems(asOf: .now).isEmpty)

        // Real SQLite must remain 100% clean and empty.
        #expect(try repo.fetchPositions().isEmpty)
        #expect(try repo.fetchPortfolioSnapshots().isEmpty)
        #expect(try !repo.hasRealLedgerData())

        // Relaunching while still empty preserves Demo Mode.
        let reopened = try PositionRepository(databaseURL: url)
        let secondStore = PortfolioStore(
            positionRepository: reopened,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )
        #expect(secondStore.isDemoMode)
        #expect(secondStore.positions.count == 8)
    }

    @Test
    func existingNonEmptyLedgerPreservesRealDataAndResetsDemoModeOnRelaunch() throws {
        let url = databaseURL()
        let repo = try PositionRepository(databaseURL: url)
        let real = realHolding()
        try repo.insert(real)

        let store = PortfolioStore(
            positionRepository: repo,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )
        #expect(!store.isDemoMode)
        #expect(store.positions.map(\.symbol) == ["MSFT"])

        // User manually enables Demo Mode for showcase/screenshots.
        store.setDemoModeEnabled(true)
        #expect(store.isDemoMode)
        #expect(store.positions.count == 8)
        // SQLite still holds only the real holding.
        #expect(try repo.fetchPositions().map(\.symbol) == ["MSFT"])

        // Relaunching a non-empty ledger automatically resets Demo Mode to OFF.
        let reopened = try PositionRepository(databaseURL: url)
        let relaunched = PortfolioStore(
            positionRepository: reopened,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )
        #expect(!relaunched.isDemoMode)
        #expect(relaunched.positions.map(\.symbol) == ["MSFT"])
    }

    @Test
    func existingEmptyLegacyLedgerDoesNotAutoEnableDemoMode() throws {
        let url = databaseURL()
        _ = try PositionRepository(databaseURL: url)
        var connection: OpaquePointer?
        try #require(sqlite3_open(url.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        try #require(sqlite3_exec(connection, "DELETE FROM app_settings", nil, nil, nil) == SQLITE_OK)

        let reopened = try PositionRepository(databaseURL: url)
        let store = PortfolioStore(
            positionRepository: reopened,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )
        #expect(!store.isDemoMode)
        #expect(store.positions.isEmpty)
    }

    @Test
    func writeAIAndExportActionsAreGuardedInDemoMode() throws {
        let url = databaseURL()
        let repo = try PositionRepository(databaseURL: url)
        let store = PortfolioStore(
            positionRepository: repo,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )
        #expect(store.isDemoMode)

        // Export is blocked in Demo Mode.
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo-export-\(UUID()).portfolix")
        #expect(throws: (any Error).self) {
            _ = try store.exportFinancialData(to: exportURL)
        }

        // Risk Profile save is blocked and prompts.
        var customDraft = store.currentRiskProfileDraft
        customDraft.positionLimit = 45
        store.saveRiskProfile(customDraft)
        #expect(store.demoModeActionPrompt != nil)
        #expect(store.isDemoMode)
        store.dismissDemoModeActionPrompt()

        // AI analysis & follow-up are blocked and prompt.
        store.generateAIAnalysis()
        #expect(store.demoModeActionPrompt != nil)
        store.dismissDemoModeActionPrompt()

        store.submitAIAnalysisFollowUp("分析一下当前组合")
        #expect(store.demoModeActionPrompt != nil)
        store.dismissDemoModeActionPrompt()

        // Add Asset prompts, and confirming exits Demo Mode and opens New Position Editor.
        store.presentNewPositionEditor()
        #expect(store.positionEditorPresentation == nil)
        let prompt = try #require(store.demoModeActionPrompt)
        #expect(prompt.followUp == .openNewPositionEditor)

        store.confirmExitDemoModeAction()
        #expect(!store.isDemoMode)
        #expect(store.positions.isEmpty)
        #expect(store.positionEditorPresentation != nil)
        #expect(store.positionEditorPresentation?.position == nil)
    }

    @Test
    func importingBackupTurnsOffDemoModeAndRestoresRealHoldings() throws {
        let sourceRepo = try PositionRepository(databaseURL: databaseURL())
        try sourceRepo.insert(realHolding(symbol: "GOOG"))
        let sourceStore = PortfolioStore(positionRepository: sourceRepo, initialLanguage: .chinese)
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo-import-\(UUID()).portfolix")
        _ = try sourceStore.exportFinancialData(to: backupURL)
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let destRepo = try PositionRepository(databaseURL: databaseURL())
        let destStore = PortfolioStore(
            positionRepository: destRepo,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )
        #expect(destStore.isDemoMode)

        let prepared = try destStore.prepareFinancialDataImport(from: backupURL)
        let summary = try destStore.importFinancialData(prepared)
        #expect(summary.holdingCount == 1)
        #expect(!destStore.isDemoMode)
        #expect(destStore.positions.map(\.symbol) == ["GOOG"])
    }

    @Test
    func switchingLanguageInDemoModeRelocalizesHoldingsWithoutTouchingSQLite() throws {
        let repo = try PositionRepository(databaseURL: databaseURL())
        let store = PortfolioStore(
            positionRepository: repo,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )
        #expect(store.positions.contains { $0.name == "沪深300 ETF" })
        store.appLanguage = .english
        #expect(store.positions.contains { $0.name == "CSI 300 ETF" })
        #expect(try repo.fetchPositions().isEmpty)
    }

    @Test
    func demoModeInvestmentDistributionHasNoUnclassifiedExposureEvenWhenAIKeyIsConfigured() throws {
        let repo = try PositionRepository(databaseURL: databaseURL())
        try repo.insert(realHolding())
        let store = PortfolioStore(
            positionRepository: repo,
            initialLanguage: .chinese,
            resolveInitialDemoMode: true
        )
        try store.saveProviderAPIKey("sk-test-demo-key", kind: .llm)
        try store.saveProviderAPIKeyValidationState(.valid, kind: .llm)

        store.setDemoModeEnabled(true)
        let items = store.investmentDistributionItems
        #expect(items.count == 7)
        #expect(!items.contains { $0.id == InvestmentDistributionEngine.unclassifiedDomain.id })
        #expect(items.contains { $0.domain.titleChinese == "美股科技" })
        #expect(items.contains { $0.domain.titleChinese == "A股宽基" })
        #expect(items.contains { $0.domain.titleChinese == "人民币债券" })
        #expect(items.contains { $0.domain.titleChinese == "人民币现金" })
        #expect(items.contains { $0.domain.titleChinese == "比特币" })
    }
}
