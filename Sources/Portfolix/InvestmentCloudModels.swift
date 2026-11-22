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
    /// Distribution uses the investment domain. Daily P&L uses the holding category.
    let assetClass: AssetClass

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
        assetClass = Self.resolvedAssetClass(forDomainID: distribution.domain.id)
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
        assetClass = position.category.assetClass
    }

    init(aggregating items: [InvestmentCloudItem]) {
        let count = items.reduce(0) { $0 + ($1.isAggregated ? $1.aggregatedCount : 1) }
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
        assetClass = .other
    }

    /// Map an investment domain to one of the five asset classes.
    static func resolvedAssetClass(forDomainID id: String) -> AssetClass {
        let lowered = id.lowercased()
        if lowered.contains("cash") { return .cash }
        if lowered.contains("crypto") || lowered.contains("bitcoin") || lowered.contains("ethereum") {
            return .crypto
        }
        if lowered.contains("bond") || lowered.contains("gold") || lowered.contains("fund") {
            return .fund
        }
        if lowered.contains("equity") || lowered.contains("semiconductor")
            || lowered.contains("optical") || lowered.contains("stock") {
            return .stock
        }
        return .other
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
        let base = items.compactMap { item -> (item: InvestmentCloudItem, weight: Double)? in
            let value = weight(item)
            guard value.isFinite, value > 0 else { return nil }
            return (item, value)
        }
        let total = base.reduce(0.0) { $0 + $1.weight }
        guard total.isFinite, total > 0 else { return [] }
        let share = min(max(minimumShare, 0), 0.5)
        let threshold = total * share

        var visible = base.filter { $0.weight >= threshold }
        let small = base.filter { $0.weight < threshold }.map(\.item)
        let itemsToGroup: [InvestmentCloudItem]
        if visible.isEmpty {
            visible = base
            itemsToGroup = []
        } else {
            itemsToGroup = small
        }
        visible.sort {
            $0.weight == $1.weight ? $0.item.id < $1.item.id : $0.weight > $1.weight
        }

        let cap = max(maximumItems, 2)
        let countWithGroup = visible.count + (itemsToGroup.isEmpty ? 0 : 1)
        if countWithGroup > cap {
            let keptCount = cap - 1
            let kept = visible.prefix(keptCount).map(\.item)
            let overflow = visible.dropFirst(keptCount).map(\.item)
            return kept + [InvestmentCloudItem(aggregating: itemsToGroup + overflow)]
        }
        guard !itemsToGroup.isEmpty else { return visible.map(\.item) }
        let group = InvestmentCloudItem(aggregating: itemsToGroup)
        let groupWeight = weight(group)
        let index = visible.firstIndex {
            groupWeight > $0.weight || (groupWeight == $0.weight && group.id < $0.item.id)
        } ?? visible.endIndex
        visible.insert((group, groupWeight), at: index)
        return visible.map(\.item)
    }
}
