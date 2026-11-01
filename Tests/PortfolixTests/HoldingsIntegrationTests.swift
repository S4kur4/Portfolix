import Foundation
import PortfolixCore
import PortfolixMCPKit
import Testing
@testable import Portfolix

@Suite("Holdings integration and stablecoin cash")
struct HoldingsIntegrationTests {
    private func repository() throws -> PositionRepository {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Portfolix.HoldingsIntegration.\(UUID())")
        let repo = try PositionRepository(databaseURL: folder.appendingPathComponent("test.sqlite"))
        try repo.setAppSetting(key: RiskProfilePersistence.updatedAtKey, value: "2026-01-01T00:00:00Z")
        return repo
    }

    private func mcp(_ repo: PositionRepository) throws -> PortfolioMCPServer {
        try repo.setAppSetting(key: MCPAccess.settingKey, value: "true")
        let server = PortfolioMCPServer(databaseURL: repo.storageURL)
        _ = server.respond(to: Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"SyntheticFixture","version":"1"}}}"#.utf8))
        _ = server.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        return server
    }

    private func call(_ server: PortfolioMCPServer, _ name: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        let response = try #require(server.respond(to: JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": name, "arguments": args]])))
        let object = try #require(try JSONSerialization.jsonObject(with: response) as? [String: Any])
        let result = try #require(object["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        return try #require(result["structuredContent"] as? [String: Any])
    }

    @MainActor private func agent(_ store: PortfolioStore, _ name: String) throws -> [String: Any] {
        let request = try AIPortfolioToolRequest(call: .init(callID: "fixture", name: name, arguments: "{}"))
        let text = AIPortfolioDataToolExecutor.execute(request, snapshot: .init(
            positions: store.positions, closures: store.positionClosures, trades: store.positionTrades, openings: store.positionOpeningBalances))
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test
    func usdcRemainsCryptoWhileUsdtCashUsesTheExistingCurrency() throws {
        #expect(CashAssetLookup.search(keyword: "USDC").isEmpty)
        #expect(CashAssetLookup.stablecoins(keyword: "USDC").isEmpty)
        #expect(CashAssetLookup.stablecoins(keyword: "USD").isEmpty)
        #expect(CashAssetLookup.stablecoins(keyword: "BTC/USDC").isEmpty)
        #expect(CashAssetLookup.search(keyword: "USDCBTC").isEmpty)
        let position = Position(name: "USDC", symbol: "USDC/USDT", category: .crypto, quoteCurrency: .usdt,
            quantity: 100, averageCost: 1, latestPrice: 1, marketValueCNY: 100 / DisplayCurrency.usdt.rateFromCNY,
            profitRate: 0, weeklyTrend: [], source: "OKX", quoteTime: "2026-10-31", freshness: .updated)
        #expect(MarketDataAdapter.supportsQuote(for: position))
        let risk = RiskConstraintEvaluation.evaluate(positions: [position], positionLimit: 100, cryptoLimit: 0,
            foreignCurrencyLimit: 100, liquidityMinimum: 100)
        #expect(risk.cryptoAllocationPercent == 100)
        #expect(risk.cashAllocationPercent == 0)
        let instruments = [
            OKXSpotInstrument(instId: "USDC-USDT", baseCcy: "USDC", quoteCcy: "USDT", state: "live"),
            OKXSpotInstrument(instId: "BTC-USDC", baseCcy: "BTC", quoteCcy: "USDC", state: "live"),
        ]
        let candidate = try #require(OKXClient.candidates(matching: "USDC", in: instruments).first)
        #expect(candidate.name == "USDC" && candidate.category == .crypto && candidate.quoteCurrency == .usdt)
        #expect(OKXClient.candidates(matching: "BTC", in: instruments).isEmpty)
        #expect(try #require(CashAssetLookup.search(keyword: "USDT").first).quoteCurrency == .usdt)
    }

    @Test @MainActor
    func displayCurrencyChoicesRemainFixedAcrossHoldingChanges() throws {
        let repo = try repository()
        let store = PortfolioStore(positionRepository: repo, credentialStore: NoIntegrationCredentials())
        let currencies = DisplayCurrency.allCases
        #expect(currencies == [.cny, .hkd, .usd, .usdt])
        var records: [PositionTradeRecord] = []
        for currency: DisplayCurrency in [.hkd, .usdt] {
            let cash = PositionClosureMath.cashPosition(currency: currency, quantity: 1, name: currency.rawValue)
            try store.recordTrade(id: UUID(), side: .add, position: cash, quantity: 100, price: 1, fees: 0,
                tradeDate: .now, cashPositionID: nil)
            records.append(try #require(store.positionTrades.first { $0.asset.id == cash.id.uuidString }))
        }
        #expect(DisplayCurrency.allCases == currencies)
        let cash = try #require(store.positions.first { $0.quoteCurrency == .usdt })
        try store.recordTrade(id: UUID(), side: .withdraw, position: cash, quantity: 100, price: 1, fees: 0,
            tradeDate: .now, cashPositionID: nil)
        #expect(DisplayCurrency.allCases == currencies)
        try store.reverseTrade(#require(store.positionTrades.first { $0.side == .withdraw }))
        for record in records { try store.reverseTrade(record) }
        #expect(DisplayCurrency.allCases == currencies)
        store.displayCurrency = .usdt
        #expect(store.displayCurrency == .usdt)
    }

    @Test @MainActor
    func appAgentMCPAndBackupAgreeThroughoutTheAssetLifecycle() throws {
        let repo = try repository()
        let store = PortfolioStore(positionRepository: repo, credentialStore: NoIntegrationCredentials())
        let cash = PositionClosureMath.cashPosition(currency: .usdt, quantity: 1, name: "Synthetic USDT")
        try store.recordTrade(id: UUID(), side: .add, position: cash, quantity: 1000, price: 1, fees: 0,
            tradeDate: .now, cashPositionID: nil)
        let security = Position(name: "Synthetic Bitcoin", symbol: "BTC/USDT", category: .crypto,
            quoteCurrency: .usdt, quantity: 1, averageCost: 100, latestPrice: 120,
            marketValueCNY: 120 / DisplayCurrency.usdt.rateFromCNY, profitRate: 20,
            weeklyTrend: [], source: "手工价格", quoteTime: ISO8601DateFormatter().string(from: .now), freshness: .manual)
        try store.recordTrade(id: UUID(), side: .buy, position: security, quantity: 2, price: 100, fees: 1,
            tradeDate: .now, cashPositionID: cash.id)
        let server = try mcp(repo)
        let first = try #require(store.positions.first { $0.id == security.id })
        #expect(first.quantity == 2 && first.totalCost == 201)
        try store.recordTrade(id: UUID(), side: .sell, position: first, quantity: 1, price: 125, fees: 1,
            tradeDate: .now, cashPositionID: cash.id)
        #expect((try agent(store, "list_closed_holdings")["data"] as? [Any])?.isEmpty == true)
        #expect((try call(server, "list_closed_holdings")["records"] as? [Any])?.isEmpty == true)
        let remaining = try #require(store.positions.first { $0.id == security.id })
        #expect(remaining.quantity == 1 && remaining.totalCost == Decimal(string: "100.5"))
        try store.recordTrade(id: UUID(), side: .sell, position: remaining, quantity: 1, price: 130, fees: 1,
            tradeDate: .now, cashPositionID: cash.id)
        let cashAfterSale = try #require(store.positions.first)
        #expect(store.positions.count == 1 && cashAfterSale.quantity == 1052)
        #expect(store.aiTodayReturnStatus(asOf: .now) == "available")
        let withdrawalID = UUID()
        try store.recordTrade(id: withdrawalID, side: .withdraw, position: cashAfterSale, quantity: 52, price: 1, fees: 0,
            tradeDate: .now, cashPositionID: nil)
        let realized = 52 / DisplayCurrency.usdt.rateFromCNY
        #expect(abs((store.realizedProfitCNY - realized).doubleValue) < 0.000001)
        let aiSummary = try #require(try agent(store, "get_portfolio_summary")["data"] as? [String: Any])
        let mcpSummary = try call(server, "get_portfolio_summary")
        #expect(aiSummary["closed_holding_count"] as? Int == 1)
        #expect(mcpSummary["closed_holding_count"] as? String == "1")
        #expect(aiSummary["transaction_count"] as? Int == 5)
        #expect(mcpSummary["transaction_count"] as? String == "5")
        #expect(aiSummary["realized_profit_cny"] as? String == mcpSummary["realized_profit_cny"] as? String)
        #expect((try agent(store, "list_closed_holdings")["data"] as? [Any])?.count == 2)
        #expect((try call(server, "list_closed_holdings")["records"] as? [Any])?.count == 2)
        let transactions = try #require(try call(server, "list_transactions")["records"] as? [[String: Any]])
        let withdrawal = try #require(transactions.first { $0["side"] as? String == "withdraw" })
        #expect(withdrawal["currency"] as? String == "USDT")
        #expect(withdrawal["portfolio_flow"] as? String == "external_out")
        #expect(withdrawal["realized_profit_quote"] is NSNull)
        #expect(withdrawal["execution_price"] is NSNull)
        let archive = repo.storageURL.deletingLastPathComponent().appendingPathComponent("backup.zip")
        try repo.setAppSetting(key: "synthetic_secret_do_not_export", value: "NOT_A_REAL_KEY")
        _ = try PortfolixDataPackageService.write(payload: repo.exportDataPayload(), to: archive)
        let payload = try PortfolixDataPackageService.prepareImport(from: archive).payload
        #expect(!String(decoding: try JSONEncoder().encode(payload), as: UTF8.self).contains("NOT_A_REAL_KEY"))
        let restored = try repository()
        _ = try restored.importDataPayload(payload)
        _ = try restored.importDataPayload(payload)
        let restoredStore = PortfolioStore(positionRepository: restored, credentialStore: NoIntegrationCredentials())
        #expect(restoredStore.positions.first?.quantity == 1000)
        #expect(restoredStore.positionTrades.count == 5)
        #expect(restoredStore.realizedProfitCNY == store.realizedProfitCNY)
        #expect(restoredStore.dailyProfitHistory.map(\.amountCNY) == store.dailyProfitHistory.map(\.amountCNY))
        #expect(restoredStore.aiTodayReturnStatus(asOf: .now) == "available")
        let restoredSummary = try call(mcp(restored), "get_portfolio_summary")
        #expect(restoredSummary["realized_profit_cny"] as? String == mcpSummary["realized_profit_cny"] as? String)
        let withdrawalRecord = try #require(restoredStore.positionTrades.first { $0.id == withdrawalID })
        try restoredStore.reverseTrade(withdrawalRecord)
        #expect(restoredStore.positions.first?.quantity == 1052)
        #expect(restoredStore.realizedProfitCNY == store.realizedProfitCNY)
        #expect((try call(mcp(restored), "list_transactions")["records"] as? [Any])?.count == 4)
        let lastSale = try #require(restoredStore.positionTrades.first { $0.side == .sell && $0.price == 130 })
        try restoredStore.reverseTrade(lastSale)
        #expect(restoredStore.positions.first { $0.id == security.id }?.quantity == 1)
        #expect((try agent(restoredStore, "list_closed_holdings")["data"] as? [Any])?.isEmpty == true)
        #expect((try call(mcp(restored), "list_closed_holdings")["records"] as? [Any])?.isEmpty == true)
    }

    @Test @MainActor
    func legacyOpeningBalancesAndClosuresAreVisibleWithoutBeingCountedAsNewPurchases() throws {
        let repo = try repository()
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 1000, name: "Synthetic Cash")
        let asset = Position(name: "Legacy Asset", symbol: "LEGACY", category: .cnStock, quoteCurrency: .cny,
            quantity: 2, averageCost: 100, latestPrice: 110, marketValueCNY: 220, profitRate: 10,
            weeklyTrend: [], source: "手工价格", quoteTime: ISO8601DateFormatter().string(from: .now), freshness: .manual)
        try repo.insert(cash); try repo.insert(asset)
        try repo.migrateOpeningBalances()
        let store = PortfolioStore(positionRepository: repo, credentialStore: NoIntegrationCredentials())
        let before = try call(mcp(repo), "get_portfolio_summary")
        #expect(before["transaction_count"] as? String == "0")
        #expect(before["opening_balance_count"] as? String == "2")
        try store.closePosition(asset, settlement: .init(executionPrice: 120, fees: 1, netProceeds: 239),
            tradeDate: .now, cashPositionID: cash.id)
        let summary = try call(mcp(repo), "get_portfolio_summary")
        #expect(summary["realized_profit_cny"] as? String == "39")
        #expect(summary["transaction_count"] as? String == "1")
        #expect((try agent(store, "list_closed_holdings")["data"] as? [Any])?.count == 1)
        let rows = try #require(try call(mcp(repo), "list_transactions")["records"] as? [[String: Any]])
        #expect(rows.filter { $0["side"] as? String == "opening" }.count == 2)
        #expect(rows.first { $0["side"] as? String == "opening" }?["trade_date"] is NSNull)
        let saved = try repo.exportDataPayload()
        let restored = try repository()
        _ = try restored.importDataPayload(saved)
        _ = try restored.importDataPayload(saved)
        let restoredStore = PortfolioStore(positionRepository: restored, credentialStore: NoIntegrationCredentials())
        #expect(restoredStore.realizedProfitCNY == 39)
        #expect(restoredStore.positions.first?.quantity == 1239)
    }

    @Test
    func mcpLedgerPaginationSearchRevocationAndReadOnlyBoundaryArePreserved() throws {
        let repo = try repository()
        let cash = PositionClosureMath.cashPosition(currency: .usdt, quantity: 1, name: "USDT_100%")
        _ = try repo.recordTrade(side: .add, expected: cash, quantity: 100, price: 1, fees: 0,
            tradeDate: .now, cashPositionID: nil, cashName: cash.name)
        _ = try repo.recordTrade(side: .withdraw, expected: #require(repo.fetchPositions().first), quantity: 10,
            price: 1, fees: 0, tradeDate: .now, cashPositionID: nil, cashName: cash.name)
        let server = try mcp(repo)
        let first = try call(server, "list_transactions", ["limit": 1, "query": "_100%"])
        #expect(first["matched_count"] as? String == "2")
        #expect(first["next_offset"] as? Int == 1)
        let second = try call(server, "list_transactions", ["limit": 1, "offset": 1, "query": "_100%"])
        #expect(second["next_offset"] is NSNull)
        #expect((first["records"] as? [[String: Any]])?.first?["number"] as? String == "2")
        #expect((second["records"] as? [[String: Any]])?.first?["number"] as? String == "1")
        #expect((try call(server, "list_transactions", ["query": "' OR 1=1 --"])["records"] as? [Any])?.isEmpty == true)
        let original = try repo.exportDataPayload()
        try repo.setAppSetting(key: MCPAccess.settingKey, value: "false")
        let denied = try #require(server.respond(to: Data(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_transactions","arguments":{}}}"#.utf8)))
        #expect(String(decoding: denied, as: UTF8.self).contains("Read access is disabled"))
        #expect(try repo.exportDataPayload() == original)
    }

    @Test
    func backgroundUpdaterUsesCurrentCashBalancesAndCorrectsStaleSameDaySnapshots() throws {
        let repo = try repository()
        let cash = PositionClosureMath.cashPosition(currency: .usdt, quantity: 100, name: "Synthetic USDT")
        try repo.insert(cash)
        _ = try repo.recordTrade(side: .withdraw, expected: cash, quantity: 40, price: 1, fees: 0,
            tradeDate: .now, cashPositionID: nil, cashName: cash.name)
        // Simulate an outdated same-day snapshot while the live ledger balance is already 60.
        try repo.replaceDailySnapshots(positions: [cash])
        try repo.setAppSetting(key: AutomaticPriceUpdateSchedule.enabledSettingKey, value: "true")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = root.appendingPathComponent(".build/debug/PortfolixPriceUpdater")
        process.arguments = ["--once"]
        process.environment = ["PORTFOLIX_DATABASE_PATH": repo.storageURL.path, "PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
        defer { watchdog.cancel() }
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let snapshot = try #require(repo.fetchAssetPriceSnapshots(positionID: cash.id).last)
        #expect(snapshot.quantity == 60)
        #expect(abs((snapshot.marketValueCNY - 60 / DisplayCurrency.usdt.rateFromCNY).doubleValue) < 0.0000001)
        #expect(try repo.fetchPositions().first?.quantity == 60)
        #expect(try repo.fetchPositionTrades().count == 1)
    }

    @Test @MainActor
    func usdcCryptoCostsQuotesAndRecordsSurviveBackupRestore() throws {
        let repo = try repository()
        let legacy = Position(name: "Legacy USDC", symbol: "USDC/USDT", category: .crypto, quoteCurrency: .usdt,
            quantity: 100, averageCost: Decimal(string: "0.9998")!, latestPrice: Decimal(string: "1.0002")!,
            marketValueCNY: 100 * Decimal(string: "1.0002")! / DisplayCurrency.usdt.rateFromCNY,
            profitRate: 0, weeklyTrend: [0.9998, 1.0002], source: "OKX",
            quoteTime: ISO8601DateFormatter().string(from: .now), freshness: .updated)
        try repo.insert(legacy)
        let store = PortfolioStore(positionRepository: repo, credentialStore: NoIntegrationCredentials())
        let before = try repo.exportDataPayload()
        #expect(store.positions.first?.quantity == legacy.quantity)
        #expect(store.positions.first?.totalCost == legacy.totalCost)
        #expect(store.positions.first?.latestPrice == legacy.latestPrice)
        let restored = try repository()
        _ = try restored.importDataPayload(before)
        #expect(try restored.fetchPositions().first?.quoteCurrency == .usdt)
        #expect(try restored.fetchPositions().first?.latestPrice == legacy.latestPrice)
        #expect(try restored.fetchPositions().first?.totalCost == legacy.totalCost)
        #expect(try restored.fetchOpeningBalances() == repo.fetchOpeningBalances())
    }
}

private struct NoIntegrationCredentials: ProviderCredentialStoring {
    func read(kind: ProviderCredentialKind) throws -> String? { nil }
    func save(_: String, kind _: ProviderCredentialKind) throws {}
    func delete(kind _: ProviderCredentialKind) throws {}
    func readValidationState(kind _: ProviderCredentialKind) throws -> ProviderCredentialValidationState { .unknown }
    func saveValidationState(_: ProviderCredentialValidationState, kind _: ProviderCredentialKind) throws {}
}
