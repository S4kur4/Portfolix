import Foundation
import AppKit
import OSLog
import ServiceManagement
import SwiftUI

func localizedText(_ chinese: String, _ english: String, language: AppLanguage) -> String {
    language == .english ? english : chinese
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case positions
    case report
    case riskProfile
    case settings

    var id: String { rawValue }

    var title: String {
        title(language: .chinese)
    }

    func title(language: AppLanguage) -> String {
        if language == .english {
            switch self {
            case .overview: "Overview"
            case .positions: "Holdings"
            case .report: "Smart Analysis"
            case .riskProfile: "Risk Profile"
            case .settings: "Settings"
            }
        } else {
            switch self {
            case .overview: "资产总览"
            case .positions: "持仓明细"
            case .report: "智能分析"
            case .riskProfile: "风险偏好"
            case .settings: "系统设置"
            }
        }
    }

    var symbol: String {
        switch self {
        case .overview: "chart.pie.fill"
        case .positions: "list.bullet.rectangle.portrait"
        case .report: "sparkles.rectangle.stack"
        case .riskProfile: "slider.horizontal.3"
        case .settings: "gearshape"
        }
    }
}

enum DisplayCurrency: String, CaseIterable, Identifiable, Sendable {
    case cny = "CNY"
    case hkd = "HKD"
    case usd = "USD"
    case usdt = "USDT"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cny: "¥"
        case .hkd: "HK$"
        case .usd: "$"
        case .usdt: "₮"
        }
    }

    var rateFromCNY: Decimal {
        switch self {
        case .cny: 1
        case .hkd: 1.153431425
        case .usd: 0.147215543
        case .usdt: 0.147289188
        }
    }

    var color: Color {
        switch self {
        case .cny: PortfolixTheme.lilac
        case .hkd: PortfolixTheme.violet
        case .usd: PortfolixTheme.blue
        case .usdt: PortfolixTheme.amber
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system = "跟随系统"
    case dark = "深色"
    case light = "浅色"

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        if language == .english {
            switch self {
            case .system: "System"
            case .dark: "Dark"
            case .light: "Light"
            }
        } else {
            rawValue
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese = "中文"
    case english = "English"

    var id: String { rawValue }

    var aiResponseLanguage: AIResponseLanguage {
        self == .english ? .english : .simplifiedChinese
    }
}

enum AutomaticPriceUpdateFrequency: String, CaseIterable, Identifiable {
    case fiveMinutes = "5 分钟"
    case fifteenMinutes = "15 分钟"
    case thirtyMinutes = "30 分钟"
    case hourly = "1 小时"
    case fourHours = "4 小时"
    case eightHours = "8 小时"
    case daily = "每日"

    var id: String { rawValue }

    var intervalSeconds: Int? {
        switch self {
        case .fiveMinutes: 5 * 60
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .hourly: 60 * 60
        case .fourHours: 4 * 60 * 60
        case .eightHours: 8 * 60 * 60
        case .daily: nil
        }
    }

    func title(language: AppLanguage) -> String {
        if language == .english {
            switch self {
            case .fiveMinutes: "5 minutes"
            case .fifteenMinutes: "15 minutes"
            case .thirtyMinutes: "30 minutes"
            case .hourly: "1 hour"
            case .fourHours: "4 hours"
            case .eightHours: "8 hours"
            case .daily: "Daily"
            }
        } else {
            rawValue
        }
    }

    func nextDelaySeconds(now: Date = .now) -> Int {
        if let intervalSeconds {
            return intervalSeconds
        }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0
        components.second = 0

        var nextDate = calendar.date(from: components) ?? now
        if nextDate <= now {
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? now.addingTimeInterval(24 * 60 * 60)
        }
        return max(60, Int(nextDate.timeIntervalSince(now)))
    }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case profitValue = "持仓收益"
    case profitRate = "持仓收益率"

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        if language == .english {
            switch self {
            case .profitValue: "Holding Return"
            case .profitRate: "Return Rate"
            }
        } else {
            rawValue
        }
    }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case day = "1日"
    case week = "1周"
    case month = "1月"
    case year = "1年"

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        if language == .english {
            switch self {
            case .day: "1D"
            case .week: "1W"
            case .month: "1M"
            case .year: "1Y"
            }
        } else {
            rawValue
        }
    }

    var days: Int {
        switch self {
        case .day: 1
        case .week: 6
        case .month: 29
        case .year: 364
        }
    }
}

enum AssetCategory: String, CaseIterable, Identifiable, Sendable {
    case cnStock = "A 股"
    case bStock = "B 股"
    case hkStock = "港股"
    case usStock = "美股"
    case fund = "公募基金"
    case crypto = "数字货币"
    case cash = "现金"

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        if language == .english {
            switch self {
            case .cnStock: "A-Share"
            case .bStock: "B-Share"
            case .hkStock: "HK Stock"
            case .usStock: "US Stock"
            case .fund: "Mutual Fund"
            case .crypto: "Crypto"
            case .cash: "Cash"
            }
        } else {
            rawValue
        }
    }

    var color: Color {
        switch self {
        case .cnStock: PortfolixTheme.lilac
        case .bStock: PortfolixTheme.violet
        case .hkStock: PortfolixTheme.violet
        case .usStock: PortfolixTheme.blue
        case .fund: PortfolixTheme.rose
        case .crypto: PortfolixTheme.amber
        case .cash: PortfolixTheme.mint
        }
    }
}

enum Freshness: String {
    case updated = "已更新"
    case stale = "已过期"
    case manual = "手工价格"

    var symbol: String {
        switch self {
        case .updated: "checkmark.circle.fill"
        case .stale: "clock.badge.exclamationmark.fill"
        case .manual: "pencil.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .updated: PortfolixTheme.mint
        case .stale: PortfolixTheme.amber
        case .manual: PortfolixTheme.lilac
        }
    }
}

struct Position: Identifiable {
    let id: UUID
    let name: String
    let symbol: String
    let category: AssetCategory
    let quoteCurrency: DisplayCurrency
    let quantity: Decimal
    let totalCost: Decimal
    let averageCost: Decimal
    let latestPrice: Decimal
    let marketValueCNY: Decimal
    let profitRate: Decimal
    let weeklyTrend: [Double]
    let source: String
    let quoteTime: String
    let fetchedAt: String
    let freshness: Freshness

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        category: AssetCategory,
        quoteCurrency: DisplayCurrency,
        quantity: Decimal,
        totalCost: Decimal? = nil,
        averageCost: Decimal,
        latestPrice: Decimal,
        marketValueCNY: Decimal,
        profitRate: Decimal,
        weeklyTrend: [Double],
        source: String,
        quoteTime: String,
        fetchedAt: String = ISO8601DateFormatter().string(from: .now),
        freshness: Freshness
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.category = category
        self.quoteCurrency = quoteCurrency
        self.quantity = quantity
        self.totalCost = totalCost ?? quantity * averageCost
        self.averageCost = averageCost
        self.latestPrice = latestPrice
        self.marketValueCNY = marketValueCNY
        self.profitRate = profitRate
        self.weeklyTrend = weeklyTrend
        self.source = normalizedQuoteSource(source, category: category)
        self.quoteTime = quoteTime
        self.fetchedAt = fetchedAt
        self.freshness = freshness
    }

    var relativeUpdateText: String {
        relativeUpdateText(now: .now, language: .chinese)
    }

    func relativeUpdateText(now: Date, language: AppLanguage = .chinese) -> String {
        guard let date = ISO8601DateFormatter().date(from: fetchedAt) else {
            return quoteTime
        }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return language == .english ? "Just updated" : "刚刚更新"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return language == .english ? "\(minutes)m ago" : "\(minutes) 分钟前更新"
        }
        let hours = minutes / 60
        if hours < 24 {
            return language == .english ? "\(hours)h ago" : "\(hours) 小时前更新"
        }
        let days = hours / 24
        return language == .english ? "\(days)d ago" : "\(days) 天前更新"
    }

    var priceDateText: String {
        priceDateText(language: .chinese)
    }

    func priceDateText(language: AppLanguage) -> String {
        guard freshness != .manual else {
            return language == .english ? "Manual price" : "手工价格"
        }
        let trimmed = quoteTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "刚刚" else {
            return fetchedDateText(language: language) ?? (language == .english ? "Unknown price date" : "价格日期未知")
        }

        if let date = Self.quoteTimeDate(from: trimmed) {
            return language == .english
                ? Self.englishPriceDateFormatter.string(from: date)
                : Self.priceDateFormatter.string(from: date)
        }
        guard language != .english else { return trimmed }
        return Self.chineseDateOnlyText(from: trimmed)
    }

    func wasFetchedOnSameDay(as date: Date, calendar: Calendar = .current) -> Bool {
        guard let fetchedDate = ISO8601DateFormatter().date(from: fetchedAt) else { return false }
        return calendar.isDate(fetchedDate, inSameDayAs: date)
    }

    private var fetchedDateText: String? {
        fetchedDateText(language: .chinese)
    }

    private func fetchedDateText(language: AppLanguage) -> String? {
        guard let date = ISO8601DateFormatter().date(from: fetchedAt) else { return nil }
        return language == .english
            ? Self.englishPriceDateFormatter.string(from: date)
            : Self.priceDateFormatter.string(from: date)
    }

    private static func chineseDateOnlyText(from value: String) -> String {
        var text = value
        if text.hasSuffix("价格") {
            text.removeLast(2)
        }
        if text.hasSuffix("获取") {
            text.removeLast(2)
        }
        return text
    }

    private static func quoteTimeDate(from value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        let formats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyyMMdd",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss.S",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss.S",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss.SSS",
            "yyyy/MM/dd HH:mm:ss.S",
            "yyyy/MM/dd HH:mm",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static let priceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let englishPriceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

func normalizedQuoteSource(_ source: String, category: AssetCategory? = nil) -> String {
    let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.caseInsensitiveCompare("OKX") == .orderedSame {
        return "OKX"
    }
    if normalized.caseInsensitiveCompare("local") == .orderedSame || normalized == "手工价格" {
        return "手工价格"
    }

    switch normalized.lowercased() {
    case "eastmoney", "em", "东方财富", "东财":
        return "东方财富"
    case "sina", "新浪", "新浪财经":
        return "新浪财经"
    case "ths", "tonghuashun", "同花顺":
        return "同花顺"
    case "tencent", "tx", "腾讯", "腾讯财经":
        return "腾讯财经"
    case "jin10", "金十", "金十数据":
        return "金十数据"
    default:
        break
    }

    if normalized.localizedCaseInsensitiveContains("eastmoney") || normalized.contains("东方财富") {
        return "东方财富"
    }
    if normalized.localizedCaseInsensitiveContains("sina") || normalized.contains("新浪") {
        return "新浪财经"
    }
    if normalized.localizedCaseInsensitiveContains("tonghuashun") || normalized.localizedCaseInsensitiveContains("ths") || normalized.contains("同花顺") {
        return "同花顺"
    }
    if normalized.localizedCaseInsensitiveContains("tencent") || normalized.localizedCaseInsensitiveContains("tx") || normalized.contains("腾讯") {
        return "腾讯财经"
    }
    if normalized.localizedCaseInsensitiveContains("jin10") || normalized.contains("金十") {
        return "金十数据"
    }
    return normalized
}

func localizedQuoteSource(_ source: String, language: AppLanguage) -> String {
    guard language == .english else { return source }
    switch source {
    case "手工价格":
        return "Manual"
    case "东方财富":
        return "Eastmoney"
    case "新浪财经":
        return "Sina Finance"
    case "同花顺":
        return "iFinD"
    case "腾讯财经":
        return "Tencent Finance"
    case "金十数据":
        return "Jin10"
    default:
        return source
    }
}

func normalizedDataSourceName(_ name: String) -> String {
    switch name.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "OKX 公共行情":
        "OKX"
    default:
        normalizedQuoteSource(name)
    }
}

func isPublicMarketQuoteSource(_ source: String) -> Bool {
    switch normalizedQuoteSource(source) {
    case "东方财富", "新浪财经", "同花顺", "腾讯财经":
        return true
    default:
        return false
    }
}

struct AllocationItem: Identifiable {
    let name: String
    let value: Double
    let color: Color

    var id: String { name }
}

struct DataSourceStatus: Identifiable {
    let name: String
    let detail: String
    let symbol: String
    let state: String
    let color: Color

    var id: String { name }

    var displayDetail: String {
        displayDetail(language: .chinese)
    }

    func displayDetail(language: AppLanguage) -> String {
        if language == .english {
            switch detail {
            case "候选查询成功":
                return defaultDetail(language: language)
            case "A 股、B 股、港股、美股和公募基金":
                return "A/B-shares, HK/US stocks, and funds"
            case "股票与基金":
                return "Stocks and funds"
            case "数字货币现货交易对":
                return "Crypto spot pairs"
            case "暂无需自动获取价格的持仓":
                return "No stock or fund holdings"
            case "暂无数字货币持仓":
                return "No crypto holdings"
            default:
                return detail
            }
        }
        guard detail == "候选查询成功" else { return detail }
        return defaultDetail(language: language)
    }

    func stateText(language: AppLanguage) -> String {
        guard language == .english else { return state }
        switch state {
        case "连接正常":
            return "Connected"
        case "连接异常":
            return "Error"
        case "部分异常":
            return "Partial error"
        case "未使用":
            return "Unused"
        case "待检查":
            return "Pending"
        default:
            return state
        }
    }

    private func defaultDetail(language: AppLanguage) -> String {
        switch name {
        case "东方财富", "新浪财经", "同花顺", "腾讯财经":
            return language == .english ? "Stocks and funds" : "股票与基金"
        case "金十数据":
            return language == .english ? "Market data" : "市场数据"
        case "OKX":
            return language == .english ? "Crypto spot pairs" : "数字货币现货交易对"
        default:
            return detail
        }
    }
}

struct PortfolioSnapshot: Identifiable {
    let id = UUID()
    let date: Date
    let totalValueCNY: Double
    let profitRate: Double

    var profitCNY: Double {
        guard profitRate != -100 else { return -totalValueCNY }
        return totalValueCNY * profitRate / (100 + profitRate)
    }
}

struct RiskConstraintEvaluation {
    let largestPositionName: String?
    let largestPositionPercent: Double
    let cryptoAllocationPercent: Double
    let nonCNYAllocationPercent: Double
    let cashAllocationPercent: Double
    let positionLimit: Double
    let cryptoLimit: Double
    let foreignCurrencyLimit: Double
    let liquidityMinimum: Double

    var results: [Bool] {
        [
            largestPositionPercent <= positionLimit,
            cryptoAllocationPercent <= cryptoLimit,
            nonCNYAllocationPercent <= foreignCurrencyLimit,
            cashAllocationPercent >= liquidityMinimum,
        ]
    }

    var constraintCount: Int {
        results.count
    }

    var passedCount: Int {
        results.filter(\.self).count
    }

    var breachCount: Int {
        constraintCount - passedCount
    }

    var matchScore: Double? {
        guard hasPositions else { return nil }
        return Double(passedCount) / Double(constraintCount) * 100
    }

    var hasPositions: Bool {
        largestPositionName != nil
    }

    var shouldSuggestReview: Bool {
        breachCount >= 2
    }

    static func evaluate(
        positions: [Position],
        positionLimit: Double,
        cryptoLimit: Double,
        foreignCurrencyLimit: Double,
        liquidityMinimum: Double
    ) -> RiskConstraintEvaluation {
        let totalValue = positions.reduce(0) { $0 + $1.marketValueCNY.doubleValue }
        let largestPosition = positions.max { $0.marketValueCNY < $1.marketValueCNY }

        func allocationPercent(where predicate: (Position) -> Bool) -> Double {
            guard totalValue > 0 else { return 0 }
            let value = positions.filter(predicate).reduce(0) { $0 + $1.marketValueCNY.doubleValue }
            return value / totalValue * 100
        }

        return RiskConstraintEvaluation(
            largestPositionName: largestPosition?.name,
            largestPositionPercent: totalValue > 0 ? (largestPosition?.marketValueCNY.doubleValue ?? 0) / totalValue * 100 : 0,
            cryptoAllocationPercent: allocationPercent { $0.category == .crypto },
            nonCNYAllocationPercent: allocationPercent { $0.quoteCurrency != .cny },
            cashAllocationPercent: allocationPercent { $0.category == .cash },
            positionLimit: positionLimit,
            cryptoLimit: cryptoLimit,
            foreignCurrencyLimit: foreignCurrencyLimit,
            liquidityMinimum: liquidityMinimum
        )
    }
}

struct PositionEditorPresentation: Identifiable {
    let id = UUID()
    let position: Position?
}

@MainActor
final class PortfolioStore: ObservableObject {
    private static let aiAnalysisLogger = Logger(
        subsystem: "app.portfolix.mac",
        category: "AIAnalysis"
    )

    @Published var selection: SidebarSection = .overview
    @Published var displayCurrency: DisplayCurrency = .cny
    @Published var appearanceMode: AppearanceMode = .system
    @Published var appLanguage: AppLanguage = .chinese {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Self.appLanguageDefaultsKey)
            persistAppSetting(key: "app_language", value: appLanguage.rawValue)
        }
    }
    @Published var isRefreshing = false
    @Published private(set) var refreshingPositionIDs: Set<Position.ID> = []
    @Published var positionEditorPresentation: PositionEditorPresentation?
    @Published var searchText = ""
    @Published var selectedPositionID: Position.ID?
    @Published var trendMetric: TrendMetric = .profitValue
    @Published var trendRange: TrendRange = .month
    @Published var riskLevel = "未配置"
    @Published var riskProfileConfigured = false
    @Published var riskProfileVersion = 0
    @Published var riskProfileUpdatedAt: Date = Date() {
        didSet {
            UserDefaults.standard.set(riskProfileUpdatedAt, forKey: Self.riskProfileUpdatedAtDefaultsKey)
            persistAppSetting(
                key: "risk_profile_updated_at",
                value: Self.isoDateFormatter.string(from: riskProfileUpdatedAt)
            )
        }
    }
    @Published var relativeTimeNow = Date()
    @Published var cryptoLimit = 15.0
    @Published var positionLimit = 30.0
    @Published var foreignCurrencyLimit = 50.0
    @Published var liquidityMinimum = 10.0
    @Published var persistenceErrorMessage: String?
    @Published var backgroundUpdatesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundUpdatesEnabled, forKey: Self.backgroundUpdatesEnabledDefaultsKey)
            persistAutomaticPriceUpdateSetting()
            configureBackgroundUpdateTask()
            configureLoginItem(launchImmediately: backgroundUpdatesEnabled)
        }
    }
    @Published var automaticPriceUpdateFrequency: AutomaticPriceUpdateFrequency = .hourly {
        didSet {
            UserDefaults.standard.set(automaticPriceUpdateFrequency.rawValue, forKey: Self.updateFrequencyDefaultsKey)
            persistAutomaticPriceUpdateSetting()
            configureBackgroundUpdateTask()
        }
    }
    @Published var automaticPriceUpdateDailyTimeMinutes = 9 * 60 {
        didSet {
            UserDefaults.standard.set(
                automaticPriceUpdateDailyTimeMinutes,
                forKey: Self.dailyUpdateTimeDefaultsKey
            )
            persistAutomaticPriceUpdateSetting()
            configureBackgroundUpdateTask()
        }
    }
    @Published var aiConfiguration: AIProviderConfiguration = AIProviderConfigurationStore.loadLLM() {
        didSet {
            AIProviderConfigurationStore.saveLLM(aiConfiguration)
        }
    }
    @Published var searchConfiguration: SearchConfiguration = AIProviderConfigurationStore.loadSearch() {
        didSet {
            AIProviderConfigurationStore.saveSearch(searchConfiguration)
            refreshProviderCredentialState()
        }
    }
    @Published var hasLLMAPIKey = false
    @Published var hasSearchAPIKey = false
    @Published var llmAPIKeyValidationState: ProviderCredentialValidationState = .unknown
    @Published var searchAPIKeyValidationState: ProviderCredentialValidationState = .unknown
    var hasValidLLMAPIKey: Bool {
        hasLLMAPIKey && llmAPIKeyValidationState == .valid
    }
    var hasValidSearchAPIKey: Bool {
        hasSearchAPIKey && searchAPIKeyValidationState == .valid
    }
    @Published var aiAnalysisRun = AIAnalysisRun()
    @Published var aiAnalysisReport: AIAnalysisReport?
    @Published private(set) var aiAnalysisChatItems: [AIReportChatItem] = []
    @Published private(set) var isAnsweringAIAnalysisFollowUp = false
    @Published private(set) var aiAnalysisFollowUpProgress: AIFollowUpProgress?
    @Published var aiChatRetentionPeriod: AIChatRetentionPeriod = .oneWeek {
        didSet {
            UserDefaults.standard.set(aiChatRetentionPeriod.rawValue, forKey: Self.aiChatRetentionDefaultsKey)
            persistAppSetting(key: "ai_chat_retention", value: aiChatRetentionPeriod.rawValue)
            pruneAIAnalysisChatHistory()
        }
    }
    @Published private var aiInvestmentProfile: AIInvestmentProfile?
    @Published private var isGeneratingInvestmentProfile = false

    @Published var positions: [Position]
    @Published var snapshotHistory: [PortfolioSnapshot]
    @Published var sourceStatuses: [DataSourceStatus]
    private let positionRepository: PositionRepository?
    private let credentialStore: ProviderCredentialStoring
    private let aiAgent: AIAnalysisAgent
    private var backgroundUpdateTask: Task<Void, Never>?
    private static let backgroundUpdatesEnabledDefaultsKey = "portfolix.backgroundUpdatesEnabled"
    private static let updateFrequencyDefaultsKey = "portfolix.automaticPriceUpdateFrequency"
    private static let dailyUpdateTimeDefaultsKey = "portfolix.automaticPriceUpdateDailyTimeMinutes"
    private static let appLanguageDefaultsKey = "portfolix.appLanguage"
    private static let riskProfileUpdatedAtDefaultsKey = "portfolix.riskProfileUpdatedAt"
    private static let riskLevelSettingKey = "risk_profile_level"
    private static let riskProfileConfiguredSettingKey = "risk_profile_configured"
    private static let riskProfileVersionSettingKey = "risk_profile_version"
    private static let riskPositionLimitSettingKey = "risk_position_limit"
    private static let riskCryptoLimitSettingKey = "risk_crypto_limit"
    private static let riskForeignCurrencyLimitSettingKey = "risk_foreign_currency_limit"
    private static let riskLiquidityMinimumSettingKey = "risk_liquidity_minimum"
    private static let riskProfileUpdatedAtSettingKey = "risk_profile_updated_at"
    private static let latestAIReportDefaultsKey = "portfolix.ai.latestReport"
    private static let latestAIInvestmentProfileDefaultsKey = "portfolix.ai.latestInvestmentProfile"
    private static let aiChatRetentionDefaultsKey = "portfolix.ai.chatRetention"
    private static let loginItemIdentifier = "app.portfolix.mac.PriceUpdater"
    private static let isoDateFormatter = ISO8601DateFormatter()

    private struct AIFallbackReportArtifact: Encodable {
        let status: String
        let reason: String
        let generatedAt: String
    }

    private struct AIStoreGuardrailArtifact: Encodable {
        let status: String
        let validator: String
        let checkedAt: String
        let notes: [String]
    }

    private static var shouldSkipLaunchRefresh: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["PORTFOLIX_SKIP_LAUNCH_REFRESH"] == "1"
#else
        false
#endif
    }

    private static var shouldSkipLoginItemConfiguration: Bool {
#if DEBUG
        let bundlePath = Bundle.main.bundleURL.path
        return bundlePath.contains("/dist/") || bundlePath.contains("/.build/")
#else
        return false
#endif
    }

    private static func savedAutomaticPriceUpdateFrequency() -> AutomaticPriceUpdateFrequency {
        guard let value = UserDefaults.standard.string(forKey: updateFrequencyDefaultsKey) else {
            return .hourly
        }
        if value == "每日固定时间" {
            return .daily
        }
        return AutomaticPriceUpdateFrequency(rawValue: value) ?? .hourly
    }

    private static func savedDailyUpdateTimeMinutes() -> Int {
        guard UserDefaults.standard.object(forKey: dailyUpdateTimeDefaultsKey) != nil else {
            return 9 * 60
        }
        let minutes = UserDefaults.standard.integer(forKey: dailyUpdateTimeDefaultsKey)
        return min(max(minutes, 0), 23 * 60 + 59)
    }

    private static func savedAppLanguage() -> AppLanguage {
        guard
            let value = UserDefaults.standard.string(forKey: appLanguageDefaultsKey),
            let language = AppLanguage(rawValue: value)
        else {
            return .chinese
        }
        return language
    }

    private static func savedRiskProfileUpdatedAt() -> Date {
        if let date = UserDefaults.standard.object(forKey: riskProfileUpdatedAtDefaultsKey) as? Date {
            return date
        }
        return .now
    }

    private static func savedAIChatRetentionPeriod() -> AIChatRetentionPeriod {
        guard
            let value = UserDefaults.standard.string(forKey: aiChatRetentionDefaultsKey),
            let period = AIChatRetentionPeriod(rawValue: value)
        else {
            return .oneWeek
        }
        return period
    }

    init(
        positionRepository: PositionRepository? = nil,
        credentialStore: ProviderCredentialStoring? = nil,
        aiAgent: AIAnalysisAgent? = nil
    ) {
        backgroundUpdatesEnabled = positionRepository == nil && !Self.shouldSkipLaunchRefresh
            ? UserDefaults.standard.bool(forKey: Self.backgroundUpdatesEnabledDefaultsKey)
            : false
        automaticPriceUpdateFrequency = Self.savedAutomaticPriceUpdateFrequency()
        automaticPriceUpdateDailyTimeMinutes = Self.savedDailyUpdateTimeMinutes()
        appLanguage = Self.savedAppLanguage()
        riskProfileUpdatedAt = Self.savedRiskProfileUpdatedAt()
        let savedChatRetentionPeriod = Self.savedAIChatRetentionPeriod()
        aiChatRetentionPeriod = savedChatRetentionPeriod
        var activeRepository: PositionRepository?
        var loadedSnapshots: [PortfolioSnapshot] = []
        var loadedSourceStatuses: [DataSourceStatus] = []
        var loadedChatItems: [AIReportChatItem] = []
        do {
            let repository = try positionRepository ?? PositionRepository()
            positions = try repository.fetchPositions()
            loadedSnapshots = try repository.fetchPortfolioSnapshots()
            loadedSourceStatuses = try repository.fetchDataSourceStatuses().filter { $0.name != "金十数据" }
            let cutoff = savedChatRetentionPeriod.cutoffDate()
            try repository.deleteExpiredAIAnalysisContent(before: cutoff)
            let storedChatItems = try repository.fetchAIAnalysisChatItems(since: cutoff)
            loadedChatItems = storedChatItems.map { $0.migratingLegacyPromptText() }
            for (stored, migrated) in zip(storedChatItems, loadedChatItems) where stored != migrated {
                try repository.upsertAIAnalysisChatItem(migrated)
            }
            activeRepository = repository
        } catch {
            positions = []
            persistenceErrorMessage = "无法打开本地持仓数据库，本次运行已切换为临时内存模式，修改不会保存\n\n\(error.localizedDescription)"
        }
        let resolvedCredentialStore = credentialStore
            ?? activeRepository.map { DatabaseProviderCredentialStore(repository: $0) }
            ?? ProviderCredentialStore.shared
        self.credentialStore = resolvedCredentialStore
        self.aiAgent = aiAgent ?? AIAnalysisAgent(credentialStore: resolvedCredentialStore)
        snapshotHistory = loadedSnapshots
        sourceStatuses = loadedSourceStatuses
        self.positionRepository = activeRepository
        loadRiskProfileSettings(from: activeRepository)
        let latestReport = (try? activeRepository?.fetchLatestAIAnalysisReport()) ?? Self.savedAIAnalysisReport()
        aiAnalysisReport = latestReport.flatMap { report in
            report.generatedAt >= savedChatRetentionPeriod.cutoffDate() ? report : nil
        }
        removePersistedAIAnalysisReportIfExpired(cutoff: savedChatRetentionPeriod.cutoffDate())
        aiAnalysisChatItems = loadedChatItems
        aiInvestmentProfile = Self.savedAIInvestmentProfile()
        seedAIAnalysisChatIfNeeded()
        refreshProviderCredentialState()
        persistAutomaticPriceUpdateSetting()
        if backgroundUpdatesEnabled {
            configureBackgroundUpdateTask()
            configureLoginItem(launchImmediately: false)
        } else if !Self.shouldSkipLaunchRefresh {
            Task { await refreshLatestPrices() }
        }
        Task { await refreshDataSourceHealth() }
    }

    func updateRelativeTime(now: Date = .now) {
        relativeTimeNow = now
    }

    var totalValueCNY: Decimal {
        positions.reduce(0) { $0 + $1.marketValueCNY }
    }

    var totalProfitCNY: Decimal {
        totalValueCNY - totalCostCNY
    }

    var totalCostCNY: Decimal {
        positions.reduce(0) {
            $0 + calculateTotalCostCNY(
                category: $1.category,
                quantity: $1.quantity,
                averageCost: $1.averageCost,
                quoteCurrency: $1.quoteCurrency
            )
        }
    }

    var totalProfitRate: Decimal {
        guard totalCostCNY != 0 else { return 0 }
        return totalProfitCNY / totalCostCNY * 100
    }

    var todayProfitCNY: Decimal {
        todayProfitCNY(asOf: .now)
    }

    func todayProfitCNY(asOf date: Date) -> Decimal {
        positions.reduce(0) { $0 + todayProfitCNY(for: $1, asOf: date) }
    }

    var todayProfitRate: Decimal {
        todayProfitRate(asOf: .now)
    }

    func todayProfitRate(asOf date: Date) -> Decimal {
        let todayProfit = todayProfitCNY(asOf: date)
        let baselineValueCNY = totalValueCNY - todayProfit
        guard baselineValueCNY != 0 else { return 0 }
        return todayProfit / baselineValueCNY * 100
    }

    func todayProfitCNY(for position: Position, asOf date: Date = .now) -> Decimal {
        guard position.category != .cash, position.weeklyTrend.count >= 2 else { return 0 }
        guard position.wasFetchedOnSameDay(as: date) else { return 0 }
        let latestPrice = Decimal(position.weeklyTrend[position.weeklyTrend.count - 1])
        let previousPrice = Decimal(position.weeklyTrend[position.weeklyTrend.count - 2])
        let priceChange = latestPrice - previousPrice
        return position.quantity * priceChange / position.quoteCurrency.rateFromCNY
    }

    var categoryAllocation: [AllocationItem] {
        allocationItems(AssetCategory.allCases) { category in
            (
                category.title(language: appLanguage),
                category.color,
                positions.filter { $0.category == category }.reduce(0) { $0 + $1.marketValueCNY }
            )
        }
    }

    var currencyAllocation: [AllocationItem] {
        allocationItems(DisplayCurrency.allCases) { currency in
            (
                currency.rawValue,
                currency.color,
                positions.filter { $0.quoteCurrency == currency }.reduce(0) { $0 + $1.marketValueCNY }
            )
        }
    }

    var filteredPositions: [Position] {
        guard !searchText.isEmpty else { return positions }
        return positions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.symbol.localizedCaseInsensitiveContains(searchText)
        }
    }

    var visibleSnapshots: [PortfolioSnapshot] {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -trendRange.days, to: .now) else {
            return snapshotHistory
        }
        let cutoff = calendar.startOfDay(for: cutoffDate)
        return snapshotHistory.filter { $0.date >= cutoff }
    }

    var riskConstraintEvaluation: RiskConstraintEvaluation {
        RiskConstraintEvaluation.evaluate(
            positions: positions,
            positionLimit: positionLimit,
            cryptoLimit: cryptoLimit,
            foreignCurrencyLimit: foreignCurrencyLimit,
            liquidityMinimum: liquidityMinimum
        )
    }

    func converted(_ valueCNY: Decimal) -> Decimal {
        valueCNY * displayCurrency.rateFromCNY
    }

    func exportFinancialData(to url: URL) throws -> PortfolixDataTransferSummary {
        guard let positionRepository else {
            throw PositionRepositoryError.database("当前未连接到可用的本地数据库")
        }
        let payload = try positionRepository.exportDataPayload()
        return try PortfolixDataPackageService.write(payload: payload, to: url)
    }

    func prepareFinancialDataImport(from url: URL) throws -> PreparedPortfolixDataImport {
        try PortfolixDataPackageService.prepareImport(from: url)
    }

    func importFinancialData(_ preparedImport: PreparedPortfolixDataImport) throws -> PortfolixDataTransferSummary {
        guard let positionRepository else {
            throw PositionRepositoryError.database("当前未连接到可用的本地数据库")
        }
        let summary = try positionRepository.importDataPayload(preparedImport.payload)
        positions = try positionRepository.fetchPositions()
        snapshotHistory = try positionRepository.fetchPortfolioSnapshots()
        return summary
    }

    func presentNewPositionEditor() {
        positionEditorPresentation = PositionEditorPresentation(position: nil)
    }

    func presentPositionEditor(for positionID: Position.ID) {
        guard let position = positions.first(where: { $0.id == positionID }) else { return }
        positionEditorPresentation = PositionEditorPresentation(position: position)
    }

    func addPosition(
        name: String,
        symbol: String,
        category: AssetCategory,
        quantity: Decimal,
        averageCost: Decimal,
        quoteCurrency: DisplayCurrency,
        latestPrice: Decimal,
        source: String = "手工价格",
        quoteTime: String = "刚刚",
        freshness: Freshness = .manual
    ) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedSource = normalizedQuoteSource(source, category: category)
        try PositionInputValidator.validate(
            name: normalizedName,
            symbol: normalizedSymbol,
            quantity: quantity,
            averageCost: averageCost,
            latestPrice: latestPrice
        )
        try PositionInputValidator.validateProviderIdentity(
            category: category,
            quoteCurrency: quoteCurrency,
            source: normalizedSource
        )
        guard !containsPosition(symbol: normalizedSymbol, category: category) else {
            throw PositionValidationError.duplicateAsset
        }

        let position = Position(
            name: normalizedName,
            symbol: normalizedSymbol,
            category: category,
            quoteCurrency: quoteCurrency,
            quantity: quantity,
            averageCost: averageCost,
            latestPrice: latestPrice,
            marketValueCNY: calculateMarketValueCNY(
                category: category,
                quantity: quantity,
                latestPrice: latestPrice,
                quoteCurrency: quoteCurrency
            ),
            profitRate: averageCost == 0 ? 0 : (latestPrice - averageCost) / averageCost * 100,
            weeklyTrend: Array(repeating: latestPrice.doubleValue, count: 7),
            source: normalizedSource,
            quoteTime: quoteTime,
            freshness: freshness
        )

        if let positionRepository {
            try positionRepository.insert(position)
            positions = try positionRepository.fetchPositions()
        } else {
            positions.append(position)
        }
        persistCurrentSnapshot()
        if let positionRepository {
            positions = try positionRepository.fetchPositions()
        }
    }

    func updatePosition(
        id: Position.ID,
        name: String,
        symbol: String,
        category: AssetCategory,
        quantity: Decimal,
        averageCost: Decimal,
        quoteCurrency: DisplayCurrency,
        latestPrice: Decimal,
        source: String? = nil,
        quoteTime: String? = nil,
        freshness: Freshness? = nil
    ) throws {
        guard let index = positions.firstIndex(where: { $0.id == id }) else { return }
        let current = positions[index]
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        try PositionInputValidator.validate(
            name: normalizedName,
            symbol: normalizedSymbol,
            quantity: quantity,
            averageCost: averageCost,
            latestPrice: latestPrice
        )
        guard !containsPosition(symbol: normalizedSymbol, category: category, excluding: id) else {
            throw PositionValidationError.duplicateAsset
        }
        let marketValueCNY = calculateMarketValueCNY(
            category: category,
            quantity: quantity,
            latestPrice: latestPrice,
            quoteCurrency: quoteCurrency
        )
        let profitRate = averageCost == 0 ? 0 : (latestPrice - averageCost) / averageCost * 100
        let isManualPrice = latestPrice != current.latestPrice
        let resolvedSource = normalizedQuoteSource(source ?? (isManualPrice ? "手工价格" : current.source), category: category)
        try PositionInputValidator.validateProviderIdentity(
            category: category,
            quoteCurrency: quoteCurrency,
            source: resolvedSource
        )
        let fetchedAt = ISO8601DateFormatter().string(from: .now)

        let updatedPosition = Position(
            id: current.id,
            name: normalizedName,
            symbol: normalizedSymbol,
            category: category,
            quoteCurrency: quoteCurrency,
            quantity: quantity,
            averageCost: averageCost,
            latestPrice: latestPrice,
            marketValueCNY: marketValueCNY,
            profitRate: profitRate,
            weeklyTrend: updatedWeeklyTrend(current: current, latestPrice: latestPrice, fetchedAt: fetchedAt),
            source: resolvedSource,
            quoteTime: quoteTime ?? (isManualPrice ? "刚刚" : current.quoteTime),
            fetchedAt: fetchedAt,
            freshness: freshness ?? (isManualPrice ? .manual : current.freshness)
        )

        if let positionRepository {
            try positionRepository.update(updatedPosition)
            positions = try positionRepository.fetchPositions()
        } else {
            positions[index] = updatedPosition
        }
        persistCurrentSnapshot()
        if let positionRepository {
            positions = try positionRepository.fetchPositions()
        }
    }

    private func updatedWeeklyTrend(current: Position, latestPrice: Decimal, fetchedAt: String) -> [Double] {
        let latest = latestPrice.doubleValue
        var trend = current.weeklyTrend
        guard !trend.isEmpty else { return [latest] }

        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current
        let oldFetchedAt = formatter.date(from: current.fetchedAt)
        let newFetchedAt = formatter.date(from: fetchedAt) ?? .now
        if let oldFetchedAt, calendar.isDate(oldFetchedAt, inSameDayAs: newFetchedAt) {
            trend[trend.count - 1] = latest
            return trend
        }

        trend.append(latest)
        if trend.count > 7 {
            trend = Array(trend.suffix(7))
        }
        return trend
    }

    func markDataSourceAvailable(for candidate: AssetLookupCandidate) {
        let status: DataSourceStatus?
        switch candidate.category {
        case .cnStock, .bStock, .hkStock, .usStock, .fund:
            let sourceName = normalizedQuoteSource(candidate.upstreamSource, category: candidate.category)
            status = DataSourceStatus(
                name: sourceName,
                detail: "股票与基金",
                symbol: dataSourceSymbol(sourceName),
                state: "连接正常",
                color: PortfolixTheme.mint
            )
        case .crypto:
            status = DataSourceStatus(
                name: "OKX",
                detail: "数字货币现货交易对",
                symbol: dataSourceSymbol("OKX"),
                state: "连接正常",
                color: PortfolixTheme.mint
            )
        case .cash:
            status = nil
        }

        guard let status else { return }
        upsertDataSourceStatus(status)
    }

    func deletePosition(for positionID: Position.ID) throws {
        try deletePositions(for: [positionID])
    }

    func deletePositions(for positionIDs: Set<Position.ID>) throws {
        guard !positionIDs.isEmpty else { return }
        if let positionRepository {
            try positionRepository.delete(positionIDs: Array(positionIDs))
            positions = try positionRepository.fetchPositions()
        } else {
            positions.removeAll { positionIDs.contains($0.id) }
        }
        if let selectedPositionID, positionIDs.contains(selectedPositionID) {
            self.selectedPositionID = nil
        }
        persistCurrentSnapshot()
    }

    private func containsPosition(
        symbol: String,
        category: AssetCategory,
        excluding positionID: Position.ID? = nil
    ) -> Bool {
        positions.contains {
            $0.id != positionID
                && $0.category == category
                && $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame
        }
    }

    func refresh() {
        Task { await refreshLatestPrices() }
    }

    func refreshProviderCredentialState() {
        let hasLLMKey = ((try? credentialStore.read(kind: .llm)) ?? nil)?.isEmpty == false
        let searchCredentialKind = searchConfiguration.provider.credentialKind
        let hasSearchKey = ((try? credentialStore.read(kind: searchCredentialKind)) ?? nil)?.isEmpty == false

        hasLLMAPIKey = hasLLMKey
        hasSearchAPIKey = hasSearchKey
        llmAPIKeyValidationState = hasLLMKey ? ((try? credentialStore.readValidationState(kind: .llm)) ?? .unknown) : .unknown
        searchAPIKeyValidationState = hasSearchKey
            ? ((try? credentialStore.readValidationState(kind: searchCredentialKind)) ?? .unknown)
            : .unknown
    }

    func saveProviderAPIKey(_ apiKey: String, kind: ProviderCredentialKind) throws {
        try credentialStore.save(apiKey, kind: kind)
        refreshProviderCredentialState()
    }

    func saveProviderAPIKeyValidationState(_ state: ProviderCredentialValidationState, kind: ProviderCredentialKind) throws {
        try credentialStore.saveValidationState(state, kind: kind)
        refreshProviderCredentialState()
    }

    func readProviderAPIKey(kind: ProviderCredentialKind) throws -> String? {
        try credentialStore.read(kind: kind)
    }

    func deleteProviderAPIKey(kind: ProviderCredentialKind) throws {
        try credentialStore.delete(kind: kind)
        refreshProviderCredentialState()
    }

    func generateAIAnalysis(trigger: AIAnalysisTrigger = .manual) {
        if trigger == .manual {
            let hasReport = aiAnalysisChatItems.contains { item in
                if case .report = item.content { return true }
                return false
            }
            appendAIAnalysisChatItem(
                .user(
                    hasReport
                        ? localizedText("请重新生成分析报告", "Regenerate the analysis report", language: appLanguage)
                        : localizedText("请基于当前持仓生成一次智能分析报告", "Generate a smart analysis report from my current portfolio", language: appLanguage)
                )
            )
        }
        Task { await generateAIAnalysisReport(trigger: trigger) }
    }

    func refreshAIAnalysisChatRetention() {
        pruneAIAnalysisChatHistory()
    }

    func submitAIAnalysisFollowUp(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnsweringAIAnalysisFollowUp else { return }
        appendAIAnalysisChatItem(.user(trimmed))
        isAnsweringAIAnalysisFollowUp = true
        aiAnalysisFollowUpProgress = .analyzing

        Task {
            let answer = await answerAIAnalysisFollowUp(trimmed)
            appendAIAnalysisChatItem(.assistant(answer))
            aiAnalysisFollowUpProgress = nil
            isAnsweringAIAnalysisFollowUp = false
        }
    }

#if DEBUG
    func prepareAIAnalysisPromptCapture() async -> (
        positions: [Position],
        context: AIAnalysisStoreContext,
        refreshedCount: Int
    ) {
        let refreshedCount = await refreshPricesForAIAnalysis()
        let positionPerformance = loadAIPositionPerformance(asOf: Date())
        return (
            positions: positions,
            context: makeAIStoreContext(positionPerformance: positionPerformance),
            refreshedCount: refreshedCount
        )
    }
#endif

    private func aiAPIConfigurationMessage(language: AppLanguage) -> String? {
        let needsSearchAPI = searchConfiguration.isEnabled
        let missingLLM = !hasValidLLMAPIKey
        let missingSearch = needsSearchAPI && !hasValidSearchAPIKey

        switch (missingLLM, missingSearch) {
        case (true, true):
            return localizedText(
                "LLM API 和 Search API 均未完成有效配置。请先在系统设置中配置并验证这两个 API Key 后，再使用联网增强分析。",
                "Both the LLM API and Search API are not validly configured. Configure and validate both API keys in Settings before using connected analysis.",
                language: language
            )
        case (true, false):
            return localizedText(
                "LLM API 未完成有效配置。请先在系统设置中配置并验证 LLM API Key 后再使用智能分析。",
                "The LLM API is not validly configured. Configure and validate the LLM API key in Settings before using smart analysis.",
                language: language
            )
        case (false, true):
            return localizedText(
                "当前开启了联网增强，Search API 未完成有效配置。请先在系统设置中配置并验证 Search API Key，或切换到基础模式。",
                "Connected search is enabled, but the Search API is not validly configured. Configure and validate the Search API key in Settings, or switch to Basic mode.",
                language: language
            )
        case (false, false):
            return nil
        }
    }

    private func answerAIAnalysisFollowUp(_ question: String) async -> String {
        refreshProviderCredentialState()
        let responseAppLanguage: AppLanguage = AIResponseLanguage.detecting(from: question) == .english
            ? .english
            : .chinese
        guard let report = aiAnalysisReport else {
            return localizedText("请先生成一份智能分析报告，再继续追问。", "Generate a smart analysis report before asking a follow-up.", language: responseAppLanguage)
        }
        guard aiConfiguration.isEnabled else {
            return localizedText("请先启用 AI 资产分析并配置 LLM API Key。", "Enable AI Asset Analysis and configure an LLM API Key first.", language: responseAppLanguage)
        }
        if let configurationMessage = aiAPIConfigurationMessage(language: responseAppLanguage) {
            return configurationMessage
        }

        do {
            let artifacts = try positionRepository?.fetchLatestAIAnalysisArtifacts() ?? nil
            let followUpContext = makeAIFollowUpPortfolioContext(asOf: Date())
            let result = try await aiAgent.answerFollowUp(
                question: question,
                report: report,
                artifacts: artifacts,
                chatHistory: aiAnalysisChatItems,
                positions: positions,
                portfolioContext: followUpContext,
                llmConfiguration: aiConfiguration,
                searchConfiguration: searchConfiguration,
                progress: { [weak self] progress in
                    await MainActor.run {
                        self?.aiAnalysisFollowUpProgress = progress
                    }
                }
            )
            return result.answer
        } catch {
            return localizedText(
                "这次追问未通过信息安全或模型返回结构校验，请稍后重试。",
                "This follow-up did not pass information security or response-structure validation. Please try again.",
                language: responseAppLanguage
            )
        }
    }

    func refreshPosition(id: Position.ID) {
        guard !refreshingPositionIDs.contains(id) else { return }
        Task { await refreshLatestPrice(for: id) }
    }

    func riskProfileUpdatedText(now: Date, language: AppLanguage) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(riskProfileUpdatedAt)))
        if seconds < 60 {
            return language == .english ? "Just updated" : "刚刚更新"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return language == .english ? "\(minutes)m ago" : "\(minutes) 分钟前更新"
        }

        let hours = minutes / 60
        if hours < 24 {
            return language == .english ? "\(hours)h ago" : "\(hours) 小时前更新"
        }

        let days = hours / 24
        return language == .english ? "\(days)d ago" : "\(days) 天前更新"
    }

    func saveRiskThresholdVersion(now: Date = .now) {
        riskProfileVersion += 1
        riskProfileUpdatedAt = now
        persistRiskProfileSettings()
    }

    func applyRiskQuestionnaire(
        riskLevel: String,
        positionLimit: Double,
        cryptoLimit: Double,
        foreignCurrencyLimit: Double,
        liquidityMinimum: Double
    ) {
        self.riskLevel = riskLevel
        riskProfileConfigured = true
        self.positionLimit = positionLimit
        self.cryptoLimit = cryptoLimit
        self.foreignCurrencyLimit = foreignCurrencyLimit
        self.liquidityMinimum = liquidityMinimum
        saveRiskThresholdVersion()
    }

    func skipRiskQuestionnaire() {
        riskLevel = "未配置"
        riskProfileConfigured = false
        persistRiskProfileSettings()
    }

    private func allocationItems<T>(
        _ values: [T],
        transform: (T) -> (name: String, color: Color, marketValueCNY: Decimal)
    ) -> [AllocationItem] {
        let total = totalValueCNY.doubleValue
        guard total > 0 else { return [] }

        return values.compactMap { value in
            let item = transform(value)
            guard item.marketValueCNY > 0 else { return nil }
            return AllocationItem(
                name: item.name,
                value: item.marketValueCNY.doubleValue / total * 100,
                color: item.color
            )
        }
    }

    private func generateAIAnalysisReport(trigger: AIAnalysisTrigger) async {
        refreshProviderCredentialState()
        guard !positions.isEmpty else {
            aiAnalysisRun = AIAnalysisRun(status: .failed(localizedText("请先添加持仓", "Add holdings first", language: appLanguage)))
            return
        }
        guard aiConfiguration.isEnabled else {
            aiAnalysisRun = AIAnalysisRun(status: .missingConfiguration(localizedText("AI 资产分析未启用", "AI Asset Analysis is disabled", language: appLanguage)))
            return
        }
        if let configurationMessage = aiAPIConfigurationMessage(language: appLanguage) {
            aiAnalysisRun = AIAnalysisRun(status: .missingConfiguration(configurationMessage))
            if trigger == .manual {
                appendAIAnalysisChatItem(.assistant(configurationMessage))
            }
            return
        }

        let startedAt = Date()
        aiAnalysisRun = AIAnalysisRun(
            status: .running(.preflight),
            startedAt: startedAt,
            model: aiConfiguration.model
        )
        Self.aiAnalysisLogger.info("Agent run started")

        var analysisContext = makeAIStoreContext()
        do {
            updateAIAnalysisProgress(.refreshingPrices(assetCount: positions.count), startedAt: startedAt)
            let refreshedCount = await refreshPricesForAIAnalysis()
            updateAIAnalysisProgress(
                .pricesRefreshed(updated: refreshedCount, total: positions.count),
                startedAt: startedAt
            )
            let positionPerformance = loadAIPositionPerformance(asOf: Date())
            analysisContext = makeAIStoreContext(positionPerformance: positionPerformance)
            let previousReport = aiAnalysisReport
            let result = try await aiAgent.generateReportResult(
                positions: positions,
                storeContext: analysisContext,
                llmConfiguration: aiConfiguration,
                searchConfiguration: searchConfiguration,
                trigger: trigger,
                outputLanguage: appLanguage.aiResponseLanguage,
                previousReport: previousReport,
                progress: { [weak self] progress in
                    await self?.updateAIAnalysisProgress(progress, startedAt: startedAt)
                }
            )
            let report = result.report
            let finishedAt = Date()
            updateAIAnalysisProgress(.savingReport, startedAt: startedAt)
            aiAnalysisReport = report
            persistAIAnalysisReport(report)
            persistAIAnalysisRun(
                report: report,
                artifacts: result.artifacts,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: finishedAt,
                usedFallback: false,
                errorCode: nil
            )
            aiAnalysisRun = AIAnalysisRun(
                status: .completed,
                startedAt: startedAt,
                finishedAt: finishedAt,
                model: aiConfiguration.model,
                searchCount: report.sources.count
            )
            appendAIAnalysisChatItem(.report(report, aiAnalysisRun))
            Self.aiAnalysisLogger.info("Agent run completed without fallback")
        } catch let error as AIAnalysisAgentError {
            if error == .missingLLMKey || error == .missingSearchKey || error == .emptyPortfolio {
                aiAnalysisRun = AIAnalysisRun(status: .missingConfiguration(error.localizedDescription), startedAt: startedAt, finishedAt: .now, model: aiConfiguration.model)
                return
            }
            completeAIAnalysisWithFallback(error: error, trigger: trigger, startedAt: startedAt, context: analysisContext)
        } catch {
            completeAIAnalysisWithFallback(error: error, trigger: trigger, startedAt: startedAt, context: analysisContext)
        }
    }

    private func updateAIAnalysisProgress(_ progress: AIAnalysisProgress, startedAt: Date) {
        guard aiAnalysisRun.startedAt == startedAt else { return }
        guard case .running = aiAnalysisRun.status else { return }
        aiAnalysisRun.status = .running(progress)
        Self.aiAnalysisLogger.info("Agent stage: \(progress.telemetryID, privacy: .public)")
    }

    private func completeAIAnalysisWithFallback(
        error: Error,
        trigger: AIAnalysisTrigger,
        startedAt: Date,
        context: AIAnalysisStoreContext
    ) {
        let errorDescription = error.localizedDescription
        let fallbackReason = aiFallbackReason(for: error)
        let fallback = AIAnalysisAgent.fallbackReport(
            positions: positions,
            context: context,
            reason: fallbackReason,
            model: aiConfiguration.model,
            outputLanguage: appLanguage.aiResponseLanguage
        )
        let finishedAt = Date()
        let artifacts = (error as? AIAnalysisPipelineError)?.partialArtifacts
            ?? fallbackAIArtifacts(
                report: fallback,
                trigger: trigger,
                startedAt: startedAt,
                reason: errorDescription,
                previousReport: aiAnalysisReport,
                context: context
            )
        aiAnalysisReport = fallback
        persistAIAnalysisReport(fallback)
        persistAIAnalysisRun(
            report: fallback,
            artifacts: artifacts,
            trigger: trigger,
            startedAt: startedAt,
            finishedAt: finishedAt,
            usedFallback: true,
            errorCode: errorDescription
        )
        aiAnalysisRun = AIAnalysisRun(
            status: .completed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            model: aiConfiguration.model,
            usedFallback: true,
            fallbackReason: fallbackReason
        )
        appendAIAnalysisChatItem(.report(fallback, aiAnalysisRun))

        let stageID = (error as? AIAnalysisPipelineError)?.stage.telemetryID ?? "unknown"
        Self.aiAnalysisLogger.error(
            "Agent fallback at stage \(stageID, privacy: .public): \(errorDescription, privacy: .private)"
        )
    }

    private func aiFallbackReason(for error: Error) -> String {
        let stage = (error as? AIAnalysisPipelineError)?.stage
        let context = stage?.failureContext(language: appLanguage)
            ?? localizedText("Agent 执行", "Agent execution", language: appLanguage)
        let description = error.localizedDescription.lowercased()
        if description.contains("timed out") || description.contains("timeout") || description.contains("超时") {
            return localizedText(
                "\(context)请求超时，已改用本地分析。请检查代理连接、Endpoint 和模型响应速度后重试。",
                "The \(context) request timed out, so local analysis was used. Check the proxy, endpoint, and model response time before retrying.",
                language: appLanguage
            )
        }
        if description.contains("安全校验") || description.contains("invalid report") {
            return localizedText(
                "\(context)未通过结构或安全校验，已改用本地分析。",
                "The \(context) output failed structural or safety validation, so local analysis was used.",
                language: appLanguage
            )
        }
        return localizedText(
            "\(context)失败，已改用本地分析。可检查 API 配置、网络连接和模型可用性后重试。",
            "The \(context) stage failed, so local analysis was used. Check API configuration, connectivity, and model availability before retrying.",
            language: appLanguage
        )
    }

    private func makeAIStoreContext(
        positionPerformance: [Position.ID: AIPositionPerformanceContext] = [:]
    ) -> AIAnalysisStoreContext {
        AIAnalysisStoreContext(
            displayCurrency: displayCurrency,
            convertedTotalValue: converted(totalValueCNY),
            convertedTotalProfit: converted(totalProfitCNY),
            totalProfitRate: totalProfitRate,
            riskProfileConfigured: riskProfileConfigured,
            riskProfileVersion: riskProfileVersion,
            riskLevel: riskLevel,
            positionLimit: positionLimit,
            cryptoLimit: cryptoLimit,
            foreignCurrencyLimit: foreignCurrencyLimit,
            liquidityMinimum: liquidityMinimum,
            riskConstraintEvaluation: riskConstraintEvaluation,
            positionPerformance: positionPerformance
        )
    }

    private static func savedAIAnalysisReport() -> AIAnalysisReport? {
        guard let data = UserDefaults.standard.data(forKey: latestAIReportDefaultsKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AIAnalysisReport.self, from: data)
    }

    private func persistAIAnalysisReport(_ report: AIAnalysisReport) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return }
        UserDefaults.standard.set(data, forKey: Self.latestAIReportDefaultsKey)
    }

    private func removePersistedAIAnalysisReportIfExpired(cutoff: Date) {
        guard let report = Self.savedAIAnalysisReport(), report.generatedAt < cutoff else { return }
        UserDefaults.standard.removeObject(forKey: Self.latestAIReportDefaultsKey)
    }

    private var currentAIAnalysisMode: String {
        searchConfiguration.isEnabled ? "connected_enhanced" : "basic_standard"
    }

    private var currentAIPrivacyMode: String {
        "include_asset_labels"
    }

    private func seedAIAnalysisChatIfNeeded() {
        guard aiAnalysisChatItems.isEmpty, let report = aiAnalysisReport else { return }
        let prompt = localizedText(
            "请基于当前持仓生成一次智能分析报告",
            "Generate a smart analysis report from my current portfolio",
            language: appLanguage
        )
        let run = AIAnalysisRun(status: .completed, finishedAt: report.generatedAt, model: report.model)
        appendAIAnalysisChatItem(.user(prompt, createdAt: report.generatedAt.addingTimeInterval(-1)))
        appendAIAnalysisChatItem(.report(report, run))
    }

    private func appendAIAnalysisChatItem(_ item: AIReportChatItem) {
        guard item.createdAt >= aiChatRetentionPeriod.cutoffDate() else { return }
        if let index = aiAnalysisChatItems.firstIndex(where: { $0.id == item.id }) {
            aiAnalysisChatItems[index] = item
        } else {
            aiAnalysisChatItems.append(item)
            aiAnalysisChatItems.sort { $0.createdAt < $1.createdAt }
        }
        do {
            try positionRepository?.upsertAIAnalysisChatItem(item)
        } catch {
            persistenceErrorMessage = "AI 对话记录保存失败：\(error.localizedDescription)"
        }
    }

    private func pruneAIAnalysisChatHistory(now: Date = .now) {
        let cutoff = aiChatRetentionPeriod.cutoffDate(now: now)
        aiAnalysisChatItems.removeAll { $0.createdAt < cutoff }
        if let report = aiAnalysisReport, report.generatedAt < cutoff {
            aiAnalysisReport = nil
        }
        removePersistedAIAnalysisReportIfExpired(cutoff: cutoff)
        do {
            try positionRepository?.deleteExpiredAIAnalysisContent(before: cutoff)
        } catch {
            persistenceErrorMessage = "AI 对话记录清理失败：\(error.localizedDescription)"
        }
    }

    private func persistAIAnalysisRun(
        report: AIAnalysisReport,
        artifacts: AIAnalysisArtifactBundle?,
        trigger: AIAnalysisTrigger,
        startedAt: Date,
        finishedAt: Date,
        usedFallback: Bool,
        errorCode: String?
    ) {
        guard let positionRepository else { return }
        let fingerprintSource = artifacts?.inputJSON ?? artifacts?.finalReportJSON ?? report.summary
        let run = PersistedAIAnalysisRun(
            trigger: trigger.rawValue,
            status: usedFallback ? "fallback_completed" : "completed",
            analysisMode: currentAIAnalysisMode,
            model: aiConfiguration.model,
            provider: aiConfiguration.providerOption.rawValue,
            privacyMode: currentAIPrivacyMode,
            riskProfileVersion: riskProfileVersion,
            inputFingerprint: Self.stableAIFingerprint(fingerprintSource),
            startedAt: startedAt,
            finishedAt: finishedAt,
            usedFallback: usedFallback,
            errorCode: errorCode.map(Self.truncatedAIErrorCode),
            report: report,
            artifacts: artifacts
        )

        do {
            try positionRepository.insertAIAnalysisRun(run)
        } catch {
            persistenceErrorMessage = "AI 分析运行记录保存失败：\(error.localizedDescription)"
        }
    }

    private func fallbackAIArtifacts(
        report: AIAnalysisReport,
        trigger: AIAnalysisTrigger,
        startedAt: Date,
        reason: String,
        previousReport: AIAnalysisReport?,
        context: AIAnalysisStoreContext
    ) -> AIAnalysisArtifactBundle {
        let input = AIAnalysisAgent.makeInput(
            positions: positions,
            context: context,
            configuration: aiConfiguration,
            trigger: trigger,
            generatedAt: startedAt,
            analysisMode: currentAIAnalysisMode,
            outputLanguage: appLanguage.aiResponseLanguage,
            previousReport: previousReport
        )
        let rawReport = AIFallbackReportArtifact(
            status: "fallback",
            reason: reason,
            generatedAt: Self.isoDateFormatter.string(from: report.generatedAt)
        )
        let guardrail = AIStoreGuardrailArtifact(
            status: "fallback",
            validator: "AIAnalysisAgent.fallbackReport",
            checkedAt: Self.isoDateFormatter.string(from: .now),
            notes: [reason]
        )
        return AIAnalysisArtifactBundle(
            inputJSON: encodeAIJSON(input, fallback: "{}"),
            toolResultsJSON: "[]",
            toolPlanJSON: #"{"tool_calls":[]}"#,
            rawReportJSON: encodeAIJSON(rawReport, fallback: #"{"status":"fallback"}"#),
            repairedReportJSON: nil,
            finalReportJSON: encodeAIJSON(report, fallback: "{}"),
            guardrailResultJSON: encodeAIJSON(guardrail, fallback: #"{"status":"fallback"}"#)
        )
    }

    private func encodeAIJSON<T: Encodable>(_ value: T, fallback: String) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return json
    }

    private static func stableAIFingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    private static func truncatedAIErrorCode(_ value: String) -> String {
        String(value.prefix(280))
    }

    func refreshInvestmentProfileIfNeeded(force: Bool = false) {
        Task { await generateInvestmentProfileIfNeeded(force: force) }
    }

    func generateInvestmentProfileForTesting(force: Bool = true) async {
        await generateInvestmentProfileIfNeeded(force: force)
    }

    private func generateInvestmentProfileIfNeeded(force: Bool) async {
        refreshProviderCredentialState()
        guard !isGeneratingInvestmentProfile else { return }
        guard !positions.isEmpty else { return }
        guard aiConfiguration.isEnabled, hasLLMAPIKey, llmAPIKeyValidationState != .invalid else { return }

        let fingerprint = investmentProfileInputFingerprint
        guard force || currentAIInvestmentProfile(fingerprint: fingerprint) == nil else { return }

        isGeneratingInvestmentProfile = true
        defer { isGeneratingInvestmentProfile = false }

        do {
            let profile = try await aiAgent.generateInvestmentProfile(
                positions: positions,
                localScores: localInvestmentProfileScoresForAI,
                storeContext: makeAIStoreContext(),
                llmConfiguration: aiConfiguration,
                inputFingerprint: fingerprint
            )
            aiInvestmentProfile = profile
            persistAIInvestmentProfile(profile)
        } catch {
            return
        }
    }

    private func currentAIInvestmentProfile(fingerprint: String? = nil) -> AIInvestmentProfile? {
        guard aiConfiguration.isEnabled, llmAPIKeyValidationState != .invalid else { return nil }
        let activeFingerprint = fingerprint ?? investmentProfileInputFingerprint
        guard
            let profile = aiInvestmentProfile,
            profile.profileDate == Self.investmentProfileDayString(from: .now),
            profile.model == aiConfiguration.model,
            profile.riskProfileVersion == riskProfileVersion,
            profile.inputFingerprint == activeFingerprint
        else {
            return nil
        }
        return profile
    }

    var investmentProfileAIScoresForDisplay: [String: Double] {
        guard let profile = currentAIInvestmentProfile() else { return [:] }
        return profile.dimensions.reduce(into: [:]) { result, dimension in
            result[dimension.id] = dimension.score
        }
    }

    private var investmentProfileInputFingerprint: String {
        let totalValue = max(positions.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue }, 0.001)
        let positionParts = positions
            .sorted {
                if $0.symbol == $1.symbol {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.symbol < $1.symbol
            }
            .map { position in
                let allocation = position.marketValueCNY.doubleValue / totalValue * 100
                return [
                    position.id.uuidString,
                    position.symbol,
                    position.category.rawValue,
                    position.quoteCurrency.rawValue,
                    stableFingerprintNumber(position.quantity.doubleValue, decimals: 4),
                    stableFingerprintNumber(position.averageCost.doubleValue, decimals: 4),
                    stableFingerprintNumber(position.latestPrice.doubleValue, decimals: 4),
                    stableFingerprintNumber(allocation, decimals: 1),
                    stableFingerprintNumber(position.profitRate.doubleValue, decimals: 1),
                    position.priceDateText(language: .chinese),
                ].joined(separator: ":")
            }
            .joined(separator: "|")
        return [
            "v2-local-primary",
            aiConfiguration.model,
            String(riskProfileVersion),
            stableFingerprintNumber(positionLimit, decimals: 0),
            stableFingerprintNumber(cryptoLimit, decimals: 0),
            stableFingerprintNumber(foreignCurrencyLimit, decimals: 0),
            stableFingerprintNumber(liquidityMinimum, decimals: 0),
            positionParts,
        ].joined(separator: "#")
    }

    private func stableFingerprintNumber(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    private static func investmentProfileDayString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    private static func savedAIInvestmentProfile() -> AIInvestmentProfile? {
        guard let data = UserDefaults.standard.data(forKey: latestAIInvestmentProfileDefaultsKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AIInvestmentProfile.self, from: data)
    }

    private func persistAIInvestmentProfile(_ profile: AIInvestmentProfile) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.latestAIInvestmentProfileDefaultsKey)
    }

    private func configureBackgroundUpdateTask() {
        backgroundUpdateTask?.cancel()
        backgroundUpdateTask = nil

        guard backgroundUpdatesEnabled else { return }
        backgroundUpdateTask = Task { [weak self] in
            await self?.refreshLatestPrices()
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.automaticPriceUpdateFrequency.nextDelaySeconds()
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    break
                }
                await self.refreshLatestPrices()
            }
        }
    }

    private func configureLoginItem(launchImmediately: Bool) {
        guard positionRepository != nil, !Self.shouldSkipLaunchRefresh, !Self.shouldSkipLoginItemConfiguration else { return }
        Task { @MainActor in
            let service = SMAppService.loginItem(identifier: Self.loginItemIdentifier)
            do {
                if backgroundUpdatesEnabled {
                    try service.register()
                    if launchImmediately {
                        launchLoginItemIfAvailable()
                    }
                } else {
                    try service.unregister()
                }
            } catch {
                persistenceErrorMessage = "自动获取最新价格后台组件配置失败：\(error.localizedDescription)"
            }
        }
    }

    private func launchLoginItemIfAvailable() {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("LoginItems")
            .appendingPathComponent("PortfolixPriceUpdater.app")
        guard FileManager.default.fileExists(atPath: helperURL.path) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.persistenceErrorMessage = "自动获取最新价格后台组件启动失败：\(error.localizedDescription)"
            }
        }
    }

    private func refreshPricesForAIAnalysis() async -> Int {
        if isRefreshing {
            let deadline = Date().addingTimeInterval(30)
            while isRefreshing, Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return await refreshLatestPrices(refreshInvestmentProfile: false)
    }

    @discardableResult
    private func refreshLatestPrices(refreshInvestmentProfile: Bool = true) async -> Int {
        guard !isRefreshing else { return 0 }
        guard !positions.isEmpty else {
            persistCurrentSnapshot()
            await refreshDataSourceHealth()
            return 0
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let currentPositions = positions
        var refreshedCount = 0
        for position in currentPositions {
            do {
                if try await applyLatestQuote(for: position) {
                    refreshedCount += 1
                }
            } catch {
                continue
            }
        }
        persistCurrentSnapshot()
        await refreshDataSourceHealth()
        if refreshInvestmentProfile {
            refreshInvestmentProfileIfNeeded()
        }
        return refreshedCount
    }

    private func refreshLatestPrice(for positionID: Position.ID) async {
        guard let position = positions.first(where: { $0.id == positionID }) else { return }
        refreshingPositionIDs.insert(positionID)
        defer { refreshingPositionIDs.remove(positionID) }

        do {
            _ = try await applyLatestQuote(for: position)
            persistCurrentSnapshot()
            await refreshDataSourceHealth()
            refreshInvestmentProfileIfNeeded(force: true)
        } catch {
            persistenceErrorMessage = "更新 \(position.name) 失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func applyLatestQuote(for position: Position) async throws -> Bool {
        guard let resolved = try await latestQuote(for: position), let latestPrice = resolved.latestPrice else {
            return false
        }
        try updatePosition(
            id: position.id,
            name: resolved.name,
            symbol: resolved.symbol,
            category: resolved.category,
            quantity: position.quantity,
            averageCost: position.averageCost,
            quoteCurrency: resolved.quoteCurrency,
            latestPrice: latestPrice,
            source: resolved.upstreamSource,
            quoteTime: resolved.quoteTime ?? "刚刚",
            freshness: .updated
        )
        return true
    }

    private func makeAIFollowUpPortfolioContext(asOf date: Date) -> AIFollowUpPortfolioContext {
        let generatedAt = Self.isoDateFormatter.string(from: date)
        let snapshotDate = Self.aiSnapshotDayFormatter.string(from: date)
        let positionPerformance = loadAIPositionPerformance(asOf: date)
        let totalValue = totalValueCNY
        let totalValueForAllocation = max(totalValue.doubleValue, 0.001)
        let portfolioTodayProfit = todayProfitCNY(asOf: date)
        let nonCashPositions = positions.filter { $0.category != .cash }
        let availableTodayCount = nonCashPositions.filter { todayReturnStatus(for: $0, asOf: date) == "available" }.count
        let portfolioTodayStatus: String
        if nonCashPositions.isEmpty {
            portfolioTodayStatus = "not_applicable_cash"
        } else if availableTodayCount == nonCashPositions.count {
            portfolioTodayStatus = "available"
        } else if availableTodayCount > 0 {
            portfolioTodayStatus = "partial"
        } else {
            portfolioTodayStatus = "unavailable"
        }

        let positionContexts = positions
            .sorted { $0.marketValueCNY > $1.marketValueCNY }
            .map { position in
                let todayProfit = todayProfitCNY(for: position, asOf: date)
                let todayStatus = todayReturnStatus(for: position, asOf: date)
                let baseline = position.marketValueCNY - todayProfit
                let todayReturnRate = todayStatus == "available" && baseline != 0
                    ? (todayProfit / baseline * 100).doubleValue
                    : nil
                let performance = positionPerformance[position.id]
                    ?? unavailableFollowUpPerformance(for: position, generatedAt: date)
                return AIFollowUpPositionContext(
                    positionRef: "position_\(position.id.uuidString)",
                    displayLabel: position.name,
                    symbol: position.symbol,
                    assetType: position.category.aiCode,
                    quoteCurrency: position.quoteCurrency.rawValue,
                    quantity: Self.aiDecimalString(position.quantity),
                    latestPrice: Self.aiDecimalString(position.latestPrice),
                    marketValueCNY: Self.aiDecimalString(position.marketValueCNY),
                    allocationPct: position.marketValueCNY.doubleValue / totalValueForAllocation * 100,
                    today: AIFollowUpReturnContext(
                        status: todayStatus,
                        profitAmountCNY: todayStatus == "available" ? Self.aiDecimalString(todayProfit) : nil,
                        profitAmountDisplay: todayStatus == "available" ? formatSignedMoney(converted(todayProfit), currency: displayCurrency) : nil,
                        returnRatePct: todayReturnRate,
                        calculationBasis: "latest_price_change_from_previous_recorded_price_when_quote_fetched_today"
                    ),
                    oneWeek: performance.oneWeek,
                    quoteTime: position.quoteTime,
                    fetchedAt: position.fetchedAt,
                    source: position.source
                )
            }

        return AIFollowUpPortfolioContext(
            snapshotDate: snapshotDate,
            generatedAt: generatedAt,
            displayCurrency: displayCurrency.rawValue,
            totalValueCNY: Self.aiDecimalString(totalValue),
            totalValueDisplay: formatMoney(converted(totalValue), currency: displayCurrency),
            today: AIFollowUpReturnContext(
                status: portfolioTodayStatus,
                profitAmountCNY: portfolioTodayStatus == "unavailable" ? nil : Self.aiDecimalString(portfolioTodayProfit),
                profitAmountDisplay: portfolioTodayStatus == "unavailable" ? nil : formatSignedMoney(converted(portfolioTodayProfit), currency: displayCurrency),
                returnRatePct: portfolioTodayStatus == "unavailable" ? nil : todayProfitRate(asOf: date).doubleValue,
                calculationBasis: "sum_of_position_today_returns_when_quote_fetched_today"
            ),
            positions: positionContexts
        )
    }

    private func todayReturnStatus(for position: Position, asOf date: Date) -> String {
        guard position.category != .cash else { return "not_applicable_cash" }
        guard position.weeklyTrend.count >= 2, position.wasFetchedOnSameDay(as: date) else {
            return "unavailable"
        }
        return "available"
    }

    private func unavailableFollowUpPerformance(
        for position: Position,
        generatedAt: Date
    ) -> AIPositionPerformanceContext {
        func window(days: Int) -> AIPerformanceWindowContext {
            AIPerformanceWindowContext(
                status: "insufficient_history",
                periodDays: days,
                startDate: nil,
                endDate: Self.aiSnapshotDayFormatter.string(from: generatedAt),
                startPrice: nil,
                endPrice: Self.aiDecimalString(position.latestPrice),
                profitAmountQuote: nil,
                returnRatePct: nil,
                observationDays: nil,
                calculationBasis: "price_change_times_current_quantity_excludes_trades_fees_fx"
            )
        }
        return AIPositionPerformanceContext(oneWeek: window(days: 7), oneMonth: window(days: 30))
    }

    private func loadAIPositionPerformance(asOf date: Date) -> [Position.ID: AIPositionPerformanceContext] {
        guard let positionRepository else { return [:] }
        var result: [Position.ID: AIPositionPerformanceContext] = [:]
        for position in positions {
            let snapshots = (try? positionRepository.fetchAssetPriceSnapshots(
                positionID: position.id,
                lookbackDays: 45,
                through: date
            )) ?? []
            result[position.id] = AIPositionPerformanceContext(
                oneWeek: makeAIPerformanceWindow(
                    position: position,
                    snapshots: snapshots,
                    periodDays: 7,
                    maximumBaselineLagDays: 7,
                    asOf: date
                ),
                oneMonth: makeAIPerformanceWindow(
                    position: position,
                    snapshots: snapshots,
                    periodDays: 30,
                    maximumBaselineLagDays: 10,
                    asOf: date
                )
            )
        }
        return result
    }

    private func makeAIPerformanceWindow(
        position: Position,
        snapshots: [AssetPriceSnapshotPoint],
        periodDays: Int,
        maximumBaselineLagDays: Int,
        asOf date: Date
    ) -> AIPerformanceWindowContext {
        let calendar = Calendar.current
        let targetDate = calendar.date(byAdding: .day, value: -periodDays, to: date) ?? date
        let baseline = snapshots.last { $0.date <= targetDate }
        let endDate = Self.aiSnapshotDayFormatter.string(from: date)
        let basis = "price_change_times_current_quantity_excludes_trades_fees_fx"
        guard let baseline else {
            return AIPerformanceWindowContext(
                status: "insufficient_history",
                periodDays: periodDays,
                startDate: nil,
                endDate: endDate,
                startPrice: nil,
                endPrice: Self.aiDecimalString(position.latestPrice),
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
                startDate: Self.aiSnapshotDayFormatter.string(from: baseline.date),
                endDate: endDate,
                startPrice: Self.aiDecimalString(baseline.latestPrice),
                endPrice: Self.aiDecimalString(position.latestPrice),
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
            startDate: Self.aiSnapshotDayFormatter.string(from: baseline.date),
            endDate: endDate,
            startPrice: Self.aiDecimalString(baseline.latestPrice),
            endPrice: Self.aiDecimalString(position.latestPrice),
            profitAmountQuote: Self.aiDecimalString(profit),
            returnRatePct: returnRate.doubleValue,
            observationDays: observationDays,
            calculationBasis: basis
        )
    }

    private static func aiDecimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static let aiSnapshotDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func refreshDataSourceHealth() async {
        let currentPositions = positions
        var statuses: [DataSourceStatus] = []

        let quoteBackedPositions = currentPositions.filter {
            [.cnStock, .bStock, .hkStock, .usStock, .fund].contains($0.category)
        }
        if quoteBackedPositions.isEmpty {
            statuses.append(
                DataSourceStatus(
                    name: "新浪财经",
                    detail: "暂无需自动获取价格的持仓",
                    symbol: "pause.circle.fill",
                    state: "未使用",
                    color: PortfolixTheme.tertiaryText
                )
            )
        } else {
            var seenSources: Set<String> = []
            for position in quoteBackedPositions {
                let fallbackSource = normalizedQuoteSource(position.source, category: position.category)
                do {
                    let resolved = try await latestQuote(for: position)
                    let sourceName = normalizedQuoteSource(resolved?.upstreamSource ?? fallbackSource, category: position.category)
                    guard seenSources.insert(sourceName).inserted else { continue }
                    statuses.append(
                        DataSourceStatus(
                            name: sourceName,
                            detail: "股票与基金",
                            symbol: dataSourceSymbol(sourceName),
                            state: "连接正常",
                            color: PortfolixTheme.mint
                        )
                    )
                } catch {
                    guard seenSources.insert(fallbackSource).inserted else { continue }
                    statuses.append(
                        DataSourceStatus(
                            name: fallbackSource,
                            detail: String(error.localizedDescription.prefix(28)),
                            symbol: "exclamationmark.triangle.fill",
                            state: "连接异常",
                            color: PortfolixTheme.danger
                        )
                    )
                }
            }
        }

        if let cryptoPosition = currentPositions.first(where: { $0.category == .crypto }) {
            do {
                _ = try await latestQuote(for: cryptoPosition)
                statuses.append(
                    DataSourceStatus(
                        name: "OKX",
                        detail: "数字货币现货交易对",
                        symbol: dataSourceSymbol("OKX"),
                        state: "连接正常",
                        color: PortfolixTheme.mint
                    )
                )
            } catch {
                statuses.append(
                    DataSourceStatus(
                        name: "OKX",
                        detail: String(error.localizedDescription.prefix(28)),
                        symbol: "exclamationmark.triangle.fill",
                        state: "连接异常",
                        color: PortfolixTheme.danger
                    )
                )
            }
        } else {
            statuses.append(
                DataSourceStatus(
                    name: "OKX",
                    detail: "暂无数字货币持仓",
                    symbol: "pause.circle.fill",
                    state: "未使用",
                    color: PortfolixTheme.tertiaryText
                )
            )
        }

        sourceStatuses = statuses
        guard let positionRepository else { return }
        do {
            try positionRepository.replaceDataSourceStatuses(statuses)
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func upsertDataSourceStatus(_ status: DataSourceStatus) {
        var nextStatuses = sourceStatuses.filter {
            normalizedDataSourceName($0.name) != normalizedDataSourceName(status.name)
                && normalizedDataSourceName($0.name) != "OKX"
        }
        nextStatuses.append(status)
        nextStatuses.sort { lhs, rhs in
            dataSourceOrder(lhs.name) < dataSourceOrder(rhs.name)
        }
        sourceStatuses = nextStatuses

        guard let positionRepository else { return }
        do {
            try positionRepository.replaceDataSourceStatuses(sourceStatuses)
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func dataSourceOrder(_ name: String) -> Int {
        switch name {
        case "新浪财经":
            0
        case "东方财富":
            1
        case "同花顺":
            2
        case "OKX":
            3
        case "腾讯财经":
            4
        default:
            99
        }
    }

    private func dataSourceSymbol(_ name: String) -> String {
        switch normalizedDataSourceName(name) {
        case "东方财富", "新浪财经", "同花顺", "腾讯财经":
            return "chart.line.uptrend.xyaxis"
        case "OKX":
            return "okx"
        default:
            return "network"
        }
    }

    private func healthStatus(
        name: String,
        detail: String,
        symbol: String,
        color: Color,
        check: () async throws -> Void
    ) async -> DataSourceStatus {
        do {
            try await check()
            return DataSourceStatus(
                name: name,
                detail: detail,
                symbol: symbol,
                state: "连接正常",
                color: color
            )
        } catch is CancellationError {
            if let existingStatus = sourceStatuses.first(where: { $0.name == name && $0.state != "连接异常" }) {
                return existingStatus
            }
            return DataSourceStatus(
                name: name,
                detail: detail,
                symbol: "clock.arrow.circlepath",
                state: "待检查",
                color: PortfolixTheme.amber
            )
        } catch {
            return DataSourceStatus(
                name: name,
                detail: String(error.localizedDescription.prefix(28)),
                symbol: "exclamationmark.triangle.fill",
                state: "连接异常",
                color: PortfolixTheme.danger
            )
        }
    }

    private func latestQuote(for position: Position) async throws -> AssetLookupCandidate? {
        guard position.category != .cash else { return nil }
        let candidate = AssetLookupCandidate(
            name: position.name,
            symbol: position.symbol,
            category: position.category,
            quoteCurrency: position.quoteCurrency,
            latestPrice: position.latestPrice,
            upstreamSource: position.source
        )

        return try await MarketDataAdapter.shared.resolveAsset(candidate)
    }

    private func persistCurrentSnapshot() {
        guard let positionRepository else { return }
        do {
            try positionRepository.replaceDailySnapshots(positions: positions)
            snapshotHistory = try positionRepository.fetchPortfolioSnapshots()
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func loadRiskProfileSettings(from repository: PositionRepository?) {
        guard let repository else { return }
        do {
            if let value = try repository.appSetting(for: Self.riskProfileConfiguredSettingKey),
               let configured = Self.boolSetting(value) {
                riskProfileConfigured = configured
            }
            if let value = try repository.appSetting(for: Self.riskLevelSettingKey), !value.isEmpty {
                riskLevel = value
            } else if !riskProfileConfigured {
                riskLevel = "未配置"
            }
            if let value = try repository.appSetting(for: Self.riskProfileVersionSettingKey),
               let version = Int(value) {
                riskProfileVersion = max(0, version)
            }
            if let value = try repository.appSetting(for: Self.riskPositionLimitSettingKey),
               let limit = Self.doubleSetting(value) {
                positionLimit = limit
            }
            if let value = try repository.appSetting(for: Self.riskCryptoLimitSettingKey),
               let limit = Self.doubleSetting(value) {
                cryptoLimit = limit
            }
            if let value = try repository.appSetting(for: Self.riskForeignCurrencyLimitSettingKey),
               let limit = Self.doubleSetting(value) {
                foreignCurrencyLimit = limit
            }
            if let value = try repository.appSetting(for: Self.riskLiquidityMinimumSettingKey),
               let limit = Self.doubleSetting(value) {
                liquidityMinimum = limit
            }
            if let value = try repository.appSetting(for: Self.riskProfileUpdatedAtSettingKey),
               let date = Self.isoDateFormatter.date(from: value) {
                riskProfileUpdatedAt = date
            }
        } catch {
            persistenceErrorMessage = "风险偏好设置读取失败：\(error.localizedDescription)"
        }
    }

    private func persistRiskProfileSettings() {
        persistAppSetting(key: Self.riskLevelSettingKey, value: riskLevel)
        persistAppSetting(key: Self.riskProfileConfiguredSettingKey, value: riskProfileConfigured ? "true" : "false")
        persistAppSetting(key: Self.riskProfileVersionSettingKey, value: String(riskProfileVersion))
        persistAppSetting(key: Self.riskPositionLimitSettingKey, value: Self.stableSettingNumber(positionLimit))
        persistAppSetting(key: Self.riskCryptoLimitSettingKey, value: Self.stableSettingNumber(cryptoLimit))
        persistAppSetting(key: Self.riskForeignCurrencyLimitSettingKey, value: Self.stableSettingNumber(foreignCurrencyLimit))
        persistAppSetting(key: Self.riskLiquidityMinimumSettingKey, value: Self.stableSettingNumber(liquidityMinimum))
        persistAppSetting(key: Self.riskProfileUpdatedAtSettingKey, value: Self.isoDateFormatter.string(from: riskProfileUpdatedAt))
    }

    private static func boolSetting(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }

    private static func doubleSetting(_ value: String) -> Double? {
        guard let number = Double(value), number.isFinite else { return nil }
        return number
    }

    private static func stableSettingNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.4f", value)
    }

    private func persistAutomaticPriceUpdateSetting() {
        persistAppSetting(
            key: "automatic_price_updates_enabled",
            value: backgroundUpdatesEnabled ? "true" : "false"
        )
        persistAppSetting(
            key: "automatic_price_update_frequency",
            value: automaticPriceUpdateFrequency.rawValue
        )
        persistAppSetting(
            key: "automatic_price_update_daily_time_minutes",
            value: String(9 * 60)
        )
    }

    private func persistAppSetting(key: String, value: String) {
        guard let positionRepository else { return }
        do {
            try positionRepository.setAppSetting(key: key, value: value)
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }
}

enum PositionValidationError: LocalizedError {
    case duplicateAsset
    case emptyName
    case emptySymbol
    case nameTooLong
    case symbolTooLong
    case invalidQuantity
    case invalidAverageCost
    case invalidLatestPrice
    case numericOverflow
    case providerIdentityMismatch

    var errorDescription: String? {
        switch self {
        case .duplicateAsset:
            "同一类别下已存在相同代码的持仓"
        case .emptyName:
            "资产名称不能为空"
        case .emptySymbol:
            "资产代码不能为空"
        case .nameTooLong:
            "资产名称不能超过 128 个字符"
        case .symbolTooLong:
            "资产代码不能超过 32 个字符"
        case .invalidQuantity:
            "持仓份额必须大于 0"
        case .invalidAverageCost:
            "持仓成本价不能小于 0"
        case .invalidLatestPrice:
            "当前价格必须大于 0"
        case .numericOverflow:
            "份额、成本或价格超出可计算范围"
        case .providerIdentityMismatch:
            "资产类别或计价币种与行情来源不一致，请重新选择候选或改为手工录入"
        }
    }
}

enum PositionInputValidator {
    static func validate(_ position: Position) throws {
        try validate(
            name: position.name,
            symbol: position.symbol,
            quantity: position.quantity,
            averageCost: position.averageCost,
            latestPrice: position.latestPrice
        )
        try validateProviderIdentity(
            category: position.category,
            quoteCurrency: position.quoteCurrency,
            source: position.source
        )
    }

    static func validate(
        name: String,
        symbol: String,
        quantity: Decimal,
        averageCost: Decimal,
        latestPrice: Decimal
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PositionValidationError.emptyName
        }
        guard !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PositionValidationError.emptySymbol
        }
        guard name.count <= 128 else {
            throw PositionValidationError.nameTooLong
        }
        guard symbol.count <= 32 else {
            throw PositionValidationError.symbolTooLong
        }
        guard !quantity.isNaN, quantity > 0 else {
            throw PositionValidationError.invalidQuantity
        }
        guard !averageCost.isNaN, averageCost >= 0 else {
            throw PositionValidationError.invalidAverageCost
        }
        guard !latestPrice.isNaN, latestPrice > 0 else {
            throw PositionValidationError.invalidLatestPrice
        }
        guard !(quantity * averageCost).isNaN, !(quantity * latestPrice).isNaN else {
            throw PositionValidationError.numericOverflow
        }
    }

    static func validateProviderIdentity(
        category: AssetCategory,
        quoteCurrency: DisplayCurrency,
        source: String
    ) throws {
        switch source {
        case "OKX":
            guard category == .crypto, [.usd, .usdt].contains(quoteCurrency) else {
                throw PositionValidationError.providerIdentityMismatch
            }
        case "金十数据":
            guard category == .crypto, [.usd, .usdt].contains(quoteCurrency) else {
                throw PositionValidationError.providerIdentityMismatch
            }
        case let sourceName where isPublicMarketQuoteSource(sourceName):
            let expectedCurrency: DisplayCurrency
            switch category {
            case .cnStock, .fund:
                expectedCurrency = .cny
            case .bStock:
                guard [.usd, .hkd].contains(quoteCurrency) else {
                    throw PositionValidationError.providerIdentityMismatch
                }
                return
            case .hkStock:
                expectedCurrency = .hkd
            case .usStock:
                expectedCurrency = .usd
            case .crypto, .cash:
                throw PositionValidationError.providerIdentityMismatch
            }
            guard quoteCurrency == expectedCurrency else {
                throw PositionValidationError.providerIdentityMismatch
            }
        default:
            break
        }
    }
}

func calculateMarketValueCNY(
    category: AssetCategory,
    quantity: Decimal,
    latestPrice: Decimal,
    quoteCurrency: DisplayCurrency
) -> Decimal {
    _ = category
    return quantity * latestPrice / quoteCurrency.rateFromCNY
}

func calculateTotalCostCNY(
    category: AssetCategory,
    quantity: Decimal,
    averageCost: Decimal,
    quoteCurrency: DisplayCurrency
) -> Decimal {
    _ = category
    return quantity * averageCost / quoteCurrency.rateFromCNY
}
