import CSQLite
import Foundation
import Testing

@testable import Portfolix

@Suite("Opt-in stored response diagnostics")
struct AIStoredResponseDiagnosticsTests {
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["PORTFOLIX_DIAGNOSE_STORED_RESPONSE"] == "1"))
  func validatesLatestStoredReportWithoutNetworkOrPrintingContent() throws {
    let path = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/app.portfolix.mac/portfolix.sqlite3")
      .path
    var database: OpaquePointer?
    guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
      let database
    else { throw DiagnosticError.unavailable }
    defer { sqlite3_close(database) }
    let query = """
      SELECT a.raw_report_json, a.input_json, e.evidence_json
      FROM ai_analysis_artifacts a
      JOIN ai_agent_evidence_ledgers e ON e.run_id = a.run_id
      ORDER BY a.rowid DESC LIMIT 1
      """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
      let statement
    else { throw DiagnosticError.unavailable }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw DiagnosticError.unavailable }
    func column(_ index: Int32) throws -> Data {
      guard let value = sqlite3_column_text(statement, index) else {
        throw DiagnosticError.unavailable
      }
      return Data(String(cString: value).utf8)
    }
    let raw = String(decoding: try column(0), as: UTF8.self)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let input = try #require(try JSONSerialization.jsonObject(with: column(1)) as? [String: Any])
    let language =
      AIResponseLanguage(rawValue: input["output_language"] as? String ?? "zh-CN")
      ?? .simplifiedChinese
    let ledger = try decoder.decode(AIEvidenceLedger.self, from: column(2))
    do {
      let payload = try AIAnalysisAgent.validatedPayload(raw, expectedLanguage: language)
      print("Stored report diagnostic: schema=passed")
      try AIReportEvidenceValidator.validate(payload: payload, ledger: ledger)
      print("Stored report diagnostic: evidence=passed")
      let metrics = input["metrics"] as? [String: Any] ?? [:]
      let positions = metrics["positions"] as? [[String: Any]] ?? []
      var comparisons = 0
      var unrelated = 0
      func inspect(_ evidenceRefs: [String], name: String?, symbol: String?) throws {
        let refs = Set(
          positions.filter {
            (name != nil && $0["display_label"] as? String == name)
              || (symbol != nil && $0["symbol"] as? String == symbol)
          }.compactMap { $0["position_ref"] as? String })
        guard !refs.isEmpty else { return }
        try AIReportEvidenceValidator.validateAssociation(
          evidenceRefs: evidenceRefs, relatedRefs: Array(refs), ledger: ledger)
        let scoped = ledger.items.filter {
          evidenceRefs.contains($0.id) && !$0.positionRefs.isEmpty
        }
        if scoped.contains(where: { Set($0.positionRefs).isDisjoint(with: refs) }) {
          if scoped.contains(where: { !Set($0.positionRefs).isDisjoint(with: refs) }) {
            comparisons += 1
          } else {
            unrelated += 1
          }
        }
      }
      for item in payload.assetAlerts {
        try inspect(item.evidenceRefs ?? [], name: item.assetName, symbol: item.symbol)
      }
      for item in payload.rebalanceActions {
        try inspect(item.evidenceRefs ?? [], name: item.assetName, symbol: item.symbol)
      }
      print(
        "Stored report diagnostic: comparative_claims=\(comparisons) unrelated_claims=\(unrelated)")
      print("Stored report diagnostic: asset_association=passed")
    } catch let error as AIReportPayloadValidationError {
      switch error {
      case .invalidJSON: print("Stored report diagnostic: invalid_json")
      case .invalidField(let field): print("Stored report diagnostic: invalid_field=\(field)")
      case .invalidEnum(let field): print("Stored report diagnostic: invalid_enum=\(field)")
      case .invalidListCount(let field): print("Stored report diagnostic: invalid_list=\(field)")
      case .invalidEvidenceRef: print("Stored report diagnostic: invalid_evidence_ref")
      case .languageMismatch: print("Stored report diagnostic: language_mismatch")
      case .informationSecurityViolation: print("Stored report diagnostic: security_violation")
      }
    }
  }

  private enum DiagnosticError: Error { case unavailable }
}
