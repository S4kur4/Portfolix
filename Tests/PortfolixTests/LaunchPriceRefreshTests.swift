import Foundation
import PortfolixCore
import Testing
@testable import Portfolix

@Suite("Launch price refresh", .timeLimit(.minutes(1)))
@MainActor
struct LaunchPriceRefreshTests {
    private func repository() throws -> PositionRepository {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Portfolix.LaunchRefresh.\(UUID())/portfolio.sqlite")
        return try PositionRepository(databaseURL: url)
    }

    private func holding(id: UUID = UUID(), symbol: String = "AAPL", quantity: Decimal = 2,
                         totalCost: Decimal = 200) -> Position {
        Position(id: id, name: "My \(symbol)", symbol: symbol, category: .usStock,
            quoteCurrency: .usd, quantity: quantity, totalCost: totalCost,
            averageCost: totalCost / quantity, latestPrice: 100,
            marketValueCNY: quantity * 100 / DisplayCurrency.usd.rateFromCNY,
            profitRate: 0, weeklyTrend: [100], source: "手工价格",
            quoteTime: "2026-11-01", fetchedAt: "2026-11-01T00:00:00Z", freshness: .manual)
    }

    private func waitForRefreshToFinish(_ store: PortfolioStore) async throws {
        let deadline = Date.now.addingTimeInterval(5)
        while store.isRefreshing && Date.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!store.isRefreshing)
    }

    @Test
    func firstLaunchRefreshesAllStarterHoldingsAndPersistsQuotes() async throws {
        let repo = try repository()
        try repo.initializeStarterPortfolioIfNeeded(language: .chinese)
        let original = try repo.fetchPositions()
        let provider = LaunchQuoteProvider()
        let store = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
        #expect(!store.backgroundUpdatesEnabled)
        await store.refreshPricesOnLaunchIfNeeded()
        #expect(Set(await provider.requestedSymbols()) == ["AAPL", "NVDA", "BTC/USDT"])
        let persisted = try repo.fetchPositions()
        #expect(persisted.allSatisfy { $0.latestPrice == 250 && $0.freshness == .updated })
        #expect(persisted.allSatisfy { position in
            let previous = original.first { $0.id == position.id }
            return previous?.quantity == position.quantity && previous?.totalCost == position.totalCost
        })
        #expect(store.positions.allSatisfy { $0.latestPrice == 250 })
        #expect(!store.isRefreshing)
        #expect(store.persistenceErrorMessage == nil)
    }

    @Test
    func repeatedRootAppearancesAndConcurrentCallsOnlyRefreshOncePerProcess() async throws {
        let repo = try repository()
        try repo.insert(holding())
        let provider = LaunchQuoteProvider(holdRequests: true)
        let store = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
        let first = Task { await store.refreshPricesOnLaunchIfNeeded() }
        await provider.waitForRequests(1)
        #expect(store.isRefreshing)
        await store.refreshPricesOnLaunchIfNeeded()
        await store.refreshPricesOnLaunchIfNeeded()
        #expect(await provider.requestedSymbols().count == 1)
        await provider.releaseRequests()
        await first.value
        await store.refreshPricesOnLaunchIfNeeded()
        #expect(await provider.requestedSymbols().count == 1)
    }

    @Test
    func reopeningAnAlreadyUpdatedLedgerRefreshesAgainWithANewStore() async throws {
        let repo = try repository()
        try repo.insert(holding())
        let provider = LaunchQuoteProvider()
        var first: PortfolioStore? = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
        await first?.refreshPricesOnLaunchIfNeeded()
        first = nil
        let reopened = PortfolioStore(positionRepository: try PositionRepository(databaseURL: repo.storageURL),
            marketDataProvider: provider)
        await reopened.refreshPricesOnLaunchIfNeeded()
        #expect(await provider.requestedSymbols() == ["AAPL", "AAPL"])
    }

    @Test(arguments: [true, false])
    func launchRefreshDoesNotChangeBackgroundSettingsOrNextScheduledTime(enabled: Bool) async throws {
        let repo = try repository()
        try repo.insert(holding())
        let settings = [
            AutomaticPriceUpdateSchedule.enabledSettingKey: enabled ? "true" : "false",
            AutomaticPriceUpdateSchedule.frequencySettingKey: "1 小时",
            AutomaticPriceUpdateSchedule.dailyTimeSettingKey: "540",
            AutomaticPriceUpdateSchedule.scheduleAnchorSettingKey: "2026-11-11T00:00:00Z",
            AutomaticPriceUpdateSchedule.lastRunSettingKey: "2026-11-11T00:30:00Z",
            AutomaticPriceUpdateSchedule.lastAttemptSettingKey: "2026-11-11T00:29:00Z",
            AutomaticPriceUpdateSchedule.lastSuccessSettingKey: "2026-11-11T00:30:00Z",
            AutomaticPriceUpdateSchedule.lastResultSettingKey: "success",
            AutomaticPriceUpdateSchedule.lastUpdatedCountSettingKey: "7",
            AutomaticPriceUpdateSchedule.lastFailedCountSettingKey: "0",
            AutomaticPriceUpdateSchedule.lastErrorSettingKey: "",
        ]
        for (key, value) in settings { try repo.setAppSetting(key: key, value: value) }
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-11-11T01:00:00Z"))
        func nextScheduledDelay() throws -> Int {
            AutomaticPriceUpdateSchedule.nextDelaySeconds(frequency: "1 小时",
                scheduleAnchor: try repo.appSetting(for: AutomaticPriceUpdateSchedule.scheduleAnchorSettingKey).flatMap(formatter.date(from:)),
                lastRun: try repo.appSetting(for: AutomaticPriceUpdateSchedule.lastRunSettingKey).flatMap(formatter.date(from:)), now: now)
        }
        let originalDelay = try nextScheduledDelay()
        let provider = LaunchQuoteProvider()
        let store = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
        await store.refreshPricesOnLaunchIfNeeded()
        #expect(await provider.requestedSymbols().count == 1)
        for (key, value) in settings { #expect(try repo.appSetting(for: key) == value) }
        #expect(try nextScheduledDelay() == originalDelay)
    }

    @Test
    func offlineFailureKeepsSavedPricesAndAllowsManualRetryOrANewLaunch() async throws {
        let repo = try repository()
        let saved = holding()
        try repo.insert(saved)
        let provider = LaunchQuoteProvider(failingSymbols: [saved.symbol])
        let store = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
        await store.refreshPricesOnLaunchIfNeeded()
        #expect(store.positions.first?.latestPrice == saved.latestPrice)
        #expect(store.positions.first?.fetchedAt == saved.fetchedAt)
        #expect(!store.isRefreshing)
        await store.refreshPricesOnLaunchIfNeeded()
        #expect(await provider.requestedSymbols().count == 1)
        await provider.allowSuccess()
        store.refresh()
        await provider.waitForRequests(2)
        try await waitForRefreshToFinish(store)
        #expect(store.positions.first?.latestPrice == 250)
        let reopened = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
        await reopened.refreshPricesOnLaunchIfNeeded()
        #expect(await provider.requestedSymbols().count == 3)
    }

    @Test
    func partialFailureDoesNotDiscardOtherSuccessfulQuotes() async throws {
        let repo = try repository()
        try repo.insert(holding())
        try repo.insert(holding(symbol: "NVDA"))
        let provider = LaunchQuoteProvider(failingSymbols: ["NVDA"])
        let store = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
        await store.refreshPricesOnLaunchIfNeeded()
        #expect(store.positions.first { $0.symbol == "AAPL" }?.latestPrice == 250)
        #expect(store.positions.first { $0.symbol == "NVDA" }?.latestPrice == 100)
        #expect(!store.isRefreshing)
        #expect(store.persistenceErrorMessage == nil)
    }

    @Test
    func launchRefreshCoalescesWithAnAlreadyRunningManualRefresh() async throws {
        let repo = try repository()
        try repo.insert(holding())
        let provider = LaunchQuoteProvider(holdRequests: true)
        let store = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
        store.refresh()
        await provider.waitForRequests(1)
        await store.refreshPricesOnLaunchIfNeeded()
        await provider.releaseRequests()
        try await waitForRefreshToFinish(store)
        await store.refreshPricesOnLaunchIfNeeded()
        #expect(await provider.requestedSymbols().count == 1)
        #expect(store.positions.first?.latestPrice == 250)
    }

    @Test
    func concurrentDatabaseWritesKeepTheLatestHoldingBalanceAndBackgroundSchedule() async throws {
        let repo = try repository()
        let saved = holding()
        try repo.insert(saved)
        let provider = LaunchQuoteProvider(holdRequests: true)
        let store = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
        let launch = Task { await store.refreshPricesOnLaunchIfNeeded() }
        await provider.waitForRequests(1)
        let otherConnection = try PositionRepository(databaseURL: repo.storageURL)
        try otherConnection.updateBalances([holding(id: saved.id, quantity: 3, totalCost: 285)])
        try otherConnection.setAppSetting(key: AutomaticPriceUpdateSchedule.lastRunSettingKey, value: "2026-11-11T01:00:00Z")
        await provider.releaseRequests()
        await launch.value
        let persisted = try #require(repo.fetchPositions().first)
        #expect(persisted.quantity == 3)
        #expect(persisted.totalCost == 285)
        #expect(persisted.latestPrice == 250)
        #expect(store.positions.first?.quantity == 3)
        #expect(try repo.appSetting(for: AutomaticPriceUpdateSchedule.lastRunSettingKey) == "2026-11-11T01:00:00Z")
    }

    @Test
    func cashOnlyOrEmptyLedgersDoNotMakePriceRequests() async throws {
        for hasCash in [true, false] {
            let repo = try repository()
            if hasCash { try repo.insert(PositionClosureMath.cashPosition(currency: .cny, quantity: 1000, name: "Cash")) }
            let provider = LaunchQuoteProvider()
            let store = PortfolioStore(positionRepository: repo, marketDataProvider: provider)
            await store.refreshPricesOnLaunchIfNeeded()
            #expect(await provider.requestedSymbols().isEmpty)
            #expect(!store.isRefreshing)
        }
    }
}

private actor LaunchQuoteProvider: AssetMarketDataProviding {
    private var calls: [String] = []
    private var failingSymbols: Set<String>
    private var holdRequests: Bool
    private var gates: [CheckedContinuation<Void, Never>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    init(failingSymbols: Set<String> = [], holdRequests: Bool = false) {
        self.failingSymbols = failingSymbols
        self.holdRequests = holdRequests
    }

    func searchAssets(keyword: String) async throws -> [AssetLookupCandidate] { [] }

    func resolveAsset(_ candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate {
        calls.append(candidate.symbol)
        let ready = observers.filter { $0.0 <= calls.count }
        observers.removeAll { $0.0 <= calls.count }
        ready.forEach { $0.1.resume() }
        if holdRequests { await withCheckedContinuation { gates.append($0) } }
        if failingSymbols.contains(candidate.symbol) { throw URLError(.notConnectedToInternet) }
        return AssetLookupCandidate(name: candidate.name, symbol: candidate.symbol, category: candidate.category,
            quoteCurrency: candidate.quoteCurrency, latestPrice: 250,
            upstreamSource: candidate.category == .crypto ? "OKX" : "东方财富", quoteTime: "2026-11-11T01:00:00Z")
    }

    func requestedSymbols() -> [String] { calls }
    func allowSuccess() { failingSymbols = [] }

    func waitForRequests(_ count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func releaseRequests() {
        holdRequests = false
        let pending = gates
        gates = []
        pending.forEach { $0.resume() }
    }
}
