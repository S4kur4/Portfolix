import Foundation

public struct RecordedTradeProfit: Decodable, Sendable {
    public struct Account: Decodable, Sendable { public let id: String }
    public struct ArchivedPrice: Decodable, Sendable {
        public let assetID: String
        public let date: String
        public let quantity: String
        public let marketValueCNY: String

        public init(assetID: String, date: String, quantity: String, marketValueCNY: String) {
            self.assetID = assetID; self.date = date; self.quantity = quantity; self.marketValueCNY = marketValueCNY
        }
    }
    public let asset: Account
    public let cash: Account?
    public let side: String
    public let tradeDate: String
    public let quantity: String
    public let executionPrice: String
    public let fees: String
    public let cashAmount: String
    public let rateFromCNY: String
    public let reversedAt: String?
    public let priceHistory: [ArchivedPrice]?

    public init(assetID: String, cashID: String?, side: String, tradeDate: String, quantity: String,
                executionPrice: String, fees: String, cashAmount: String, rateFromCNY: String,
                priceHistory: [ArchivedPrice]? = nil) {
        asset = Account(id: assetID); cash = cashID.map { Account(id: $0) }; self.side = side; self.tradeDate = tradeDate
        self.quantity = quantity; self.executionPrice = executionPrice; self.fees = fees
        self.cashAmount = cashAmount; self.rateFromCNY = rateFromCNY; reversedAt = nil
        self.priceHistory = priceHistory
    }

    // Both the App and MCP use this adjustment; neither credits a sale as daily investment profit.
    public static func adjustments(trades: [Self], unitValues: [String: [String: Decimal]], through end: String) -> [String: [String: Decimal]] {
        var result: [String: [String: Decimal]] = [:]
        var unitValues = unitValues
        // Fully sold assets leave the active snapshot table, but their archived prices still anchor same-day trades.
        for trade in trades where trade.reversedAt == nil {
            for snapshot in trade.priceHistory ?? [] where snapshot.date <= end && unitValues[snapshot.assetID]?[snapshot.date] == nil {
                guard let quantity = Decimal(string: snapshot.quantity), quantity > 0,
                      let value = Decimal(string: snapshot.marketValueCNY), value >= 0 else { continue }
                unitValues[snapshot.assetID, default: [:]][snapshot.date] = value / quantity
            }
        }
        let sortedDays = unitValues.mapValues { $0.keys.sorted() }
        for trade in trades where trade.reversedAt == nil && trade.tradeDate <= end {
            guard ["add", "buy", "sell", "withdraw"].contains(trade.side),
                  let quantity = Decimal(string: trade.quantity), quantity > 0,
                  let price = Decimal(string: trade.executionPrice), price >= 0,
                  let fees = Decimal(string: trade.fees), fees >= 0,
                  let amount = Decimal(string: trade.cashAmount), amount >= 0,
                  let rate = Decimal(string: trade.rateFromCNY), rate > 0 else { continue }
            let isBuy = trade.side != "sell" && trade.side != "withdraw"
            let previous = sortedDays[trade.asset.id]?.last { $0 < trade.tradeDate }.flatMap { unitValues[trade.asset.id]?[$0] }
            let closing = unitValues[trade.asset.id]?[trade.tradeDate]
            let baseline = previous ?? closing
            let change = baseline.map { (isBuy ? quantity : -quantity) * ($0 - price / rate) } ?? 0
            // Reversing decimal unit conversions may leave dust far below any displayed currency precision.
            let normalizedChange: Decimal = abs(NSDecimalNumber(decimal: change).doubleValue) < 1e-18 ? 0 : change
            result[trade.tradeDate, default: [:]][trade.asset.id, default: 0] += normalizedChange - fees / rate
            if let cash = trade.cash, let priorDay = sortedDays[cash.id]?.last(where: { $0 < trade.tradeDate }),
               let prior = unitValues[cash.id]?[priorDay] {
                result[trade.tradeDate, default: [:]][cash.id, default: 0] += (isBuy ? -amount : amount) * (prior - 1 / rate)
            }
        }
        return result
    }
}
