import Foundation

/// Read a whitelist of ledger fields, never archived payloads or application settings.
struct MCPPortfolioLedger {
    struct Record {
        var fields: [String: String]
        let timestamp: Date
        let sequence: Int
        var id: String { fields["record_id"]! }
        var assetID: String { fields["asset_id"]! }
        var side: String { fields["side"]! }
        var isOpening: Bool { side == "opening" }

        var realizedProfitCNY: Decimal {
            guard side == "sell", let amount = Self.decimal(fields["recorded_amount_quote"]),
                  let cost = Self.decimal(fields["allocated_cost_quote"]),
                  let rate = Self.decimal(fields["rate_from_cny"]), rate > 0 else { return 0 }
            return (amount - cost) / rate
        }

        func output(number: Int) -> [String: Any] {
            var result: [String: Any] = [:]
            for key in MCPPortfolioLedger.outputFields { result[key] = fields[key] as Any? ?? NSNull() }
            result["number"] = String(number)
            if side == "sell" {
                let amount = Self.decimal(fields["recorded_amount_quote"])!
                let cost = Self.decimal(fields["allocated_cost_quote"])!
                result["realized_profit_quote"] = NSDecimalNumber(decimal: amount - cost).stringValue
                result["realized_profit_cny"] = NSDecimalNumber(decimal: realizedProfitCNY).stringValue
            }
            return result
        }

        static func decimal(_ value: String?) -> Decimal? {
            guard let value, value.count <= 80,
                  value.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
                  let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
                  !number.isNaN, abs(NSDecimalNumber(decimal: number).doubleValue) <= 1e28 else { return nil }
            return number
        }
    }

    static let outputFields = "record_id asset_id name symbol category side trade_date recorded_at currency quantity execution_price fees recorded_amount_quote cash_account_id cash_account_name portfolio_flow opening_balance_status realized_profit_quote realized_profit_cny number".split(separator: " ").map(String.init)
    let records: [Record]
    let openAssetIDs: Set<String>
    var closedSales: [Record] { records.filter { $0.side == "sell" && !openAssetIDs.contains($0.assetID) } }
    var realizedProfitCNY: Decimal { records.reduce(0) { $0 + $1.realizedProfitCNY } }
    var transactionCount: Int { records.filter { !$0.isOpening }.count }
    var openingCount: Int { records.filter(\.isOpening).count }

    init(database: MCPDatabase) throws {
        openAssetIDs = Set(try database.query("SELECT asset_id FROM positions").compactMap { $0["asset_id"] })
        var records: [Record] = []
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions.insert(.withFractionalSeconds)
        let tables = Set(try database.query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0["name"] })
        if tables.contains("position_trades") {
            let rows = try database.query("""
                SELECT id AS record_id, json_extract(payload_json, '$.asset.id') AS asset_id,
                    json_extract(payload_json, '$.asset.name') AS name, json_extract(payload_json, '$.asset.symbol') AS symbol,
                    json_extract(payload_json, '$.asset.category') AS category, json_extract(payload_json, '$.side') AS side,
                    trade_date, json_extract(payload_json, '$.recordedAt') AS recorded_at,
                    json_extract(payload_json, '$.asset.quoteCurrency') AS currency,
                    json_extract(payload_json, '$.quantity') AS quantity, json_extract(payload_json, '$.executionPrice') AS execution_price,
                    json_extract(payload_json, '$.fees') AS fees, json_extract(payload_json, '$.cashAmount') AS recorded_amount_quote,
                    json_extract(payload_json, '$.allocatedCost') AS allocated_cost_quote,
                    json_extract(payload_json, '$.rateFromCNY') AS rate_from_cny,
                    json_extract(payload_json, '$.cash.id') AS cash_account_id,
                    json_extract(payload_json, '$.cash.name') AS cash_account_name,
                    json_extract(payload_json, '$.sequence') AS sequence
                FROM position_trades WHERE json_extract(payload_json, '$.reversedAt') IS NULL
                """, limit: 10_000)
            for var row in rows {
                guard let side = row["side"], ["add", "buy", "sell", "withdraw"].contains(side) else { throw MCPFailure.invalidData }
                row["portfolio_flow"] = side == "add" ? "external_in" : side == "withdraw" ? "external_out" : "internal"
                if side == "withdraw" { row["execution_price"] = nil }
                records.append(try Self.record(row, plain: plain, fractional: fractional))
            }
        }
        if tables.contains("position_closures") {
            let rows = try database.query("""
                SELECT id AS record_id, position_id AS asset_id, 'sell' AS side, trade_date,
                    json_extract(payload_json, '$.holding.name') AS name, json_extract(payload_json, '$.holding.symbol') AS symbol,
                    json_extract(payload_json, '$.holding.category') AS category,
                    json_extract(payload_json, '$.holding.quoteCurrency') AS currency,
                    json_extract(payload_json, '$.holding.quantity') AS quantity,
                    json_extract(payload_json, '$.holding.totalCost') AS allocated_cost_quote,
                    json_extract(payload_json, '$.executionPrice') AS execution_price,
                    json_extract(payload_json, '$.fees') AS fees, json_extract(payload_json, '$.netProceeds') AS recorded_amount_quote,
                    json_extract(payload_json, '$.rateFromCNY') AS rate_from_cny,
                    json_extract(payload_json, '$.cashPositionID') AS cash_account_id,
                    json_extract(payload_json, '$.cashName') AS cash_account_name,
                    json_extract(payload_json, '$.recordedAt') AS recorded_at
                FROM position_closures WHERE reversed_at IS NULL
                """, limit: 10_000)
            for var row in rows { row["portfolio_flow"] = "internal"; records.append(try Self.record(row, plain: plain, fractional: fractional)) }
        }
        if tables.contains("position_opening_balances") {
            let rows = try database.query("""
                SELECT position_id AS record_id, position_id AS asset_id, 'opening' AS side,
                    json_extract(payload_json, '$.holding.name') AS name, json_extract(payload_json, '$.holding.symbol') AS symbol,
                    json_extract(payload_json, '$.holding.category') AS category,
                    json_extract(payload_json, '$.holding.quoteCurrency') AS currency,
                    json_extract(payload_json, '$.quantity') AS quantity,
                    json_extract(payload_json, '$.totalCost') AS recorded_amount_quote,
                    json_extract(payload_json, '$.requiresReview') AS requires_review,
                    json_extract(payload_json, '$.recordedAt') AS recorded_at
                FROM position_opening_balances WHERE json_extract(payload_json, '$.reversedAt') IS NULL
                """, limit: 30_000)
            for var row in rows {
                guard let flag = row["requires_review"], ["0", "1"].contains(flag) else { throw MCPFailure.invalidData }
                let review = row["requires_review"] == "1"
                if !review {
                    guard let quantity = Record.decimal(row["quantity"]), quantity >= 0,
                          let cost = Record.decimal(row["recorded_amount_quote"]), cost >= 0,
                          quantity > 0 || cost == 0 else { throw MCPFailure.invalidData }
                    if quantity == 0 { continue }
                }
                row["portfolio_flow"] = "none"
                row["opening_balance_status"] = review ? "needs_review" : "confirmed"
                if review { row["quantity"] = nil; row["recorded_amount_quote"] = nil }
                records.append(try Self.record(row, plain: plain, fractional: fractional))
            }
        }
        self.records = records.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.id < $1.id
        }.reversed()
    }

    private static func record(_ row: [String: String], plain: ISO8601DateFormatter, fractional: ISO8601DateFormatter) throws -> Record {
        guard let id = row["record_id"], UUID(uuidString: id) != nil,
              let asset = row["asset_id"], UUID(uuidString: asset) != nil,
              let name = row["name"], name.count <= 256, let symbol = row["symbol"], symbol.count <= 64,
              row["category"] != nil, let currency = row["currency"], ["CNY", "HKD", "USD", "USDT"].contains(currency),
              let recordedAt = row["recorded_at"], let timestamp = fractional.date(from: recordedAt) ?? plain.date(from: recordedAt) else { throw MCPFailure.invalidData }
        if row["side"] != "opening" {
            guard let units = Record.decimal(row["quantity"]), units > 0,
                  let amount = Record.decimal(row["recorded_amount_quote"]), amount >= 0,
                  let cost = Record.decimal(row["allocated_cost_quote"]), cost >= 0,
                  let rate = Record.decimal(row["rate_from_cny"]), rate > 0,
                  let fee = Record.decimal(row["fees"]), fee >= 0,
                  !((amount - cost) / rate).isNaN else { throw MCPFailure.invalidData }
        }
        return Record(fields: row, timestamp: timestamp, sequence: row["sequence"].flatMap(Int.init) ?? 0)
    }
}
