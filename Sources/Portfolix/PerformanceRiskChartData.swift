import Foundation

struct PerformanceRiskPoint: Identifiable {
    let date: Date
    let drawdownCNY: Double
    let profitCNY: Double
    let profitRate: Double
    let peakProfitRate: Double

    var id: Date { date }
}

struct ProfitAreaPoint: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

struct ProfitAreaSeries: Identifiable {
    let id: String
    let isPositive: Bool
    let points: [ProfitAreaPoint]
}

struct PerformanceRiskSummary {
    let currentDrawdownCNY: Double
    let currentDrawdownRate: Double
    let currentProfitCNY: Double
    let currentProfitRate: Double
    let maxDrawdownCNY: Double
    let maxDrawdownDate: Date?
    let maxDrawdownRate: Double?
    let annualizedVolatility: Double?
    let upDayRatio: Double?
    let upDayCount: Int
    let trackedDayCount: Int
    let worstDayCNY: Double?
    let worstDayDate: Date?

    static let empty = PerformanceRiskSummary(
        currentDrawdownCNY: 0,
        currentDrawdownRate: 0,
        currentProfitCNY: 0,
        currentProfitRate: 0,
        maxDrawdownCNY: 0,
        maxDrawdownDate: nil,
        maxDrawdownRate: nil,
        annualizedVolatility: nil,
        upDayRatio: nil,
        upDayCount: 0,
        trackedDayCount: 0,
        worstDayCNY: nil,
        worstDayDate: nil
    )
}

extension ProfitAreaSeries {
    /// Adjacent sign runs meet at zero. Reuse any measured zero at the run boundary
    /// so each series has only one point at a given date.
    static func make(from samples: [(date: Date, value: Double)]) -> [Self] {
        var series: [Self] = []
        var start = 0
        while start < samples.count {
            let isPositive = samples[start].value >= 0
            var end = start
            while end + 1 < samples.count, (samples[end + 1].value >= 0) == isPositive {
                end += 1
            }

            var points: [ProfitAreaPoint] = []
            if start > 0, samples[start].value != 0 {
                let crossing = zeroCrossing(samples[start - 1], samples[start])
                if crossing.date < samples[start].date { points.append(crossing) }
            }
            points.append(contentsOf: samples[start...end].map {
                ProfitAreaPoint(date: $0.date, value: $0.value)
            })
            if end + 1 < samples.count, samples[end].value != 0 {
                let crossing = zeroCrossing(samples[end], samples[end + 1])
                if crossing.date > samples[end].date { points.append(crossing) }
            }

            series.append(Self(
                id: "\(isPositive ? "positive" : "negative")-\(series.count)",
                isPositive: isPositive,
                points: points
            ))
            start = end + 1
        }
        return series
    }

    private static func zeroCrossing(
        _ start: (date: Date, value: Double),
        _ end: (date: Date, value: Double)
    ) -> ProfitAreaPoint {
        if start.value == 0 { return ProfitAreaPoint(date: start.date, value: 0) }
        if end.value == 0 { return ProfitAreaPoint(date: end.date, value: 0) }
        let fraction = start.value / (start.value - end.value)
        let date = start.date.addingTimeInterval(end.date.timeIntervalSince(start.date) * fraction)
        return ProfitAreaPoint(date: date, value: 0)
    }
}

struct PerformanceRiskChartData {
    let points: [PerformanceRiskPoint]
    let summary: PerformanceRiskSummary

    init(
        snapshots: [PortfolioSnapshot],
        dailyProfit: [DailyProfitPoint],
        range: PerformanceRiskRange,
        calendar: Calendar,
        now: Date
    ) {
        let today = calendar.startOfDay(for: now)
        let start = range.days.map { calendar.date(byAdding: .day, value: -$0, to: today) ?? today }
            ?? .distantPast
        let history = snapshots.filter(\.costIsKnown).sorted { $0.date < $1.date }
        var snapshotByDay: [Date: PortfolioSnapshot] = [:]
        var positiveValueByDay: [Date: Double] = [:]
        for snapshot in history {
            let day = calendar.startOfDay(for: snapshot.date)
            snapshotByDay[day] = snapshot
            if snapshot.totalValueCNY.isFinite, snapshot.totalValueCNY > 0 {
                positiveValueByDay[day] = snapshot.totalValueCNY
            }
        }

        var peakProfit: Double?
        var peakRate: Double?
        var riskPoints: [PerformanceRiskPoint] = []
        for (day, snapshot) in snapshotByDay.sorted(by: { $0.key < $1.key }) {
            guard day <= today else { break }
            let profit = snapshot.profitCNY
            let rate = snapshot.profitRate
            // Non-finite values cannot be plotted or converted to Decimal for labels.
            guard profit.isFinite, rate.isFinite else { continue }
            let newPeakProfit = max(peakProfit ?? profit, profit)
            let newPeakRate = max(peakRate ?? rate, rate)
            peakProfit = newPeakProfit
            peakRate = newPeakRate
            guard day >= start else { continue }
            riskPoints.append(PerformanceRiskPoint(
                date: day,
                drawdownCNY: profit - newPeakProfit,
                profitCNY: profit,
                profitRate: rate,
                peakProfitRate: newPeakRate
            ))
        }
        points = riskPoints
        guard let latest = riskPoints.last else {
            summary = .empty
            return
        }

        let dailyPoints = dailyProfit
            .map { (day: calendar.startOfDay(for: $0.date), point: $0) }
            .filter { $0.day >= start && $0.day <= today }
            .sorted { $0.point.date < $1.point.date }
        let maxPoint = riskPoints.min { $0.drawdownCNY < $1.drawdownCNY }
        let worst = dailyPoints.min { $0.point.amountCNY < $1.point.amountCNY }
        let upDays = dailyPoints.count { $0.point.amountCNY > 0 }
        let trackedDays = dailyPoints.count { $0.point.amountCNY != 0 }

        var returns: [Double] = []
        let values = positiveValueByDay.sorted { $0.key < $1.key }
        var next = values.startIndex
        for (day, point) in dailyPoints {
            // Use the most recent strictly earlier snapshot, including when day is
            // later than the final available snapshot.
            while next < values.endIndex, values[next].key < day {
                next += 1
            }
            if next > values.startIndex {
                let dailyReturn = point.amountCNY.doubleValue / values[next - 1].value
                if dailyReturn.isFinite { returns.append(dailyReturn) }
            }
        }

        summary = PerformanceRiskSummary(
            currentDrawdownCNY: latest.drawdownCNY,
            currentDrawdownRate: latest.profitRate - latest.peakProfitRate,
            currentProfitCNY: latest.profitCNY,
            currentProfitRate: latest.profitRate,
            maxDrawdownCNY: maxPoint?.drawdownCNY ?? 0,
            maxDrawdownDate: maxPoint?.date,
            maxDrawdownRate: maxPoint.map { $0.profitRate - $0.peakProfitRate },
            annualizedVolatility: Self.standardDeviation(returns).map { $0 * (252.0).squareRoot() * 100 },
            upDayRatio: trackedDays == 0 ? nil : Double(upDays) / Double(trackedDays) * 100,
            upDayCount: upDays,
            trackedDayCount: trackedDays,
            worstDayCNY: worst?.point.amountCNY.doubleValue,
            worstDayDate: worst?.day
        )
    }

    var chartPoints: [PerformanceRiskPoint] {
        let maximumCount = 128
        guard points.count > maximumCount else { return points }
        let step = Double(points.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            points[Int((Double(index) * step).rounded())]
        }
    }

    private static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
