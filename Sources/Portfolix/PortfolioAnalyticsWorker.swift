import Foundation

struct PortfolioPersistedState: Sendable {
    let positions: [Position]
    let snapshots: [PortfolioSnapshot]
    let dailyProfitHistory: [DailyProfitPoint]
}

actor PortfolioAnalyticsWorker {
    private let databaseURL: URL
    private var repository: PositionRepository?
    private let dayFormatter: DateFormatter

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        dayFormatter = formatter
    }

    func loadPositionPerformance(
        positions: [Position],
        asOf date: Date
    ) -> [Position.ID: AIPositionPerformanceContext] {
        let performanceInterval = PortfolixPerformance.begin("AIContextPreparation")
        defer {
            PortfolixPerformance.end("AIContextPreparation", identifier: performanceInterval)
        }
        guard let repository = try? resolvedRepository() else { return [:] }
        let snapshotsByPosition = (try? repository.fetchAssetPriceSnapshots(
            positionIDs: positions.map(\.id),
            lookbackDays: 45,
            through: date
        )) ?? [:]

        return Dictionary(uniqueKeysWithValues: positions.map { position in
            let snapshots = snapshotsByPosition[position.id] ?? []
            let performance = AIPositionPerformanceContext(
                oneWeek: performanceWindow(
                    position: position,
                    snapshots: snapshots,
                    periodDays: 7,
                    maximumBaselineLagDays: 7,
                    asOf: date
                ),
                oneMonth: performanceWindow(
                    position: position,
                    snapshots: snapshots,
                    periodDays: 30,
                    maximumBaselineLagDays: 10,
                    asOf: date
                )
            )
            return (position.id, performance)
        })
    }

    func fetchLatestAIAnalysisArtifacts() throws -> AIAnalysisArtifactBundle? {
        try resolvedRepository().fetchLatestAIAnalysisArtifacts()
    }

    func persistQuoteRefresh(
        updatedPositions: [Position],
        snapshotPositions: [Position],
        snapshotDate: Date = .now
    ) throws -> PortfolioPersistedState? {
        let repository = try resolvedRepository()
        try repository.applyQuoteRefresh(
            updatedPositions: updatedPositions,
            snapshotPositions: snapshotPositions,
            snapshotDate: snapshotDate
        )
        return PortfolioPersistedState(
            positions: try repository.fetchPositions(),
            snapshots: try repository.fetchPortfolioSnapshots(),
            dailyProfitHistory: try repository.fetchDailyProfitPoints(through: snapshotDate)
        )
    }

    private func resolvedRepository() throws -> PositionRepository {
        if let repository {
            return repository
        }
        let repository = try PositionRepository(databaseURL: databaseURL)
        self.repository = repository
        return repository
    }

    private func performanceWindow(
        position: Position,
        snapshots: [AssetPriceSnapshotPoint],
        periodDays: Int,
        maximumBaselineLagDays: Int,
        asOf date: Date
    ) -> AIPerformanceWindowContext {
        let calendar = Calendar.current
        let targetDate = calendar.date(byAdding: .day, value: -periodDays, to: date) ?? date
        let baseline = snapshots.last { $0.date <= targetDate }
        let endDate = dayFormatter.string(from: date)
        let basis = "price_change_times_current_quantity_excludes_trades_fees_fx"

        guard let baseline else {
            return AIPerformanceWindowContext(
                status: "insufficient_history",
                periodDays: periodDays,
                startDate: nil,
                endDate: endDate,
                startPrice: nil,
                endPrice: decimalString(position.latestPrice),
                profitAmountQuote: nil,
                returnRatePct: nil,
                observationDays: nil,
                calculationBasis: basis
            )
        }

        let targetLag = calendar.dateComponents([.day], from: baseline.date, to: targetDate).day ?? Int.max
        let observationDays = calendar.dateComponents([.day], from: baseline.date, to: date).day ?? periodDays
        guard targetLag <= maximumBaselineLagDays, baseline.latestPrice != 0 else {
            return AIPerformanceWindowContext(
                status: "insufficient_history",
                periodDays: periodDays,
                startDate: dayFormatter.string(from: baseline.date),
                endDate: endDate,
                startPrice: decimalString(baseline.latestPrice),
                endPrice: decimalString(position.latestPrice),
                profitAmountQuote: nil,
                returnRatePct: nil,
                observationDays: observationDays,
                calculationBasis: basis
            )
        }

        let profit = (position.latestPrice - baseline.latestPrice) * position.quantity
        let returnRate = (position.latestPrice - baseline.latestPrice) / baseline.latestPrice * 100
        return AIPerformanceWindowContext(
            status: "available",
            periodDays: periodDays,
            startDate: dayFormatter.string(from: baseline.date),
            endDate: endDate,
            startPrice: decimalString(baseline.latestPrice),
            endPrice: decimalString(position.latestPrice),
            profitAmountQuote: decimalString(profit),
            returnRatePct: returnRate.doubleValue,
            observationDays: observationDays,
            calculationBasis: basis
        )
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
