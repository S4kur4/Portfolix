import CSQLite
import Foundation

@main
struct PortfolixPriceUpdater {
    static func main() async {
        let updater = BackgroundPriceUpdater()
        let runOnceOnly = CommandLine.arguments.contains("--once")
        repeat {
            do {
                try await updater.runOnce()
            } catch {
                try? updater.recordHealth(
                    [
                        DataSourceHealth(
                            name: "后台价格更新",
                            detail: String(error.localizedDescription.prefix(64)),
                            symbol: "exclamationmark.triangle.fill",
                            state: "连接异常",
                            colorKey: "danger",
                            order: 99
                        ),
                    ]
                )
            }

            if runOnceOnly { return }
            guard (try? updater.automaticUpdatesEnabled()) == true else { return }
            let delay = (try? updater.nextUpdateDelaySeconds()) ?? 60 * 60
            try? await Task.sleep(for: .seconds(delay))
        } while !Task.isCancelled
    }
}

private final class BackgroundPriceUpdater {
    private let database: OpaquePointer
    private let databaseURL: URL
    private let maximumResponseBytes = 512 * 1024

    init(databaseURL: URL = BackgroundPriceUpdater.defaultDatabaseURL()) {
        self.databaseURL = databaseURL
        var handle: OpaquePointer?
        sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        database = handle!
        try? migrateSupportTables()
    }

    deinit {
        sqlite3_close(database)
    }

    func runOnce() async throws {
        guard try automaticUpdatesEnabled() else { return }
        let positions = try fetchPositions()
        guard !positions.isEmpty else {
            try recordHealth([
                .unused(name: "东方财富", detail: "暂无需自动获取价格的持仓", order: 0),
                .unused(name: "OKX", detail: "暂无数字货币持仓", order: 1),
            ])
            return
        }

        var updated = positions
        var health: [DataSourceHealth] = []
        var sourceErrors: [String: String] = [:]
        var sourceSuccessCounts: [String: Int] = [:]
        var usedSources: Set<String> = []

        for index in updated.indices {
            do {
                switch updated[index].category {
                case "A 股", "B 股", "港股", "美股", "公募基金":
                    let quote = try await resolveNativeQuote(for: updated[index])
                    updated[index].latestPrice = quote.price
                    updated[index].source = quote.source
                    updated[index].freshness = "已更新"
                    updated[index].quoteTime = quote.quoteTime ?? Self.quoteTime()
                    sourceSuccessCounts[quote.source, default: 0] += 1
                    usedSources.insert(quote.source)
                case "数字货币":
                    usedSources.insert("OKX")
                    let okxQuote = try await resolveOKXQuote(symbol: updated[index].symbol)
                    let quote = (price: okxQuote.price, quoteTime: okxQuote.quoteTime, source: "OKX")
                    updated[index].latestPrice = quote.price
                    updated[index].source = quote.source
                    updated[index].freshness = "已更新"
                    updated[index].quoteTime = quote.quoteTime ?? Self.quoteTime()
                    sourceSuccessCounts[quote.source, default: 0] += 1
                    usedSources.insert(quote.source)
                default:
                    continue
                }
                try updateLatestQuote(updated[index])
            } catch {
                let source = Self.primarySource(for: updated[index].category)
                usedSources.insert(source)
                if sourceErrors[source] == nil {
                    sourceErrors[source] = error.localizedDescription
                }
            }
        }

        try replaceDailySnapshots(positions: updated)

        for source in Self.orderedDataSources where usedSources.contains(source) {
            health.append(
                DataSourceHealth.from(
                    error: sourceErrors[source],
                    hasSuccess: (sourceSuccessCounts[source] ?? 0) > 0,
                    name: source,
                    detail: Self.detail(for: source),
                    order: Self.order(for: source)
                )
            )
        }
        if !positions.contains(where: { ["A 股", "B 股", "港股", "美股", "公募基金"].contains($0.category) }) {
            health.append(.unused(name: "东方财富", detail: "暂无需自动获取价格的持仓", order: Self.order(for: "东方财富")))
        }
        if !positions.contains(where: { $0.category == "数字货币" }) {
            health.append(.unused(name: "OKX", detail: "暂无数字货币持仓", order: Self.order(for: "OKX")))
        }
        try recordHealth(health)
    }

    func automaticUpdatesEnabled() throws -> Bool {
        guard let value = try appSettingValue(for: "automatic_price_updates_enabled") else {
            return false
        }
        return value == "true"
    }

    func nextUpdateDelaySeconds(now: Date = .now) throws -> Int {
        let frequency = try appSettingValue(for: "automatic_price_update_frequency") ?? "1 小时"
        switch frequency {
        case "5 分钟":
            return 5 * 60
        case "15 分钟":
            return 15 * 60
        case "30 分钟":
            return 30 * 60
        case "4 小时":
            return 4 * 60 * 60
        case "8 小时":
            return 8 * 60 * 60
        case "每日", "每日固定时间":
            return nextDailyDelaySeconds(now: now)
        default:
            return 60 * 60
        }
    }

    private func appSettingValue(for key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM app_settings WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(key, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(at: 0, in: statement)
    }

    private func nextDailyDelaySeconds(now: Date) -> Int {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0
        components.second = 0

        var nextDate = calendar.date(from: components) ?? now
        if nextDate <= now {
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? now.addingTimeInterval(24 * 60 * 60)
        }
        return max(60, Int(nextDate.timeIntervalSince(now)))
    }

    func recordHealth(_ statuses: [DataSourceHealth]) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("DELETE FROM data_source_health")
            for status in statuses {
                let statement = try prepare(
                    """
                    INSERT INTO data_source_health (
                        name, detail, symbol, state, color_key, checked_at, display_order
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """
                )
                defer { sqlite3_finalize(statement) }
                try bind(status.name, to: 1, in: statement)
                try bind(status.detail, to: 2, in: statement)
                try bind(status.symbol, to: 3, in: statement)
                try bind(status.state, to: 4, in: statement)
                try bind(status.colorKey, to: 5, in: statement)
                try bind(Self.timestamp(), to: 6, in: statement)
                try bind(status.order, to: 7, in: statement)
                try stepDone(statement)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func fetchPositions() throws -> [StoredPosition] {
        let statement = try prepare(
            """
            SELECT p.id, a.name, a.symbol, a.category, a.quote_currency, p.quantity,
                   p.average_cost, q.price, q.source, q.quote_time, q.freshness, q.weekly_trend_json
            FROM positions p
            JOIN assets a ON a.id = p.asset_id
            JOIN latest_quotes q ON q.asset_id = a.id
            ORDER BY p.created_at, a.name
            """
        )
        defer { sqlite3_finalize(statement) }

        var positions: [StoredPosition] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            positions.append(
                StoredPosition(
                    id: text(at: 0, in: statement),
                    name: text(at: 1, in: statement),
                    symbol: text(at: 2, in: statement),
                    category: text(at: 3, in: statement),
                    currency: text(at: 4, in: statement),
                    quantity: Double(text(at: 5, in: statement)) ?? 0,
                    averageCost: Double(text(at: 6, in: statement)) ?? 0,
                    latestPrice: Double(text(at: 7, in: statement)) ?? 0,
                    source: text(at: 8, in: statement),
                    quoteTime: text(at: 9, in: statement),
                    freshness: text(at: 10, in: statement),
                    weeklyTrendJSON: text(at: 11, in: statement)
                )
            )
        }
        return positions
    }

    private func updateLatestQuote(_ position: StoredPosition) throws {
        var trend = (try? JSONDecoder().decode([Double].self, from: Data(position.weeklyTrendJSON.utf8))) ?? []
        if trend.isEmpty {
            trend = Array(repeating: position.latestPrice, count: 7)
        } else {
            trend = Array(trend.dropFirst() + [position.latestPrice])
        }
        let trendJSON = String(data: try JSONEncoder().encode(trend), encoding: .utf8) ?? "[]"
        let statement = try prepare(
            """
            UPDATE latest_quotes
            SET price = ?, source = ?, quote_time = ?, fetched_at = ?, freshness = ?, weekly_trend_json = ?
            WHERE asset_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(Self.numberString(position.latestPrice), to: 1, in: statement)
        try bind(position.source, to: 2, in: statement)
        try bind(position.quoteTime, to: 3, in: statement)
        try bind(Self.timestamp(), to: 4, in: statement)
        try bind(position.freshness, to: 5, in: statement)
        try bind(trendJSON, to: 6, in: statement)
        try bind(position.id, to: 7, in: statement)
        try stepDone(statement)
    }

    private func replaceDailySnapshots(positions: [StoredPosition]) throws {
        let day = Self.dayString()
        let totalValue = positions.reduce(0.0) { $0 + $1.marketValueCNY }
        let totalCost = positions.reduce(0.0) { $0 + $1.totalCostCNY }
        let profit = totalValue - totalCost
        let profitRate = totalCost == 0 ? 0 : profit / totalCost * 100

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let statement = try prepare(
                """
                INSERT INTO portfolio_snapshots (
                    snapshot_date, total_value_cny, total_cost_cny, total_profit_cny, profit_rate, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(snapshot_date) DO UPDATE SET
                    total_value_cny = excluded.total_value_cny,
                    total_cost_cny = excluded.total_cost_cny,
                    total_profit_cny = excluded.total_profit_cny,
                    profit_rate = excluded.profit_rate,
                    updated_at = excluded.updated_at
                """
            )
            defer { sqlite3_finalize(statement) }
            try bind(day, to: 1, in: statement)
            try bind(Self.numberString(totalValue), to: 2, in: statement)
            try bind(Self.numberString(totalCost), to: 3, in: statement)
            try bind(Self.numberString(profit), to: 4, in: statement)
            try bind(Self.numberString(profitRate), to: 5, in: statement)
            try bind(Self.timestamp(), to: 6, in: statement)
            try stepDone(statement)

            for position in positions {
                let assetStatement = try prepare(
                    """
                    INSERT INTO asset_price_snapshots (
                        id, asset_id, snapshot_date, name, symbol, category, quote_currency,
                        quantity, average_cost, latest_price, market_value_cny,
                        source, quote_time, freshness, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(asset_id, snapshot_date) DO UPDATE SET
                        latest_price = excluded.latest_price,
                        market_value_cny = excluded.market_value_cny,
                        source = excluded.source,
                        quote_time = excluded.quote_time,
                        freshness = excluded.freshness,
                        updated_at = excluded.updated_at
                    """
                )
                defer { sqlite3_finalize(assetStatement) }
                try bind("\(position.id)-\(day)", to: 1, in: assetStatement)
                try bind(position.id, to: 2, in: assetStatement)
                try bind(day, to: 3, in: assetStatement)
                try bind(position.name, to: 4, in: assetStatement)
                try bind(position.symbol, to: 5, in: assetStatement)
                try bind(position.category, to: 6, in: assetStatement)
                try bind(position.currency, to: 7, in: assetStatement)
                try bind(Self.numberString(position.quantity), to: 8, in: assetStatement)
                try bind(Self.numberString(position.averageCost), to: 9, in: assetStatement)
                try bind(Self.numberString(position.latestPrice), to: 10, in: assetStatement)
                try bind(Self.numberString(position.marketValueCNY), to: 11, in: assetStatement)
                try bind(position.source, to: 12, in: assetStatement)
                try bind(position.quoteTime, to: 13, in: assetStatement)
                try bind(position.freshness, to: 14, in: assetStatement)
                try bind(Self.timestamp(), to: 15, in: assetStatement)
                try stepDone(assetStatement)
            }
            try execute("DELETE FROM portfolio_snapshots WHERE snapshot_date < date('now', '-365 day')")
            try execute("DELETE FROM asset_price_snapshots WHERE snapshot_date < date('now', '-365 day')")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func resolveOKXQuote(symbol: String) async throws -> (price: Double, quoteTime: String?) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.okx.com"
        components.path = "/api/v5/market/ticker"
        components.queryItems = [URLQueryItem(name: "instId", value: symbol.replacingOccurrences(of: "/", with: "-"))]
        guard let url = components.url else { throw UpdaterError.invalidResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 300 else { throw UpdaterError.requestFailed("OKX 请求失败") }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataArray = object?["data"] as? [[String: Any]]
        guard
            let last = dataArray?.first?["last"] as? String,
            let price = Double(last),
            price > 0
        else { throw UpdaterError.invalidResponse }
        let quoteTime = (dataArray?.first?["ts"] as? String).flatMap(Self.quoteTime(fromMilliseconds:))
        return (price, quoteTime)
    }

    private func resolveNativeQuote(for position: StoredPosition) async throws -> (price: Double, quoteTime: String?, source: String) {
        if position.category == "公募基金" {
            if Self.isExchangeTradedFundSymbol(position.symbol),
               let quote = try? await resolveEastmoneyQuote(symbol: position.symbol, category: "A 股")
            {
                return quote
            }
            return try await resolveFundQuote(symbol: position.symbol, fallbackName: position.name)
        }
        return try await resolveEastmoneyQuote(symbol: position.symbol, category: position.category)
    }

    private func resolveEastmoneyQuote(symbol: String, category: String) async throws -> (price: Double, quoteTime: String?, source: String) {
        guard let secid = Self.eastmoneySECID(symbol: symbol, category: category) else {
            throw UpdaterError.requestFailed("该资产暂不支持自动行情")
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "push2.eastmoney.com"
        components.path = "/api/qt/stock/get"
        components.queryItems = [
            URLQueryItem(name: "secid", value: secid),
            URLQueryItem(name: "fields", value: "f43,f57,f58,f59,f86"),
        ]
        guard let url = components.url else { throw UpdaterError.invalidResponse }
        let data = try await request(url: url, failureMessage: "东方财富行情请求失败")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let quote = object?["data"] as? [String: Any]
        guard
            let rawPrice = Self.numberValue(quote?["f43"]),
            rawPrice > 0
        else { throw UpdaterError.invalidResponse }
        let precision = Int(Self.numberValue(quote?["f59"]) ?? 2)
        guard (0 ... 6).contains(precision) else { throw UpdaterError.invalidResponse }
        let price = rawPrice / pow(10.0, Double(precision))
        guard price > 0 else { throw UpdaterError.invalidResponse }
        let quoteTime = Self.numberValue(quote?["f86"]).flatMap(Self.quoteTime(fromSeconds:))
        return (price, quoteTime, "东方财富")
    }

    private func resolveFundQuote(symbol: String, fallbackName: String) async throws -> (price: Double, quoteTime: String?, source: String) {
        if let quote = try? await resolveFundLatestNetValueQuote(symbol: symbol, fallbackName: fallbackName) {
            return quote
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "fundgz.1234567.com.cn"
        components.path = "/js/\(symbol).js"
        guard let url = components.url else { throw UpdaterError.invalidResponse }
        let data = try await request(url: url, failureMessage: "东方财富基金净值请求失败")
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "jsonpgz("
        guard text.hasPrefix(prefix), text.hasSuffix(");") else { throw UpdaterError.invalidResponse }
        let jsonText = String(text.dropFirst(prefix.count).dropLast(2))
        let object = try JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any]
        guard
            let priceText = object?["dwjz"] as? String,
            let price = Double(priceText),
            price > 0
        else { throw UpdaterError.invalidResponse }
        return (price, object?["jzrq"] as? String, "东方财富")
    }

    private func resolveFundLatestNetValueQuote(symbol: String, fallbackName _: String) async throws -> (price: Double, quoteTime: String?, source: String) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fund.eastmoney.com"
        components.path = "/f10/lsjz"
        components.queryItems = [
            URLQueryItem(name: "fundCode", value: symbol),
            URLQueryItem(name: "pageIndex", value: "1"),
            URLQueryItem(name: "pageSize", value: "3"),
            URLQueryItem(name: "startDate", value: ""),
            URLQueryItem(name: "endDate", value: ""),
        ]
        guard let url = components.url else { throw UpdaterError.invalidResponse }
        let data = try await request(
            url: url,
            failureMessage: "东方财富基金净值请求失败",
            headers: [
                "Referer": "https://fundf10.eastmoney.com/",
                "User-Agent": "Portfolix/0.1",
            ]
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let errorCode = Self.numberValue(object?["ErrCode"]), Int(errorCode) != 0 {
            throw UpdaterError.invalidResponse
        }
        let payload = object?["Data"] as? [String: Any]
        let rows = payload?["LSJZList"] as? [[String: Any]] ?? []
        for row in rows {
            guard let price = Self.numberValue(row["DWJZ"]), price > 0 else { continue }
            return (price, row["FSRQ"] as? String, "东方财富")
        }
        throw UpdaterError.invalidResponse
    }

    private func request(url: URL, failureMessage: String, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard data.count <= maximumResponseBytes else {
            throw UpdaterError.requestFailed("行情数据返回内容超出限制")
        }
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw UpdaterError.requestFailed(failureMessage)
        }
        return data
    }

    private static let orderedDataSources = ["东方财富", "OKX"]

    private static func primarySource(for category: String) -> String {
        switch category {
        case "A 股", "B 股", "港股", "美股", "公募基金":
            return "东方财富"
        case "数字货币":
            return "OKX"
        default:
            return "东方财富"
        }
    }

    private static func detail(for source: String) -> String {
        switch source {
        case "东方财富":
            return "股票、基金与跨市场行情"
        case "OKX":
            return "数字货币现货交易对"
        default:
            return "行情数据"
        }
    }

    private static func order(for source: String) -> Int {
        switch source {
        case "东方财富":
            return 0
        case "OKX":
            return 1
        default:
            return 99
        }
    }

    private static func eastmoneySECID(symbol: String, category: String) -> String? {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch category {
        case "A 股":
            guard normalized.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else { return nil }
            if isExchangeTradedFundSymbol(normalized) {
                return "\(normalized.hasPrefix("5") || normalized.hasPrefix("588") || normalized.hasPrefix("589") ? "1" : "0").\(normalized)"
            }
            if normalized.hasPrefix("6") {
                return "1.\(normalized)"
            }
            if normalized.hasPrefix("0") || normalized.hasPrefix("3") || normalized.hasPrefix("4") || normalized.hasPrefix("8") || normalized.hasPrefix("9") {
                return "0.\(normalized)"
            }
            return nil
        case "B 股":
            guard normalized.range(of: #"^(900|200)\d{3}$"#, options: .regularExpression) != nil else { return nil }
            return "\(normalized.hasPrefix("900") ? "1" : "0").\(normalized)"
        case "港股":
            let code = leadingZeroTrimmed(normalized.replacingOccurrences(of: ".HK", with: ""))
            let padded = String(code.suffix(5)).leftPadded(toLength: 5, withPad: "0")
            return "116.\(padded)"
        case "美股":
            let symbol = normalizedUSSymbol(normalized)
            guard symbol.range(of: #"^[A-Z][A-Z0-9.-]{0,11}$"#, options: .regularExpression) != nil else { return nil }
            return "105.\(symbol)"
        default:
            return nil
        }
    }

    private static func isExchangeTradedFundSymbol(_ value: String) -> Bool {
        value.range(
            of: #"^(159|510|511|512|513|515|516|517|518|520|560|561|562|563|564|588|589)\d{3}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func normalizedUSSymbol(_ value: String) -> String {
        let symbol = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return symbol.contains(".") ? String(symbol.split(separator: ".").last ?? Substring(symbol)) : symbol
    }

    private static func leadingZeroTrimmed(_ value: String) -> String {
        let trimmed = value.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    private static func numberValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value.isFinite ? value : nil
        case let value as Int:
            return Double(value)
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func quoteTime(fromSeconds value: Double) -> String? {
        guard value.isFinite, value > 0 else { return nil }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: value))
    }

    private static func normalizedQuoteSource(_ value: String?) -> String {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized.lowercased() {
        case "okx", "OKX":
            return "OKX"
        case "local", "手工价格":
            return "手工价格"
        case "eastmoney", "em", "东方财富", "东财":
            return "东方财富"
        case "sina", "新浪", "新浪财经":
            return "新浪财经"
        case "ths", "tonghuashun", "同花顺":
            return "同花顺"
        case "tencent", "tx", "腾讯", "腾讯财经":
            return "腾讯财经"
        case "jin10", "金十", "金十数据":
            return "金十数据"
        default:
            if normalized.isEmpty {
                return "东方财富"
            }
            if normalized.localizedCaseInsensitiveContains("okx") {
                return "OKX"
            }
            if normalized.localizedCaseInsensitiveContains("sina") || normalized.contains("新浪") {
                return "新浪财经"
            }
            if normalized.localizedCaseInsensitiveContains("eastmoney") || normalized.contains("东方财富") {
                return "东方财富"
            }
            if normalized.localizedCaseInsensitiveContains("tonghuashun") || normalized.localizedCaseInsensitiveContains("ths") || normalized.contains("同花顺") {
                return "同花顺"
            }
            if normalized.localizedCaseInsensitiveContains("jin10") || normalized.contains("金十") {
                return "金十数据"
            }
            return normalized
        }
    }

    private func migrateSupportTables() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS data_source_health (
                name TEXT PRIMARY KEY NOT NULL,
                detail TEXT NOT NULL,
                symbol TEXT NOT NULL,
                state TEXT NOT NULL,
                color_key TEXT NOT NULL,
                checked_at TEXT NOT NULL,
                display_order INTEGER NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
    }

    private func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
            let error = message.map { String(cString: $0) } ?? "未知数据库错误"
            sqlite3_free(message)
            throw UpdaterError.requestFailed(error)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw UpdaterError.requestFailed(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw UpdaterError.requestFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(_ value: Int, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int(statement, index, Int32(value)) == SQLITE_OK else {
            throw UpdaterError.requestFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UpdaterError.requestFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func text(at index: Int32, in statement: OpaquePointer) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private static func defaultDatabaseURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["PORTFOLIX_DATABASE_PATH"] {
            return URL(fileURLWithPath: overridePath)
        }
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return baseURL
            .appendingPathComponent(applicationSupportFolderName(), isDirectory: true)
            .appendingPathComponent("portfolix.sqlite3")
    }

    private static func applicationSupportFolderName() -> String {
        let fallback = "app.portfolix.mac"
        let identifier = Bundle.main.bundleIdentifier ?? fallback
        let helperSuffix = ".PriceUpdater"
        let normalizedIdentifier = identifier.hasSuffix(helperSuffix)
            ? String(identifier.dropLast(helperSuffix.count))
            : identifier
        return normalizedIdentifier.isEmpty ? fallback : normalizedIdentifier
    }

    private static func numberString(_ value: Double) -> String {
        String(format: "%.8f", value)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: .now)
    }

    private static func dayString() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    private static func quoteTime() -> String {
        ISO8601DateFormatter().string(from: .now)
    }

    private static func quoteTime(fromMilliseconds value: String) -> String? {
        guard let milliseconds = TimeInterval(value) else { return nil }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }
}

private struct StoredPosition {
    let id: String
    let name: String
    let symbol: String
    let category: String
    let currency: String
    let quantity: Double
    let averageCost: Double
    var latestPrice: Double
    var source: String
    var quoteTime: String
    var freshness: String
    let weeklyTrendJSON: String

    var marketValueCNY: Double {
        quantity * latestPrice / rateFromCNY
    }

    var totalCostCNY: Double {
        quantity * averageCost / rateFromCNY
    }

    private var rateFromCNY: Double {
        switch currency {
        case "HKD": 1.153431425
        case "USD": 0.147215543
        case "USDT": 0.147289188
        default: 1
        }
    }
}

private struct DataSourceHealth {
    let name: String
    let detail: String
    let symbol: String
    let state: String
    let colorKey: String
    let order: Int

    static func unused(name: String, detail: String, order: Int) -> DataSourceHealth {
        DataSourceHealth(name: name, detail: detail, symbol: "pause.circle.fill", state: "未使用", colorKey: "tertiary", order: order)
    }

    static func from(error: String?, hasSuccess: Bool, name: String, detail: String, order: Int) -> DataSourceHealth {
        if let error {
            if hasSuccess {
                return DataSourceHealth(
                    name: name,
                    detail: String(error.prefix(64)),
                    symbol: "exclamationmark.triangle.fill",
                    state: "部分异常",
                    colorKey: "amber",
                    order: order
                )
            }
            return DataSourceHealth(
                name: name,
                detail: String(error.prefix(64)),
                symbol: "exclamationmark.triangle.fill",
                state: "连接异常",
                colorKey: "danger",
                order: order
            )
        }
        return DataSourceHealth(
            name: name,
            detail: detail,
            symbol: normalSymbol(for: name),
            state: "连接正常",
            colorKey: "mint",
            order: order
        )
    }

    private static func normalSymbol(for name: String) -> String {
        switch name {
        case "东方财富", "新浪财经", "同花顺", "腾讯财经":
            "chart.line.uptrend.xyaxis"
        case "金十数据":
            "chart.bar.doc.horizontal"
        case "OKX":
            "okx"
        default:
            "checkmark.circle.fill"
        }
    }
}

private enum UpdaterError: LocalizedError {
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "行情响应无效"
        case let .requestFailed(message):
            message
        }
    }
}

private extension String {
    func leftPadded(toLength length: Int, withPad pad: Character) -> String {
        guard count < length else { return self }
        return String(repeating: String(pad), count: length - count) + self
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
