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
    static func validate(payload: LLMReportPayload, ledger: AIEvidenceLedger) throws {
        let allowedRefs = Set(ledger.items.map(\.id))
        if let invalidRef = payloadEvidenceRefs(payload).first(where: { !allowedRefs.contains($0) }) {
            throw AIReportPayloadValidationError.invalidEvidenceRef(invalidRef)
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
        let knownNumbers = numericMatches(in: inputJSON).compactMap(\.value)
            + ledger.items.compactMap(\.numericValue)
        let groundedNumericClaimCount = numericClaims.filter { claim in
            guard let value = claim.value else { return true }
            return knownNumbers.contains { known in
                abs(known - value) <= max(0.01, abs(known) * 0.001)
            } || hasDerivedMarker(before: claim.range, in: reportText)
        }.count
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

    private static func hasDerivedMarker(before range: NSRange, in text: String) -> Bool {
        let nsText = text as NSString
        let start = max(0, range.location - 36)
        let prefix = nsText.substring(with: NSRange(location: start, length: range.location - start)).lowercased()
        let markers = ["模型", "情景", "假设", "估计", "约", "scenario", "assume", "estimate", "approximately"]
        return markers.contains { prefix.localizedCaseInsensitiveContains($0) }
    }

    private static func percentage(_ numerator: Int, of denominator: Int, emptyValue: Double) -> Double {
        denominator == 0 ? emptyValue : (Double(numerator) / Double(denominator) * 100)
    }
}
