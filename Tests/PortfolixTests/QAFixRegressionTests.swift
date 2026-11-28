import Foundation
import Testing
@testable import Portfolix

@Suite("QA report regression fixes")
@MainActor
struct QAFixRegressionTests {
    private func databaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Portfolix.QAFixTests.\(UUID())/portfolio.sqlite")
    }

    @Test
    func incompleteReconciliationBlocksBothDashboardAndInvestmentCloudDailyProfit() throws {
        let now = Date.now
        let yesterday = now.addingTimeInterval(-86_400)
        let repo = try PositionRepository(databaseURL: databaseURL())
        let day = PositionClosureMath.day(now)
        let fetched = PositionClosureMath.isoTimestamp(now)

        let apple = Position(
            name: "Apple", symbol: "AAPL", category: .usStock, quoteCurrency: .usd,
            quantity: 10, averageCost: 200, latestPrice: 220,
            marketValueCNY: 2_200 / DisplayCurrency.usd.rateFromCNY, profitRate: 10,
            weeklyTrend: [210, 220], source: "东方财富", quoteTime: day, fetchedAt: fetched,
            freshness: .updated,
            dailyPriceBaseline: PositionDailyPriceBaseline(day: day, price: 210)
        )
        let yesterdayFetched = PositionClosureMath.isoTimestamp(yesterday)
        let yesterdayDay = PositionClosureMath.day(yesterday)
        let temp = Position(
            name: "TEMP", symbol: "TEMP001", category: .cnStock, quoteCurrency: .cny,
            quantity: 100, averageCost: 10, latestPrice: 10,
            marketValueCNY: 1_000, profitRate: 0,
            weeklyTrend: [10], source: "手工价格", quoteTime: yesterdayDay, fetchedAt: yesterdayFetched,
            freshness: .manual
        )
        try repo.insert(apple)
        try repo.insert(temp)
        try repo.replaceDailySnapshots(positions: [apple, temp], snapshotDate: yesterday)
        // Reconcile temp with missing intraday valuation, then clear to 0 -> incomplete day.
        _ = try repo.reconcilePosition(expected: temp, quantity: 120, totalCost: 1_200, reason: "missing", now: now)
        let updatedTemp = try #require(try repo.fetchPositions().first { $0.id == temp.id })
        _ = try repo.reconcilePosition(expected: updatedTemp, quantity: 0, totalCost: 0, reason: "correction", now: now.addingTimeInterval(60))

        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        #expect(!store.todayProfitIsAvailable(asOf: now))
        // PF-001: Cloud must NOT show partial Apple daily profit while Dashboard shows "—".
        #expect(store.investmentCloudDailyProfitItems(asOf: now).isEmpty)
    }

    @Test
    func defaultSystemCashNamesLocalizeWhileCustomCashNamesStayUntouched() {
        let systemCash = PositionClosureMath.cashPosition(currency: .cny, quantity: 5_000, name: "现金 CNY")
        #expect(systemCash.localizedDisplayName(language: .chinese) == "现金 CNY")
        #expect(systemCash.localizedDisplayName(language: .english) == "Cash CNY")

        let customCash = PositionClosureMath.cashPosition(currency: .cny, quantity: 10_000, name: "应急现金", symbol: "CASH-EMERGENCY")
        #expect(customCash.localizedDisplayName(language: .chinese) == "应急现金")
        #expect(customCash.localizedDisplayName(language: .english) == "应急现金")
    }

    @Test
    func tradePriceFormattingPreservesThreeDecimalETFPrecision() {
        let price = Decimal(string: "4.162")!
        #expect(formatUnitCost(price, currency: .cny) == "¥4.162")
    }

    @Test
    func cashAdditionDisplaysDepositAndTradeTimeUsesUnifiedISOStyle() throws {
        let now = Date(timeIntervalSince1970: 1_795_875_540) // 2026-11-28 22:19 UTC+8
        let repo = try PositionRepository(databaseURL: databaseURL())
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 10_000, name: "应急现金", symbol: "CASH-CNY")
        let trade = try repo.recordTrade(
            side: .add, expected: cash, quantity: 10_000, price: 1, fees: 0,
            tradeDate: now, cashPositionID: nil, cashName: "现金 CNY", now: now
        )
        let row = PositionTransactionRow(trade)
        #expect(row.kindTitle(language: .chinese) == "存入")
        #expect(row.kindTitle(language: .english) == "Deposit")

        let formattedTradeTime = PositionTransactionRow.formatTradeTime(trade)
        #expect(formattedTradeTime.contains("-"))
        #expect(formattedTradeTime.contains(":"))
        #expect(!formattedTradeTime.contains("/"))
    }

    @Test
    func missingAPIKeyFollowUpIsMarkedAsFailureWithoutZeroTokenUsageAndFollowsAppLanguage() async throws {
        let repo = try PositionRepository(databaseURL: databaseURL())
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .english)
        store.aiConfiguration.isEnabled = true

        // Even when typing a Chinese prompt in English UI, system configuration errors follow appLanguage.
        store.submitAIAnalysisFollowUp("看看我的组合")
        await store.waitForAIAnalysisIdle()

        let assistant = try #require(store.aiAnalysisChatItems.last)
        #expect(assistant.kind == .assistant)
        #expect(assistant.retryQuestion == "看看我的组合")
        #expect(assistant.modelUsage == nil)
        #expect(assistant.text?.contains("DeepSeek API is not configured yet") == true)
    }

    @Test
    func localizedCashNameTranslatesDefaultCashFundingLabel() {
        #expect(PositionClosureMath.localizedCashName("现金 CNY", currency: .cny, language: .english) == "Cash CNY")
        #expect(PositionClosureMath.localizedCashName("Cash USD", currency: .usd, language: .chinese) == "现金 USD")
        #expect(PositionClosureMath.localizedCashName("应急现金", currency: .cny, language: .english) == "应急现金")
    }
}
