import Foundation
import Testing
@testable import Portfolix

struct PrimaryPositionOrderingTests {
    @Test
    func limitsByMarketValueBeforeApplyingSelectedSort() {
        let positions = (1 ... 12).map { index in
            makePosition(
                name: "Asset \(index)",
                marketValue: Decimal(index * 100),
                profitRate: Decimal(index)
            )
        }

        let visible = PrimaryPositionOrdering.visiblePositions(
            from: positions,
            limit: .top5,
            sortField: .profitRate,
            direction: .ascending,
            todayProfit: { _ in 0 }
        )

        #expect(visible.count == 5)
        #expect(visible.first?.name == "Asset 8")
        #expect(visible.last?.name == "Asset 12")
        #expect(!visible.contains(where: { $0.name == "Asset 7" }))
    }

    @Test
    func limitsCapVisibleHoldingsAtFiveTenOrAll() {
        #expect(PrimaryPositionDisplayLimit.top5.maximumCount(totalCount: 1) == 1)
        #expect(PrimaryPositionDisplayLimit.top5.maximumCount(totalCount: 13) == 5)
        #expect(PrimaryPositionDisplayLimit.top10.maximumCount(totalCount: 13) == 10)
        #expect(PrimaryPositionDisplayLimit.top10.maximumCount(totalCount: 7) == 7)
        #expect(PrimaryPositionDisplayLimit.all.maximumCount(totalCount: 13) == nil)
    }

    @Test
    func sortsVisiblePositionsByEachSupportedMetric() {
        let lowValue = makePosition(name: "Low", marketValue: 100, profitRate: 30)
        let mediumValue = makePosition(name: "Medium", marketValue: 200, profitRate: 20)
        let highValue = makePosition(name: "High", marketValue: 300, profitRate: 10)
        let todayProfit: [Position.ID: Decimal] = [
            lowValue.id: 3,
            mediumValue.id: 1,
            highValue.id: 2,
        ]

        let marketAscending = PrimaryPositionOrdering.visiblePositions(
            from: [mediumValue, highValue, lowValue],
            limit: .all,
            sortField: .marketValue,
            direction: .ascending,
            todayProfit: { todayProfit[$0.id] ?? 0 }
        )
        let returnDescending = PrimaryPositionOrdering.visiblePositions(
            from: [mediumValue, highValue, lowValue],
            limit: .all,
            sortField: .profitRate,
            direction: .descending,
            todayProfit: { todayProfit[$0.id] ?? 0 }
        )
        let todayAscending = PrimaryPositionOrdering.visiblePositions(
            from: [mediumValue, highValue, lowValue],
            limit: .all,
            sortField: .todayProfit,
            direction: .ascending,
            todayProfit: { todayProfit[$0.id] ?? 0 }
        )

        #expect(marketAscending.map(\.name) == ["Low", "Medium", "High"])
        #expect(returnDescending.map(\.name) == ["Low", "Medium", "High"])
        #expect(todayAscending.map(\.name) == ["Medium", "High", "Low"])
    }

    @Test
    func calculatesDailyProfitOncePerVisibleHoldingAndKeepsTieOrder() {
        let positions = (1...12).map {
            makePosition(name: "Asset \($0)", marketValue: Decimal($0), profitRate: 0)
        }
        var calls: [Position.ID] = []

        let visible = PrimaryPositionOrdering.visiblePositions(
            from: positions, limit: .top5, sortField: .todayProfit, direction: .ascending
        ) { position in
            calls.append(position.id)
            return 1
        }

        #expect(calls == positions.suffix(5).reversed().map(\.id))
        #expect(visible.map(\.id) == calls)
    }

    @Test
    func detailTableSortsByTotalCostMarketValueAndReturnRate() {
        let first = makePosition(name: "First", marketValue: 300, profitRate: -5, totalCost: 100)
        let second = makePosition(name: "Second", marketValue: 100, profitRate: 15, totalCost: 300)
        let third = makePosition(name: "Third", marketValue: 200, profitRate: 5, totalCost: 200)
        let positions = [first, second, third]

        let byCost = PositionDetailOrdering.sorted(
            positions,
            using: [KeyPathComparator(\Position.totalCost, order: .forward)]
        )
        let byMarketValue = PositionDetailOrdering.sorted(
            positions,
            using: [KeyPathComparator(\Position.marketValueCNY, order: .reverse)]
        )
        let byReturnRate = PositionDetailOrdering.sorted(
            positions,
            using: [KeyPathComparator(\Position.profitRate, order: .forward)]
        )

        #expect(byCost.map(\.name) == ["First", "Third", "Second"])
        #expect(byMarketValue.map(\.name) == ["First", "Third", "Second"])
        #expect(byReturnRate.map(\.name) == ["First", "Third", "Second"])
    }

    @Test
    func holdingSequenceNumbersFollowTheCurrentlySortedAndFilteredRows() {
        let positions = [makePosition(name: "First", marketValue: 300, profitRate: -5),
                         makePosition(name: "Second", marketValue: 100, profitRate: 15),
                         makePosition(name: "Third", marketValue: 200, profitRate: 5)]
        for order: SortOrder in [.forward, .reverse] {
            let sorted = PositionDetailOrdering.sorted(positions, using: [KeyPathComparator(\Position.marketValueCNY, order: order)])
            let numbers = PositionDetailOrdering.displayNumbers(for: sorted)
            #expect(sorted.compactMap { numbers[$0.id] } == [1, 2, 3])
            let filtered = sorted.filter { $0.name != "Second" }
            let filteredNumbers = PositionDetailOrdering.displayNumbers(for: filtered)
            #expect(filtered.compactMap { filteredNumbers[$0.id] } == [1, 2])
        }
        #expect(PositionDetailOrdering.displayNumbers(for: []).isEmpty)
    }

    private func makePosition(
        name: String,
        marketValue: Decimal,
        profitRate: Decimal,
        totalCost: Decimal = 1
    ) -> Position {
        Position(
            id: UUID(),
            name: name,
            symbol: name.uppercased(),
            category: .cnStock,
            quoteCurrency: .cny,
            quantity: 1,
            averageCost: totalCost,
            latestPrice: marketValue,
            marketValueCNY: marketValue,
            profitRate: profitRate,
            weeklyTrend: [1, 1],
            source: "手工价格",
            quoteTime: "刚刚",
            fetchedAt: ISO8601DateFormatter().string(from: .now),
            freshness: .manual
        )
    }
}
