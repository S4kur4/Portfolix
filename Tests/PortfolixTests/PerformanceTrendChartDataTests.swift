import Foundation
import Testing
@testable import Portfolix

@Suite("Return trend presentation")
struct PerformanceTrendChartDataTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var today: Date { Date(timeIntervalSince1970: 1_794_268_800) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func snapshot(_ offset: Int, rate: Double, knownCost: Bool = true) -> PortfolioSnapshot {
        PortfolioSnapshot(date: day(offset), totalValueCNY: 10_000 * (1 + rate / 100),
            profitRate: rate, costIsKnown: knownCost)
    }

    @Test(arguments: TrendRange.allCases)
    func emptyHistoryDrawsAZeroLineAcrossTheSelectedRange(range: TrendRange) {
        let domain = day(-range.days) ... today
        let chart = PerformanceTrendChartData(snapshots: [], metric: .profitValue,
            currency: .cny, domain: domain, calendar: calendar)
        #expect(chart.points.first?.date == domain.lowerBound)
        #expect(chart.points.last?.date == today)
        #expect(chart.points.count == range.days + 1)
        #expect(chart.points.allSatisfy { $0.value == 0 && $0.snapshot == nil })
        #expect(chart.yDomain.lowerBound == 0)
        #expect(chart.yDomain.upperBound > 0)
    }

    @Test(arguments: TrendRange.allCases)
    func aSingleSnapshotGetsLeadingZerosWithoutChangingItsRealReturn(range: TrendRange) {
        let actual = snapshot(0, rate: 16)
        let chart = PerformanceTrendChartData(snapshots: [actual], metric: .profitValue,
            currency: .cny, domain: day(-range.days) ... today, calendar: calendar)
        #expect(chart.points.count == range.days + 1)
        #expect(chart.points.dropLast().allSatisfy { $0.value == 0 && $0.snapshot == nil })
        #expect(chart.points.last?.snapshot?.id == actual.id)
        #expect(abs((chart.points.last?.value ?? 0) - 1_600) < 0.000001)
        #expect(chart.yDomain.lowerBound == 0)
        #expect(chart.yDomain.upperBound > 1_600)
        #expect(actual.profitRate == 16)
    }

    @Test(arguments: [TrendMetric.profitValue, .profitRate])
    func zeroReturnsStayOnTheBottomWithANonzeroScale(metric: TrendMetric) {
        let chart = PerformanceTrendChartData(snapshots: [snapshot(0, rate: 0)], metric: metric,
            currency: .usd, domain: day(-29) ... today, calendar: calendar)
        #expect(chart.points.allSatisfy { $0.value == 0 })
        #expect(chart.yDomain.lowerBound == 0)
        #expect(chart.yDomain.upperBound > 0)
    }

    @Test
    func negativeAndMixedReturnsRemainVisibleAlongWithZero() {
        for rates in [[-10.0, -5], [-5.0, 10]] {
            let chart = PerformanceTrendChartData(snapshots: [snapshot(-29, rate: rates[0]), snapshot(0, rate: rates[1])],
                metric: .profitRate, currency: .cny, domain: day(-29) ... today, calendar: calendar)
            #expect(chart.yDomain.contains(0))
            #expect(chart.yDomain.lowerBound < rates.min()!)
            #expect(chart.points.count == 2)
            #expect(chart.points.allSatisfy { chart.yDomain.contains($0.value) })
        }
    }

    @Test
    func existingHistoryKeepsItsValuesAndDoesNotFillInternalGapsWithZero() {
        let records = [snapshot(0, rate: 10), snapshot(-29, rate: 3), snapshot(-10, rate: 5)]
        let chart = PerformanceTrendChartData(snapshots: records, metric: .profitValue,
            currency: .usd, domain: day(-29) ... today, calendar: calendar)
        #expect(chart.points.count == 3)
        #expect(chart.points.map(\.date) == [day(-29), day(-10), today])
        #expect(Set(chart.points.compactMap { $0.snapshot?.id }) == Set(records.map(\.id)))
        #expect(abs(chart.points[2].value - 1_000 * DisplayCurrency.usd.rateFromCNY.doubleValue) < 0.000001)
    }

    @Test
    func unknownCostIsNotPresentedAsARecordedZeroReturn() {
        let unknown = snapshot(-10, rate: 0, knownCost: false)
        let actual = snapshot(0, rate: 10)
        let chart = PerformanceTrendChartData(snapshots: [unknown, actual], metric: .profitRate,
            currency: .cny, domain: day(-29) ... today, calendar: calendar)
        #expect(chart.points.filter { $0.snapshot == nil }.allSatisfy { $0.date < unknown.date })
        #expect(chart.points.compactMap { $0.snapshot?.id } == [actual.id])
    }

    @Test
    func datesOutsideTheSelectedRangeCannotChangeTheScaleOrLeadingZeros() {
        let actual = snapshot(0, rate: 5)
        let chart = PerformanceTrendChartData(snapshots: [snapshot(-40, rate: -99), actual, snapshot(1, rate: 500)],
            metric: .profitRate, currency: .cny, domain: day(-29) ... today, calendar: calendar)
        #expect(chart.points.compactMap { $0.snapshot?.id } == [actual.id])
        #expect(chart.points.count == 30)
        #expect(chart.yDomain.lowerBound == 0)
        #expect(chart.yDomain.upperBound < 10)
    }

    @Test
    func dailySpacingSurvivesADaylightSavingTimeChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let chart = PerformanceTrendChartData(snapshots: [], metric: .profitRate,
            currency: .cny, domain: start ... end, calendar: calendar)
        #expect(chart.points.count == 5)
        #expect(chart.points.allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
        #expect(Set(chart.points.map(\.date)).count == 5)
        #expect(chart.points.last?.date == end)
    }
}
