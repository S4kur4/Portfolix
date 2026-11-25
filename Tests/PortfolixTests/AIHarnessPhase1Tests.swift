import Foundation
import Testing
@testable import Portfolix

@Suite("Phase 1 AI Harness upgrades")
struct AIHarnessPhase1Tests {
    private func sampleHolding(
        name: String = "NVIDIA Corp",
        symbol: String = "NVDA",
        quantity: Decimal = 123,
        totalCost: Decimal = 14_567,
        marketValueCNY: Decimal = 543_210
    ) -> Position {
        Position(
            name: name,
            symbol: symbol,
            category: .usStock,
            quoteCurrency: .usd,
            quantity: quantity,
            totalCost: totalCost,
            averageCost: 118.43,
            latestPrice: 140,
            marketValueCNY: marketValueCNY,
            profitRate: 18.2,
            weeklyTrend: [],
            source: "manual",
            quoteTime: "2026-11-24",
            freshness: .manual
        )
    }

    @Test
    func toolSchemasIncludeParameterDescriptionsAndAcceptSymbolInPerformanceTool() throws {
        for tool in AIPortfolioDataTool.allCases {
            let def = tool.definition
            if case let .object(schema) = def.parameters,
               case let .object(props) = schema["properties"]
            {
                for (name, value) in props {
                    if case let .object(propObj) = value {
                        let desc = propObj["description"]
                        #expect(desc != nil, "Missing description on \(tool.rawValue).\(name)")
                    }
                }
            }
        }
        let holding = sampleHolding()
        let snapshot = AIPortfolioToolSnapshot(positions: [holding])
        let request = try AIPortfolioToolRequest(
            call: LLMFunctionCall(
                callID: "perf_1",
                name: "get_holding_performance",
                arguments: #"{"position_refs":["NVDA"],"period":"one_week"}"#
            )
        )
        let output = AIPortfolioDataToolExecutor.execute(request, snapshot: snapshot)
        #expect(output.contains("\"symbol\":\"NVDA\""))
        #expect(output.contains("\"missing_position_refs\":[]"))
    }

    @Test
    func invalidLocalToolArgumentsIncludeActionableFieldAndHint() {
        do {
            _ = try AIPortfolioToolRequest(
                call: LLMFunctionCall(callID: "bad", name: "list_holdings", arguments: #"{"limit":99}"#)
            )
            Issue.record("Expected invalidArguments error")
        } catch let AIPortfolioToolError.invalidArguments(field, hint) {
            #expect(field == "limit")
            #expect(hint.contains("1") && hint.contains("25"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func searchQueryValidationAllowsCalendarYearsAndFormsWhileBlockingPrivateAmounts() throws {
        let holding = sampleHolding(quantity: 1234, totalCost: 87654, marketValueCNY: 543210)
        let ref = "position_\(holding.id.uuidString)"
        let sensitive = AIAnalysisAgent.sensitivePortfolioNumbers(positions: [holding])

        let legitimate = AIWebSearchToolPlan(toolCalls: [
            AIWebSearchToolCall(id: "s1", query: "NVDA 2026 Q3 earnings 10-K filing", positionRefs: [ref], provider: .tavily),
        ])
        let validated = try AIAnalysisAgent.validatedToolPlan(
            legitimate,
            allowedRefs: [ref],
            allowedSearchTerms: [ref: ["NVDA", "NVIDIA Corp"]],
            allowedProviders: [.tavily],
            sensitiveNumbers: sensitive
        )
        #expect(validated.toolCalls.count == 1)

        let leakingGeneral = AIWebSearchToolPlan(toolCalls: [
            AIWebSearchToolCall(id: "s2", query: "US stock market 543210 rebalance news", positionRefs: [], provider: .tavily),
        ])
        #expect(throws: AIAnalysisAgentError.self) {
            try AIAnalysisAgent.validatedToolPlan(
                leakingGeneral,
                allowedRefs: [ref],
                allowsGeneralQueries: true,
                allowedProviders: [.tavily],
                sensitiveNumbers: sensitive
            )
        }
    }

    @Test
    func evidenceProjectionCanOmitDuplicateWebExcerptsWhenSearchOutputsArePresent() {
        let ledger = AIEvidenceLedger(
            schemaVersion: "agent-evidence-ledger.v1",
            generatedAt: .now,
            items: [
                AIEvidenceItem(
                    id: "web.search_1.1",
                    kind: "web_source",
                    metric: "public_information_source",
                    valueText: "Reuters headline",
                    numericValue: nil,
                    unit: nil,
                    positionRefs: [],
                    asOf: "2026-11-24",
                    source: "reuters.com",
                    confidence: "authoritative",
                    sourceURL: "https://reuters.com/article",
                    sourceExcerpt: "UNIQUE_EXCERPT_BODY_TEXT"
                ),
            ]
        )
        let withExcerpt = AIContextProjection.evidenceJSON(ledger, includeWebExcerpts: true)
        let withoutExcerpt = AIContextProjection.evidenceJSON(ledger, includeWebExcerpts: false)
        #expect(withExcerpt.contains("UNIQUE_EXCERPT_BODY_TEXT"))
        #expect(!withoutExcerpt.contains("UNIQUE_EXCERPT_BODY_TEXT"))
        #expect(withoutExcerpt.contains("web.search_1.1"))
    }

    @Test
    func reportValidationCatchesInvalidEnumsBeforeNormalizationAndAvoidsSecurityFalsePositives() throws {
        let badEnumJSON = """
        {
          "summary": "组合风险整体可控。",
          "health_score_explanation": "未触发风险阈值。",
          "risk_items": [{
            "severity": "critical_extreme",
            "category": "concentration",
            "title": "集中度偏高",
            "evidence": "单一持仓占比 45%",
            "impact": "波动放大",
            "related_refs": []
          }],
          "asset_alerts": [],
          "rebalance_actions": [],
          "questions_to_consider": [],
          "data_quality_notes": [],
          "limitations": ["仅基于当前记录"]
        }
        """
        do {
            _ = try AIAnalysisAgent.validatedPayload(badEnumJSON, expectedLanguage: .simplifiedChinese)
            Issue.record("Expected invalidEnum to be caught before normalizer coercion")
        } catch let error as AIReportPayloadValidationError {
            #expect(error == .invalidEnum("risk_items.severity"))
        }

        try AIInformationSecurityGuardrail.validateGeneratedText("Cloud cybersecurity vendors focusing on passwordless authentication and identity management grew revenue.")
        #expect(throws: AIReportValidationError.self) {
            try AIInformationSecurityGuardrail.validateGeneratedText("password: my-secret-value")
        }
    }

    @Test @MainActor
    func followUpErrorMessagesDistinguishBudgetRateLimitAuthAndNetworkFailures() {
        let budgetMsg = PortfolioStore.localizedFollowUpFailureMessage(for: AIModelBudgetError.exhausted, language: .chinese)
        let rateMsg = PortfolioStore.localizedFollowUpFailureMessage(for: LLMClientError.rateLimited, language: .chinese)
        let authMsg = PortfolioStore.localizedFollowUpFailureMessage(for: LLMClientError.unauthorized, language: .chinese)
        let netMsg = PortfolioStore.localizedFollowUpFailureMessage(for: URLError(.timedOut), language: .chinese)
        #expect(budgetMsg.contains("上限"))
        #expect(rateMsg.contains("频率"))
        #expect(authMsg.contains("API Key"))
        #expect(netMsg.contains("网络"))
        #expect(!rateMsg.contains("安全"))
        #expect(!netMsg.contains("结构校验"))
    }

    @Test
    func interleavedFollowUpCanReadHoldingsThenRunSemanticWebSearchWithCitations() async throws {
        let holding = sampleHolding()
        let llm = InterleavedMockLLM(responses: [
            // Phase 1 planning returns empty (model doesn't know holdings yet)
            LLMCompletionResult(content: #"{"status":"finish","tool_calls":[],"limitations":[]}"#),
            // Phase 2 round 0: call local list_holdings
            LLMCompletionResult(
                content: "",
                functionCalls: [LLMFunctionCall(callID: "local_1", name: "list_holdings", arguments: "{}")]
            ),
            // Phase 2 round 1: call semantic web_search on discovered NVDA
            LLMCompletionResult(
                content: "",
                functionCalls: [LLMFunctionCall(
                    callID: "web_1",
                    name: "web_search",
                    arguments: #"{"query":"NVDA 2026 Q3 earnings guidance Reuters","scope":"global_en","assets":["NVDA"]}"#
                )]
            ),
            // Phase 2 final answer citing interleaved source_1
            LLMCompletionResult(content: #"{"answer":"NVDA 最新财报指引稳健。[[cite:source_1]]","limitations":[]}"#),
        ])
        let search = InterleavedMockSearch()
        let agent = AIAnalysisAgent(llm: llm, search: search, credentialStore: InterleavedCredentials())
        let result = try await agent.answerFollowUp(
            question: "我最近买的那只芯片股财报怎么样？",
            report: nil,
            artifacts: nil,
            positions: [holding],
            llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.tavily], quality: .basic)
        )
        #expect(result.localToolCallCount == 1)
        #expect(result.toolCallCount == 1)
        #expect(result.citations.count == 1)
        #expect(result.citations.first?.url == "https://reuters.com/nvda-q3")
        #expect(result.searchMode == "connected_search_completed")
    }

    @Test
    func activityStepPolicyTracksLifecycleTransitionsCleanly() {
        var steps: [AIAgentActivityStep] = []
        steps = AIAgentActivityStepPolicy.recording(kind: .plan, title: "规划步骤", into: steps)
        steps = AIAgentActivityStepPolicy.recording(kind: .localData, title: "读取持仓", into: steps)
        steps = AIAgentActivityStepPolicy.recording(kind: .webSearch, title: "检索公开资料", detail: "NVDA earnings", into: steps)
        steps = AIAgentActivityStepPolicy.recording(kind: .compose, title: "推理中 · 4s", into: steps)
        steps = AIAgentActivityStepPolicy.recording(kind: .compose, title: "推理中 · 8s", into: steps)
        #expect(steps.count == 4)
        #expect(steps[0].status == .completed)
        #expect(steps[1].status == .completed)
        #expect(steps[2].detail == "NVDA earnings")
        #expect(steps[3].title == "推理中 · 8s")
        let finished = AIAgentActivityStepPolicy.finishing(steps)
        #expect(finished.allSatisfy { $0.status == .completed })

        // Verify repeated compose transitions (e.g. compose -> localData -> compose -> reasoning) collapse into one canonical compose step.
        var followUpSteps: [AIAgentActivityStep] = []
        followUpSteps = AIAgentActivityStepPolicy.recording(kind: .plan, title: "理解问题与制定步骤", into: followUpSteps)
        followUpSteps = AIAgentActivityStepPolicy.recording(kind: .compose, title: "整理分析回复", into: followUpSteps)
        followUpSteps = AIAgentActivityStepPolicy.recording(kind: .localData, title: "核对本地持仓与记录", into: followUpSteps)
        followUpSteps = AIAgentActivityStepPolicy.recording(kind: .compose, title: "整理分析回复", detail: "深度推理 · 4 秒", into: followUpSteps)
        followUpSteps = AIAgentActivityStepPolicy.recording(kind: .compose, title: "整理分析回复", detail: "输出回复正文", into: followUpSteps)
        #expect(followUpSteps.filter { $0.kind == .compose }.count == 1)
        #expect(followUpSteps.last?.status == .running)
        let withPending = AIAgentActivityStepPolicy.liveStepsWithPending(
            [AIAgentActivityStep(kind: .localData, title: "核对组合与行情", status: .running)],
            isReport: true,
            usesConnectedSearch: true,
            language: .chinese
        )
        #expect(withPending.contains { $0.status == .pending })
    }

    @Test @MainActor
    func composerDraftBufferAppendsMultipleReviewQuestionsWithoutOverwritingOrDuplicating() {
        let buffer = AIReportComposerDraftBuffer()
        buffer.appendReviewQuestion("现金是否计划半年内使用？", language: .chinese)
        #expect(buffer.text == "关于「现金是否计划半年内使用？」：\n")

        buffer.replace(with: buffer.text + "是的，预计三个月内会用掉一半。")
        buffer.appendReviewQuestion("单一持仓上限是否需要调整？", language: .chinese)
        #expect(buffer.text.contains("是的，预计三个月内会用掉一半。"))
        #expect(buffer.text.contains("\n\n关于「单一持仓上限是否需要调整？」：\n"))

        // Clicking an already-present question does not duplicate it.
        let snapshot = buffer.text
        buffer.appendReviewQuestion("现金是否计划半年内使用？", language: .chinese)
        #expect(buffer.text == snapshot)
    }

    @Test
    func roseOrbitDarkModeTrackIsSubtleLowAlphaPurpleWithoutWhiteHalo() throws {
        let darkTrack = RoseOrbitPalette.track(isDarkMode: true)
        #expect(darkTrack.alpha <= 0.20)
        let components = try #require(darkTrack.components)
        // Must be violet-hued (blue channel clearly dominant over green) and dark-harmonized, never white/gray.
        #expect(components.count >= 4)
        #expect(components[2] > components[1] + 0.25)
        #expect(components[1] < 0.40)
    }

    @Test
    func toolPlanAllowsCalendarDatesAndSalvagesValidCallsInMultiCallPlans() throws {
        let ref = "position_\(UUID().uuidString)"
        let plan = AIWebSearchToolPlan(toolCalls: [
            AIWebSearchToolCall(
                id: "c1",
                query: "易方达信息产业混合A 2026年11月 最新季报 催化剂 30天",
                positionRefs: [ref],
                provider: .bocha
            ),
            AIWebSearchToolCall(
                id: "c2",
                query: "short", // invalid length; should be dropped while c1 is salvaged
                positionRefs: [ref],
                provider: .parallel
            ),
        ])
        let validated = try AIAnalysisAgent.validatedToolPlan(
            plan,
            allowedRefs: [ref],
            allowedSearchTerms: [ref: ["易方达信息产业混合A", "易方达信息产业混合", "001513"]],
            allowedProviders: [.bocha, .parallel],
            sensitiveNumbers: ["98765"]
        )
        #expect(validated.toolCalls.count == 1)
        #expect(validated.toolCalls.first?.provider == .bocha)
        #expect(validated.toolCalls.first?.query.contains("2026年11月") == true)
    }
}

private actor InterleavedMockLLM: LLMCompleting {
    private var queue: [LLMCompletionResult]
    init(responses: [LLMCompletionResult]) { self.queue = responses }
    func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String {
        "{}"
    }
    func completeJSONResult(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIProviderConfiguration,
        apiKey: String,
        webSearchEnabled: Bool,
        webSearchProgress: LLMWebSearchProgressHandler?
    ) async throws -> LLMCompletionResult {
        guard !queue.isEmpty else { return LLMCompletionResult(content: "{}") }
        return queue.removeFirst()
    }
}

private struct InterleavedMockSearch: WebSearching {
    func search(query: String, positions: [Position], configuration: SearchConfiguration, apiKey: String) async throws -> [AssetResearchSource] {
        [
            AssetResearchSource(
                title: "NVIDIA Q3 Guidance",
                url: "https://reuters.com/nvda-q3",
                domain: "reuters.com",
                publishedDate: "2026-11-20",
                snippet: "NVIDIA posted strong Q3 datacenter revenue.",
                credibility: .official
            ),
        ]
    }
}

private struct InterleavedCredentials: ProviderCredentialStoring {
    func read(kind: ProviderCredentialKind) throws -> String? { "test-key" }
    func save(_: String, kind _: ProviderCredentialKind) throws {}
    func delete(kind _: ProviderCredentialKind) throws {}
    func readValidationState(kind _: ProviderCredentialKind) throws -> ProviderCredentialValidationState { .valid }
    func saveValidationState(_: ProviderCredentialValidationState, kind _: ProviderCredentialKind) throws {}
}
