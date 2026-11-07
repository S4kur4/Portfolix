import Foundation

struct AIReportQualityScorecard: Codable, Equatable, Sendable {
    let schemaVersion: String
    let score: Int
    let claimCount: Int
    let citedClaimCount: Int
    let evidenceCoveragePct: Double
    let numericClaimCount: Int
    let groundedNumericClaimCount: Int
    let numericGroundingPct: Double
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case score
        case claimCount = "claim_count"
        case citedClaimCount = "cited_claim_count"
        case evidenceCoveragePct = "evidence_coverage_pct"
        case numericClaimCount = "numeric_claim_count"
        case groundedNumericClaimCount = "grounded_numeric_claim_count"
        case numericGroundingPct = "numeric_grounding_pct"
        case warnings
    }
}

enum AIReportQualityPolicy {
    static let minimumScore = 70
    static let minimumEvidenceCoveragePct = 70.0
    static let minimumNumericGroundingPct = 70.0

    static func status(for scorecard: AIReportQualityScorecard) -> String {
        guard scorecard.claimCount > 0,
              scorecard.score >= minimumScore,
              scorecard.evidenceCoveragePct >= minimumEvidenceCoveragePct,
              scorecard.numericClaimCount == 0
                || scorecard.numericGroundingPct >= minimumNumericGroundingPct else {
            return "needs_review"
        }
        return "passed"
    }
}

enum AIReportEvidenceValidator {
    static func validate(payload: LLMReportPayload, ledger: AIEvidenceLedger, input: AIAnalysisInput? = nil) throws {
        let allowedRefs = Set(ledger.items.map(\.id))
        if let invalidRef = payloadEvidenceRefs(payload).first(where: { !allowedRefs.contains($0) }) {
            throw AIReportPayloadValidationError.invalidEvidenceRef(invalidRef)
        }
        for (index, risk) in payload.riskItems.enumerated() {
            try validateAssociation(evidenceRefs: risk.evidenceRefs ?? [], relatedRefs: risk.relatedRefs, ledger: ledger,
                field: "risk_items[\(index)].evidence_refs")
        }
        if let input {
            for (index, alert) in payload.assetAlerts.enumerated() {
                let refs = input.metrics.positions.filter { $0.displayLabel == alert.assetName || $0.symbol == alert.symbol }.map(\.positionRef)
                try validateAssociation(evidenceRefs: alert.evidenceRefs ?? [], relatedRefs: refs, ledger: ledger,
                    field: "asset_alerts[\(index)].evidence_refs")
            }
            for (index, action) in payload.rebalanceActions.enumerated() {
                let refs = input.metrics.positions.filter {
                    (action.assetName != nil && $0.displayLabel == action.assetName)
                        || (action.symbol != nil && $0.symbol == action.symbol)
                }.map(\.positionRef)
                try validateAssociation(evidenceRefs: action.evidenceRefs ?? [], relatedRefs: refs, ledger: ledger,
                    field: "rebalance_actions[\(index)].evidence_refs")
            }
        }
    }

    static func validateAssociation(evidenceRefs: [String], relatedRefs: [String], ledger: AIEvidenceLedger,
                                    field: String = "evidence_refs") throws {
        guard !relatedRefs.isEmpty else { return }
        let scoped = ledger.items.filter { evidenceRefs.contains($0.id) && $0.associationScope == .positions }
        guard scoped.isEmpty || scoped.contains(where: { !Set($0.positionRefs).isDisjoint(with: relatedRefs) }) else {
            throw AIReportPayloadValidationError.invalidField("\(field).asset_association")
        }
    }

    static func validate(report: AIAnalysisReport, ledger: AIEvidenceLedger) throws {
        let allowedRefs = Set(ledger.items.map(\.id))
        if let invalidRef = reportEvidenceRefs(report).first(where: { !allowedRefs.contains($0) }) {
            throw AIReportValidationError.invalidEvidenceRef(invalidRef)
        }
    }

    private static func payloadEvidenceRefs(_ payload: LLMReportPayload) -> [String] {
        payload.riskItems.flatMap { $0.evidenceRefs ?? [] }
            + payload.assetAlerts.flatMap { $0.evidenceRefs ?? [] }
            + payload.rebalanceActions.flatMap { $0.evidenceRefs ?? [] }
    }

    private static func reportEvidenceRefs(_ report: AIAnalysisReport) -> [String] {
        report.riskItems.flatMap { $0.evidenceRefs ?? [] }
            + report.assetAlerts.flatMap { $0.evidenceRefs ?? [] }
            + (report.rebalanceActions ?? []).flatMap { $0.evidenceRefs ?? [] }
    }
}

enum AIReportQualityEvaluator {
    static func evaluate(
        report: AIAnalysisReport,
        inputJSON: String,
        ledger: AIEvidenceLedger
    ) -> AIReportQualityScorecard {
        let claims = report.riskItems.map { $0.evidenceRefs ?? [] }
            + report.assetAlerts.map { $0.evidenceRefs ?? [] }
            + (report.rebalanceActions ?? []).map { $0.evidenceRefs ?? [] }
        let claimCount = claims.count
        let citedClaimCount = claims.filter { !$0.isEmpty }.count
        let evidenceCoveragePct = percentage(citedClaimCount, of: claimCount, emptyValue: 0)

        let reportText = userFacingText(report)
        let numericClaims = numericMatches(in: reportText)
        var sections: [(String, [String])] = []
        for risk in report.riskItems {
            sections.append(("\(risk.title) \(risk.evidence) \(risk.impact)", risk.evidenceRefs ?? []))
        }
        for alert in report.assetAlerts {
            sections.append(("\(alert.title) \(alert.reason)", alert.evidenceRefs ?? []))
        }
        for action in report.rebalanceActions ?? [] {
            sections.append(("\(action.title) \(action.rationale) \(action.riskNote ?? "")", action.evidenceRefs ?? []))
        }
        let snapshotEvidence = summarySnapshotEvidence(inputJSON)
        let allEvidence = ledger.items + snapshotEvidence
        let summaryRefs = ledger.items.filter { $0.kind == "calculation" }.map(\.id) + snapshotEvidence.map(\.id)
        sections.append((report.summary + " " + report.healthScoreExplanation, summaryRefs))
        let groundedNumericClaimCount = sections.reduce(0) { count, section in
            let evidence = allEvidence.filter { section.1.contains($0.id) }
            return count + numericMatches(in: section.0).filter { claim in
                guard let value = claim.value else { return false }
                let unit = claimUnit(in: section.0, range: claim.range)
                return evidence.contains { item in
                    guard let known = item.numericValue else { return false }
                    if let expectedUnit = unit.name, item.unit != expectedUnit { return false }
                    return abs(known - value * unit.scale) <= max(0.01, abs(known) * 0.001)
                }
            }.count
        }
        let numericGroundingPct = percentage(groundedNumericClaimCount, of: numericClaims.count, emptyValue: 0)
        let score: Int
        if numericClaims.isEmpty {
            score = Int(evidenceCoveragePct.rounded())
        } else {
            score = Int((evidenceCoveragePct * 0.6 + numericGroundingPct * 0.4).rounded())
        }
        var warnings: [String] = []
        if claimCount == 0 {
            warnings.append("no_auditable_claims")
        }
        if claimCount > 0, evidenceCoveragePct < 50 {
            warnings.append("low_evidence_reference_coverage")
        }
        if !numericClaims.isEmpty, numericGroundingPct < 70 {
            warnings.append("low_numeric_grounding_coverage")
        }
        return AIReportQualityScorecard(
            schemaVersion: "report-quality-scorecard.v1",
            score: score,
            claimCount: claimCount,
            citedClaimCount: citedClaimCount,
            evidenceCoveragePct: evidenceCoveragePct,
            numericClaimCount: numericClaims.count,
            groundedNumericClaimCount: groundedNumericClaimCount,
            numericGroundingPct: numericGroundingPct,
            warnings: warnings
        )
    }

    private static func userFacingText(_ report: AIAnalysisReport) -> String {
        [
            report.summary,
            report.healthScoreExplanation,
            report.riskItems.map { "\($0.title) \($0.evidence) \($0.impact)" }.joined(separator: " "),
            report.assetAlerts.map { "\($0.title) \($0.reason)" }.joined(separator: " "),
            (report.rebalanceActions ?? []).map { "\($0.title) \($0.rationale) \($0.riskNote ?? "")" }.joined(separator: " "),
        ].joined(separator: " ")
    }

    private static func numericMatches(in text: String) -> [(value: Double?, range: NSRange)] {
        guard let regex = try? NSRegularExpression(pattern: #"[-+]?\d[\d,]*(?:\.\d+)?%?"#) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            let raw = nsText.substring(with: match.range)
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "%", with: "")
            return (Double(raw), match.range)
        }
    }

    private static func summarySnapshotEvidence(_ inputJSON: String) -> [AIEvidenceItem] {
        guard let data = inputJSON.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let snapshot = object["snapshot"] as? [String: Any] else { return [] }
        let fields = ["total_value_text", "holding_return_text", "holding_return_rate_text"]
        return fields.flatMap { field -> [AIEvidenceItem] in
            guard let text = snapshot[field] as? String else { return [] }
            return numericMatches(in: text).compactMap { number in
                guard let value = number.value else { return nil }
                let unit = claimUnit(in: text, range: number.range)
                return AIEvidenceItem(id: "snapshot.\(field)", kind: "calculation", metric: field, valueText: text,
                                      numericValue: value * unit.scale, unit: unit.name, positionRefs: [], asOf: "snapshot",
                                      source: "portfolix_snapshot", confidence: "deterministic", sourceURL: nil)
            }
        }
    }

    private static func claimUnit(in text: String, range: NSRange) -> (name: String?, scale: Double) {
        let nsText = text as NSString
        let raw = nsText.substring(with: range)
        if raw.hasSuffix("%") { return ("percent", 1) }
        let start = max(0, range.location - 4)
        let before = nsText.substring(with: NSRange(location: start, length: range.location - start)).uppercased()
        let end = NSMaxRange(range)
        let after = nsText.substring(with: NSRange(location: end, length: min(8, nsText.length - end))).trimmingCharacters(in: .whitespaces).uppercased()
        if before.hasSuffix("HK$") || before.hasSuffix("HKD") || after.hasPrefix("HKD") || after.hasPrefix("港元") { return ("HKD", 1) }
        if before.hasSuffix("$") || before.hasSuffix("USD") || after.hasPrefix("USD") || after.hasPrefix("美元") { return ("USD", 1) }
        if after.hasPrefix("万元") { return ("CNY", 10_000) }
        if before.hasSuffix("¥") || before.hasSuffix("￥") || before.hasSuffix("CNY") || after.hasPrefix("元") || after.hasPrefix("CNY") { return ("CNY", 1) }
        if after.hasPrefix("%") || after.hasPrefix("％") { return ("percent", 1) }
        return (nil, 1)
    }

    private static func percentage(_ numerator: Int, of denominator: Int, emptyValue: Double) -> Double {
        denominator == 0 ? emptyValue : (Double(numerator) / Double(denominator) * 100)
    }
}
