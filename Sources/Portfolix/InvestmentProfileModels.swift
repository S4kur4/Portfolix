import Foundation

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

/// Retained for Codable compatibility with persisted `AIInvestmentDistribution.researchedExposures` snapshots.
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
}
