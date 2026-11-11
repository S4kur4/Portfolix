import Foundation

/// Display-only leading zeros keep a new portfolio's selected date range visible.
/// They never become ledger snapshots or participate in return calculations.
struct PerformanceTrendChartData {
    struct Point: Identifiable {
        let date: Date
        let value: Double
        let snapshot: PortfolioSnapshot?

        var id: Date { date }
    }

    let points: [Point]
    let yDomain: ClosedRange<Double>

    init(snapshots: [PortfolioSnapshot], metric: TrendMetric, currency: DisplayCurrency,
         domain: ClosedRange<Date>, calendar: Calendar = .current) {
        let recorded = snapshots.filter { domain.contains(calendar.startOfDay(for: $0.date)) }
            .sorted { $0.date < $1.date }
        let firstRecordedDay = recorded.first.map { calendar.startOfDay(for: $0.date) }
        let leadingEnd = firstRecordedDay ?? domain.upperBound
        var points: [Point] = []
        var cursor = domain.lowerBound
        while cursor < leadingEnd {
            points.append(Point(date: cursor, value: 0, snapshot: nil))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        if recorded.isEmpty {
            points.append(Point(date: domain.upperBound, value: 0, snapshot: nil))
        }
        for snapshot in recorded where snapshot.costIsKnown {
            let value = metric == .profitValue
                ? snapshot.profitCNY * currency.rateFromCNY.doubleValue
                : snapshot.profitRate
            points.append(Point(date: calendar.startOfDay(for: snapshot.date), value: value, snapshot: snapshot))
        }
        self.points = points

        let minimum = min(points.map(\.value).min() ?? 0, 0)
        let maximum = max(points.map(\.value).max() ?? 0, 0)
        let padding = max((maximum - minimum) * 0.18, metric == .profitValue ? 2_000 : 0.3)
        let lower = minimum < 0 ? minimum - padding : 0
        let upper = maximum > 0 || minimum == 0 ? maximum + padding : 0
        yDomain = lower ... upper
    }
}
