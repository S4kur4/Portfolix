import Foundation

enum AIAnalysisTrigger: String, Codable {
    case manual
    case scheduled
}

enum AIAnalysisProgress: Equatable, Sendable {
    case refreshingPrices(assetCount: Int)
    case pricesRefreshed(updated: Int, total: Int)
    case preflight
    case buildingInput
    case planningToolCalls
    case callingWebSearch(query: String, ordinal: Int, total: Int)
    case webSearchResultsReady(callCount: Int, sourceCount: Int)
    case generatingReport(model: String)
    case repairingReport
    case validatingReport
    case preparingArtifacts
    case savingReport

    var telemetryID: String {
        switch self {
        case .refreshingPrices: "refreshing_prices"
        case .pricesRefreshed: "prices_refreshed"
        case .preflight: "preflight"
        case .buildingInput: "building_input"
        case .planningToolCalls: "planning_tool_calls"
        case .callingWebSearch: "calling_web_search"
        case .webSearchResultsReady: "web_search_results_ready"
        case .generatingReport: "generating_report"
        case .repairingReport: "repairing_report"
        case .validatingReport: "validating_report"
        case .preparingArtifacts: "preparing_artifacts"
        case .savingReport: "saving_report"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case let .refreshingPrices(assetCount):
            localizedText("正在更新 \(assetCount) 项资产价格", "Refreshing prices for \(assetCount) assets", language: language)
        case let .pricesRefreshed(updated, total):
            localizedText("已更新 \(updated)/\(total) 项资产价格", "Updated prices for \(updated)/\(total) assets", language: language)
        case .preflight:
            localizedText("正在检查分析配置", "Checking analysis configuration", language: language)
        case .buildingInput:
            localizedText("正在整理完整持仓与历史表现", "Preparing complete holdings and historical performance", language: language)
        case .planningToolCalls:
            localizedText("正在判断是否需要联网搜索", "Deciding whether connected search is needed", language: language)
        case let .callingWebSearch(query, _, _):
            localizedText("正在搜索 \(shortened(query))", "Searching \(shortened(query))", language: language)
        case .webSearchResultsReady:
            localizedText("联网搜索结果已整理", "Connected search results are ready", language: language)
        case .generatingReport:
            localizedText("正在分析组合并生成报告", "Analyzing the portfolio and generating the report", language: language)
        case .repairingReport:
            localizedText("正在修复模型返回", "Repairing the model response", language: language)
        case .validatingReport:
            localizedText("正在执行报告安全校验", "Running report safety checks", language: language)
        case .preparingArtifacts:
            localizedText("正在整理分析审计记录", "Preparing analysis audit records", language: language)
        case .savingReport:
            localizedText("正在保存报告与运行记录", "Saving the report and run record", language: language)
        }
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .refreshingPrices:
            localizedText("逐项获取最新报价；失败项保留原价格并标记数据状态", "Fetching current quotes; failed items retain their prior price and data status", language: language)
        case let .pricesRefreshed(updated, total):
            localizedText("本次成功刷新 \(updated) 项，共 \(total) 项持仓", "Refreshed \(updated) of \(total) holdings", language: language)
        case .preflight:
            localizedText("核对持仓、模型配置和凭据状态", "Checking holdings, model configuration, and credentials", language: language)
        case .buildingInput:
            localizedText("核对持仓明细、区间表现和风险约束", "Checking holdings, performance, and risk constraints", language: language)
        case .planningToolCalls:
            localizedText("检查报告是否依赖近期公开信息", "Checking whether recent public information is needed", language: language)
        case let .callingWebSearch(_, ordinal, total):
            localizedText("受控联网搜索 \(ordinal)/\(total)", "Controlled connected search \(ordinal)/\(total)", language: language)
        case let .webSearchResultsReady(callCount, sourceCount):
            localizedText("完成 \(callCount) 次搜索，保留 \(sourceCount) 个可信来源", "Completed \(callCount) searches and retained \(sourceCount) trusted sources", language: language)
        case let .generatingReport(model):
            localizedText("模型：\(shortened(model))", "Model: \(shortened(model))", language: language)
        case .repairingReport:
            localizedText("模型首次返回未满足结构或安全预检，正在受限重试一次", "The first response failed structure or safety preflight; retrying once", language: language)
        case .validatingReport:
            localizedText("检查结构、引用、来源 URL 与信息安全边界", "Checking structure, references, source URLs, and information security boundaries", language: language)
        case .preparingArtifacts:
            localizedText("整理本次分析过程和校验结果", "Organizing the analysis and validation results", language: language)
        case .savingReport:
            localizedText("事务写入本地数据库", "Writing to the local database transactionally", language: language)
        }
    }

    func failureContext(language: AppLanguage) -> String {
        switch self {
        case .refreshingPrices, .pricesRefreshed: localizedText("更新资产价格", "price refresh", language: language)
        case .preflight: localizedText("配置检查", "configuration check", language: language)
        case .buildingInput: localizedText("整理组合数据", "portfolio data preparation", language: language)
        case .planningToolCalls: localizedText("判断联网需求", "connected information assessment", language: language)
        case .callingWebSearch, .webSearchResultsReady: localizedText("联网搜索", "connected search", language: language)
        case .generatingReport: localizedText("生成分析报告", "report generation", language: language)
        case .repairingReport: localizedText("修复模型返回", "model response repair", language: language)
        case .validatingReport: localizedText("报告安全校验", "report safety validation", language: language)
        case .preparingArtifacts: localizedText("整理审计记录", "audit artifact preparation", language: language)
        case .savingReport: localizedText("保存分析结果", "analysis persistence", language: language)
        }
    }

    private func shortened(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }
}

typealias AIAnalysisProgressHandler = @Sendable (AIAnalysisProgress) async -> Void

enum AIFollowUpProgress: Equatable, Sendable {
    case analyzing
    case searching(query: String, ordinal: Int, total: Int)
    case composing

    func title(language: AppLanguage) -> String {
        switch self {
        case .analyzing:
            localizedText("正在理解你的问题", "Understanding your question", language: language)
        case let .searching(query, _, _):
            localizedText("正在搜索 \(shortened(query))", "Searching \(shortened(query))", language: language)
        case .composing:
            localizedText("正在整理回答", "Preparing the answer", language: language)
        }
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .analyzing:
            localizedText("正在结合当前报告与持仓信息进行分析", "Reviewing the current report and holdings", language: language)
        case let .searching(_, ordinal, total):
            localizedText("联网补充近期公开信息 \(ordinal)/\(total)", "Checking recent public information \(ordinal)/\(total)", language: language)
        case .composing:
            localizedText("正在把分析结果转化为清晰、易读的说明", "Turning the analysis into a clear response", language: language)
        }
    }

    private func shortened(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }
}

typealias AIFollowUpProgressHandler = @Sendable (AIFollowUpProgress) async -> Void

enum AIAnalysisRunStatus: Equatable {
    case idle
    case missingConfiguration(String)
    case running(AIAnalysisProgress)
    case completed
    case failed(String)

    func title(language: AppLanguage) -> String {
        switch self {
        case .idle:
            return localizedText("准备生成", "Ready", language: language)
        case let .missingConfiguration(message):
            return message
        case let .running(progress):
            return progress.title(language: language)
        case .completed:
            return localizedText("分析已完成", "Analysis completed", language: language)
        case let .failed(message):
            return message
        }
    }
}

struct AIAnalysisRun: Equatable {
    var status: AIAnalysisRunStatus = .idle
    var startedAt: Date?
    var finishedAt: Date?
    var model: String?
    var searchCount = 0
    var usedFallback = false
    var fallbackReason: String?
}

enum AIChatRetentionPeriod: String, CaseIterable, Identifiable {
    case oneWeek
    case oneMonth
    case threeMonths

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .oneWeek: 7
        case .oneMonth: 30
        case .threeMonths: 90
        }
    }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.oneWeek, .chinese): "1 周"
        case (.oneMonth, .chinese): "1 个月"
        case (.threeMonths, .chinese): "3 个月"
        case (.oneWeek, .english): "1 week"
        case (.oneMonth, .english): "1 month"
        case (.threeMonths, .english): "3 months"
        }
    }

    func cutoffDate(now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: -dayCount, to: now) ?? now
    }
}

enum AIReportChatContent: Equatable {
    case user(String)
    case report(AIAnalysisReport, AIAnalysisRun)
    case assistant(String)
}

struct AIReportChatItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case user
        case report
        case assistant
    }

    struct RunSnapshot: Codable, Equatable {
        let model: String?
        let usedFallback: Bool
        let fallbackReason: String?

        init(run: AIAnalysisRun) {
            model = run.model
            usedFallback = run.usedFallback
            fallbackReason = run.fallbackReason
        }

        var run: AIAnalysisRun {
            AIAnalysisRun(
                status: .completed,
                model: model,
                usedFallback: usedFallback,
                fallbackReason: fallbackReason
            )
        }
    }

    let id: UUID
    let createdAt: Date
    let kind: Kind
    let text: String?
    let report: AIAnalysisReport?
    let runSnapshot: RunSnapshot?

    var content: AIReportChatContent {
        switch kind {
        case .user:
            .user(text ?? "")
        case .assistant:
            .assistant(text ?? "")
        case .report:
            if let report {
                .report(report, runSnapshot?.run ?? AIAnalysisRun(status: .completed, model: report.model))
            } else {
                .assistant("这条历史分析记录无法读取。")
            }
        }
    }

    static func user(_ text: String, createdAt: Date = .now) -> AIReportChatItem {
        AIReportChatItem(id: UUID(), createdAt: createdAt, kind: .user, text: text, report: nil, runSnapshot: nil)
    }

    static func report(_ report: AIAnalysisReport, _ run: AIAnalysisRun) -> AIReportChatItem {
        AIReportChatItem(
            id: report.id,
            createdAt: report.generatedAt,
            kind: .report,
            text: nil,
            report: report,
            runSnapshot: RunSnapshot(run: run)
        )
    }

    static func assistant(_ text: String, createdAt: Date = .now) -> AIReportChatItem {
        AIReportChatItem(id: UUID(), createdAt: createdAt, kind: .assistant, text: text, report: nil, runSnapshot: nil)
    }

    func migratingLegacyPromptText() -> AIReportChatItem {
        guard let text else { return self }
        let migratedText: String
        switch kind {
        case .assistant:
            migratedText = AIUserFacingTextSanitizer.sanitize(text)
        case .user:
            switch text {
            case "请重新生成一份智能分析报告":
                migratedText = "请重新生成分析报告"
            case "Regenerate the smart analysis report":
                migratedText = "Regenerate the analysis report"
            default:
                return self
            }
        case .report:
            return self
        }
        guard migratedText != text else { return self }
        return AIReportChatItem(
            id: id,
            createdAt: createdAt,
            kind: kind,
            text: migratedText,
            report: report,
            runSnapshot: runSnapshot
        )
    }
}

struct AIAnalysisAgentResult: Equatable {
    let report: AIAnalysisReport
    let artifacts: AIAnalysisArtifactBundle
}

struct AIAnalysisArtifactBundle: Codable, Equatable {
    let inputJSON: String
    let toolResultsJSON: String
    let toolPlanJSON: String
    let rawReportJSON: String
    let repairedReportJSON: String?
    let finalReportJSON: String
    let guardrailResultJSON: String
}

struct AIAnalysisFollowUpResult: Equatable {
    let answer: String
    let guardrailResultJSON: String
    let searchMode: String
    let toolCallCount: Int
    let toolResultCount: Int
}

struct PersistedAIAnalysisRun: Codable, Equatable {
    let id: UUID
    let trigger: String
    let status: String
    let analysisMode: String
    let model: String
    let provider: String
    let privacyMode: String
    let riskProfileVersion: Int
    let inputFingerprint: String
    let startedAt: Date
    let finishedAt: Date?
    let usedFallback: Bool
    let errorCode: String?
    let report: AIAnalysisReport?
    let artifacts: AIAnalysisArtifactBundle?

    init(
        id: UUID = UUID(),
        trigger: String,
        status: String,
        analysisMode: String,
        model: String,
        provider: String,
        privacyMode: String,
        riskProfileVersion: Int,
        inputFingerprint: String,
        startedAt: Date,
        finishedAt: Date?,
        usedFallback: Bool,
        errorCode: String?,
        report: AIAnalysisReport?,
        artifacts: AIAnalysisArtifactBundle?
    ) {
        self.id = id
        self.trigger = trigger
        self.status = status
        self.analysisMode = analysisMode
        self.model = model
        self.provider = provider
        self.privacyMode = privacyMode
        self.riskProfileVersion = riskProfileVersion
        self.inputFingerprint = inputFingerprint
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.usedFallback = usedFallback
        self.errorCode = errorCode
        self.report = report
        self.artifacts = artifacts
    }
}

struct AssetResearchResult: Codable, Identifiable, Equatable {
    let id: UUID
    let positionRef: String
    let assetName: String
    let symbol: String
    let category: String
    let query: String
    let searchedAt: Date
    let status: String
    let sourceCount: Int
    let results: [AssetResearchSource]

    init(
        id: UUID = UUID(),
        positionRef: String,
        assetName: String,
        symbol: String,
        category: String,
        query: String,
        searchedAt: Date,
        status: String,
        sourceCount: Int,
        results: [AssetResearchSource]
    ) {
        self.id = id
        self.positionRef = positionRef
        self.assetName = assetName
        self.symbol = symbol
        self.category = category
        self.query = query
        self.searchedAt = searchedAt
        self.status = status
        self.sourceCount = sourceCount
        self.results = results
    }
}

struct AssetResearchSource: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let url: String
    let domain: String
    let publishedDate: String?
    let snippet: String
    let credibility: SourceCredibility

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        domain: String,
        publishedDate: String?,
        snippet: String,
        credibility: SourceCredibility
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.domain = domain
        self.publishedDate = publishedDate
        self.snippet = snippet
        self.credibility = credibility
    }
}

enum SourceCredibility: String, Codable, Equatable, Sendable {
    case official
    case mainstream
    case general

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.official, .chinese): "官方"
        case (.mainstream, .chinese): "财经媒体"
        case (.general, .chinese): "一般来源"
        case (.official, .english): "Official"
        case (.mainstream, .english): "Media"
        case (.general, .english): "General"
        }
    }
}

struct AIAnalysisReport: Codable, Identifiable, Equatable {
    let id: UUID
    let generatedAt: Date
    let searchedAt: Date
    let model: String
    let promptVersion: String
    let riskProfileVersion: Int
    let summary: String
    let healthScoreExplanation: String
    let riskItems: [AIReportRiskItem]
    let assetAlerts: [AIAssetAlert]
    let rebalanceActions: [AIRebalanceAction]?
    let questionsToConsider: [String]
    let dataQualityNotes: [String]
    let limitations: [String]
    let sources: [AIReportSource]

    init(
        id: UUID = UUID(),
        generatedAt: Date,
        searchedAt: Date,
        model: String,
        promptVersion: String,
        riskProfileVersion: Int,
        summary: String,
        healthScoreExplanation: String,
        riskItems: [AIReportRiskItem],
        assetAlerts: [AIAssetAlert],
        rebalanceActions: [AIRebalanceAction]? = nil,
        questionsToConsider: [String],
        dataQualityNotes: [String],
        limitations: [String],
        sources: [AIReportSource]
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.searchedAt = searchedAt
        self.model = model
        self.promptVersion = promptVersion
        self.riskProfileVersion = riskProfileVersion
        self.summary = summary
        self.healthScoreExplanation = healthScoreExplanation
        self.riskItems = riskItems
        self.assetAlerts = assetAlerts
        self.rebalanceActions = rebalanceActions
        self.questionsToConsider = questionsToConsider
        self.dataQualityNotes = dataQualityNotes
        self.limitations = limitations
        self.sources = sources
    }
}

struct AIInvestmentProfile: Codable, Identifiable, Equatable {
    let id: UUID
    let generatedAt: Date
    let profileDate: String
    let model: String
    let promptVersion: String
    let riskProfileVersion: Int
    let inputFingerprint: String
    let dimensions: [AIInvestmentProfileScore]
    let summary: String
    let confidence: String

    init(
        id: UUID = UUID(),
        generatedAt: Date,
        profileDate: String,
        model: String,
        promptVersion: String,
        riskProfileVersion: Int,
        inputFingerprint: String,
        dimensions: [AIInvestmentProfileScore],
        summary: String,
        confidence: String
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.profileDate = profileDate
        self.model = model
        self.promptVersion = promptVersion
        self.riskProfileVersion = riskProfileVersion
        self.inputFingerprint = inputFingerprint
        self.dimensions = dimensions
        self.summary = summary
        self.confidence = confidence
    }
}

struct AIInvestmentProfileScore: Codable, Equatable {
    let id: String
    let score: Double
    let reason: String
}

struct AIReportRiskItem: Codable, Identifiable, Equatable {
    let id: UUID
    let severity: String
    let category: String
    let title: String
    let evidence: String
    let impact: String
    let relatedRefs: [String]

    init(
        id: UUID = UUID(),
        severity: String,
        category: String,
        title: String,
        evidence: String,
        impact: String,
        relatedRefs: [String]
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.title = title
        self.evidence = evidence
        self.impact = impact
        self.relatedRefs = relatedRefs
    }
}

struct AIAssetAlert: Codable, Identifiable, Equatable {
    let id: UUID
    let assetName: String
    let symbol: String
    let title: String
    let reason: String
    let sourceDomains: [String]

    init(
        id: UUID = UUID(),
        assetName: String,
        symbol: String,
        title: String,
        reason: String,
        sourceDomains: [String]
    ) {
        self.id = id
        self.assetName = assetName
        self.symbol = symbol
        self.title = title
        self.reason = reason
        self.sourceDomains = sourceDomains
    }
}

struct AIRebalanceAction: Codable, Identifiable, Equatable {
    let id: UUID
    let action: String
    let assetName: String?
    let symbol: String?
    let title: String
    let rationale: String
    let riskNote: String?

    init(
        id: UUID = UUID(),
        action: String,
        assetName: String?,
        symbol: String?,
        title: String,
        rationale: String,
        riskNote: String?
    ) {
        self.id = id
        self.action = action
        self.assetName = assetName
        self.symbol = symbol
        self.title = title
        self.rationale = rationale
        self.riskNote = riskNote
    }
}

struct AIReportSource: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let url: String
    let domain: String
    let assetName: String
    let credibility: SourceCredibility

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        domain: String,
        assetName: String,
        credibility: SourceCredibility
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.domain = domain
        self.assetName = assetName
        self.credibility = credibility
    }
}

enum AIAnalysisPromptVersion {
    static let report = AIAnalysisPromptText.reportVersion
}

enum AIResponseLanguage: String, Codable, Sendable {
    case simplifiedChinese = "zh-CN"
    case english = "en"

    static func detecting(from text: String) -> AIResponseLanguage {
        let normalized = text.lowercased()
        let chineseCues = ["吗", "呢", "如何", "为什么", "是否", "建议", "应该", "可以", "能否", "怎么看", "请", "帮我"]
        if chineseCues.contains(where: normalized.contains) {
            return .simplifiedChinese
        }

        let englishCues = Set([
            "what", "why", "how", "should", "can", "could", "would", "is", "are", "do", "does",
            "buy", "sell", "hold", "reduce", "increase", "explain", "compare", "risk", "price", "latest",
        ])
        let englishWords = normalized
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { word in word.unicodeScalars.allSatisfy { $0.isASCII } }
        if englishWords.contains(where: englishCues.contains) {
            return .english
        }

        let hanCount = normalized.unicodeScalars.filter { scalar in
            (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
        }.count
        if hanCount == 0 {
            return .english
        }
        let latinLetterCount = normalized.unicodeScalars.filter { scalar in
            (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
        }.count
        return latinLetterCount >= max(8, hanCount * 2) ? .english : .simplifiedChinese
    }

    func matchesUserFacingText(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let hanCount = scalars.filter { scalar in
            (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
        }.count
        let latinLetterCount = scalars.filter { scalar in
            (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
        }.count
        switch self {
        case .simplifiedChinese:
            return hanCount >= 4
        case .english:
            return latinLetterCount >= 12 && latinLetterCount >= hanCount * 2
        }
    }
}

struct AIAnalysisInput: Encodable {
    let schemaVersion = "ai-analysis-input.v7"
    let promptVersion = AIAnalysisPromptVersion.report
    let trigger: String
    let analysisMode: String
    let outputLanguage: AIResponseLanguage
    let snapshot: AIAnalysisSnapshot
    let privacyMode: String
    let riskProfileContext: AIRiskProfileContext
    let score: AIScoreContext
    let metrics: AIMetricsContext
    let rebalanceContext: AIRebalanceContext
    let previousReport: AIPreviousReportContext?
    let riskFlags: [AIRiskFlag]
}

struct AIAnalysisSnapshot: Encodable {
    let snapshotID: String
    let snapshotDate: String
    let displayCurrency: String
    let generatedAt: String
    let totalValueText: String
    let holdingReturnText: String
    let holdingReturnRateText: String
}

struct AIRiskProfileContext: Encodable {
    let status: String
    let riskProfileVersion: Int
    let riskLevel: String?
    let baseCurrency: String
    let thresholds: AIRiskThresholds
}

struct AIRiskThresholds: Encodable {
    let maxSinglePositionPct: Double?
    let maxCryptoAllocationPct: Double?
    let maxNonBaseCurrencyPct: Double?
    let minLiquidAssetsPct: Double?
}

struct AIScoreContext: Encodable {
    let constraintFitScore: Double?
    let passedConstraintCount: Int
    let breachedConstraintCount: Int
}

struct AIMetricsContext: Encodable {
    let allocationByAssetType: [AIAllocationContext]
    let allocationByCurrency: [AIAllocationContext]
    let positions: [AIPositionContext]
    let dataQuality: AIDataQualityContext
}

struct AIRebalanceContext: Encodable {
    let mode: String
    let guidance: String
    let signals: [AIRebalanceSignal]
}

struct AIRebalanceSignal: Encodable {
    let code: String
    let severity: String
    let title: String
    let detail: String
    let relatedRefs: [String]
    let metricValue: Double?
    let threshold: Double?
}

struct AIPreviousReportContext: Encodable {
    let generatedAt: String
    let summary: String
    let riskTitles: [String]
    let rebalanceTitles: [String]
}

struct AIAllocationContext: Encodable {
    let code: String
    let allocationPct: Double
}

struct AIPositionContext: Encodable {
    let positionRef: String
    let displayLabel: String?
    let symbol: String
    let assetType: String
    let quoteCurrency: String
    let quantity: String
    let averageCost: String
    let latestPrice: String
    let totalCostQuote: String
    let marketValueCNY: String
    let unrealizedProfitQuote: String
    let allocationPct: Double
    let unrealizedProfitRatePct: Double?
    let oneWeek: AIPerformanceWindowContext
    let oneMonth: AIPerformanceWindowContext
    let isStale: Bool
    let quoteTime: String
    let fetchedAt: String
    let source: String
}

struct AIPerformanceWindowContext: Encodable, Equatable, Sendable {
    let status: String
    let periodDays: Int
    let startDate: String?
    let endDate: String
    let startPrice: String?
    let endPrice: String
    let profitAmountQuote: String?
    let returnRatePct: Double?
    let observationDays: Int?
    let calculationBasis: String
}

struct AIPositionPerformanceContext: Equatable, Sendable {
    let oneWeek: AIPerformanceWindowContext
    let oneMonth: AIPerformanceWindowContext
}

struct AIDataQualityContext: Encodable {
    let missingQuoteAllocationPct: Double
    let staleQuoteAllocationPct: Double
    let manualQuoteAllocationPct: Double
}

struct AIRiskFlag: Encodable {
    let code: String
    let severity: String
    let relatedRefs: [String]
    let metricValue: Double?
    let threshold: Double?
    let unit: String
}

struct AIWebSearchToolCall: Codable, Equatable, Sendable {
    let id: String
    let query: String
    let positionRefs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case query
        case positionRefs = "position_refs"
    }
}

struct AIWebSearchToolPlan: Codable, Equatable, Sendable {
    let toolCalls: [AIWebSearchToolCall]
    let status: String?
    let limitations: [String]?

    init(
        toolCalls: [AIWebSearchToolCall],
        status: String? = nil,
        limitations: [String]? = nil
    ) {
        self.toolCalls = toolCalls
        self.status = status
        self.limitations = limitations
    }

    enum CodingKeys: String, CodingKey {
        case toolCalls = "tool_calls"
        case status
        case limitations
    }
}

struct AIWebSearchToolResult: Codable, Equatable, Sendable {
    let callID: String
    let query: String
    let positionRefs: [String]
    let searchedAt: Date
    let status: String
    let sources: [AssetResearchSource]
    let limitations: [String]

    enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case query
        case positionRefs = "position_refs"
        case searchedAt = "searched_at"
        case status
        case sources
        case limitations
    }
}

extension AssetCategory {
    var aiCode: String {
        switch self {
        case .cnStock: "cn_stock"
        case .bStock: "b_stock"
        case .hkStock: "hk_stock"
        case .usStock: "us_stock"
        case .fund: "public_fund"
        case .crypto: "crypto"
        case .cash: "cash"
        }
    }
}
