import Foundation

enum InvestmentProfileAssetClass: String, Codable, CaseIterable, Sendable {
    case equity
    case fixedIncome = "fixed_income"
    case cash
    case crypto
    case commodity
    case unknown
}

enum InvestmentProfileRegion: String, Codable, CaseIterable, Sendable {
    case china = "CN"
    case hongKong = "HK"
    case unitedStates = "US"
    case japan = "JP"
    case europe = "EU"
    case emergingMarkets = "EM"
    case globalOther = "GLOBAL_OTHER"
    case unknown = "UNKNOWN"
}

struct InvestmentProfileEvidence: Codable, Equatable, Sendable {
    let title: String
    let url: String?
    let source: String
    let asOf: Date

    init(title: String, url: String? = nil, source: String, asOf: Date = .now) {
        self.title = title
        self.url = url
        self.source = source
        self.asOf = asOf
    }
}

struct AssetExposureProfile: Codable, Equatable, Sendable {
    let positionRef: String
    let symbol: String
    let category: String
    let resolverVersion: String
    let resolvedAt: Date
    let expiresAt: Date
    let assetClassWeights: [String: Double]
    let regionWeights: [String: Double]
    let sectorWeights: [String: Double]
    let growthStyleScore: Double
    let incomeScore: Double
    let volatilityScore: Double
    let benchmarkKey: String?
    let confidence: Double
    let rationale: String
    let evidence: [InvestmentProfileEvidence]

    var isExpired: Bool { expiresAt <= .now }

    func matches(_ position: Position) -> Bool {
        positionRef == "position_\(position.id.uuidString)"
            && symbol.caseInsensitiveCompare(position.symbol) == .orderedSame
            && category == position.category.aiCode
            && resolverVersion == InvestmentProfileEngine.resolverVersion
    }
}

struct PortfolioExposureSnapshot: Codable, Equatable, Sendable {
    let assetClassPercentages: [String: Double]
    let regionPercentages: [String: Double]
    let sectorPercentages: [String: Double]
    let evidenceCoverage: Double
    let unknownExposurePercent: Double
    let weightedGrowthStyle: Double
    let weightedIncome: Double
    let weightedVolatility: Double
}

struct InvestmentProfileScoreResult: Equatable, Sendable {
    let scores: [AIInvestmentProfileScore]
    let snapshot: PortfolioExposureSnapshot
}

struct InvestmentProfileResearchResult: Sendable {
    let exposures: [AssetExposureProfile]
    let searchedAssetCount: Int
    let limitations: [String]
}

struct InvestmentProfileCalibrationContext: Encodable, Sendable {
    let snapshot: PortfolioExposureSnapshot
    let assetExposures: [AssetExposureProfile]
    let searchedAssetCount: Int
    let limitations: [String]

    enum CodingKeys: String, CodingKey {
        case snapshot
        case assetExposures = "asset_exposures"
        case searchedAssetCount = "searched_asset_count"
        case limitations
    }
}
