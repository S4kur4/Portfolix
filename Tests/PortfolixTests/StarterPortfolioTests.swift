import CSQLite
import Foundation
import Testing
@testable import Portfolix

@Suite("First launch sample holdings")
struct StarterPortfolioTests {
    private func databaseURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Portfolix.StarterTests.\(UUID())/portfolio.sqlite")
    }

    private func sql(_ command: String, at url: URL) throws {
        var connection: OpaquePointer?
        try #require(sqlite3_open(url.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        try #require(sqlite3_exec(connection, command, nil, nil, nil) == SQLITE_OK)
    }

    private func userHolding(symbol: String = "MSFT") -> Position {
        Position(name: "My holding", symbol: symbol, category: .usStock, quoteCurrency: .usd,
            quantity: 2, averageCost: 100, latestPrice: 100,
            marketValueCNY: 200 / DisplayCurrency.usd.rateFromCNY, profitRate: 0,
            weeklyTrend: [100], source: "手工价格", quoteTime: "2026-11-01", freshness: .manual)
    }

    @Test
    func newLedgerHasThreeClearlyMarkedHoldingsAndOnlyOneDayOfHistory() throws {
        let repository = try PositionRepository(databaseURL: databaseURL())
        // Background readers and injected stores do not create examples themselves.
        #expect(try repository.fetchPositions().isEmpty)
        let now = Date.now
        try repository.initializeStarterPortfolioIfNeeded(language: .chinese, now: now)
        let positions = try repository.fetchPositions()
        #expect(Set(positions.map(\.symbol)) == ["AAPL", "NVDA", "BTC/USDT"])
        #expect(positions.allSatisfy { $0.name.contains("示例") && $0.freshness == .manual })
        #expect(positions.allSatisfy { $0.quantity > 0 && $0.marketValueCNY > 0 && $0.profitRate == 0 })
        #expect(positions.allSatisfy { $0.marketValueCNY == $0.quantity * $0.latestPrice / $0.quoteCurrency.rateFromCNY })
        #expect(try repository.fetchPositionTrades().isEmpty)
        let payload = try repository.exportDataPayload()
        #expect(payload.portfolioSnapshots.count == 1)
        #expect(payload.assetPriceSnapshots.count == 3)
        #expect(Set(payload.assetPriceSnapshots.map(\.date)).count == 1)
        #expect(payload.portfolioSnapshots.first?.totalProfitCNY == "0")
        #expect(try repository.fetchOpeningBalances().count == 3)
        #expect(try repository.fetchDailyProfitPoints().allSatisfy { $0.amountCNY == 0 })
        #expect(try repository.starterPositionIDs() == Set(positions.map(\.id)))
    }

    @Test
    func aLaterLaunchKeepsIdentityAndDoesNotReseedDeletedExamples() throws {
        let url = databaseURL()
        var first: PositionRepository? = try PositionRepository(databaseURL: url)
        try first?.initializeStarterPortfolioIfNeeded(language: .english)
        let original = try #require(first).fetchPositions()
        #expect(original.allSatisfy { $0.name.contains("(Sample)") })
        first = nil
        let reopened = try PositionRepository(databaseURL: url)
        try reopened.initializeStarterPortfolioIfNeeded(language: .chinese)
        #expect(try reopened.fetchPositions().map(\.id) == original.map(\.id))
        try reopened.delete(positionIDs: original.map(\.id))
        #expect(try reopened.fetchOpeningBalances().isEmpty)
        #expect(try reopened.fetchPortfolioSnapshots().isEmpty)
        let final = try PositionRepository(databaseURL: url)
        try final.initializeStarterPortfolioIfNeeded(language: .english)
        #expect(try final.fetchPositions().isEmpty)
        #expect(try final.starterPositionIDs().isEmpty)
    }

    @Test
    func anExistingEmptyLedgerRemainsEmpty() throws {
        let repository = try PositionRepository(databaseURL: databaseURL())
        // Legacy installations have a schema but no starter initialization marker.
        try sql("DELETE FROM app_settings", at: repository.storageURL)
        let reopened = try PositionRepository(databaseURL: repository.storageURL)
        try reopened.initializeStarterPortfolioIfNeeded(language: .chinese)
        #expect(try reopened.fetchPositions().isEmpty)
        #expect(try reopened.fetchPortfolioSnapshots().isEmpty)
    }

    @Test
    func userDataWrittenBeforeTheUIStartsPreventsInitialization() throws {
        let repository = try PositionRepository(databaseURL: databaseURL())
        let holding = userHolding()
        try repository.insert(holding)
        try repository.initializeStarterPortfolioIfNeeded(language: .chinese)
        #expect(try repository.fetchPositions().map(\.id) == [holding.id])
        #expect(try repository.starterPositionIDs().isEmpty)
        try repository.delete(positionIDs: [holding.id])
        try repository.initializeStarterPortfolioIfNeeded(language: .chinese)
        #expect(try repository.fetchPositions().isEmpty)
    }

    @Test
    func initializationRollsBackCompletelyAndCanRetryAfterFailure() throws {
        let repository = try PositionRepository(databaseURL: databaseURL())
        try sql("CREATE TRIGGER reject_example BEFORE INSERT ON assets WHEN NEW.symbol = 'NVDA' BEGIN SELECT RAISE(ABORT, 'test failure'); END", at: repository.storageURL)
        #expect(throws: (any Error).self) { try repository.initializeStarterPortfolioIfNeeded(language: .chinese) }
        #expect(try repository.fetchPositions().isEmpty)
        #expect(try repository.fetchOpeningBalances().isEmpty)
        #expect(try repository.starterPositionIDs().isEmpty)
        try sql("DROP TRIGGER reject_example", at: repository.storageURL)
        try repository.initializeStarterPortfolioIfNeeded(language: .chinese)
        #expect(try repository.fetchPositions().count == 3)
    }

    @Test @MainActor
    func examplesCanBeEditedAndDeletedThroughTheStoreAfterRestart() throws {
        let repository = try PositionRepository(databaseURL: databaseURL())
        try repository.initializeStarterPortfolioIfNeeded(language: .chinese)
        let reopened = try PositionRepository(databaseURL: repository.storageURL)
        let store = PortfolioStore(positionRepository: reopened, initialLanguage: .chinese)
        let apple = try #require(store.positions.first { $0.symbol == "AAPL" })
        #expect(store.directlyDeletablePositionIDs == Set(store.positions.map(\.id)))
        try store.updatePosition(id: apple.id, name: "My Apple", symbol: apple.symbol,
            category: apple.category, quantity: 3, averageCost: 150,
            quoteCurrency: apple.quoteCurrency, latestPrice: 210)
        #expect(store.positions.first { $0.id == apple.id }?.name == "My Apple")
        #expect(store.positions.first { $0.id == apple.id }?.quantity == 3)
        try store.deletePositions(for: Set(store.positions.map(\.id)))
        #expect(store.positions.isEmpty)
        #expect(store.positionOpeningBalances.isEmpty)
        let final = try PositionRepository(databaseURL: repository.storageURL)
        try final.initializeStarterPortfolioIfNeeded(language: .english)
        #expect(try final.fetchPositions().isEmpty)
    }

    @Test @MainActor
    func aRealTradeRetainsTheExistingDeletionProtection() throws {
        let repository = try PositionRepository(databaseURL: databaseURL())
        try repository.initializeStarterPortfolioIfNeeded(language: .chinese)
        let apple = try #require(repository.fetchPositions().first { $0.symbol == "AAPL" })
        _ = try repository.recordTrade(side: .add, expected: apple, quantity: 1, price: 200,
            fees: 0, tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        #expect(throws: PositionTradeError.recordedTradesExist) { try repository.delete(positionIDs: [apple.id]) }
        let store = PortfolioStore(positionRepository: repository, initialLanguage: .chinese)
        #expect(!store.directlyDeletablePositionIDs.contains(apple.id))
        #expect(throws: PositionTradeError.recordedTradesExist) { try store.deletePosition(for: apple.id) }
    }

    @Test
    func restoringABackupReplacesUntouchedExamplesAndDoesNotAddAPhantomDay() throws {
        let source = try PositionRepository(databaseURL: databaseURL())
        let apple = userHolding(symbol: "AAPL")
        try source.insert(apple)
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: .now))
        try source.replaceDailySnapshots(positions: [apple], snapshotDate: yesterday)
        let payload = try source.exportDataPayload()
        let destination = try PositionRepository(databaseURL: databaseURL())
        try destination.initializeStarterPortfolioIfNeeded(language: .chinese)
        _ = try destination.importDataPayload(payload)
        try destination.initializeStarterPortfolioIfNeeded(language: .chinese)
        #expect(try destination.fetchPositions().map(\.id) == [apple.id])
        #expect(try destination.starterPositionIDs().isEmpty)
        let restored = try destination.exportDataPayload()
        #expect(restored.holdings == payload.holdings)
        #expect(restored.portfolioSnapshots == payload.portfolioSnapshots)
        #expect(restored.assetPriceSnapshots == payload.assetPriceSnapshots)
        #expect(restored.openingBalances == payload.openingBalances)
    }

    @Test
    func restoringABackupPreservesAnExampleTheUserHasEdited() throws {
        let destination = try PositionRepository(databaseURL: databaseURL())
        try destination.initializeStarterPortfolioIfNeeded(language: .english)
        let apple = try #require(destination.fetchPositions().first { $0.symbol == "AAPL" })
        let edited = Position(id: apple.id, name: "My Apple", symbol: apple.symbol, category: apple.category,
            quoteCurrency: apple.quoteCurrency, quantity: 2, averageCost: 100, latestPrice: 200,
            marketValueCNY: 400 / apple.quoteCurrency.rateFromCNY, profitRate: 100,
            weeklyTrend: [200], source: "手工价格", quoteTime: apple.quoteTime, freshness: .manual)
        try destination.update(edited)
        try destination.replaceDailySnapshots(positions: destination.fetchPositions())
        let source = try PositionRepository(databaseURL: databaseURL())
        try source.insert(userHolding())
        _ = try destination.importDataPayload(source.exportDataPayload())
        #expect(Set(try destination.fetchPositions().map(\.symbol)) == ["AAPL", "MSFT"])
        #expect(try destination.fetchPositions().first { $0.id == apple.id }?.name == "My Apple")
    }

    @Test
    func aRejectedImportRestoresExamplesAndTheirHistoryAtomically() throws {
        let destination = try PositionRepository(databaseURL: databaseURL())
        try destination.initializeStarterPortfolioIfNeeded(language: .chinese)
        let apple = try #require(destination.fetchPositions().first { $0.symbol == "AAPL" })
        _ = try destination.recordTrade(side: .add, expected: apple, quantity: 1, price: 200,
            fees: 0, tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        let before = try destination.exportDataPayload()
        let source = try PositionRepository(databaseURL: databaseURL())
        try source.insert(userHolding())
        #expect(throws: (any Error).self) { _ = try destination.importDataPayload(source.exportDataPayload()) }
        let after = try destination.exportDataPayload()
        #expect(after.holdings == before.holdings)
        #expect(after.portfolioSnapshots == before.portfolioSnapshots)
        #expect(after.assetPriceSnapshots == before.assetPriceSnapshots)
        #expect(try destination.starterPositionIDs().count == 3)
    }

    @Test
    func restoringBeforeInitializationSuppressesExamplesEvenForAnEmptyBackup() throws {
        let source = try PositionRepository(databaseURL: databaseURL())
        let destination = try PositionRepository(databaseURL: databaseURL())
        _ = try destination.importDataPayload(source.exportDataPayload())
        try destination.initializeStarterPortfolioIfNeeded(language: .chinese)
        #expect(try destination.fetchPositions().isEmpty)
    }
}
