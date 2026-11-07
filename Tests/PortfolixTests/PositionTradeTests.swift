import AppKit
import CSQLite
import Foundation
import PortfolixMCPKit
import SwiftUI
import Testing
@testable import Portfolix

@Suite("Buy and sell bookkeeping")
struct PositionTradeTests {
    private func repository() throws -> PositionRepository {
        let repository = try PositionRepository(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("Portfolix.TradeTests.\(UUID())/test.sqlite"))
        try repository.setAppSetting(key: RiskProfilePersistence.updatedAtKey, value: "2026-01-01T00:00:00Z")
        return repository
    }
    private func day(_ ago: Int) -> Date { Calendar.current.date(byAdding: .day, value: -ago, to: .now)! }
    private func asset(id: UUID = UUID(), quantity: Decimal = 10, price: Decimal = 130,
                       currency: DisplayCurrency = .cny, category: AssetCategory = .cnStock,
                       name: String = "Demo Semiconductor ETF", symbol: String = "DEMO") -> Position {
        Position(id: id, name: name, symbol: symbol, category: category,
            quoteCurrency: currency, quantity: quantity, totalCost: quantity * 80, averageCost: 80,
            latestPrice: price, marketValueCNY: quantity * price / currency.rateFromCNY,
            profitRate: (price - 80) / 80 * 100, weeklyTrend: [120, price.doubleValue],
            source: "手工价格", quoteTime: ISO8601DateFormatter().string(from: .now), freshness: .manual)
    }
    private func setup(currency: DisplayCurrency = .cny) throws -> (PositionRepository, Position, Position) {
        let repo = try repository()
        let holding = asset(currency: currency)
        let cash = PositionClosureMath.cashPosition(currency: currency, quantity: 1000, name: "Demo Cash")
        try repo.insert(holding); try repo.insert(cash)
        for (ago, price): (Int, Decimal) in [(4, 90), (3, 100), (2, 110), (1, 120), (0, 130)] {
            try repo.replaceDailySnapshots(positions: [asset(id: holding.id, price: price, currency: currency), cash], snapshotDate: day(ago))
        }
        return (repo, holding, cash)
    }
    @discardableResult
    private func trade(_ repo: PositionRepository, _ holding: Position, _ cash: Position?, side: PositionTradeSide = .sell,
                       quantity: Decimal = 4, price: Decimal = 110, fee: Decimal = 5, ago: Int = 0,
                       id: UUID = UUID()) throws -> PositionTradeRecord {
        try repo.recordTrade(id: id, side: side, expected: holding, quantity: quantity, price: price, fees: fee,
            tradeDate: day(ago), cashPositionID: cash?.id, cashName: "Demo Cash")
    }

    @Test(arguments: DisplayCurrency.allCases)
    func partialSaleConservesUnitsCostAndCash(currency: DisplayCurrency) throws {
        let (repo, holding, cash) = try setup(currency: currency)
        let record = try trade(repo, holding, cash)
        let positions = try repo.fetchPositions()
        let remaining = try #require(positions.first { $0.id == holding.id })
        #expect(remaining.quantity == 6)
        #expect(remaining.totalCost == 480)
        #expect(remaining.averageCost == 80)
        #expect(positions.first { $0.id == cash.id }?.quantity == 1435)
        #expect(record.realizedProfit == 115)
        let row = PositionTransactionRow(record)
        for displayCurrency in DisplayCurrency.allCases {
            let expected = Decimal(115) / currency.rateFromCNY * displayCurrency.rateFromCNY
            #expect(abs(((row.profit(in: displayCurrency) ?? 0) - expected).doubleValue) < 0.00000001)
        }
        let profit = try #require(repo.fetchDailyProfitPoints().last)
        // 6 remaining units move 120 -> 130; 4 sold at 110; fee 5.
        #expect(abs((profit.amountCNY - 15 / currency.rateFromCNY).doubleValue) < 0.00000001)
        try repo.reverseTrade(id: record.id)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.quantity == 10)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 1000)
    }

    @Test
    func buyAddsFeesToCostAndUsesWeightedAverageThenSellsPart() throws {
        let (repo, holding, cash) = try setup()
        let buy = try trade(repo, holding, cash, side: .buy, quantity: 2, price: 120, fee: 2)
        let added = try #require(repo.fetchPositions().first { $0.id == holding.id })
        #expect(added.quantity == 12)
        #expect(added.totalCost == 1042)
        #expect(buy.realizedProfit == nil)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 758)
        let sell = try trade(repo, added, cash, quantity: 6, price: 130, fee: 3)
        #expect(sell.cost == 521)
        #expect(sell.realizedProfit == 256)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.totalCost == 521)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 1535)
    }

    @Test
    func repeatingAverageCostDoesNotLeaveADustBalanceWhenSellingAll() throws {
        let (repo, holding, cash) = try setup()
        _ = try trade(repo, holding, cash, side: .buy, quantity: 2, price: 120, fee: 2)
        let added = try #require(repo.fetchPositions().first { $0.id == holding.id })
        _ = try trade(repo, added, cash, quantity: 3, price: 130, fee: 1)
        let remaining = try #require(repo.fetchPositions().first { $0.id == holding.id })
        let final = try trade(repo, remaining, cash, quantity: 9, price: 140, fee: 1)
        #expect(final.cost == Decimal(string: "781.5"))
        #expect(final.realizedProfit == Decimal(string: "477.5"))
        #expect(try repo.fetchPositions().allSatisfy { $0.id != holding.id })
        try repo.reverseTrade(id: final.id)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.totalCost == Decimal(string: "781.5"))
    }

    @Test
    func historicalInsertionReplaysLaterSalesAndReversalRestoresTheirCost() throws {
        let (repo, holding, cash) = try setup()
        let sell = try trade(repo, holding, cash, quantity: 4, price: 120, fee: 2, ago: 1)
        let current = try #require(repo.fetchPositions().first { $0.id == holding.id })
        let buy = try trade(repo, current, cash, side: .buy, quantity: 2, price: 100, fee: 0, ago: 2)
        let updated = try #require(repo.fetchPositions().first { $0.id == holding.id })
        let replayed = try #require(repo.fetchPositionTrades().first { $0.id == sell.id })
        #expect(updated.quantity == 8)
        #expect(abs((updated.totalCost - Decimal(2000) / 3).doubleValue) < 0.000001)
        #expect(abs((replayed.cost - Decimal(1000) / 3).doubleValue) < 0.000001)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 1278)
        let history = try repo.fetchAssetPriceSnapshots(positionID: holding.id)
        #expect(history.map(\.quantity) == [10, 10, 12, 8, 8])
        try repo.reverseTrade(id: buy.id)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.totalCost == 480)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 1478)
        #expect(try repo.fetchPositionTrades().first { $0.id == sell.id }?.realizedProfit == 158)
    }

    @Test
    func consecutiveHistoricalTradesUseTheirTradingOrderNotTheirEntryTimestamps() throws {
        let (repo, holding, cash) = try setup()
        _ = try trade(repo, holding, cash, side: .buy, quantity: 2, price: 120, fee: 2, ago: 2)
        let current = try #require(repo.fetchPositions().first { $0.id == holding.id })
        let sell = try trade(repo, current, cash, quantity: 3, price: 130, fee: 1, ago: 1)
        #expect(sell.cost == Decimal(string: "260.5"))
        #expect(sell.realizedProfit == Decimal(string: "128.5"))
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.quantity == 9)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 1147)
        #expect(try repo.fetchPositionTrades().allSatisfy { $0.priceHistory.isEmpty })
    }

    @Test
    func aLegacyClosureCanFundANewBuyButCannotBeReversedUnderThatBuy() throws {
        let (repo, holding, cash) = try setup()
        let closure = try repo.closePosition(expected: holding, settlement: .init(executionPrice: 110, fees: 0, netProceeds: 1100),
            tradeDate: .now, cashPositionID: cash.id, cashName: "Cash")
        let next = asset()
        _ = try trade(repo, next, cash, side: .buy, quantity: 1, price: 100, fee: 0)
        #expect(try repo.fetchPositions().first { $0.id == next.id }?.quantity == 1)
        #expect(throws: PositionTradeError.dependentTrade) { try repo.reversePositionClosure(id: closure.id) }
    }

    @Test
    func fullSaleAndNewBuyKeepSeparateHistoryCycles() throws {
        let (repo, holding, cash) = try setup()
        let sell = try trade(repo, holding, cash, quantity: 10, price: 140, fee: 0)
        #expect(try repo.fetchPositions().allSatisfy { $0.id != holding.id })
        let next = asset(quantity: 2, price: 140)
        _ = try trade(repo, next, cash, side: .buy, quantity: 2, price: 140, fee: 0)
        #expect(try repo.fetchPositions().first { $0.symbol == "DEMO" }?.id == next.id)
        let archive = repo.storageURL.deletingLastPathComponent().appendingPathComponent("roundtrip.zip")
        _ = try PortfolixDataPackageService.write(payload: repo.exportDataPayload(), to: archive)
        let prepared = try PortfolixDataPackageService.prepareImport(from: archive)
        let restored = try repository()
        _ = try restored.importDataPayload(prepared.payload)
        _ = try restored.importDataPayload(prepared.payload)
        #expect(try restored.fetchPositionTrades().count == 2)
        #expect(try restored.fetchPositions().first { $0.symbol == "DEMO" }?.quantity == 2)
        #expect(try restored.fetchAssetPriceSnapshots(positionID: holding.id).count == 4)
        #expect(try restored.fetchAssetPriceSnapshots(positionID: next.id).count == 1)
        // Reopening the old cycle must not replace the newly bought holding with the same symbol.
        #expect(throws: (any Error).self) { try restored.reverseTrade(id: sell.id) }
        #expect(try restored.fetchPositions().first { $0.symbol == "DEMO" }?.id == next.id)
    }

    @Test
    func newBuyAndZeroCashAfterPaymentCanBeReversed() throws {
        let repo = try repository()
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 1000, name: "Cash")
        try repo.insert(cash)
        let holding = asset()
        let buy = try trade(repo, holding, cash, side: .buy, quantity: 10, price: 99, fee: 10)
        #expect(try repo.fetchPositions().count == 1)
        #expect(try repo.fetchPositions().first?.totalCost == 1000)
        try repo.reverseTrade(id: buy.id)
        #expect(try repo.fetchPositions().count == 1)
        #expect(try repo.fetchPositions().first?.id == cash.id)
        #expect(try repo.fetchPositions().first?.quantity == 1000)
    }

    @Test
    func invalidTradesNeverChangeAnyBalancesOrHistory() throws {
        let (repo, holding, cash) = try setup()
        let before = try repo.exportDataPayload()
        for (quantity, price, fee): (Decimal, Decimal, Decimal) in [(11, 110, 0), (-1, 110, 0), (1, -1, 0), (1, 0, 1)] {
            #expect(throws: (any Error).self) { try trade(repo, holding, cash, quantity: quantity, price: price, fee: fee) }
            #expect(try repo.exportDataPayload() == before)
        }
        #expect(throws: PositionTradeError.insufficientCash) { try trade(repo, holding, cash, side: .buy, quantity: 20, price: 100, fee: 1) }
        #expect(try repo.exportDataPayload() == before)
        let usd = PositionClosureMath.cashPosition(currency: .usd, quantity: 1000, name: "USD")
        try repo.insert(usd)
        #expect(throws: (any Error).self) { try trade(repo, holding, usd) }
        #expect(try repo.fetchPositionTrades().isEmpty)
    }

    @Test
    func idempotencyAndStaleQuotesCannotResurrectSoldPositions() throws {
        let (repo, holding, cash) = try setup()
        let id = UUID()
        _ = try trade(repo, holding, cash, quantity: 10, fee: 0, id: id)
        #expect(throws: PositionTradeError.changed) { try trade(repo, holding, cash, quantity: 10, fee: 0, id: id) }
        try repo.applyQuoteRefresh(updatedPositions: [holding, cash], snapshotPositions: [holding, cash])
        #expect(try repo.fetchPositions().count == 1)
        #expect(try repo.fetchPositions().first?.quantity == 2100)
    }

    @Test
    func missingHistoryAndLaterManualCorrectionsAreNotGuessed() throws {
        let repo = try repository()
        let holding = asset()
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 1000, name: "Cash")
        try repo.insert(holding); try repo.insert(cash)
        #expect(throws: PositionTradeError.missingHistory) { try trade(repo, holding, cash, ago: 2) }
        for ago in [2, 1, 0] { try repo.replaceDailySnapshots(positions: [holding, cash], snapshotDate: day(ago)) }
        try repo.updateBalances([asset(id: holding.id, quantity: 20)])
        try repo.updateBalances([holding])
        #expect(throws: PositionTradeError.historicalCorrection) { try trade(repo, holding, cash, ago: 2) }
        #expect(try repo.fetchPositionTrades().isEmpty)
        _ = try trade(repo, holding, cash)
        #expect(try repo.fetchPositionTrades().count == 1)
    }

    @Test
    func emptyProceedsAndFractionalQuantitiesAreSupported() throws {
        let (repo, holding, cash) = try setup()
        let record = try trade(repo, holding, cash, quantity: Decimal(string: "0.125")!, price: 0, fee: 0)
        #expect(record.realizedProfit == -10)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.quantity == Decimal(string: "9.875"))
        try repo.reverseTrade(id: record.id)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.totalCost == 800)
    }

    @Test
    func saleDraftLinksQuantityPriceFeesAndProceeds() throws {
        var draft = PositionTradeDraft(side: .sell, position: asset())
        draft.setQuantity("2.5"); draft.setPrice("100"); draft.setFees("1")
        #expect(draft.amountText == "249")
        draft.setAmount("299")
        #expect(draft.priceText == "120")
        draft.setQuantity("5")
        #expect(draft.priceText == "60")
        #expect(try draft.values(availableQuantity: 5).quantity == 5)
        #expect(throws: PositionTradeError.insufficientQuantity) { try draft.values(availableQuantity: 4) }
        for invalid in ["1 2", "NaN", "1e999", "0", "-2"] {
            draft.setQuantity(invalid)
            #expect(throws: (any Error).self) { try draft.values() }
        }
    }

    @Test
    func optionalFeesDefaultToZeroAndRecalculateProceedsWhenCleared() throws {
        for text in ["", " ", "\n\t"] {
            #expect(PositionTradeInput.fees(text) == 0)
        }
        #expect(PositionTradeInput.fees("1.25") == Decimal(string: "1.25"))
        #expect(PositionTradeInput.fees("invalid") == nil)
        var draft = PositionTradeDraft(side: .sell, position: asset())
        #expect(draft.feesText.isEmpty)
        draft.setQuantity("2")
        #expect(try draft.values().fees == 0)
        draft.setPrice("100")
        draft.setFees("3")
        #expect(draft.amountText == "197")
        draft.setFees("")
        #expect(draft.amountText == "200")
        #expect(try draft.values().fees == 0)
        draft.setFees("-1")
        #expect(throws: PositionTradeError.invalidInput) { try draft.values() }
    }

    @Test
    func additionCopyAndSharedFormMetricsRemainConsistent() {
        #expect(PositionTradeSide.add.title(language: .chinese) == "增持")
        #expect(PositionTradeSide.buy.title(language: .chinese) == "增持")
        #expect(PositionTradeSide.sell.title(language: .chinese) == "卖出")
        #expect(AssetEntryLayout.valueFieldWidth == 320)
        #expect(AssetEntryLayout.valueFieldHeight == 28)
        #expect(AssetEntryLayout.minimumRowHeight == 42)
        #expect(AssetEntryLayout.inlineControlHeight == PortfolixLayout.glassControlHeight)
    }

    @Test
    func saleStartsAtZeroWithoutLosingTheLatestEditablePrice() throws {
        var draft = PositionTradeDraft(side: .sell, position: asset(price: 135))
        #expect(draft.quantityText == "0")
        #expect(draft.amountText == "0")
        #expect(draft.priceText == "135")
        #expect(throws: PositionTradeError.invalidInput) { try draft.values(availableQuantity: 10) }
        draft.setPrice("140")
        #expect(draft.amountText == "0")
        draft.setQuantity("2")
        #expect(draft.amountText == "280")
        draft.setAmount("270")
        #expect(draft.priceText == "135")
        draft.setQuantity("0")
        #expect(draft.amountText == "0")
        #expect(!draft.usesAmount)
        draft.setQuantity("3")
        #expect(draft.amountText == "405")
    }

    @Test @MainActor
    func unsupportedQuoteControlsUseTheSameCapabilityAsRefresh() throws {
        for (category, symbol, supported): (AssetCategory, String, Bool) in [
            (.cnStock, "DEMO", false), (.cnStock, "600519", true), (.bStock, "900901", true),
            (.hkStock, "00700.HK", true), (.hkStock, "INVALID", false), (.usStock, "AAPL", true),
            (.fund, "008887", true), (.fund, "GOLD", false), (.crypto, "BTC/USDT", true),
            (.crypto, "BTC", false), (.cash, "CNY", false)
        ] {
            #expect(MarketDataAdapter.supportsQuote(for: asset(category: category, symbol: symbol)) == supported)
        }
        let repo = try repository()
        let manual = asset()
        try repo.insert(manual)
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        store.refreshPosition(id: manual.id)
        #expect(store.refreshingPositionIDs.isEmpty)
        #expect(store.persistenceErrorMessage == nil)
    }

    @Test @MainActor
    func transactionNumbersFollowPreciseRecordTimeAndSurviveFiltering() {
        func record(_ sequence: Int, time: String, tradeDay: String = "2026-10-30", reversed: Bool = false) -> PositionTradeRecord {
            PositionTradeRecord(id: UUID(), sequence: sequence, side: .add,
                asset: .init(position: asset(name: "Asset \(sequence)", symbol: "DEMO\(sequence)"), timestamp: time),
                cash: nil, tradeDate: tradeDay, quantity: "1", executionPrice: "80", fees: "0", cashAmount: "80", allocatedCost: "0",
                rateFromCNY: "1", recordedAt: time, reversedAt: reversed ? time : nil, priceHistory: [])
        }
        let first = record(1, time: "2026-10-30T12:44:35Z")
        let second = record(2, time: "2026-10-30T12:44:36Z", tradeDay: "2026-10-29")
        let third = record(3, time: "2026-10-30T12:44:36.500Z")
        let reversed = record(4, time: "2026-10-30T12:44:37Z", reversed: true)
        let rows = PositionTransactionRow.listed(trades: [first, third, reversed, second], closures: [])
        #expect(rows.map(\.id) == [third.id, second.id, first.id])
        #expect(rows.map(\.displayNumber) == [3, 2, 1])
        let filtered = PositionTransactionRow.listed(trades: [first, third, second], closures: [], query: "DEMO2")
        #expect(filtered.first?.displayNumber == 2)
        #expect(rows.last?.recordedClockText.hasSuffix(":35") == true)
        #expect(rows.last?.recordedClockText.split(separator: ":").count == 3)
        #expect(rows.last?.recordedDateText.count == 10)
    }

    @Test(arguments: [false, true])
    func newAssetCopyNeverDescribesAnExistingHolding(isCash: Bool) {
        for language: AppLanguage in [.chinese, .english] {
            let copy = AssetAdditionCopy(isExistingAsset: false, isCash: isCash, language: language)
            let strings = [copy.quantityTitle, copy.quantityPlaceholder, copy.costTitle(mode: .totalCost),
                copy.costTitle(mode: .averageCost), copy.costPlaceholder(mode: .totalCost),
                copy.costPlaceholder(mode: .averageCost), copy.totalCostTitle,
                copy.externalFundsTitle, copy.resultingQuantityTitle]
            #expect(strings.allSatisfy { !$0.contains("增持") && !$0.localizedCaseInsensitiveContains("added") && !$0.localizedCaseInsensitiveContains("additional") })
            let existing = AssetAdditionCopy(isExistingAsset: true, isCash: isCash, language: language)
            #expect(existing.quantityTitle != copy.quantityTitle)
            #expect(existing.quantityPlaceholder != copy.quantityPlaceholder)
        }
    }

    @Test @MainActor
    func footerKeepsLongErrorsAndBothActionsVisibleInBothLanguages() throws {
        for language: AppLanguage in [.chinese, .english] {
            let error = PositionTradeError.historicalCorrection.message(language: language)
            let host = NSHostingView(rootView: SheetActionFooter(errorMessage: error) {
                Button(localizedText("取消", "Cancel", language: language)) {}.buttonStyle(QuietButtonStyle())
                Button(localizedText("确认添加", "Add Asset", language: language)) {}.buttonStyle(PrimaryButtonStyle())
            }.frame(width: 620))
            let size = host.fittingSize
            #expect(size.width == 620)
            #expect(size.height >= 64 && size.height < 200)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            #expect(host.bitmapImageRepForCachingDisplay(in: host.bounds) != nil)
        }
    }

    @Test @MainActor
    func footerActionsStayRightAlignedWithAndWithoutAnError() throws {
        for message: String? in [nil, "请核对输入。"] {
            let host = NSHostingView(rootView: SheetActionFooter(errorMessage: message) {
                Color.red.frame(width: 64, height: 24)
            }.frame(width: 620))
            let size = host.fittingSize
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let x = Int(CGFloat(bitmap.pixelsWide) * (620 - PortfolixSpacing.xl - 32) / 620)
            let color = try #require(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            #expect(color.redComponent > 0.7 && color.greenComponent < 0.5 && color.blueComponent < 0.5)
        }
    }

    @Test @MainActor
    func additionUsesTheRefreshedQuoteForBothExistingAndAddedUnits() throws {
        let (repo, holding, _) = try setup()
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        let quote = AssetLookupCandidate(name: holding.name, symbol: holding.symbol, category: holding.category,
            quoteCurrency: holding.quoteCurrency, latestPrice: 140, upstreamSource: holding.source,
            quoteTime: ISO8601DateFormatter().string(from: .now))
        let id = UUID()
        try store.recordTrade(id: id, side: .add, position: holding, quantity: 2, price: 135,
            fees: 1, tradeDate: .now, cashPositionID: nil, refreshedQuote: quote)
        let current = try #require(store.positions.first { $0.id == holding.id })
        #expect(current.quantity == 12)
        #expect(current.totalCost == 1071)
        #expect(current.latestPrice == 140)
        #expect(store.todayProfitCNY == 209)
        #expect(store.investmentCloudDailyProfitItems(asOf: .now).reduce(0) { $0 + $1.amountCNY } == 209)
        #expect(try repo.fetchDailyProfitPoints().last?.amountCNY == 209)
        #expect(PortfolioStore(positionRepository: repo).todayProfitCNY == 209)
        try store.reverseTrade(try #require(store.positionTrades.first { $0.id == id }))
        #expect(store.todayProfitCNY == 200)
        #expect(store.positions.first { $0.id == holding.id }?.quantity == 10)
    }

    @Test @MainActor
    func rejectedAdditionRollsBackItsQuoteAndSnapshotsAsWellAsBalances() throws {
        let (repo, holding, cash) = try setup()
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        let before = try repo.exportDataPayload()
        let quote = AssetLookupCandidate(name: holding.name, symbol: holding.symbol, category: holding.category,
            quoteCurrency: holding.quoteCurrency, latestPrice: 140, upstreamSource: holding.source,
            quoteTime: ISO8601DateFormatter().string(from: .now))
        #expect(throws: PositionTradeError.insufficientCash) {
            try store.recordTrade(id: UUID(), side: .buy, position: holding, quantity: 100, price: 135,
                fees: 1, tradeDate: .now, cashPositionID: cash.id, refreshedQuote: quote)
        }
        #expect(try repo.exportDataPayload() == before)
        #expect(store.todayProfitCNY == 100)
    }

    @Test @MainActor
    func fundAdditionKeepsTheExistingUnitsProfitWithSparsePriceHistory() throws {
        let repo = try repository()
        let holding = asset(category: .fund, name: "Synthetic Fund", symbol: "SYNTHETIC")
        try repo.insert(holding)
        try repo.replaceDailySnapshots(positions: [asset(id: holding.id, price: 120,
            category: .fund, name: holding.name, symbol: holding.symbol)], snapshotDate: day(10))
        try repo.replaceDailySnapshots(positions: [holding])
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        #expect(store.todayProfitCNY == 100)

        let id = UUID()
        try store.recordTrade(id: id, side: .add, position: holding, quantity: 2, price: 125,
            fees: 1, tradeDate: .now, cashPositionID: nil)
        // Original units: 10 × (130 - 120); added units: 2 × (130 - 125), less the fee.
        #expect(store.todayProfitCNY == 109)
        #expect(try repo.fetchDailyProfitPoints().last?.amountCNY == 109)
        #expect(PortfolioStore(positionRepository: repo).todayProfitCNY == 109)
        try store.reverseTrade(try #require(store.positionTrades.first { $0.id == id }))
        #expect(store.todayProfitCNY == 100)
    }

    @Test @MainActor
    func todaysPriceChangeUsesThePreviousDayRatherThanTheLastTwoChartPoints() throws {
        let repo = try repository()
        let holding = asset(price: 125, category: .fund, name: "Synthetic Fund", symbol: "SYNTHETIC")
        try repo.insert(holding)
        for (ago, price): (Int, Decimal) in [(2, 100), (1, 120)] {
            try repo.replaceDailySnapshots(positions: [asset(id: holding.id, price: price,
                category: .fund, name: holding.name, symbol: holding.symbol)], snapshotDate: day(ago))
        }
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        // A current quote can exist before any snapshot has been written for today.
        #expect(store.todayProfitCNY == 50)
        try store.recordTrade(id: UUID(), side: .add, position: holding, quantity: 2, price: 124,
            fees: 0, tradeDate: .now, cashPositionID: nil)
        #expect(store.todayProfitCNY == 52)
        #expect(try repo.fetchDailyProfitPoints().last?.amountCNY == 52)
    }

    @Test @MainActor
    func additionsSalesBackupAndUndoKeepAllDisplayedTotalsInSync() throws {
        let (repo, holding, cash) = try setup()
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        let addID = UUID(), buyID = UUID(), partialID = UUID(), fullID = UUID()
        try store.recordTrade(id: addID, side: .add, position: holding, quantity: 2, price: 130,
            fees: 0, tradeDate: .now, cashPositionID: nil)
        #expect(store.totalValueCNY == 2560)
        #expect(store.positions.first { $0.id == cash.id }?.quantity == 1000)
        #expect(store.todayProfitCNY == 100)
        var current = try #require(store.positions.first { $0.id == holding.id })
        try store.recordTrade(id: buyID, side: .buy, position: current, quantity: 1, price: 130,
            fees: 2, tradeDate: .now, cashPositionID: cash.id)
        #expect(store.totalValueCNY == 2558)
        #expect(store.todayProfitCNY == 98)
        current = try #require(store.positions.first { $0.id == holding.id })
        try store.recordTrade(id: partialID, side: .sell, position: current, quantity: Decimal(string: "6.5")!, price: 140,
            fees: 3, tradeDate: .now, cashPositionID: cash.id)
        #expect(store.totalValueCNY == 2620)
        #expect(store.todayProfitCNY == 160)
        #expect(try repo.fetchDailyProfitPoints().last?.amountCNY == store.todayProfitCNY)
        current = try #require(store.positions.first { $0.id == holding.id })
        try store.recordTrade(id: fullID, side: .sell, position: current, quantity: current.quantity, price: 130,
            fees: 0, tradeDate: .now, cashPositionID: cash.id)
        #expect(store.positions.count == 1)
        #expect(store.totalValueCNY == 2620)
        #expect(store.todayProfitCNY == 160)
        #expect(store.realizedProfitCNY == 560)
        #expect(store.investmentCloudDailyProfitItems(asOf: .now).reduce(0) { $0 + $1.amountCNY } == 160)
        let restored = try repository()
        _ = try restored.importDataPayload(repo.exportDataPayload())
        let reopened = PortfolioStore(positionRepository: restored, initialLanguage: .chinese)
        #expect(reopened.totalValueCNY == store.totalValueCNY)
        #expect(reopened.todayProfitCNY == store.todayProfitCNY)
        #expect(reopened.realizedProfitCNY == store.realizedProfitCNY)
        for id in [fullID, partialID, buyID, addID] {
            try store.reverseRecord(PositionTransactionRow(try #require(store.positionTrades.first { $0.id == id })))
        }
        #expect(store.positions.first { $0.id == holding.id }?.quantity == 10)
        #expect(store.positions.first { $0.id == holding.id }?.totalCost == 800)
        #expect(store.positions.first { $0.id == cash.id }?.quantity == 1000)
        #expect(store.todayProfitCNY == 100)
        #expect(store.positionTrades.allSatisfy { $0.isReversed })
    }

    @Test @MainActor
    func reversingAListedRecordSupportsLegacyClosuresAndRejectsDuplicateReversal() throws {
        let (repo, holding, cash) = try setup()
        let closure = try repo.closePosition(expected: holding,
            settlement: .init(executionPrice: 130, fees: 0, netProceeds: 1300),
            tradeDate: .now, cashPositionID: cash.id, cashName: "Cash")
        let row = PositionTransactionRow(closure)
        #expect(row.canReverse())
        #expect(!row.canReverse(asOf: Calendar.current.date(byAdding: .day, value: 1, to: .now)!))
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        try store.reverseRecord(row)
        #expect(store.positions.first { $0.id == holding.id }?.quantity == 10)
        #expect(store.positions.first { $0.id == cash.id }?.quantity == 1000)
        let before = try repo.exportDataPayload()
        #expect(throws: (any Error).self) { try store.reverseRecord(row) }
        #expect(try repo.exportDataPayload() == before)
    }

    @Test @MainActor
    func sameDayNewAssetAndFullSaleDoNotLoseOrDoubleCountProfit() throws {
        let repo = try repository()
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        let holding = asset(quantity: 2)
        try store.recordTrade(id: UUID(), side: .add, position: holding, quantity: 2, price: 130,
            fees: 0, tradeDate: .now, cashPositionID: nil)
        #expect(store.todayProfitCNY == 0)
        #expect(try repo.fetchDailyProfitPoints().last?.amountCNY == 0)
        let current = try #require(store.positions.first)
        try store.recordTrade(id: UUID(), side: .sell, position: current, quantity: 2, price: 140,
            fees: 1, tradeDate: .now, cashPositionID: nil)
        #expect(store.todayProfitCNY == 19)
        #expect(store.realizedProfitCNY == 19)
        #expect(try repo.fetchDailyProfitPoints().last?.amountCNY == 19)
        #expect(store.investmentCloudDailyProfitItems(asOf: .now).first?.amountCNY == 19)
        let restored = try repository()
        _ = try restored.importDataPayload(repo.exportDataPayload())
        #expect(PortfolioStore(positionRepository: restored).todayProfitCNY == 19)
        try repo.setAppSetting(key: "mcp_read_access_enabled", value: "true")
        let server = PortfolioMCPServer(databaseURL: repo.storageURL)
        _ = server.respond(to: Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"TradeFixture","version":"1"}}}"#.utf8))
        _ = server.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        let data = try #require(server.respond(to: JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "get_daily_profit",
                "arguments": ["start_date": PositionClosureMath.day(.now), "end_date": PositionClosureMath.day(.now)]]])))
        let response = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])
        let days = try #require(result["days"] as? [[String: String]])
        #expect(days.last?["amount_cny"] == "19")
    }

    @Test @MainActor
    func quoteRefreshAfterAnAdditionCannotRestoreStaleBalancesOrDuplicateProfit() throws {
        let (repo, holding, cash) = try setup()
        _ = try trade(repo, holding, cash, side: .buy, quantity: 1, price: 130, fee: 2)
        try repo.applyQuoteRefresh(updatedPositions: [asset(id: holding.id, price: 140), cash], snapshotPositions: [holding, cash])
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        #expect(store.positions.first { $0.id == holding.id }?.quantity == 11)
        #expect(store.positions.first { $0.id == holding.id }?.totalCost == 932)
        #expect(store.positions.first { $0.id == cash.id }?.quantity == 868)
        #expect(store.todayProfitCNY == 208)
        #expect(try repo.fetchDailyProfitPoints().last?.amountCNY == 208)
    }

    @Test @MainActor
    func rejectedFundingAndSaleLeaveStoreAndBackupUnchanged() throws {
        let (repo, holding, cash) = try setup()
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        let before = try repo.exportDataPayload()
        for (side, quantity, price): (PositionTradeSide, Decimal, Decimal) in [(.buy, 100, 130), (.sell, 11, 130)] {
            #expect(throws: (any Error).self) {
                try store.recordTrade(id: UUID(), side: side, position: holding, quantity: quantity, price: price,
                    fees: 0, tradeDate: .now, cashPositionID: cash.id)
            }
            #expect(try repo.exportDataPayload() == before)
            #expect(store.totalValueCNY == 2300)
            #expect(store.positionTrades.isEmpty)
        }
    }

    @Test
    func externalAdditionsCreateAssetsAndAccumulateUnitsWithoutDebitingCash() throws {
        let (repo, holding, cash) = try setup()
        let record = try trade(repo, holding, nil, side: .add, quantity: 2, price: 100, fee: 3)
        #expect(record.cash == nil)
        #expect(record.cashDelta == 0)
        #expect(record.amount == 203)
        #expect(record.realizedProfit == nil)
        let updated = try #require(repo.fetchPositions().first { $0.id == holding.id })
        #expect(updated.quantity == 12)
        #expect(updated.totalCost == 1003)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 1000)
        let next = Position(id: UUID(), name: "New Gold Asset", symbol: "GOLD", category: .fund,
            quoteCurrency: .cny, quantity: 3, averageCost: 50, latestPrice: 55,
            marketValueCNY: 165, profitRate: 10, weeklyTrend: [55, 55], source: "手工价格", quoteTime: "刚刚", freshness: .manual)
        _ = try trade(repo, next, nil, side: .add, quantity: 3, price: 50, fee: 0)
        #expect(try repo.fetchPositions().first { $0.id == next.id }?.quantity == 3)
        #expect(try repo.fetchPositions().first { $0.id == cash.id }?.quantity == 1000)
        try repo.reverseTrade(id: record.id)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.totalCost == 800)
    }

    @Test(arguments: DisplayCurrency.allCases)
    func cashCanBeAddedAndToppedUpButNeverSold(currency: DisplayCurrency) throws {
        let repo = try repository()
        let cash = PositionClosureMath.cashPosition(currency: currency, quantity: 1, name: "Demo Cash")
        let initial = try trade(repo, cash, nil, side: .add, quantity: Decimal(string: "1000.12345678")!, price: 1, fee: 0)
        #expect(initial.amount == Decimal(string: "1000.12345678"))
        var current = try #require(repo.fetchPositions().first)
        _ = try trade(repo, current, nil, side: .add, quantity: 50, price: 1, fee: 0)
        current = try #require(repo.fetchPositions().first)
        #expect(current.quantity == Decimal(string: "1050.12345678"))
        #expect(current.averageCost == 1)
        #expect(current.totalCost == current.quantity)
        let before = try repo.exportDataPayload()
        #expect(throws: PositionTradeError.invalidInput) { try trade(repo, current, nil, side: .sell, quantity: 1, price: 1, fee: 0) }
        #expect(throws: PositionTradeError.invalidInput) { try trade(repo, current, nil, side: .buy, quantity: 1, price: 1, fee: 0) }
        #expect(throws: PositionTradeError.invalidInput) { try trade(repo, current, nil, side: .add, quantity: 1, price: 2, fee: 0) }
        #expect(try repo.exportDataPayload() == before)
        #expect(try repo.fetchDailyProfitPoints().last?.amountCNY == 0)
    }

    @Test
    func externalCashAdditionCanFundLaterAssetsAndCannotBeUndoneIntoNegativeCash() throws {
        let repo = try repository()
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 1, name: "Demo Cash")
        let deposit = try trade(repo, cash, nil, side: .add, quantity: 1000, price: 1, fee: 0)
        let currentCash = try #require(repo.fetchPositions().first)
        _ = try trade(repo, asset(), currentCash, side: .buy, quantity: 2, price: 100, fee: 1)
        #expect(try repo.fetchPositions().first { $0.id == currentCash.id }?.quantity == 799)
        #expect(throws: PositionTradeError.insufficientCash) { try repo.reverseTrade(id: deposit.id) }
        #expect(try repo.fetchPositionTrades().first { $0.id == deposit.id }?.isReversed == false)
    }

    @Test
    func externalAdditionsSurviveBackupAndImportWithoutCreditingTwice() throws {
        let repo = try repository()
        let record = try trade(repo, asset(), nil, side: .add, quantity: 2, price: 100, fee: 1)
        let archive = repo.storageURL.deletingLastPathComponent().appendingPathComponent("external.zip")
        _ = try PortfolixDataPackageService.write(payload: repo.exportDataPayload(), to: archive)
        let payload = try PortfolixDataPackageService.prepareImport(from: archive).payload
        let restored = try repository()
        _ = try restored.importDataPayload(payload)
        _ = try restored.importDataPayload(payload)
        #expect(try restored.fetchPositions().first?.quantity == 2)
        #expect(try restored.fetchPositions().first?.totalCost == 201)
        #expect(try restored.fetchPositionTrades().first?.cash == nil)
        try restored.reverseTrade(id: record.id)
        #expect(try restored.fetchPositions().isEmpty)
    }

    @Test @MainActor
    func allAssetEntriesShareTheAdditionPresentationIncludingCash() throws {
        let (repo, holding, cash) = try setup()
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        store.presentNewPositionEditor()
        #expect(store.positionEditorPresentation?.position == nil)
        store.presentPositionEditor(for: holding.id)
        #expect(store.positionEditorPresentation?.position?.id == holding.id)
        store.presentPositionEditor(for: cash.id)
        #expect(store.positionEditorPresentation?.position?.category == .cash)
        let host = NSHostingView(rootView: PositionEditorSheet(presentation: .init(position: cash)).environment(store))
        #expect(host.fittingSize == CGSize(width: 620, height: 620))
    }

    @Test
    func agentTransactionsAreReadOnlyAndBuyProfitIsNotZero() throws {
        let (repo, holding, cash) = try setup()
        _ = try trade(repo, holding, cash, side: .buy, quantity: 1, price: 100, fee: 0)
        let request = try AIPortfolioToolRequest(call: LLMFunctionCall(callID: "demo", name: "list_transactions", arguments: "{}"))
        let json = AIPortfolioDataToolExecutor.execute(request, snapshot: .init(positions: try repo.fetchPositions(), trades: try repo.fetchPositionTrades()))
        #expect(json.contains("\"side\":\"buy\""))
        #expect(json.contains("\"realized_profit_quote\":null"))
        #expect(!json.contains("priceHistory"))
        #expect(!AIPortfolioDataToolExecutor.definitions.contains { $0.name == "record_trade" })
    }

    @Test @MainActor
    func storeCloudAndMCPAgreeAfterAllUnitsAreSold() throws {
        let (repo, holding, cash) = try setup()
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        try store.recordTrade(id: UUID(), side: .sell, position: holding, quantity: 10, price: 140,
            fees: 5, tradeDate: .now, cashPositionID: cash.id)
        #expect(store.todayProfitCNY == 195)
        #expect(store.realizedProfitCNY == 595)
        #expect(store.investmentCloudDailyProfitItems(asOf: .now).first?.amountCNY == 195)
        #expect(PortfolioStore(positionRepository: repo).todayProfitCNY == 195)
        #expect(try repo.fetchDailyProfitPoints().last?.amountCNY == 195)
        try repo.setAppSetting(key: "mcp_read_access_enabled", value: "true")
        let server = PortfolioMCPServer(databaseURL: repo.storageURL)
        _ = server.respond(to: try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "TradeFixture", "version": "1"]]]))
        _ = server.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        let data = try #require(server.respond(to: JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "get_daily_profit",
                "arguments": ["start_date": PositionClosureMath.day(day(2)), "end_date": PositionClosureMath.day(.now)]]])))
        let response = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])
        let days = try #require(result["days"] as? [[String: String]])
        #expect(days.last?["amount_cny"] == "195")
    }

    @Test
    func storageFailureRollsBackTradeCashAndHistoricalSnapshotsTogether() throws {
        let (repo, holding, cash) = try setup()
        let before = try repo.exportDataPayload()
        var connection: OpaquePointer?
        #expect(sqlite3_open(repo.storageURL.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        #expect(sqlite3_exec(connection, "CREATE TRIGGER reject_trade BEFORE INSERT ON position_trades BEGIN SELECT RAISE(ABORT, 'fixture'); END", nil, nil, nil) == SQLITE_OK)
        #expect(throws: (any Error).self) { try trade(repo, holding, cash, ago: 2) }
        #expect(try repo.exportDataPayload() == before)
    }

    @Test
    func tradeLinkedBalancesCannotBeDeletedAndOldBackupsCannotSilentlyEraseTheLedger() throws {
        let (repo, holding, cash) = try setup()
        let oldBackup = try repo.exportDataPayload()
        let record = try trade(repo, holding, cash)
        #expect(throws: PositionTradeError.recordedTradesExist) { try repo.delete(positionID: holding.id) }
        #expect(throws: PositionTradeError.recordedTradesExist) { try repo.delete(positionID: cash.id) }
        #expect(throws: (any Error).self) { try repo.importDataPayload(oldBackup) }
        #expect(try repo.fetchPositionTrades().first?.id == record.id)
        #expect(try repo.fetchPositions().first { $0.id == holding.id }?.quantity == 6)
    }

    @Test @MainActor
    func migratedLegacyHoldingsStayOnTheRecordBasedPathAfterReversingLaterTrades() throws {
        let (repo, holding, cash) = try setup()
        let legacy = asset(symbol: "LEGACY")
        try repo.insert(legacy)
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        #expect(store.directlyDeletablePositionIDs.isEmpty)

        let id = UUID()
        try store.recordTrade(id: id, side: .buy, position: holding, quantity: 1, price: 100,
            fees: 0, tradeDate: .now, cashPositionID: cash.id)
        #expect(store.directlyDeletablePositionIDs.isEmpty)
        let before = try repo.exportDataPayload()
        #expect(throws: PositionTradeError.recordedTradesExist) { try store.deletePosition(for: holding.id) }
        #expect(throws: PositionTradeError.recordedTradesExist) { try store.deletePosition(for: cash.id) }
        #expect(try repo.exportDataPayload() == before)

        try store.reverseRecord(PositionTransactionRow(try #require(store.positionTrades.first { $0.id == id })))
        #expect(store.directlyDeletablePositionIDs.isEmpty)
        try store.reverseRecord(PositionTransactionRow(try #require(store.positionOpeningBalances.first { $0.id == legacy.id })))
        #expect(store.positions.allSatisfy { $0.id != legacy.id })
    }

    @Test @MainActor
    func newlyAddedAssetIsRemovedByReversingItsRecordRatherThanDeletingTheHolding() throws {
        let repo = try repository()
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        let holding = asset()
        try store.recordTrade(id: UUID(), side: .add, position: holding, quantity: 2, price: 100,
            fees: 1, tradeDate: .now, cashPositionID: nil)
        #expect(store.directlyDeletablePositionIDs.isEmpty)
        #expect(throws: PositionTradeError.recordedTradesExist) { try store.deletePosition(for: holding.id) }
        let row = PositionTransactionRow(try #require(store.positionTrades.first))
        try store.reverseRecord(row)
        #expect(store.positions.isEmpty)
        #expect(store.positionTrades.first?.isReversed == true)
    }

    @Test @MainActor
    func legacyClosureAlsoProtectsItsCashAccountUntilTheRecordIsReversed() throws {
        let (repo, holding, cash) = try setup()
        let record = try repo.closePosition(expected: holding,
            settlement: .init(executionPrice: 130, fees: 0, netProceeds: 1300),
            tradeDate: .now, cashPositionID: cash.id, cashName: "Cash")
        let store = PortfolioStore(positionRepository: repo, initialLanguage: .chinese)
        #expect(store.directlyDeletablePositionIDs.isEmpty)
        let before = try repo.exportDataPayload()
        #expect(throws: PositionTradeError.recordedTradesExist) { try store.deletePosition(for: cash.id) }
        #expect(throws: PositionTradeError.recordedTradesExist) { try repo.delete(positionID: cash.id) }
        #expect(try repo.exportDataPayload() == before)
        try store.reverseRecord(PositionTransactionRow(record))
        #expect(store.directlyDeletablePositionIDs.isEmpty)
    }

    @Test
    func mixedBatchDeletionIsRejectedAtomicallyWhenAnyBalanceHasAnActiveRecord() throws {
        let (repo, holding, cash) = try setup()
        let legacy = asset(symbol: "LEGACY")
        try repo.insert(legacy)
        _ = try trade(repo, holding, cash)
        let before = try repo.exportDataPayload()
        #expect(throws: PositionTradeError.recordedTradesExist) {
            try repo.delete(positionIDs: [legacy.id, holding.id, cash.id])
        }
        #expect(try repo.exportDataPayload() == before)
        #expect(throws: PositionTradeError.recordedTradesExist) { try repo.delete(positionID: legacy.id) }
        try repo.reverseOpeningBalance(id: legacy.id)
        #expect(try repo.fetchPositions().allSatisfy { $0.id != legacy.id })
    }

    @Test
    func accountLinksNormalizeIdentifiersAndIgnoreReversedRecords() throws {
        let (repo, holding, cash) = try setup()
        let record = try trade(repo, holding, cash)
        var imported = record.remapping([
            holding.id.uuidString: holding.id.uuidString.lowercased(),
            cash.id.uuidString: cash.id.uuidString.lowercased()
        ])
        #expect(PositionRecordLinks.activeAccountIDs(trades: [imported], closures: []) == [holding.id, cash.id])
        imported.reversedAt = ISO8601DateFormatter().string(from: .now)
        #expect(PositionRecordLinks.activeAccountIDs(trades: [imported], closures: []).isEmpty)
    }

    @Test @MainActor
    func newSheetsFitBothLanguagesAndAppearances() throws {
        let (repo, holding, cash) = try setup()
        for language: AppLanguage in [.chinese, .english] {
            let store = PortfolioStore(positionRepository: repo, initialLanguage: language)
            for scheme: ColorScheme in [.light, .dark] {
                if let path = ProcessInfo.processInfo.environment["PORTFOLIX_TRADE_PREVIEW_DIRECTORY"] {
                    let editor = PortfolixDateTimeEditor(selection: .constant(.now), language: language, onDone: {})
                    let host = NSHostingView(rootView: editor.environment(\.colorScheme, scheme))
                    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    host.frame = CGRect(origin: .zero, size: host.fittingSize)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let directory = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let data = try #require(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("date-editor-\(language == .english ? "en" : "zh")-\(scheme == .dark ? "dark" : "light").png"))
                }
                let views: [(String, AnyView, CGSize)] = [
                    ("reconcile", AnyView(PositionReconciliationSheet(position: holding).environment(store)), CGSize(width: 620, height: 760)),
                    ("reconcile-cash", AnyView(PositionReconciliationSheet(position: cash).environment(store)), CGSize(width: 620, height: 580)),
                    ("sell", AnyView(PositionTradeSheet(position: holding).environment(store)), CGSize(width: 620, height: 700)),
                    ("add-new", AnyView(PositionEditorSheet(presentation: .init(position: nil)).environment(store)), CGSize(width: 620, height: 780)),
                    ("add-existing", AnyView(PositionEditorSheet(presentation: .init(position: holding)).environment(store)), CGSize(width: 620, height: 780)),
                    ("add-cash", AnyView(PositionEditorSheet(presentation: .init(position: cash)).environment(store)), CGSize(width: 620, height: 620)),
                    ("cash", AnyView(CashReductionSheet(position: cash).environment(store)), CGSize(width: 620, height: 460)),
                    ("risk", AnyView(RiskQuestionnaireSheet().environment(store)), CGSize(width: 640, height: 680)),
                    ("model-settings", AnyView(LLMConfigurationSheet().environment(store)), CGSize(width: 560, height: 420)),
                    ("search-settings", AnyView(SearchConfigurationSheet().environment(store)), CGSize(width: 560, height: 620)),
                    ("holdings", AnyView(PositionsView().environment(store).frame(width: 960, height: 640)), CGSize(width: 960, height: 640))]
                for (name, view, size) in views {
                    let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
                    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    #expect(host.fittingSize == size)
                    host.frame = CGRect(origin: .zero, size: size)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    #expect(bitmap.pixelsWide > 0)
                    if let path = ProcessInfo.processInfo.environment["PORTFOLIX_TRADE_PREVIEW_DIRECTORY"] {
                        let folder = URL(fileURLWithPath: path)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let data = try #require(bitmap.representation(using: .png, properties: [:]))
                        try data.write(to: folder.appendingPathComponent("\(name)-\(language == .english ? "en" : "zh")-\(scheme == .dark ? "dark" : "light").png"))
                    }
                }
            }
        }
    }

    @Test
    func prepareIsolatedTradeDemoOnlyWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["PORTFOLIX_TRADE_DEMO_DATABASE"] else { return }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"),
              !FileManager.default.fileExists(atPath: path) else { throw PositionTradeError.changed }
        let repo = try PositionRepository(databaseURL: url)
        let holding = asset()
        let cash = PositionClosureMath.cashPosition(currency: .cny, quantity: 10000, name: "现金 CNY")
        try repo.insert(holding); try repo.insert(cash)
        for ago in (0...5).reversed() {
            try repo.replaceDailySnapshots(positions: [asset(id: holding.id, price: Decimal(130 - ago * 2)), cash], snapshotDate: day(ago))
        }
        _ = try trade(repo, holding, cash, side: .buy, quantity: 2, price: 120, fee: 2, ago: 2)
        let current = try #require(repo.fetchPositions().first { $0.id == holding.id })
        _ = try trade(repo, current, cash, quantity: 3, price: 130, fee: 1, ago: 1)
        try repo.setAppSetting(key: "app_language", value: AppLanguage.chinese.rawValue)
    }
}
