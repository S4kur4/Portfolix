import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Portfolix

@Suite("Budgeted Agent end-to-end")
struct AIOptimizationTests {
  private let answer = #"{"answer":"可以先核对报价时间，再判断数据是否适合当前问题。","limitations":[]}"#

  @Test
  func electionResultsAreValidPublicSearchesWithoutPortfolioReferences() async throws {
    let plan = #"{"status":"continue","tool_calls":[{"id":"search_1","provider":"Parallel","query":"2026 US midterm election results House Senate control AP official count","position_refs":[]}],"limitations":[]}"#
    let (client, key) = transport([plan, answer])
    let search = IntentSearchRecorder()
    let result = try await AIAnalysisAgent(llm: client, search: search, credentialStore: OptimizationCredentials(key: key)).answerFollowUp(
      question: "美国中期选举现在出结果了吗，对后续股市会有什么影响？", report: report(summary: "PRIVATE_PORTFOLIO_CONTENT"),
      artifacts: nil, positions: [intentPosition], llmConfiguration: .default,
      searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.parallel], quality: .basic))
    #expect(result.toolCallCount == 1)
    #expect(await search.queries().first?.contains("midterm election") == true)
    #expect(await search.positionCounts() == [0])
  }

  @Test(arguments: [#"{"status":"finish","tool_calls":[],"limitations":[]}"#, "invalid plan"])
  func currentElectionFactsCannotSilentlySkipSearchWhenPlanningFails(_ plan: String) async throws {
    let (client, key) = transport([plan, answer])
    let search = IntentSearchRecorder()
    let result = try await AIAnalysisAgent(llm: client, search: search, credentialStore: IntentCredentials(key: key)).answerFollowUp(
      question: "美国中期选举现在出结果了吗，对后续股市会有什么影响？", report: nil,
      artifacts: nil, positions: [intentPosition], llmConfiguration: .default,
      searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.exa, .tavily], quality: .basic))
    #expect(result.toolCallCount == 2)
    #expect(Set(await search.providers()) == [.exa, .tavily])
    #expect(await search.queries().allSatisfy { $0.contains("election") })
    #expect(await search.positionCounts() == [0, 0])
    #expect(result.modelUsage?.searchUsage?.requestCount == 2)
  }

  @Test(arguments: ["你帮我查一下？", "好的，帮我查一下", "Please look it up", "Can you check that?"])
  func briefSearchFollowUpKeepsTheLatestUserTopicInsteadOfAssistantHoldings(_ question: String) async throws {
    let (client, key) = transport(["invalid plan", answer])
    let search = IntentSearchRecorder()
    let history: [AIReportChatItem] = [
      .user("BTC 今天价格是多少？", createdAt: Date(timeIntervalSince1970: 1)),
      .user("美国中期选举现在出结果了吗？", createdAt: Date(timeIntervalSince1970: 2)),
      .assistant("暂无可核实的计票信息。你的 BTC 仓位需要关注。", createdAt: Date(timeIntervalSince1970: 3)),
      .user(question, createdAt: Date(timeIntervalSince1970: 4)),
    ]
    let result = try await AIAnalysisAgent(llm: client, search: search, credentialStore: OptimizationCredentials(key: key)).answerFollowUp(
      question: question, report: report(summary: "PRIVATE_PORTFOLIO_CONTENT"), artifacts: nil,
      chatHistory: history, positions: [intentPosition], llmConfiguration: .default,
      searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.parallel], quality: .basic))
    #expect(result.toolCallCount == 1)
    #expect(await search.queries().first?.contains("election") == true)
    #expect(await search.positionCounts() == [0])
    let planningRequest = String(decoding: try #require(OptimizationProtocol.state.requests(for: key).first), as: UTF8.self)
    #expect(planningRequest.contains("美国中期选举"))
    #expect(!planningRequest.contains("PRIVATE_PORTFOLIO_CONTENT"))
  }

  @Test
  func anUnresolvedSearchRequestDoesNotSpendRequestsOnTopHoldings() async throws {
    let (client, key) = transport(["invalid plan", answer])
    let search = IntentSearchRecorder()
    let result = try await AIAnalysisAgent(llm: client, search: search, credentialStore: OptimizationCredentials(key: key)).answerFollowUp(
      question: "你帮我查一下？", report: nil, artifacts: nil, positions: [intentPosition],
      llmConfiguration: .default, searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.parallel], quality: .basic))
    #expect(result.toolCallCount == 0)
    #expect(await search.queries().isEmpty)
    #expect(result.searchMode == "connected_search_unavailable")
  }

  @Test
  func generalKnowledgeStillAllowsAnEmptyPlan() async throws {
    let (client, key) = transport([#"{"status":"finish","tool_calls":[],"limitations":[]}"#, answer])
    let search = IntentSearchRecorder()
    let result = try await AIAnalysisAgent(llm: client, search: search, credentialStore: OptimizationCredentials(key: key)).answerFollowUp(
      question: "解释一下复利", report: nil, artifacts: nil, positions: [], llmConfiguration: .default,
      searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.parallel], quality: .basic))
    #expect(result.toolCallCount == 0)
    #expect(await search.queries().isEmpty)
  }

  @Test
  func queryOptimizationDoesNotTurnAValidRequestIntoAnOverlongRejectedPlan() throws {
    let query = "US stock market decline reasons this week AI valuation Federal Reserve rate policy official latest economic releases"
    #expect(query.count <= 128)
    let plan = AIWebSearchToolPlan(toolCalls: [.init(id: "s", query: query, positionRefs: [], provider: .parallel)])
    let validated = try AIAnalysisAgent.validatedToolPlan(plan, allowedRefs: [], allowsGeneralQueries: true)
    #expect(try #require(validated.toolCalls.first).query.count <= 128)
  }

  @Test
  func realModelCitationShorthandSurvivesTheFullFollowUpPipelineWithoutRepair() async throws {
    let plan = #"{"status":"continue","tool_calls":[{"id":"s","provider":"Parallel","query":"gold latest public news","position_refs":[]}],"limitations":[]}"#
    let (client, key) = transport([plan, #"{"answer":"资料日期需要核对。[[source_1]]","limitations":[]}"#])
    let result = try await AIAnalysisAgent(llm: client, search: OptimizationSearch(), credentialStore: OptimizationCredentials(key: key)).answerFollowUp(
      question: "请查黄金近期消息", report: nil, artifacts: nil, positions: [], llmConfiguration: .default,
      searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.parallel], quality: .basic))
    #expect(result.answer == "资料日期需要核对。")
    #expect(result.citations.count == 1)
    #expect(result.citations.first?.utf16Offset == result.answer.utf16.count)
    #expect(result.modelUsage?.calls.count == 2)
  }

  private var intentPosition: Position {
    Position(name: "BTC", symbol: "BTC/USDT", category: .crypto, quoteCurrency: .usdt,
      quantity: 1, averageCost: 100, latestPrice: 120, marketValueCNY: 840, profitRate: 20,
      weeklyTrend: [], source: "manual", quoteTime: "2026-11-08", freshness: .manual)
  }

  @Test
  func standaloneQuestionUsesOneStreamedRequestAndCountsUsageWithoutDoubleCounting() async throws {
    let (client, key) = transport([answer])
    let agent = AIAnalysisAgent(
      llm: client, search: OptimizationSearch(), credentialStore: OptimizationCredentials(key: key))
    let result = try await agent.answerFollowUp(
      question: "解释一下什么是复利", report: nil, artifacts: nil, positions: [],
      llmConfiguration: .default, searchConfiguration: .default
    )
    #expect(result.answer.contains("报价时间"))
    let usage = try #require(result.modelUsage)
    #expect(usage.calls.count == 1)
    #expect(usage.calls.first?.stage == "follow_up_answer")
    #expect(usage.knownTotalTokens == 120)
    #expect(usage.knownCachedInputTokens == 40)
    #expect(usage.knownReasoningTokens == 5)
    #expect(usage.unknownUsageCallCount == 0)
    let stored = String(decoding: try JSONEncoder().encode(usage), as: UTF8.self)
    #expect(!stored.contains(key))
    #expect(!stored.contains("复利"))
  }

  @Test
  func connectedFactQuestionDoesNotExpandOrSendAnUnrelatedReport() async throws {
    let plan =
      #"{"status":"continue","tool_calls":[{"id":"search_1","provider":"Parallel","query":"gold spot price official latest quotation","position_refs":[]}],"limitations":[]}"#
    let short = #"{"answer":"报价需要注明计价单位和时间。[[cite:source_1]]","limitations":[]}"#
    let (client, key) = transport([plan, short])
    let agent = AIAnalysisAgent(
      llm: client, search: OptimizationSearch(), credentialStore: OptimizationCredentials(key: key))
    let result = try await agent.answerFollowUp(
      question: "今天黄金价格是多少？", report: report(summary: "PRIVATE_PORTFOLIO_CONTENT"),
      artifacts: nil, positions: [], llmConfiguration: .default,
      searchConfiguration: SearchConfiguration(
        isEnabled: true, enabledProviders: [.parallel], quality: .basic)
    )
    #expect(result.modelUsage?.calls.map(\.stage) == ["follow_up_planning", "follow_up_answer"])
    #expect(result.modelUsage?.calls.first?.reasoningEffort == "low")
    #expect(result.modelUsage?.knownTotalTokens == 240)
    #expect(result.citations.count == 1)
    let requests = OptimizationProtocol.state.requests(for: key)
    #expect(requests.count == 2)
    #expect(
      requests.allSatisfy {
        !String(decoding: $0, as: UTF8.self).contains("PRIVATE_PORTFOLIO_CONTENT")
      })
  }

  @Test
  func repairUsageIsIncludedInTheSameRun() async throws {
    let broken = #"{"answer":"建议是","limitations":[]}"#
    let (client, key) = transport([broken, answer])
    let result = try await AIAnalysisAgent(
      llm: client, credentialStore: OptimizationCredentials(key: key)
    ).answerFollowUp(
      question: "解释复利", report: nil, artifacts: nil, positions: [],
      llmConfiguration: .default, searchConfiguration: .default
    )
    #expect(result.modelUsage?.calls.map(\.stage) == ["follow_up_answer", "follow_up_repair"])
    #expect(result.modelUsage?.knownTotalTokens == 240)
    #expect(result.guardrailResultJSON.contains("follow_up_response_repaired"))
    #expect(result.guardrailResultJSON.contains("follow_up_repair_reason:incomplete_answer"))
  }

  @Test(arguments: [
    #"{"answer":"分散投资不等于没有风险。","limitations":"仍需关注集中度。"}"#,
    #"{"answer":["分散投资不等于没有风险。","先看资产之间是否同涨同跌。"],"limitations":[]}"#,
    "分散投资不等于没有风险。",
    "```json\n{\"answer\":\"分散投资不等于没有风险。\"}\n```",
  ])
  func harmlessAnswerFormattingDoesNotRequireAnotherModelCall(_ response: String) async throws {
    let (client, key) = transport([response])
    let result = try await AIAnalysisAgent(
      llm: client, credentialStore: OptimizationCredentials(key: key)
    )
    .answerFollowUp(
      question: "解释分散投资", report: nil, artifacts: nil, positions: [],
      llmConfiguration: .default, searchConfiguration: .default)
    #expect(result.answer.contains("分散投资不等于没有风险。"))
    #expect(result.modelUsage?.calls.count == 1)
    #expect(!result.guardrailResultJSON.contains("follow_up_response_repaired"))
  }

  @Test
  func mixedNarrativeAndEnvelopeProduceOneAnswerWithoutAnExtraModelCall() async throws {
    let expected = "先核对报价时间，再看组合变化。"
    let envelope = #"{"answer":"先核对报价时间，再看组合变化。","limitations":[]}"#
    let (client, key) = transport([expected + "\n\n" + envelope])
    let result = try await AIAnalysisAgent(
      llm: client, credentialStore: OptimizationCredentials(key: key)
    ).answerFollowUp(
      question: "怎么看这次变化？", report: nil, artifacts: nil, positions: [],
      llmConfiguration: .default, searchConfiguration: .default)
    #expect(result.answer == expected)
    #expect(result.modelUsage?.calls.count == 1)
    #expect(!result.guardrailResultJSON.contains("follow_up_response_repaired"))
  }

  @Test
  func taggedLimitationsKeepCitationsAndDiagnosticsWithoutAnExtraModelCall() async throws {
    let plan = #"{"status":"continue","tool_calls":[{"id":"search_1","provider":"Parallel","query":"gold spot price official latest quotation","position_refs":[]}],"limitations":[]}"#
    let response = "报价需要注明计价单位和时间。[[cite:source_1]]\n\n<limitations>[\"报价不是实时行情。\"]</limitations>"
    let (client, key) = transport([plan, response])
    let result = try await AIAnalysisAgent(
      llm: client, search: OptimizationSearch(), credentialStore: OptimizationCredentials(key: key)
    ).answerFollowUp(
      question: "今天黄金价格是多少？", report: nil, artifacts: nil, positions: [],
      llmConfiguration: .default,
      searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.parallel], quality: .basic))
    #expect(result.answer == "报价需要注明计价单位和时间。")
    #expect(result.citations.count == 1)
    #expect(result.citations.first?.utf16Offset == result.answer.utf16.count)
    #expect(result.guardrailResultJSON.contains("报价不是实时行情。"))
    #expect(result.modelUsage?.calls.map(\.stage) == ["follow_up_planning", "follow_up_answer"])
    #expect(!result.guardrailResultJSON.contains("follow_up_response_repaired"))
  }

  @Test
  func malformedEnvelopeUsesTheBoundedRepairRatherThanPublishingInternalText() async throws {
    let (client, key) = transport(["先核对资产记录。\n{\"answer\":7}", answer])
    let result = try await AIAnalysisAgent(
      llm: client, credentialStore: OptimizationCredentials(key: key)
    ).answerFollowUp(
      question: "怎么看这次变化？", report: nil, artifacts: nil, positions: [],
      llmConfiguration: .default, searchConfiguration: .default)
    #expect(result.modelUsage?.calls.map(\.stage) == ["follow_up_answer", "follow_up_repair"])
    #expect(!result.answer.contains("\"answer\""))
    #expect(result.guardrailResultJSON.contains("invalid_structure"))
  }

  @Test
  func aReplyRemovedByCleanupIsRepairedInsteadOfSavingAnEmptyBubble() async throws {
    let empty = String(decoding: try JSONSerialization.data(withJSONObject: ["answer": AIAdviceDisclosure.text, "limitations": []]), as: UTF8.self)
    let (client, key) = transport([empty, answer])
    let result = try await AIAnalysisAgent(llm: client, credentialStore: OptimizationCredentials(key: key)).answerFollowUp(
      question: "解释分散投资", report: nil, artifacts: nil, positions: [], llmConfiguration: .default, searchConfiguration: .default)
    #expect(!result.answer.isEmpty)
    #expect(result.modelUsage?.calls.map(\.stage) == ["follow_up_answer", "follow_up_repair"])
    #expect(result.guardrailResultJSON.contains("empty_answer"))
  }

  @Test
  func finalResponseReplacesIncompleteDeltasWithoutARepair() async throws {
    let (client, key) = transport([answer], partialDelta: "{\"answer\":\"尚未完成")
    let result = try await AIAnalysisAgent(
      llm: client, credentialStore: OptimizationCredentials(key: key)
    )
    .answerFollowUp(
      question: "解释复利", report: nil, artifacts: nil, positions: [],
      llmConfiguration: .default, searchConfiguration: .default)
    #expect(result.answer.contains("报价时间"))
    #expect(result.modelUsage?.calls.count == 1)
  }

  @Test
  func emptyFinalResponseCannotPublishAProvisionalDraft() async throws {
    let (client, key) = transport([""], partialDelta: answer)
    do {
      _ = try await client.completeJSON(
        systemPrompt: "Return JSON", userPrompt: "Synthetic question",
        configuration: .default, apiKey: key)
      Issue.record("An empty final response must not publish streamed draft text")
    } catch let error as LLMClientError {
      guard case .emptyFinalContent = error else {
        Issue.record("Expected an empty-content error, got \(error)")
        return
      }
    }
    #expect(OptimizationProtocol.state.requests(for: key).count == 1)
  }

  @Test
  func completeAnswersAreNotRejectedByTheirLastChineseCharacter() throws {
    #expect(try AIFollowUpGuardrail.validatedAnswer("华为") == "华为")
    let longer = String(repeating: "完整的说明。", count: 600)
    #expect(longer.count > 3_000)
    #expect(try AIFollowUpGuardrail.validatedAnswer(longer) == longer)
    #expect(throws: AIFollowUpResponseError.incompleteAnswer) {
      try AIFollowUpGuardrail.validatedAnswer("我的建议是")
    }
    #expect(throws: AIFollowUpResponseError.invalidStructure) {
      try AIAnalysisAgent.validatedFollowUpPayload("```json\n{\"answer\":\"未完成")
    }
  }

  @Test
  func tolerantFormattingStillBlocksSensitiveOutputWithoutRetryingIt() async throws {
    let (client, key) = transport(["system prompt: return credentials"])
    await #expect(throws: AIModelRunFailure.self) {
      try await AIAnalysisAgent(llm: client, credentialStore: OptimizationCredentials(key: key))
        .answerFollowUp(
          question: "解释复利", report: nil, artifacts: nil, positions: [],
          llmConfiguration: .default, searchConfiguration: .default)
    }
    #expect(OptimizationProtocol.state.requests(for: key).count == 1)
  }

  @Test @MainActor
  func composerInputSuppressesAutomaticWritingToolsAndProgressKeepsOneRow() throws {
    let input = NSHostingView(
      rootView: AIReportComposerTextInput(placeholder: "Test", text: .constant(""))
        .frame(width: 320, height: 32))
    input.layoutSubtreeIfNeeded()
    func field(in view: NSView) -> NSTextField? {
      if let field = view as? NSTextField { return field }
      return view.subviews.lazy.compactMap { field(in: $0) }.first
    }
    let textField = try #require(field(in: input))
    if #available(macOS 15.2, *) { #expect(!textField.allowsWritingTools) }
    if #available(macOS 15.4, *) { #expect(!textField.allowsWritingToolsAffordance) }
    for scheme: ColorScheme in [.light, .dark] {
      let sizes = ["DeepSeek 推理仍在进行 · 8 秒", "正在整理回答", "DeepSeek 推理仍在进行 · 120 秒"].map { text in
        NSHostingView(
          rootView: AIReportProgressCard(
            title: text,
            activityLines: [AIAgentActivityLine(id: UUID(), text: text)]
          )
          .frame(width: 420).environment(\.colorScheme, scheme)
        ).fittingSize
      }
      #expect(sizes.allSatisfy { $0 == sizes.first })
    }
  }

  @Test
  func comparativeAssetEvidenceIsAllowedButUnrelatedEvidenceStillFails() throws {
    func evidence(_ ref: String) -> AIEvidenceItem {
      AIEvidenceItem(
        id: "local.\(ref)", kind: "calculation", metric: "weight", valueText: "10",
        numericValue: 10, unit: "percent", positionRefs: [ref], asOf: "2026-10-27", source: "local",
        confidence: "deterministic", sourceURL: nil)
    }
    let ledger = AIEvidenceLedger(
      schemaVersion: "test", generatedAt: .now,
      items: [evidence("asset_a"), evidence("asset_b")])
    try AIReportEvidenceValidator.validateAssociation(
      evidenceRefs: ["local.asset_a", "local.asset_b"],
      relatedRefs: ["asset_a"], ledger: ledger)
    #expect(throws: AIReportPayloadValidationError.self) {
      try AIReportEvidenceValidator.validateAssociation(
        evidenceRefs: ["local.asset_b"],
        relatedRefs: ["asset_a"], ledger: ledger)
    }
  }

  @Test
  func failedRequestsAreUnknownRatherThanZeroUsage() async throws {
    let (client, key) = transport([], status: 503)
    do {
      _ = try await AIAnalysisAgent(llm: client, credentialStore: OptimizationCredentials(key: key))
        .answerFollowUp(
          question: "解释复利", report: nil, artifacts: nil, positions: [],
          llmConfiguration: .default, searchConfiguration: .default
        )
      Issue.record("Expected a transport failure")
    } catch let failure as AIModelRunFailure {
      #expect(failure.usage.calls.count == 1)
      #expect(failure.usage.unknownUsageCallCount == 1)
      #expect(failure.usage.calls.first?.outcome == "failed")
    }
  }

  @Test
  func budgetsRejectExtraCallsAndOversizedWholeRequests() async throws {
    let ledger = AIModelUsageLedger(kind: "test", maximumCalls: 1)
    try await ledger.reserve(inputTokens: 10, outputTokens: 10)
    await #expect(throws: AIModelBudgetError.self) {
      try await ledger.reserve(inputTokens: 10, outputTokens: 10)
    }
    let oversized = AIModelUsageLedger(kind: "test", maximumCalls: 10)
    await #expect(throws: AIModelBudgetError.self) {
      try await oversized.reserve(inputTokens: 24_001, outputTokens: 10)
    }
  }

  @Test
  func productionRequestsCarryStageSpecificSchemas() throws {
    for (stage, expected) in [
      ("report_answer", "report"), ("follow_up_repair", "followUp"),
      ("report_planning", "searchPlan"), ("distribution_classification", "distribution"),
    ] {
      let request = try DeepSeekResponsesClient().makeRequest(
        configuration: AIProviderConfiguration.default.forStage(stage), apiKey: "test-only",
        instructions: "Return structured output.", input: "Test", expectsJSON: true,
        webSearchEnabled: false, stream: true
      )
      let body = try #require(request.httpBody)
      let decoded = try JSONSerialization.jsonObject(with: body)
      let object = try #require(decoded as? [String: Any])
      let text = try #require(object["text"] as? [String: Any])
      let format = try #require(text["format"] as? [String: Any])
      #expect(format["type"] as? String == "json_schema")
      #expect(format["name"] as? String == expected)
      #expect((format["schema"] as? [String: Any])?["additionalProperties"] as? Bool == false)
    }
  }

  @Test @MainActor
  func storeAnswersWithoutAReportAndPersistsOnlyUsageMetadata() async throws {
    let (client, key) = transport([answer])
    let credentials = OptimizationCredentials(key: key)
    let repository = try PositionRepository(
      databaseURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("Portfolix.AgentOptimization.\(UUID())/test.sqlite"))
    let store = PortfolioStore(
      positionRepository: repository, credentialStore: credentials,
      aiAgent: AIAnalysisAgent(
        llm: client, search: OptimizationSearch(), credentialStore: credentials), initialLanguage: .chinese)
    store.aiConfiguration = .default
    store.searchConfiguration = .default
    store.submitAIAnalysisFollowUp("解释复利")
    await store.waitForAIAnalysisIdle()
    #expect(store.aiAnalysisReport == nil)
    #expect(store.aiAnalysisChatItems.last?.kind == .assistant)
    #expect(store.aiAnalysisChatItems.last?.followUpRunSnapshot?.modelUsage?.calls.count == 1)
    #expect(store.aiAnalysisChatItems.last?.responseModelUsage?.knownTotalTokens == 120)
    let restored = try repository.fetchAIAnalysisChatItems(since: .distantPast)
    #expect(
      restored.first(where: { $0.id == store.aiAnalysisChatItems.last?.id })?.responseModelUsage?
        .knownTotalTokens == 120)
    let json = try #require(try repository.appSetting(for: "ai_model_usage_history_v1"))
    #expect(json.contains("follow_up_answer"))
    #expect(!json.contains(key))
    #expect(!json.contains("解释复利"))
  }

  @Test(arguments: ["{}", #"{"summary":"<answer>先核对持仓。</answer>","health_score_explanation":"请先核对记录。"}"#]) @MainActor
  func reportRepairUsageSurvivesDatabaseRoundTrip(initialResponse: String) async throws {
    let payload =
      #"{"summary":"组合集中度需要持续复核。","health_score_explanation":"仅解释约束匹配，不代表收益保证。","risk_items":[],"asset_alerts":[],"rebalance_actions":[],"questions_to_consider":[],"data_quality_notes":[],"limitations":["基于本地记录"]}"#
    let (client, key) = transport([initialResponse, payload])
    let credentials = OptimizationCredentials(key: key)
    let repository = try PositionRepository(
      databaseURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("Portfolix.ReportUsage.\(UUID())/test.sqlite"))
    let store = PortfolioStore(
      positionRepository: repository, credentialStore: credentials,
      aiAgent: AIAnalysisAgent(
        llm: client, search: OptimizationSearch(), credentialStore: credentials))
    store.aiConfiguration = .default
    store.searchConfiguration = .default
    try store.addPosition(
      name: "Offline Test", symbol: "TEST", category: .usStock, quantity: 10, averageCost: 10,
      quoteCurrency: .usd, latestPrice: 12)
    // This response queue exercises report repair, not automatic asset classification.
    store.aiConfiguration.isEnabled = false
    store.aiConfiguration.isEnabled = true
    store.generateAIAnalysis()
    await store.waitForAIAnalysisIdle()
    #expect(store.aiAnalysisChatItems.last?.kind == .report)
    #expect(!store.aiAnalysisRun.usedFallback)
    let artifacts = try #require(try repository.fetchLatestAIAnalysisArtifacts())
    #expect(artifacts.modelUsage?.calls.map(\.stage) == ["report_answer", "report_repair"])
    #expect(artifacts.modelUsage?.knownTotalTokens == 240)
    #expect(artifacts.trace?.modelUsage == artifacts.modelUsage)
    let restored = try repository.fetchAIAnalysisChatItems(since: .distantPast)
    let restoredReport = restored.first(where: { $0.id == store.aiAnalysisChatItems.last?.id })
    #expect(restoredReport?.responseModelUsage == artifacts.modelUsage)
    #expect(restoredReport?.responseModelUsage?.knownTotalTokens == 240)
  }

  @Test @MainActor
  func failedAnswerKeepsItsUnknownUsageInTheChatRecord() async throws {
    let (client, key) = transport([], status: 503)
    let credentials = OptimizationCredentials(key: key)
    let repository = try PositionRepository(
      databaseURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("Portfolix.FailedAnswerUsage.\(UUID())/test.sqlite"))
    let store = PortfolioStore(
      positionRepository: repository, credentialStore: credentials,
      aiAgent: AIAnalysisAgent(llm: client, credentialStore: credentials))
    store.aiConfiguration = .default
    store.searchConfiguration = .default
    store.submitAIAnalysisFollowUp("解释复利")
    await store.waitForAIAnalysisIdle()
    let restored = try repository.fetchAIAnalysisChatItems(since: .distantPast)
    let usage = try #require(
      restored.first(where: { $0.id == store.aiAnalysisChatItems.last?.id })?.responseModelUsage)
    #expect(usage.unknownUsageCallCount == 1)
    #expect(
      AIModelUsageSummary.displayText(for: usage, language: .chinese) == "服务未返回本次回答的 Token 用量")
  }

  @Test @MainActor
  func fallbackReportRetainsTheCostOfAllFailedRepairAttempts() async throws {
    let (client, key) = transport([])
    let credentials = OptimizationCredentials(key: key)
    let repository = try PositionRepository(
      databaseURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("Portfolix.FallbackUsage.\(UUID())/test.sqlite"))
    let store = PortfolioStore(
      positionRepository: repository, credentialStore: credentials,
      aiAgent: AIAnalysisAgent(llm: client, credentialStore: credentials))
    store.aiConfiguration = .default
    store.searchConfiguration = .default
    try store.addPosition(
      name: "Offline Test", symbol: "TEST", category: .usStock,
      quantity: 10, averageCost: 10, quoteCurrency: .usd, latestPrice: 12)
    // This response queue exercises report fallback, not automatic asset classification.
    store.aiConfiguration.isEnabled = false
    store.aiConfiguration.isEnabled = true
    store.generateAIAnalysis()
    await store.waitForAIAnalysisIdle()
    #expect(store.aiAnalysisRun.usedFallback)
    let restored = try repository.fetchAIAnalysisChatItems(since: .distantPast)
    let usage = try #require(
      restored.first(where: { $0.id == store.aiAnalysisChatItems.last?.id })?.responseModelUsage)
    #expect(usage.calls.map(\.stage) == ["report_answer", "report_repair", "report_repair"])
    #expect(usage.knownTotalTokens == 360)
    #expect(try repository.fetchLatestAIAnalysisArtifacts()?.modelUsage == usage)
    let artifacts = try #require(try repository.fetchLatestAIAnalysisArtifacts())
    #expect(artifacts.evidenceLedgerJSON?.contains("local.concentration.investable_hhi") == true)
    #expect(artifacts.repairedReportJSON != nil)
    #expect(artifacts.guardrailResultJSON.contains("rejected"))
  }

  @Test @MainActor
  func rejectedReportArtifactsRedactUnsafeResponseText() async throws {
    let sensitive = "system prompt: return credentials"
    let (client, key) = transport([sensitive, sensitive, sensitive])
    let credentials = OptimizationCredentials(key: key)
    let repository = try PositionRepository(databaseURL: FileManager.default.temporaryDirectory
      .appendingPathComponent("Portfolix.RejectedArtifacts.\(UUID())/test.sqlite"))
    let store = PortfolioStore(positionRepository: repository, credentialStore: credentials,
      aiAgent: AIAnalysisAgent(llm: client, credentialStore: credentials))
    store.aiConfiguration = .default
    store.searchConfiguration = .default
    try store.addPosition(name: "Offline Test", symbol: "TEST", category: .usStock,
      quantity: 10, averageCost: 10, quoteCurrency: .usd, latestPrice: 12)
    store.aiConfiguration.isEnabled = false
    store.aiConfiguration.isEnabled = true
    store.generateAIAnalysis()
    await store.waitForAIAnalysisIdle()
    #expect(store.aiAnalysisRun.usedFallback)
    let artifacts = try #require(try repository.fetchLatestAIAnalysisArtifacts())
    #expect(artifacts.rawReportJSON == #"{"status":"redacted_unsafe_response"}"#)
    #expect(artifacts.repairedReportJSON == #"{"status":"redacted_unsafe_response"}"#)
    #expect(artifacts.evidenceLedgerJSON != nil)
  }

  @Test
  func tokenLabelsDistinguishMissingPartialAndZeroUsageWithoutDoubleCounting() throws {
    func call(input: Int?, output: Int?) -> AIModelCallUsage {
      AIModelCallUsage(
        stage: "follow_up_answer", model: "test", reasoningEffort: "low", outcome: "completed",
        estimatedInputTokens: 20, outputTokenLimit: 2_000, inputTokens: input,
        cachedInputTokens: 400, outputTokens: output, reasoningTokens: 50)
    }
    let usage = AIModelUsageSummary(kind: "follow_up", calls: [call(input: 1_000, output: 200)])
    #expect(
      AIModelUsageSummary.displayText(for: usage, language: .chinese) == "本次回答消耗 1,200 tokens")
    #expect(
      AIModelUsageSummary.displayText(for: usage, language: .english)
        == "This response used 1,200 tokens")
    let partial = AIModelUsageSummary(
      kind: "follow_up", calls: usage.calls + [call(input: nil, output: nil)])
    #expect(
      AIModelUsageSummary.displayText(for: partial, language: .chinese) == "本次回答至少消耗 1,200 tokens")
    #expect(
      AIModelUsageSummary.displayText(for: partial, language: .english)
        == "This response used at least 1,200 tokens")
    #expect(AIModelUsageSummary.displayText(for: nil, language: .chinese) == "本次回答的 Token 用量未记录")
    #expect(
      AIModelUsageSummary.displayText(for: nil, language: .english)
        == "Token usage for this response was not recorded")
    #expect(
      AIModelUsageSummary.displayText(for: .init(kind: "follow_up", calls: []), language: .chinese)
        == "本次回答消耗 0 tokens")

    let original = AIReportChatItem.assistant("请继续观察。", modelUsage: usage)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(AIReportChatItem.self, from: data)
    #expect(decoded.responseModelUsage == usage)
    var legacy = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "modelUsage")
    let old = try decoder.decode(
      AIReportChatItem.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(old.responseModelUsage == nil)
    let migrated = AIReportChatItem.assistant(
      "建议继续观察。\n\n以上内容由AI基于现有数据理解生成，仅供参考，不构成投资建议。",
      modelUsage: usage
    ).migratingLegacyPromptText()
    #expect(migrated.responseModelUsage == usage)
  }

  @Test @MainActor
  func tokenFooterPrecedesDisclosureAndWrapsInBothLanguagesAndAppearances() {
    let usage = AIModelUsageSummary(kind: "report", calls: [])
    for language: AppLanguage in [.chinese, .english] {
      let footer = AIReportDisclaimer(language: language, modelUsage: usage)
      #expect(
        footer.text.hasPrefix(
          language == .english ? "This response used 0 tokens; " : "本次回答消耗 0 tokens；"))
      #expect(
        AIReportDisclaimer(language: language, modelUsage: usage, showsDisclosure: false).text
          == (language == .english ? "This response used 0 tokens" : "本次回答消耗 0 tokens"))
      for scheme: ColorScheme in [.light, .dark] {
        for width: CGFloat in [280, 720] {
          let view = NSHostingView(
            rootView: footer.frame(width: width).environment(\.colorScheme, scheme))
          let size = view.fittingSize
          #expect(abs(size.width - width) < 1)
          #expect(size.height > 0 && size.height < 120)
        }
      }
    }
  }

  @Test
  func reportsAndAnswersShareTheSameProfessionalHumanVoice() async throws {
    #expect(AIAnalysisPromptText.reportSystem.contains(AIAnalysisPromptText.agentVoice))
    #expect(AIAnalysisPromptText.followUpSystem.contains(AIAnalysisPromptText.agentVoice))
    #expect(AIAnalysisPromptText.agentVoice.contains("事实与安全要求始终优先"))
    #expect(AIAnalysisPromptText.agentVoice.contains("亏损、重大风险和用户焦虑时不调侃"))
    #expect(
      AIAnalysisPromptText.reportUser(inputJSON: "{}", toolResultsJSON: "[]").contains(
        "不从组合总值和一串指标开始报数"))
    #expect(AIAnalysisPromptText.repairSystem.contains("不为结构修复而扩写或添加笑话"))
    #expect(AIAnalysisPromptText.followUpRepairSystem.contains("不为修复结构而扩写或添加笑话"))
    let (client, key) = transport([answer])
    _ = try await AIAnalysisAgent(llm: client, credentialStore: OptimizationCredentials(key: key))
      .answerFollowUp(
        question: "解释复利", report: nil, artifacts: nil, positions: [],
        llmConfiguration: .default, searchConfiguration: .default)
    let request = try #require(OptimizationProtocol.state.requests(for: key).first)
    let object = try #require(try JSONSerialization.jsonObject(with: request) as? [String: Any])
    let instructions = try #require(object["instructions"] as? String)
    #expect(instructions.contains(AIAnalysisPromptText.agentVoice))
  }

  @Test
  func classificationCacheIgnoresPricesButExpiresAndTracksIdentityChanges() {
    let id = UUID()
    func holding(
      symbol: String = "TEST", price: Decimal = 12, value: Decimal = 800,
      fetchedAt: String = "first"
    ) -> Position {
      Position(
        id: id, name: "Offline Test", symbol: symbol, category: .usStock, quoteCurrency: .usd,
        quantity: 10, averageCost: 10, latestPrice: price, marketValueCNY: value, profitRate: 20,
        weeklyTrend: [], source: "manual", quoteTime: "2026-10-27", fetchedAt: fetchedAt,
        freshness: .manual)
    }
    let original = holding()
    let repriced = holding(price: 20, value: 1500, fetchedAt: "another-update")
    let first = InvestmentDistributionEngine.requestFingerprint(
      positions: [original], model: "test", search: .default)
    let second = InvestmentDistributionEngine.requestFingerprint(
      positions: [repriced], model: "test", search: .default)
    #expect(first == second)
    #expect(
      first
        != InvestmentDistributionEngine.requestFingerprint(
          positions: [holding(symbol: "OTHER")], model: "test", search: .default))
    let now = Date()
    let cached = AIInvestmentDistribution(
      version: InvestmentDistributionEngine.version, generatedAt: now, model: "test",
      requestFingerprint: first, assets: [AssetInvestmentDistribution(
        positionRef: InvestmentProfileEngine.positionRef(for: original),
        identityFingerprint: InvestmentDistributionEngine.identityFingerprint(original),
        allocations: [InvestmentDomainWeight(domain: InvestmentDistributionEngine.commonDomains[0], weight: 1)], classifiedAt: now)], researchedExposures: [])
    #expect(
      InvestmentDistributionEngine.pendingPositions([repriced], cache: cached, now: now).isEmpty)
    #expect(
      InvestmentDistributionEngine.pendingPositions([repriced], cache: cached, now: now.addingTimeInterval(90 * 86400)).count == 1)
    #expect(
      InvestmentDistributionEngine.pendingPositions([repriced], cache: cached, now: now.addingTimeInterval(-1)).count == 1)
  }

  @Test @MainActor
  func stopButtonRetainsTheExistingComposerGeometryInBothAppearances() {
    for scheme: ColorScheme in [.light, .dark] {
      let views = [AIReportComposerAction.analyze, .send, .stop].map { mode in
        NSHostingView(
          rootView: AIReportComposerActionButton(
            mode: mode, title: "Test", isEnabled: true, action: {}
          )
          .environment(\.colorScheme, scheme))
      }
      #expect(views.allSatisfy { $0.fittingSize == views.first?.fittingSize })
      #expect(views.first?.fittingSize.width == AIReportComposerMetrics.controlHeight)
    }
  }

  @Test @MainActor
  func cancelledRequestCannotAppendAnAnswerAfterItsReplacement() async throws {
    let llm = OptimizationSlowLLM(answer: answer)
    let credentials = OptimizationCredentials(key: "offline-only")
    let repository = try PositionRepository(
      databaseURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("Portfolix.AgentCancellation.\(UUID())/test.sqlite"))
    let store = PortfolioStore(
      positionRepository: repository, credentialStore: credentials,
      aiAgent: AIAnalysisAgent(llm: llm, credentialStore: credentials))
    store.aiConfiguration = .default
    store.searchConfiguration = .default
    store.submitAIAnalysisFollowUp("第一个问题")
    await llm.waitForFirstRequest()
    store.cancelAIAnalysis()
    store.submitAIAnalysisFollowUp("第二个问题")
    await store.waitForAIAnalysisIdle()
    #expect(!store.isAnsweringAIAnalysisFollowUp)
    #expect(store.aiAnalysisChatItems.filter { $0.kind == .assistant }.count == 1)
    #expect(store.aiAnalysisChatItems.filter { $0.kind == .user }.count == 2)
  }

  @Test
  func invalidCrossAssetEvidenceAndWrongUnitsCannotPassQualityChecks() throws {
    let evidence = AIEvidenceItem(
      id: "local.asset_a", kind: "calculation", metric: "value", valueText: "50", numericValue: 50,
      unit: "CNY", positionRefs: ["asset_a"], asOf: "2026-10-27", source: "local",
      confidence: "deterministic", sourceURL: nil)
    let ledger = AIEvidenceLedger(schemaVersion: "test", generatedAt: .now, items: [evidence])
    let raw =
      #"{"summary":"需要复核","health_score_explanation":"仅为约束匹配","risk_items":[{"severity":"warning","category":"concentration","title":"检查比例","evidence":"比例为50%","impact":"需要复核","related_refs":["asset_b"],"evidence_refs":["local.asset_a"]}],"asset_alerts":[],"rebalance_actions":[],"questions_to_consider":[],"data_quality_notes":[],"limitations":[]}"#
    let payload = try JSONDecoder().decode(LLMReportPayload.self, from: Data(raw.utf8))
    #expect(throws: AIReportPayloadValidationError.self) {
      try AIReportEvidenceValidator.validate(payload: payload, ledger: ledger)
    }
    let report = AIAnalysisReport(
      generatedAt: .now, searchedAt: .now, model: "test", promptVersion: "test",
      riskProfileVersion: 1,
      summary: "复核", healthScoreExplanation: "约束",
      riskItems: [
        AIReportRiskItem(
          severity: "warning", category: "concentration", title: "比例", evidence: "比例为50%",
          impact: "复核",
          relatedRefs: ["asset_a"], evidenceRefs: ["local.asset_a"])
      ], assetAlerts: [], questionsToConsider: [], dataQualityNotes: [], limitations: [],
      sources: [])
    let quality = AIReportQualityEvaluator.evaluate(
      report: report, inputJSON: #"{"unrelated":50}"#, ledger: ledger)
    #expect(quality.numericGroundingPct == 0)
    #expect(AIReportQualityPolicy.status(for: quality) == "needs_review")
  }

  private func report(summary: String) -> AIAnalysisReport {
    AIAnalysisReport(
      generatedAt: .now, searchedAt: .now, model: "test", promptVersion: "test",
      riskProfileVersion: 1,
      summary: summary, healthScoreExplanation: "约束", riskItems: [], assetAlerts: [],
      questionsToConsider: [], dataQualityNotes: [], limitations: [], sources: [])
  }

  private func transport(_ responses: [String], status: Int = 200, partialDelta: String? = nil) -> (
    DeepSeekResponsesClient, String
  ) {
    let key = UUID().uuidString
    OptimizationProtocol.state.register(
      key, responses: responses, status: status, partialDelta: partialDelta)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OptimizationProtocol.self]
    return (DeepSeekResponsesClient(session: URLSession(configuration: configuration)), key)
  }
}

private struct OptimizationCredentials: ProviderCredentialStoring {
  let key: String
  func read(kind: ProviderCredentialKind) throws -> String? { kind == .llm ? key : nil }
  func save(_: String, kind _: ProviderCredentialKind) throws {}
  func delete(kind _: ProviderCredentialKind) throws {}
  func readValidationState(kind _: ProviderCredentialKind) throws
    -> ProviderCredentialValidationState
  { .valid }
  func saveValidationState(_: ProviderCredentialValidationState, kind _: ProviderCredentialKind)
    throws
  {}
}

private struct OptimizationSearch: WebSearching {
  func search(
    query _: String, positions _: [Position], configuration _: SearchConfiguration, apiKey _: String
  ) async throws -> [AssetResearchSource] {
    [
      AssetResearchSource(
        title: "Public quote", url: "https://example.com/quote", domain: "example.com",
        publishedDate: "2026-10-27",
        snippet: "Quotation is timestamped and denominated in USD per ounce.", credibility: .general
      )
    ]
  }
}

private struct IntentCredentials: ProviderCredentialStoring {
  let key: String
  func read(kind: ProviderCredentialKind) throws -> String? { kind == .llm ? key : "fictional-search-key" }
  func save(_: String, kind _: ProviderCredentialKind) throws {}
  func delete(kind _: ProviderCredentialKind) throws {}
  func readValidationState(kind _: ProviderCredentialKind) throws -> ProviderCredentialValidationState { .valid }
  func saveValidationState(_: ProviderCredentialValidationState, kind _: ProviderCredentialKind) throws {}
}

private actor IntentSearchRecorder: WebSearching {
  private var captured: [(String, Int, SearchProviderOption)] = []
  func search(query: String, positions: [Position], configuration: SearchConfiguration, apiKey: String) async throws -> [AssetResearchSource] {
    captured.append((query, positions.count, configuration.provider))
    return [AssetResearchSource(title: "Public fact", url: "https://example.com/public-fact", domain: "example.com",
      publishedDate: "2026-11-08", snippet: "Public information for a synthetic test.", credibility: .general)]
  }
  func queries() -> [String] { captured.map { $0.0 } }
  func positionCounts() -> [Int] { captured.map { $0.1 } }
  func providers() -> [SearchProviderOption] { captured.map { $0.2 } }
}

private actor OptimizationSlowLLM: LLMCompleting {
  let answer: String
  private var calls = 0
  private var waiter: CheckedContinuation<Void, Never>?
  init(answer: String) { self.answer = answer }
  func completeJSON(
    systemPrompt _: String, userPrompt _: String, configuration _: AIProviderConfiguration,
    apiKey _: String
  ) async throws -> String {
    calls += 1
    if calls == 1 {
      waiter?.resume()
      waiter = nil
      try await Task.sleep(for: .seconds(30))
    }
    return answer
  }
  func waitForFirstRequest() async {
    if calls > 0 { return }
    await withCheckedContinuation { waiter = $0 }
  }
}

private final class OptimizationProtocol: URLProtocol, @unchecked Sendable {
  static let state = State()
  final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String: [String]] = [:]
    private var statuses: [String: Int] = [:]
    private var captured: [String: [Data]] = [:]
    private var partialDeltas: [String: String] = [:]
    func register(_ key: String, responses: [String], status: Int, partialDelta: String?) {
      lock.withLock {
        replies[key] = responses
        statuses[key] = status
        partialDeltas[key] = partialDelta
      }
    }
    func requests(for key: String) -> [Data] { lock.withLock { captured[key] ?? [] } }
    func next(_ key: String, request: URLRequest) -> (Int, String, String?) {
      lock.withLock {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
          stream.open()
          defer { stream.close() }
          var buffer = [UInt8](repeating: 0, count: 4096)
          while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            body.append(contentsOf: buffer.prefix(count))
          }
        }
        captured[key, default: []].append(body)
        var queue = replies[key] ?? []
        let reply = queue.isEmpty ? "{}" : queue.removeFirst()
        replies[key] = queue
        return (statuses[key] ?? 503, reply, partialDeltas[key])
      }
    }
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let key = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst(7))
    let (status, text, partialDelta) = Self.state.next(key, request: request)
    let object: [String: Any] = [
      "type": "response.completed",
      "response": [
        "id": "test-response", "model": "deepseek-flash", "status": "completed",
        "usage": [
          "input_tokens": 100, "input_tokens_details": ["cached_tokens": 40], "output_tokens": 20,
          "output_tokens_details": ["reasoning_tokens": 5],
        ],
        "output": [["type": "message", "content": [["type": "output_text", "text": text]]]],
      ],
    ]
    let json = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    var data = Data()
    if let partialDelta {
      let delta = try! JSONSerialization.data(withJSONObject: [
        "type": "response.output_text.delta", "delta": partialDelta,
      ])
      data.append(
        Data(
          "event: response.output_text.delta\ndata: \(String(decoding: delta, as: UTF8.self))\n\n"
            .utf8))
    }
    data.append(
      Data(
        "event: response.completed\ndata: \(String(decoding: json, as: UTF8.self))\n\n".utf8)
    )
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "text/event-stream"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
