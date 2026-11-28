import Foundation
import PortfolixCore

enum DemoModeBlockedAction: Equatable {
    case addAsset
    case modifyHolding
    case saveRiskProfile
    case aiInsights
    case refreshQuotes
}

struct DemoModeActionPrompt: Identifiable, Equatable {
    enum FollowUp: Equatable {
        case none
        case openNewPositionEditor
    }

    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let followUp: FollowUp
}

enum DemoPortfolio {
    static let stateKey = "demo_mode.state"
    static let enabledKey = "demo_mode.enabled"

    struct Dataset: Sendable {
        let positions: [Position]
        let snapshotHistory: [PortfolioSnapshot]
        let dailyProfitHistory: [DailyProfitPoint]
        let riskProfileDraft: RiskProfileDraft
        let riskProfileUpdatedAt: Date
    }

    private struct HoldingSpec {
        let id: UUID
        let chineseName: String
        let englishName: String
        let symbol: String
        let category: AssetCategory
        let quoteCurrency: DisplayCurrency
        let quantity: Decimal
        let averageCost: Decimal
        let latestPrice: Decimal
        let source: String
        let freshness: Freshness
        /// Relative price multipliers for 30 days (index 0 = today-29 ... index 29 = today = 1.0).
        let dailyMultipliers: [Double]
    }

    /// Base 30-day market path (index 0 = 29 days ago, index 29 = today = 1.0000).
    /// Features an early climb, a ~4.5% mid-month pullback, and a healthy recovery.
    private static let baseMarketCurve: [Double] = [
        0.9460, 0.9515, 0.9482, 0.9560, 0.9635,
        0.9602, 0.9698, 0.9784, 0.9850, 0.9925,
        0.9990, 0.9932, 0.9845, 0.9760, 0.9685,
        0.9592, 0.9535, 0.9578, 0.9652, 0.9615,
        0.9704, 0.9776, 0.9742, 0.9828, 0.9896,
        0.9864, 0.9918, 0.9962, 0.9970, 1.0000
    ]

    /// Generates an asset-specific 30-day multiplier curve ending at 1.0000 on index 29,
    /// with a controlled yesterday-to-today return (`todayChange`) so Today's P&L is crisp.
    private static func makeCurve(
        beta: Double,
        phase: Double,
        wiggle: Double,
        todayChange: Double
    ) -> [Double] {
        var values = (0..<30).map { index -> Double in
            if index == 29 { return 1.0 }
            if index == 28 { return 1.0 / (1.0 + todayChange) }
            let marketDelta = baseMarketCurve[index] - 1.0
            let wave = sin(Double(index) * 0.72 + phase) * wiggle
            return max(0.75, 1.0 + marketDelta * beta + wave)
        }
        values[29] = 1.0
        return values
    }

    private static var specs: [HoldingSpec] {
        [
            HoldingSpec(
                id: UUID(uuidString: "D0000001-0001-4000-8000-000000000001")!,
                chineseName: "沪深300 ETF",
                englishName: "CSI 300 ETF",
                symbol: "510300",
                category: .fund,
                quoteCurrency: .cny,
                quantity: Decimal(55_000),
                averageCost: Decimal(string: "3.820")!,
                latestPrice: Decimal(string: "4.125")!,
                source: "东方财富",
                freshness: .updated,
                dailyMultipliers: makeCurve(beta: 0.95, phase: 0.4, wiggle: 0.0055, todayChange: 0.0068)
            ),
            HoldingSpec(
                id: UUID(uuidString: "D0000001-0001-4000-8000-000000000002")!,
                chineseName: "中证短债基金",
                englishName: "Short-Term Bond Fund",
                symbol: "004672",
                category: .fund,
                quoteCurrency: .cny,
                quantity: Decimal(165_000),
                averageCost: Decimal(string: "1.062")!,
                latestPrice: Decimal(string: "1.095")!,
                source: "东方财富",
                freshness: .updated,
                dailyMultipliers: makeCurve(beta: 0.08, phase: 1.1, wiggle: 0.0005, todayChange: 0.0006)
            ),
            HoldingSpec(
                id: UUID(uuidString: "D0000001-0001-4000-8000-000000000003")!,
                chineseName: "Apple",
                englishName: "Apple",
                symbol: "AAPL",
                category: .usStock,
                quoteCurrency: .usd,
                quantity: Decimal(90),
                averageCost: Decimal(string: "212.50")!,
                latestPrice: Decimal(string: "236.80")!,
                source: "东方财富",
                freshness: .updated,
                dailyMultipliers: makeCurve(beta: 1.15, phase: 1.9, wiggle: 0.0075, todayChange: 0.0142)
            ),
            HoldingSpec(
                id: UUID(uuidString: "D0000001-0001-4000-8000-000000000004")!,
                chineseName: "人民币现金",
                englishName: "CNY Cash",
                symbol: "CNY",
                category: .cash,
                quoteCurrency: .cny,
                quantity: Decimal(150_000),
                averageCost: Decimal(1),
                latestPrice: Decimal(1),
                source: "手工价格",
                freshness: .manual,
                dailyMultipliers: Array(repeating: 1.0, count: 30)
            ),
            HoldingSpec(
                id: UUID(uuidString: "D0000001-0001-4000-8000-000000000005")!,
                chineseName: "NVIDIA",
                englishName: "NVIDIA",
                symbol: "NVDA",
                category: .usStock,
                quoteCurrency: .usd,
                quantity: Decimal(95),
                averageCost: Decimal(string: "118.40")!,
                latestPrice: Decimal(string: "138.60")!,
                source: "东方财富",
                freshness: .updated,
                dailyMultipliers: makeCurve(beta: 1.65, phase: 2.8, wiggle: 0.0125, todayChange: -0.0118)
            ),
            HoldingSpec(
                id: UUID(uuidString: "D0000001-0001-4000-8000-000000000006")!,
                chineseName: "腾讯控股",
                englishName: "Tencent",
                symbol: "00700.HK",
                category: .hkStock,
                quoteCurrency: .hkd,
                quantity: Decimal(200),
                averageCost: Decimal(string: "386.00")!,
                latestPrice: Decimal(string: "428.60")!,
                source: "东方财富",
                freshness: .updated,
                dailyMultipliers: makeCurve(beta: 1.30, phase: 3.7, wiggle: 0.0090, todayChange: 0.0185)
            ),
            HoldingSpec(
                id: UUID(uuidString: "D0000001-0001-4000-8000-000000000007")!,
                chineseName: "Bitcoin",
                englishName: "Bitcoin",
                symbol: "BTC/USDT",
                category: .crypto,
                quoteCurrency: .usdt,
                quantity: Decimal(string: "0.11")!,
                averageCost: Decimal(84_500),
                latestPrice: Decimal(91_800),
                source: "OKX",
                freshness: .updated,
                dailyMultipliers: makeCurve(beta: 2.05, phase: 4.9, wiggle: 0.0165, todayChange: -0.0165)
            ),
            HoldingSpec(
                id: UUID(uuidString: "D0000001-0001-4000-8000-000000000008")!,
                chineseName: "招商银行",
                englishName: "China Merchants Bank",
                symbol: "600036",
                category: .cnStock,
                quoteCurrency: .cny,
                quantity: Decimal(2_500),
                averageCost: Decimal(string: "35.80")!,
                latestPrice: Decimal(string: "38.60")!,
                source: "东方财富",
                freshness: .updated,
                dailyMultipliers: makeCurve(beta: 0.85, phase: 5.5, wiggle: 0.0065, todayChange: -0.0052)
            ),
        ]
    }

    static func build(
        language: AppLanguage,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Dataset {
        let todayStart = calendar.startOfDay(for: now)
        let fetchedDate = now.addingTimeInterval(-180)
        let fetchedTimestamp = ISO8601DateFormatter().string(from: fetchedDate)
        let todayDayString = PositionClosureMath.day(now)
        let allSpecs = specs

        let totalCostCNY: Decimal = allSpecs.reduce(Decimal.zero) { sum, spec in
            sum + (spec.quantity * spec.averageCost / spec.quoteCurrency.rateFromCNY)
        }

        // Precompute exact daily unit prices for each holding across the 30-day window.
        let dailyPriceTables: [[Decimal]] = allSpecs.map { spec in
            spec.dailyMultipliers.enumerated().map { index, multiplier in
                if spec.category == .cash || index == 29 {
                    return spec.latestPrice
                }
                let raw = spec.latestPrice.doubleValue * multiplier
                return roundedPrice(raw, category: spec.category)
            }
        }

        // Build 30 PortfolioSnapshots and 29 DailyProfitPoints from exact daily holdings valuations.
        var snapshots: [PortfolioSnapshot] = []
        var dailyProfits: [DailyProfitPoint] = []
        var previousTotalValueCNY: Decimal?

        for dayIndex in 0..<30 {
            let offset = dayIndex - 29
            let dayDate = calendar.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
            var dayTotalValueCNY = Decimal.zero
            for (specIndex, spec) in allSpecs.enumerated() {
                let price = dailyPriceTables[specIndex][dayIndex]
                dayTotalValueCNY += spec.quantity * price / spec.quoteCurrency.rateFromCNY
            }
            let profitRateDouble: Double = totalCostCNY > 0
                ? ((dayTotalValueCNY - totalCostCNY) / totalCostCNY * 100).doubleValue
                : 0
            snapshots.append(
                PortfolioSnapshot(
                    date: dayDate,
                    totalValueCNY: dayTotalValueCNY.doubleValue,
                    profitRate: profitRateDouble,
                    costIsKnown: true
                )
            )
            if let previous = previousTotalValueCNY {
                dailyProfits.append(
                    DailyProfitPoint(
                        date: dayDate,
                        amountCNY: dayTotalValueCNY - previous
                    )
                )
            }
            previousTotalValueCNY = dayTotalValueCNY
        }

        // Build current Position models with exact 7-day sparkline and yesterday baseline.
        let positions: [Position] = allSpecs.enumerated().map { specIndex, spec in
            let prices = dailyPriceTables[specIndex]
            let latest = prices[29]
            let yesterday = prices[28]
            let marketValueCNY = spec.quantity * latest / spec.quoteCurrency.rateFromCNY
            let profitRate: Decimal = spec.averageCost == 0
                ? 0
                : (latest - spec.averageCost) / spec.averageCost * 100
            let weeklyTrend = prices.suffix(7).map(\.doubleValue)
            let baseline: PositionDailyPriceBaseline? = spec.category == .cash
                ? nil
                : PositionDailyPriceBaseline(
                    day: todayDayString,
                    price: yesterday,
                    unitValueCNY: yesterday / spec.quoteCurrency.rateFromCNY
                )
            return Position(
                id: spec.id,
                name: language == .english ? spec.englishName : spec.chineseName,
                symbol: spec.symbol,
                category: spec.category,
                quoteCurrency: spec.quoteCurrency,
                quantity: spec.quantity,
                averageCost: spec.averageCost,
                latestPrice: latest,
                marketValueCNY: marketValueCNY,
                profitRate: profitRate,
                weeklyTrend: weeklyTrend,
                source: spec.source,
                quoteTime: todayDayString,
                fetchedAt: fetchedTimestamp,
                freshness: spec.freshness,
                dailyPriceBaseline: baseline,
                costIsKnown: true
            )
        }

        let riskProfileUpdatedAt = calendar.date(byAdding: .day, value: -15, to: todayStart) ?? todayStart
        return Dataset(
            positions: positions,
            snapshotHistory: snapshots,
            dailyProfitHistory: dailyProfits,
            riskProfileDraft: .defaultBalanced,
            riskProfileUpdatedAt: riskProfileUpdatedAt
        )
    }

    private static func roundedPrice(_ raw: Double, category: AssetCategory) -> Decimal {
        let scale: Double = switch category {
        case .fund: 1_000
        case .crypto: 1
        default: 100
        }
        let rounded = (raw * scale).rounded() / scale
        return Decimal(string: String(format: scale == 1 ? "%.0f" : (scale == 1_000 ? "%.3f" : "%.2f"), rounded))
            ?? Decimal(rounded)
    }

    /// Built-in thematic domain mapping for Demo Mode so Investment Map Distribution
    /// always renders rich domains (never "待识别领域") without spending LLM tokens.
    static func investmentDistributionAssets(for positions: [Position]) -> [AssetInvestmentDistribution] {
        positions.compactMap { position in
            let domain: InvestmentDomain?
            switch position.symbol.uppercased() {
            case "AAPL", "NVDA":
                domain = InvestmentDomain(id: "us_tech_equity", titleChinese: "美股科技", titleEnglish: "US Tech Equities")
            case "510300":
                domain = InvestmentDomain(id: "cn_broad_equity_fund", titleChinese: "A股宽基", titleEnglish: "China Broad Equity")
            case "004672":
                domain = InvestmentDomain(id: "cn_bonds", titleChinese: "人民币债券", titleEnglish: "CNY Bonds")
            case "00700.HK":
                domain = InvestmentDomain(id: "hk_tech_stock", titleChinese: "港股互联网", titleEnglish: "HK Internet")
            case "600036":
                domain = InvestmentDomain(id: "cn_financial_stock", titleChinese: "中国金融", titleEnglish: "China Financials")
            default:
                domain = InvestmentDistributionEngine.localDomain(for: position)
            }
            guard let domain else { return nil }
            return AssetInvestmentDistribution(
                positionRef: InvestmentProfileEngine.positionRef(for: position),
                identityFingerprint: InvestmentDistributionEngine.identityFingerprint(position),
                allocations: [InvestmentDomainWeight(domain: domain, weight: 1)]
            )
        }
    }
}
