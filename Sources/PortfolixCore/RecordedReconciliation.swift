import Foundation

/// Minimal read-only checkpoint representation shared by the app and local tools.
public struct RecordedReconciliation: Decodable, Sendable {
    public struct Asset: Decodable, Sendable { public let id: String }
    public let asset: Asset
    public let quantity: String
    public let totalCost: String
    public let costKnown: Bool
    public let effectiveAt: String
    public let effectiveDay: String
    public let profitAdjustmentCNY: String?
    public let reversedAt: String?
    public let reversalDay: String?
    public let reversalProfitAdjustmentCNY: String?
    public let sequence: Int

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func adjustments(_ records: [Self]) -> [String: [String: Decimal]] {
        var result: [String: [String: Decimal]] = [:]
        for record in records {
            if let text = record.profitAdjustmentCNY, let amount = Decimal(string: text, locale: posixLocale) {
                result[record.effectiveDay, default: [:]][record.asset.id, default: 0] += amount
            }
            if let day = record.reversalDay, let text = record.reversalProfitAdjustmentCNY,
               let amount = Decimal(string: text, locale: posixLocale) {
                result[day, default: [:]][record.asset.id, default: 0] += amount
            }
        }
        return result
    }
}

extension RecordedReconciliation {
    public static func costKnown(_ records: [Self], assetID: String? = nil, assetIDs: Set<String>? = nil, through day: String = "9999-12-31") -> Bool {
        guard !records.isEmpty else { return true }
        let relevantRecords: [Self]
        if let assetID {
            relevantRecords = records.filter { $0.asset.id == assetID }
            guard !relevantRecords.isEmpty else { return true }
        } else if let assetIDs {
            guard !assetIDs.isEmpty else { return true }
            relevantRecords = records.filter { assetIDs.contains($0.asset.id) }
            guard !relevantRecords.isEmpty else { return true }
        } else {
            relevantRecords = records
        }

        var states: [String: Bool] = [:]
        var events: [(String, Int, String, Bool)] = []
        events.reserveCapacity(relevantRecords.count)
        for record in relevantRecords {
            if record.effectiveDay <= day { events.append((record.effectiveAt, record.sequence, record.asset.id, record.costKnown)) }
            // Reversing the latest checkpoint restores the cost state before that checkpoint.
            if let reversedAt = record.reversedAt, let reversalDay = record.reversalDay, reversalDay <= day {
                var bestSequence = Int.min
                var beforeKnown = true
                for prior in relevantRecords where prior.asset.id == record.asset.id && prior.sequence < record.sequence {
                    if let priorReversedAt = prior.reversedAt, priorReversedAt <= record.effectiveAt {
                        continue
                    }
                    if prior.sequence > bestSequence {
                        bestSequence = prior.sequence
                        beforeKnown = prior.costKnown
                    }
                }
                events.append((reversedAt, record.sequence, record.asset.id, beforeKnown))
            }
        }
        guard !events.isEmpty else { return true }
        for event in events.sorted(by: { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }) { states[event.2] = event.3 }
        if let assetID { return states[assetID] ?? true }
        return states.values.allSatisfy { $0 }
    }

    public static func incompleteDays(_ records: [Self]) -> Set<String> {
        var days = Set<String>()
        for record in records {
            if record.profitAdjustmentCNY == nil { days.insert(record.effectiveDay) }
            if let reversalDay = record.reversalDay, record.reversalProfitAdjustmentCNY == nil { days.insert(reversalDay) }
        }
        return days
    }
}
