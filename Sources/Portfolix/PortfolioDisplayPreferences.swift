import Foundation

enum PortfolioDisplayPreferenceKey: String, CaseIterable {
    case displayCurrency = "display_currency"
    case appearanceMode = "appearance_mode"
    case trendMetric = "dashboard_trend_metric"
    case trendRange = "dashboard_trend_range"
    case investmentCloudMode = "dashboard_investment_cloud_mode"
    case dailyProfitDisplayMode = "dashboard_daily_profit_display_mode"
    case primaryPositionSortField = "dashboard_primary_positions_sort_field"
    case primaryPositionSortDirection = "dashboard_primary_positions_sort_direction"

    func load<Value: RawRepresentable>(from repository: PositionRepository?, default fallback: Value) -> Value
        where Value.RawValue == String {
        guard let storedValue = try? repository?.appSetting(for: rawValue),
              let value = Value(rawValue: storedValue) else { return fallback }
        return value
    }
}
