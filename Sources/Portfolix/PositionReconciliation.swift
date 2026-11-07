import Foundation

/// An absolute balance checkpoint. It never represents a purchase, sale, or income.
struct PositionReconciliationRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let sequence: Int
    let asset: PortfolixDataPackage.Holding
    let quantity: String
    let totalCost: String
    let costKnown: Bool
    let effectiveAt: String
    let effectiveDay: String
    let quoteUnitCNY: String
    let baselineUnitCNY: String?
    let profitAdjustmentCNY: String?
    let reason: String
    let note: String
    var reversedAt: String?
    var reversalDay: String? = nil
    var reversalProfitAdjustmentCNY: String? = nil

    var isReversed: Bool { reversedAt != nil }
    var units: Decimal { PositionClosureMath.decimal(quantity) ?? 0 }
    var cost: Decimal { PositionClosureMath.decimal(totalCost) ?? 0 }
    var beforeUnits: Decimal { PositionClosureMath.decimal(asset.quantity) ?? 0 }

    func remapping(_ ids: [String: String]) -> Self {
        Self(id: id, sequence: sequence, asset: asset.replacingID(ids[asset.id] ?? asset.id),
             quantity: quantity, totalCost: totalCost, costKnown: costKnown, effectiveAt: effectiveAt,
             effectiveDay: effectiveDay, quoteUnitCNY: quoteUnitCNY, baselineUnitCNY: baselineUnitCNY,
             profitAdjustmentCNY: profitAdjustmentCNY, reason: reason, note: note, reversedAt: reversedAt, reversalDay: reversalDay, reversalProfitAdjustmentCNY: reversalProfitAdjustmentCNY)
    }

    func validate() throws {
        let position = try asset.position()
        guard sequence > 0, sequence < Int.max,
              let time = ISO8601DateFormatter().date(from: effectiveAt), effectiveDay == PositionClosureMath.day(time),
              let quantity = PositionClosureMath.decimal(quantity), quantity >= 0,
              let cost = PositionClosureMath.decimal(totalCost), cost >= 0,
              quantity != 0 || (cost == 0 && costKnown),
              position.category != .cash || (costKnown && cost == quantity),
              let quote = PositionClosureMath.decimal(quoteUnitCNY), quote >= 0,
              reason.count <= 80, !reason.isEmpty, note.count <= 1000,
              reversedAt == nil || ISO8601DateFormatter().date(from: reversedAt!) != nil else {
            throw PositionTradeError.invalidInput
        }
        if let reversalDay {
            guard let reversedAt, let time = ISO8601DateFormatter().date(from: reversedAt),
                  reversalDay == PositionClosureMath.day(time), reversalDay >= effectiveDay,
                  reversalProfitAdjustmentCNY == nil || reversalProfitAdjustmentCNY.flatMap(PositionClosureMath.decimal) != nil
            else { throw PositionTradeError.invalidInput }
        } else if reversedAt != nil || reversalProfitAdjustmentCNY != nil { throw PositionTradeError.invalidInput }
        if let baselineUnitCNY, let profitAdjustmentCNY {
            guard let baseline = PositionClosureMath.decimal(baselineUnitCNY), baseline >= 0,
                  let adjustment = PositionClosureMath.decimal(profitAdjustmentCNY),
                  abs((adjustment - (beforeUnits - quantity) * (quote - baseline)).doubleValue) < 0.000001
            else { throw PositionTradeError.invalidInput }
        } else if baselineUnitCNY != nil || profitAdjustmentCNY != nil {
            throw PositionTradeError.invalidInput
        }
    }
}
