import Foundation

enum InvestmentCloudMode: String, CaseIterable, Identifiable {
    case dailyProfit
    case distribution

    static let defaultMode = InvestmentCloudMode.dailyProfit
    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .dailyProfit: localizedText("今日盈亏", "Today's P&L", language: language)
        case .distribution: localizedText("投资分布", "Distribution", language: language)
        }
    }
}

struct InvestmentCloudItem: Identifiable {
    let id: String
    let titleChinese: String
    let titleEnglish: String
    let amountCNY: Decimal
    /// Current market value backing this tile (daily mode) or category value (distribution mode).
    let marketValueCNY: Decimal?
    /// Today's P&L rate for this item, when known (daily mode only).
    let dailyProfitRate: Decimal?
    let areaWeight: Double
    let distributionPercentage: Double?
    let mode: InvestmentCloudMode
    let isAggregated: Bool
    let aggregatedCount: Int

    init(distribution: InvestmentDistributionItem) {
        id = distribution.id
        titleChinese = distribution.domain.titleChinese
        titleEnglish = distribution.domain.titleEnglish
        amountCNY = distribution.amountCNY
        marketValueCNY = distribution.amountCNY
        dailyProfitRate = nil
        areaWeight = distribution.percentage
        distributionPercentage = distribution.percentage
        mode = .distribution
        isAggregated = false
        aggregatedCount = 0
    }

    init(position: Position, dailyProfitCNY: Decimal) {
        id = "daily_profit_\(position.id.uuidString)"
        titleChinese = position.name
        titleEnglish = position.name
        amountCNY = dailyProfitCNY
        marketValueCNY = position.marketValueCNY
        let baseValue = position.marketValueCNY - dailyProfitCNY
        dailyProfitRate = baseValue == 0 ? nil : dailyProfitCNY / baseValue * 100
        areaWeight = abs(dailyProfitCNY.doubleValue)
        distributionPercentage = nil
        mode = .dailyProfit
        isAggregated = false
        aggregatedCount = 0
    }

    init(aggregating items: [InvestmentCloudItem]) {
        let count = items.count
        id = "aggregated_other"
        titleChinese = "其他 \(count) 项"
        titleEnglish = count == 1 ? "1 other" : "\(count) others"
        amountCNY = items.reduce(Decimal(0)) { $0 + $1.amountCNY }
        let marketValues = items.compactMap(\.marketValueCNY)
        marketValueCNY = marketValues.isEmpty ? nil : marketValues.reduce(Decimal(0), +)
        dailyProfitRate = nil
        areaWeight = items.reduce(0.0) { $0 + $1.areaWeight }
        let percentages = items.compactMap(\.distributionPercentage)
        distributionPercentage = percentages.isEmpty ? nil : percentages.reduce(0, +)
        mode = items.first?.mode ?? .dailyProfit
        isAggregated = true
        aggregatedCount = count
    }

    func title(language: AppLanguage) -> String {
        language == .english ? titleEnglish : titleChinese
    }
}

enum InvestmentCloudEngine {
    static func dailyProfitItems(
        positions: [Position], profitForPosition: (Position) -> Decimal
    ) -> [InvestmentCloudItem] {
        positions.compactMap { position in
            let amount = profitForPosition(position)
            guard amount != 0, amount.doubleValue.isFinite else { return nil }
            return InvestmentCloudItem(position: position, dailyProfitCNY: amount)
        }.sorted {
            $0.areaWeight == $1.areaWeight ? $0.id < $1.id : $0.areaWeight > $1.areaWeight
        }
    }

    /// Builds the tiles for the investment map: drops items without a positive
    /// display weight, aggregates tiny slices into a single "others" tile, and
    /// caps the number of rendered tiles so the map stays readable.
    static func displayItems(
        _ items: [InvestmentCloudItem],
        minimumShare: Double = 0.02,
        maximumItems: Int = 12,
        weight: (InvestmentCloudItem) -> Double
    ) -> [InvestmentCloudItem] {
        let base = items.filter {
            let value = weight($0)
            return value.isFinite && value > 0
        }
        guard !base.isEmpty else { return [] }
        let total = base.reduce(0.0) { $0 + weight($1) }
        guard total > 0 else { return [] }
        let share = min(max(minimumShare, 0), 0.5)
        let threshold = total * share

        var result = base.filter { weight($0) >= threshold }
        let small = base.filter { weight($0) < threshold }
        if result.isEmpty {
            result = base
        } else if !small.isEmpty {
            result.append(InvestmentCloudItem(aggregating: small))
        }
        result.sort {
            weight($0) == weight($1) ? $0.id < $1.id : weight($0) > weight($1)
        }

        let cap = max(maximumItems, 2)
        if result.count > cap {
            let kept = Array(result.prefix(cap - 1))
            let rest = Array(result.dropFirst(cap - 1))
            var merged = kept
            merged.append(InvestmentCloudItem(aggregating: rest))
            result = merged
        }
        return result
    }
}
