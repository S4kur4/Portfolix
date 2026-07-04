import Foundation

struct AssetLookupCandidate: Identifiable, Hashable, Sendable {
    let name: String
    let symbol: String
    let category: AssetCategory
    let quoteCurrency: DisplayCurrency
    let latestPrice: Decimal?
    let upstreamSource: String
    var quoteTime: String? = nil

    var id: String {
        "\(category.rawValue):\(symbol)"
    }
}

protocol AssetMarketDataProviding: Sendable {
    func searchAssets(keyword: String) async throws -> [AssetLookupCandidate]
    func resolveAsset(_ candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate
}

enum MarketDataAdapterError: LocalizedError {
    case invalidKeyword
    case assetNotFound
    case unsupportedAsset
    case responseTooLarge
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidKeyword:
            "搜索关键字长度无效"
        case .assetNotFound:
            "未找到对应资产"
        case .unsupportedAsset:
            "该资产暂不支持自动行情"
        case .responseTooLarge:
            "行情数据返回内容超出限制"
        case .invalidResponse:
            "行情数据返回了无效内容"
        case let .requestFailed(message):
            message
        }
    }
}

actor MarketDataAdapter {
    static let shared = MarketDataAdapter()

    private let native: NativeMarketDataAdapter
    private let okx: OKXClient

    init(
        native: NativeMarketDataAdapter = NativeMarketDataAdapter(),
        okx: OKXClient = .shared
    ) {
        self.native = native
        self.okx = okx
    }

    func searchAssets(keyword rawKeyword: String) async throws -> [AssetLookupCandidate] {
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard 1 ... 64 ~= keyword.count else {
            throw MarketDataAdapterError.invalidKeyword
        }

        var candidates = try await native.searchAssets(keyword: keyword)

        var errors: [Error] = []

        if Self.shouldSearchOKXAssets(keyword: keyword) {
            do {
                candidates = try await okx.searchAssets(keyword: keyword) + candidates
            } catch {
                errors.append(error)
            }
        }

        let merged = Self.deduplicated(candidates).prefix(12).map { $0 }
        if !merged.isEmpty {
            return merged
        }
        if let firstError = errors.first {
            throw firstError
        }
        return []
    }

    func searchAssets(keyword rawKeyword: String, category: AssetCategory) async throws -> [AssetLookupCandidate] {
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard 1 ... 64 ~= keyword.count else {
            throw MarketDataAdapterError.invalidKeyword
        }

        switch category {
        case .cash:
            return []
        case .crypto:
            return Self.deduplicated(try await okx.searchAssets(keyword: keyword)).prefix(12).map { $0 }
        case .cnStock, .bStock, .hkStock, .usStock, .fund:
            let candidates = try await native.searchAssets(keyword: keyword)
            return Self.deduplicated(candidates.filter { $0.category == category }).prefix(12).map { $0 }
        }
    }

    func resolveAsset(_ candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate {
        switch candidate.category {
        case .cash:
            return candidate
        case .crypto:
            return try await okx.resolveAsset(candidate)
        case .cnStock, .bStock, .hkStock, .usStock, .fund:
            return try await native.resolveAsset(candidate)
        }
    }

    static func supportsQuoteCategory(_ category: AssetCategory) -> Bool {
        category != .cash
    }

    static func shouldSearchOKXAssets(keyword: String) -> Bool {
        let normalized = keyword
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "/", with: "-")
        guard !normalized.isEmpty else { return false }
        if normalized.contains("USDT") || normalized.contains("-") {
            return true
        }
        return [
            "BTC", "ETH", "SOL", "BNB", "XRP", "DOGE", "ADA", "TRX",
            "AVAX", "DOT", "LINK", "LTC", "BCH", "TON", "OKB",
        ].contains(normalized)
    }

    private static func deduplicated(_ candidates: [AssetLookupCandidate]) -> [AssetLookupCandidate] {
        var seen: Set<AssetLookupCandidate.ID> = []
        var result: [AssetLookupCandidate] = []
        for candidate in candidates where seen.insert(candidate.id).inserted {
            result.append(candidate)
        }
        return result
    }
}

actor NativeMarketDataAdapter: AssetMarketDataProviding {
    private let maximumResponseBytes = 512 * 1024
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)
    }

    func searchAssets(keyword: String) async throws -> [AssetLookupCandidate] {
        var candidates = Self.directSymbolCandidates(keyword: keyword)
        var errors: [Error] = []

        do {
            candidates.append(contentsOf: try await eastmoneySuggestCandidates(keyword: keyword))
        } catch {
            errors.append(error)
        }

        do {
            candidates.append(contentsOf: try await fundSuggestCandidates(keyword: keyword))
        } catch {
            errors.append(error)
        }

        let merged = Self.deduplicated(candidates).prefix(12).map { $0 }
        if !merged.isEmpty {
            return merged
        }
        if let firstError = errors.first {
            throw firstError
        }
        return []
    }

    func resolveAsset(_ candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate {
        switch candidate.category {
        case .cnStock, .bStock, .hkStock, .usStock:
            return try await eastmoneyQuote(for: candidate)
        case .fund:
            return try await fundQuote(for: candidate)
        case .crypto, .cash:
            throw MarketDataAdapterError.unsupportedAsset
        }
    }

    static func directSymbolCandidates(keyword: String) -> [AssetLookupCandidate] {
        let normalized = keyword
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .uppercased()
        guard !normalized.isEmpty else { return [] }

        var candidates: [AssetLookupCandidate] = []

        if normalized.range(of: #"^\d{1,5}\.HK$"#, options: .regularExpression) != nil {
            let symbol = normalizedHKSymbol(normalized)
            candidates.append(
                AssetLookupCandidate(
                    name: symbol,
                    symbol: symbol,
                    category: .hkStock,
                    quoteCurrency: .hkd,
                    latestPrice: nil,
                    upstreamSource: "东方财富"
                )
            )
        }

        if normalized.range(of: #"^(900|200)\d{3}$"#, options: .regularExpression) != nil {
            candidates.append(
                AssetLookupCandidate(
                    name: normalized,
                    symbol: normalized,
                    category: .bStock,
                    quoteCurrency: bShareCurrency(symbol: normalized),
                    latestPrice: nil,
                    upstreamSource: "东方财富"
                )
            )
        }

        if normalized.range(of: #"^\d{6}$"#, options: .regularExpression) != nil, isExchangeTradedFundSymbol(normalized) {
            candidates.append(
                AssetLookupCandidate(
                    name: normalized,
                    symbol: normalized,
                    category: .cnStock,
                    quoteCurrency: .cny,
                    latestPrice: nil,
                    upstreamSource: "东方财富"
                )
            )
        }

        candidates.append(contentsOf: usAliasCandidates(keyword: normalized))

        if normalized.range(of: #"^[A-Z][A-Z0-9.-]{0,11}$"#, options: .regularExpression) != nil {
            let symbol = normalizedUSSymbol(normalized)
            candidates.append(
                AssetLookupCandidate(
                    name: usAliasName(symbol: symbol) ?? symbol,
                    symbol: symbol,
                    category: .usStock,
                    quoteCurrency: .usd,
                    latestPrice: nil,
                    upstreamSource: "东方财富"
                )
            )
        }

        return deduplicated(candidates).prefix(12).map { $0 }
    }

    static func isExchangeTradedFundSymbol(_ value: String) -> Bool {
        value.range(
            of: #"^(159|510|511|512|513|515|516|517|518|520|560|561|562|563|564|588|589)\d{3}$"#,
            options: .regularExpression
        ) != nil
    }

    static func eastmoneySECID(symbol: String, category: AssetCategory) -> String? {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch category {
        case .cnStock:
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
        case .bStock:
            guard normalized.range(of: #"^(900|200)\d{3}$"#, options: .regularExpression) != nil else { return nil }
            return "\(normalized.hasPrefix("900") ? "1" : "0").\(normalized)"
        case .hkStock:
            let code = leadingZeroTrimmed(normalized.replacingOccurrences(of: ".HK", with: ""))
            let padded = String(code.suffix(5)).leftPadded(toLength: 5, withPad: "0")
            return "116.\(padded)"
        case .usStock:
            let symbol = normalizedUSSymbol(normalized)
            guard symbol.range(of: #"^[A-Z][A-Z0-9.-]{0,11}$"#, options: .regularExpression) != nil else { return nil }
            return "105.\(symbol)"
        case .fund:
            guard isExchangeTradedFundSymbol(normalized) else { return nil }
            return "\(normalized.hasPrefix("5") || normalized.hasPrefix("588") || normalized.hasPrefix("589") ? "1" : "0").\(normalized)"
        case .crypto, .cash:
            return nil
        }
    }

    static func candidates(fromEastmoneySuggestData data: Data) throws -> [AssetLookupCandidate] {
        let payload = try JSONDecoder().decode(EastmoneySuggestPayload.self, from: data)
        let rows = payload.quotationCodeTable?.data ?? []
        return deduplicated(rows.compactMap(candidate(from:))).prefix(12).map { $0 }
    }

    static func candidates(fromFundSuggestData data: Data) throws -> [AssetLookupCandidate] {
        let payload = try JSONDecoder().decode(EastmoneyFundSuggestPayload.self, from: data)
        guard payload.errorCode == 0 else {
            throw MarketDataAdapterError.invalidResponse
        }
        return deduplicated(payload.data.compactMap(fundCandidate(from:))).prefix(12).map { $0 }
    }

    static func candidate(
        fromFundGZData data: Data,
        symbol: String,
        fallbackName: String
    ) throws -> AssetLookupCandidate {
        let jsonData = try jsonDataFromJSONP(data, functionName: "jsonpgz")
        let payload = try JSONDecoder().decode(FundGZPayload.self, from: jsonData)
        guard
            let price = Decimal(string: payload.unitNetValue),
            price > 0
        else {
            throw MarketDataAdapterError.invalidResponse
        }
        return AssetLookupCandidate(
            name: payload.name.nonEmpty ?? fallbackName,
            symbol: payload.fundCode.nonEmpty ?? symbol,
            category: .fund,
            quoteCurrency: .cny,
            latestPrice: price,
            upstreamSource: "东方财富",
            quoteTime: payload.netValueDate.nonEmpty
        )
    }

    static func candidate(
        fromFundLatestNetValueData data: Data,
        symbol: String,
        fallbackName: String
    ) throws -> AssetLookupCandidate {
        let payload = try JSONDecoder().decode(EastmoneyFundNetValuePayload.self, from: data)
        guard payload.errorCode == 0 else {
            throw MarketDataAdapterError.invalidResponse
        }
        guard
            let row = payload.data?.netValues.first(where: { ($0.unitNetValue?.decimalValue ?? 0) > 0 }),
            let price = row.unitNetValue?.decimalValue,
            price > 0
        else {
            throw MarketDataAdapterError.invalidResponse
        }
        return AssetLookupCandidate(
            name: fallbackName,
            symbol: symbol,
            category: .fund,
            quoteCurrency: .cny,
            latestPrice: price,
            upstreamSource: "东方财富",
            quoteTime: row.netValueDate.nonEmpty
        )
    }

    private func eastmoneySuggestCandidates(keyword: String) async throws -> [AssetLookupCandidate] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "searchapi.eastmoney.com"
        components.path = "/api/suggest/get"
        components.queryItems = [
            URLQueryItem(name: "input", value: keyword),
            URLQueryItem(name: "type", value: "14"),
            URLQueryItem(name: "token", value: "44c9d251add88e27b65ed86506f6e5da"),
            URLQueryItem(name: "count", value: "12"),
        ]
        return try Self.candidates(fromEastmoneySuggestData: try await request(components: components))
    }

    private func fundSuggestCandidates(keyword: String) async throws -> [AssetLookupCandidate] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "fundsuggest.eastmoney.com"
        components.path = "/FundSearch/api/FundSearchAPI.ashx"
        components.queryItems = [
            URLQueryItem(name: "m", value: "1"),
            URLQueryItem(name: "key", value: keyword),
        ]
        return try Self.candidates(fromFundSuggestData: try await request(components: components))
    }

    private func eastmoneyQuote(for candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate {
        guard let secid = Self.eastmoneySECID(symbol: candidate.symbol, category: candidate.category) else {
            throw MarketDataAdapterError.unsupportedAsset
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "push2.eastmoney.com"
        components.path = "/api/qt/stock/get"
        components.queryItems = [
            URLQueryItem(name: "secid", value: secid),
            URLQueryItem(name: "fields", value: "f43,f57,f58,f59,f86"),
        ]
        guard let url = components.url else {
            throw MarketDataAdapterError.invalidResponse
        }

        let data = try await request(url: url, failureMessage: "东方财富行情请求失败")
        let payload = try JSONDecoder().decode(EastmoneyQuotePayload.self, from: data)
        guard
            let quote = payload.data,
            let rawPrice = quote.rawPrice?.decimalValue,
            rawPrice > 0,
            let price = Self.scaledPrice(rawPrice, precision: quote.precision?.intValue),
            price > 0
        else {
            throw MarketDataAdapterError.assetNotFound
        }

        return AssetLookupCandidate(
            name: quote.name?.nonEmpty ?? candidate.name,
            symbol: Self.displaySymbol(quote.symbol?.nonEmpty ?? candidate.symbol, category: candidate.category),
            category: candidate.category,
            quoteCurrency: Self.quoteCurrency(for: candidate),
            latestPrice: price,
            upstreamSource: "东方财富",
            quoteTime: Self.quoteTime(from: quote.quoteTime)
        )
    }

    private func fundQuote(for candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate {
        if Self.isExchangeTradedFundSymbol(candidate.symbol) {
            do {
                let exchangeCandidate = AssetLookupCandidate(
                    name: candidate.name,
                    symbol: candidate.symbol,
                    category: .cnStock,
                    quoteCurrency: .cny,
                    latestPrice: candidate.latestPrice,
                    upstreamSource: candidate.upstreamSource,
                    quoteTime: candidate.quoteTime
                )
                let quote = try await eastmoneyQuote(for: exchangeCandidate)
                return AssetLookupCandidate(
                    name: quote.name,
                    symbol: quote.symbol,
                    category: .fund,
                    quoteCurrency: .cny,
                    latestPrice: quote.latestPrice,
                    upstreamSource: quote.upstreamSource,
                    quoteTime: quote.quoteTime
                )
            } catch {
                // Some exchange-traded funds are only available through fund endpoints.
            }
        }

        var latestNetValueError: Error?
        do {
            return try await fundLatestNetValueQuote(for: candidate)
        } catch {
            latestNetValueError = error
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "fundgz.1234567.com.cn"
        components.path = "/js/\(candidate.symbol).js"
        do {
            return try Self.candidate(
                fromFundGZData: try await request(components: components),
                symbol: candidate.symbol,
                fallbackName: candidate.name
            )
        } catch {
            let matches = try await fundSuggestCandidates(keyword: candidate.symbol)
            if let exact = matches.first(where: { $0.category == .fund && $0.symbol == candidate.symbol && $0.latestPrice != nil }) {
                return exact
            }
            throw latestNetValueError ?? error
        }
    }

    private func fundLatestNetValueQuote(for candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fund.eastmoney.com"
        components.path = "/f10/lsjz"
        components.queryItems = [
            URLQueryItem(name: "fundCode", value: candidate.symbol),
            URLQueryItem(name: "pageIndex", value: "1"),
            URLQueryItem(name: "pageSize", value: "3"),
            URLQueryItem(name: "startDate", value: ""),
            URLQueryItem(name: "endDate", value: ""),
        ]
        guard let url = components.url else {
            throw MarketDataAdapterError.invalidResponse
        }
        return try Self.candidate(
            fromFundLatestNetValueData: try await request(
                url: url,
                failureMessage: "东方财富基金净值请求失败",
                headers: [
                    "Referer": "https://fundf10.eastmoney.com/",
                    "User-Agent": "Portfolix/0.1",
                ]
            ),
            symbol: candidate.symbol,
            fallbackName: candidate.name
        )
    }

    private func request(components: URLComponents) async throws -> Data {
        guard let url = components.url else {
            throw MarketDataAdapterError.invalidResponse
        }
        return try await request(url: url, failureMessage: "行情请求失败")
    }

    private func request(url: URL, failureMessage: String, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)
        guard data.count <= maximumResponseBytes else {
            throw MarketDataAdapterError.responseTooLarge
        }
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw MarketDataAdapterError.requestFailed(failureMessage)
        }
        return data
    }

    private static func scaledPrice(_ rawPrice: Decimal, precision: Int?) -> Decimal? {
        let precision = precision ?? 2
        guard (0 ... 6).contains(precision) else { return nil }
        var result = rawPrice
        if precision > 0 {
            for _ in 0 ..< precision {
                result /= 10
            }
        }
        return result
    }

    private static func quoteTime(from value: EastmoneyFlexibleNumber?) -> String? {
        guard let decimal = value?.decimalValue else { return nil }
        let number = NSDecimalNumber(decimal: decimal).int64Value
        guard number > 0 else { return nil }
        if number > 2_000_000_000_000 {
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(number) / 1000))
        }
        if number > 1_000_000_000 {
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(number)))
        }
        return nil
    }

    private static func normalizedHKSymbol(_ value: String) -> String {
        let digits = value.uppercased().replacingOccurrences(of: ".HK", with: "")
        return "\(leadingZeroTrimmed(digits).leftPadded(toLength: 4, withPad: "0")).HK"
    }

    private static func normalizedUSSymbol(_ value: String) -> String {
        let symbol = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return symbol.contains(".") ? String(symbol.split(separator: ".").last ?? Substring(symbol)) : symbol
    }

    private static func displaySymbol(_ value: String, category: AssetCategory) -> String {
        switch category {
        case .hkStock:
            normalizedHKSymbol(value)
        case .usStock:
            normalizedUSSymbol(value)
        default:
            value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
    }

    private static func quoteCurrency(for candidate: AssetLookupCandidate) -> DisplayCurrency {
        switch candidate.category {
        case .cnStock, .fund:
            .cny
        case .bStock:
            bShareCurrency(symbol: candidate.symbol)
        case .hkStock:
            .hkd
        case .usStock:
            .usd
        case .crypto:
            candidate.quoteCurrency
        case .cash:
            candidate.quoteCurrency
        }
    }

    private static func candidate(from row: EastmoneySuggestItem) -> AssetLookupCandidate? {
        guard
            let code = row.code?.nonEmpty,
            let name = row.name?.nonEmpty
        else {
            return nil
        }

        switch row.classify {
        case "AStock", "NEEQ":
            return AssetLookupCandidate(
                name: name,
                symbol: code,
                category: .cnStock,
                quoteCurrency: .cny,
                latestPrice: nil,
                upstreamSource: "东方财富"
            )
        case "Fund":
            guard isExchangeTradedFundSymbol(code) else { return nil }
            return AssetLookupCandidate(
                name: name,
                symbol: code,
                category: .cnStock,
                quoteCurrency: .cny,
                latestPrice: nil,
                upstreamSource: "东方财富"
            )
        case "BStock":
            return AssetLookupCandidate(
                name: name,
                symbol: code,
                category: .bStock,
                quoteCurrency: bShareCurrency(symbol: code),
                latestPrice: nil,
                upstreamSource: "东方财富"
            )
        case "HK":
            return AssetLookupCandidate(
                name: name,
                symbol: normalizedHKSymbol(code),
                category: .hkStock,
                quoteCurrency: .hkd,
                latestPrice: nil,
                upstreamSource: "东方财富"
            )
        case "UsStock":
            guard row.securityType == "20" else { return nil }
            return AssetLookupCandidate(
                name: name,
                symbol: normalizedUSSymbol(code),
                category: .usStock,
                quoteCurrency: .usd,
                latestPrice: nil,
                upstreamSource: "东方财富"
            )
        default:
            return nil
        }
    }

    private static func fundCandidate(from row: EastmoneyFundSuggestItem) -> AssetLookupCandidate? {
        guard
            row.category == 700,
            let fundBaseInfo = row.fundBaseInfo,
            let code = row.code.nonEmpty,
            let name = (fundBaseInfo.shortName?.nonEmpty ?? row.name.nonEmpty)
        else {
            return nil
        }
        let category: AssetCategory = isExchangeTradedFundSymbol(code) ? .cnStock : .fund
        let latestPrice: Decimal?
        if category == .fund, let rawNetValue = fundBaseInfo.unitNetValue?.decimalValue, rawNetValue > 0 {
            latestPrice = rawNetValue
        } else {
            latestPrice = nil
        }
        return AssetLookupCandidate(
            name: name,
            symbol: code,
            category: category,
            quoteCurrency: .cny,
            latestPrice: latestPrice,
            upstreamSource: "东方财富",
            quoteTime: category == .fund ? fundBaseInfo.netValueDate : nil
        )
    }

    private static func jsonDataFromJSONP(_ data: Data, functionName: String) throws -> Data {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "\(functionName)("
        guard text.hasPrefix(prefix), text.hasSuffix(");") else {
            throw MarketDataAdapterError.invalidResponse
        }
        let jsonText = String(text.dropFirst(prefix.count).dropLast(2))
        return Data(jsonText.utf8)
    }

    private static func bShareCurrency(symbol: String) -> DisplayCurrency {
        symbol.hasPrefix("900") ? .usd : .hkd
    }

    private static func leadingZeroTrimmed(_ value: String) -> String {
        let trimmed = value.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    private static func usAliasCandidates(keyword: String) -> [AssetLookupCandidate] {
        usStockNameAliases.compactMap { alias, symbol, name in
            guard keyword.localizedCaseInsensitiveContains(alias.uppercased()) || alias.uppercased().localizedCaseInsensitiveContains(keyword) else {
                return nil
            }
            return AssetLookupCandidate(
                name: name,
                symbol: symbol,
                category: .usStock,
                quoteCurrency: .usd,
                latestPrice: nil,
                upstreamSource: "东方财富"
            )
        }
    }

    private static func usAliasName(symbol: String) -> String? {
        usStockNameAliases.first { $0.symbol == symbol }?.name
    }

    private static func deduplicated(_ candidates: [AssetLookupCandidate]) -> [AssetLookupCandidate] {
        var seen: Set<AssetLookupCandidate.ID> = []
        var result: [AssetLookupCandidate] = []
        for candidate in candidates where seen.insert(candidate.id).inserted {
            result.append(candidate)
        }
        return result
    }

    private static let usStockNameAliases: [(alias: String, symbol: String, name: String)] = [
        ("apple", "AAPL", "Apple"),
        ("苹果", "AAPL", "Apple"),
        ("microsoft", "MSFT", "Microsoft"),
        ("微软", "MSFT", "Microsoft"),
        ("nvidia", "NVDA", "Nvidia"),
        ("英伟达", "NVDA", "Nvidia"),
        ("tesla", "TSLA", "Tesla"),
        ("特斯拉", "TSLA", "Tesla"),
        ("amazon", "AMZN", "Amazon"),
        ("亚马逊", "AMZN", "Amazon"),
        ("google", "GOOGL", "Alphabet"),
        ("alphabet", "GOOGL", "Alphabet"),
        ("谷歌", "GOOGL", "Alphabet"),
        ("meta", "META", "Meta"),
        ("facebook", "META", "Meta"),
    ]
}

extension OKXClient: AssetMarketDataProviding {}

private struct EastmoneySuggestPayload: Decodable {
    let quotationCodeTable: EastmoneySuggestTable?

    enum CodingKeys: String, CodingKey {
        case quotationCodeTable = "QuotationCodeTable"
    }
}

private struct EastmoneySuggestTable: Decodable {
    let data: [EastmoneySuggestItem]?

    enum CodingKeys: String, CodingKey {
        case data = "Data"
    }
}

private struct EastmoneySuggestItem: Decodable {
    let code: String?
    let name: String?
    let classify: String?
    let securityTypeName: String?
    let securityType: String?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case name = "Name"
        case classify = "Classify"
        case securityTypeName = "SecurityTypeName"
        case securityType = "SecurityType"
    }
}

private struct EastmoneyFundSuggestPayload: Decodable {
    let errorCode: Int
    let data: [EastmoneyFundSuggestItem]

    enum CodingKeys: String, CodingKey {
        case errorCode = "ErrCode"
        case data = "Datas"
    }
}

private struct EastmoneyFundSuggestItem: Decodable {
    let code: String
    let name: String
    let category: Int?
    let categoryDescription: String?
    let fundBaseInfo: EastmoneyFundBaseInfo?

    enum CodingKeys: String, CodingKey {
        case code = "CODE"
        case name = "NAME"
        case category = "CATEGORY"
        case categoryDescription = "CATEGORYDESC"
        case fundBaseInfo = "FundBaseInfo"
    }
}

private struct EastmoneyFundBaseInfo: Decodable {
    let unitNetValue: EastmoneyFlexibleNumber?
    let netValueDate: String?
    let shortName: String?

    enum CodingKeys: String, CodingKey {
        case unitNetValue = "DWJZ"
        case netValueDate = "FSRQ"
        case shortName = "SHORTNAME"
    }
}

private struct EastmoneyFundNetValuePayload: Decodable {
    let errorCode: Int
    let data: EastmoneyFundNetValueData?

    enum CodingKeys: String, CodingKey {
        case errorCode = "ErrCode"
        case data = "Data"
    }
}

private struct EastmoneyFundNetValueData: Decodable {
    let netValues: [EastmoneyFundNetValueItem]

    enum CodingKeys: String, CodingKey {
        case netValues = "LSJZList"
    }
}

private struct EastmoneyFundNetValueItem: Decodable {
    let netValueDate: String
    let unitNetValue: EastmoneyFlexibleNumber?

    enum CodingKeys: String, CodingKey {
        case netValueDate = "FSRQ"
        case unitNetValue = "DWJZ"
    }
}

private struct FundGZPayload: Decodable {
    let fundCode: String
    let name: String
    let netValueDate: String
    let unitNetValue: String

    enum CodingKeys: String, CodingKey {
        case fundCode = "fundcode"
        case name
        case netValueDate = "jzrq"
        case unitNetValue = "dwjz"
    }
}

private struct EastmoneyQuotePayload: Decodable {
    let data: EastmoneyQuoteData?
}

private struct EastmoneyQuoteData: Decodable {
    let rawPrice: EastmoneyFlexibleNumber?
    let symbol: String?
    let name: String?
    let precision: EastmoneyFlexibleNumber?
    let quoteTime: EastmoneyFlexibleNumber?

    enum CodingKeys: String, CodingKey {
        case rawPrice = "f43"
        case symbol = "f57"
        case name = "f58"
        case precision = "f59"
        case quoteTime = "f86"
    }
}

private enum EastmoneyFlexibleNumber: Decodable {
    case decimal(Decimal)

    var decimalValue: Decimal {
        switch self {
        case let .decimal(value):
            value
        }
    }

    var intValue: Int {
        NSDecimalNumber(decimal: decimalValue).intValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .decimal(Decimal(intValue))
            return
        }
        if let doubleValue = try? container.decode(Double.self), doubleValue.isFinite {
            self = .decimal(Decimal(doubleValue))
            return
        }
        if
            let stringValue = try? container.decode(String.self),
            let decimal = Decimal(string: stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            self = .decimal(decimal)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a numeric value")
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func leftPadded(toLength length: Int, withPad pad: Character) -> String {
        guard count < length else { return self }
        return String(repeating: String(pad), count: length - count) + self
    }
}
