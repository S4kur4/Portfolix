import AppKit
import Foundation
import PortfolixCore
import PortfolixMCPKit
import SwiftUI
import Testing
@testable import Portfolix

@Suite("Cash reductions")
struct CashReductionTests {
    private func repository() throws -> PositionRepository {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Portfolix.CashReduction.\(UUID())")
        let repo = try PositionRepository(databaseURL: folder.appendingPathComponent("test.sqlite"))
        try repo.setAppSetting(key: RiskProfilePersistence.updatedAtKey, value: "2026-01-01T00:00:00Z")
        return repo
    }

    private func seed(currency: DisplayCurrency = .cny) throws -> (PositionRepository, Position) {
        let repo = try repository()
        let cash = PositionClosureMath.cashPosition(currency: currency, quantity: 1000, name: "Demo Cash \(currency.rawValue)")
        try repo.insert(cash)
        try repo.replaceDailySnapshots(positions: [cash], snapshotDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        try repo.replaceDailySnapshots(positions: [cash], snapshotDate: .now)
        return (repo, cash)
    }

    private func withdraw(_ repo: PositionRepository, cash: Position, amount: Decimal, id: UUID = UUID()) throws -> PositionTradeRecord {
        try repo.recordTrade(id: id, side: .withdraw, expected: cash, quantity: amount, price: 1, fees: 0,
            tradeDate: .now, cashPositionID: nil, cashName: cash.name)
    }

    @Test(arguments: DisplayCurrency.allCases)
    func partialCashReductionHasNoRealizedProfitAndCanBeReversed(currency: DisplayCurrency) throws {
        let (repo, cash) = try seed(currency: currency)
        let record = try withdraw(repo, cash: cash, amount: Decimal(string: "249.75")!)
        let remaining = try #require(repo.fetchPositions().first)
        #expect(remaining.id == cash.id)
        #expect(remaining.quantity == Decimal(string: "750.25"))
        #expect(remaining.totalCost == remaining.quantity)
        #expect(remaining.averageCost == 1)
        #expect(record.side == .withdraw)
        #expect(record.cash == nil)
        #expect(record.quantityDelta == Decimal(string: "-249.75"))
        #expect(record.cashDelta == 0)
        #expect(record.realizedProfit == nil)
        let row = PositionTransactionRow(record)
        #expect(row.kind == .withdraw)
        #expect(row.profit(in: .cny) == nil)
        #expect(abs((try #require(repo.fetchDailyProfitPoints().last)).amountCNY.doubleValue) < 0.000001)
        try repo.reverseTrade(id: record.id)
        #expect(try repo.fetchPositions().first?.quantity == 1000)
        #expect(try repo.fetchPositions().first?.id == cash.id)
    }

    @Test @MainActor
    func fullReductionRemovesTheOpenRowButKeepsHistoryAndIgnoresStaleRefreshes() throws {
        let (repo, cash) = try seed()
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        let id = UUID()
        try store.recordTrade(id: id, side: .withdraw, position: cash, quantity: 1000,
            price: 1, fees: 0, tradeDate: .now, cashPositionID: nil)
        #expect(store.positions.isEmpty)
        #expect(store.realizedProfitCNY == 0)
        #expect(store.todayProfitCNY == 0)
        #expect(store.investmentCloudDailyProfitItems(asOf: .now).isEmpty)
        #expect(try repo.fetchAssetPriceSnapshots(positionID: cash.id).count == 1)
        let record = try #require(store.positionTrades.first)
        #expect(record.priceHistory.contains { $0.assetID == cash.id.uuidString && $0.date == PositionClosureMath.day(.now) })
        try repo.applyQuoteRefresh(updatedPositions: [cash], snapshotPositions: [cash])
        #expect(try repo.fetchPositions().isEmpty)
        try store.reverseRecord(PositionTransactionRow(record))
        #expect(store.positions.first?.quantity == 1000)
        #expect(store.positions.first?.id == cash.id)
    }

    @Test
    func invalidCashOperationsCannotChangeBalancesOrAuditRecords() throws {
        let (repo, cash) = try seed()
        let before = try repo.exportDataPayload()
        for value: Decimal in [-1, 0, 1001] {
            #expect(throws: (any Error).self) { try withdraw(repo, cash: cash, amount: value) }
        }
        for (price, fees): (Decimal, Decimal) in [(0, 0), (2, 0), (1, 1)] {
            #expect(throws: (any Error).self) {
                try repo.recordTrade(side: .withdraw, expected: cash, quantity: 10, price: price, fees: fees,
                    tradeDate: .now, cashPositionID: nil, cashName: cash.name)
            }
        }
        #expect(throws: PositionTradeError.invalidInput) {
            try repo.recordTrade(side: .withdraw, expected: cash, quantity: 10, price: 1, fees: 0,
                tradeDate: .now, cashPositionID: UUID(), cashName: cash.name)
        }
        #expect(throws: PositionTradeError.invalidInput) {
            try repo.recordTrade(side: .sell, expected: cash, quantity: 10, price: 1, fees: 0,
                tradeDate: .now, cashPositionID: nil, cashName: cash.name)
        }
        let security = Position(id: UUID(), name: "Demo Fund", symbol: "DEMO", category: .fund, quoteCurrency: .cny,
            quantity: 10, averageCost: 1, latestPrice: 1, marketValueCNY: 10, profitRate: 0,
            weeklyTrend: [], source: "手工价格", quoteTime: ISO8601DateFormatter().string(from: .now), freshness: .manual)
        #expect(throws: PositionTradeError.invalidInput) { try withdraw(repo, cash: security, amount: 1) }
        #expect(try repo.exportDataPayload() == before)
    }

    @Test(arguments: ["", "0", "-1", "1001", "1e29", "中文", "NaN"])
    func reductionInputRejectsEmptyInvalidOrExcessiveAmounts(text: String) {
        #expect(throws: (any Error).self) { try CashReductionInput.amount(text, available: 1000) }
    }

    @Test
    func reductionsAreIdempotentAndCannotBeAppliedToARemovedCashAccount() throws {
        let (repo, cash) = try seed()
        let record = try withdraw(repo, cash: cash, amount: 1000)
        let before = try repo.exportDataPayload()
        #expect(throws: PositionTradeError.changed) { try withdraw(repo, cash: cash, amount: 1000, id: record.id) }
        #expect(throws: PositionTradeError.changed) { try withdraw(repo, cash: cash, amount: 1) }
        #expect(try repo.exportDataPayload() == before)
    }

    @Test
    func undoingACashDepositCannotBypassLaterWithdrawals() throws {
        let repo = try repository()
        let template = PositionClosureMath.cashPosition(currency: .cny, quantity: 1, name: "Cash")
        let deposit = try repo.recordTrade(side: .add, expected: template, quantity: 1000, price: 1, fees: 0,
            tradeDate: .now, cashPositionID: nil, cashName: template.name)
        let first = try withdraw(repo, cash: #require(repo.fetchPositions().first), amount: 400)
        let second = try withdraw(repo, cash: #require(repo.fetchPositions().first), amount: 600)
        let before = try repo.exportDataPayload()
        #expect(throws: PositionTradeError.insufficientCash) { try repo.reverseTrade(id: deposit.id) }
        #expect(try repo.exportDataPayload() == before)
        try repo.reverseTrade(id: second.id)
        #expect(try repo.fetchPositions().first?.quantity == 600)
        try repo.reverseTrade(id: first.id)
        #expect(try repo.fetchPositions().first?.quantity == 1000)
        try repo.reverseTrade(id: deposit.id)
        #expect(try repo.fetchPositions().isEmpty)
    }

    @Test
    func reversalPreservesLaterCashFundedPurchases() throws {
        let (repo, cash) = try seed()
        let reduction = try withdraw(repo, cash: cash, amount: 250)
        let currentCash = try #require(repo.fetchPositions().first)
        let security = Position(id: UUID(), name: "Demo Fund", symbol: "DEMO", category: .fund, quoteCurrency: .cny,
            quantity: 2, averageCost: 100, latestPrice: 100, marketValueCNY: 200, profitRate: 0,
            weeklyTrend: [], source: "手工价格", quoteTime: ISO8601DateFormatter().string(from: .now), freshness: .manual)
        _ = try repo.recordTrade(side: .buy, expected: security, quantity: 2, price: 100, fees: 0,
            tradeDate: .now, cashPositionID: currentCash.id, cashName: cash.name)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 550)
        try repo.reverseTrade(id: reduction.id)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 800)
        #expect(try repo.fetchPositions().first { $0.id == security.id }?.quantity == 2)
        #expect(try repo.fetchPositions().first { $0.id == security.id }?.totalCost == 200)
    }

    @Test
    func backupRoundTripPreservesWithdrawalAndDoesNotDebitCashTwice() throws {
        let (repo, cash) = try seed(currency: .usdt)
        let record = try withdraw(repo, cash: cash, amount: 1000)
        let archive = repo.storageURL.deletingLastPathComponent().appendingPathComponent("cash.zip")
        _ = try PortfolixDataPackageService.write(payload: repo.exportDataPayload(), to: archive)
        let payload = try PortfolixDataPackageService.prepareImport(from: archive).payload
        let restored = try repository()
        _ = try restored.importDataPayload(payload)
        _ = try restored.importDataPayload(payload)
        #expect(try restored.fetchPositions().isEmpty)
        #expect(try restored.fetchPositionTrades().count == 1)
        #expect(try restored.fetchOpeningBalances().first { $0.id == cash.id }?.units == 1000)
        try restored.reverseTrade(id: record.id)
        #expect(try restored.fetchPositions().first?.quantity == 1000)
        #expect(try restored.fetchPositions().first?.quoteCurrency == .usdt)
    }

    @Test
    func reopeningAnEarlierCashCycleCannotOverwriteANewCashHolding() throws {
        let (repo, cash) = try seed()
        let withdrawal = try withdraw(repo, cash: cash, amount: 1000)
        let replacement = PositionClosureMath.cashPosition(currency: .cny, quantity: 1, name: "New Cash")
        _ = try repo.recordTrade(side: .add, expected: replacement, quantity: 500, price: 1, fees: 0,
            tradeDate: .now, cashPositionID: nil, cashName: replacement.name)
        let before = try repo.exportDataPayload()
        #expect(throws: PositionTradeError.identityConflict) { try repo.reverseTrade(id: withdrawal.id) }
        #expect(try repo.exportDataPayload() == before)
        #expect(try repo.fetchPositions().first?.id == replacement.id)
        #expect(try repo.fetchPositions().first?.quantity == 500)
    }

    @Test
    func foreignCashWithdrawalPreservesFXPerformanceWithoutTreatingPrincipalAsLoss() {
        let record = RecordedTradeProfit(assetID: "cash", cashID: nil, side: "withdraw", tradeDate: "2026-10-31",
            quantity: "100", executionPrice: "1", fees: "0", cashAmount: "100", rateFromCNY: "0.2")
        let result = RecordedTradeProfit.adjustments(trades: [record],
            unitValues: ["cash": ["2026-10-30": 4, "2026-10-31": 5]], through: "2026-10-31")
        #expect(result["2026-10-31"]?["cash"] == 100)
    }

    @Test @MainActor
    func appAgentAndMCPDoNotReportCashWithdrawalsAsInvestmentLosses() throws {
        let (repo, cash) = try seed()
        _ = try withdraw(repo, cash: cash, amount: 1000)
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        #expect(store.todayProfitCNY == 0)
        #expect(store.realizedProfitCNY == 0)
        let request = try AIPortfolioToolRequest(call: .init(callID: "cash", name: "list_transactions", arguments: "{}"))
        let json = AIPortfolioDataToolExecutor.execute(request, snapshot: .init(positions: store.positions, trades: store.positionTrades))
        #expect(json.contains("\"side\":\"withdraw\""))
        #expect(json.contains("\"cash_flow_direction\":\"out\""))
        #expect(json.contains("\"realized_profit_quote\":null"))
        #expect(json.contains("\"execution_price\":null"))
        try repo.setAppSetting(key: "mcp_read_access_enabled", value: "true")
        let server = PortfolioMCPServer(databaseURL: repo.storageURL)
        _ = server.respond(to: try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "CashFixture", "version": "1"]]]))
        _ = server.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        let data = try #require(server.respond(to: JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "get_daily_profit",
                "arguments": ["start_date": PositionClosureMath.day(Calendar.current.date(byAdding: .day, value: -1, to: .now)!),
                              "end_date": PositionClosureMath.day(.now)]]])))
        let response = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])
        let days = try #require(result["days"] as? [[String: String]])
        #expect(days.last?["amount_cny"] == "0")
    }

    @Test @MainActor
    func cashReductionSheetFitsBothLanguagesAndAppearances() throws {
        let (repo, cash) = try seed()
        for language: AppLanguage in [.chinese, .english] {
            let store = PortfolioStore(positionRepository: repo, initialLanguage: language)
            for scheme: ColorScheme in [.light, .dark] {
                let host = NSHostingView(rootView: CashReductionSheet(position: cash).environment(store).environment(\.colorScheme, scheme))
                #expect(host.fittingSize == CGSize(width: 620, height: 460))
            }
        }
    }
}
