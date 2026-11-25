import Foundation

enum AIPortfolioDataTool: String, CaseIterable, Sendable {
  case summary = "get_portfolio_summary"
  case holdings = "list_holdings"
  case closedHoldings = "list_closed_holdings"
  case transactions = "list_transactions"
  case performance = "get_holding_performance"
  case constraints = "get_risk_constraints"
  case history = "get_portfolio_history"
  case report = "get_latest_analysis_report"

  var definition: LLMFunctionTool {
    let properties: [String: AIJSONValue]
    let required: [String]
    let description: String
    switch self {
    case .summary:
      properties = [:]
      required = []
      description =
        "Read-only: current local portfolio value, cost, unrealized P&L, realized P&L, today's recorded performance, and holding count. Use for portfolio overview questions or accepting an offer to review holdings. Does not fetch live quotes."
    case .holdings, .closedHoldings, .transactions:
      let queryDesc: String = switch self {
      case .holdings: "Optional case-insensitive substring filter matching holding name or ticker symbol."
      case .closedHoldings: "Optional case-insensitive substring filter matching closed asset name or ticker symbol."
      case .transactions: "Optional case-insensitive substring filter matching asset name or ticker symbol across trades, openings, withdrawals, and checkpoints."
      default: ""
      }
      properties = [
        "query": .object([
          "type": .string("string"),
          "maxLength": .number(80),
          "description": .string(queryDesc),
        ]),
        "offset": Self.integer(0, 100_000, description: "Pagination start row index (0-based). Pass next_offset from a previous response to read the next page."),
        "limit": Self.integer(1, 25, description: "Maximum number of rows to return per call (1 to 25, default 20)."),
      ]
      required = []
      description = self == .transactions
        ? "Read-only: ledger records including additions, buys/sells, cash withdrawals, opening balances, and balance checkpoints. Note: reconciliations set balances without cash flow/realized P&L; openings are migrated starting balances; cash withdrawals are not sales or losses. Supports optional name/symbol filter and pagination."
        : self == .closedHoldings
        ? "Read-only: sale records for assets no longer held (including partial/full sales and legacy closures), with quantities, prices, fees, net proceeds, destination cash, and realized P&L. Supports optional name/symbol filter and pagination."
        : "Read-only: current open holdings with position_ref, symbol, quantities, recorded costs, market values, weights, unrealized P&L, and quote dates. Paginated (default 20); check omitted_count and follow next_offset when full coverage is needed."
    case .performance:
      properties = [
        "position_refs": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string"), "maxLength": .number(80)]),
          "minItems": .number(1), "maxItems": .number(10),
          "description": .string("1 to 10 holding identifiers: accepts position_ref (from list_holdings), ticker symbol (e.g. AAPL, 000218), or exact holding name."),
        ]),
        "period": .object([
          "type": .string("string"),
          "enum": .array([.string("one_week"), .string("one_month")]),
          "description": .string("Observation window: one_week (7 days) or one_month (30 days)."),
        ]),
      ]
      required = ["position_refs", "period"]
      description =
        "Read-only: recorded 1-week or 1-month price-change observations for up to 10 holdings (identified by position_ref, symbol, or name). Uses current quantities and excludes trades/fees/FX; not true account return or NAV drawdown."
    case .constraints:
      properties = [:]
      required = []
      description =
        "Read-only: whether risk preferences are configured, current allocation limits (single position, crypto, foreign currency, minimum cash) and current breach evaluation. Passing limits does not guarantee safety or returns."
    case .history:
      properties = [
        "days": Self.integer(1, 90, description: "Number of recent calendar days to return (1 to 90, default 30).")
      ]
      required = []
      description =
        "Read-only: up to 90 days of recorded portfolio values and daily price-based P&L. Values include deposits/withdrawals and holding changes; do not treat changes as time-weighted return or NAV drawdown."
    case .report:
      properties = [:]
      required = []
      description =
        "Read-only: dated digest of the most recent saved analysis report. Current holdings tools override stale report facts; an absent report does not prevent reading holdings."
    }
    return LLMFunctionTool(
      name: rawValue, description: description,
      parameters: .object([
        "type": .string("object"), "properties": .object(properties),
        "required": .array(required.map(AIJSONValue.string)), "additionalProperties": .bool(false),
      ]))
  }

  static let semanticWebSearchToolName = "web_search"

  static var semanticWebSearchDefinition: LLMFunctionTool {
    LLMFunctionTool(
      name: semanticWebSearchToolName,
      description: "Read-only public web search (available in Web Research mode). Use after inspecting local holdings/transactions or whenever up-to-date market news, filings, macro events, or fund announcements are needed. Returns verified public sources with citation IDs (cite inline as [[cite:source_N]]). Never include personal share counts, costs, or account values in query.",
      parameters: .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "properties": .object([
          "query": .object([
            "type": .string("string"),
            "minLength": .number(8),
            "maxLength": .number(128),
            "description": .string("Public search query (8 to 128 chars). Include ticker/asset name or market topic; years/quarters/form numbers like 2026 Q3 or 10-K are allowed. Never include personal amounts or credentials."),
          ]),
          "scope": .object([
            "type": .string("string"),
            "enum": .array([.string("auto"), .string("cn_domestic"), .string("global_en"), .string("deep_research")]),
            "description": .string("Optional routing hint: cn_domestic (A-shares/CN funds/domestic policy), global_en (US/HK/crypto/global macro), deep_research (multi-provider corroboration), or auto."),
          ]),
          "assets": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string"), "maxLength": .number(80)]),
            "maxItems": .number(3),
            "description": .string("Optional list of up to 3 related asset symbols or position_refs. Omit or pass [] for general market/macro queries."),
          ]),
        ]),
        "required": .array([.string("query")]),
      ])
    )
  }

  private static func integer(_ minimum: Int, _ maximum: Int, description: String) -> AIJSONValue {
    .object([
      "type": .string("integer"),
      "minimum": .number(Double(minimum)),
      "maximum": .number(Double(maximum)),
      "description": .string(description),
    ])
  }
}

struct AIPortfolioToolRequest: Sendable {
  let tool: AIPortfolioDataTool
  var query = ""
  var offset = 0
  var limit = 20
  var positionRefs: [String] = []
  var period = "one_week"
  var days = 30

  init(call: LLMFunctionCall) throws {
    guard let tool = AIPortfolioDataTool(rawValue: call.name) else {
      throw AIPortfolioToolError.invalidArguments(
        field: "name",
        hint: "Unknown read-only tool '\(call.name)'. Allowed tools: \(AIPortfolioDataTool.allCases.map(\.rawValue).joined(separator: ", "))."
      )
    }
    guard call.arguments.utf8.count <= 16_000 else {
      throw AIPortfolioToolError.invalidArguments(field: nil, hint: "Arguments payload exceeds 16,000 bytes.")
    }
    self.tool = tool
    guard
      case .object(let arguments) = try? JSONDecoder().decode(
        AIJSONValue.self, from: Data(call.arguments.utf8))
    else {
      throw AIPortfolioToolError.invalidArguments(field: nil, hint: "Arguments must be a valid JSON object.")
    }
    let allowed: Set<String>
    switch tool {
    case .holdings, .closedHoldings, .transactions:
      allowed = ["query", "offset", "limit"]
      if let value = arguments["query"] {
        guard case .string(let text) = value, text.count <= 80 else {
          throw AIPortfolioToolError.invalidArguments(field: "query", hint: "query must be a string of at most 80 characters.")
        }
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      offset = try Self.integer(arguments["offset"], field: "offset", default: 0, range: 0...100_000)
      limit = try Self.integer(arguments["limit"], field: "limit", default: 20, range: 1...25)
    case .performance:
      allowed = ["position_refs", "period"]
      guard case .array(let refs) = arguments["position_refs"], (1...10).contains(refs.count) else {
        throw AIPortfolioToolError.invalidArguments(
          field: "position_refs",
          hint: "position_refs must be a non-empty array of 1 to 10 holding refs, symbols, or names."
        )
      }
      guard case .string(let period) = arguments["period"], ["one_week", "one_month"].contains(period) else {
        throw AIPortfolioToolError.invalidArguments(
          field: "period",
          hint: "period must be either 'one_week' or 'one_month'."
        )
      }
      self.period = period
      positionRefs = try refs.map { value in
        guard case .string(let ref) = value, !ref.isEmpty, ref.count <= 80 else {
          throw AIPortfolioToolError.invalidArguments(
            field: "position_refs",
            hint: "Each element in position_refs must be a non-empty string up to 80 characters."
          )
        }
        return ref
      }
    case .history:
      allowed = ["days"]
      days = try Self.integer(arguments["days"], field: "days", default: 30, range: 1...90)
    default:
      allowed = []
    }
    let unexpected = Set(arguments.keys).subtracting(allowed)
    guard unexpected.isEmpty else {
      throw AIPortfolioToolError.invalidArguments(
        field: unexpected.sorted().first,
        hint: "Unexpected argument(s): \(unexpected.sorted().joined(separator: ", ")). Allowed keys: \(allowed.sorted().joined(separator: ", "))."
      )
    }
  }

  private static func integer(
    _ value: AIJSONValue?,
    field: String,
    default fallback: Int,
    range: ClosedRange<Int>
  ) throws -> Int {
    guard let value else { return fallback }
    guard case .number(let number) = value, number.isFinite, number.rounded() == number,
      number >= Double(range.lowerBound), number <= Double(range.upperBound)
    else {
      throw AIPortfolioToolError.invalidArguments(
        field: field,
        hint: "\(field) must be an integer between \(range.lowerBound) and \(range.upperBound)."
      )
    }
    return Int(number)
  }
}

enum AIPortfolioToolError: Error {
  case invalidArguments(field: String?, hint: String)
}
typealias AIPortfolioToolHandler = @Sendable (AIPortfolioToolRequest) async -> String

struct AIPortfolioToolSnapshot {
  let positions: [Position]
  var portfolioContext: AIFollowUpPortfolioContext? = nil
  var performance: [Position.ID: AIPositionPerformanceContext] = [:]
  var riskContext: AIAnalysisStoreContext? = nil
  var report: AIAnalysisReport? = nil
  var history: [PortfolioSnapshot] = []
  var dailyProfit: [DailyProfitPoint] = []
  var closures: [PositionClosureRecord] = []
  var trades: [PositionTradeRecord] = []
  var openings: [PositionOpeningBalanceRecord] = []
  var reconciliations: [PositionReconciliationRecord] = []
  var asOf: Date = .now
}

enum AIPortfolioDataToolExecutor {
  static let definitions = AIPortfolioDataTool.allCases.map(\.definition)

  static func error(_ code: String, field: String? = nil, hint: String? = nil) -> String {
    var payload: [String: Any] = ["status": "error", "code": code]
    if let field, !field.isEmpty { payload["field"] = field }
    if let hint, !hint.isEmpty { payload["hint"] = hint }
    return json(payload)
  }

  static func resolvePosition(_ identifier: String, in positions: [Position]) -> Position? {
    let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let exactRef = positions.first(where: { "position_\($0.id.uuidString)" == trimmed }) {
      return exactRef
    }
    if let bySymbol = positions.first(where: { $0.symbol.caseInsensitiveCompare(trimmed) == .orderedSame }) {
      return bySymbol
    }
    return positions.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
  }

  private static func rounded(_ value: Double, digits: Int = 2) -> Double {
    guard value.isFinite else { return 0 }
    let factor = pow(10.0, Double(digits))
    return (value * factor).rounded() / factor
  }

  static func execute(_ request: AIPortfolioToolRequest, snapshot: AIPortfolioToolSnapshot)
    -> String
  {
    let asOf = ISO8601DateFormatter().string(from: snapshot.asOf)
    let positions = snapshot.positions.sorted { $0.marketValueCNY > $1.marketValueCNY }
    var result: [String: Any] = [
      "status": "ok", "as_of": asOf, "source": "local_portfolix_records", "read_only": true,
    ]
    let knownCost = positions.allSatisfy(\.costIsKnown)
    result["history_complete"] = !snapshot.reconciliations.contains { !$0.isReversed }
    switch request.tool {
    case .summary:
      let value = positions.reduce(Decimal.zero) { $0 + $1.marketValueCNY }
      let cost = positions.reduce(Decimal.zero) { $0 + $1.totalCost / $1.quoteCurrency.rateFromCNY }
      let knownRealized = snapshot.trades.filter { !$0.isReversed && $0.side == .sell }.allSatisfy { $0.asset.costKnown != false }
      let realized = snapshot.closures.filter { !$0.isReversed }.reduce(Decimal.zero) { $0 + $1.realizedProfitCNY }
        + snapshot.trades.filter { !$0.isReversed }.reduce(Decimal.zero) { $0 + ($1.realizedProfit ?? 0) / $1.rate }
      let openIDs = Set(positions.map { $0.id.uuidString })
      let closedIDs = Set(snapshot.closures.filter { !$0.isReversed }.map { $0.holding.id })
        .union(snapshot.trades.filter { !$0.isReversed && $0.side == .sell && !openIDs.contains($0.asset.id) }.map { $0.asset.id })
      result["data"] =
        [
          "holding_count": positions.count, "total_value_cny": decimal(value),
          "cost_status": knownCost ? "known" : "unknown",
          "total_cost_cny": knownCost ? decimal(cost) as Any : NSNull(), "unrealized_profit_cny": knownCost ? decimal(value - cost) as Any : NSNull(),
          "realized_profit_status": knownRealized ? "known" : "incomplete",
          "realized_profit_cny": knownRealized ? decimal(realized) as Any : NSNull(),
          "transaction_count": snapshot.trades.filter { !$0.isReversed }.count + snapshot.closures.filter { !$0.isReversed }.count,
          "opening_balance_count": snapshot.openings.filter(\.isVisible).count,
          "closed_holding_count": closedIDs.count,
          "unrealized_profit_rate_pct": !knownCost || cost == 0
            ? NSNull() : decimal((value - cost) / cost * 100) as Any,
          "display_currency": snapshot.portfolioContext?.displayCurrency ?? "CNY",
          "total_value_display": snapshot.portfolioContext?.totalValueDisplay ?? decimal(value),
          "today": snapshot.portfolioContext.map { encoded($0.today) } ?? ["status": "unavailable"],
        ] as [String: Any]
    case .holdings:
      let filtered = positions.filter {
        request.query.isEmpty || $0.name.localizedCaseInsensitiveContains(request.query)
          || $0.symbol.localizedCaseInsensitiveContains(request.query)
      }
      let rows = filtered.dropFirst(min(request.offset, filtered.count)).prefix(request.limit)
      let nextOffset = min(filtered.count, request.offset + rows.count)
      result["total_count"] = positions.count
      result["matched_count"] = filtered.count
      result["omitted_count"] = max(0, filtered.count - nextOffset)
      result["next_offset"] = nextOffset < filtered.count ? nextOffset as Any : NSNull()
      let totalValue = positions.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue }
      let todayByRef = (snapshot.portfolioContext?.positions ?? []).reduce(
        into: [String: AIFollowUpReturnContext]()
      ) {
        $0[$1.positionRef] = $1.today
      }
      result["data"] = rows.map { position in
        let quoteCost = position.totalCost
        let quoteValue = position.quantity * position.latestPrice
        return [
          "position_ref": "position_\(position.id.uuidString)",
          "name": String(position.name.prefix(120)),
          "symbol": String(position.symbol.prefix(40)), "asset_type": position.category.aiCode,
          "quote_currency": position.quoteCurrency.rawValue, "quantity": decimal(position.quantity),
          "cost_status": position.costIsKnown ? "known" : "unknown",
          "average_cost": position.costIsKnown ? decimal(position.averageCost) as Any : NSNull(), "total_cost_quote": position.costIsKnown ? decimal(quoteCost) as Any : NSNull(),
          "latest_price": decimal(position.latestPrice),
          "market_value_cny": decimal(position.marketValueCNY),
          "unrealized_profit_quote": position.costIsKnown ? decimal(quoteValue - quoteCost) as Any : NSNull(),
          "unrealized_profit_rate_pct": position.costIsKnown ? decimal(position.profitRate) as Any : NSNull(),
          "allocation_pct": totalValue > 0
            ? rounded(position.marketValueCNY.doubleValue / totalValue * 100, digits: 2) : 0,
          "today": todayByRef["position_\(position.id.uuidString)"].map(encoded) ?? [
            "status": "unavailable"
          ],
          "quote_status": position.freshness == .manual
            ? "manual" : position.freshness == .stale ? "stale" : "updated",
          "quote_time": String(position.quoteTime.prefix(64)),
          "fetched_at": String(position.fetchedAt.prefix(64)),
        ] as [String: Any]
      }
    case .transactions:
      let filtered = PositionTransactionRow.listed(trades: snapshot.trades, closures: snapshot.closures,
          openings: snapshot.openings, reconciliations: snapshot.reconciliations, query: request.query)
      let rows = filtered.dropFirst(min(request.offset, filtered.count)).prefix(request.limit)
      let next = min(filtered.count, request.offset + rows.count)
      result["matched_count"] = filtered.count
      result["omitted_count"] = filtered.count - next
      result["next_offset"] = next < filtered.count ? next as Any : NSNull()
      result["data"] = rows.map { row -> [String: Any] in
        var data: [String: Any] = ["record_id": row.id.uuidString, "position_ref": "position_\(row.assetID)",
          "name": row.name, "symbol": row.symbol, "side": row.kind.rawValue,
          "trade_date": row.tradeDate, "quantity": row.quantity, "currency": row.currency.rawValue,
          "recorded_at": row.recordedAt.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull()]
        data["execution_price"] = decimal(row.price)
        data["effective_at"] = (row.trade?.effectiveAt ?? row.reconciliation?.effectiveAt) as Any? ?? NSNull()
        data["fees"] = decimal(row.fee)
        data["recorded_amount_quote"] = decimal(row.amount)
        data["cash_amount"] = decimal(row.kind.hasCashFlow ? row.amount : 0)
        data["portfolio_flow"] = row.kind == .opening || row.reconciliation != nil ? "none" : row.kind == .add ? "external_in" : row.kind == .withdraw ? "external_out" : "internal"
        if let record = row.reconciliation {
          data["is_transaction"] = false
          data["cost_status"] = record.costKnown ? "known" : "unknown"
          data["before_quantity"] = record.asset.quantity
          data["total_cost_quote"] = record.costKnown ? record.totalCost as Any : NSNull()
          data["execution_price"] = NSNull(); data["recorded_amount_quote"] = NSNull()
        }
        if row.kind == .withdraw {
          data["cash_flow_direction"] = "out"
          data["execution_price"] = NSNull()
        }
        if row.opening != nil {
          data["is_transaction"] = false
          data["opening_balance_needs_review"] = row.needsOpeningReview
          data["trade_date"] = NSNull()
          if row.needsOpeningReview {
            data["quantity"] = NSNull(); data["recorded_amount_quote"] = NSNull()
          }
          data["execution_price"] = NSNull()
        }
        data["funding_or_destination"] = row.trade?.cash?.name ?? (row.closure?.cashName ?? "external")
        data["realized_profit_quote"] = row.profit.map { decimal($0) } as Any? ?? NSNull()
        return data
      }
    case .closedHoldings:
      let activeIDs = Set(positions.map { $0.id.uuidString })
      let filtered = PositionTransactionRow.listed(trades: snapshot.trades, closures: snapshot.closures, query: request.query)
        .filter { $0.kind == .sell && !activeIDs.contains($0.assetID) }
      let rows = filtered.dropFirst(min(request.offset, filtered.count)).prefix(request.limit)
      let nextOffset = min(filtered.count, request.offset + rows.count)
      result["matched_count"] = filtered.count
      result["omitted_count"] = max(0, filtered.count - nextOffset)
      result["next_offset"] = nextOffset < filtered.count ? nextOffset as Any : NSNull()
      result["data"] = rows.map { row in
        ["record_id": row.id.uuidString, "position_ref": "position_\(row.assetID)",
         "name": row.name, "symbol": row.symbol, "trade_date": row.tradeDate,
         "currency": row.currency.rawValue, "quantity": row.quantity,
         "execution_price": decimal(row.price), "fees": decimal(row.fee), "net_proceeds": decimal(row.amount),
         "realized_profit_quote": row.profit.map(decimal) as Any? ?? NSNull(),
         "cash_destination": row.trade?.cash?.name ?? row.closure?.cashName ?? "external",
         "trade_day_profit_cny": row.closure?.dailyProfitCNY as Any? ?? NSNull()] as [String: Any]
      }
      result["limitation"] = "Realized P&L is net proceeds minus recorded cost; it is not the trade day's price-change P&L."
    case .performance:
      var missing: [String] = []
      result["data"] = request.positionRefs.compactMap { identifier -> [String: Any]? in
        guard let position = resolvePosition(identifier, in: positions)
        else {
          missing.append(identifier)
          return nil
        }
        let resolvedRef = "position_\(position.id.uuidString)"
        let performance = snapshot.performance[position.id]
        let window = request.period == "one_month" ? performance?.oneMonth : performance?.oneWeek
        return [
          "position_ref": resolvedRef,
          "symbol": position.symbol,
          "name": String(position.name.prefix(120)),
          "period": request.period,
          "observation": window.map(encoded) ?? ["status": "insufficient_history"],
        ]
      }
      result["missing_position_refs"] = missing
      result["calculation_basis"] =
        "price_change_times_current_quantity_excludes_trades_fees_fx_not_account_return_or_nav_drawdown"
    case .constraints:
      guard let context = snapshot.riskContext else { return error("risk_preferences_unavailable") }
      let evaluation = context.riskConstraintEvaluation
      result["data"] =
        [
          "configured": context.riskProfileConfigured, "risk_level": context.riskLevel,
          "single_position_limit_pct": rounded(context.positionLimit),
          "crypto_limit_pct": rounded(context.cryptoLimit),
          "foreign_currency_limit_pct": rounded(context.foreignCurrencyLimit),
          "liquidity_minimum_pct": rounded(context.liquidityMinimum),
          "largest_position_pct": rounded(evaluation.largestPositionPercent),
          "crypto_allocation_pct": rounded(evaluation.cryptoAllocationPercent),
          "non_cny_allocation_pct": rounded(evaluation.nonCNYAllocationPercent),
          "cash_allocation_pct": rounded(evaluation.cashAllocationPercent),
          "breach_count": evaluation.breachCount,
        ] as [String: Any]
      result["limitation"] = "Constraint fit does not measure investment safety or future returns."
    case .history:
      let calendar = Calendar.current
      let start =
        calendar.date(
          byAdding: .day, value: 1 - request.days, to: calendar.startOfDay(for: snapshot.asOf))
        ?? snapshot.asOf
      let end =
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: snapshot.asOf))
        ?? snapshot.asOf
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd"
      result["data"] = snapshot.history.filter {
        $0.date >= start && $0.date < end && $0.totalValueCNY.isFinite
      }.sorted { $0.date < $1.date }.suffix(90).map {
        ["date": formatter.string(from: $0.date), "total_value_cny": rounded($0.totalValueCNY)]
          as [String: Any]
      }
      result["daily_profit"] = snapshot.dailyProfit.filter { $0.date >= start && $0.date < end }
        .sorted { $0.date < $1.date }.suffix(90).map {
          ["date": formatter.string(from: $0.date), "amount_cny": decimal($0.amountCNY)]
        }
      result["limitation"] =
        "Portfolio value changes may include deposits, withdrawals and holding changes; they are not time-weighted returns or NAV drawdowns. Daily P&L follows the app's recorded price-based calculation."
    case .report:
      guard let report = snapshot.report else { return error("no_saved_report") }
      result["data"] =
        (try? JSONSerialization.jsonObject(with: Data(AIContextProjection.reportJSON(report).utf8)))
        ?? [:]
      result["limitation"] =
        "This is a dated report, not the current holdings snapshot. Prefer current holdings for up-to-date quantities and prices."
    }
    let response = json(result)
    if response.utf8.count <= AIFunctionCallPolicy.maximumResultBytes {
      return response
    }
    return error(
      "result_too_large_narrow_query",
      hint: "Result was \(response.utf8.count) bytes (limit \(AIFunctionCallPolicy.maximumResultBytes)). Reduce limit (e.g. 10) or days (e.g. 30), or pass a narrower query filter."
    )
  }

  private static func decimal(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
  }
  private static func encoded<T: Encodable>(_ value: T) -> Any {
    guard let data = try? AIAnalysisAgent.inputEncoder.encode(value),
      let object = try? JSONSerialization.jsonObject(with: data)
    else { return [:] }
    return object
  }
  private static func json(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    else { return #"{"status":"error","code":"unavailable"}"# }
    return text
  }
}
