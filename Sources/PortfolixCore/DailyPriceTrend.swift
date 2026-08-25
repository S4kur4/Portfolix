import Foundation

public enum DailyPriceTrend {
    public static func merging(
        existing: [Double],
        latestPrice: Double,
        previousFetchedAt: Date?,
        fetchedAt: Date,
        maximumCount: Int = 7,
        calendar: Calendar = .current
    ) -> [Double] {
        guard maximumCount > 0 else { return [] }
        guard !existing.isEmpty else { return [latestPrice] }

        var trend = existing
        if let previousFetchedAt, calendar.isDate(previousFetchedAt, inSameDayAs: fetchedAt) {
            trend[trend.count - 1] = latestPrice
            return Array(trend.suffix(maximumCount))
        }

        trend.append(latestPrice)
        return Array(trend.suffix(maximumCount))
    }
}
