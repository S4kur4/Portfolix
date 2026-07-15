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

struct AIReportEvidenceAttributionResult: Equatable {
    let report: AIAnalysisReport
    let notes: [String]
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

enum AIReportEvidenceAttributor {
    static func attribute(
        report: AIAnalysisReport,
        input: AIAnalysisInput,
        ledger: AIEvidenceLedger
    ) -> AIReportEvidenceAttributionResult {
        var attributedCount = 0
        let riskItems = report.riskItems.map { item -> AIReportRiskItem in
            let refs = normalizedExistingRefs(item.evidenceRefs, ledger: ledger)
            let resolvedRefs = refs.isEmpty
                ? evidenceRefs(forRiskCategory: item.category, relatedRefs: item.relatedRefs, ledger: ledger)
                : refs
            if refs.isEmpty, !resolvedRefs.isEmpty { attributedCount += 1 }
            return AIReportRiskItem(
                id: item.id,
                severity: item.severity,
                category: item.category,
                title: item.title,
                evidence: item.evidence,
                impact: item.impact,
                relatedRefs: item.relatedRefs,
                evidenceRefs: resolvedRefs.isEmpty ? nil : resolvedRefs
            )
        }
        let assetAlerts = report.assetAlerts.map { alert -> AIAssetAlert in
            let refs = normalizedExistingRefs(alert.evidenceRefs, ledger: ledger)
            let resolvedRefs = refs.isEmpty
                ? evidenceRefs(forSourceDomains: alert.sourceDomains, ledger: ledger)
                : refs
            if refs.isEmpty, !resolvedRefs.isEmpty { attributedCount += 1 }
            return AIAssetAlert(
                id: alert.id,
                assetName: alert.assetName,
                symbol: alert.symbol,
                title: alert.title,
                reason: alert.reason,
                sourceDomains: alert.sourceDomains,
                evidenceRefs: resolvedRefs.isEmpty ? nil : resolvedRefs
            )
        }
        let actions = (report.rebalanceActions ?? []).map { action -> AIRebalanceAction in
            let refs = normalizedExistingRefs(action.evidenceRefs, ledger: ledger)
            let resolvedRefs = refs.isEmpty
                ? evidenceRefs(for: action, input: input, ledger: ledger)
                : refs
            if refs.isEmpty, !resolvedRefs.isEmpty { attributedCount += 1 }
            return AIRebalanceAction(
                id: action.id,
                action: action.action,
                assetName: action.assetName,
                symbol: action.symbol,
                title: action.title,
                rationale: action.rationale,
                riskNote: action.riskNote,
                evidenceRefs: resolvedRefs.isEmpty ? nil : resolvedRefs
            )
        }
        let attributedReport = AIAnalysisReport(
            id: report.id,
            generatedAt: report.generatedAt,
            searchedAt: report.searchedAt,
            model: report.model,
            promptVersion: report.promptVersion,
            riskProfileVersion: report.riskProfileVersion,
            summary: report.summary,
            healthScoreExplanation: report.healthScoreExplanation,
            riskItems: riskItems,
            assetAlerts: assetAlerts,
            rebalanceActions: actions,
            questionsToConsider: report.questionsToConsider,
            dataQualityNotes: report.dataQualityNotes,
            limitations: report.limitations,
            sources: report.sources
        )
        let notes = attributedCount > 0 ? ["deterministic_evidence_attribution_count:\(attributedCount)"] : []
        return AIReportEvidenceAttributionResult(report: attributedReport, notes: notes)
    }

    private static func normalizedExistingRefs(
        _ refs: [String]?,
        ledger: AIEvidenceLedger
    ) -> [String] {
        guard let refs else { return [] }
        let allowed = Set(ledger.items.map(\.id))
        return Array(Array(NSOrderedSet(array: refs.filter(allowed.contains)).compactMap { $0 as? String }).prefix(4))
    }

    private static func evidenceRefs(
        forRiskCategory category: String,
        relatedRefs: [String],
        ledger: AIEvidenceLedger
    ) -> [String] {
        let metricFragments: [String]
        switch category {
        case "concentration": metricFragments = ["concentration", "top_", "effective_number"]
        case "asset_type_diversification": metricFragments = ["position_count", "effective_number", "concentration"]
        case "data_quality": metricFragments = ["data_quality", "quote_allocation"]
        case "volatility": metricFragments = ["performance", "weighted_return"]
        case "risk_profile": metricFragments = ["constraint", "risk_flag"]
        default: metricFragments = []
        }
        guard !metricFragments.isEmpty else { return [] }
        return ledger.items.filter { evidence in
            let metricMatches = metricFragments.contains { evidence.metric.localizedCaseInsensitiveContains($0) || evidence.id.localizedCaseInsensitiveContains($0) }
            let positionMatches = relatedRefs.isEmpty
                || evidence.positionRefs.isEmpty
                || !Set(evidence.positionRefs).isDisjoint(with: Set(relatedRefs))
            return metricMatches && positionMatches && evidence.confidence != "unavailable"
        }.prefix(2).map(\.id)
    }

    private static func evidenceRefs(
        forSourceDomains domains: [String],
        ledger: AIEvidenceLedger
    ) -> [String] {
        let normalizedDomains = Set(domains.map { $0.lowercased() })
        guard !normalizedDomains.isEmpty else { return [] }
        return ledger.items.filter { evidence in
            evidence.kind == "web_source" && normalizedDomains.contains(evidence.source.lowercased())
        }.prefix(3).map(\.id)
    }

    private static func evidenceRefs(
        for action: AIRebalanceAction,
        input: AIAnalysisInput,
        ledger: AIEvidenceLedger
    ) -> [String] {
        let matchedPositionRefs = Set(input.metrics.positions.compactMap { position -> String? in
            let symbolMatches = action.symbol.map { $0.caseInsensitiveCompare(position.symbol) == .orderedSame } ?? false
            let nameMatches = action.assetName.map { $0.caseInsensitiveCompare(position.displayLabel ?? "") == .orderedSame } ?? false
            return symbolMatches || nameMatches ? position.positionRef : nil
        })
        let text = [action.title, action.rationale, action.riskNote ?? ""].joined(separator: " ").lowercased()
        let metricFragments: [String]
        if containsAny(text, ["收益", "涨", "跌", "回撤", "return", "performance"]) {
            metricFragments = ["performance", "weighted_return"]
        } else if containsAny(text, ["集中", "仓位", "占比", "allocation", "concentration", "weight"]) {
            metricFragments = ["concentration", "top_"]
        } else if containsAny(text, ["风险", "约束", "阈值", "risk", "constraint", "limit"]) {
            metricFragments = ["constraint", "risk_flag"]
        } else {
            return []
        }
        return ledger.items.filter { evidence in
            let metricMatches = metricFragments.contains { evidence.metric.localizedCaseInsensitiveContains($0) || evidence.id.localizedCaseInsensitiveContains($0) }
            let positionMatches = matchedPositionRefs.isEmpty
                || evidence.positionRefs.isEmpty
                || !Set(evidence.positionRefs).isDisjoint(with: matchedPositionRefs)
            return metricMatches && positionMatches && evidence.confidence != "unavailable"
        }.prefix(2).map(\.id)
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.localizedCaseInsensitiveContains($0) }
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
        let evidenceCoveragePct = percentage(citedClaimCount, of: claimCount)

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
        let numericGroundingPct = percentage(groundedNumericClaimCount, of: numericClaims.count)
        let score = Int((evidenceCoveragePct * 0.6 + numericGroundingPct * 0.4).rounded())
        var warnings: [String] = []
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
        let markers = ["模型", "情景", "目标", "建议", "假设", "估计", "约", "区间", "scenario", "target", "assume", "estimate", "approximately"]
        return markers.contains { prefix.localizedCaseInsensitiveContains($0) }
    }

    private static func percentage(_ numerator: Int, of denominator: Int) -> Double {
        denominator == 0 ? 100 : (Double(numerator) / Double(denominator) * 100)
    }
}
