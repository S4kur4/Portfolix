import Foundation

enum AIContextProjection {
  static func needsPortfolio(
    _ question: String, positions: [Position], chatHistory: [AIReportChatItem] = []
  ) -> Bool {
    let hints = [
      "持仓", "组合", "报告", "收益", "盈亏", "赚", "亏", "回撤", "成本", "份额", "市值", "仓位", "我的", "我该", "我应该",
      "该基金", "这只", "这些", "继续", "portfolio", "holding", "report", "profit", "loss", "my ", "our ",
      "that ", "continue",
    ]
    if hints.contains(where: { question.localizedCaseInsensitiveContains($0) })
      || positions.contains { position in
        [position.name, position.symbol].contains { matchesIdentity($0, in: question) }
      }
    {
      return true
    }
    let compact = question.lowercased().replacingOccurrences(
      of: #"[\p{P}\s]+"#, with: "", options: .regularExpression)
    let acknowledgements: Set<String> = [
      "好", "好的", "可以", "行", "好你帮我看看", "好的你帮我看看", "你帮我看看", "帮我看看", "帮我看一下",
      "那你帮我看看", "麻烦你看看", "好的帮我看看", "请帮我看看", "具体说说", "展开说说",
      "yes", "sure", "ok", "okay", "yesplease", "please", "pleasedo", "goahead", "takealook",
      "dothat", "doit",
    ]
    guard acknowledgements.contains(compact),
      let preceding = chatHistory.last(where: { $0.kind != .user })
    else { return false }
    if preceding.kind == .report { return true }
    let portfolioHints = ["持仓", "组合", "仓位", "你的资产", "portfolio", "your holdings", "your positions"]
    return portfolioHints.contains { (preceding.text ?? "").localizedCaseInsensitiveContains($0) }
  }

  static func reportJSON(_ report: AIAnalysisReport?) -> String {
    guard let report else { return "{}" }
    return json([
      "generated_at": ISO8601DateFormatter().string(from: report.generatedAt),
      "summary": report.summary,
      "risk_items": report.riskItems.prefix(4).map {
        ["title": $0.title, "evidence": $0.evidence, "impact": $0.impact]
      },
      "asset_alerts": report.assetAlerts.prefix(3).map {
        ["asset": $0.assetName, "symbol": $0.symbol, "reason": $0.reason]
      },
      "rebalance_actions": (report.rebalanceActions ?? []).prefix(3).map {
        ["title": $0.title, "rationale": $0.rationale]
      },
      "limitations": Array(report.limitations.prefix(4)),
    ])
  }

  static func portfolioJSON(_ context: AIFollowUpPortfolioContext?, question: String) -> String {
    guard let context, let data = try? AIAnalysisAgent.inputEncoder.encode(context),
      var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let positions = object["positions"] as? [[String: Any]]
    else { return "{}" }
    let matched = positions.filter { position in
      [position["display_label"] as? String, position["symbol"] as? String].compactMap { $0 }
        .contains { matchesIdentity($0, in: question) }
    }
    let selected = matched.isEmpty ? positions : matched
    object["generated_at"] = nil
    object["positions"] = Array(selected.prefix(16))
    object["omitted_position_count"] = positions.count - min(16, selected.count)
    return json(object)
  }

  static func evidenceJSON(_ ledger: AIEvidenceLedger) -> String {
    guard let data = try? AIAnalysisAgent.encoder.encode(ledger),
      var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      var items = object["items"] as? [[String: Any]]
    else { return "{}" }
    for index in items.indices {
      items[index]["scope"] = ledger.items[index].associationScope.rawValue
      if items[index]["numeric_value"] != nil { items[index]["value_text"] = nil }
      if items[index]["kind"] as? String == "calculation" {
        items[index]["source"] = nil
        items[index]["as_of"] = nil
      }
    }
    object["items"] = items
    object["local_evidence_source"] = "portfolix_local_financial_tool"
    return json(object)
  }

  static func searchSummaryJSON(_ results: [AIWebSearchToolResult]) -> String {
    json(
      results.map {
        ["call_id": $0.callID, "status": $0.status, "limitations": $0.limitations] as [String: Any]
      })
  }

  private static func json(_ object: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      let string = String(data: data, encoding: .utf8)
    else { return "{}" }
    return string
  }

  private static func matchesIdentity(_ identity: String, in question: String) -> Bool {
    guard identity.count >= 2 else { return false }
    let escaped = NSRegularExpression.escapedPattern(for: identity)
    return question.range(
      of: "(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])",
      options: [.regularExpression, .caseInsensitive]) != nil
  }
}
