import AppKit
import CSQLite
import Foundation
import PortfolixMCPKit
import SwiftUI
import Testing
@testable import Portfolix

@Suite("Position closure bookkeeping")
struct PositionClosureTests {
    private func holding(id: UUID = UUID(), symbol: String = "DEMO", currency: DisplayCurrency = .cny,
                         quantity: Decimal = 10, price: Decimal = 100) -> Position {
        Position(id: id, name: "Demo Asset", symbol: symbol, category: .cnStock, quoteCurrency: currency,
            quantity: quantity, totalCost: quantity * 80, averageCost: 80, latestPrice: price,
            marketValueCNY: quantity * price / currency.rateFromCNY, profitRate: (price - 80) / 80 * 100,
            weeklyTrend: [90, price.doubleValue], source: "手工价格", quoteTime: "2026-10-28",
            freshness: .manual)
    }
    private func repository() throws -> PositionRepository {
        try PositionRepository(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("Portfolix.ClosureTests.\(UUID())/test.sqlite"))
    }
    private func daysAgo(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: .now)! }
    private func settle(price: Decimal = 110, fees: Decimal = 5) -> PositionClosureSettlement {
        .init(executionPrice: price, fees: fees, netProceeds: 10 * price - fees)
    }

    @Test
    func priceAndNetProceedsStayLinkedWithoutAcceptingPartialNumbers() throws {
        var draft = PositionClosureDraft(position: holding())
        draft.setPrice("110")
        draft.setFees("5")
        #expect(draft.proceedsText == "1095")
        draft.setProceeds("1200")
        #expect(draft.priceText == "120.5")
        draft.setFees("10")
        #expect(draft.priceText == "121")
        #expect(try draft.settlement().netProceeds == 1200)
        for value in ["10foo", "NaN", "1e999", "-1", "", "1 2"] {
            draft.setProceeds(value)
            #expect(throws: (any Error).self) { try draft.settlement() }
        }
    }

    @Test(arguments: DisplayCurrency.allCases)
    func creditsOnlyTheQuoteCurrencyAndPreservesRealizedProfit(currency: DisplayCurrency) throws {
        let repository = try repository()
        let asset = holding(currency: currency)
        let cash = PositionClosureMath.cashPosition(currency: currency, quantity: 200, name: "Demo Cash")
        try repository.insert(asset)
        try repository.insert(cash)
        try repository.replaceDailySnapshots(positions: [holding(id: asset.id, currency: currency, price: 90), cash], snapshotDate: daysAgo(1))
        let record = try repository.closePosition(expected: asset, settlement: settle(), tradeDate: .now, cashPositionID: cash.id, cashName: "unused")
        let positions = try repository.fetchPositions()
        #expect(positions.count == 1)
        #expect(positions.first?.quantity == 1295)
        #expect(positions.first?.quoteCurrency == currency)
        #expect(record.realizedProfit == 295)
        #expect(record.currency == currency)
        let point = try #require(repository.fetchDailyProfitPoints().last)
        #expect(abs((point.amountCNY - 195 / currency.rateFromCNY).doubleValue) < 0.00000001)
        #expect(try repository.fetchAssetPriceSnapshots(positionID: asset.id).count == 2)
    }

    @Test
    func historicalClosureRebasesLaterValuesAndCashWithoutCountingProceedsAsProfit() throws {
        let repository = try repository()
        let asset = holding(price: 140)
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 200, name: "Demo Cash")
        try repository.insert(asset)
        try repository.insert(cash)
        for (day, price): (Int, Decimal) in [(3, 90), (2, 100), (1, 120), (0, 140)] {
            try repository.replaceDailySnapshots(positions: [holding(id: asset.id, price: price), cash], snapshotDate: daysAgo(day))
        }
        let record = try repository.closePosition(expected: asset, settlement: settle(), tradeDate: daysAgo(2), cashPositionID: cash.id, cashName: "unused")
        #expect(record.dailyProfitCNY == "195")
        let history = try repository.fetchPortfolioSnapshots()
        #expect(history.map(\.totalValueCNY) == [1100, 1295, 1295, 1295])
        let assetHistory = try repository.fetchAssetPriceSnapshots(positionID: asset.id)
        #expect(assetHistory.count == 2)
        #expect(assetHistory.last?.latestPrice == 110)
        let profit = try repository.fetchDailyProfitPoints()
        #expect(profit.first { PositionClosureMath.day($0.date) == record.tradeDate }?.amountCNY == 195)
        #expect(profit.filter { $0.date > Calendar.current.startOfDay(for: daysAgo(2)) }.allSatisfy { $0.amountCNY == 0 })
        try repository.reversePositionClosure(id: record.id)
        #expect(try repository.fetchPositions().first { $0.id == asset.id }?.quantity == 10)
        #expect(try repository.fetchPositions().first { $0.id == cash.id }?.quantity == 200)
        #expect(try repository.fetchPortfolioSnapshots().map(\.totalValueCNY) == [1100, 1200, 1400, 1600])
        #expect(try repository.fetchAssetPriceSnapshots(positionID: asset.id).count == 4)
        #expect(try repository.fetchPositionClosures().first?.isReversed == true)
    }

    @Test
    func changedQuantityAndCrossCurrencyDestinationsFailAtomically() throws {
        let repository = try repository()
        let asset = holding()
        let cash = PositionClosureMath.cashPosition(currency: .usd, quantity: 200, name: "USD Cash")
        try repository.insert(asset)
        try repository.insert(cash)
        #expect(throws: PositionClosureError.invalidCash) {
            try repository.closePosition(expected: asset, settlement: settle(), tradeDate: .now, cashPositionID: cash.id, cashName: "new")
        }
        try repository.replaceDailySnapshots(positions: [holding(id: asset.id, quantity: 20)], snapshotDate: daysAgo(1))
        #expect(throws: PositionClosureError.historicalQuantityChange) {
            try repository.closePosition(expected: asset, settlement: settle(), tradeDate: daysAgo(2), cashPositionID: nil, cashName: "new")
        }
        #expect(try repository.fetchPositionClosures().isEmpty)
        #expect(try repository.fetchPositions().count == 2)
    }

    @Test
    func intradayQuantityChangesCannotBeHiddenByTheFinalDailySnapshot() throws {
        let repository = try repository()
        let asset = holding()
        try repository.insert(asset)
        try repository.updateBalances([holding(id: asset.id, quantity: 20)])
        try repository.updateBalances([asset])
        try repository.replaceDailySnapshots(positions: [asset])
        #expect(throws: PositionClosureError.historicalQuantityChange) {
            try repository.closePosition(expected: asset, settlement: settle(), tradeDate: daysAgo(1), cashPositionID: nil, cashName: "Cash")
        }
        #expect(try repository.fetchPositions().first?.quantity == 10)
        #expect(try repository.fetchPositionClosures().isEmpty)
        _ = try repository.closePosition(expected: asset, settlement: settle(), tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        #expect(try repository.fetchPositionClosures().count == 1)
    }

    @Test
    func staleQuoteRefreshCannotReopenAClosedHoldingOrOverwriteCreditedCash() throws {
        let repository = try repository()
        let asset = holding()
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 200, name: "Cash")
        try repository.insert(asset)
        try repository.insert(cash)
        _ = try repository.closePosition(expected: asset, settlement: settle(), tradeDate: .now, cashPositionID: cash.id, cashName: "unused")
        try repository.applyQuoteRefresh(updatedPositions: [asset, cash], snapshotPositions: [asset, cash])
        #expect(try repository.fetchPositions().count == 1)
        #expect(try repository.fetchPositions().first?.quantity == 1295)
        #expect(try repository.fetchPortfolioSnapshots().last?.totalValueCNY == 1295)
        #expect(try repository.fetchAssetPriceSnapshots(positionID: asset.id).last?.latestPrice == 110)
        #expect(throws: PositionClosureError.holdingChanged) { try repository.update(asset) }
    }

    @Test
    func duplicateSubmissionAndInsufficientCashCannotChangeTheLedger() throws {
        let repository = try repository()
        let asset = holding()
        try repository.insert(asset)
        let record = try repository.closePosition(expected: asset, settlement: settle(), tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        #expect(throws: PositionClosureError.holdingChanged) {
            try repository.closePosition(expected: asset, settlement: settle(), tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        }
        let cash = try #require(repository.fetchPositions().first)
        try repository.updateBalances([PositionClosureMath.cashPosition(id: cash.id, currency: .cny, quantity: 10, name: cash.name)])
        #expect(throws: PositionClosureError.insufficientCash) { try repository.reversePositionClosure(id: record.id) }
        #expect(try repository.fetchPositions().first?.quantity == 10)
        #expect(try repository.fetchPositionClosures().count == 1)
        #expect(try repository.fetchPositionClosures().first?.isReversed == false)
    }

    @Test
    func zeroProceedsCanRecordATotalLossWithoutCreatingZeroCash() throws {
        let repository = try repository()
        let asset = holding()
        try repository.insert(asset)
        let record = try repository.closePosition(expected: asset,
            settlement: .init(executionPrice: 0, fees: 0, netProceeds: 0), tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        #expect(record.realizedProfit == -800)
        #expect(try repository.fetchPositions().isEmpty)
        try repository.reversePositionClosure(id: record.id)
        #expect(try repository.fetchPositions().first?.id == asset.id)
    }

    @Test
    func closureSurvivesExportImportAndRepeatedImportNeverCreditsCashTwice() throws {
        let source = try repository()
        let asset = holding()
        try source.insert(asset)
        let record = try source.closePosition(expected: asset, settlement: settle(), tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        let archive = source.storageURL.deletingLastPathComponent().appendingPathComponent("roundtrip.zip")
        _ = try PortfolixDataPackageService.write(payload: source.exportDataPayload(), to: archive)
        let prepared = try PortfolixDataPackageService.prepareImport(from: archive)
        #expect(prepared.payload.closedHoldings?.count == 1)
        let restored = try repository()
        _ = try restored.importDataPayload(prepared.payload)
        _ = try restored.importDataPayload(prepared.payload)
        #expect(try restored.fetchPositions().first?.quantity == 1095)
        #expect(try restored.fetchPositionClosures().count == 1)
        #expect(try restored.fetchPositionClosures().first?.realizedProfit == 295)
        try restored.reversePositionClosure(id: record.id)
        #expect(try restored.fetchPositions().first { $0.id == asset.id }?.quantity == 10)
    }

    @Test(arguments: [3, 4, 5])
    func previousVersionThreeThroughFiveBackupsRemainReadable(version: Int) throws {
        let source = try repository()
        try source.insert(holding())
        let folder = source.storageURL.deletingLastPathComponent()
        let archive = folder.appendingPathComponent("current.zip")
        _ = try PortfolixDataPackageService.write(payload: source.exportDataPayload(), to: archive)
        let extracted = folder.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        func run(_ path: String, _ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.currentDirectoryURL = extracted
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        try run("/usr/bin/unzip", ["-qq", archive.path])
        let manifestURL = extracted.appendingPathComponent("manifest.json")
        var manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["schemaVersion"] = version
        var counts = try #require(manifest["recordCounts"] as? [String: Any])
        if version < 4 { counts["closedHoldings"] = nil }
        if version < 5 { counts["trades"] = nil }
        counts["openingBalances"] = nil
        manifest["recordCounts"] = counts
        manifest["files"] = (manifest["files"] as? [[String: Any]])?.filter {
            let name = $0["name"] as? String ?? ""
            return name != "opening_balances.json" && (version >= 5 || name != "trades.json") && (version >= 4 || name != "closed_holdings.json")
        }
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        let legacy = folder.appendingPathComponent("legacy.zip")
        try run("/usr/bin/zip", ["-q", "-X", legacy.path, "manifest.json", "holdings.json", "daily_returns.json", "daily_asset_prices.json", "risk_profile.json"] + (version >= 4 ? ["closed_holdings.json"] : []) + (version >= 5 ? ["trades.json"] : []))
        let prepared = try PortfolixDataPackageService.prepareImport(from: legacy)
        #expect(version < 4 ? prepared.payload.closedHoldings == nil : prepared.payload.closedHoldings == [])
        #expect(version < 5 ? prepared.payload.trades == nil : prepared.payload.trades == [])
        #expect(prepared.payload.openingBalances == nil)
        #expect(prepared.payload.holdings.count == 1)
        #expect(prepared.payload.riskProfile != nil)
    }

    @Test
    func aFailedRecordWriteRollsBackCashPositionsAndHistoricalChanges() throws {
        let repository = try repository()
        let asset = holding()
        try repository.insert(asset)
        try repository.replaceDailySnapshots(positions: [asset], snapshotDate: daysAgo(1))
        let before = try repository.exportDataPayload()
        var handle: OpaquePointer?
        #expect(sqlite3_open(repository.storageURL.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "CREATE TRIGGER reject_closure BEFORE INSERT ON position_closures BEGIN SELECT RAISE(ABORT, 'fixture failure'); END", nil, nil, nil) == SQLITE_OK)
        #expect(throws: (any Error).self) {
            try repository.closePosition(expected: asset, settlement: settle(), tradeDate: daysAgo(1), cashPositionID: nil, cashName: "Cash")
        }
        #expect(try repository.exportDataPayload() == before)
    }

    @Test
    func twoClosedLotsWithTheSameSymbolKeepSeparateHistoryWhenImported() throws {
        let repository = try repository()
        let first = holding()
        try repository.insert(first)
        _ = try repository.closePosition(expected: first, settlement: settle(), tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        let cash = try #require(repository.fetchPositions().first)
        let second = holding()
        try repository.insert(second)
        _ = try repository.closePosition(expected: second, settlement: settle(), tradeDate: .now, cashPositionID: cash.id, cashName: "unused")
        let restored = try self.repository()
        _ = try restored.importDataPayload(repository.exportDataPayload())
        #expect(try restored.fetchPositionClosures().count == 2)
        #expect(try restored.fetchPositions().first?.quantity == 2190)
        #expect(try restored.fetchAssetPriceSnapshots(positionID: first.id).count == 1)
        #expect(try restored.fetchAssetPriceSnapshots(positionID: second.id).count == 1)
    }

    @Test
    func mcpAndAgentReadOnlyToolsExposeTheSameClosedProfitWithoutRawUndoData() throws {
        let repository = try repository()
        let asset = holding()
        try repository.insert(asset)
        try repository.replaceDailySnapshots(positions: [holding(id: asset.id, price: 90)], snapshotDate: daysAgo(1))
        let record = try repository.closePosition(expected: asset, settlement: settle(), tradeDate: .now, cashPositionID: nil, cashName: "Cash")
        let request = try AIPortfolioToolRequest(call: .init(callID: "closed", name: "list_closed_holdings", arguments: "{}"))
        let output = AIPortfolioDataToolExecutor.execute(request, snapshot: .init(positions: [], closures: [record]))
        #expect(output.contains("295"))
        #expect(!output.contains("historyAdjustments") && !output.contains("originalSnapshots"))
        try repository.setAppSetting(key: "mcp_read_access_enabled", value: "true")
        let server = PortfolioMCPServer(databaseURL: repository.storageURL)
        let initialization: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "Fixture", "version": "1"]]]
        _ = server.respond(to: try JSONSerialization.data(withJSONObject: initialization))
        _ = server.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        let arguments = ["start_date": PositionClosureMath.day(daysAgo(1)), "end_date": record.tradeDate]
        let data = try #require(server.respond(to: JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "get_daily_profit", "arguments": arguments]])))
        let response = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let content = try #require((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])
        let days = try #require(content["days"] as? [[String: String]])
        #expect(days.last?["amount_cny"] == "195")
    }

    @Test @MainActor
    func storeAndCloudRetainTodaysProfitAfterTheLastRiskAssetIsClosed() throws {
        let repository = try repository()
        let asset = holding()
        try repository.insert(asset)
        try repository.replaceDailySnapshots(positions: [holding(id: asset.id, price: 90)], snapshotDate: daysAgo(1))
        let store = PortfolioStore(positionRepository: repository)
        try store.closePosition(asset, settlement: settle(), tradeDate: .now, cashPositionID: nil)
        #expect(store.positions.count == 1 && store.positions.first?.category == .cash)
        #expect(store.todayProfitCNY == 195)
        #expect(store.realizedProfitCNY == 295)
        #expect(store.investmentCloudDailyProfitItems(asOf: .now).first?.amountCNY == 195)
        let restarted = PortfolioStore(positionRepository: repository)
        #expect(restarted.activePositionClosures.count == 1)
        #expect(restarted.todayProfitCNY == 195)
    }

    @Test @MainActor
    func closureSheetsFitBothAppearancesAndLanguages() throws {
        let repository = try repository()
        let asset = holding()
        try repository.insert(asset)
        for language: AppLanguage in [.chinese, .english] {
            let store = PortfolioStore(positionRepository: repository, initialLanguage: language)
            for scheme: ColorScheme in [.light, .dark] {
                let host = NSHostingView(rootView: PositionClosureSheet(position: asset).environment(store).environment(\.colorScheme, scheme))
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                #expect(host.fittingSize == CGSize(width: 600, height: 660))
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
                if let directory = ProcessInfo.processInfo.environment["PORTFOLIX_CLOSURE_PREVIEW_DIRECTORY"] {
                    let folder = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let image = try #require(bitmap.representation(using: .png, properties: [:]))
                    try image.write(to: folder.appendingPathComponent("closure-\(language == .english ? "en" : "zh")-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
    }

    @Test
    func preparesIsolatedInteractiveDemoOnlyWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["PORTFOLIX_CLOSURE_DEMO_DATABASE"] else { return }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path + "/") else { throw PositionClosureError.invalidRecord }
        let repository = try PositionRepository(databaseURL: url)
        let chip = holding(symbol: "CHIP", price: 120)
        let gold = holding(symbol: "GOLD", price: 160)
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 10000, name: "现金 CNY")
        try repository.insert(chip)
        try repository.insert(gold)
        try repository.insert(cash)
        for day in (0...5).reversed() {
            try repository.replaceDailySnapshots(positions: [holding(id: chip.id, symbol: chip.symbol, price: Decimal(120 - day * 2)),
                holding(id: gold.id, symbol: gold.symbol, price: Decimal(160 - day)), cash], snapshotDate: daysAgo(day))
        }
        _ = try repository.closePosition(expected: gold, settlement: settle(price: 155), tradeDate: daysAgo(2), cashPositionID: cash.id, cashName: "unused")
        try repository.setAppSetting(key: "app_language", value: AppLanguage.chinese.rawValue)
    }
}
