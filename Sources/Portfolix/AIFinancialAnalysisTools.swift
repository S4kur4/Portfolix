import Foundation

enum AILocalFinancialToolName: String, Codable, CaseIterable, Sendable {
    case portfolioSnapshot = "portfolio_snapshot"
    case concentrationAnalysis = "concentration_analysis"
    case performanceWindows = "performance_windows"
    case constraintEvaluation = "constraint_evaluation"
}

struct AIEvidenceItem: Codable, Equatable, Sendable {
    let id: String
    let kind: String
    let metric: String
    let valueText: String
    let numericValue: Double?
    let unit: String?
    let positionRefs: [String]
    let asOf: String
    let source: String
    let confidence: String
    let sourceURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case metric
        case valueText = "value_text"
        case numericValue = "numeric_value"
        case unit
        case positionRefs = "position_refs"
        case asOf = "as_of"
        case source
        case confidence
        case sourceURL = "source_url"
    }
}

struct AILocalFinancialToolResult: Codable, Equatable, Sendable {
    let callID: String
    let tool: AILocalFinancialToolName
    let status: String
    let evidence: [AIEvidenceItem]
    let limitations: [String]

    enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case tool
        case status
        case evidence
        case limitations
    }
}

struct AIEvidenceLedger: Codable, Equatable, Sendable {
    let schemaVersion: String
    let generatedAt: Date
    let items: [AIEvidenceItem]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case items
    }
}

enum AILocalFinancialToolExecutor {
    static func baselineResults(input: AIAnalysisInput) -> [AILocalFinancialToolResult] {
        [
            portfolioSnapshot(input: input),
            concentrationAnalysis(input: input),
            performanceWindows(input: input),
            constraintEvaluation(input: input),
        ]
    }

    private static func portfolioSnapshot(input: AIAnalysisInput) -> AILocalFinancialToolResult {
        let positions = input.metrics.positions
        let asOf = input.snapshot.generatedAt
        let totalValueCNY = positions.reduce(0) { result, position in
            result + (Double(position.marketValueCNY) ?? 0)
        }
        let investableCount = positions.filter { $0.assetType != AssetCategory.cash.aiCode }.count
        let items = [
            evidence(
                id: "local.portfolio.total_value_cny",
                metric: "portfolio_total_value_cny",
                numericValue: totalValueCNY,
                unit: "CNY",
                asOf: asOf
            ),
            evidence(
                id: "local.portfolio.position_count",
                metric: "position_count",
                numericValue: Double(positions.count),
                unit: "count",
                asOf: asOf
            ),
            evidence(
                id: "local.portfolio.investable_position_count",
                metric: "investable_position_count",
                numericValue: Double(investableCount),
                unit: "count",
                asOf: asOf
            ),
            evidence(
                id: "local.data_quality.stale_allocation_pct",
                metric: "stale_quote_allocation_pct",
                numericValue: input.metrics.dataQuality.staleQuoteAllocationPct,
                unit: "percent",
                asOf: asOf
            ),
            evidence(
                id: "local.data_quality.manual_allocation_pct",
                metric: "manual_quote_allocation_pct",
                numericValue: input.metrics.dataQuality.manualQuoteAllocationPct,
                unit: "percent",
                asOf: asOf
            ),
        ]
        return AILocalFinancialToolResult(
            callID: "local_portfolio_snapshot",
            tool: .portfolioSnapshot,
            status: "ok",
            evidence: items,
            limitations: []
        )
    }

    private static func concentrationAnalysis(input: AIAnalysisInput) -> AILocalFinancialToolResult {
        let positions = input.metrics.positions.filter {
            $0.assetType != AssetCategory.cash.aiCode && $0.allocationPct > 0
        }
        let sorted = positions.sorted { $0.allocationPct > $1.allocationPct }
        let investableAllocation = sorted.reduce(0) { $0 + $1.allocationPct }
        let weights = sorted.map {
            investableAllocation > 0 ? max(0, $0.allocationPct) / investableAllocation : 0
        }
        let sumOfSquares = weights.reduce(0) { $0 + $1 * $1 }
        let hhi = sumOfSquares * 10_000
        let effectiveHoldings = sumOfSquares > 0 ? 1 / sumOfSquares : 0
        let asOf = input.snapshot.generatedAt
        let top1 = sorted.prefix(1).reduce(0) { $0 + $1.allocationPct }
        let top3 = sorted.prefix(3).reduce(0) { $0 + $1.allocationPct }
        let top5 = sorted.prefix(5).reduce(0) { $0 + $1.allocationPct }
        let topRefs = Array(sorted.prefix(5).map(\.positionRef))
        let items = [
            evidence(
                id: "local.concentration.investable_hhi",
                metric: "investable_herfindahl_hirschman_index",
                numericValue: hhi,
                unit: "index_0_10000",
                positionRefs: topRefs,
                asOf: asOf
            ),
            evidence(
                id: "local.concentration.effective_investable_holdings",
                metric: "effective_number_of_investable_holdings",
                numericValue: effectiveHoldings,
                unit: "count",
                positionRefs: topRefs,
                asOf: asOf
            ),
            evidence(
                id: "local.concentration.top_1_pct",
                metric: "top_1_allocation_pct",
                numericValue: top1,
                unit: "percent",
                positionRefs: Array(sorted.prefix(1).map(\.positionRef)),
                asOf: asOf
            ),
            evidence(
                id: "local.concentration.top_3_pct",
                metric: "top_3_allocation_pct",
                numericValue: top3,
                unit: "percent",
                positionRefs: Array(sorted.prefix(3).map(\.positionRef)),
                asOf: asOf
            ),
            evidence(
                id: "local.concentration.top_5_pct",
                metric: "top_5_allocation_pct",
                numericValue: top5,
                unit: "percent",
                positionRefs: topRefs,
                asOf: asOf
            ),
        ]
        return AILocalFinancialToolResult(
            callID: "local_concentration_analysis",
            tool: .concentrationAnalysis,
            status: positions.isEmpty ? "empty" : "ok",
            evidence: items,
            limitations: positions.isEmpty ? ["no_investable_positions"] : []
        )
    }

    private static func performanceWindows(input: AIAnalysisInput) -> AILocalFinancialToolResult {
        let asOf = input.snapshot.generatedAt
        let week = weightedPerformance(
            positions: input.metrics.positions.filter { $0.assetType != AssetCategory.cash.aiCode },
            window: { $0.oneWeek },
            prefix: "one_week",
            asOf: asOf
        )
        let month = weightedPerformance(
            positions: input.metrics.positions.filter { $0.assetType != AssetCategory.cash.aiCode },
            window: { $0.oneMonth },
            prefix: "one_month",
            asOf: asOf
        )
        let evidence = week.items + month.items
        let unavailable = [week.availableAllocationPct, month.availableAllocationPct].allSatisfy { $0 == 0 }
        return AILocalFinancialToolResult(
            callID: "local_performance_windows",
            tool: .performanceWindows,
            status: unavailable ? "partial" : "ok",
            evidence: evidence,
            limitations: unavailable ? ["historical_price_coverage_unavailable"] : []
        )
    }

    private static func constraintEvaluation(input: AIAnalysisInput) -> AILocalFinancialToolResult {
        let asOf = input.snapshot.generatedAt
        var items = [
            evidence(
                id: "local.constraints.fit_score",
                metric: "constraint_fit_score",
                numericValue: input.score.constraintFitScore,
                unit: "score_0_100",
                asOf: asOf
            ),
            evidence(
                id: "local.constraints.breached_count",
                metric: "breached_constraint_count",
                numericValue: Double(input.score.breachedConstraintCount),
                unit: "count",
                asOf: asOf
            ),
        ]
        items.append(contentsOf: input.riskFlags.map { flag in
            evidence(
                id: "local.risk_flag.\(safeID(flag.code))",
                metric: flag.code,
                numericValue: flag.metricValue,
                unit: flag.unit,
                positionRefs: flag.relatedRefs,
                asOf: asOf
            )
        })
        return AILocalFinancialToolResult(
            callID: "local_constraint_evaluation",
            tool: .constraintEvaluation,
            status: "ok",
            evidence: items,
            limitations: []
        )
    }

    private static func weightedPerformance(
        positions: [AIPositionContext],
        window: (AIPositionContext) -> AIPerformanceWindowContext,
        prefix: String,
        asOf: String
    ) -> (items: [AIEvidenceItem], availableAllocationPct: Double) {
        let available = positions.compactMap { position -> (AIPositionContext, AIPerformanceWindowContext)? in
            let value = window(position)
            guard value.status == "available", value.returnRatePct != nil else { return nil }
            return (position, value)
        }
        let coverage = available.reduce(0) { $0 + $1.0.allocationPct }
        let weightedContribution = available.reduce(0) { result, entry in
            result + entry.0.allocationPct / 100 * (entry.1.returnRatePct ?? 0)
        }
        let normalizedReturn = coverage > 0 ? weightedContribution / (coverage / 100) : nil
        let refs = available.map { $0.0.positionRef }
        return (
            [
                evidence(
                    id: "local.performance.\(prefix).coverage_pct",
                    metric: "\(prefix)_available_allocation_pct",
                    numericValue: coverage,
                    unit: "percent",
                    positionRefs: refs,
                    asOf: asOf
                ),
                evidence(
                    id: "local.performance.\(prefix).weighted_return_pct",
                    metric: "\(prefix)_current_weighted_return_pct",
                    numericValue: normalizedReturn,
                    unit: "percent",
                    positionRefs: refs,
                    asOf: asOf
                ),
            ],
            coverage
        )
    }

    private static func evidence(
        id: String,
        metric: String,
        numericValue: Double?,
        unit: String,
        positionRefs: [String] = [],
        asOf: String
    ) -> AIEvidenceItem {
        AIEvidenceItem(
            id: id,
            kind: "calculation",
            metric: metric,
            valueText: numericValue.map { String(format: "%.6f", $0) } ?? "unavailable",
            numericValue: numericValue,
            unit: unit,
            positionRefs: positionRefs,
            asOf: asOf,
            source: "portfolix_local_financial_tool",
            confidence: numericValue == nil ? "unavailable" : "deterministic",
            sourceURL: nil
        )
    }

    private static func safeID(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_.-]+"#, with: "_", options: .regularExpression)
    }
}

enum AIEvidenceLedgerBuilder {
    static func build(
        localResults: [AILocalFinancialToolResult],
        webResults: [AIWebSearchToolResult],
        generatedAt: Date = Date()
    ) -> AIEvidenceLedger {
        let localItems = localResults.flatMap(\.evidence)
        let webItems = webResults.flatMap { result in
            result.sources.enumerated().map { index, source in
                AIEvidenceItem(
                    id: "web.\(result.callID).\(index + 1)",
                    kind: "web_source",
                    metric: "public_information_source",
                    valueText: source.title,
                    numericValue: nil,
                    unit: nil,
                    positionRefs: result.positionRefs,
                    asOf: ISO8601DateFormatter().string(from: result.searchedAt),
                    source: source.domain,
                    confidence: source.credibility.rawValue,
                    sourceURL: source.url
                )
            }
        }
        return AIEvidenceLedger(
            schemaVersion: "agent-evidence-ledger.v1",
            generatedAt: generatedAt,
            items: localItems + webItems
        )
    }
}
