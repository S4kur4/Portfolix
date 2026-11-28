import Foundation
import Testing
@testable import Portfolix

@Suite("Investment cloud display items")
struct InvestmentCloudDisplayItemsTests {
    private func item(_ id: String, percentage: Double, amount: Decimal) -> InvestmentCloudItem {
        InvestmentCloudItem(distribution: InvestmentDistributionItem(
            domain: InvestmentDomain(id: id, titleChinese: id, titleEnglish: id),
            amountCNY: amount,
            percentage: percentage
        ))
    }

    @Test func aggregatesSmallSlicesIntoOtherTile() {
        let items = [
            item("a", percentage: 50, amount: 5000),
            item("b", percentage: 30, amount: 3000),
            item("c", percentage: 15, amount: 1500),
            item("d", percentage: 5, amount: 500),
        ]
        let prepared = InvestmentCloudEngine.displayItems(
            items, minimumShare: 0.1, maximumItems: 8
        ) { $0.distributionPercentage ?? 0 }

        #expect(prepared.count == 4)
        #expect(prepared.first?.id == "a")
        #expect(prepared.last?.isAggregated == true)
        #expect(prepared.last?.aggregatedCount == 1)
        #expect(prepared.last?.amountCNY == 500)
        #expect(prepared.last?.titleChinese == "其他 1 项")
        #expect(prepared.last?.titleEnglish == "1 other")
    }

    @Test func capsTileCountByAggregatingTail() {
        let items = (0..<8).map { index in
            item("item\(index)", percentage: 12.5, amount: Decimal(index + 1) * 100)
        }
        let prepared = InvestmentCloudEngine.displayItems(
            items, minimumShare: 0.01, maximumItems: 4
        ) { $0.distributionPercentage ?? 0 }

        #expect(prepared.count == 4)
        #expect(prepared.last?.isAggregated == true)
        #expect(prepared.last?.aggregatedCount == 5)
        #expect(prepared.last?.amountCNY == 3000)
    }

    @Test func combinesSmallAndOverflowTilesWithoutDuplicateIDs() {
        let large = (0..<6).map { item("large-\($0)", percentage: 12, amount: 12) }
        let small = (0..<14).map { item("small-\($0)", percentage: 2, amount: 2) }
        let prepared = InvestmentCloudEngine.displayItems(
            large + small, minimumShare: 0.04, maximumItems: 4
        ) { $0.distributionPercentage ?? 0 }

        #expect(prepared.count == 4)
        #expect(Set(prepared.map(\.id)).count == prepared.count)
        #expect(prepared.last?.aggregatedCount == 17)
        #expect(prepared.last?.amountCNY == 64)
        #expect(prepared.reduce(Decimal(0)) { $0 + $1.amountCNY } == 100)
    }

    @Test func dropsItemsWithoutPositiveDisplayWeight() {
        let items = [
            item("zero", percentage: 0, amount: 0),
            item("value", percentage: 100, amount: 1000),
        ]
        let prepared = InvestmentCloudEngine.displayItems(items, minimumShare: 0.02) {
            $0.marketValueCNY?.doubleValue ?? 0
        }

        #expect(prepared.map(\.id) == ["value"])
    }

    @Test func dailyProfitModeWeightsTilesByAbsoluteProfitMagnitudeRatherThanMarketValue() {
        let largeBondTinyLoss = Position(
            id: UUID(),
            name: "中短债基金",
            symbol: "000001",
            category: .fund,
            quoteCurrency: .cny,
            quantity: 500_000,
            totalCost: 500_000,
            averageCost: 1,
            latestPrice: 1,
            marketValueCNY: 500_000,
            profitRate: 0,
            weeklyTrend: [],
            source: "Fund",
            quoteTime: "2026-11-27",
            freshness: .updated
        )
        let smallEquityBigGain = Position(
            id: UUID(),
            name: "科技ETF",
            symbol: "515000",
            category: .fund,
            quoteCurrency: .cny,
            quantity: 10_000,
            totalCost: 40_000,
            averageCost: 4,
            latestPrice: 5,
            marketValueCNY: 50_000,
            profitRate: 25,
            weeklyTrend: [],
            source: "Fund",
            quoteTime: "2026-11-27",
            freshness: .updated
        )
        let cryptoBigLoss = Position(
            id: UUID(),
            name: "BTC",
            symbol: "BTC/USDT",
            category: .crypto,
            quoteCurrency: .usdt,
            quantity: 0.2,
            totalCost: 15_000,
            averageCost: 75_000,
            latestPrice: 70_000,
            marketValueCNY: 100_000,
            profitRate: -6.67,
            weeklyTrend: [],
            source: "OKX",
            quoteTime: "2026-11-27",
            freshness: .updated
        )

        let rawItems = [
            InvestmentCloudItem(position: largeBondTinyLoss, dailyProfitCNY: Decimal(string: "-69.72")!),
            InvestmentCloudItem(position: smallEquityBigGain, dailyProfitCNY: Decimal(string: "12500.00")!),
            InvestmentCloudItem(position: cryptoBigLoss, dailyProfitCNY: Decimal(string: "-2382.39")!),
        ]
        let weight: (InvestmentCloudItem) -> Double = {
            InvestmentCloudEngine.displayWeight(for: $0, mode: .dailyProfit)
        }
        let prepared = InvestmentCloudEngine.displayItems(
            rawItems,
            minimumShare: 0.02,
            maximumItems: 12,
            weight: weight
        )

        #expect(prepared.count == 3)
        #expect(prepared[0].titleChinese == "科技ETF")
        #expect(prepared[1].titleChinese == "BTC")
        #expect(prepared[2].isAggregated == true)
        #expect(weight(prepared[0]) > weight(prepared[1]))
        #expect(weight(prepared[1]) > weight(prepared[2]))
    }
}
