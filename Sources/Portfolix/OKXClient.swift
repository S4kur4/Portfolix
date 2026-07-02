import Foundation

enum OKXClientError: LocalizedError {
    case invalidResponse
    case responseTooLarge
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "OKX 返回了无效数据"
        case .responseTooLarge:
            "OKX 返回内容超出限制"
        case let .requestFailed(message):
            message
        }
    }
}

actor OKXClient {
    static let shared = OKXClient()

    private let maximumResponseBytes = 16 * 1024 * 1024
    private let instrumentCacheLifetime: TimeInterval = 7 * 24 * 60 * 60
    private let instrumentCacheURL: URL
    private var instrumentCache: (loadedAt: Date, instruments: [OKXSpotInstrument])?
    private let session: URLSession

    init() {
        instrumentCacheURL = Self.defaultInstrumentCacheURL()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func searchAssets(keyword: String) async throws -> [AssetLookupCandidate] {
        let instruments = try await fetchInstruments(useCache: true)
        return Self.candidates(matching: keyword, in: instruments)
    }

    func resolveAsset(_ candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate {
        guard candidate.category == .crypto else {
            throw OKXClientError.invalidResponse
        }

        let data = try await request(
            path: "/api/v5/market/ticker",
            queryItems: [
                URLQueryItem(name: "instId", value: candidate.symbol.replacingOccurrences(of: "/", with: "-")),
            ]
        )
        let response: OKXEnvelope<OKXTicker> = try Self.decodeEnvelope(from: data)
        guard
            let ticker = response.data.first,
            let price = Decimal(string: ticker.last),
            price > 0
        else {
            throw OKXClientError.invalidResponse
        }

        return AssetLookupCandidate(
            name: candidate.name,
            symbol: candidate.symbol,
            category: .crypto,
            quoteCurrency: candidate.quoteCurrency,
            latestPrice: price,
            upstreamSource: "OKX",
            quoteTime: Self.quoteTime(fromMilliseconds: ticker.ts)
        )
    }

    static func candidates(
        matching keyword: String,
        in instruments: [OKXSpotInstrument]
    ) -> [AssetLookupCandidate] {
        let normalizedKeyword = keyword
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "/", with: "-")
        guard !normalizedKeyword.isEmpty else { return [] }

        return instruments
            .filter {
                $0.instId.localizedCaseInsensitiveContains(normalizedKeyword)
                    || $0.baseCcy.localizedCaseInsensitiveContains(normalizedKeyword)
            }
            .compactMap(candidate)
            .sorted {
                candidateRank($0, keyword: normalizedKeyword) < candidateRank($1, keyword: normalizedKeyword)
            }
            .prefix(12)
            .map { $0 }
    }

    static func decodeInstruments(from data: Data) throws -> [OKXSpotInstrument] {
        let response: OKXEnvelope<OKXSpotInstrument> = try decodeEnvelope(from: data)
        return try validatedInstruments(response.data)
    }

    private func fetchInstruments(useCache: Bool) async throws -> [OKXSpotInstrument] {
        if
            useCache,
            let instrumentCache,
            Date().timeIntervalSince(instrumentCache.loadedAt) < instrumentCacheLifetime
        {
            return instrumentCache.instruments
        }
        if
            useCache,
            let persistedCache = loadPersistedInstrumentCache(),
            Date().timeIntervalSince(persistedCache.loadedAt) < instrumentCacheLifetime
        {
            instrumentCache = persistedCache
            return persistedCache.instruments
        }

        let data = try await request(
            path: "/api/v5/public/instruments",
            queryItems: [
                URLQueryItem(name: "instType", value: "SPOT"),
            ]
        )
        let instruments = try Self.decodeInstruments(from: data)
        let loadedAt = Date.now
        instrumentCache = (loadedAt, instruments)
        persistInstrumentCache(instruments, loadedAt: loadedAt)
        return instruments
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.okx.com"
        components.path = path
        components.queryItems = queryItems
        guard let url = components.url else {
            throw OKXClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard data.count <= maximumResponseBytes else {
            throw OKXClientError.responseTooLarge
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OKXClientError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw OKXClientError.requestFailed(Self.errorMessage(from: data))
        }
        return data
    }

    private func loadPersistedInstrumentCache() -> (loadedAt: Date, instruments: [OKXSpotInstrument])? {
        guard
            let data = try? Data(contentsOf: instrumentCacheURL),
            data.count <= maximumResponseBytes,
            let payload = try? JSONDecoder().decode(OKXInstrumentCache.self, from: data),
            let instruments = try? Self.validatedInstruments(payload.instruments)
        else {
            return nil
        }
        return (payload.loadedAt, instruments)
    }

    private func persistInstrumentCache(_ instruments: [OKXSpotInstrument], loadedAt: Date) {
        do {
            let fileManager = FileManager.default
            let directoryURL = instrumentCacheURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)

            let payload = OKXInstrumentCache(loadedAt: loadedAt, instruments: instruments)
            let data = try JSONEncoder().encode(payload)
            guard data.count <= maximumResponseBytes else { return }
            try data.write(to: instrumentCacheURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: instrumentCacheURL.path)
        } catch {
            // Cache persistence is optional. Valid network results remain usable.
        }
    }

    private static func defaultInstrumentCacheURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        return baseURL
            .appendingPathComponent("Portfolix", isDirectory: true)
            .appendingPathComponent("okx-spot-instruments.json")
    }

    private static func decodeEnvelope<T: Decodable>(from data: Data) throws -> OKXEnvelope<T> {
        let response = try JSONDecoder().decode(OKXEnvelope<T>.self, from: data)
        guard response.code == "0" else {
            throw OKXClientError.requestFailed(String(response.msg.prefix(180)))
        }
        return response
    }

    private static func validatedInstruments(_ rawInstruments: [OKXSpotInstrument]) throws -> [OKXSpotInstrument] {
        let instruments = rawInstruments.filter {
            $0.instId.count <= 32
                && $0.baseCcy.count <= 16
                && $0.quoteCcy.count <= 16
                && $0.state == "live"
                && $0.instId.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                && $0.baseCcy.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
                && $0.quoteCcy.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
        guard !instruments.isEmpty else {
            throw OKXClientError.invalidResponse
        }
        return instruments
    }

    private static func candidate(from instrument: OKXSpotInstrument) -> AssetLookupCandidate? {
        let currency: DisplayCurrency
        switch instrument.quoteCcy {
        case "USDT":
            currency = .usdt
        case "USD":
            currency = .usd
        default:
            return nil
        }
        return AssetLookupCandidate(
            name: instrument.baseCcy,
            symbol: instrument.instId.replacingOccurrences(of: "-", with: "/"),
            category: .crypto,
            quoteCurrency: currency,
            latestPrice: nil,
            upstreamSource: "OKX"
        )
    }

    private static func quoteTime(fromMilliseconds value: String) -> String? {
        guard let milliseconds = TimeInterval(value) else { return nil }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }

    private static func candidateRank(_ candidate: AssetLookupCandidate, keyword: String) -> (Int, String) {
        let normalizedSymbol = candidate.symbol.replacingOccurrences(of: "/", with: "-")
        let rank: Int
        if normalizedSymbol == keyword || candidate.name == keyword {
            rank = 0
        } else if normalizedSymbol == "\(keyword)-USDT" {
            rank = 1
        } else if normalizedSymbol.hasPrefix("\(keyword)-") {
            rank = 2
        } else {
            rank = 3
        }
        return (rank, candidate.symbol)
    }

    private static func errorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return "OKX 请求失败，请稍后重试"
        }
        let rawMessage = dictionary["msg"] as? String
            ?? dictionary["message"] as? String
            ?? "OKX 请求失败，请稍后重试"
        return String(rawMessage.prefix(180))
    }
}

struct OKXSpotInstrument: Codable {
    let instId: String
    let baseCcy: String
    let quoteCcy: String
    let state: String
}

private struct OKXTicker: Decodable {
    let last: String
    let ts: String
}

private struct OKXEnvelope<T: Decodable>: Decodable {
    let code: String
    let msg: String
    let data: [T]
}

private struct OKXInstrumentCache: Codable {
    let loadedAt: Date
    let instruments: [OKXSpotInstrument]
}
