import Foundation
import Testing
import PortfolixCore
import PortfolixMCPKit
@testable import Portfolix

@Suite("Holding reconciliation checkpoints")
struct PositionReconciliationTests {
    private var now: Date { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)! }
    private func position(_ id: UUID = UUID(), quantity: Decimal = 10, price: Decimal = 130, at date: Date) -> Position {
        Position(id: id, name: "Reconciliation Demo", symbol: "RECON", category: .cnStock, quoteCurrency: .cny,
                 quantity: quantity, totalCost: 800, averageCost: 800 / quantity, latestPrice: price,
                 marketValueCNY: quantity * price, profitRate: 62.5, weeklyTrend: [120, price.doubleValue],
                 source: "手工价格", quoteTime: ISO8601DateFormatter().string(from: date),
                 fetchedAt: ISO8601DateFormatter().string(from: date), freshness: .manual)
    }
    private func setup(at date: Date? = nil) throws -> (PositionRepository, Position, Position) {
        let date = date ?? now
        let repo = try PositionRepository(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("Portfolix.Reconciliation.\(UUID())/test.sqlite"))
        try repo.setAppSetting(key: RiskProfilePersistence.updatedAtKey, value: "2026-01-01T00:00:00Z")
        let holding = position(at: date)
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 1000, name: "Demo Cash")
        try repo.insert(holding); try repo.insert(cash)
        try repo.replaceDailySnapshots(positions: [position(holding.id, price: 120, at: date), cash], snapshotDate: date.addingTimeInterval(-86400))
        try repo.replaceDailySnapshots(positions: [holding, cash], snapshotDate: date)
        return (repo, holding, cash)
    }
    private func holding(_ repo: PositionRepository, _ id: UUID) throws -> Position {
        try #require(repo.fetchPositions().first { $0.id == id })
    }
    private func profit(_ repo: PositionRepository, through date: Date) throws -> Decimal {
        try #require(repo.fetchDailyProfitPoints(through: date).last).amountCNY
    }

    @Test func absoluteBalanceDoesNotBecomeProfitOrCashFlow() throws {
        let (repo, original, cash) = try setup()
        let record = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: 960, reason: "reconcile", now: now)
        #expect(record.asset.quantity == "10")
        #expect(try holding(repo, original.id).quantity == 12)
        #expect(try holding(repo, cash.id).quantity == 1000)
        #expect(try repo.fetchPositionTrades().isEmpty)
        #expect(try profit(repo, through: now) == 100)
        #expect(try repo.fetchOpeningBalances().first { $0.id == original.id }?.units == 10)
        let refreshed = position(original.id, quantity: 12, price: 135, at: now)
        _ = try repo.applyQuoteRefresh(updatedPositions: [refreshed], snapshotPositions: [], snapshotDate: now)
        #expect(try profit(repo, through: now) == 160)
    }

    @Test func multipleCheckpointsPreserveEachPriceSegment() throws {
        let (repo, original, _) = try setup()
        _ = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: 960, reason: "reconcile", now: now)
        _ = try repo.applyQuoteRefresh(updatedPositions: [position(original.id, quantity: 12, price: 135, at: now)], snapshotPositions: [], snapshotDate: now)
        let second = try repo.reconcilePosition(expected: holding(repo, original.id), quantity: 15, totalCost: 1200, reason: "missing", now: now.addingTimeInterval(60))
        _ = try repo.applyQuoteRefresh(updatedPositions: [position(original.id, quantity: 15, price: 140, at: now)], snapshotPositions: [], snapshotDate: now)
        #expect(try profit(repo, through: now) == 235) // 10×10 + 12×5 + 15×5
        try repo.reverseReconciliation(id: second.id, now: now.addingTimeInterval(120))
        #expect(try holding(repo, original.id).quantity == 12)
        #expect(try holding(repo, original.id).latestPrice == 140)
        #expect(try profit(repo, through: now) == 235)
    }

    @Test func unknownCostSurvivesQuotesTradingAndBackup() throws {
        let (repo, original, cash) = try setup()
        _ = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: nil, reason: "missing", now: now)
        let current = try holding(repo, original.id)
        #expect(!current.costIsKnown)
        #expect(current.totalCost == 800) // carried internally, never reported as a known zero
        let trade = try repo.recordTrade(side: .sell, expected: current, quantity: 2, price: 130, fees: 0,
            tradeDate: now.addingTimeInterval(60), cashPositionID: cash.id, cashName: cash.name, now: now.addingTimeInterval(120))
        #expect(trade.realizedProfit == nil)
        #expect(try !holding(repo, original.id).costIsKnown)
        let payload = try repo.exportDataPayload()
        #expect(payload.holdings.first { $0.id == original.id.uuidString }?.costKnown == false)
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("Reconciliation-\(UUID()).zip")
        _ = try PortfolixDataPackageService.write(payload: payload, to: zip)
        let prepared = try PortfolixDataPackageService.prepareImport(from: zip)
        let restored = try PositionRepository(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("Restore-\(UUID())/test.sqlite"))
        _ = try restored.importDataPayload(prepared.payload)
        #expect(try !holding(restored, original.id).costIsKnown)
        #expect(try restored.fetchReconciliations() == repo.fetchReconciliations())
        #expect(try profit(restored, through: now) == 100)
    }

    @Test func zeroIsNotASaleAndCanBeReversed() throws {
        let (repo, original, cash) = try setup()
        let record = try repo.reconcilePosition(expected: original, quantity: 0, totalCost: nil, reason: "correction", now: now)
        #expect(try repo.fetchPositions().allSatisfy { $0.id != original.id })
        #expect(try holding(repo, cash.id).quantity == 1000)
        #expect(try profit(repo, through: now) == 100)
        try repo.reverseReconciliation(id: record.id, now: now.addingTimeInterval(60))
        #expect(try holding(repo, original.id).quantity == 10)
        #expect(try profit(repo, through: now) == 100)
    }

    @Test func olderTransactionsAndUndoCannotCrossCheckpoint() throws {
        let (repo, original, cash) = try setup()
        let trade = try repo.recordTrade(side: .sell, expected: original, quantity: 1, price: 130, fees: 0,
            tradeDate: now.addingTimeInterval(-120), cashPositionID: cash.id, cashName: cash.name, now: now.addingTimeInterval(-60))
        _ = try repo.reconcilePosition(expected: holding(repo, original.id), quantity: 12, totalCost: 960, reason: "missing", now: now)
        #expect(throws: (any Error).self) { try repo.reverseTrade(id: trade.id, now: now.addingTimeInterval(60)) }
        #expect(throws: (any Error).self) {
            try repo.recordTrade(side: .add, expected: holding(repo, original.id), quantity: 1, price: 130, fees: 0,
                tradeDate: now.addingTimeInterval(-1), cashPositionID: nil, cashName: "", now: now.addingTimeInterval(60))
        }
        #expect(try holding(repo, original.id).quantity == 12)
    }

    @Test func subsequentTradeBlocksUndoUntilReversed() throws {
        let (repo, original, cash) = try setup()
        let checkpoint = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: 960, reason: "reconcile", now: now)
        let trade = try repo.recordTrade(side: .sell, expected: holding(repo, original.id), quantity: 2, price: 130, fees: 0,
            tradeDate: now.addingTimeInterval(60), cashPositionID: cash.id, cashName: cash.name, now: now.addingTimeInterval(120))
        #expect(throws: (any Error).self) { try repo.reverseReconciliation(id: checkpoint.id, now: now.addingTimeInterval(180)) }
        try repo.reverseTrade(id: trade.id, now: now.addingTimeInterval(180))
        try repo.reverseReconciliation(id: checkpoint.id, now: now.addingTimeInterval(240))
        #expect(try holding(repo, original.id).quantity == 10)
    }

    @Test func backdatingWithinThePostCheckpointDayReplaysInActualTimeOrder() throws {
        let (repo, original, cash) = try setup()
        _ = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: 960, reason: "reconcile", now: now)
        let sale = try repo.recordTrade(side: .sell, expected: holding(repo, original.id), quantity: 6, price: 130, fees: 0,
            tradeDate: now.addingTimeInterval(120), cashPositionID: cash.id, cashName: cash.name, now: now.addingTimeInterval(180))
        _ = try repo.recordTrade(side: .add, expected: holding(repo, original.id), quantity: 2, price: 100, fees: 0,
            tradeDate: now.addingTimeInterval(60), cashPositionID: nil, cashName: "", now: now.addingTimeInterval(240))
        let corrected = try #require(repo.fetchPositionTrades().first { $0.id == sale.id })
        #expect(abs((corrected.cost - Decimal(1160) * 6 / 14).doubleValue) < 0.000001)
        #expect(try holding(repo, original.id).quantity == 8)
        #expect(try holding(repo, cash.id).quantity == 1780)
        #expect(try profit(repo, through: now) == 160) // 100 existing gain + 2×(130−100)
    }

    @Test func missingCheckpointPriceSuppressesDailyProfit() throws {
        let (repo, original, _) = try setup()
        _ = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: 960, reason: "missing", now: now.addingTimeInterval(86400))
        #expect(try repo.fetchReconciliations().last?.profitAdjustmentCNY == nil)
        #expect(try repo.fetchDailyProfitPoints(through: now.addingTimeInterval(86400)).allSatisfy { $0.date != Calendar.current.startOfDay(for: now.addingTimeInterval(86400)) })
    }

    @Test func staleFormAndInvalidAmountsCannotChangeBalances() throws {
        let (repo, original, _) = try setup()
        _ = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: 960, reason: "reconcile", now: now)
        #expect(throws: (any Error).self) { try repo.reconcilePosition(expected: original, quantity: 15, totalCost: 1200, reason: "missing", now: now) }
        #expect(throws: (any Error).self) { try repo.reconcilePosition(expected: holding(repo, original.id), quantity: -1, totalCost: nil, reason: "missing", now: now) }
        #expect(try repo.fetchReconciliations().count == 1)
        #expect(try holding(repo, original.id).quantity == 12)
    }

    @Test func reverseOnLaterDayPreservesHistoricalProfit() throws {
        let (repo, original, _) = try setup()
        let record = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: 960, reason: "reconcile", now: now)
        let tomorrow = now.addingTimeInterval(86400)
        _ = try repo.applyQuoteRefresh(updatedPositions: [position(original.id, quantity: 12, price: 140, at: tomorrow)], snapshotPositions: [], snapshotDate: tomorrow)
        try repo.reverseReconciliation(id: record.id, now: tomorrow.addingTimeInterval(60))
        let profits = try repo.fetchDailyProfitPoints(through: tomorrow)
        #expect(profits.first { $0.date == Calendar.current.startOfDay(for: now) }?.amountCNY == 100)
        #expect(profits.last?.amountCNY == 120)
    }

    private func tool(_ repo: PositionRepository, _ name: String, arguments: [String: Any] = [:]) throws -> [String: Any] {
        try repo.setAppSetting(key: "mcp_read_access_enabled", value: "true")
        let server = PortfolioMCPServer(databaseURL: repo.storageURL)
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [
            "name": name, "arguments": arguments, "_meta": [
                "io.modelcontextprotocol/protocolVersion": PortfolioMCPServer.modernVersion,
                "io.modelcontextprotocol/clientCapabilities": [:]]]]
        let data = try #require(server.respond(to: JSONSerialization.data(withJSONObject: request)))
        let response = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["isError"] as? Bool != true)
        return try #require(result["structuredContent"] as? [String: Any])
    }

    @Test func readOnlyToolsHideUnknownCostAndExposeCheckpoints() throws {
        let (repo, original, _) = try setup()
        _ = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: nil, reason: "missing", now: now)
        let holdings = try tool(repo, "list_holdings")
        let rows = try #require(holdings["holdings"] as? [[String: String]])
        let row = try #require(rows.first { $0["asset_id"] == original.id.uuidString })
        #expect(row["cost_status"] == "unknown")
        #expect(row["total_cost"] == nil)
        #expect(row["average_cost"] == nil)
        let summary = try tool(repo, "get_portfolio_summary")
        let snapshot = try #require(summary["latest_snapshot"] as? [String: String])
        #expect(snapshot["total_profit_cny"] == nil)
        let activity = try tool(repo, "list_transactions")
        let records = try #require(activity["records"] as? [[String: Any]])
        let checkpoint = try #require(records.first { $0["side"] as? String == "reconciliation" })
        #expect(checkpoint["portfolio_flow"] as? String == "none")
        #expect(checkpoint["before_quantity"] as? String == "10")
        #expect(checkpoint["realized_profit_cny"] is NSNull)
        let day = PositionClosureMath.day(now)
        let daily = try tool(repo, "get_daily_profit", arguments: ["start_date": day, "end_date": day])
        #expect((daily["days"] as? [[String: String]])?.first?["amount_cny"] == "100")
    }

    @Test func unknownRealizedProfitIsNotReportedAsZeroAndRemainingCashHasKnownCost() throws {
        let (repo, original, cash) = try setup()
        _ = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: nil, reason: "missing", now: now)
        _ = try repo.recordTrade(side: .sell, expected: holding(repo, original.id), quantity: 12, price: 130, fees: 0,
            tradeDate: now.addingTimeInterval(60), cashPositionID: cash.id, cashName: cash.name, now: now.addingTimeInterval(120))
        let summary = try tool(repo, "get_portfolio_summary")
        #expect(summary["realized_profit_status"] as? String == "incomplete")
        #expect(summary["realized_profit_cny"] is NSNull)
        let snapshot = try #require(summary["latest_snapshot"] as? [String: String])
        #expect(snapshot["cost_status"] == "known")
        #expect(snapshot["total_cost_cny"] == "2560")
        #expect(try repo.fetchPortfolioSnapshots().last?.costIsKnown == true)
    }

    @Test func prepareIsolatedReconciliationDemoOnlyWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["PORTFOLIX_RECONCILIATION_DEMO_DATABASE"] else { return }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(temporaryRoot), !FileManager.default.fileExists(atPath: url.path) else {
            throw PositionTradeError.invalidInput
        }
        let (source, _, _) = try setup(at: .now)
        let destination = try PositionRepository(databaseURL: url)
        _ = try destination.importDataPayload(source.exportDataPayload())
        _ = try PortfolixDataPackageService.write(payload: source.exportDataPayload(),
            to: url.deletingPathExtension().appendingPathExtension("zip"))
    }

    @Test func historicalAdditionCanRefreshTodaysQuoteWithoutBackfillingThatPrice() throws {
        let (repo, original, _) = try setup()
        let yesterday = now.addingTimeInterval(-86400)
        let trade = try repo.recordTrade(side: .add, expected: original, quantity: 2, price: 125, fees: 0,
            tradeDate: yesterday, cashPositionID: nil, cashName: "", now: now,
            quoteUpdate: position(original.id, price: 140, at: now))
        #expect(trade.tradeDate == PositionClosureMath.day(yesterday))
        #expect(try holding(repo, original.id).quantity == 12)
        #expect(try holding(repo, original.id).latestPrice == 140)
        let payload = try repo.exportDataPayload()
        let oldPrice = payload.assetPriceSnapshots.first { $0.assetID == original.id.uuidString && $0.date == PositionClosureMath.day(yesterday) }
        #expect(oldPrice?.latestPrice == "120")
        #expect(try profit(repo, through: now) == 240)
    }

    @Test func reversingCostOnlyCheckpointDoesNotNeedAFreshQuote() throws {
        let (repo, original, _) = try setup()
        let checkpoint = try repo.reconcilePosition(expected: original, quantity: original.quantity,
            totalCost: 900, reason: "correction", now: now)
        let tomorrow = now.addingTimeInterval(86400)
        try repo.reverseReconciliation(id: checkpoint.id, now: tomorrow)
        let reversed = try #require(repo.fetchReconciliations().last)
        #expect(reversed.reversalProfitAdjustmentCNY == "0")
        #expect(try repo.fetchDailyProfitPoints(through: tomorrow).contains { $0.date == Calendar.current.startOfDay(for: tomorrow) })
    }

    @Test @MainActor func zeroCheckpointRetainsAvailableProfitInAIAndCloud() throws {
        let (repo, original, _) = try setup()
        _ = try repo.reconcilePosition(expected: original, quantity: 0, totalCost: 0, reason: "correction", now: now)
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        #expect(store.todayProfitCNY(asOf: now) == 100)
        #expect(store.aiTodayReturnStatus(asOf: now) == "available")
        #expect(store.investmentCloudDailyProfitItems(asOf: now).map(\.amountCNY) == [100])
    }

    @Test @MainActor func incompleteZeroCheckpointDoesNotExposePartialProfitInCloud() throws {
        let (repo, original, cash) = try setup(at: now.addingTimeInterval(-86400))
        _ = try repo.reconcilePosition(expected: original, quantity: 12, totalCost: 960, reason: "missing", now: now)
        let fresh = position(original.id, quantity: 12, price: 140, at: now)
        _ = try repo.applyQuoteRefresh(updatedPositions: [fresh], snapshotPositions: [], snapshotDate: now)
        _ = try repo.recordTrade(side: .sell, expected: holding(repo, original.id), quantity: 1, price: 140, fees: 1,
            tradeDate: now.addingTimeInterval(60), cashPositionID: cash.id, cashName: cash.name,
            now: now.addingTimeInterval(120))
        _ = try repo.reconcilePosition(expected: holding(repo, original.id), quantity: 0, totalCost: 0,
            reason: "correction", now: now.addingTimeInterval(180))
        let store = PortfolioStore(positionRepository: repo)
        #expect(!store.todayProfitIsAvailable(asOf: now))
        #expect(store.investmentCloudDailyProfitItems(asOf: now).isEmpty)
    }

    @Test func staleKnownCostCannotSubmitAfterCostBecomesUnknown() throws {
        let (repo, original, cash) = try setup()
        _ = try repo.reconcilePosition(expected: original, quantity: original.quantity, totalCost: nil,
            reason: "missing", now: now)
        #expect(throws: (any Error).self) {
            try repo.recordTrade(side: .sell, expected: original, quantity: 1, price: 130, fees: 0,
                tradeDate: now.addingTimeInterval(60), cashPositionID: cash.id, cashName: cash.name,
                now: now.addingTimeInterval(120))
        }
        #expect(try repo.fetchPositionTrades().isEmpty)
        #expect(try holding(repo, original.id).quantity == original.quantity)
        #expect(try holding(repo, cash.id).quantity == cash.quantity)
    }

    @Test @MainActor func synchronizationReloadsACostStatusChangeWithoutBalanceChanges() throws {
        let (repo, original, _) = try setup()
        let store = PortfolioStore(positionRepository: repo)
        #expect(store.hasKnownPortfolioCost)
        _ = try repo.reconcilePosition(expected: original, quantity: original.quantity,
            totalCost: nil, reason: "missing", now: now)
        store.synchronizePersistedMarketDataIfNeeded()
        #expect(!store.hasKnownPortfolioCost)
        #expect(store.positionReconciliations.count == 1)
    }

    @Test @MainActor func lifecycleKeepsAppAIAndMCPConsistentAcrossRestore() throws {
        let (repo, original, cash) = try setup()
        // External addition, then a balance checkpoint: neither can credit cash.
        let added = try repo.recordTrade(side: .add, expected: original, quantity: 2, price: 125, fees: 1,
            tradeDate: now.addingTimeInterval(-120), cashPositionID: nil, cashName: "",
            now: now.addingTimeInterval(-60))
        _ = try repo.reconcilePosition(expected: holding(repo, original.id), quantity: 15,
            totalCost: nil, reason: "missing", now: now)
        let unknown = try holding(repo, original.id)
        #expect(!unknown.costIsKnown)
        let sold = try repo.recordTrade(side: .sell, expected: unknown, quantity: 3, price: 135, fees: 2,
            tradeDate: now.addingTimeInterval(60), cashPositionID: cash.id, cashName: cash.name,
            now: now.addingTimeInterval(120))
        #expect(sold.realizedProfit == nil)
        #expect(try holding(repo, cash.id).quantity == 1403)
        // A current quote, a new store and a ZIP round trip must agree on the same segments.
        _ = try repo.applyQuoteRefresh(updatedPositions: [position(original.id, quantity: 12, price: 140, at: now)],
            snapshotPositions: [], snapshotDate: now)
        let before = try repo.exportDataPayload()
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("Lifecycle-\(UUID()).zip")
        _ = try PortfolixDataPackageService.write(payload: before, to: zip)
        let restored = try PositionRepository(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("LifecycleRestore-\(UUID())/test.sqlite"))
        _ = try restored.importDataPayload(PortfolixDataPackageService.prepareImport(from: zip).payload)
        let store = PortfolioStore(positionRepository: restored)
        let expectedProfit: Decimal = 242 // 100 + 2×(130−125)−1 + 3×(135−130)−2 + 12×(140−130)
        #expect(store.todayProfitCNY(asOf: now) == expectedProfit)
        #expect(try profit(restored, through: now) == expectedProfit)
        #expect(!store.hasKnownPortfolioCost)
        #expect(store.investmentCloudDailyProfitItems(asOf: now).reduce(Decimal.zero) { $0 + $1.amountCNY } == expectedProfit)
        let daily = try tool(restored, "get_daily_profit", arguments: ["start_date": PositionClosureMath.day(now), "end_date": PositionClosureMath.day(now)])
        #expect((daily["days"] as? [[String: String]])?.first?["amount_cny"] == "242")
        let summary = try tool(restored, "get_portfolio_summary")
        #expect(summary["realized_profit_cny"] is NSNull)
        #expect((summary["latest_snapshot"] as? [String: String])?["total_cost_cny"] == nil)
        let aiRequest = try AIPortfolioToolRequest(call: LLMFunctionCall(
            callID: "review-summary", name: AIPortfolioDataTool.summary.rawValue, arguments: "{}"))
        let ai = AIPortfolioDataToolExecutor.execute(aiRequest, snapshot: AIPortfolioToolSnapshot(
            positions: store.positions, history: store.snapshotHistory, dailyProfit: store.dailyProfitHistory,
            trades: store.positionTrades, openings: store.positionOpeningBalances,
            reconciliations: store.positionReconciliations, asOf: now))
        let aiData = try #require((JSONSerialization.jsonObject(with: Data(ai.utf8)) as? [String: Any])?["data"] as? [String: Any])
        #expect(aiData["total_cost_cny"] is NSNull)
        #expect(aiData["realized_profit_cny"] is NSNull)
        let activity = try tool(restored, "list_transactions")
        let records = try #require(activity["records"] as? [[String: Any]])
        let sale = try #require(records.first { $0["record_id"] as? String == sold.id.uuidString })
        #expect(sale["effective_at"] as? String == sold.effectiveAt)
        #expect(sale["recorded_at"] as? String == sold.recordedAt)
        let request = try AIPortfolioToolRequest(call: LLMFunctionCall(
            callID: "review-transactions", name: AIPortfolioDataTool.transactions.rawValue, arguments: "{}"))
        let transactionJSON = AIPortfolioDataToolExecutor.execute(request, snapshot: AIPortfolioToolSnapshot(
            positions: store.positions, trades: store.positionTrades, openings: store.positionOpeningBalances,
            reconciliations: store.positionReconciliations, asOf: now))
        let aiRecords = try #require((JSONSerialization.jsonObject(with: Data(transactionJSON.utf8)) as? [String: Any])?["data"] as? [[String: Any]])
        #expect(aiRecords.first { $0["record_id"] as? String == sold.id.uuidString }?["effective_at"] as? String == sold.effectiveAt)
        // Undo after restore, verify checkpoint boundaries, then explicitly confirm the cost.
        try restored.reverseTrade(id: sold.id, now: now.addingTimeInterval(180))
        #expect(try holding(restored, cash.id).quantity == 1000)
        #expect(throws: (any Error).self) { try restored.reverseTrade(id: added.id, now: now.addingTimeInterval(240)) }
        _ = try restored.reconcilePosition(expected: holding(restored, original.id), quantity: 15,
            totalCost: 1200, reason: "correction", now: now.addingTimeInterval(300))
        #expect(try holding(restored, original.id).costIsKnown)
        #expect(try restored.exportDataPayload().holdings.first { $0.id == original.id.uuidString }?.costKnown != false)
    }

    @Test func backgroundHelperKeepsCashCheckpointAndDoesNotCreateIncome() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper = root.appendingPathComponent(".build/debug/PortfolixPriceUpdater")
        #expect(FileManager.default.isExecutableFile(atPath: helper.path))
        let repo = try PositionRepository(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundCheckpoint-\(UUID())/test.sqlite"))
        let cash = PositionClosureMath.cashPosition(currency: .usdt, quantity: 1000, name: "Test Cash")
        try repo.insert(cash)
        try repo.replaceDailySnapshots(positions: [cash], snapshotDate: now.addingTimeInterval(-86400))
        let record = try repo.reconcilePosition(expected: cash, quantity: 1010, totalCost: 1010,
            reason: "reconcile", now: now)
        try repo.setAppSetting(key: AutomaticPriceUpdateSchedule.enabledSettingKey, value: "true")
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--once"]
        var environment = ProcessInfo.processInfo.environment
        environment["PORTFOLIX_DATABASE_PATH"] = repo.storageURL.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try repo.appSetting(for: AutomaticPriceUpdateSchedule.lastResultSettingKey) == "no_eligible_assets")
        #expect(try holding(repo, cash.id).quantity == 1010)
        #expect(try repo.fetchReconciliations() == [record])
        #expect(try repo.fetchPositionTrades().isEmpty)
        #expect(try abs(profit(repo, through: now).doubleValue) < 0.000001)
        let daily = try tool(repo, "get_daily_profit", arguments: ["start_date": PositionClosureMath.day(now), "end_date": PositionClosureMath.day(now)])
        let amount = try #require((daily["days"] as? [[String: String]])?.first?["amount_cny"].flatMap(PositionClosureMath.decimal))
        #expect(abs(amount.doubleValue) < 0.000001)
    }
}
