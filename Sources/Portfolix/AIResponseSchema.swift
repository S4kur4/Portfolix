import Foundation

indirect enum AIJSONValue: Codable, Equatable, Sendable {
  case object([String: AIJSONValue])
  case array([AIJSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: AIJSONValue].self) {
      self = .object(value)
    } else {
      self = .array(try container.decode([AIJSONValue].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}

enum AIResponseSchema: String, Equatable, Sendable {
  case report, followUp, searchPlan, distribution

  static func forStage(_ stage: String) -> Self? {
    switch stage {
    case "report_answer", "report_repair": .report
    case "follow_up_answer", "follow_up_repair": .followUp
    case "report_planning", "follow_up_planning", "distribution_planning": .searchPlan
    case "distribution_classification": .distribution
    default: nil
    }
  }

  var schema: AIJSONValue {
    let text = Self.text()
    let refs = Self.list(text, maximum: 8)
    switch self {
    case .followUp:
      return Self.object([
        "answer": Self.text(maximum: AIFollowUpGuardrail.maximumAnswerCharacters),
        "limitations": Self.list(text, maximum: 4),
      ])
    case .searchPlan:
      return Self.object([
        "status": Self.choice(["continue", "finish"]),
        "tool_calls": Self.list(
          Self.object([
            "id": text, "provider": Self.choice(SearchProviderOption.allCases.map(\.rawValue)),
            "query": Self.text(maximum: 128), "position_refs": Self.list(text, maximum: 3),
          ]), maximum: 3),
        "limitations": Self.list(text, maximum: 4),
      ])
    case .report:
      return Self.object([
        "summary": Self.text(maximum: 220), "health_score_explanation": Self.text(maximum: 320),
        "risk_items": Self.list(
          Self.object([
            "severity": Self.choice(["info", "warning", "high"]),
            "category": Self.choice([
              "concentration", "asset_type_diversification", "data_quality", "volatility",
              "currency_exposure", "external_event", "risk_profile",
            ]),
            "title": Self.text(maximum: 120), "evidence": Self.text(maximum: 360),
            "impact": Self.text(maximum: 420),
            "related_refs": refs, "evidence_refs": refs,
          ]), maximum: 4),
        "asset_alerts": Self.list(
          Self.object([
            "asset_name": text, "symbol": text, "title": Self.text(maximum: 140),
            "reason": Self.text(maximum: 360), "source_domains": Self.list(text, maximum: 6),
            "evidence_refs": refs,
          ]), maximum: 3),
        "rebalance_actions": Self.list(
          Self.object([
            "action": Self.choice([
              "observe", "maintain", "hold", "buy", "increase", "reduce", "sell", "exit",
              "review_reduce", "review_replenish", "rebalance",
            ]),
            "asset_name": Self.nullableText(), "symbol": Self.nullableText(),
            "title": Self.text(maximum: 140), "rationale": Self.text(maximum: 360),
            "risk_note": Self.nullableText(), "evidence_refs": refs,
          ]), maximum: 3),
        "questions_to_consider": Self.list(text, maximum: 3),
        "data_quality_notes": Self.list(text, maximum: 4),
        "limitations": Self.list(text, maximum: 4),
      ])
    case .distribution:
      return Self.object([
        "assets": Self.list(
          Self.object([
            "position_ref": text, "source_urls": Self.list(text, maximum: 6),
            "allocations": Self.list(
              Self.object([
                "domain": Self.object([
                  "id": Self.text(maximum: 64), "titleChinese": Self.text(maximum: 48),
                  "titleEnglish": Self.text(maximum: 48),
                ]),
                "weight": .object([
                  "type": .string("number"), "minimum": .number(0), "maximum": .number(1),
                ]),
              ]), maximum: 1),
          ]), maximum: 24)
      ])
    }
  }

  private static func object(_ properties: [String: AIJSONValue]) -> AIJSONValue {
    .object([
      "type": .string("object"), "properties": .object(properties),
      "required": .array(properties.keys.sorted().map(AIJSONValue.string)),
      "additionalProperties": .bool(false),
    ])
  }
  private static func text(maximum: Int = 500) -> AIJSONValue {
    .object(["type": .string("string"), "maxLength": .number(Double(maximum))])
  }
  private static func nullableText() -> AIJSONValue {
    .object(["type": .array([.string("string"), .string("null")])])
  }
  private static func list(_ items: AIJSONValue, maximum: Int) -> AIJSONValue {
    .object(["type": .string("array"), "items": items, "maxItems": .number(Double(maximum))])
  }
  private static func choice(_ options: [String]) -> AIJSONValue {
    .object(["type": .string("string"), "enum": .array(options.map(AIJSONValue.string))])
  }
}
