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
    var classifiedAt: Date? = nil
    var retryAfter: Date? = nil
    var researchedAt: Date? = nil
}

struct AIInvestmentDistribution: Codable, Equatable, Sendable {
    var modelUsage: AIModelUsageSummary? = nil
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
    static let version = "investment-distribution.v3-asset-domains"
    static let classificationLifetime: TimeInterval = 90 * 24 * 60 * 60
    static let unresolvedLifetime: TimeInterval = 7 * 24 * 60 * 60
    static let failureRetryInterval: TimeInterval = 24 * 60 * 60
    static let cacheKey = "ai_investment_distribution_cache_v1"

    static func identityFingerprint(_ position: Position) -> String {
        digest([
            position.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            position.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            position.category.aiCode, position.quoteCurrency.rawValue,
        ])
    }

    static func requestFingerprint(
        positions: [Position], model _: String, search _: SearchConfiguration
    ) -> String {
        digest([
            version, digest(Array(Set(positions.filter { $0.marketValueCNY > 0 }.map(identityFingerprint))).sorted()),
        ])
    }

    static let unclassifiedDomain = InvestmentDomain(
        id: "unclassified", titleChinese: "待识别领域", titleEnglish: "Unclassified exposure"
    )

    static let commonDomains: [InvestmentDomain] = [
        InvestmentDomain(id: "gold", titleChinese: "黄金", titleEnglish: "Gold"),
        InvestmentDomain(id: "cn_semiconductors", titleChinese: "中国半导体芯片", titleEnglish: "China Semiconductors"),
        InvestmentDomain(id: "cn_optical_communication", titleChinese: "中国光通信", titleEnglish: "China Optical Communications"),
        InvestmentDomain(id: "us_broad_equity", titleChinese: "美股宽基", titleEnglish: "Broad US Equities"),
        InvestmentDomain(id: "us_technology", titleChinese: "美股科技", titleEnglish: "US Technology"),
        InvestmentDomain(id: "cn_bonds", titleChinese: "人民币债券", titleEnglish: "CNY Bonds"),
    ]

    static func localDomain(for position: Position) -> InvestmentDomain? {
        let base = position.symbol.uppercased().split(whereSeparator: { "/-_".contains($0) }).first.map(String.init) ?? ""
        if position.category == .cash {
            if ["USDT", "USDC"].contains(base) {
                return InvestmentDomain(id: "stablecoin_cash", titleChinese: "稳定币现金", titleEnglish: "Stablecoin Cash")
            }
            let code = position.quoteCurrency.rawValue
            let title = ["CNY": "人民币现金", "USD": "美元现金", "HKD": "港币现金", "USDT": "稳定币现金"][code] ?? "\(code)现金"
            return InvestmentDomain(id: code == "USDT" ? "stablecoin_cash" : "cash_\(code.lowercased())",
                titleChinese: title, titleEnglish: code == "USDT" ? "Stablecoin Cash" : "\(code) Cash")
        }
        guard position.category == .crypto else { return nil }
        switch base {
        case "BTC", "BTCUSDT", "BTCUSD":
            return InvestmentDomain(id: "bitcoin", titleChinese: "比特币", titleEnglish: "Bitcoin")
        case "ETH", "ETHUSDT", "ETHUSD":
            return InvestmentDomain(id: "ethereum", titleChinese: "以太坊", titleEnglish: "Ethereum")
        case "USDT", "USDC":
            return InvestmentDomain(id: "stablecoin_cash", titleChinese: "稳定币现金", titleEnglish: "Stablecoin Cash")
        default: return nil
        }
    }

    static func cachedAssets(_ cache: AIInvestmentDistribution?, positions: [Position]) -> [AssetInvestmentDistribution] {
        guard let cache, cache.version == version else { return [] }
        let byIdentity = Dictionary(grouping: cache.assets, by: \.identityFingerprint)
        return positions.compactMap { position in
            let candidates = byIdentity[identityFingerprint(position)] ?? []
            guard let candidate = candidates.max(by: { ($0.classifiedAt ?? cache.generatedAt) < ($1.classifiedAt ?? cache.generatedAt) }) else { return nil }
            let asset = AssetInvestmentDistribution(
                positionRef: InvestmentProfileEngine.positionRef(for: position), identityFingerprint: identityFingerprint(position),
                allocations: candidate.allocations, classifiedAt: candidate.classifiedAt ?? cache.generatedAt,
                retryAfter: candidate.retryAfter, researchedAt: candidate.researchedAt
            )
            return (try? validatedAssets([asset], positions: [position]))?.first
        }
    }

    static func pendingPositions(_ positions: [Position], cache: AIInvestmentDistribution?, now: Date = .now, force: Bool = false) -> [Position] {
        let cached = Dictionary(grouping: cachedAssets(cache, positions: positions), by: \.identityFingerprint)
        var seen = Set<String>()
        return positions.filter { position in
            let identity = identityFingerprint(position)
            guard position.marketValueCNY > 0, localDomain(for: position) == nil,
                  seen.insert(identity).inserted else { return false }
            guard !force, let asset = cached[identity]?.first else { return true }
            if let retry = asset.retryAfter, now < retry { return false }
            let age = now.timeIntervalSince(asset.classifiedAt ?? .distantPast)
            return age < 0 || age >= (asset.allocations.isEmpty ? unresolvedLifetime : classificationLifetime)
                || asset.retryAfter != nil
        }.sorted {
            let left = cached[identityFingerprint($0)]?.first?.researchedAt ?? .distantPast
            let right = cached[identityFingerprint($1)]?.first?.researchedAt ?? .distantPast
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
    }

    static func merging(_ result: AIInvestmentDistribution, into cache: AIInvestmentDistribution?, positions: [Position]) -> AIInvestmentDistribution {
        var byIdentity: [String: AssetInvestmentDistribution] = [:]
        for asset in (cache?.version == version ? cache?.assets ?? [] : []) + result.assets {
            byIdentity[asset.identityFingerprint] = asset
        }
        let active = Set(positions.map(identityFingerprint))
        let sorted = byIdentity.values.sorted {
            ($0.classifiedAt ?? .distantPast) > ($1.classifiedAt ?? .distantPast)
        }
        // Retain every active holding; cap only removed identities so a large portfolio cannot cause cache churn.
        let retained = sorted.filter { active.contains($0.identityFingerprint) }
            + sorted.filter { !active.contains($0.identityFingerprint) }.prefix(100)
        return AIInvestmentDistribution(
            modelUsage: result.modelUsage, version: version, generatedAt: result.generatedAt,
            model: result.model, requestFingerprint: result.requestFingerprint,
            assets: retained, researchedExposures: []
        )
    }

    static func items(
        positions: [Position], assets: [AssetInvestmentDistribution] = [], usesUnclassifiedFallback: Bool = false
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
                let domain = usesUnclassifiedFallback ? unclassifiedDomain : fallbackDomain(position.category)
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
                      !isAssetType(domain), domain.id != unclassifiedDomain.id,
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

    private static func isAssetType(_ domain: InvestmentDomain) -> Bool {
        let types = Set(AssetCategory.allCases.flatMap { [$0.title(language: .chinese).lowercased(), $0.title(language: .english).lowercased()] }
            + ["基金", "股票", "债券基金", "fund", "funds", "etf", "cryptocurrency", "digital currency"])
        return types.contains(domain.titleChinese.lowercased()) || types.contains(domain.titleEnglish.lowercased())
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
