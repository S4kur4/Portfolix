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

enum AKShareBridgeError: LocalizedError {
    case helperUnavailable
    case timeout
    case invalidResponse
    case outputTooLarge
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            "本地行情组件尚未配置，可继续手工填写"
        case .timeout:
            "本地行情组件查询超时，可稍后重试或手工填写"
        case .invalidResponse:
            "本地行情组件返回了无效数据"
        case .outputTooLarge:
            "本地行情组件返回内容超出限制"
        case let .requestFailed(message):
            message
        }
    }
}

final class AKShareBridgeClient: @unchecked Sendable {
    static let shared = AKShareBridgeClient()

    private let timeout: TimeInterval
    private let maximumOutputBytes = 256 * 1024

    init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

    func searchAssets(keyword: String) async throws -> [AssetLookupCandidate] {
        let payload = try await send(operation: "search_assets", params: ["keyword": keyword])
        return try payload.candidates
            .filter { $0.category != AssetCategory.crypto.rawValue }
            .map(validatedCandidate)
    }

    func resolveAsset(_ candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate {
        guard Self.supportsQuoteCategory(candidate.category) else {
            throw AKShareBridgeError.invalidResponse
        }
        let payload = try await send(
            operation: "resolve_asset",
            params: [
                "name": candidate.name,
                "symbol": candidate.symbol,
                "category": candidate.category.rawValue,
            ]
        )
        guard let candidate = payload.candidate else {
            throw AKShareBridgeError.invalidResponse
        }
        return try validatedCandidate(candidate)
    }

    static func supportsQuoteCategory(_ category: AssetCategory) -> Bool {
        [.cnStock, .bStock, .hkStock, .usStock, .fund].contains(category)
    }

    func fetchEvidence(for assets: [AIMarketDataRequest]) async throws -> AIMarketEvidenceBundle {
        guard !assets.isEmpty, assets.count <= 8 else {
            return .empty
        }
        let requestData = try JSONEncoder().encode(assets)
        guard let assetsJSON = String(data: requestData, encoding: .utf8) else {
            throw AKShareBridgeError.invalidResponse
        }
        let payload = try await send(
            operation: "enrich_assets",
            params: ["assets_json": assetsJSON],
            timeoutOverride: 30
        )
        guard let evidence = payload.marketEvidence else {
            throw AKShareBridgeError.invalidResponse
        }
        try validate(evidence: evidence, requestedAssets: assets)
        return evidence
    }

    private func send(
        operation: String,
        params: [String: String],
        timeoutOverride: TimeInterval? = nil
    ) async throws -> BridgePayload {
        try await Task.detached(priority: .userInitiated) {
            try self.sendSynchronously(
                operation: operation,
                params: params,
                timeout: timeoutOverride ?? self.timeout
            )
        }.value
    }

    private func sendSynchronously(
        operation: String,
        params: [String: String],
        timeout: TimeInterval
    ) throws -> BridgePayload {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let invocation = try helperInvocation()

        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = Self.pythonHelperEnvironment()

        let request = BridgeRequest(
            protocolVersion: "akshare-bridge.v1",
            requestID: UUID().uuidString,
            operation: operation,
            params: params
        )
        let requestData = try JSONEncoder().encode(request)

        try process.run()
        try inputPipe.fileHandleForWriting.write(contentsOf: requestData + Data([0x0A]))
        try inputPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !process.isRunning else {
            process.terminate()
            throw AKShareBridgeError.timeout
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard output.count <= maximumOutputBytes else {
            throw AKShareBridgeError.outputTooLarge
        }

        let envelope = try JSONDecoder().decode(BridgeEnvelope.self, from: output)
        guard envelope.protocolVersion == "akshare-bridge.v1" else {
            throw AKShareBridgeError.invalidResponse
        }
        if let error = envelope.error {
            throw AKShareBridgeError.requestFailed(error.message)
        }
        guard envelope.status == "ok", let payload = envelope.data else {
            throw AKShareBridgeError.invalidResponse
        }
        return payload
    }

    private func helperInvocation() throws -> HelperInvocation {
        let fileManager = FileManager.default
        let scriptURL: URL

        if let bundledURL = Bundle.main.url(
            forResource: "portfolix-akshare-bridge",
            withExtension: "py",
            subdirectory: "Helpers"
        ) {
            scriptURL = bundledURL
        } else {
            scriptURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Helpers/portfolix-akshare-bridge.py")
        }
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw AKShareBridgeError.helperUnavailable
        }

        let bundledPythonURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/python-runtime/bin/python3")
        let developmentPythonURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/akshare-runtime/bin/python3")
        let homebrewPythonURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
        guard let pythonURL = [bundledPythonURL, developmentPythonURL, homebrewPythonURL]
            .first(where: { fileManager.isExecutableFile(atPath: $0.path) })
        else {
            throw AKShareBridgeError.helperUnavailable
        }
        return HelperInvocation(executableURL: pythonURL, arguments: [scriptURL.path])
    }

    private static func pythonHelperEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter { key, _ in
            !key.hasPrefix("PYTHON") && !key.hasPrefix("DYLD_") && key != "LD_LIBRARY_PATH"
        }
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["PYTHONSAFEPATH"] = "1"
        return environment
    }

    private func validatedCandidate(_ dto: BridgeCandidate) throws -> AssetLookupCandidate {
        guard
            !dto.name.isEmpty,
            !dto.symbol.isEmpty,
            dto.name.count <= 128,
            dto.symbol.count <= 32,
            let category = AssetCategory(rawValue: dto.category),
            Self.supportsQuoteCategory(category),
            let currency = DisplayCurrency(rawValue: dto.currency)
        else {
            throw AKShareBridgeError.invalidResponse
        }

        let latestPrice: Decimal?
        if let price = dto.latestPrice {
            guard let decimal = Decimal(string: price), decimal > 0 else {
                throw AKShareBridgeError.invalidResponse
            }
            latestPrice = decimal
        } else {
            latestPrice = nil
        }

        return AssetLookupCandidate(
            name: dto.name,
            symbol: dto.symbol,
            category: category,
            quoteCurrency: currency,
            latestPrice: latestPrice,
            upstreamSource: normalizedQuoteSource(dto.upstreamSource, category: category),
            quoteTime: dto.quoteTime
        )
    }

    private func validate(evidence: AIMarketEvidenceBundle, requestedAssets: [AIMarketDataRequest]) throws {
        let allowedStatuses = Set(["complete", "partial", "unavailable"])
        let requestedRefs = Set(requestedAssets.map(\.positionRef))
        guard
            evidence.provider == "AKShare",
            allowedStatuses.contains(evidence.status),
            evidence.assets.count <= requestedAssets.count,
            evidence.marketFacts.count <= 24,
            evidence.limitations.count <= 16
        else {
            throw AKShareBridgeError.invalidResponse
        }
        for asset in evidence.assets {
            guard
                requestedRefs.contains(asset.positionRef),
                allowedStatuses.contains(asset.status),
                !asset.symbol.isEmpty,
                asset.symbol.count <= 32,
                asset.endpoints.count <= 12,
                asset.metrics.count <= 16,
                asset.facts.count <= 24,
                asset.holdings.count <= 12,
                asset.limitations.count <= 16,
                asset.metrics.allSatisfy({ $0.value.isFinite && abs($0.value) <= 1_000_000_000_000 })
            else {
                throw AKShareBridgeError.invalidResponse
            }
        }
    }
}

extension AKShareBridgeClient: AIMarketDataEnriching {}

private struct HelperInvocation {
    let executableURL: URL
    let arguments: [String]
}

private struct BridgeRequest: Encodable {
    let protocolVersion: String
    let requestID: String
    let operation: String
    let params: [String: String]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case operation
        case params
    }
}

private struct BridgeEnvelope: Decodable {
    let protocolVersion: String
    let status: String
    let data: BridgePayload?
    let error: BridgeResponseError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case status
        case data
        case error
    }
}

private struct BridgeResponseError: Decodable {
    let message: String
}

private struct BridgePayload: Decodable {
    let candidates: [BridgeCandidate]
    let candidate: BridgeCandidate?
    let marketEvidence: AIMarketEvidenceBundle?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidates = try container.decodeIfPresent([BridgeCandidate].self, forKey: .candidates) ?? []
        candidate = try container.decodeIfPresent(BridgeCandidate.self, forKey: .candidate)
        marketEvidence = try container.decodeIfPresent(AIMarketEvidenceBundle.self, forKey: .marketEvidence)
    }

    private enum CodingKeys: String, CodingKey {
        case candidates
        case candidate
        case marketEvidence = "market_evidence"
    }
}

private struct BridgeCandidate: Decodable {
    let name: String
    let symbol: String
    let category: String
    let currency: String
    let latestPrice: String?
    let upstreamSource: String
    let quoteTime: String?

    enum CodingKeys: String, CodingKey {
        case name
        case symbol
        case category
        case currency
        case latestPrice = "latest_price"
        case upstreamSource = "upstream_source"
        case quoteTime = "quote_time"
    }
}
