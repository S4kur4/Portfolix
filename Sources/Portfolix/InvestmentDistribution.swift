import CryptoKit
import Foundation

struct InvestmentDomain: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let titleChinese: String
    let titleEnglish: String

    func title(language: AppLanguage) -> String {
        language == .english ? titleEnglish : titleChinese
    }
}

struct InvestmentDomainWeight: Codable, Equatable, Sendable {
    let domain: InvestmentDomain
    let weight: Double
}

struct AssetInvestmentDistribution: Codable, Equatable, Sendable {
    let positionRef: String
    let identityFingerprint: String
    let allocations: [InvestmentDomainWeight]
}

struct AIInvestmentDistribution: Codable, Equatable, Sendable {
    let version: String
    let generatedAt: Date
    let model: String
    let requestFingerprint: String
    let assets: [AssetInvestmentDistribution]
    let researchedExposures: [AssetExposureProfile]
}

struct InvestmentDistributionItem: Identifiable, Equatable, Sendable {
    let domain: InvestmentDomain
    let amountCNY: Decimal
    let percentage: Double

    var id: String { domain.id }
}

enum InvestmentDistributionEngine {
    static let version = "investment-distribution.v1"
    static let cacheKey = "ai_investment_distribution_cache_v1"

    static func identityFingerprint(_ position: Position) -> String {
        digest([
            position.id.uuidString, position.name, position.symbol,
            position.category.aiCode, position.quoteCurrency.rawValue,
        ])
    }

    static func marketFingerprint(positions: [Position]) -> String {
        digest(positions.sorted { $0.id.uuidString < $1.id.uuidString }.flatMap {
            [
                identityFingerprint($0), $0.fetchedAt, $0.quoteTime,
                NSDecimalNumber(decimal: $0.marketValueCNY).stringValue,
            ]
        })
    }

    static func requestFingerprint(
        positions: [Position], model: String, search: SearchConfiguration
    ) -> String {
        digest([
            version, model, marketFingerprint(positions: positions),
            search.isEnabled ? search.orderedEnabledProviders.map(\.rawValue).joined(separator: ",") : "offline",
        ])
    }

    static func items(
        positions: [Position], assets: [AssetInvestmentDistribution] = []
    ) -> [InvestmentDistributionItem] {
        let positivePositions = positions.filter { $0.marketValueCNY > 0 }
        let total = positivePositions.reduce(Decimal.zero) { $0 + $1.marketValueCNY }
        guard total > 0 else { return [] }
        let byRef = Dictionary(grouping: assets, by: \.positionRef)
        var domains: [String: InvestmentDomain] = [:]
        var amounts: [String: Decimal] = [:]
        for position in positivePositions {
            let profile = byRef[InvestmentProfileEngine.positionRef(for: position)]?.first
            let allocations = profile?.identityFingerprint == identityFingerprint(position)
                ? profile?.allocations ?? [] : []
            var remaining = position.marketValueCNY
            let complete = abs(allocations.reduce(0) { $0 + $1.weight } - 1) <= 0.000001
            // Amounts always come from local records, never from the model.
            for (index, allocation) in allocations.enumerated() where allocation.weight.isFinite && allocation.weight > 0 {
                let amount = complete && index == allocations.count - 1
                    ? remaining : min(position.marketValueCNY * Decimal(allocation.weight), remaining)
                guard amount > 0 else { continue }
                domains[allocation.domain.id] = allocation.domain
                amounts[allocation.domain.id, default: 0] += amount
                remaining -= amount
            }
            if remaining > 0 {
                let domain = fallbackDomain(position.category)
                domains[domain.id] = domain
                amounts[domain.id, default: 0] += remaining
            }
        }
        return amounts.compactMap { key, amount in
            guard let domain = domains[key], amount > 0 else { return nil }
            return InvestmentDistributionItem(
                domain: domain, amountCNY: amount, percentage: (amount / total * 100).doubleValue
            )
        }.sorted {
            $0.amountCNY == $1.amountCNY ? $0.id < $1.id : $0.amountCNY > $1.amountCNY
        }
    }

    static func fallbackDomain(_ category: AssetCategory) -> InvestmentDomain {
        InvestmentDomain(
            id: "category_\(category.aiCode)",
            titleChinese: category.title(language: .chinese),
            titleEnglish: category.title(language: .english)
        )
    }

    static func validatedAssets(
        _ assets: [AssetInvestmentDistribution], positions: [Position]
    ) throws -> [AssetInvestmentDistribution] {
        let byRef = Dictionary(uniqueKeysWithValues: positions.map {
            (InvestmentProfileEngine.positionRef(for: $0), $0)
        })
        guard assets.count <= positions.count,
              Set(assets.map(\.positionRef)).count == assets.count else {
            throw AIAnalysisAgentError.invalidReport
        }
        var domains: [String: InvestmentDomain] = [:]
        for asset in assets {
            guard let position = byRef[asset.positionRef],
                  asset.identityFingerprint == identityFingerprint(position),
                  asset.allocations.count <= 12,
                  Set(asset.allocations.map(\.domain.id)).count == asset.allocations.count else {
                throw AIAnalysisAgentError.invalidReport
            }
            var total = 0.0
            for allocation in asset.allocations {
                let domain = allocation.domain
                guard allocation.weight.isFinite, allocation.weight > 0, allocation.weight <= 1,
                      domain.id.range(of: #"^[a-z][a-z0-9_]{0,63}$"#, options: .regularExpression) != nil,
                      !domain.id.hasPrefix("category_"),
                      validTitle(domain.titleChinese), validTitle(domain.titleEnglish) else {
                    throw AIAnalysisAgentError.invalidReport
                }
                try AIInformationSecurityGuardrail.validateGeneratedText(domain.titleChinese)
                try AIInformationSecurityGuardrail.validateGeneratedText(domain.titleEnglish)
                if let existing = domains[domain.id], existing != domain {
                    throw AIAnalysisAgentError.invalidReport
                }
                domains[domain.id] = domain
                total += allocation.weight
            }
            guard total <= 1.000001 else { throw AIAnalysisAgentError.invalidReport }
        }
        guard domains.count <= 128 else { throw AIAnalysisAgentError.invalidReport }
        return assets
    }

    private static func validTitle(_ title: String) -> Bool {
        !title.isEmpty && title.count <= 48
            && title == title.trimmingCharacters(in: .whitespacesAndNewlines)
            && !title.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            && !title.contains("://")
    }

    private static func digest(_ components: [String]) -> String {
        let data = (try? JSONEncoder().encode(components)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct HoldingShareGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let amountCNY: Decimal
    let percentage: Double
}

enum HoldingShareEngine {
    static func groups(positions: [Position], language: AppLanguage) -> [HoldingShareGroup] {
        let sorted = positions.filter { $0.marketValueCNY > 0 }.sorted {
            if $0.marketValueCNY != $1.marketValueCNY { return $0.marketValueCNY > $1.marketValueCNY }
            return $0.id.uuidString < $1.id.uuidString
        }
        let total = sorted.reduce(Decimal.zero) { $0 + $1.marketValueCNY }
        guard total > 0 else { return [] }
        let threshold = total * Decimal(string: "0.9")!
        var covered: Decimal = 0
        var groups: [HoldingShareGroup] = []
        for position in sorted where covered < threshold {
            groups.append(HoldingShareGroup(
                id: "holding_\(position.id.uuidString)", name: position.name,
                amountCNY: position.marketValueCNY,
                percentage: (position.marketValueCNY / total * 100).doubleValue
            ))
            covered += position.marketValueCNY
        }
        let remaining = total - covered
        if remaining > 0 {
            groups.append(HoldingShareGroup(
                id: "other_holdings", name: localizedText("其他", "Other", language: language),
                amountCNY: remaining, percentage: (remaining / total * 100).doubleValue
            ))
        }
        return groups
    }
}
