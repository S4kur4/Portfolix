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
    let areaWeight: Double
    let distributionPercentage: Double?
    let mode: InvestmentCloudMode

    init(distribution: InvestmentDistributionItem) {
        id = distribution.id
        titleChinese = distribution.domain.titleChinese
        titleEnglish = distribution.domain.titleEnglish
        amountCNY = distribution.amountCNY
        areaWeight = distribution.percentage
        distributionPercentage = distribution.percentage
        mode = .distribution
    }

    init(position: Position, dailyProfitCNY: Decimal) {
        id = "daily_profit_\(position.id.uuidString)"
        titleChinese = position.name
        titleEnglish = position.name
        amountCNY = dailyProfitCNY
        areaWeight = abs(dailyProfitCNY.doubleValue)
        distributionPercentage = nil
        mode = .dailyProfit
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
}
