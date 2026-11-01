import AppKit
import CSQLite
import SwiftUI
import Testing
@testable import Portfolix

@Suite("Legacy opening balances")
struct PositionOpeningBalanceTests {
    private func repository() throws -> PositionRepository {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Portfolix.OpeningTests.\(UUID())")
        let repo = try PositionRepository(databaseURL: folder.appendingPathComponent("test.sqlite"))
        try repo.setAppSetting(key: RiskProfilePersistence.updatedAtKey, value: "2026-01-01T00:00:00Z")
        return repo
    }

    private func asset(id: UUID = UUID(), quantity: Decimal = 10, cost: Decimal = 800) -> Position {
        Position(id: id, name: "Demo Legacy Fund", symbol: "DEMO", category: .fund,
            quoteCurrency: .cny, quantity: quantity, totalCost: cost, averageCost: cost / quantity,
            latestPrice: 130, marketValueCNY: quantity * 130, profitRate: cost == 0 ? 0 : (quantity * 130 / cost - 1) * 100,
            weeklyTrend: [120, 130], source: "手工价格", quoteTime: ISO8601DateFormatter().string(from: .now), freshness: .manual)
    }

    private func sql(_ command: String, in repo: PositionRepository) throws {
        #expect(repo.storageURL.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        var connection: OpaquePointer?
        #expect(sqlite3_open(repo.storageURL.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        #expect(sqlite3_exec(connection, command, nil, nil, nil) == SQLITE_OK)
    }

    private func seed() throws -> (PositionRepository, Position, Position) {
        let repo = try repository()
        let holding = asset()
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 1000, name: "Demo Cash")
        try repo.insert(holding); try repo.insert(cash)
        for ago in [2, 1, 0] {
            try repo.replaceDailySnapshots(positions: [holding, cash],
                snapshotDate: Calendar.current.date(byAdding: .day, value: -ago, to: .now)!)
        }
        return (repo, holding, cash)
    }

    @Test
    func migrationDoesNotTouchFinancialRecordsAndIsIdempotentAcrossRestarts() throws {
        let (repo, holding, cash) = try seed()
        let before = try repo.exportDataPayload()
        try sql("DELETE FROM position_opening_balances", in: repo)
        let reopened = try PositionRepository(databaseURL: repo.storageURL)
        let records = try reopened.fetchOpeningBalances()
        #expect(records.count == 2)
        #expect(records.first { $0.id == holding.id }?.units == 10)
        #expect(records.first { $0.id == holding.id }?.cost == 800)
        #expect(records.first { $0.id == cash.id }?.units == 1000)
        #expect(records.allSatisfy { !$0.requiresReview })
        try reopened.migrateOpeningBalances(now: .now.addingTimeInterval(600))
        #expect(try reopened.fetchOpeningBalances() == records)
        #expect(try PositionRepository(databaseURL: repo.storageURL).fetchOpeningBalances() == records)
        let after = try reopened.exportDataPayload()
        #expect(after.holdings == before.holdings)
        #expect(after.portfolioSnapshots == before.portfolioSnapshots)
        #expect(after.assetPriceSnapshots == before.assetPriceSnapshots)
        #expect(after.trades == before.trades)
    }

    @Test @MainActor
    func existingIncreaseAndPartialSaleRecoverTheOriginalBaseRatherThanTodaysBalance() throws {
        let (repo, holding, cash) = try seed()
        let buy = try repo.recordTrade(side: .buy, expected: holding, quantity: 2, price: 120, fees: 2,
            tradeDate: .now, cashPositionID: cash.id, cashName: cash.name)
        let increased = try #require(repo.fetchPositions().first { $0.id == holding.id })
        let sale = try repo.recordTrade(side: .sell, expected: increased, quantity: 3, price: 130, fees: 1,
            tradeDate: .now, cashPositionID: cash.id, cashName: cash.name)
        let before = try repo.exportDataPayload()
        try sql("DELETE FROM position_opening_balances", in: repo)
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        let opening = try #require(store.positionOpeningBalances.first { $0.id == holding.id })
        #expect(opening.units == 10)
        #expect(opening.cost == 800)
        #expect(!opening.requiresReview)
        #expect(store.positions.first { $0.id == holding.id }?.quantity == 9)
        #expect(store.positions.first { $0.id == holding.id }?.totalCost == Decimal(string: "781.5"))
        #expect(throws: PositionOpeningBalanceError.dependentRecords) { try repo.reverseOpeningBalance(id: holding.id) }
        #expect(try repo.exportDataPayload().holdings == before.holdings)
        #expect(try repo.exportDataPayload().portfolioSnapshots == before.portfolioSnapshots)
        try store.reverseRecord(PositionTransactionRow(sale))
        try store.reverseRecord(PositionTransactionRow(buy))
        #expect(store.positions.first { $0.id == holding.id }?.quantity == 10)
        #expect(store.positions.first { $0.id == cash.id }?.quantity == 1000)
        try store.reverseRecord(PositionTransactionRow(opening))
        #expect(store.positions.allSatisfy { $0.id != holding.id })
        #expect(store.positions.first { $0.id == cash.id }?.quantity == 1000)
        #expect(store.positionOpeningBalances.first { $0.id == holding.id }?.isReversed == true)
        try repo.migrateOpeningBalances()
        #expect(try repo.fetchOpeningBalances().first { $0.id == holding.id }?.isReversed == true)
    }

    @Test
    func aNewAssetAndItsSaleNeverReceiveADuplicateVisibleOpeningBalance() throws {
        let repo = try repository()
        let holding = asset(quantity: 2, cost: 200)
        _ = try repo.recordTrade(side: .add, expected: holding, quantity: 2, price: 100, fees: 0,
            tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        #expect(try repo.fetchOpeningBalances().allSatisfy { !$0.isVisible })
        let current = try #require(repo.fetchPositions().first)
        _ = try repo.recordTrade(side: .sell, expected: current, quantity: 2, price: 130, fees: 0,
            tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        #expect(try repo.fetchPositions().first?.quantity == 260)
        #expect(try repo.fetchOpeningBalances().allSatisfy { !$0.isVisible })
        let rows = try PositionTransactionRow.listed(trades: repo.fetchPositionTrades(), closures: [], openings: repo.fetchOpeningBalances())
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.kind != .opening })
    }

    @Test
    func backdatedEntriesUseEntryTimeTemplatesAndTradingTimeAllocations() throws {
        let (repo, holding, cash) = try seed()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        _ = try repo.recordTrade(side: .sell, expected: holding, quantity: 4, price: 120, fees: 2,
            tradeDate: .now, cashPositionID: cash.id, cashName: cash.name)
        let remaining = try #require(repo.fetchPositions().first { $0.id == holding.id })
        _ = try repo.recordTrade(side: .buy, expected: remaining, quantity: 2, price: 100, fees: 0,
            tradeDate: yesterday, cashPositionID: cash.id, cashName: cash.name)
        let before = try repo.exportDataPayload()
        try sql("DELETE FROM position_opening_balances", in: repo)
        try repo.migrateOpeningBalances()
        let opening = try #require(repo.fetchOpeningBalances().first { $0.id == holding.id })
        #expect(opening.units == 10)
        #expect(opening.cost.map { abs(($0 - 800).doubleValue) < 0.000001 } == true)
        #expect(!opening.requiresReview)
        #expect(try repo.exportDataPayload().holdings == before.holdings)
        #expect(try repo.exportDataPayload().portfolioSnapshots == before.portfolioSnapshots)
    }

    @Test
    func restoringAReversedOpeningDoesNotResurrectItsStaleHoldingOrPriceHistory() throws {
        let (repo, holding, _) = try seed()
        let earlier = try repo.exportDataPayload()
        try repo.reverseOpeningBalance(id: holding.id)
        let afterReversal = try repo.exportDataPayload()
        let restored = try repository()
        _ = try restored.importDataPayload(earlier)
        #expect(try restored.fetchPositions().contains { $0.id == holding.id })
        _ = try restored.importDataPayload(afterReversal)
        _ = try restored.importDataPayload(afterReversal)
        #expect(try restored.fetchPositions().allSatisfy { $0.id != holding.id })
        #expect(try restored.fetchAssetPriceSnapshots(positionID: holding.id).isEmpty)
        #expect(try restored.fetchOpeningBalances().first { $0.id == holding.id }?.isReversed == true)
    }

    @Test
    func importedOpeningFollowsTheResolvedAssetIdentity() throws {
        let (repo, holding, _) = try seed()
        let payload = try repo.exportDataPayload()
        let destination = try repository()
        let existing = asset(quantity: 1, cost: 50)
        try destination.insert(existing)
        _ = try destination.importDataPayload(payload)
        let openings = try destination.fetchOpeningBalances()
        #expect(openings.contains { $0.id == existing.id && $0.units == 10 && $0.cost == 800 })
        #expect(!openings.contains { $0.id == holding.id })
        _ = try destination.importDataPayload(payload)
        #expect(try destination.fetchOpeningBalances().count == openings.count)
        #expect(try destination.fetchPositions().first { $0.id == existing.id }?.quantity == 10)
    }

    @Test
    func legacyBackupImportAndNewArchiveRoundTripDoNotDuplicateOrReapplyOpenings() throws {
        let (repo, holding, _) = try seed()
        let exported = try repo.exportDataPayload()
        let legacy = PortfolixDataPackage.Payload(holdings: exported.holdings, portfolioSnapshots: exported.portfolioSnapshots,
            assetPriceSnapshots: exported.assetPriceSnapshots, riskProfile: exported.riskProfile, trades: exported.trades)
        let restored = try repository()
        _ = try restored.importDataPayload(legacy)
        let first = try restored.fetchOpeningBalances()
        #expect(first.count == 2)
        _ = try restored.importDataPayload(legacy)
        #expect(try restored.fetchOpeningBalances() == first)
        #expect(try restored.fetchPositions().first { $0.id == holding.id }?.quantity == 10)
        let archive = restored.storageURL.deletingLastPathComponent().appendingPathComponent("opening.zip")
        let payload = try restored.exportDataPayload()
        _ = try PortfolixDataPackageService.write(payload: payload, to: archive)
        let prepared = try PortfolixDataPackageService.prepareImport(from: archive)
        #expect(prepared.payload.openingBalances == first)
        let destination = try repository()
        _ = try destination.importDataPayload(prepared.payload)
        _ = try destination.importDataPayload(prepared.payload)
        #expect(try destination.fetchOpeningBalances() == first)
        #expect(try destination.exportDataPayload().holdings == payload.holdings)
        #expect(try destination.exportDataPayload().assetPriceSnapshots == payload.assetPriceSnapshots)
    }

    @Test
    func legacyClosuresRetainTheirAssetBaseAndDoNotCreditCashTwice() throws {
        let (repo, holding, cash) = try seed()
        let closure = try repo.closePosition(expected: holding, settlement: .init(executionPrice: 130, fees: 0, netProceeds: 1300),
            tradeDate: .now, cashPositionID: cash.id, cashName: cash.name)
        try repo.migrateOpeningBalances()
        let records = try repo.fetchOpeningBalances()
        #expect(records.first { $0.id == holding.id }?.units == 10)
        #expect(records.first { $0.id == cash.id }?.units == 1000)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 2300)
        #expect(throws: PositionOpeningBalanceError.dependentRecords) { try repo.reverseOpeningBalance(id: holding.id) }
        try repo.reversePositionClosure(id: closure.id)
        try repo.reverseOpeningBalance(id: holding.id)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 1000)
    }

    @Test
    func manualCorrectionsRequireExplicitReviewWithoutSilentlyChangingBalances() throws {
        let (repo, holding, cash) = try seed()
        _ = try repo.recordTrade(side: .buy, expected: holding, quantity: 2, price: 100, fees: 0,
            tradeDate: .now, cashPositionID: cash.id, cashName: cash.name)
        try repo.updateBalances([asset(id: holding.id, quantity: 13, cost: 1000)])
        try sql("DELETE FROM position_opening_balances", in: repo)
        try repo.migrateOpeningBalances()
        let opening = try #require(repo.fetchOpeningBalances().first { $0.id == holding.id })
        #expect(opening.requiresReview)
        #expect(opening.units == 11)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.quantity == 13)
        #expect(throws: PositionOpeningBalanceError.needsReview) { try repo.reverseOpeningBalance(id: holding.id) }
        #expect(throws: PositionOpeningBalanceError.changed) { try repo.confirmOpeningBalance(id: holding.id, quantity: 10, totalCost: 800) }
        try repo.confirmOpeningBalance(id: holding.id, quantity: 11, totalCost: 800)
        #expect(try repo.fetchOpeningBalances().first { $0.id == holding.id }?.requiresReview == false)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.quantity == 13)
    }

    @Test
    func partialMigrationFailureRollsBackAllOpeningRecordsOnly() throws {
        let (repo, _, _) = try seed()
        let positions = try repo.fetchPositions()
        try sql("CREATE TRIGGER reject_opening BEFORE INSERT ON position_opening_balances BEGIN SELECT RAISE(ABORT, 'fixture'); END", in: repo)
        #expect(throws: (any Error).self) { try repo.migrateOpeningBalances() }
        #expect(try repo.fetchOpeningBalances().isEmpty)
        let after = try repo.fetchPositions().map { PortfolixDataPackage.Holding(position: $0, timestamp: "2026-01-01T00:00:00Z") }
        #expect(after == positions.map { PortfolixDataPackage.Holding(position: $0, timestamp: "2026-01-01T00:00:00Z") })
    }

    @Test
    func unrepresentableInferredBalancesBecomeReviewRecordsInsteadOfFailingStartup() throws {
        let holding = asset(quantity: Decimal(string: "1e28")!, cost: 0)
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 1, name: "Cash")
        let trades = (1...2).map { sequence in
            PositionTradeRecord(id: UUID(), sequence: sequence, side: .sell,
                asset: .init(position: holding, timestamp: timestamp), cash: .init(position: cash, timestamp: timestamp),
                tradeDate: PositionClosureMath.day(.now), quantity: "1e28", executionPrice: "0", fees: "0", cashAmount: "0",
                allocatedCost: "0", rateFromCNY: "1", recordedAt: timestamp, priceHistory: [])
        }
        let opening = try #require(PositionOpeningBalanceMath.reconstruct(positions: [], trades: trades, closures: [],
            recordedAt: timestamp).first { $0.id == holding.id })
        #expect(opening.requiresReview)
        #expect(opening.quantity == nil)
        #expect(opening.totalCost == nil)
        try opening.validate()
    }

    @Test @MainActor
    func migratedRecordsUseTheirRealRecordingTimeWithoutInventingAPurchaseDate() throws {
        let (repo, _, _) = try seed()
        try repo.migrateOpeningBalances()
        let first = try #require(repo.fetchOpeningBalances().first)
        let later = PositionOpeningBalanceRecord(id: first.id, holding: first.holding,
            quantity: first.quantity, totalCost: first.totalCost, requiresReview: false,
            recordedAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(60)))
        let rows = PositionTransactionRow.listed(trades: [], closures: [],
            openings: try repo.fetchOpeningBalances().filter { $0.id != first.id } + [later])
        #expect(rows.first?.id == later.id)
        #expect(rows.first?.displayNumber == rows.count)
        #expect(rows.first?.recordedAt == ISO8601DateFormatter().date(from: later.recordedAt))
        let request = try AIPortfolioToolRequest(call: .init(callID: "opening", name: "list_transactions", arguments: "{}"))
        let data = AIPortfolioDataToolExecutor.execute(request, snapshot: .init(positions: [], openings: [later]))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any])
        let record = try #require((json["data"] as? [[String: Any]])?.first)
        #expect(record["trade_date"] is NSNull)
        #expect(record["is_transaction"] as? Bool == false)
        #expect(record["cash_amount"] as? String == "0")
    }

    @Test @MainActor
    func reviewSheetFitsBothLanguagesAndAppearances() throws {
        let (repo, _, _) = try seed()
        try repo.migrateOpeningBalances()
        let record = try #require(repo.fetchOpeningBalances().first)
        for language: AppLanguage in [.chinese, .english] {
            let store = PortfolioStore(positionRepository: repo, initialLanguage: language)
            for scheme: ColorScheme in [.light, .dark] {
                let view = NSHostingView(rootView: PositionOpeningBalanceSheet(record: record).environment(store).environment(\.colorScheme, scheme))
                #expect(view.fittingSize == CGSize(width: 620, height: 400))
            }
        }
    }
}
