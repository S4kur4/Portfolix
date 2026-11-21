import Foundation
import Testing
@testable import Portfolix

@Suite("Daily profit month filtering")
struct DailyProfitMonthFilterTests {
    @Test func monthFilterUsesHalfOpenRange() throws {
        let calendar = Calendar.current
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let interval = calendar.dateInterval(of: .month, for: anchor)!

        let firstInMonth = DailyProfitPoint(date: interval.start, amountCNY: 10)
        let lastInMonth = DailyProfitPoint(
            date: calendar.date(byAdding: .day, value: -1, to: interval.end)!,
            amountCNY: -5
        )
        let firstOfNextMonth = DailyProfitPoint(date: interval.end, amountCNY: 7)
        let lastOfPreviousMonth = DailyProfitPoint(date: interval.start.addingTimeInterval(-1), amountCNY: 3)

        let filtered = dailyProfitPointsInMonth(
            [firstInMonth, lastInMonth, firstOfNextMonth, lastOfPreviousMonth],
            in: interval
        )

        #expect(filtered.count == 2)
        #expect(filtered.map(\.amountCNY) == [10, -5])
    }
}
