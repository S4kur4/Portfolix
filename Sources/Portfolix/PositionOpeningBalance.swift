import Foundation

struct PositionOpeningBalanceRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let holding: PortfolixDataPackage.Holding
    let quantity: String?
    let totalCost: String?
    let requiresReview: Bool
    let recordedAt: String
    var reversedAt: String?

    var isReversed: Bool { reversedAt != nil }
    var units: Decimal? { quantity.flatMap(PositionClosureMath.decimal) }
    var cost: Decimal? { totalCost.flatMap(PositionClosureMath.decimal) }
    var isVisible: Bool { !isReversed && (requiresReview || (units ?? 0) > 0) }
    var currency: DisplayCurrency { DisplayCurrency(rawValue: holding.quoteCurrency) ?? .cny }

    func remapping(_ ids: [String: String]) throws -> Self {
        let target = ids[holding.id] ?? holding.id
        guard let id = UUID(uuidString: target) else { throw PositionOpeningBalanceError.invalidInput }
        return Self(id: id, holding: holding.replacingID(id.uuidString), quantity: quantity, totalCost: totalCost,
            requiresReview: requiresReview, recordedAt: recordedAt, reversedAt: reversedAt)
    }

    func validate() throws {
        guard id == UUID(uuidString: holding.id), ISO8601DateFormatter().date(from: recordedAt) != nil,
              reversedAt == nil || ISO8601DateFormatter().date(from: reversedAt!) != nil else {
            throw PositionOpeningBalanceError.invalidInput
        }
        _ = try holding.position()
        if let units, let cost {
            guard units >= 0, cost >= 0, units > 0 || cost == 0 else { throw PositionOpeningBalanceError.invalidInput }
        } else if !requiresReview || quantity != nil || totalCost != nil {
            throw PositionOpeningBalanceError.invalidInput
        }
    }
}

enum PositionOpeningBalanceError: LocalizedError {
    case invalidInput, needsReview, dependentRecords, changed

    func message(language: AppLanguage) -> String {
        switch self {
        case .invalidInput:
            localizedText("请核对期初份额和总成本。", "Check the opening quantity and total cost.", language: language)
        case .needsReview:
            localizedText("期初余额无法可靠还原，请先核对期初持仓；当前余额未作修改。", "The opening balance needs review. Current balances have not been changed.", language: language)
        case .dependentRecords:
            localizedText("请先撤销该资产或现金账户关联的后续记录。", "Reverse the later records linked to this asset or cash account first.", language: language)
        case .changed:
            localizedText("当前余额与期初记录不一致，请先核对持仓。", "The current balance differs from the opening record. Review the holding first.", language: language)
        }
    }

    var errorDescription: String? { message(language: .chinese) }
}

enum PositionOpeningBalanceMath {
    // Opening balances explain existing holdings; they are never replayed as purchases or cash flows.
    static func reconstruct(positions: [Position], trades: [PositionTradeRecord], closures: [PositionClosureRecord],
                            recordedAt: String) throws -> [PositionOpeningBalanceRecord] {
        var templates: [UUID: PortfolixDataPackage.Holding] = [:]
        for record in trades {
            templates[try identity(record.asset.id)] = record.asset
            if let cash = record.cash { templates[try identity(cash.id)] = cash }
        }
        for record in closures {
            templates[try identity(record.holding.id)] = record.holding
            if let cashID = record.cashPositionID {
                let id = try identity(cashID)
                if templates[id] == nil {
                    templates[id] = .init(position: PositionClosureMath.cashPosition(id: id, currency: record.currency,
                        quantity: 1, name: record.cashName), timestamp: recordedAt)
                }
            }
        }
        for position in positions { templates[position.id] = .init(position: position, timestamp: recordedAt) }
        let activeTrades = trades.filter { !$0.isReversed }
        let activeClosures = closures.filter { !$0.isReversed }
        var balances = Dictionary(uniqueKeysWithValues: positions.map {
            ($0.id, PositionTradeReplay.Balance(quantity: $0.quantity, cost: $0.totalCost))
        })
        for record in activeTrades {
            let id = try identity(record.asset.id)
            balances[id, default: .init(quantity: 0, cost: 0)].quantity -= record.quantityDelta
            balances[id, default: .init(quantity: 0, cost: 0)].cost -= record.costDelta
            if let cash = record.cash {
                let cashID = try identity(cash.id)
                balances[cashID, default: .init(quantity: 0, cost: 0)].quantity -= record.cashDelta
                balances[cashID, default: .init(quantity: 0, cost: 0)].cost -= record.cashDelta
            }
        }
        for record in activeClosures {
            let id = try identity(record.holding.id)
            balances[id, default: .init(quantity: 0, cost: 0)].quantity += record.quantity
            balances[id, default: .init(quantity: 0, cost: 0)].cost += PositionClosureMath.decimal(record.holding.totalCost) ?? 0
            if let cashID = record.cashPositionID {
                let id = try identity(cashID)
                balances[id, default: .init(quantity: 0, cost: 0)].quantity -= record.netAmount
                balances[id, default: .init(quantity: 0, cost: 0)].cost -= record.netAmount
            }
        }

        var invalid = Set<UUID>()
        for id in templates.keys {
            var balance = balances[id] ?? .init(quantity: 0, cost: 0)
            if balance.quantity == 0 && abs(balance.cost.doubleValue) < 1e-12 { balance.cost = 0 }
            if !isUsable(balance) { invalid.insert(id) }
            balances[id] = balance
        }

        // Check that the inferred base reproduces recorded allocations, not just the final share count.
        var replay = Dictionary(uniqueKeysWithValues: balances.map { ($0.key.uuidString, $0.value) })
        let events: [(day: String, timestamp: String, sequence: Int, trade: PositionTradeRecord?, closure: PositionClosureRecord?)] =
            activeTrades.map { ($0.tradeDate, $0.recordedAt, $0.sequence, $0, nil) }
            + activeClosures.map { ($0.tradeDate, $0.recordedAt, 0, nil, $0) }
        // Trade templates describe balances at entry time, even for a backdated trade.
        var seenAccounts = Set<UUID>()
        for event in events.sorted(by: { $0.timestamp == $1.timestamp ? $0.sequence < $1.sequence : $0.timestamp < $1.timestamp }) {
            if let record = event.trade {
                for snapshot in [record.asset, record.cash].compactMap({ $0 }) {
                    let id = try identity(snapshot.id)
                    if seenAccounts.insert(id).inserted, let balance = balances[id], balance.quantity > 0 {
                        if PositionClosureMath.decimal(snapshot.quantity) != balance.quantity
                            || PositionClosureMath.decimal(snapshot.totalCost).map({ abs(($0 - balance.cost).doubleValue) > 0.000001 }) != false {
                            invalid.insert(id)
                        }
                    }
                }
            } else if let record = event.closure {
                seenAccounts.insert(try identity(record.holding.id))
                if let cash = record.cashPositionID {
                    let id = try identity(cash)
                    if seenAccounts.insert(id).inserted, record.createdCashPosition,
                       (balances[id]?.quantity ?? 0) != 0 { invalid.insert(id) }
                }
            }
        }
        for event in events.sorted(by: {
            if $0.day != $1.day { return $0.day < $1.day }
            if $0.trade != nil && $1.trade != nil { return $0.sequence < $1.sequence }
            return $0.timestamp < $1.timestamp
        }) {
            if let record = event.trade {
                let ids = try Set(record.accountIDs.map(identity))
                var normalized = try record.remapping(Dictionary(uniqueKeysWithValues: record.accountIDs.map { ($0, try identity($0).uuidString) }))
                var trial = replay
                if (try? PositionTradeReplay.apply(&normalized, to: &trial)) == nil
                    || abs((normalized.cost - record.cost).doubleValue) > 0.000001 {
                    invalid.formUnion(ids)
                }
                let id = try identity(record.asset.id).uuidString
                replay[id, default: .init(quantity: 0, cost: 0)].quantity += record.quantityDelta
                replay[id, default: .init(quantity: 0, cost: 0)].cost += record.costDelta
                if let cash = record.cash {
                    let cashID = try identity(cash.id).uuidString
                    replay[cashID, default: .init(quantity: 0, cost: 0)].quantity += record.cashDelta
                    replay[cashID, default: .init(quantity: 0, cost: 0)].cost += record.cashDelta
                }
            } else if let record = event.closure {
                let id = try identity(record.holding.id)
                let balance = replay[id.uuidString] ?? .init(quantity: 0, cost: 0)
                let cost = PositionClosureMath.decimal(record.holding.totalCost) ?? 0
                if balance.quantity != record.quantity || abs((balance.cost - cost).doubleValue) > 0.000001 { invalid.insert(id) }
                replay[id.uuidString] = .init(quantity: 0, cost: 0)
                if let cash = record.cashPositionID {
                    let cashUUID = try identity(cash)
                    let cashID = cashUUID.uuidString
                    replay[cashID, default: .init(quantity: 0, cost: 0)].quantity += record.netAmount
                    replay[cashID, default: .init(quantity: 0, cost: 0)].cost += record.netAmount
                }
            }
        }

        return try templates.map { id, holding in
            let balance = balances[id] ?? .init(quantity: 0, cost: 0)
            let usable = isUsable(balance)
            let record = PositionOpeningBalanceRecord(id: id, holding: holding.replacingID(id.uuidString),
                quantity: usable ? PositionClosureMath.string(balance.quantity) : nil,
                totalCost: usable ? PositionClosureMath.string(balance.cost) : nil,
                requiresReview: invalid.contains(id), recordedAt: recordedAt)
            try record.validate()
            return record
        }
    }

    private static func identity(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else { throw PositionOpeningBalanceError.invalidInput }
        return id
    }

    private static func isUsable(_ balance: PositionTradeReplay.Balance) -> Bool {
        !balance.quantity.isNaN && !balance.cost.isNaN && balance.quantity >= 0 && balance.cost >= 0
            && (balance.quantity > 0 || balance.cost == 0)
            && balance.quantity.doubleValue <= 1e28 && balance.cost.doubleValue <= 1e28
    }
}
