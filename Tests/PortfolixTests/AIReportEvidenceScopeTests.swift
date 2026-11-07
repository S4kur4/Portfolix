import Foundation
import Testing
@testable import Portfolix

@Suite("Report evidence scope and repair diagnostics")
struct AIReportEvidenceScopeTests {
    private func item(_ id: String, refs: [String], kind: String = "calculation") -> AIEvidenceItem {
        AIEvidenceItem(id: id, kind: kind, metric: "test", valueText: "25", numericValue: 25,
            unit: "percent", positionRefs: refs, asOf: "2026-11-07",
            source: "portfolix_local_financial_tool", confidence: "deterministic", sourceURL: nil)
    }

    @Test(arguments: ["local.concentration.investable_hhi", "local.concentration.top_1_pct",
                       "local.performance.one_week.weighted_return_pct", "local.performance.one_week.coverage_pct"])
    func portfolioAggregatesAreContextForHoldingsOutsideTheirContributorList(id: String) throws {
        let ledger = AIEvidenceLedger(schemaVersion: "agent-evidence-ledger.v1", generatedAt: .now,
            items: [item(id, refs: ["position_largest"])])
        try AIReportEvidenceValidator.validateAssociation(evidenceRefs: [id],
            relatedRefs: ["position_smaller"], ledger: ledger)
    }

    @Test func portfolioContextDoesNotExcuseAnUnrelatedAssetSource() {
        let ledger = AIEvidenceLedger(schemaVersion: "test", generatedAt: .now, items: [
            item("local.concentration.investable_hhi", refs: ["position_largest"]),
            item("web.other.1", refs: ["position_other"], kind: "web_source")])
        #expect(throws: AIReportPayloadValidationError.self) {
            try AIReportEvidenceValidator.validateAssociation(
                evidenceRefs: ledger.items.map(\.id), relatedRefs: ["position_smaller"], ledger: ledger)
        }
    }

    @Test func associationRepairExplainsTheRelationshipInsteadOfChangingFieldTypes() {
        let instruction = AIReportPayloadValidationError.invalidField("risk_items[1].evidence_refs.asset_association").repairInstruction
        #expect(instruction.contains("position_refs"))
        #expect(instruction.contains("risk_items[1]"))
    }

    @Test func associationFailureIdentifiesTheExactItem() {
        let ledger = AIEvidenceLedger(schemaVersion: "test", generatedAt: .now,
            items: [item("web.other.1", refs: ["position_other"], kind: "web_source")])
        do {
            try AIReportEvidenceValidator.validateAssociation(evidenceRefs: ["web.other.1"],
                relatedRefs: ["position_smaller"], ledger: ledger, field: "asset_alerts[2].evidence_refs")
            Issue.record("An unrelated asset source must be rejected")
        } catch let error as AIReportPayloadValidationError {
            #expect(error.localizedDescription.contains("asset_alerts[2].evidence_refs.asset_association"))
        } catch { Issue.record("Unexpected error") }
    }

    @Test func legacyAggregateScopeSurvivesArchiveDecodingAndPromptProjection() throws {
        let legacy = AIEvidenceLedger(schemaVersion: "agent-evidence-ledger.v1", generatedAt: .now,
            items: [item("local.concentration.investable_hhi", refs: ["position_largest"])])
        let data = try AIAnalysisAgent.encoder.encode(legacy)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(AIEvidenceLedger.self, from: data)
        #expect(restored.items.first?.scope == nil)
        #expect(restored.items.first?.associationScope == .portfolio)
        #expect(AIContextProjection.evidenceJSON(restored).contains("\"scope\":\"portfolio\""))
    }
}
