import Foundation

enum AIAnalysisTrigger: String, Codable {
    case manual
    case scheduled
}

enum AIAnalysisProgress: Equatable, Sendable {
    case loadingMarketData(assetCount: Int)
    case marketDataLoaded(total: Int)
    case preflight
    case buildingInput
    case planningToolCalls
    case replanningToolCalls(turn: Int, total: Int)
    case callingWebSearch(query: String, ordinal: Int, total: Int)
    case webSearchResultsReady(callCount: Int, sourceCount: Int)
    case evaluatingEvidence(turn: Int, total: Int)
    case generatingReport(model: String)
    case modelReasoning(model: String, elapsedSeconds: Int?)
    case modelOutputStarted
    case validatingModelOutput(attempt: Int, total: Int)
    case repairingReport(attempt: Int, total: Int, reason: String)
    case validatingReport
    case preparingArtifacts
    case savingReport

    var telemetryID: String {
        switch self {
        case .loadingMarketData: "loading_market_data"
        case .marketDataLoaded: "market_data_loaded"
        case .preflight: "preflight"
        case .buildingInput: "building_input"
        case .planningToolCalls: "planning_tool_calls"
        case .replanningToolCalls: "replanning_tool_calls"
        case .callingWebSearch: "calling_web_search"
        case .webSearchResultsReady: "web_search_results_ready"
        case .evaluatingEvidence: "evaluating_evidence"
        case .generatingReport: "generating_report"
        case .modelReasoning: "model_reasoning"
        case .modelOutputStarted: "model_output_started"
        case .validatingModelOutput: "validating_model_output"
        case .repairingReport: "repairing_report"
        case .validatingReport: "validating_report"
        case .preparingArtifacts: "preparing_artifacts"
        case .savingReport: "saving_report"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case let .loadingMarketData(assetCount):
            localizedText("正在同步 \(assetCount) 项资产最新行情", "Syncing latest quotes for \(assetCount) assets", language: language)
        case let .marketDataLoaded(total):
            localizedText("已载入 \(total) 项资产行情", "Loaded quotes for \(total) assets", language: language)
        case .preflight:
            localizedText("正在准备分析环境", "Preparing analysis", language: language)
        case .buildingInput:
            localizedText("正在梳理持仓结构与历史表现", "Reviewing holdings and performance", language: language)
        case .planningToolCalls:
            localizedText("正在评估是否需要检索市场动态", "Checking if market research is needed", language: language)
        case let .replanningToolCalls(turn, total):
            localizedText("正在补充市场检索 \(turn)/\(total)", "Refining research queries \(turn)/\(total)", language: language)
        case let .callingWebSearch(query, _, _):
            localizedText("正在检索 \(shortened(query))", "Searching \(shortened(query))", language: language)
        case .webSearchResultsReady:
            localizedText("市场公开信息已整理", "Market research ready", language: language)
        case .evaluatingEvidence:
            localizedText("正在交叉核验市场信息", "Cross-checking research findings", language: language)
        case .generatingReport:
            localizedText("正在深度分析组合表现", "Analyzing portfolio performance", language: language)
        case let .modelReasoning(_, elapsedSeconds):
            if let elapsedSeconds {
                localizedText(
                    "DeepSeek 深度推理中 · \(elapsedSeconds) 秒",
                    "DeepSeek is reasoning · \(elapsedSeconds)s",
                    language: language
                )
            } else {
                localizedText("DeepSeek 深度推理中", "DeepSeek started reasoning", language: language)
            }
        case .modelOutputStarted:
            localizedText("正在撰写分析报告", "Drafting analysis report", language: language)
        case .validatingModelOutput:
            localizedText("正在核对数据准确性", "Verifying figures and structure", language: language)
        case let .repairingReport(attempt, total, _):
            localizedText("正在整理报告格式 \(attempt)/\(total)", "Formatting report \(attempt)/\(total)", language: language)
        case .validatingReport:
            localizedText("正在复核引用与合规边界", "Verifying citations and guardrails", language: language)
        case .preparingArtifacts:
            localizedText("正在归档分析报告", "Archiving analysis report", language: language)
        case .savingReport:
            localizedText("正在保存分析报告", "Saving report locally", language: language)
        }
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .loadingMarketData:
            localizedText("同步已缓存的最新行情数据", "Syncing latest cached market quotes", language: language)
        case let .marketDataLoaded(total):
            localizedText("已核对 \(total) 项持仓的价格与历史净值", "Checked prices and history for \(total) holdings", language: language)
        case .preflight:
            localizedText("确认持仓、模型配置与连接状态", "Checking holdings, model, and connection status", language: language)
        case .buildingInput:
            localizedText("汇总持仓明细、区间收益与风险约束", "Summarizing holdings, returns, and risk limits", language: language)
        case .planningToolCalls:
            localizedText("判断是否需要结合近期公开市场信息", "Checking whether recent public market data is needed", language: language)
        case let .replanningToolCalls(turn, total):
            localizedText("补充关键市场信息（\(turn)/\(total)）", "Filling research gaps (\(turn)/\(total))", language: language)
        case let .callingWebSearch(_, ordinal, total):
            localizedText("检索公开市场信息 \(ordinal)/\(total)", "Searching market sources \(ordinal)/\(total)", language: language)
        case let .webSearchResultsReady(callCount, sourceCount):
            localizedText("已完成 \(callCount) 次检索，采纳 \(sourceCount) 条来源", "Completed \(callCount) searches across \(sourceCount) sources", language: language)
        case let .evaluatingEvidence(turn, total):
            localizedText("核验来源覆盖与信息时效（\(turn)/\(total)）", "Checking source coverage and recency (\(turn)/\(total))", language: language)
        case let .generatingReport(model):
            localizedText("模型：\(shortened(model))", "Model: \(shortened(model))", language: language)
        case let .modelReasoning(model, _):
            localizedText("模型：\(shortened(model)) · 推理过程不落盘", "Model: \(shortened(model)) · reasoning is not stored", language: language)
        case .modelOutputStarted:
            localizedText("正在接收完整分析内容", "Receiving analysis output", language: language)
        case let .validatingModelOutput(attempt, total):
            localizedText(
                "复核数值、语言与报告结构（\(attempt)/\(total)）",
                "Checking figures, language, and structure (\(attempt)/\(total))",
                language: language
            )
        case let .repairingReport(_, _, reason):
            localizedText("优化项：\(shortened(reason))", "Refining: \(shortened(reason))", language: language)
        case .validatingReport:
            localizedText("复核数据引用与来源链接", "Checking citations and source links", language: language)
        case .preparingArtifacts:
            localizedText("整理本次分析摘要与记录", "Organizing analysis summary and records", language: language)
        case .savingReport:
            localizedText("写入本机账本记录", "Saving to local ledger", language: language)
        }
    }

    func failureContext(language: AppLanguage) -> String {
        switch self {
        case .loadingMarketData, .marketDataLoaded: localizedText("读取行情数据", "market data loading", language: language)
        case .preflight: localizedText("配置检查", "configuration check", language: language)
        case .buildingInput: localizedText("整理组合数据", "portfolio data preparation", language: language)
        case .planningToolCalls, .replanningToolCalls: localizedText("判断联网需求", "connected information assessment", language: language)
        case .callingWebSearch, .webSearchResultsReady: localizedText("联网搜索", "connected search", language: language)
        case .evaluatingEvidence: localizedText("评估分析证据", "evidence evaluation", language: language)
        case .generatingReport, .modelReasoning, .modelOutputStarted: localizedText("生成分析报告", "report generation", language: language)
        case .validatingModelOutput: localizedText("模型输出校验", "model output validation", language: language)
        case .repairingReport: localizedText("修复模型返回", "model response repair", language: language)
        case .validatingReport: localizedText("报告安全校验", "report safety validation", language: language)
        case .preparingArtifacts: localizedText("整理审计记录", "audit artifact preparation", language: language)
        case .savingReport: localizedText("保存分析结果", "analysis persistence", language: language)
        }
    }

    private func shortened(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }
    func activityStepSpec(language: AppLanguage) -> (kind: AIAgentActivityStep.Kind, title: String, detail: String?) {
        switch self {
        case .preflight, .buildingInput:
            return (.localData, localizedText("核对组合与风险约束", "Reviewing portfolio & constraints", language: language), nil)
        case let .loadingMarketData(assetCount):
            return (
                .localData,
                localizedText("同步持仓行情", "Updating holding quotes", language: language),
                localizedText("\(assetCount) 项持仓", "\(assetCount) holdings", language: language)
            )
        case let .marketDataLoaded(total):
            return (
                .localData,
                localizedText("核对组合与行情", "Reviewed portfolio & quotes", language: language),
                localizedText("已同步 \(total) 项持仓", "\(total) holdings synced", language: language)
            )
        case .planningToolCalls, .replanningToolCalls:
            return (.plan, localizedText("规划公开资料检索", "Planning web research", language: language), nil)
        case let .callingWebSearch(query, _, _):
            return (
                .webSearch,
                localizedText("检索公开资料", "Searching public sources", language: language),
                shortened(query)
            )
        case let .webSearchResultsReady(callCount, sourceCount):
            return (
                .webSearch,
                localizedText("检索公开资料", "Searched public sources", language: language),
                localizedText("\(callCount) 次检索 · \(sourceCount) 条来源", "\(callCount) searches · \(sourceCount) sources", language: language)
            )
        case .evaluatingEvidence:
            return (.webSearch, localizedText("交叉核验公开来源", "Cross-checking sources", language: language), nil)
        case .generatingReport:
            return (.compose, localizedText("深度分析与撰写报告", "Analyzing & drafting report", language: language), nil)
        case let .modelReasoning(_, elapsedSeconds):
            let detail = elapsedSeconds.map { localizedText("深度推理 · \($0) 秒", "Reasoning · \($0)s", language: language) }
            return (.compose, localizedText("深度分析与撰写报告", "Analyzing & drafting report", language: language), detail)
        case .modelOutputStarted:
            return (.compose, localizedText("深度分析与撰写报告", "Analyzing & drafting report", language: language), localizedText("输出报告正文", "Writing report", language: language))
        case .validatingModelOutput, .validatingReport, .preparingArtifacts, .savingReport:
            return (.verify, localizedText("核验数据与生成报告", "Verifying & saving report", language: language), nil)
        case let .repairingReport(attempt, total, _):
            return (
                .verify,
                localizedText("核验并修正报告格式", "Refining report format", language: language),
                localizedText("第 \(attempt)/\(total) 次", "Attempt \(attempt)/\(total)", language: language)
            )
        }
    }
}

typealias AIAnalysisProgressHandler = @Sendable (AIAnalysisProgress) async -> Void

enum AIFollowUpProgress: Equatable, Sendable {
    case analyzing
    case replanning(turn: Int, total: Int)
    case searching(query: String, ordinal: Int, total: Int)
    case evaluatingEvidence(turn: Int, total: Int)
    case composing
    case reasoning(elapsedSeconds: Int?)
    case outputStarted
    case repairingResponse
    case readingLocalData

    func title(language: AppLanguage) -> String {
        switch self {
        case .analyzing:
            localizedText("正在理解你的问题", "Understanding your question", language: language)
        case .readingLocalData:
            localizedText("正在核对你的资产记录", "Checking your portfolio records", language: language)
        case let .replanning(turn, total):
            localizedText("正在调整搜索计划 \(turn)/\(total)", "Refining the search plan \(turn)/\(total)", language: language)
        case let .searching(query, _, _):
            localizedText("正在搜索 \(shortened(query))", "Searching \(shortened(query))", language: language)
        case .evaluatingEvidence:
            localizedText("正在评估搜索结果", "Evaluating search results", language: language)
        case .composing:
            localizedText("正在组织回复", "Drafting response", language: language)
        case let .reasoning(elapsedSeconds):
            if let elapsedSeconds {
                localizedText(
                    "DeepSeek 深度推理中 · \(elapsedSeconds) 秒",
                    "DeepSeek is reasoning · \(elapsedSeconds)s",
                    language: language
                )
            } else {
                localizedText("DeepSeek 深度推理中", "DeepSeek started reasoning", language: language)
            }
        case .outputStarted:
            localizedText("正在生成回复", "Generating response", language: language)
        case .repairingResponse:
            localizedText("正在整理回复格式", "Formatting response", language: language)
        }
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .analyzing:
            localizedText("结合当前报告与持仓记录进行分析", "Reviewing the current report and holdings", language: language)
        case .readingLocalData:
            localizedText("按需读取本机最新持仓与历史记录", "Reading the latest local holdings and history", language: language)
        case let .replanning(turn, total):
            localizedText("补充关键市场信息（\(turn)/\(total)）", "Filling research gaps (\(turn)/\(total))", language: language)
        case let .searching(_, ordinal, total):
            localizedText("检索公开市场信息 \(ordinal)/\(total)", "Searching market sources \(ordinal)/\(total)", language: language)
        case let .evaluatingEvidence(turn, total):
            localizedText("核验来源是否充分（\(turn)/\(total)）", "Checking source sufficiency (\(turn)/\(total))", language: language)
        case .composing:
            localizedText("正在组织清晰简洁的分析回复", "Drafting a clear response", language: language)
        case .reasoning:
            localizedText("推理过程仅用于本次回答，不会展示或保存", "Reasoning is not displayed or stored", language: language)
        case .outputStarted:
            localizedText("正在接收完整回答", "Receiving response", language: language)
        case .repairingResponse:
            localizedText("正在优化回答格式并重试", "Refining response format automatically", language: language)
        }
    }

    private func shortened(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }
    func activityStepSpec(language: AppLanguage) -> (kind: AIAgentActivityStep.Kind, title: String, detail: String?) {
        switch self {
        case .analyzing:
            return (.plan, localizedText("理解问题与制定步骤", "Understanding question", language: language), nil)
        case .replanning:
            return (.plan, localizedText("规划公开资料检索", "Planning web search", language: language), nil)
        case .readingLocalData:
            return (.localData, localizedText("核对本地持仓与记录", "Checking local portfolio records", language: language), nil)
        case let .searching(query, _, _):
            return (
                .webSearch,
                localizedText("检索公开资料", "Searching public sources", language: language),
                shortened(query)
            )
        case .evaluatingEvidence:
            return (.webSearch, localizedText("核验外部来源", "Verifying external sources", language: language), nil)
        case .composing:
            return (.compose, localizedText("整理分析回复", "Drafting response", language: language), nil)
        case let .reasoning(elapsedSeconds):
            let detail = elapsedSeconds.map { localizedText("深度推理 · \($0) 秒", "Reasoning · \($0)s", language: language) }
            return (.compose, localizedText("整理分析回复", "Drafting response", language: language), detail)
        case .outputStarted:
            return (.compose, localizedText("整理分析回复", "Drafting response", language: language), localizedText("输出回复正文", "Writing response", language: language))
        case .repairingResponse:
            return (.verify, localizedText("核验回复格式", "Verifying response format", language: language), nil)
        }
    }
}

typealias AIFollowUpProgressHandler = @Sendable (AIFollowUpProgress) async -> Void

struct AIAgentActivityLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

enum AIAgentActivityPolicy {
    static let maximumVisibleLineCount = 1

    static func appending(_ text: String, to lines: [AIAgentActivityLine]) -> [AIAgentActivityLine] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, lines.last?.text != normalized else { return lines }
        return Array((lines + [AIAgentActivityLine(text: normalized)]).suffix(maximumVisibleLineCount))
    }
}

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

struct AIAgentActivityStep: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case plan
        case localData
        case webSearch
        case verify
        case compose
    }

    enum Status: String, Codable, Sendable {
        case pending
        case running
        case completed
        case failed
    }

    let id: UUID
    let kind: Kind
    var title: String
    var detail: String?
    var status: Status

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        detail: String? = nil,
        status: Status = .running
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
    }
}

enum AIAgentActivityStepPolicy {
    static let maximumStoredSteps = 8

    static func recording(
        kind: AIAgentActivityStep.Kind,
        title: String,
        detail: String? = nil,
        into steps: [AIAgentActivityStep]
    ) -> [AIAgentActivityStep] {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return steps }
        let normalizedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = (normalizedDetail?.isEmpty == false) ? normalizedDetail : nil

        var updated = steps
        // If the immediately active step has the same kind, update it in place without creating duplicates.
        if let last = updated.last, last.status == .running, last.kind == kind {
            updated[updated.count - 1].title = normalizedTitle
            if let cleanDetail {
                updated[updated.count - 1].detail = cleanDetail
            }
            return updated
        }
        // Collapse repeated compose phases (e.g., compose -> localData -> compose) into a single canonical compose step at the tail.
        if kind == .compose, let existingIndex = updated.lastIndex(where: { $0.kind == .compose }) {
            for index in updated.indices where updated[index].status == .running {
                updated[index].status = .completed
            }
            var existing = updated.remove(at: existingIndex)
            existing.title = normalizedTitle
            if let cleanDetail { existing.detail = cleanDetail }
            existing.status = .running
            updated.append(existing)
            return updated
        }
        for index in updated.indices where updated[index].status == .running {
            updated[index].status = .completed
        }
        // Avoid duplicating consecutive identical (kind, title, detail) steps.
        if let last = updated.last,
           last.kind == kind,
           last.title == normalizedTitle,
           last.detail == cleanDetail
        {
            updated[updated.count - 1].status = .running
            return updated
        }
        updated.append(
            AIAgentActivityStep(kind: kind, title: normalizedTitle, detail: cleanDetail, status: .running)
        )
        if updated.count > maximumStoredSteps {
            updated = Array(updated.suffix(maximumStoredSteps))
        }
        return updated
    }

    static func liveStepsWithPending(
        _ recorded: [AIAgentActivityStep],
        isReport: Bool,
        usesConnectedSearch: Bool,
        language: AppLanguage
    ) -> [AIAgentActivityStep] {
        let planned: [(AIAgentActivityStep.Kind, String)] = isReport
            ? (usesConnectedSearch
                ? [
                    (.localData, localizedText("核对组合与行情", "Review portfolio & quotes", language: language)),
                    (.webSearch, localizedText("检索公开资料", "Search public sources", language: language)),
                    (.compose, localizedText("深度分析与撰写报告", "Analyze & draft report", language: language)),
                    (.verify, localizedText("核验数据与生成报告", "Verify & save report", language: language)),
                ]
                : [
                    (.localData, localizedText("核对组合与行情", "Review portfolio & quotes", language: language)),
                    (.compose, localizedText("深度分析与撰写报告", "Analyze & draft report", language: language)),
                    (.verify, localizedText("核验数据与生成报告", "Verify & save report", language: language)),
                ])
            : (usesConnectedSearch
                ? [
                    (.plan, localizedText("理解问题与制定步骤", "Understand question", language: language)),
                    (.webSearch, localizedText("检索公开资料", "Search public sources", language: language)),
                    (.compose, localizedText("整理分析回复", "Draft response", language: language)),
                ]
                : [
                    (.plan, localizedText("理解问题与制定步骤", "Understand question", language: language)),
                    (.compose, localizedText("整理分析回复", "Draft response", language: language)),
                ])

        let seenKinds = Set(recorded.map(\.kind))
        let lastRecordedOrder = planned.lastIndex(where: { seenKinds.contains($0.0) }) ?? -1
        var result = recorded
        for (idx, item) in planned.enumerated() where idx > lastRecordedOrder && !seenKinds.contains(item.0) {
            result.append(AIAgentActivityStep(kind: item.0, title: item.1, detail: nil, status: .pending))
        }
        return result
    }

    static func finishing(_ steps: [AIAgentActivityStep], failed: Bool = false) -> [AIAgentActivityStep] {
        steps.compactMap { step in
            guard step.status != .pending else { return nil }
            var copy = step
            if copy.status == .running {
                copy.status = failed ? .failed : .completed
            }
            return copy
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
    var diagnostic: AIAnalysisDiagnostic?
    var qualityStatus: String? = nil
    var evidenceCoveragePct: Double? = nil
    var numericGroundingPct: Double? = nil
}

struct AIAgentExecutionBudget: Codable, Equatable, Sendable {
    let totalSeconds: TimeInterval
    let planningSeconds: TimeInterval
    let searchSecondsPerCall: TimeInterval
    let reportSeconds: TimeInterval
    let repairSeconds: TimeInterval
    let followUpSeconds: TimeInterval
    let maxLoopTurns: Int
    let maxToolCalls: Int

    static let production = AIAgentExecutionBudget(
        totalSeconds: 420,
        planningSeconds: 60,
        searchSecondsPerCall: 25,
        reportSeconds: 180,
        repairSeconds: 60,
        followUpSeconds: 150,
        maxLoopTurns: 4,
        maxToolCalls: 6
    )
}

struct AIAgentTraceEvent: Codable, Equatable, Sendable {
    let sequence: Int
    let stageID: String
    let kind: String
    let startedAt: Date
    let finishedAt: Date
    let durationMilliseconds: Int
    let outcome: String
    let metadata: [String: String]
}

struct AIAgentRunTrace: Codable, Equatable, Sendable {
    var modelUsage: AIModelUsageSummary? = nil
    let schemaVersion: String
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let outcome: String
    let budget: AIAgentExecutionBudget
    let events: [AIAgentTraceEvent]
}

struct AIAnalysisDiagnostic: Codable, Identifiable, Equatable {
    let id: UUID
    let runID: UUID?
    let stageID: String
    let stageTitle: String
    let errorKind: String
    let errorSummary: String
    let provider: String
    let model: String
    let analysisMode: String
    let startedAt: Date
    let finishedAt: Date
    let recoveryHint: String

    init(
        id: UUID = UUID(),
        runID: UUID?,
        stageID: String,
        stageTitle: String,
        errorKind: String,
        errorSummary: String,
        provider: String,
        model: String,
        analysisMode: String,
        startedAt: Date,
        finishedAt: Date,
        recoveryHint: String
    ) {
        self.id = id
        self.runID = runID
        self.stageID = stageID
        self.stageTitle = stageTitle
        self.errorKind = errorKind
        self.errorSummary = errorSummary
        self.provider = provider
        self.model = model
        self.analysisMode = analysisMode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.recoveryHint = recoveryHint
    }

    var displayID: String {
        (runID ?? id).uuidString
    }

    func analysisModeLabel(language: AppLanguage) -> String {
        switch analysisMode {
        case "connected_enhanced":
            localizedText("联网研究", "Web Research", language: language)
        case "basic_standard":
            localizedText("基础分析", "Basic Analysis", language: language)
        default:
            analysisMode
        }
    }

    func copyText(language: AppLanguage) -> String {
        let formatter = ISO8601DateFormatter()
        return [
            localizedText("Portfolix Agent 诊断信息", "Portfolix Agent diagnostics", language: language),
            localizedText("诊断 ID：\(displayID)", "Diagnostic ID: \(displayID)", language: language),
            localizedText("阶段：\(stageTitle) (\(stageID))", "Stage: \(stageTitle) (\(stageID))", language: language),
            localizedText("类型：\(errorKind)", "Type: \(errorKind)", language: language),
            localizedText("模型：\(provider) / \(model)", "Model: \(provider) / \(model)", language: language),
            localizedText("模式：\(analysisModeLabel(language: language))", "Mode: \(analysisModeLabel(language: language))", language: language),
            localizedText("开始时间：\(formatter.string(from: startedAt))", "Started at: \(formatter.string(from: startedAt))", language: language),
            localizedText("结束时间：\(formatter.string(from: finishedAt))", "Finished at: \(formatter.string(from: finishedAt))", language: language),
            localizedText("错误摘要：\(errorSummary)", "Error summary: \(errorSummary)", language: language),
            localizedText("建议：\(recoveryHint)", "Suggestion: \(recoveryHint)", language: language)
        ].joined(separator: "\n")
    }
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
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(dayCount - 1), to: todayStart) ?? todayStart
    }
}

enum AIReportChatContent: Equatable {
    case user(String)
    case report(AIAnalysisReport, AIAnalysisRun)
    case assistant(String)
}

struct AIMessageCitation: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let utf16Offset: Int
    let title: String
    let url: String

    init(id: UUID = UUID(), utf16Offset: Int, title: String, url: String) {
        self.id = id
        self.utf16Offset = utf16Offset
        self.title = title
        self.url = url
    }
}

struct AICitationCatalogEntry: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let url: String
}

enum AIMessageCitationResolver {
    private static let shorthandExpression = try! NSRegularExpression(
        pattern: #"\[\[(source_[0-9]+(?:\s*[,;，；]\s*source_[0-9]+)*)\]\]"#
    )
    private static let markerExpression = try! NSRegularExpression(
        // Accept grouped IDs and Markdown links, but resolve only against the trusted catalog.
        pattern: #"\[\[cite:([^\]\r\n]{1,512})\]\]|(?<!!)\[([^\[\]\r\n]{1,512})\]\(\s*([^\s()]{1,4096})\s*\)"#,
        options: []
    )

    static func catalog(from toolResults: [AIWebSearchToolResult]) -> [AICitationCatalogEntry] {
        var seenURLs = Set<String>()
        let sources = toolResults.flatMap(\.sources).filter { source in
            guard (try? LLMBaseURLValidator.validatedComponents(from: source.url)) != nil else { return false }
            return seenURLs.insert(AISearchSourceIdentity.key(source.url)).inserted
        }
        return sources.enumerated().map { index, source in
            AICitationCatalogEntry(
                id: "source_\(index + 1)",
                title: String(source.title.prefix(120)),
                url: source.url
            )
        }
    }

    static func resolve(
        _ answer: String,
        catalog: [AICitationCatalogEntry]
    ) -> (text: String, citations: [AIMessageCitation]) {
        let trusted = catalog.filter { (try? LLMBaseURLValidator.validatedComponents(from: $0.url)) != nil }
        let sourceByID = Dictionary(trusted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sourceByURL = Dictionary(trusted.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        // Real responses also use [[source_1]]. Normalize only source IDs, then apply the same catalog checks.
        let normalizedAnswer = shorthandExpression.stringByReplacingMatches(in: answer,
            range: NSRange(location: 0, length: answer.utf16.count), withTemplate: "[[cite:$1]]")
        let source = normalizedAnswer as NSString
        let matches = markerExpression.matches(
            in: normalizedAnswer,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else { return (answer, []) }

        let clean = NSMutableString()
        var citations: [AIMessageCitation] = []
        var cursor = 0
        for match in matches {
            let precedingLength = match.range.location - cursor
            if precedingLength > 0 {
                clean.append(source.substring(with: NSRange(location: cursor, length: precedingLength)))
            }
            let entries: [AICitationCatalogEntry]
            if match.range(at: 1).location != NSNotFound {
                let ids = source.substring(with: match.range(at: 1)).split(whereSeparator: { ",;，；".contains($0) })
                var seen = Set<String>()
                entries = ids.compactMap { id in
                    let key = id.trimmingCharacters(in: .whitespaces)
                    guard seen.insert(key).inserted else { return nil }
                    return sourceByID[key]
                }
            } else {
                let destination = source.substring(with: match.range(at: 3))
                if let entry = sourceByID[destination] ?? sourceByURL[destination] {
                    clean.append(source.substring(with: match.range(at: 2)))
                    entries = [entry]
                } else {
                    // Preserve unrelated Markdown; the renderer does not make it interactive.
                    clean.append(source.substring(with: match.range))
                    entries = []
                }
            }
            for entry in entries {
                citations.append(
                    AIMessageCitation(
                        utf16Offset: clean.length,
                        title: entry.title,
                        url: entry.url
                    )
                )
            }
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length {
            clean.append(source.substring(from: cursor))
        }
        return (clean as String, citations)
    }
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
        let diagnostic: AIAnalysisDiagnostic?
        var qualityStatus: String? = nil
        var evidenceCoveragePct: Double? = nil
        var numericGroundingPct: Double? = nil

        init(run: AIAnalysisRun) {
            model = run.model
            usedFallback = run.usedFallback
            fallbackReason = run.fallbackReason
            diagnostic = run.diagnostic
            qualityStatus = run.qualityStatus
            evidenceCoveragePct = run.evidenceCoveragePct
            numericGroundingPct = run.numericGroundingPct
        }

        var run: AIAnalysisRun {
            AIAnalysisRun(
                status: .completed,
                model: model,
                usedFallback: usedFallback,
                fallbackReason: fallbackReason,
                diagnostic: diagnostic,
                qualityStatus: qualityStatus,
                evidenceCoveragePct: evidenceCoveragePct,
                numericGroundingPct: numericGroundingPct
            )
        }
    }

    struct FollowUpRunSnapshot: Codable, Equatable {
        var modelUsage: AIModelUsageSummary? = nil
        var localToolCallCount: Int? = nil
        let searchMode: String
        let toolCallCount: Int
        let toolResultCount: Int
        let loopTurnCount: Int
        let toolPlanJSON: String
        let toolResultsJSON: String
        let guardrailResultJSON: String

        init(result: AIAnalysisFollowUpResult) {
            modelUsage = result.modelUsage
            localToolCallCount = result.localToolCallCount
            searchMode = result.searchMode
            toolCallCount = result.toolCallCount
            toolResultCount = result.toolResultCount
            loopTurnCount = result.loopTurnCount
            toolPlanJSON = result.toolPlanJSON
            toolResultsJSON = result.toolResultsJSON
            guardrailResultJSON = result.guardrailResultJSON
        }
    }

    let id: UUID
    let createdAt: Date
    let kind: Kind
    let text: String?
    let report: AIAnalysisReport?
    let runSnapshot: RunSnapshot?
    let followUpRunSnapshot: FollowUpRunSnapshot?
    let citations: [AIMessageCitation]?
    let modelUsage: AIModelUsageSummary?
    var activitySteps: [AIAgentActivityStep]? = nil
    var retryQuestion: String? = nil

    var responseModelUsage: AIModelUsageSummary? {
        modelUsage ?? followUpRunSnapshot?.modelUsage
    }

    var displayedCitations: [AIMessageCitation] {
        let citations = citations ?? []
        guard kind == .assistant, let text else { return citations }
        let visible = AIFollowUpResponseParser.displayText(text)
        guard visible != text else { return citations }
        let range = (text as NSString).range(of: visible)
        guard range.location != NSNotFound else { return [] }
        return citations.compactMap { citation in
            guard (range.location...NSMaxRange(range)).contains(citation.utf16Offset) else { return nil }
            return AIMessageCitation(id: citation.id, utf16Offset: citation.utf16Offset - range.location,
                                     title: citation.title, url: citation.url)
        }
    }

    init(
        id: UUID,
        createdAt: Date,
        kind: Kind,
        text: String?,
        report: AIAnalysisReport?,
        runSnapshot: RunSnapshot?,
        followUpRunSnapshot: FollowUpRunSnapshot? = nil,
        citations: [AIMessageCitation]? = nil,
        modelUsage: AIModelUsageSummary? = nil,
        activitySteps: [AIAgentActivityStep]? = nil,
        retryQuestion: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.text = text
        self.report = report
        self.runSnapshot = runSnapshot
        self.followUpRunSnapshot = followUpRunSnapshot
        self.citations = citations
        self.modelUsage = modelUsage
        self.activitySteps = activitySteps
        self.retryQuestion = retryQuestion
    }

    var content: AIReportChatContent {
        switch kind {
        case .user:
            .user(text ?? "")
        case .assistant:
            .assistant(AIFollowUpResponseParser.displayText(text ?? ""))
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

    static func report(
        _ report: AIAnalysisReport,
        _ run: AIAnalysisRun,
        modelUsage: AIModelUsageSummary? = nil,
        activitySteps: [AIAgentActivityStep]? = nil
    ) -> AIReportChatItem {
        AIReportChatItem(
            id: report.id,
            createdAt: report.generatedAt,
            kind: .report,
            text: nil,
            report: report,
            runSnapshot: RunSnapshot(run: run),
            modelUsage: modelUsage,
            activitySteps: activitySteps?.isEmpty == false ? activitySteps : nil
        )
    }

    static func assistant(
        _ text: String,
        createdAt: Date = .now,
        followUpRunSnapshot: FollowUpRunSnapshot? = nil,
        citations: [AIMessageCitation] = [],
        modelUsage: AIModelUsageSummary? = nil,
        activitySteps: [AIAgentActivityStep]? = nil,
        retryQuestion: String? = nil
    ) -> AIReportChatItem {
        AIReportChatItem(
            id: UUID(),
            createdAt: createdAt,
            kind: .assistant,
            text: text,
            report: nil,
            runSnapshot: nil,
            followUpRunSnapshot: followUpRunSnapshot,
            citations: citations.isEmpty ? nil : citations,
            modelUsage: modelUsage,
            activitySteps: activitySteps?.isEmpty == false ? activitySteps : nil,
            retryQuestion: retryQuestion
        )
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
            runSnapshot: runSnapshot,
            followUpRunSnapshot: followUpRunSnapshot,
            citations: citations,
            modelUsage: modelUsage
        )
    }
}

struct AIAnalysisAgentResult: Equatable {
    let report: AIAnalysisReport
    let artifacts: AIAnalysisArtifactBundle
}

struct AIAnalysisArtifactBundle: Codable, Equatable, Sendable {
    let inputJSON: String
    let toolResultsJSON: String
    let toolPlanJSON: String
    let evidenceLedgerJSON: String?
    let loopStateJSON: String?
    let rawReportJSON: String
    let repairedReportJSON: String?
    let finalReportJSON: String
    let guardrailResultJSON: String
    let trace: AIAgentRunTrace?
    var modelUsage: AIModelUsageSummary? = nil

    init(
        inputJSON: String,
        toolResultsJSON: String,
        toolPlanJSON: String,
        evidenceLedgerJSON: String? = nil,
        loopStateJSON: String? = nil,
        rawReportJSON: String,
        repairedReportJSON: String?,
        finalReportJSON: String,
        guardrailResultJSON: String,
        trace: AIAgentRunTrace? = nil
    ) {
        self.inputJSON = inputJSON
        self.toolResultsJSON = toolResultsJSON
        self.toolPlanJSON = toolPlanJSON
        self.evidenceLedgerJSON = evidenceLedgerJSON
        self.loopStateJSON = loopStateJSON
        self.rawReportJSON = rawReportJSON
        self.repairedReportJSON = repairedReportJSON
        self.finalReportJSON = finalReportJSON
        self.guardrailResultJSON = guardrailResultJSON
        self.trace = trace
    }

    func withTrace(_ trace: AIAgentRunTrace?) -> AIAnalysisArtifactBundle {
        var copy = AIAnalysisArtifactBundle(
            inputJSON: inputJSON,
            toolResultsJSON: toolResultsJSON,
            toolPlanJSON: toolPlanJSON,
            evidenceLedgerJSON: evidenceLedgerJSON,
            loopStateJSON: loopStateJSON,
            rawReportJSON: rawReportJSON,
            repairedReportJSON: repairedReportJSON,
            finalReportJSON: finalReportJSON,
            guardrailResultJSON: guardrailResultJSON,
            trace: trace
        )
        copy.modelUsage = modelUsage ?? trace?.modelUsage
        return copy
    }

    func withModelUsage(_ usage: AIModelUsageSummary) -> AIAnalysisArtifactBundle {
        var copy = self
        copy.modelUsage = usage
        if var trace = copy.trace {
            trace.modelUsage = usage
            copy = copy.withTrace(trace)
        }
        return copy
    }

    func decodedQualitySummary() -> (status: String?, evidenceCoveragePct: Double?, numericGroundingPct: Double?) {
        guard let data = guardrailResultJSON.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return (nil, nil, nil) }
        let status = object["status"] as? String
        let scorecard = object["scorecard"] as? [String: Any]
        let evidencePct = scorecard?["evidence_coverage_pct"] as? Double
        let numericPct = scorecard?["numeric_grounding_pct"] as? Double
        return (status, evidencePct, numericPct)
    }
}

struct AIAnalysisFollowUpResult: Equatable {
    var modelUsage: AIModelUsageSummary? = nil
    var localToolCallCount = 0
    let answer: String
    let citations: [AIMessageCitation]
    let guardrailResultJSON: String
    let searchMode: String
    let toolCallCount: Int
    let toolResultCount: Int
    let loopTurnCount: Int
    let toolPlanJSON: String
    let toolResultsJSON: String

    init(
        answer: String,
        citations: [AIMessageCitation] = [],
        guardrailResultJSON: String,
        searchMode: String,
        toolCallCount: Int,
        toolResultCount: Int,
        loopTurnCount: Int,
        toolPlanJSON: String,
        toolResultsJSON: String
    ) {
        self.answer = answer
        self.citations = citations
        self.guardrailResultJSON = guardrailResultJSON
        self.searchMode = searchMode
        self.toolCallCount = toolCallCount
        self.toolResultCount = toolResultCount
        self.loopTurnCount = loopTurnCount
        self.toolPlanJSON = toolPlanJSON
        self.toolResultsJSON = toolResultsJSON
    }
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
    let exposureCoverage: Double?
    let unknownExposurePercent: Double?
    let evidenceSourceCount: Int?
    let assetExposures: [AssetExposureProfile]?

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
        confidence: String,
        exposureCoverage: Double? = nil,
        unknownExposurePercent: Double? = nil,
        evidenceSourceCount: Int? = nil,
        assetExposures: [AssetExposureProfile]? = nil
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
        self.exposureCoverage = exposureCoverage
        self.unknownExposurePercent = unknownExposurePercent
        self.evidenceSourceCount = evidenceSourceCount
        self.assetExposures = assetExposures
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
    let evidenceRefs: [String]?

    init(
        id: UUID = UUID(),
        severity: String,
        category: String,
        title: String,
        evidence: String,
        impact: String,
        relatedRefs: [String],
        evidenceRefs: [String]? = nil
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.title = title
        self.evidence = evidence
        self.impact = impact
        self.relatedRefs = relatedRefs
        self.evidenceRefs = evidenceRefs
    }
}

struct AIAssetAlert: Codable, Identifiable, Equatable {
    let id: UUID
    let assetName: String
    let symbol: String
    let title: String
    let reason: String
    let sourceDomains: [String]
    let evidenceRefs: [String]?

    init(
        id: UUID = UUID(),
        assetName: String,
        symbol: String,
        title: String,
        reason: String,
        sourceDomains: [String],
        evidenceRefs: [String]? = nil
    ) {
        self.id = id
        self.assetName = assetName
        self.symbol = symbol
        self.title = title
        self.reason = reason
        self.sourceDomains = sourceDomains
        self.evidenceRefs = evidenceRefs
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
    let evidenceRefs: [String]?

    init(
        id: UUID = UUID(),
        action: String,
        assetName: String?,
        symbol: String?,
        title: String,
        rationale: String,
        riskNote: String?,
        evidenceRefs: [String]? = nil
    ) {
        self.id = id
        self.action = action
        self.assetName = assetName
        self.symbol = symbol
        self.title = title
        self.rationale = rationale
        self.riskNote = riskNote
        self.evidenceRefs = evidenceRefs
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
    let costStatus: String
    let quantity: String
    let averageCost: String?
    let latestPrice: String
    let totalCostQuote: String?
    let marketValueCNY: String
    let unrealizedProfitQuote: String?
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

struct AIFollowUpPortfolioContext: Encodable, Equatable, Sendable {
    let schemaVersion = "ai-follow-up-portfolio-context.v1"
    let snapshotDate: String
    let generatedAt: String
    let displayCurrency: String
    let totalValueCNY: String
    let totalValueDisplay: String
    let today: AIFollowUpReturnContext
    let positions: [AIFollowUpPositionContext]
}

struct AIFollowUpPositionContext: Encodable, Equatable, Sendable {
    let positionRef: String
    let displayLabel: String
    let symbol: String
    let assetType: String
    let quoteCurrency: String
    let quantity: String
    let latestPrice: String
    let marketValueCNY: String
    let allocationPct: Double
    let today: AIFollowUpReturnContext
    let oneWeek: AIPerformanceWindowContext
    let quoteTime: String
    let fetchedAt: String
    let source: String
}

struct AIFollowUpReturnContext: Encodable, Equatable, Sendable {
    let status: String
    let profitAmountCNY: String?
    let profitAmountDisplay: String?
    let returnRatePct: Double?
    let calculationBasis: String
}

struct AIDataQualityContext: Encodable {
    let missingQuoteAllocationPct: Double
    let staleQuoteAllocationPct: Double
    let manualQuoteAllocationPct: Double
    var balanceHistoryIncomplete: Bool? = nil
    var balanceHistoryNote: String? = nil
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
    let provider: SearchProviderOption?

    init(
        id: String,
        query: String,
        positionRefs: [String],
        provider: SearchProviderOption? = nil
    ) {
        self.id = id
        self.query = query
        self.positionRefs = positionRefs
        self.provider = provider
    }

    enum CodingKeys: String, CodingKey {
        case id
        case query
        case positionRefs = "position_refs"
        case provider
    }
}

struct AIWebSearchToolPlan: Codable, Equatable, Sendable {
    var functionContext: AISearchFunctionContext? = nil
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
    let provider: SearchProviderOption?

    init(
        callID: String,
        query: String,
        positionRefs: [String],
        searchedAt: Date,
        status: String,
        sources: [AssetResearchSource],
        limitations: [String],
        provider: SearchProviderOption? = nil
    ) {
        self.callID = callID
        self.query = query
        self.positionRefs = positionRefs
        self.searchedAt = searchedAt
        self.status = status
        self.sources = sources
        self.limitations = limitations
        self.provider = provider
    }

    enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case query
        case positionRefs = "position_refs"
        case searchedAt = "searched_at"
        case status
        case sources
        case limitations
        case provider
    }
}

struct AIAgentLoopTurn: Codable, Equatable, Sendable {
    let turn: Int
    let startedAt: Date
    let finishedAt: Date
    let plan: AIWebSearchToolPlan
    let toolResults: [AIWebSearchToolResult]
    let evidenceItemCount: Int
    let decision: String

    enum CodingKeys: String, CodingKey {
        case turn
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case plan
        case toolResults = "tool_results"
        case evidenceItemCount = "evidence_item_count"
        case decision
    }
}

struct AIAgentWorkflowStep: Codable, Equatable, Sendable {
    let sequence: Int
    let phase: String
    let startedAt: Date
    let finishedAt: Date
    let outcome: String
    let detail: String
    let evidenceItemCount: Int

    enum CodingKeys: String, CodingKey {
        case sequence
        case phase
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case outcome
        case detail
        case evidenceItemCount = "evidence_item_count"
    }
}

struct AIAgentLoopState: Codable, Equatable, Sendable {
    let schemaVersion: String
    let id: UUID
    let goal: String
    let startedAt: Date
    let finishedAt: Date
    let maxTurns: Int
    let maxToolCalls: Int
    let turns: [AIAgentLoopTurn]
    var steps: [AIAgentWorkflowStep]? = nil
    let stopReason: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case goal
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case maxTurns = "max_turns"
        case maxToolCalls = "max_tool_calls"
        case turns
        case steps
        case stopReason = "stop_reason"
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
