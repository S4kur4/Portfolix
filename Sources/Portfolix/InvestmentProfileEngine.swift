import Foundation

enum InvestmentProfileEngine {
    static let resolverVersion = "native-lookthrough.v1"

    static func localExposureProfiles(
        positions: [Position],
        now: Date = .now
    ) -> [AssetExposureProfile] {
        positions.map { localExposureProfile(for: $0, now: now) }
    }

    static func merge(
        positions: [Position],
        cached: [AssetExposureProfile],
        now: Date = .now
    ) -> [AssetExposureProfile] {
        let cachedByRef = Dictionary(uniqueKeysWithValues: cached.map { ($0.positionRef, $0) })
        return positions.map { position in
            let ref = positionRef(for: position)
            if let profile = cachedByRef[ref], profile.matches(position), profile.expiresAt > now {
                return profile
            }
            return localExposureProfile(for: position, now: now)
        }
    }

    static func researchCandidates(
        positions: [Position],
        exposures: [AssetExposureProfile],
        limit: Int = 4
    ) -> [Position] {
        let profiles = Dictionary(uniqueKeysWithValues: exposures.map { ($0.positionRef, $0) })
        return positions
            .filter { position in
                guard position.category == .fund else { return false }
                guard let profile = profiles[positionRef(for: position)] else { return true }
                let hasExternalEvidence = profile.evidence.contains { $0.source != "portfolix_native_resolver" }
                return !hasExternalEvidence && profile.confidence < 0.9
            }
            .sorted { $0.marketValueCNY > $1.marketValueCNY }
            .prefix(limit)
            .map { $0 }
    }

    static func score(
        positions: [Position],
        exposures: [AssetExposureProfile],
        context: AIAnalysisStoreContext
    ) -> InvestmentProfileScoreResult {
        guard !positions.isEmpty else {
            return InvestmentProfileScoreResult(
                scores: dimensionIDs.map { AIInvestmentProfileScore(id: $0, score: 0, reason: "暂无持仓数据") },
                snapshot: PortfolioExposureSnapshot(
                    assetClassPercentages: [:],
                    regionPercentages: [:],
                    sectorPercentages: [:],
                    evidenceCoverage: 0,
                    unknownExposurePercent: 100,
                    weightedGrowthStyle: 0,
                    weightedIncome: 0,
                    weightedVolatility: 0
                )
            )
        }

        let totalValue = max(positions.reduce(0.0) { $0 + max($1.marketValueCNY.doubleValue, 0) }, 0.001)
        let exposuresByRef = Dictionary(uniqueKeysWithValues: exposures.map { ($0.positionRef, $0) })
        var assetClasses: [String: Double] = [:]
        var regions: [String: Double] = [:]
        var sectors: [String: Double] = [:]
        var benchmarkWeights: [String: Double] = [:]
        var weightedGrowth = 0.0
        var weightedIncome = 0.0
        var weightedVolatility = 0.0
        var coverage = 0.0
        var unknownExposure = 0.0

        for position in positions {
            let portfolioWeight = max(position.marketValueCNY.doubleValue, 0) / totalValue
            let profile = exposuresByRef[positionRef(for: position)]
                ?? localExposureProfile(for: position)
            accumulate(profile.assetClassWeights, weight: portfolioWeight, into: &assetClasses)
            accumulate(profile.regionWeights, weight: portfolioWeight, into: &regions)
            accumulate(profile.sectorWeights, weight: portfolioWeight, into: &sectors)
            weightedGrowth += portfolioWeight * clampUnit(profile.growthStyleScore)
            weightedIncome += portfolioWeight * clampUnit(profile.incomeScore)
            weightedVolatility += portfolioWeight * clampUnit(profile.volatilityScore)
            coverage += portfolioWeight * clampUnit(profile.confidence)
            let declaredUnknown = max(
                profile.assetClassWeights[InvestmentProfileAssetClass.unknown.rawValue] ?? 0,
                profile.regionWeights[InvestmentProfileRegion.unknown.rawValue] ?? 0
            )
            unknownExposure += portfolioWeight * max(declaredUnknown, 1 - clampUnit(profile.confidence))
            let benchmark = profile.benchmarkKey ?? "position:\(position.symbol.lowercased())"
            benchmarkWeights[benchmark, default: 0] += portfolioWeight
        }

        let percentageAssetClasses = percentages(assetClasses)
        let percentageRegions = percentages(regions)
        let percentageSectors = percentages(sectors)
        let overseas = percentageRegions.reduce(0.0) { result, item in
            switch item.key {
            case InvestmentProfileRegion.china.rawValue, InvestmentProfileRegion.unknown.rawValue:
                result
            default:
                result + item.value
            }
        }
        let meaningfulRegionCount = percentageRegions.filter {
            $0.key != InvestmentProfileRegion.unknown.rawValue && $0.value >= 5
        }.count
        let regionBreadthBonus = min(Double(max(meaningfulRegionCount - 1, 0)) * 4, 12)
        let equity = percentageAssetClasses[InvestmentProfileAssetClass.equity.rawValue] ?? 0
        let fixedIncome = percentageAssetClasses[InvestmentProfileAssetClass.fixedIncome.rawValue] ?? 0
        let cash = percentageAssetClasses[InvestmentProfileAssetClass.cash.rawValue] ?? 0
        let crypto = percentageAssetClasses[InvestmentProfileAssetClass.crypto.rawValue] ?? 0
        let commodity = percentageAssetClasses[InvestmentProfileAssetClass.commodity.rawValue] ?? 0
        let concentrationPenalty = max(context.riskConstraintEvaluation.largestPositionPercent - 20, 0) * 0.45

        let lookThroughScores: [String: Double] = [
            "growth": clamp(equity * 0.42 + weightedGrowth * 46 + crypto * 0.12),
            "global": clamp(overseas * 0.9 + regionBreadthBonus),
            "diversification": diversificationScore(
                positions: positions,
                totalValue: totalValue,
                assetClassPercentages: percentageAssetClasses,
                regionPercentages: percentageRegions,
                benchmarkWeights: benchmarkWeights
            ),
            "defense": clamp(
                cash * 0.95 + fixedIncome * 0.82 + commodity * 0.52 + equity * 0.22
                    + (1 - weightedVolatility) * 18 - concentrationPenalty
            ),
            "cashflow": clamp(cash * 0.68 + fixedIncome * 0.72 + weightedIncome * 34),
            "activity": clamp(weightedVolatility * 72 + equity * 0.14 + crypto * 0.22),
        ]
        let legacy = legacyScores(positions: positions, context: context)
        let evidenceWeight = clampUnit((coverage - 0.2) / 0.8)
        let scores = dimensionIDs.map { id in
            let lookThrough = lookThroughScores[id] ?? 0
            let fallback = legacy[id] ?? lookThrough
            let final = clamp(lookThrough * evidenceWeight + fallback * (1 - evidenceWeight))
            return AIInvestmentProfileScore(
                id: id,
                score: final,
                reason: reason(
                    for: id,
                    regions: percentageRegions,
                    assets: percentageAssetClasses,
                    coverage: coverage,
                    unknownExposure: unknownExposure
                )
            )
        }

        return InvestmentProfileScoreResult(
            scores: scores,
            snapshot: PortfolioExposureSnapshot(
                assetClassPercentages: percentageAssetClasses,
                regionPercentages: percentageRegions,
                sectorPercentages: percentageSectors,
                evidenceCoverage: clampUnit(coverage),
                unknownExposurePercent: clamp(unknownExposure * 100),
                weightedGrowthStyle: clampUnit(weightedGrowth),
                weightedIncome: clampUnit(weightedIncome),
                weightedVolatility: clampUnit(weightedVolatility)
            )
        )
    }

    static func positionRef(for position: Position) -> String {
        "position_\(position.id.uuidString)"
    }

    private static let dimensionIDs = ["growth", "global", "diversification", "defense", "cashflow", "activity"]

    private static func localExposureProfile(for position: Position, now: Date = .now) -> AssetExposureProfile {
        let identity = "\(position.name) \(position.symbol)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let expiry: TimeInterval
        let assetWeights: [String: Double]
        let regionWeights: [String: Double]
        let sectorWeights: [String: Double]
        let growth: Double
        let income: Double
        let volatility: Double
        let benchmark: String?
        let confidence: Double
        let rationale: String

        switch position.category {
        case .cnStock, .bStock:
            expiry = 365 * 86_400
            assetWeights = weights([(.equity, 1)])
            regionWeights = regionMap([(.china, 1)])
            sectorWeights = [:]
            growth = 0.58
            income = 0.28
            volatility = 0.68
            benchmark = "stock:\(position.symbol.lowercased())"
            confidence = 0.96
            rationale = "根据股票上市市场识别为中国权益资产"
        case .hkStock:
            expiry = 365 * 86_400
            assetWeights = weights([(.equity, 1)])
            regionWeights = regionMap([(.hongKong, 1)])
            sectorWeights = [:]
            growth = 0.62
            income = 0.3
            volatility = 0.66
            benchmark = "stock:\(position.symbol.lowercased())"
            confidence = 0.96
            rationale = "根据股票上市市场识别为香港权益资产"
        case .usStock:
            expiry = 365 * 86_400
            assetWeights = weights([(.equity, 1)])
            regionWeights = regionMap([(.unitedStates, 1)])
            sectorWeights = [:]
            growth = 0.68
            income = 0.24
            volatility = 0.64
            benchmark = "stock:\(position.symbol.lowercased())"
            confidence = 0.96
            rationale = "根据股票上市市场识别为美国权益资产"
        case .crypto:
            expiry = 365 * 86_400
            assetWeights = weights([(.crypto, 1)])
            regionWeights = regionMap([(.globalOther, 1)])
            sectorWeights = ["digital_assets": 1]
            growth = 0.78
            income = 0.05
            volatility = 0.96
            benchmark = "crypto:\(position.symbol.lowercased())"
            confidence = 0.98
            rationale = "根据资产类别识别为全球数字资产"
        case .cash:
            expiry = 365 * 86_400
            assetWeights = weights([(.cash, 1)])
            regionWeights = cashRegionWeights(currency: position.quoteCurrency)
            sectorWeights = [:]
            growth = 0.05
            income = 0.35
            volatility = 0.02
            benchmark = "cash:\(position.quoteCurrency.rawValue.lowercased())"
            confidence = 1
            rationale = "根据币种识别为现金及流动性资产"
        case .fund:
            let fund = localFundExposure(identity: identity, symbol: position.symbol)
            if fund.confidence >= 0.88 {
                expiry = 90 * 86_400
            } else if fund.confidence < 0.5 {
                expiry = 7 * 86_400
            } else {
                expiry = 30 * 86_400
            }
            assetWeights = fund.assetClasses
            regionWeights = fund.regions
            sectorWeights = fund.sectors
            growth = fund.growth
            income = fund.income
            volatility = fund.volatility
            benchmark = fund.benchmark
            confidence = fund.confidence
            rationale = fund.rationale
        }

        return AssetExposureProfile(
            positionRef: positionRef(for: position),
            symbol: position.symbol,
            category: position.category.aiCode,
            resolverVersion: resolverVersion,
            resolvedAt: now,
            expiresAt: now.addingTimeInterval(expiry),
            assetClassWeights: normalized(assetWeights),
            regionWeights: normalized(regionWeights),
            sectorWeights: normalized(sectorWeights),
            growthStyleScore: clampUnit(growth),
            incomeScore: clampUnit(income),
            volatilityScore: clampUnit(volatility),
            benchmarkKey: benchmark,
            confidence: clampUnit(confidence),
            rationale: rationale,
            evidence: [InvestmentProfileEvidence(title: rationale, source: "portfolix_native_resolver", asOf: now)]
        )
    }

    private static func localFundExposure(identity: String, symbol: String) -> FundExposureSeed {
        let isBond = containsAny(identity, ["债", "固收", "利率债", "信用债", "bond"])
        let isMoney = containsAny(identity, ["货币", "现金管理", "money market"])
        let isGold = containsAny(identity, ["黄金", "gold"])
        let isUS = containsAny(identity, ["美股", "纳斯达克", "纳指", "nasdaq", "标普", "s&p", "sp500", "道琼斯"])
        let isHongKong = containsAny(identity, ["港股", "恒生", "hang seng"])
        let isJapan = containsAny(identity, ["日本", "日经", "nikkei"])
        let isEurope = containsAny(identity, ["欧洲", "欧股", "europe"])
        let isGlobal = containsAny(identity, ["全球", "环球", "world", "acwi", "msci"])
        let isTechnology = containsAny(identity, ["科技", "半导体", "芯片", "信息技术", "technology", "semiconductor"])
        let isDividend = containsAny(identity, ["红利", "高股息", "股息", "dividend"])
        let isQDII = containsAny(identity, ["qdii"])

        if isMoney {
            return FundExposureSeed(
                assetClasses: weights([(.cash, 0.95), (.fixedIncome, 0.05)]),
                regions: regionMap([(.china, 1)]), sectors: [:], growth: 0.04, income: 0.46,
                volatility: 0.03, benchmark: "money_market:\(symbol.lowercased())", confidence: 0.92,
                rationale: "名称表明该基金以货币市场和现金类资产为主"
            )
        }
        if isBond {
            return FundExposureSeed(
                assetClasses: weights([(.fixedIncome, 0.92), (.cash, 0.08)]),
                regions: isGlobal ? regionMap([(.china, 0.2), (.globalOther, 0.8)]) : regionMap([(.china, 0.95), (.unknown, 0.05)]),
                sectors: [:], growth: 0.12, income: 0.78, volatility: 0.2,
                benchmark: "bond:\(normalizedBenchmark(identity, symbol: symbol))", confidence: 0.84,
                rationale: "名称表明该基金以固定收益资产为主"
            )
        }
        if isGold {
            return FundExposureSeed(
                assetClasses: weights([(.commodity, 0.95), (.cash, 0.05)]),
                regions: regionMap([(.globalOther, 0.9), (.unknown, 0.1)]),
                sectors: ["precious_metals": 1], growth: 0.2, income: 0.05, volatility: 0.5,
                benchmark: "gold", confidence: 0.92, rationale: "名称表明该基金主要跟踪黄金资产"
            )
        }

        var regions: [String: Double] = [:]
        if isUS { regions = regionMap([(.unitedStates, 0.92), (.globalOther, 0.05), (.unknown, 0.03)]) }
        else if isHongKong { regions = regionMap([(.hongKong, 0.92), (.china, 0.05), (.unknown, 0.03)]) }
        else if isJapan { regions = regionMap([(.japan, 0.92), (.globalOther, 0.05), (.unknown, 0.03)]) }
        else if isEurope { regions = regionMap([(.europe, 0.9), (.globalOther, 0.07), (.unknown, 0.03)]) }
        else if isGlobal { regions = regionMap([(.unitedStates, 0.5), (.europe, 0.18), (.japan, 0.08), (.emergingMarkets, 0.12), (.globalOther, 0.12)]) }
        else if isQDII { regions = regionMap([(.globalOther, 0.7), (.unknown, 0.3)]) }
        else { regions = regionMap([(.china, 0.55), (.unknown, 0.45)]) }

        let recognizedRegion = isUS || isHongKong || isJapan || isEurope || isGlobal
        let confidence = recognizedRegion ? 0.84 : (isQDII ? 0.55 : 0.34)
        let rationale = recognizedRegion
            ? "根据基金名称识别其主要投资市场和权益属性"
            : "基金名称不足以可靠识别底层资产，需要联网资料补充"
        return FundExposureSeed(
            assetClasses: weights([(.equity, recognizedRegion || isQDII ? 0.9 : 0.5), (.fixedIncome, recognizedRegion || isQDII ? 0.04 : 0.2), (.cash, 0.06), (.unknown, recognizedRegion || isQDII ? 0 : 0.24)]),
            regions: regions,
            sectors: isTechnology ? ["technology": 0.82, "other": 0.18] : [:],
            growth: isTechnology ? 0.88 : (isDividend ? 0.42 : 0.62),
            income: isDividend ? 0.72 : 0.22,
            volatility: isTechnology ? 0.78 : 0.58,
            benchmark: recognizedRegion || isTechnology ? normalizedBenchmark(identity, symbol: symbol) : nil,
            confidence: confidence,
            rationale: rationale
        )
    }

    private static func legacyScores(positions: [Position], context: AIAnalysisStoreContext) -> [String: Double] {
        let totalValue = max(positions.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue }, 0.001)
        func allocation(_ category: AssetCategory) -> Double {
            positions.filter { $0.category == category }.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue } / totalValue * 100
        }
        func weighted(_ score: (Position) -> Double) -> Double {
            positions.reduce(0.0) { $0 + score($1) * $1.marketValueCNY.doubleValue / totalValue }
        }
        let shares = positions.map { max($0.marketValueCNY.doubleValue / totalValue, 0) }
        let hhi = shares.reduce(0.0) { $0 + $1 * $1 }
        let effectiveCount = hhi > 0 ? min(1 / hhi, 12) : 0
        let categoryCount = Set(positions.map(\.category)).count
        let currencyCount = Set(positions.map(\.quoteCurrency)).count
        let concentrationPenalty = max(context.riskConstraintEvaluation.largestPositionPercent - 14, 0) * 1.15
        let topThree = positions.sorted { $0.marketValueCNY > $1.marketValueCNY }.prefix(3)
            .reduce(0.0) { $0 + $1.marketValueCNY.doubleValue / totalValue * 100 }
        let profitable = positions.filter { $0.profitRate > 0 }.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue / totalValue * 100 }
        let stale = positions.filter { $0.freshness == .stale }.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue / totalValue * 100 }
        let riskBudget = (context.positionLimit - 30) * 0.06
            + (context.cryptoLimit - 15) * 0.08
            + (context.foreignCurrencyLimit - 50) * 0.04
            - (context.liquidityMinimum - 10) * 0.08
        let overseasMarket = allocation(.usStock) + allocation(.hkStock)
        return [
            "growth": clamp(weighted { position in
                switch position.category {
                case .crypto: 88
                case .usStock, .hkStock: 72
                case .cnStock, .bStock: 64
                case .fund: 52
                case .cash: 12
                }
            } + profitable * 0.08 - context.riskConstraintEvaluation.cashAllocationPercent * 0.12 + riskBudget),
            "global": clamp(context.riskConstraintEvaluation.nonCNYAllocationPercent * 1.05 + overseasMarket * 0.42),
            "diversification": clamp(
                18 + effectiveCount / 12 * 38 + min(Double(positions.count), 10) / 10 * 14
                    + min(Double(categoryCount), 5) / 5 * 22 + min(Double(currencyCount), 4) / 4 * 14
                    - concentrationPenalty - max(topThree - 62, 0) * 0.32
            ),
            "defense": clamp(weighted { position in
                switch position.category {
                case .cash: 96
                case .fund: 76
                case .cnStock, .hkStock, .usStock: 52
                case .bStock: 46
                case .crypto: 20
                }
            } - concentrationPenalty * 0.42 - allocation(.crypto) * 0.22 - stale * 0.18 - riskBudget),
            "cashflow": clamp(8 + context.riskConstraintEvaluation.cashAllocationPercent * 1.55 + allocation(.fund) * 0.52 + profitable * 0.12),
            "activity": clamp(weighted { position in
                switch position.category {
                case .crypto: 92
                case .cnStock, .hkStock, .usStock: 76
                case .bStock: 58
                case .fund: 44
                case .cash: 24
                }
            } + min(Double(positions.count), 12) / 12 * 8 - context.riskConstraintEvaluation.cashAllocationPercent * 0.08 + riskBudget),
        ]
    }

    private static func diversificationScore(
        positions: [Position],
        totalValue: Double,
        assetClassPercentages: [String: Double],
        regionPercentages: [String: Double],
        benchmarkWeights: [String: Double]
    ) -> Double {
        let positionHHI = positions.reduce(0.0) {
            let share = max($1.marketValueCNY.doubleValue, 0) / totalValue
            return $0 + share * share
        }
        let effectivePositionScore = min((positionHHI > 0 ? 1 / positionHHI : 0) / 10, 1) * 30
        let assetHHI = hhi(percentages: assetClassPercentages)
        let regionHHI = hhi(percentages: regionPercentages.filter { $0.key != InvestmentProfileRegion.unknown.rawValue })
        let benchmarkHHI = benchmarkWeights.values.reduce(0.0) { $0 + $1 * $1 }
        return clamp(
            10 + effectivePositionScore + (1 - assetHHI) * 20 + (1 - regionHHI) * 15 + (1 - benchmarkHHI) * 25
        )
    }

    private static func reason(
        for id: String,
        regions: [String: Double],
        assets: [String: Double],
        coverage: Double,
        unknownExposure: Double
    ) -> String {
        let overseas = regions.reduce(0.0) { partial, item in
            [InvestmentProfileRegion.china.rawValue, InvestmentProfileRegion.unknown.rawValue].contains(item.key)
                ? partial : partial + item.value
        }
        let equity = assets[InvestmentProfileAssetClass.equity.rawValue] ?? 0
        let fixedIncome = assets[InvestmentProfileAssetClass.fixedIncome.rawValue] ?? 0
        let cash = assets[InvestmentProfileAssetClass.cash.rawValue] ?? 0
        switch id {
        case "growth": return String(format: "底层权益暴露约 %.0f%%，并结合成长风格特征计算", equity)
        case "global": return String(format: "按底层投资地区估算海外暴露约 %.0f%%，不以计价币种代替投资地区", overseas)
        case "diversification": return "综合底层资产、地区、持仓集中度与重复基准计算"
        case "defense": return String(format: "底层固定收益约 %.0f%%、现金约 %.0f%%，并计入波动与集中度", fixedIncome, cash)
        case "cashflow": return "根据现金、固定收益及收入型资产的底层占比计算"
        default:
            return String(format: "根据底层资产市场敏感度计算；证据覆盖率约 %.0f%%，未知暴露约 %.0f%%", coverage * 100, unknownExposure * 100)
        }
    }

    private static func accumulate(_ values: [String: Double], weight: Double, into result: inout [String: Double]) {
        for (key, value) in values {
            result[key, default: 0] += weight * max(value, 0)
        }
    }

    private static func percentages(_ values: [String: Double]) -> [String: Double] {
        values.mapValues { clamp($0 * 100) }
    }

    private static func hhi<S: Sequence>(percentages: S) -> Double where S.Element == Dictionary<String, Double>.Element {
        percentages.reduce(0.0) { partial, item in
            let share = item.value / 100
            return partial + share * share
        }
    }

    private static func weights(_ values: [(InvestmentProfileAssetClass, Double)]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.rawValue, $1) })
    }

    private static func regionMap(_ values: [(InvestmentProfileRegion, Double)]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.rawValue, $1) })
    }

    private static func cashRegionWeights(currency: DisplayCurrency) -> [String: Double] {
        switch currency {
        case .cny: regionMap([(.china, 1)])
        case .hkd: regionMap([(.hongKong, 1)])
        case .usd: regionMap([(.unitedStates, 1)])
        case .usdt: regionMap([(.globalOther, 1)])
        }
    }

    private static func normalized(_ values: [String: Double]) -> [String: Double] {
        let sanitized = values.mapValues { max($0, 0) }
        let total = sanitized.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return sanitized.mapValues { $0 / total }
    }

    private static func normalizedBenchmark(_ identity: String, symbol: String) -> String {
        if containsAny(identity, ["纳斯达克", "纳指", "nasdaq"]) { return "index:nasdaq_100" }
        if containsAny(identity, ["标普", "s&p", "sp500"]) { return "index:sp500" }
        if containsAny(identity, ["恒生科技"]) { return "index:hang_seng_tech" }
        if containsAny(identity, ["恒生"]) { return "index:hang_seng" }
        if containsAny(identity, ["日经", "nikkei"]) { return "index:nikkei" }
        return "fund:\(symbol.lowercased())"
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 100) }
    private static func clampUnit(_ value: Double) -> Double { min(max(value, 0), 1) }
}

private struct FundExposureSeed {
    let assetClasses: [String: Double]
    let regions: [String: Double]
    let sectors: [String: Double]
    let growth: Double
    let income: Double
    let volatility: Double
    let benchmark: String?
    let confidence: Double
    let rationale: String
}
