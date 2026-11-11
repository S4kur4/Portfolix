import Foundation

enum StarterPortfolio {
    static let stateKey = "starter_portfolio_v1.state"
    static let positionIDsKey = "starter_portfolio_v1.position_ids"

    static func positions(language: AppLanguage, now: Date) -> [Position] {
        let examples: [(String, String, AssetCategory, DisplayCurrency, Decimal, Decimal)] = [
            ("Apple", "AAPL", .usStock, .usd, 10, 200),
            ("NVIDIA", "NVDA", .usStock, .usd, 10, 100),
            ("BTC", "BTC/USDT", .crypto, .usdt, Decimal(string: "0.01")!, 60_000),
        ]
        let timestamp = ISO8601DateFormatter().string(from: now)
        return examples.map { name, symbol, category, currency, quantity, price in
            Position(
                name: language == .english ? "\(name) (Sample)" : "\(name)（示例）",
                symbol: symbol, category: category, quoteCurrency: currency,
                quantity: quantity, averageCost: price, latestPrice: price,
                marketValueCNY: quantity * price / currency.rateFromCNY,
                profitRate: 0, weeklyTrend: [price.doubleValue],
                source: language == .english ? "Sample price" : "示例价格",
                quoteTime: timestamp, fetchedAt: timestamp, freshness: .manual
            )
        }
    }
}
