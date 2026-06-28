import Foundation

struct AIMarketDataRequest: Codable, Equatable, Sendable {
    let positionRef: String
    let symbol: String
    let category: String

    enum CodingKeys: String, CodingKey {
        case positionRef = "position_ref"
        case symbol
        case category
    }
}

protocol AIMarketDataEnriching: Sendable {
    func fetchEvidence(for assets: [AIMarketDataRequest]) async throws -> AIMarketEvidenceBundle
}

struct DisabledAIMarketDataEnricher: AIMarketDataEnriching {
    static let shared = DisabledAIMarketDataEnricher()

    func fetchEvidence(for assets: [AIMarketDataRequest]) async throws -> AIMarketEvidenceBundle {
        .unavailable(assetCount: assets.count)
    }
}

struct AIMarketEvidenceBundle: Codable, Equatable, Sendable {
    let provider: String
    let generatedAt: String
    let status: String
    let assets: [AIAssetMarketEvidence]
    let marketFacts: [AIMarketEvidenceFact]
    let limitations: [String]

    enum CodingKeys: String, CodingKey {
        case provider
        case generatedAt = "generated_at"
        case status
        case assets
        case marketFacts = "market_facts"
        case limitations
    }

    static let empty = AIMarketEvidenceBundle(
        provider: "AKShare",
        generatedAt: "",
        status: "not_requested",
        assets: [],
        marketFacts: [],
        limitations: []
    )

    static func unavailable(assetCount: Int) -> AIMarketEvidenceBundle {
        AIMarketEvidenceBundle(
            provider: "AKShare",
            generatedAt: ISO8601DateFormatter().string(from: .now),
            status: "unavailable",
            assets: [],
            marketFacts: [],
            limitations: assetCount > 0 ? ["AKShare 市场数据本次不可用，报告将继续使用持仓快照与其他证据"] : []
        )
    }

    var availableAssetCount: Int {
        assets.filter { $0.status == "complete" || $0.status == "partial" }.count
    }
}

struct AIAssetMarketEvidence: Codable, Equatable, Sendable {
    let positionRef: String
    let symbol: String
    let category: String
    let status: String
    let asOf: String?
    let endpoints: [String]
    let metrics: [AIMarketEvidenceMetric]
    let facts: [AIMarketEvidenceFact]
    let holdings: [AIMarketEvidenceHolding]
    let limitations: [String]

    enum CodingKeys: String, CodingKey {
        case positionRef = "position_ref"
        case symbol
        case category
        case status
        case asOf = "as_of"
        case endpoints
        case metrics
        case facts
        case holdings
        case limitations
    }
}

struct AIMarketEvidenceMetric: Codable, Equatable, Sendable {
    let code: String
    let value: Double
    let unit: String
    let asOf: String?

    enum CodingKeys: String, CodingKey {
        case code
        case value
        case unit
        case asOf = "as_of"
    }
}

struct AIMarketEvidenceFact: Codable, Equatable, Sendable {
    let code: String
    let label: String
    let value: String
    let asOf: String?
    let endpoint: String

    enum CodingKeys: String, CodingKey {
        case code
        case label
        case value
        case asOf = "as_of"
        case endpoint
    }
}

struct AIMarketEvidenceHolding: Codable, Equatable, Sendable {
    let assetType: String
    let name: String
    let symbol: String?
    let weightPct: Double?
    let asOf: String?

    enum CodingKeys: String, CodingKey {
        case assetType = "asset_type"
        case name
        case symbol
        case weightPct = "weight_pct"
        case asOf = "as_of"
    }
}
