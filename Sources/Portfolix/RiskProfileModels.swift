import Foundation

enum RiskProfileTier: String, CaseIterable, Identifiable, Sendable {
    case conservative = "保守稳健"
    case balanced = "稳健平衡"
    case growth = "积极成长"

    var id: String { rawValue }

    init(rawOrDefault rawValue: String) {
        self = Self(rawValue: rawValue) ?? .balanced
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .conservative:
            localizedText("保守型", "Conservative", language: language)
        case .balanced:
            localizedText("平衡型", "Balanced", language: language)
        case .growth:
            localizedText("进取型", "Growth", language: language)
        }
    }

    func summary(language: AppLanguage) -> String {
        switch self {
        case .conservative:
            localizedText(
                "以本金安全与低回撤为首要目标，核心仓位偏向现金、固收与低波动资产。",
                "Prioritizes capital preservation and low drawdowns with cash, fixed-income, and lower-volatility core holdings.",
                language: language
            )
        case .balanced:
            localizedText(
                "兼顾长期增值与回撤控制，通过股债与多资产分散降低单一波动冲击。",
                "Balances long-term growth with drawdown control through multi-asset diversification.",
                language: language
            )
        case .growth:
            localizedText(
                "愿意承受阶段性较大回撤，以高弹性权益与成长资产博取长期复利。",
                "Accepts deeper drawdowns in pursuit of higher long-term compounding from growth assets.",
                language: language
            )
        }
    }

    var recommendedGuardrails: RiskProfileGuardrailPreset {
        switch self {
        case .conservative:
            RiskProfileGuardrailPreset(
                maxDrawdownLimit: 10,
                positionLimit: 20,
                riskAssetLimit: 35,
                cryptoLimit: 5,
                foreignCurrencyLimit: 30,
                liquidityMinimum: 20
            )
        case .balanced:
            RiskProfileGuardrailPreset(
                maxDrawdownLimit: 20,
                positionLimit: 30,
                riskAssetLimit: 65,
                cryptoLimit: 15,
                foreignCurrencyLimit: 50,
                liquidityMinimum: 10
            )
        case .growth:
            RiskProfileGuardrailPreset(
                maxDrawdownLimit: 30,
                positionLimit: 40,
                riskAssetLimit: 90,
                cryptoLimit: 25,
                foreignCurrencyLimit: 70,
                liquidityMinimum: 5
            )
        }
    }
}

struct RiskProfileGuardrailPreset: Equatable, Sendable {
    let maxDrawdownLimit: Double
    let positionLimit: Double
    let riskAssetLimit: Double
    let cryptoLimit: Double
    let foreignCurrencyLimit: Double
    let liquidityMinimum: Double
}

enum RiskInvestmentGoal: String, CaseIterable, Identifiable, Sendable {
    case capitalPreservation = "稳健保本"
    case balancedGrowth = "平衡增值"
    case longTermCompounding = "长期复利"
    case incomeFocus = "现金流优先"

    var id: String { rawValue }

    init(rawOrDefault rawValue: String) {
        self = Self(rawValue: rawValue) ?? .balancedGrowth
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .capitalPreservation:
            localizedText("稳健保本", "Capital Preservation", language: language)
        case .balancedGrowth:
            localizedText("平衡增值", "Balanced Growth", language: language)
        case .longTermCompounding:
            localizedText("长期复利", "Long-Term Compounding", language: language)
        case .incomeFocus:
            localizedText("现金流优先", "Income Focus", language: language)
        }
    }
}

enum RiskInvestmentHorizon: String, CaseIterable, Identifiable, Sendable {
    case underOneYear = "< 1 年"
    case oneToThreeYears = "1-3 年"
    case threeToFiveYears = "3-5 年"
    case overFiveYears = "> 5 年"

    var id: String { rawValue }

    init(rawOrDefault rawValue: String) {
        self = Self(rawValue: rawValue) ?? .threeToFiveYears
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .underOneYear:
            localizedText("< 1 年", "< 1 year", language: language)
        case .oneToThreeYears:
            localizedText("1-3 年", "1–3 years", language: language)
        case .threeToFiveYears:
            localizedText("3-5 年", "3–5 years", language: language)
        case .overFiveYears:
            localizedText("> 5 年", "> 5 years", language: language)
        }
    }
}

enum RiskInvestmentExperience: String, CaseIterable, Identifiable, Sendable {
    case beginner = "初次接触"
    case oneToThreeYears = "1-3 年"
    case threeToFiveYears = "3-5 年"
    case overFiveYears = "> 5 年"

    var id: String { rawValue }

    init(rawOrDefault rawValue: String) {
        self = Self(rawValue: rawValue) ?? .threeToFiveYears
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .beginner:
            localizedText("初次接触", "New investor", language: language)
        case .oneToThreeYears:
            localizedText("1-3 年", "1–3 years", language: language)
        case .threeToFiveYears:
            localizedText("3-5 年", "3–5 years", language: language)
        case .overFiveYears:
            localizedText("> 5 年", "> 5 years", language: language)
        }
    }
}

enum RiskReviewCadence: Int, CaseIterable, Identifiable, Sendable {
    case quarterly = 3
    case semiannual = 6
    case annual = 12

    var id: Int { rawValue }

    init(monthsOrDefault months: Int) {
        self = Self(rawValue: months) ?? .semiannual
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .quarterly:
            localizedText("每 3 个月", "Every 3 months", language: language)
        case .semiannual:
            localizedText("每 6 个月", "Every 6 months", language: language)
        case .annual:
            localizedText("每 12 个月", "Every 12 months", language: language)
        }
    }
}

enum RiskGuardrailSeverity: Equatable, Sendable {
    case noData
    case normal
    case approaching
    case breached

    static func evaluate(actual: Double?, limit: Double, isMinimum: Bool) -> Self {
        guard let actual, actual.isFinite, limit.isFinite else { return .noData }
        if isMinimum {
            if actual < limit { return .breached }
            if limit > 0 && actual <= limit * 1.20 { return .approaching }
            return .normal
        } else {
            if actual > limit { return .breached }
            if limit > 0 && actual >= limit * 0.80 { return .approaching }
            return .normal
        }
    }
}

struct RiskPresetChange: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let currentValue: String
    let targetValue: String
}

enum RiskProfileReviewHealth: Equatable, Sendable {
    case notConfigured
    case breached(count: Int)
    case approaching(count: Int)
    case reviewDue(nextReviewDate: Date)
    case valid(nextReviewDate: Date)
}

struct RiskProfileDraft: Equatable, Sendable {
    var tier: RiskProfileTier
    var investmentGoal: RiskInvestmentGoal
    var investmentHorizon: RiskInvestmentHorizon
    var investmentExperience: RiskInvestmentExperience
    var reviewCadence: RiskReviewCadence
    var maxDrawdownLimit: Double
    var positionLimit: Double
    var riskAssetLimit: Double
    var cryptoLimit: Double
    var foreignCurrencyLimit: Double
    var liquidityMinimum: Double

    static let defaultBalanced = RiskProfileDraft(
        tier: .balanced,
        investmentGoal: .balancedGrowth,
        investmentHorizon: .threeToFiveYears,
        investmentExperience: .threeToFiveYears,
        reviewCadence: .semiannual,
        maxDrawdownLimit: 20,
        positionLimit: 30,
        riskAssetLimit: 65,
        cryptoLimit: 15,
        foreignCurrencyLimit: 50,
        liquidityMinimum: 10
    )

    var drawdownToleranceLabel: String {
        "\(Int(maxDrawdownLimit.rounded()))%"
    }

    var matchesRecommendedGuardrails: Bool {
        let preset = tier.recommendedGuardrails
        return abs(maxDrawdownLimit - preset.maxDrawdownLimit) < 0.05
            && abs(positionLimit - preset.positionLimit) < 0.05
            && abs(riskAssetLimit - preset.riskAssetLimit) < 0.05
            && abs(cryptoLimit - preset.cryptoLimit) < 0.05
            && abs(foreignCurrencyLimit - preset.foreignCurrencyLimit) < 0.05
            && abs(liquidityMinimum - preset.liquidityMinimum) < 0.05
    }

    mutating func applyRecommendedGuardrails(for targetTier: RiskProfileTier? = nil) {
        let preset = (targetTier ?? tier).recommendedGuardrails
        maxDrawdownLimit = preset.maxDrawdownLimit
        positionLimit = preset.positionLimit
        riskAssetLimit = preset.riskAssetLimit
        cryptoLimit = preset.cryptoLimit
        foreignCurrencyLimit = preset.foreignCurrencyLimit
        liquidityMinimum = preset.liquidityMinimum
    }

    func presetChanges(for targetTier: RiskProfileTier? = nil, language: AppLanguage) -> [RiskPresetChange] {
        let preset = (targetTier ?? tier).recommendedGuardrails
        let items: [(String, String, Double, Double)] = [
            ("drawdown", localizedText("最大回撤容忍", "Max Drawdown", language: language), maxDrawdownLimit, preset.maxDrawdownLimit),
            ("position", localizedText("单一非现金资产上限", "Max Single Asset", language: language), positionLimit, preset.positionLimit),
            ("riskAsset", localizedText("股票与加密资产上限", "Max Stocks & Crypto", language: language), riskAssetLimit, preset.riskAssetLimit),
            ("crypto", localizedText("加密资产上限", "Max Crypto", language: language), cryptoLimit, preset.cryptoLimit),
            ("fx", localizedText("外币资产上限", "Max Non-Base Currency", language: language), foreignCurrencyLimit, preset.foreignCurrencyLimit),
            ("cash", localizedText("最低现金比例", "Minimum Cash", language: language), liquidityMinimum, preset.liquidityMinimum),
        ]
        return items.compactMap { id, title, current, target in
            guard abs(current - target) >= 0.05 else { return nil }
            return RiskPresetChange(
                id: id,
                title: title,
                currentValue: "\(Int(current.rounded()))%",
                targetValue: "\(Int(target.rounded()))%"
            )
        }
    }

    func changedFieldCount(comparedTo other: RiskProfileDraft) -> Int {
        var count = 0
        if tier != other.tier { count += 1 }
        if investmentGoal != other.investmentGoal { count += 1 }
        if investmentHorizon != other.investmentHorizon { count += 1 }
        if investmentExperience != other.investmentExperience { count += 1 }
        if reviewCadence != other.reviewCadence { count += 1 }
        if abs(maxDrawdownLimit - other.maxDrawdownLimit) >= 0.05 { count += 1 }
        if abs(positionLimit - other.positionLimit) >= 0.05 { count += 1 }
        if abs(riskAssetLimit - other.riskAssetLimit) >= 0.05 { count += 1 }
        if abs(cryptoLimit - other.cryptoLimit) >= 0.05 { count += 1 }
        if abs(foreignCurrencyLimit - other.foreignCurrencyLimit) >= 0.05 { count += 1 }
        if abs(liquidityMinimum - other.liquidityMinimum) >= 0.05 { count += 1 }
        return count
    }

    static func parseDrawdownTolerance(_ raw: String, fallback: Double = 20) -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed.hasPrefix(">") {
            let numeric = trimmed
                .dropFirst()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            if let value = Double(numeric), value.isFinite {
                return min(max(value + 5, 5), 50)
            }
            return 35
        }
        let cleaned = trimmed.replacingOccurrences(of: "%", with: "")
        guard let value = Double(cleaned), value.isFinite else { return fallback }
        return min(max(value, 5), 50)
    }

    func consistencyHints(language: AppLanguage) -> [String] {
        var hints: [String] = []
        if cryptoLimit > riskAssetLimit {
            hints.append(localizedText(
                "加密上限 (\(Int(cryptoLimit.rounded()))%) 高于股币总上限 (\(Int(riskAssetLimit.rounded()))%)，建议前者不高于后者",
                "Max Crypto (\(Int(cryptoLimit.rounded()))%) exceeds Max Stocks & Crypto (\(Int(riskAssetLimit.rounded()))%)",
                language: language
            ))
        }
        if tier == .conservative && (maxDrawdownLimit > 15 || riskAssetLimit > 50 || cryptoLimit > 10) {
            hints.append(localizedText(
                "保守型下部分波动护栏偏宽松，建议核对或切换为平衡型",
                "Some volatility caps are wide for Conservative tier",
                language: language
            ))
        } else if tier == .growth && (investmentGoal == .capitalPreservation || maxDrawdownLimit <= 10) {
            hints.append(localizedText(
                "进取型与当前目标或回撤护栏偏保守，请确认是否一致",
                "Growth tier contrasts with defensive goal or drawdown cap",
                language: language
            ))
        }
        if investmentHorizon == .underOneYear && (tier == .growth || maxDrawdownLimit > 15) {
            hints.append(localizedText(
                "持有周期不足 1 年，较高回撤容忍会放大短期波动风险",
                "Holding horizon < 1 year carries higher short-term drawdown risk",
                language: language
            ))
        }
        return hints
    }

    func reviewHealth(
        isConfigured: Bool,
        updatedAt: Date,
        evaluation: RiskConstraintEvaluation,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RiskProfileReviewHealth {
        guard isConfigured else { return .notConfigured }
        let nextReview = calendar.date(byAdding: .month, value: reviewCadence.rawValue, to: updatedAt) ?? updatedAt
        if evaluation.breachCount > 0 {
            return .breached(count: evaluation.breachCount)
        }
        if evaluation.approachingCount > 0 {
            return .approaching(count: evaluation.approachingCount)
        }
        if now >= nextReview {
            return .reviewDue(nextReviewDate: nextReview)
        }
        return .valid(nextReviewDate: nextReview)
    }
}
