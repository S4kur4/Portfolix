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
        "Read-only: current local portfolio value, cost, unrealized P&L, today's recorded performance and holding count. Use for portfolio follow-ups, including accepting an earlier offer to review holdings. Does not fetch live quotes."
    case .holdings, .closedHoldings, .transactions:
      properties = [
        "query": .object(["type": .string("string"), "maxLength": .number(80)]),
        "offset": Self.integer(0, 100_000), "limit": Self.integer(1, 25),
      ]
      required = []
      description = self == .transactions
        ? "Read-only: balance checkpoints, opening balances, additions, sales and external cash withdrawals. Reconciliations set balances without cash flow or realized profit; missing trades are not reconstructed and unknown cost is unavailable. Opening balances are migrated starting balances, not purchases or cash flows. External additions do not debit cash; cash-funded additions do. Cash withdrawals reduce portfolio cash, are not sales or investment losses, and have no realized P&L. Cash cannot be sold. Optional name/code query and pagination, default 20 rows. Cannot execute or modify records."
        : self == .closedHoldings
        ? "Read-only: sale records for assets no longer held, including current partial/full sales and legacy closures. Multiple sales can belong to one asset. Includes quantities, prices, fees, net proceeds, destination cash and realized P&L. Optional name/code query and pagination, default 20 rows. No trading or writes."
        : "Read-only: current holdings with asset refs, quantities, costs, market values, weights, unrealized P&L and quote dates. Optional name/code query; paginated, default 20 rows. Use next_offset until omitted_count is zero when the complete list is needed."
    case .performance:
      properties = [
        "position_refs": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string"), "maxLength": .number(80)]),
          "minItems": .number(1), "maxItems": .number(10),
        ]),
        "period": .object([
          "type": .string("string"), "enum": .array([.string("one_week"), .string("one_month")]),
        ]),
      ]
      required = ["position_refs", "period"]
      description =
        "Read-only: recorded one-week or one-month price-change observations for up to 10 holding refs from list_holdings. These use current quantities, exclude trades/fees/FX and are not true account returns or NAV drawdowns. Missing history is explicitly marked."
    case .constraints:
      properties = [:]
      required = []
      description =
        "Read-only: whether risk preferences are configured, current allocation limits and their local evaluation. Passing limits is not a safety or return guarantee."
    case .history:
      properties = ["days": Self.integer(1, 90)]
      required = []
      description =
        "Read-only: up to 90 days of recorded portfolio values and daily price-based P&L. Default 30 days. Values may include deposits/withdrawals and holding changes; do not treat their changes as time-weighted returns or NAV drawdowns."
    case .report:
      properties = [:]
      required = []
      description =
        "Read-only: dated digest of the most recent saved analysis report. Use only when relevant; current holdings tools override stale report facts. An absent report does not prevent reading holdings."
    }
    return LLMFunctionTool(
      name: rawValue, description: description,
      parameters: .object([
        "type": .string("object"), "properties": .object(properties),
        "required": .array(required.map(AIJSONValue.string)), "additionalProperties": .bool(false),
      ]))
  }

  private static func integer(_ minimum: Int, _ maximum: Int) -> AIJSONValue {
    .object([
      "type": .string("integer"), "minimum": .number(Double(minimum)),
      "maximum": .number(Double(maximum)),
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
    guard let tool = AIPortfolioDataTool(rawValue: call.name), call.arguments.utf8.count <= 16_000
    else { throw AIPortfolioToolError.invalidArguments }
    self.tool = tool
    guard
      case .object(let arguments) = try JSONDecoder().decode(
        AIJSONValue.self, from: Data(call.arguments.utf8))
    else { throw AIPortfolioToolError.invalidArguments }
    let allowed: Set<String>
    switch tool {
    case .holdings, .closedHoldings, .transactions:
      allowed = ["query", "offset", "limit"]
      if let value = arguments["query"] {
        guard case .string(let text) = value, text.count <= 80 else {
          throw AIPortfolioToolError.invalidArguments
        }
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      offset = try Self.integer(arguments["offset"], default: 0, range: 0...100_000)
      limit = try Self.integer(arguments["limit"], default: 20, range: 1...25)
    case .performance:
      allowed = ["position_refs", "period"]
      guard case .array(let refs) = arguments["position_refs"], (1...10).contains(refs.count),
        case .string(let period) = arguments["period"], ["one_week", "one_month"].contains(period)
      else { throw AIPortfolioToolError.invalidArguments }
      self.period = period
      positionRefs = try refs.map { value in
        guard case .string(let ref) = value, !ref.isEmpty, ref.count <= 80 else {
          throw AIPortfolioToolError.invalidArguments
        }
        return ref
      }
    case .history:
      allowed = ["days"]
      days = try Self.integer(arguments["days"], default: 30, range: 1...90)
    default:
      allowed = []
    }
    guard Set(arguments.keys).isSubset(of: allowed) else {
      throw AIPortfolioToolError.invalidArguments
    }
  }

  private static func integer(_ value: AIJSONValue?, default fallback: Int, range: ClosedRange<Int>)
    throws -> Int
  {
    guard let value else { return fallback }
    guard case .number(let number) = value, number.isFinite, number.rounded() == number,
      number >= Double(range.lowerBound), number <= Double(range.upperBound)
    else { throw AIPortfolioToolError.invalidArguments }
    return Int(number)
  }
}

enum AIPortfolioToolError: Error { case invalidArguments }
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

  static func error(_ code: String) -> String { json(["status": "error", "code": code]) }

  static func execute(_ request: AIPortfolioToolRequest, snapshot: AIPortfolioToolSnapshot)
    -> String
  {
    let asOf = ISO8601DateFormatter().string(from: snapshot.asOf)
    let positions = snapshot.positions.sorted { $0.marketValueCNY > $1.marketValueCNY }
    var result: [String: Any] = [
      "status": "ok", "as_of": asOf, "source": "local_portfolix_records", "read_only": true,
    ]
    let knownCost = positions.allSatisfy(\.costIsKnown)
    result["history_complete"] = snapshot.reconciliations.isEmpty
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
            ? position.marketValueCNY.doubleValue / totalValue * 100 : 0,
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
      result["data"] = request.positionRefs.compactMap { ref -> [String: Any]? in
        guard let position = positions.first(where: { "position_\($0.id.uuidString)" == ref })
        else {
          missing.append(ref)
          return nil
        }
        let performance = snapshot.performance[position.id]
        let window = request.period == "one_month" ? performance?.oneMonth : performance?.oneWeek
        return [
          "position_ref": ref, "period": request.period,
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
          "single_position_limit_pct": context.positionLimit,
          "crypto_limit_pct": context.cryptoLimit,
          "foreign_currency_limit_pct": context.foreignCurrencyLimit,
          "liquidity_minimum_pct": context.liquidityMinimum,
          "largest_position_pct": evaluation.largestPositionPercent,
          "crypto_allocation_pct": evaluation.cryptoAllocationPercent,
          "non_cny_allocation_pct": evaluation.nonCNYAllocationPercent,
          "cash_allocation_pct": evaluation.cashAllocationPercent,
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
        ["date": formatter.string(from: $0.date), "total_value_cny": $0.totalValueCNY]
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
    return response.utf8.count <= AIFunctionCallPolicy.maximumResultBytes
      ? response : error("result_too_large_narrow_query")
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
