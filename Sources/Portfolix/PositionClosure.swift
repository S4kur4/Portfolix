import Foundation

struct PositionClosureHistoryAdjustment: Codable, Equatable, Sendable {
    let date: String
    let valueDeltaCNY: String
    let costDeltaCNY: String
    let cashUnitValueCNY: String
    let createdCashSnapshot: Bool
    let adjustedPortfolioSnapshot: Bool
}

struct PositionClosureRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let holding: PortfolixDataPackage.Holding
    let tradeDate: String
    let executionPrice: String
    let fees: String
    let netProceeds: String
    let rateFromCNY: String
    let cashPositionID: String?
    let cashName: String
    let createdCashPosition: Bool
    let dailyProfitCNY: String?
    let originalSnapshots: [PortfolixDataPackage.AssetPriceHistory]
    let historyAdjustments: [PositionClosureHistoryAdjustment]
    let recordedAt: String
    var reversedAt: String? = nil

    var isReversed: Bool { reversedAt != nil }
    var currency: DisplayCurrency { DisplayCurrency(rawValue: holding.quoteCurrency) ?? .cny }
    var quantity: Decimal { PositionClosureMath.decimal(holding.quantity) ?? 0 }
    var netAmount: Decimal { PositionClosureMath.decimal(netProceeds) ?? 0 }
    var feeAmount: Decimal { PositionClosureMath.decimal(fees) ?? 0 }
    var conversionRate: Decimal { PositionClosureMath.decimal(rateFromCNY) ?? 1 }
    var realizedProfit: Decimal { netAmount - (PositionClosureMath.decimal(holding.totalCost) ?? 0) }
    var realizedProfitCNY: Decimal { realizedProfit / conversionRate }
    var realizedProfitRate: Decimal {
        let cost = PositionClosureMath.decimal(holding.totalCost) ?? 0
        return cost > 0 ? realizedProfit / cost * 100 : 0
    }

    func remapping(positionID: String, cashPositionID: String?) -> Self {
        Self(id: id, holding: holding.replacingID(positionID), tradeDate: tradeDate, executionPrice: executionPrice,
            fees: fees, netProceeds: netProceeds, rateFromCNY: rateFromCNY, cashPositionID: cashPositionID,
            cashName: cashName, createdCashPosition: createdCashPosition, dailyProfitCNY: dailyProfitCNY,
            originalSnapshots: originalSnapshots.map {
                .init(assetID: positionID, date: $0.date, name: $0.name, symbol: $0.symbol, category: $0.category,
                    quoteCurrency: $0.quoteCurrency, quantity: $0.quantity, averageCost: $0.averageCost,
                    latestPrice: $0.latestPrice, marketValueCNY: $0.marketValueCNY, source: $0.source,
                    quoteTime: $0.quoteTime, freshness: $0.freshness, updatedAt: $0.updatedAt)
            }, historyAdjustments: historyAdjustments, recordedAt: recordedAt, reversedAt: reversedAt)
    }
}

struct PositionClosureSettlement: Equatable {
    let executionPrice: Decimal
    let fees: Decimal
    let netProceeds: Decimal
    var grossProceeds: Decimal { netProceeds + fees }
}

struct PositionClosureDraft {
    enum AmountBasis { case price, proceeds }
    let position: Position
    var priceText: String
    var feesText = "0"
    var proceedsText: String
    private(set) var basis = AmountBasis.price

    init(position: Position) {
        self.position = position
        priceText = PositionClosureMath.string(position.latestPrice)
        proceedsText = PositionClosureMath.string(PositionClosureMath.rounded(
            position.quantity * position.latestPrice, currency: position.quoteCurrency))
    }

    mutating func setPrice(_ value: String) {
        priceText = value
        basis = .price
        synchronize()
    }

    mutating func setProceeds(_ value: String) {
        proceedsText = value
        basis = .proceeds
        synchronize()
    }

    mutating func setFees(_ value: String) {
        feesText = value
        synchronize()
    }

    func settlement() throws -> PositionClosureSettlement {
        guard position.category != .cash, position.quantity > 0,
              let fees = PositionClosureMath.decimal(feesText), fees >= 0 else {
            throw PositionClosureError.invalidAmount
        }
        let price: Decimal
        let proceeds: Decimal
        switch basis {
        case .price:
            guard let parsed = PositionClosureMath.decimal(priceText), parsed >= 0 else {
                throw PositionClosureError.invalidAmount
            }
            price = parsed
            proceeds = PositionClosureMath.rounded(position.quantity * price, currency: position.quoteCurrency) - fees
        case .proceeds:
            guard let parsed = PositionClosureMath.decimal(proceedsText), parsed >= 0 else {
                throw PositionClosureError.invalidAmount
            }
            proceeds = parsed
            price = (proceeds + fees) / position.quantity
        }
        guard !price.isNaN, !proceeds.isNaN, proceeds >= 0,
              (proceeds + fees).doubleValue.isFinite else { throw PositionClosureError.invalidAmount }
        return PositionClosureSettlement(executionPrice: price, fees: fees, netProceeds: proceeds)
    }

    private mutating func synchronize() {
        guard let settlement = try? settlement() else { return }
        if basis == .price { proceedsText = PositionClosureMath.string(settlement.netProceeds) }
        else { priceText = PositionClosureMath.string(settlement.executionPrice) }
    }
}

enum PositionClosureError: LocalizedError {
    case invalidAmount, invalidDate, holdingChanged, invalidCash, insufficientCash, historicalQuantityChange
    case activeHoldingExists, invalidRecord, reversalExpired

    func message(language: AppLanguage) -> String {
        switch self {
        case .invalidAmount:
            localizedText("请填写有效的成交价、手续费和到账金额，手续费不能超过成交金额。", "Enter valid price, fees and proceeds. Fees cannot exceed the sale amount.", language: language)
        case .invalidDate:
            localizedText("成交日期不能晚于今天。", "The trade date cannot be in the future.", language: language)
        case .holdingChanged:
            localizedText("持仓已发生变化，请重新打开清仓窗口。", "The holding has changed. Reopen the close-position window.", language: language)
        case .invalidCash:
            localizedText("请选择相同币种的现金持仓，或新建现金持仓。", "Choose a cash holding in the same currency, or create one.", language: language)
        case .insufficientCash:
            localizedText("现金余额不足，无法撤销这笔清仓。请先核对后续资金变动。", "The cash balance is insufficient to reverse this closure. Review subsequent cash movements first.", language: language)
        case .historicalQuantityChange:
            localizedText("该日期之后持仓份额曾变化，无法直接回填全部清仓。请选择最近一次份额变更之后的日期。", "Quantity changed after this date. Choose a date after the last quantity change.", language: language)
        case .activeHoldingExists:
            localizedText("该资产已有新的持仓，暂不能撤销旧清仓。", "This asset has a new holding. Its earlier closure cannot be reversed.", language: language)
        case .invalidRecord:
            localizedText("清仓记录无效或与当前记录冲突。", "The closure record is invalid or conflicts with existing records.", language: language)
        case .reversalExpired:
            localizedText("只能撤销今天录入的清仓记录。", "Only closures recorded today can be reversed.", language: language)
        }
    }

    var errorDescription: String? { message(language: .chinese) }
}

enum PositionClosureMath {
    static func decimal(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
        guard value.count <= 80,
              value.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
              let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN, abs(number.doubleValue) <= 1e28 else { return nil }
        return number
    }

    static func string(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }

    static func rounded(_ value: Decimal, currency: DisplayCurrency) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, currency == .usdt ? 8 : 2, .bankers)
        return result
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func date(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard day.count == 10, let date = formatter.date(from: day), formatter.string(from: date) == day else { return nil }
        return date
    }

    static func cashName(_ currency: DisplayCurrency, language: AppLanguage) -> String {
        localizedText("现金 \(currency.rawValue)", "Cash \(currency.rawValue)", language: language)
    }

    static func cashPosition(id: UUID = UUID(), currency: DisplayCurrency, quantity: Decimal, name: String, symbol: String? = nil) -> Position {
        Position(id: id, name: name, symbol: symbol ?? currency.rawValue, category: .cash,
            quoteCurrency: currency, quantity: quantity, totalCost: quantity, averageCost: 1,
            latestPrice: 1, marketValueCNY: quantity / currency.rateFromCNY, profitRate: 0,
            weeklyTrend: [], source: "手工价格", quoteTime: ISO8601DateFormatter().string(from: .now), freshness: .manual)
    }
}

extension PortfolixDataPackage.Holding {
    func replacingID(_ value: String) -> Self {
        Self(id: value, name: name, symbol: symbol, category: category, quoteCurrency: quoteCurrency,
            quantity: quantity, totalCost: totalCost, averageCost: averageCost, latestPrice: latestPrice,
            marketValueCNY: marketValueCNY, profitRate: profitRate, source: source, quoteTime: quoteTime,
            fetchedAt: fetchedAt, freshness: freshness, weeklyTrend: weeklyTrend, createdAt: createdAt, updatedAt: updatedAt)
    }
    init(position: Position, timestamp: String) {
        self.init(id: position.id.uuidString, name: position.name, symbol: position.symbol,
            category: position.category.rawValue, quoteCurrency: position.quoteCurrency.rawValue,
            quantity: PositionClosureMath.string(position.quantity), totalCost: PositionClosureMath.string(position.totalCost),
            averageCost: PositionClosureMath.string(position.averageCost), latestPrice: PositionClosureMath.string(position.latestPrice),
            marketValueCNY: PositionClosureMath.string(position.marketValueCNY), profitRate: PositionClosureMath.string(position.profitRate),
            source: position.source, quoteTime: position.quoteTime, fetchedAt: position.fetchedAt,
            freshness: position.freshness.rawValue, weeklyTrend: position.weeklyTrend, createdAt: timestamp, updatedAt: timestamp)
    }

    func position() throws -> Position {
        guard let id = UUID(uuidString: id), let category = AssetCategory(rawValue: category),
              let currency = DisplayCurrency(rawValue: quoteCurrency),
              let quantity = PositionClosureMath.decimal(quantity), let cost = PositionClosureMath.decimal(totalCost),
              let average = PositionClosureMath.decimal(averageCost), let latest = PositionClosureMath.decimal(latestPrice),
              let freshness = Freshness(rawValue: freshness) else { throw PositionClosureError.invalidRecord }
        let result = Position(id: id, name: name, symbol: symbol, category: category, quoteCurrency: currency,
            quantity: quantity, totalCost: cost, averageCost: average, latestPrice: latest,
            marketValueCNY: quantity * latest / currency.rateFromCNY,
            profitRate: average == 0 ? 0 : (latest - average) / average * 100,
            weeklyTrend: weeklyTrend, source: source, quoteTime: quoteTime, fetchedAt: fetchedAt, freshness: freshness)
        try PositionInputValidator.validate(result)
        return result
    }
}

enum PositionClosureValidation {
    static func validate(_ record: PositionClosureRecord) throws {
        let holding = try record.holding.position()
        guard holding.category != .cash, let tradeDate = PositionClosureMath.date(record.tradeDate),
              let recordedAt = ISO8601DateFormatter().date(from: record.recordedAt),
              PositionClosureMath.day(tradeDate) <= PositionClosureMath.day(recordedAt),
              let price = PositionClosureMath.decimal(record.executionPrice), price >= 0,
              let fees = PositionClosureMath.decimal(record.fees), fees >= 0,
              let net = PositionClosureMath.decimal(record.netProceeds), net >= 0,
              let rate = PositionClosureMath.decimal(record.rateFromCNY), rate > 0,
              record.cashName.count <= 256,
              record.originalSnapshots.count <= 367, record.historyAdjustments.count <= 1_000,
              abs((holding.quantity * price - net - fees).doubleValue) <= (record.currency == .usdt ? 0.00000001 : 0.01),
              record.dailyProfitCNY == nil || PositionClosureMath.decimal(record.dailyProfitCNY!) != nil,
              record.reversedAt == nil || ISO8601DateFormatter().date(from: record.reversedAt!) != nil else {
            throw PositionClosureError.invalidRecord
        }
        if let cashID = record.cashPositionID {
            guard UUID(uuidString: cashID) != nil, cashID != record.holding.id else { throw PositionClosureError.invalidRecord }
        } else if net > 0 { throw PositionClosureError.invalidRecord }
        guard Set(record.originalSnapshots.map(\.date)).count == record.originalSnapshots.count,
              Set(record.historyAdjustments.map(\.date)).count == record.historyAdjustments.count else { throw PositionClosureError.invalidRecord }
        for snapshot in record.originalSnapshots {
            guard snapshot.assetID == record.holding.id, snapshot.date >= record.tradeDate else { throw PositionClosureError.invalidRecord }
        }
        for adjustment in record.historyAdjustments {
            guard PositionClosureMath.date(adjustment.date) != nil, adjustment.date >= record.tradeDate,
                  adjustment.date <= PositionClosureMath.day(recordedAt),
                  PositionClosureMath.decimal(adjustment.valueDeltaCNY) != nil,
                  PositionClosureMath.decimal(adjustment.costDeltaCNY) != nil,
                  let unit = PositionClosureMath.decimal(adjustment.cashUnitValueCNY), unit > 0 else { throw PositionClosureError.invalidRecord }
            let valueDelta = PositionClosureMath.decimal(adjustment.valueDeltaCNY) ?? 0
            let costDelta = PositionClosureMath.decimal(adjustment.costDeltaCNY) ?? 0
            if adjustment.adjustedPortfolioSnapshot {
                guard let source = record.originalSnapshots.first(where: { $0.date == adjustment.date }),
                      let quantity = PositionClosureMath.decimal(source.quantity), quantity > 0,
                      let value = PositionClosureMath.decimal(source.marketValueCNY),
                      let price = PositionClosureMath.decimal(source.latestPrice),
                      let average = PositionClosureMath.decimal(source.averageCost) else { throw PositionClosureError.invalidRecord }
                let sourceRate = price > 0 ? value / quantity / price : 1 / rate
                guard abs((valueDelta - (net * unit - value)).doubleValue) < 0.00000001,
                      abs((costDelta - (net * unit - quantity * average * sourceRate)).doubleValue) < 0.00000001 else {
                    throw PositionClosureError.invalidRecord
                }
            } else if valueDelta != 0 || costDelta != 0 { throw PositionClosureError.invalidRecord }
        }
        try PortfolixDataPackageService.validate(payload: .init(holdings: [record.holding], portfolioSnapshots: [],
            assetPriceSnapshots: record.originalSnapshots))
    }
}
