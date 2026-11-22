import Foundation
import Testing
@testable import Portfolix

@Suite("Dashboard performance risk chart data")
struct PerformanceRiskChartDataTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ index: Int) -> Date {
        Date(timeIntervalSince1970: Double(index) * 86_400)
    }

    @Test func reusesExactZeroAtBothBoundaries() {
        let series = ProfitAreaSeries.make(from: [
            (day(0), -5), (day(1), 0), (day(2), -10)
        ])
        #expect(series.map(\.isPositive) == [false, true, false])
        #expect(series.map { $0.points.map(\.date) } == [[day(0), day(1)], [day(1)], [day(1), day(2)]])
    }

    @Test func interpolatesCrossingBetweenSamples() {
        let start = day(1)
        let end = day(2)
        let crossing = start.addingTimeInterval(21_600)
        let series = ProfitAreaSeries.make(from: [(start, -1), (end, 3)])
        #expect(series.count == 2)
        #expect(series.map { $0.points.map(\.date) } == [[start, crossing], [crossing, end]])
        #expect(series.map { $0.points.map(\.value) } == [[-1, 0], [0, 3]])
    }

    @Test func volatilityUsesPriorSnapshotEvenAfterLastSnapshotDate() throws {
        let data = PerformanceRiskChartData(
            snapshots: [
                PortfolioSnapshot(date: day(12), totalValueCNY: 2_000, profitRate: 0),
                PortfolioSnapshot(date: day(10), totalValueCNY: 1_000, profitRate: 0),
            ],
            dailyProfit: [
                DailyProfitPoint(date: day(13), amountCNY: 600),
                DailyProfitPoint(date: day(12), amountCNY: 100),
            ],
            range: .all,
            calendar: calendar,
            now: day(13)
        )
        let volatility = try #require(data.summary.annualizedVolatility)
        #expect(abs(volatility - 10 * (252.0).squareRoot()) < 0.000_001)
    }

    @Test func drawdownKeepsEarlierPeakOutsideSelectedRange() {
        let data = PerformanceRiskChartData(
            snapshots: [
                PortfolioSnapshot(date: day(0), totalValueCNY: 1_200, profitRate: 20),
                PortfolioSnapshot(date: day(40), totalValueCNY: 1_100, profitRate: 10),
                PortfolioSnapshot(date: day(41), totalValueCNY: .infinity, profitRate: 10),
            ],
            dailyProfit: [],
            range: .month,
            calendar: calendar,
            now: day(41)
        )
        #expect(data.points.map(\.date) == [day(40)])
        #expect(data.summary.currentDrawdownCNY == -100)
        #expect(data.summary.currentDrawdownRate == -10)
    }
}
