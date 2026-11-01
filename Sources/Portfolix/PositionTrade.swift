import Foundation

enum PositionTradeSide: String, Codable, CaseIterable, Sendable {
    case add, buy, sell, withdraw

    var reducesBalance: Bool { self == .sell || self == .withdraw }
    var usesCashAccount: Bool { self == .buy || self == .sell }

    func title(language: AppLanguage) -> String {
        switch self {
        case .sell: localizedText("卖出", "Sell", language: language)
        case .withdraw: localizedText("现金转出", "Cash Out", language: language)
        case .add, .buy: localizedText("增持", "Increase", language: language)
        }
    }
}

enum PositionRecordLinks {
    static func activeAccountIDs(trades: [PositionTradeRecord], closures: [PositionClosureRecord],
                                 openings: [PositionOpeningBalanceRecord] = []) -> Set<UUID> {
        var ids = Set(trades.filter { !$0.isReversed }.flatMap(\.accountIDs).compactMap(UUID.init(uuidString:)))
        ids.formUnion(openings.filter(\.isVisible).map(\.id))
        for closure in closures where !closure.isReversed {
            if let holdingID = UUID(uuidString: closure.holding.id) { ids.insert(holdingID) }
            if let cashID = closure.cashPositionID.flatMap(UUID.init(uuidString:)) { ids.insert(cashID) }
        }
        return ids
    }
}

struct PositionTradeRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let sequence: Int
    let side: PositionTradeSide
    let asset: PortfolixDataPackage.Holding
    let cash: PortfolixDataPackage.Holding?
    let tradeDate: String
    let quantity: String
    let executionPrice: String
    let fees: String
    let cashAmount: String
    var allocatedCost: String
    let rateFromCNY: String
    let recordedAt: String
    var reversedAt: String?
    var priceHistory: [PortfolixDataPackage.AssetPriceHistory]

    var isReversed: Bool { reversedAt != nil }
    var currency: DisplayCurrency { DisplayCurrency(rawValue: asset.quoteCurrency) ?? .cny }
    var units: Decimal { PositionClosureMath.decimal(quantity) ?? 0 }
    var price: Decimal { PositionClosureMath.decimal(executionPrice) ?? 0 }
    var fee: Decimal { PositionClosureMath.decimal(fees) ?? 0 }
    var amount: Decimal { PositionClosureMath.decimal(cashAmount) ?? 0 }
    var cost: Decimal { PositionClosureMath.decimal(allocatedCost) ?? 0 }
    var rate: Decimal { PositionClosureMath.decimal(rateFromCNY) ?? 1 }
    var quantityDelta: Decimal { side.reducesBalance ? -units : units }
    var costDelta: Decimal { side.reducesBalance ? -cost : amount }
    var cashDelta: Decimal { side.usesCashAccount ? (side == .buy ? -amount : amount) : 0 }
    var accountIDs: Set<String> { Set([asset.id, cash?.id].compactMap { $0 }) }
    var realizedProfit: Decimal? { side == .sell ? amount - cost : nil }

    func remapping(_ ids: [String: String]) -> Self {
        Self(id: id, sequence: sequence, side: side,
            asset: asset.replacingID(ids[asset.id] ?? asset.id), cash: cash.map { $0.replacingID(ids[$0.id] ?? $0.id) },
            tradeDate: tradeDate, quantity: quantity, executionPrice: executionPrice, fees: fees,
            cashAmount: cashAmount, allocatedCost: allocatedCost, rateFromCNY: rateFromCNY,
            recordedAt: recordedAt, reversedAt: reversedAt, priceHistory: priceHistory.map {
                .init(assetID: ids[$0.assetID] ?? $0.assetID, date: $0.date, name: $0.name, symbol: $0.symbol,
                    category: $0.category, quoteCurrency: $0.quoteCurrency, quantity: $0.quantity,
                    averageCost: $0.averageCost, latestPrice: $0.latestPrice, marketValueCNY: $0.marketValueCNY,
                    source: $0.source, quoteTime: $0.quoteTime, freshness: $0.freshness, updatedAt: $0.updatedAt)
            })
    }

    func validate() throws {
        let position = try asset.position()
        if side == .withdraw {
            guard cash == nil, position.category == .cash, price == 1, fee == 0 else { throw PositionTradeError.invalidInput }
        } else if side == .add {
            guard cash == nil, position.category != .cash || (price == 1 && fee == 0) else { throw PositionTradeError.invalidInput }
        } else {
            guard let cash, asset.id != cash.id, position.category != .cash,
                  try cash.position().category == .cash, asset.quoteCurrency == cash.quoteCurrency else { throw PositionTradeError.invalidInput }
        }
        guard sequence > 0, sequence < Int.max,
              PositionClosureMath.date(tradeDate) != nil,
              let timestamp = ISO8601DateFormatter().date(from: recordedAt),
              tradeDate <= PositionClosureMath.day(timestamp),
              reversedAt == nil || ISO8601DateFormatter().date(from: reversedAt!) != nil,
              let units = PositionClosureMath.decimal(quantity), units > 0,
              let price = PositionClosureMath.decimal(executionPrice), price >= 0,
              let fee = PositionClosureMath.decimal(fees), fee >= 0,
              let amount = PositionClosureMath.decimal(cashAmount), amount >= 0,
              let cost = PositionClosureMath.decimal(allocatedCost), cost >= 0,
              let rate = PositionClosureMath.decimal(rateFromCNY), rate > 0,
              side != .buy || price > 0,
              abs((amount - (position.category == .cash ? units : PositionClosureMath.rounded(units * price, currency: currency) + (side == .sell ? -fee : fee))).doubleValue) < 0.000000001,
              priceHistory.count <= 800,
              Set(priceHistory.map { "\($0.assetID)/\($0.date)" }).count == priceHistory.count,
              priceHistory.allSatisfy({ accountIDs.contains($0.assetID) }) else {
            throw PositionTradeError.invalidInput
        }
        try PortfolixDataPackageService.validate(payload: .init(holdings: [], portfolioSnapshots: [], assetPriceSnapshots: priceHistory))
    }
}

struct PositionTradeDraft {
    let side: PositionTradeSide
    var quantityText: String
    var priceText: String
    var feesText = ""
    var amountText: String
    var usesAmount = false
    let currency: DisplayCurrency

    init(side: PositionTradeSide, position: Position) {
        self.side = side
        currency = position.quoteCurrency
        quantityText = side == .sell ? "0" : ""
        priceText = PositionClosureMath.string(position.latestPrice)
        amountText = side == .sell ? "0" : ""
    }

    mutating func setQuantity(_ text: String) { quantityText = text; synchronize() }
    mutating func setPrice(_ text: String) { priceText = text; usesAmount = false; synchronize() }
    mutating func setFees(_ text: String) { feesText = text; synchronize() }
    mutating func setAmount(_ text: String) { amountText = text; usesAmount = true; synchronize() }

    func values() throws -> (quantity: Decimal, price: Decimal, fees: Decimal, amount: Decimal) {
        guard side != .withdraw else { throw PositionTradeError.invalidInput }
        guard let quantity = PositionClosureMath.decimal(quantityText), quantity > 0,
              let fees = PositionTradeInput.fees(feesText), fees >= 0 else { throw PositionTradeError.invalidInput }
        let price: Decimal
        if usesAmount {
            guard let amount = PositionClosureMath.decimal(amountText), amount >= 0 else { throw PositionTradeError.invalidInput }
            price = (amount + (side == .sell ? fees : -fees)) / quantity
        } else {
            guard let value = PositionClosureMath.decimal(priceText) else { throw PositionTradeError.invalidInput }
            price = value
        }
        let amount = PositionClosureMath.rounded(quantity * price, currency: currency) + (side == .sell ? -fees : fees)
        guard price >= 0, side != .buy || price > 0, amount >= 0, !amount.isNaN,
              abs(amount.doubleValue) <= 1e28 else { throw PositionTradeError.invalidInput }
        return (quantity, price, fees, amount)
    }

    func values(availableQuantity: Decimal) throws -> (quantity: Decimal, price: Decimal, fees: Decimal, amount: Decimal) {
        let values = try values()
        guard side != .sell || values.quantity <= availableQuantity else { throw PositionTradeError.insufficientQuantity }
        return values
    }

    private mutating func synchronize() {
        if side == .sell, PositionClosureMath.decimal(quantityText) == 0 {
            amountText = "0"
            usesAmount = false
            return
        }
        guard let values = try? values() else { return }
        if usesAmount { priceText = PositionClosureMath.string(values.price) }
        else { amountText = PositionClosureMath.string(values.amount) }
    }
}

enum PositionTradeInput {
    static func fees(_ text: String) -> Decimal? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : PositionClosureMath.decimal(text)
    }
}

enum PositionTradeError: LocalizedError {
    case invalidInput, insufficientQuantity, insufficientCash, changed, historicalCorrection, missingHistory, dependentLegacyRecord
    case identityConflict, recordedTradesExist, dependentTrade, invalidCashReduction
    func message(language: AppLanguage) -> String {
        switch self {
        case .invalidInput: localizedText("请核对份额、成本、成交价格和手续费。", "Check the quantity, cost, trade price, and fees.", language: language)
        case .insufficientQuantity: localizedText("可用份额不足，请核对卖出份额。", "Insufficient units. Check the sell quantity.", language: language)
        case .insufficientCash: localizedText("资金账户余额不足，请先核对现金余额。", "Insufficient cash. Reconcile the cash account first.", language: language)
        case .changed: localizedText("持仓已发生变化，请重新打开交易窗口。", "Holdings have changed. Reopen the trade window.", language: language)
        case .historicalCorrection: localizedText("该日期之后有手工持仓修正，无法可靠重算。请先核对修正记录或选择更晚的日期。", "A later manual balance correction prevents reliable replay. Reconcile it or choose a later date.", language: language)
        case .missingHistory: localizedText("缺少该日期的资产或现金记录，无法可靠回填。请选择有记录的日期。", "Asset or cash history is missing for this date. Choose a date with saved records.", language: language)
        case .dependentLegacyRecord: localizedText("该日期之后存在旧版清仓记录，请先撤销相关记录后再回填交易。", "A later legacy closure exists. Reverse it before backdating this trade.", language: language)
        case .identityConflict: localizedText("该资产已有新一轮持仓，请先撤销后续添加记录，再撤销这条记录。", "This asset has a new holding. Reverse its later addition before reversing this record.", language: language)
        case .recordedTradesExist: localizedText("该资产关联操作记录，不能直接删除。请先撤销关联记录。", "This asset is linked to records. Reverse those records before deleting it.", language: language)
        case .dependentTrade: localizedText("关联账户已有后续买卖，请先撤销后续交易。", "A linked account has later transactions. Reverse those transactions first.", language: language)
        case .invalidCashReduction: localizedText("请填写大于 0 的现金减少金额。", "Enter a cash reduction greater than zero.", language: language)
        }
    }
    var errorDescription: String? { message(language: .chinese) }
}

enum PositionTransactionKind: String {
    case opening, add, buy, sell, withdraw

    init(_ side: PositionTradeSide) {
        switch side { case .add: self = .add; case .buy: self = .buy; case .sell: self = .sell; case .withdraw: self = .withdraw }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .opening: localizedText("期初持仓", "Opening", language: language)
        case .add, .buy: localizedText("增持", "Increase", language: language)
        case .sell: localizedText("卖出", "Sell", language: language)
        case .withdraw: localizedText("现金转出", "Cash Out", language: language)
        }
    }

    var hasCashFlow: Bool { self == .buy || self == .sell || self == .withdraw }
}

struct PositionTransactionRow: Identifiable {
    let id: UUID
    let sequence: Int
    let name: String
    let symbol: String
    let tradeDate: String
    let kind: PositionTransactionKind
    let quantity: String
    let price: Decimal
    let fee: Decimal
    let amount: Decimal
    let profit: Decimal?
    let currency: DisplayCurrency
    let trade: PositionTradeRecord?
    let closure: PositionClosureRecord?
    let opening: PositionOpeningBalanceRecord?
    let recordedAt: Date?
    let rateFromCNY: Decimal
    var displayNumber = 0

    init(_ record: PositionTradeRecord) {
        id = record.id; sequence = record.sequence; name = record.asset.name; symbol = record.asset.symbol
        tradeDate = record.tradeDate; kind = PositionTransactionKind(record.side); quantity = record.quantity
        price = record.price; fee = record.fee; amount = record.amount; profit = record.realizedProfit
        currency = record.currency; trade = record; closure = nil; opening = nil
        recordedAt = Self.recordedDate(record.recordedAt)
        rateFromCNY = record.rate
    }
    init(_ record: PositionClosureRecord) {
        id = record.id; sequence = 0; name = record.holding.name; symbol = record.holding.symbol
        tradeDate = record.tradeDate; kind = .sell; quantity = record.holding.quantity
        price = PositionClosureMath.decimal(record.executionPrice) ?? 0; fee = record.feeAmount
        amount = record.netAmount; profit = record.realizedProfit
        currency = record.currency; trade = nil; closure = record; opening = nil
        recordedAt = Self.recordedDate(record.recordedAt)
        rateFromCNY = record.conversionRate
    }

    init(_ record: PositionOpeningBalanceRecord) {
        id = record.id; sequence = 0; name = record.holding.name; symbol = record.holding.symbol
        recordedAt = Self.recordedDate(record.recordedAt)
        tradeDate = recordedAt.map(PositionClosureMath.day) ?? ""
        kind = .opening; quantity = record.quantity ?? "—"
        amount = record.cost ?? 0; price = (record.units ?? 0) > 0 ? amount / record.units! : 0
        fee = 0; profit = nil; currency = record.currency
        trade = nil; closure = nil; opening = record; rateFromCNY = record.currency.rateFromCNY
    }

    var needsOpeningReview: Bool { opening?.requiresReview == true }
    var assetID: String { trade?.asset.id ?? closure?.holding.id ?? opening!.holding.id }

    func profit(in displayCurrency: DisplayCurrency) -> Decimal? {
        profit.map { $0 / rateFromCNY * displayCurrency.rateFromCNY }
    }

    func canReverse(asOf date: Date = .now) -> Bool {
        if let opening { return !opening.isReversed && !opening.requiresReview && (opening.units ?? 0) > 0 }
        if let trade { return !trade.isReversed }
        guard let closure, !closure.isReversed, let recordedAt else { return false }
        return Calendar.current.isDate(recordedAt, inSameDayAs: date)
    }

    static func listed(trades: [PositionTradeRecord], closures: [PositionClosureRecord],
                       openings: [PositionOpeningBalanceRecord] = [], query: String = "") -> [Self] {
        let rows = (trades.filter { !$0.isReversed }.map(Self.init) + closures.filter { !$0.isReversed }.map(Self.init)
            + openings.filter(\.isVisible).map(Self.init))
            .sorted {
                if $0.recordedAt != $1.recordedAt { return ($0.recordedAt ?? .distantPast) < ($1.recordedAt ?? .distantPast) }
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                return $0.id.uuidString < $1.id.uuidString
            }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.enumerated().reversed().compactMap { index, value in
            guard query.isEmpty || value.name.localizedCaseInsensitiveContains(query) || value.symbol.localizedCaseInsensitiveContains(query) else { return nil }
            var row = value
            row.displayNumber = index + 1
            return row
        }
    }

    @MainActor var recordedDateText: String { recordedAt.map(Self.dayFormatter.string(from:)) ?? tradeDate }
    @MainActor var recordedClockText: String { recordedAt.map(Self.clockFormatter.string(from:)) ?? "—" }
    @MainActor var recordedTimeText: String { "\(recordedDateText) \(recordedClockText)" }

    private static func recordedDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }

    @MainActor private static let dayFormatter = formatter("yyyy-MM-dd")
    @MainActor private static let clockFormatter = formatter("HH:mm:ss")
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}

// Replaying from the balances before the affected trades keeps average cost and cash in one calculation.
enum PositionTradeReplay {
    struct Balance { var quantity: Decimal; var cost: Decimal }
    static func apply(_ trade: inout PositionTradeRecord, to balances: inout [String: Balance]) throws {
        var asset = balances[trade.asset.id] ?? Balance(quantity: 0, cost: 0)
        var cash = trade.cash.flatMap { balances[$0.id] } ?? Balance(quantity: 0, cost: 0)
        if !trade.side.reducesBalance {
            guard trade.side != .buy || cash.quantity >= trade.amount else { throw PositionTradeError.insufficientCash }
            asset.quantity += trade.units
            asset.cost += trade.amount
            trade.allocatedCost = "0"
        } else {
            guard asset.quantity >= trade.units else {
                throw trade.side == .withdraw ? PositionTradeError.insufficientCash : PositionTradeError.insufficientQuantity
            }
            let cost = asset.quantity == trade.units ? asset.cost : asset.cost * trade.units / asset.quantity
            trade.allocatedCost = PositionClosureMath.string(cost)
            asset.quantity -= trade.units
            asset.cost -= cost
        }
        cash.quantity += trade.cashDelta
        cash.cost = cash.quantity
        guard !asset.quantity.isNaN, !asset.cost.isNaN, !cash.quantity.isNaN,
              asset.cost >= 0, abs(asset.quantity.doubleValue) <= 1e28,
              abs(asset.cost.doubleValue) <= 1e28, abs(cash.quantity.doubleValue) <= 1e28 else { throw PositionTradeError.invalidInput }
        balances[trade.asset.id] = asset
        if let account = trade.cash { balances[account.id] = cash }
    }
}
