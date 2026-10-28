import CSQLite
import Foundation
import Testing

@testable import Portfolix

@Suite("Opt-in DeepSeek contract integration")
struct AIOptimizationLiveTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTFOLIX_RUN_DOMAIN_CLASSIFICATION_LIVE"] == "1"))
  func investmentDomainsClassifyOnceWithoutReasoningOrSearch() async throws {
    let key = try readConfiguredKeyWithoutLoadingPortfolio()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.urlCredentialStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForResource = 90
    let session = URLSession(configuration: configuration, delegate: LiveVerificationRedirectPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let client = LimitedDistributionLiveClient(base: DeepSeekResponsesClient(session: session))
    let identities: [(String, String)] = [("华安黄金ETF", "518880"), ("华夏国证半导体芯片ETF", "159995"), ("虚构灵活配置混合", "SYNTHFUND")]
    let positions = identities.map { name, symbol in
      Position(name: name, symbol: symbol, category: .fund, quoteCurrency: .cny,
        quantity: 1, averageCost: 1, latestPrice: 1, marketValueCNY: 1, profitRate: 0,
        weeklyTrend: [], source: "synthetic", quoteTime: "2026-10-27", freshness: .manual)
    }
    let result = try await AIAnalysisAgent(llm: client, credentialStore: FunctionLiveCredentials(key: key))
      .generateInvestmentDistribution(positions: positions, llmConfiguration: .default,
        searchConfiguration: SearchConfiguration(isEnabled: false, provider: .parallel, quality: .basic), requestFingerprint: "synthetic-domain-qa")
    #expect(await client.callCount == 1)
    let byRef = Dictionary(uniqueKeysWithValues: result.assets.map { ($0.positionRef, $0) })
    #expect(byRef[InvestmentProfileEngine.positionRef(for: positions[0])]?.allocations.first?.domain.id == "gold")
    #expect(byRef[InvestmentProfileEngine.positionRef(for: positions[1])]?.allocations.first?.domain.id == "cn_semiconductors")
    #expect(byRef[InvestmentProfileEngine.positionRef(for: positions[2])]?.allocations.isEmpty == true)
    #expect(result.modelUsage?.calls.count == 1)
    #expect(result.modelUsage?.calls.first?.reasoningEffort == "none")
    for call in result.modelUsage?.calls ?? [] {
      print("Domain live QA model_calls=1 search_calls=0 input=\(call.inputTokens ?? -1) output=\(call.outputTokens ?? -1) reasoning=\(call.reasoningTokens ?? -1)")
    }
  }

  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["PORTFOLIX_RUN_FUNCTION_TOOLS_LIVE"] == "1"))
  func nativeReadOnlyToolsCompleteAnImplicitPortfolioFollowUp() async throws {
    let key = try readConfiguredKeyWithoutLoadingPortfolio()
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.urlCredentialStorage = nil
    config.httpShouldSetCookies = false
    config.timeoutIntervalForResource = 90
    let session = URLSession(
      configuration: config, delegate: LiveVerificationRedirectPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let client = LimitedFunctionLiveClient(base: DeepSeekResponsesClient(session: session))
    let position = Position(
      name: "虚构测试资产", symbol: "SYNTHETIC", category: .usStock, quoteCurrency: .cny,
      quantity: 10, averageCost: 10, latestPrice: 12, marketValueCNY: 120, profitRate: 20,
      weeklyTrend: [], source: "manual", quoteTime: "2026-10-27", freshness: .manual)
    let result = try await AIAnalysisAgent(
      llm: client, credentialStore: FunctionLiveCredentials(key: key)
    )
    .answerFollowUp(
      question: "好的，你帮我看看", report: nil, artifacts: nil,
      chatHistory: [.assistant("我可以直接核对 App 中记录的持仓份额、总成本和当前市值，需要我帮你看看吗？")],
      positions: [position], llmConfiguration: .default, searchConfiguration: .default)
    #expect(await client.callCount == 2)
    #expect(await client.sawHoldingsOutput)
    #expect(result.localToolCallCount > 0)
    #expect(!result.answer.isEmpty)
    #expect(!result.guardrailResultJSON.contains("follow_up_response_repaired"))
    #expect(result.modelUsage?.unknownUsageCallCount == 0)
    print(
      "Function live QA validation=passed model_calls=\(await client.callCount) local_calls=\(result.localToolCallCount) repair_calls=0"
    )
    for call in result.modelUsage?.calls ?? [] {
      print("Function live QA input=\(call.inputTokens ?? -1) output=\(call.outputTokens ?? -1)")
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTFOLIX_RUN_RESPONSE_FIX_LIVE"] == "1"))
  func validatesRevisedAnswerAndReportWithoutRepair() async throws {
    let key = try readConfiguredKeyWithoutLoadingPortfolio()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.urlCredentialStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForResource = 90
    let session = URLSession(
      configuration: configuration, delegate: LiveVerificationRedirectPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let client = AIUsageTrackingLLM(base: DeepSeekResponsesClient(session: session))
    let syntheticInput =
      #"{"output_language":"zh-CN","analysis_mode":"basic_standard","snapshot":{"total_value_text":"¥1,000.00"},"risk_profile":{"configured":false},"metrics":{"positions":[{"position_ref":"position_synthetic_cash","display_label":"虚构测试现金","symbol":"CNY","asset_type":"cash","market_value_cny":"1000","allocation_pct":100}]},"risk_flags":[]}"#
    let prompts = [
      (
        "follow_up_answer", AIAnalysisPromptText.followUpSystem,
        AIAnalysisPromptText.followUpUser(
          question: "请用一两句话解释分散投资，不需要行情或持仓。",
          reportJSON: "{}", artifactSummary: "", searchMode: "disabled", toolResultsJSON: "[]")
      ),
      (
        "report_answer", AIAnalysisPromptText.reportSystem,
        AIAnalysisPromptText.reportUser(inputJSON: syntheticInput, toolResultsJSON: "[]")
          + "\n以上均为虚构数据。报告保持简短；没有设定风险约束，勿编造评分；风险、关注、建议和复核列表均可为空，不引用不存在的证据。"
      ),
    ]
    let (_, usage) = try await AIModelRun.tracked(
      kind: "synthetic_response_fix_verification", maximumCalls: 2
    ) {
      for (index, prompt) in prompts.enumerated() {
        print("Response fix live QA request=\(index + 1) stage=\(prompt.0)")
        let result = try await client.completeJSONResult(
          systemPrompt: prompt.1, userPrompt: prompt.2,
          configuration: AIProviderConfiguration.default.forStage(prompt.0).withMaxOutputTokens(
            2_000
          ).withRequestTimeout(90),
          apiKey: key, webSearchEnabled: false, reasoningEffort: .low, webSearchProgress: nil)
        if prompt.0 == "follow_up_answer" {
          _ = try AIAnalysisAgent.validatedFollowUpPayload(result.content)
        } else {
          let payload = try AIAnalysisAgent.validatedPayload(
            result.content, expectedLanguage: .simplifiedChinese)
          try AIReportEvidenceValidator.validate(
            payload: payload,
            ledger: AIEvidenceLedger(schemaVersion: "test", generatedAt: .now, items: []))
        }
        print("Response fix live QA stage=\(prompt.0) validation=passed repair_calls=0")
      }
    }
    #expect(usage.calls.count == 2)
    #expect(usage.unknownUsageCallCount == 0)
    #expect(
      usage.calls.allSatisfy { $0.outputTokenLimit == 2_000 && ($0.outputTokens ?? 0) <= 2_000 })
    for call in usage.calls {
      print(
        "Response fix live QA stage=\(call.stage) input=\(call.inputTokens ?? -1) output=\(call.outputTokens ?? -1)"
      )
    }
  }

  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment["PORTFOLIX_RUN_AGENT_OPTIMIZATION_LIVE"] == "1"))
  func validatesThreeContractsUsingOnlySyntheticData() async throws {
    let key = try readConfiguredKeyWithoutLoadingPortfolio()
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.urlCache = nil
    sessionConfiguration.urlCredentialStorage = nil
    sessionConfiguration.httpShouldSetCookies = false
    sessionConfiguration.timeoutIntervalForResource = 90
    let session = URLSession(
      configuration: sessionConfiguration, delegate: LiveVerificationRedirectPolicy(),
      delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let client = AIUsageTrackingLLM(base: DeepSeekResponsesClient(session: session))
    let requests = [
      ("follow_up_planning", "虚构测试：当前没有持仓，也没有可用搜索服务。用户只问复利的定义，返回空工具调用列表。"),
      ("follow_up_answer", "虚构测试：请用一句简体中文解释复利，不超过40字；limitations为空数组。"),
      ("report_answer", "虚构测试组合只有人民币现金1000元。用最简短的中文描述；风险、关注和建议列表均可为空。limitations注明这是虚构测试。"),
    ]
    let (outputs, usage) = try await AIModelRun.tracked(
      kind: "synthetic_live_verification", maximumCalls: 3
    ) {
      var outputs: [(String, String)] = []
      for (stage, input) in requests {
        print("Synthetic live QA request=\(outputs.count + 1) stage=\(stage)")
        let result = try await client.completeJSONResult(
          systemPrompt: "只输出符合JSON Schema的JSON对象。所有数据为虚构测试。输出简短，不调用工具。",
          userPrompt: input,
          configuration: AIProviderConfiguration.default.forStage(stage).withMaxOutputTokens(2_000)
            .withRequestTimeout(90),
          apiKey: key, webSearchEnabled: false, reasoningEffort: .low, webSearchProgress: nil
        )
        outputs.append((stage, result.content))
      }
      return outputs
    }
    #expect(outputs.count == 3)
    for (stage, content) in outputs {
      let data = Data(content.utf8)
      switch stage {
      case "follow_up_planning":
        let plan = try JSONDecoder().decode(AIWebSearchToolPlan.self, from: data)
        #expect(plan.toolCalls.isEmpty)
      case "follow_up_answer":
        let payload = try JSONDecoder().decode(LLMFollowUpPayload.self, from: data)
        #expect(!payload.answer.isEmpty)
      default:
        let report = try JSONDecoder().decode(LLMReportPayload.self, from: data)
        try AIAnalysisSchemaValidator.validate(payload: report)
      }
    }
    #expect(usage.calls.count == 3)
    #expect(usage.unknownUsageCallCount == 0)
    #expect(
      usage.calls.allSatisfy { $0.outputTokenLimit == 2_000 && ($0.outputTokens ?? 0) <= 2_000 })
    for call in usage.calls {
      print(
        "Synthetic live QA stage=\(call.stage) input=\(call.inputTokens ?? -1) cached=\(call.cachedInputTokens ?? -1) output=\(call.outputTokens ?? -1) reasoning=\(call.reasoningTokens ?? -1)"
      )
    }
  }

  private func readConfiguredKeyWithoutLoadingPortfolio() throws -> String {
    let path = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/app.portfolix.mac/portfolix.sqlite3")
      .path
    var database: OpaquePointer?
    guard
      sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK,
      let database
    else {
      if let database { sqlite3_close(database) }
      throw ProviderCredentialError.unavailable
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT value FROM app_settings WHERE key = 'provider_credential_llm_api_key' LIMIT 1", -1,
        &statement, nil) == SQLITE_OK,
      let statement
    else { throw ProviderCredentialError.unavailable }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0)
    else {
      throw ProviderCredentialError.unavailable
    }
    let key = String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { throw ProviderCredentialError.invalidValue }
    return key
  }
}

private actor LimitedDistributionLiveClient: LLMCompleting {
  let base: DeepSeekResponsesClient
  private(set) var callCount = 0
  init(base: DeepSeekResponsesClient) { self.base = base }
  func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String {
    try await completeJSONResult(systemPrompt: systemPrompt, userPrompt: userPrompt, configuration: configuration,
      apiKey: apiKey, webSearchEnabled: false, reasoningEffort: .none, webSearchProgress: nil).content
  }
  func completeJSONResult(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration,
    apiKey: String, webSearchEnabled: Bool, reasoningEffort: DeepSeekReasoningEffort,
    webSearchProgress: LLMWebSearchProgressHandler?) async throws -> LLMCompletionResult {
    guard callCount == 0, !webSearchEnabled, reasoningEffort == .none,
          configuration.functionTools.isEmpty, configuration.functionInputItems == nil else { throw AIModelBudgetError.exhausted }
    callCount += 1
    return try await base.completeJSONResult(systemPrompt: systemPrompt, userPrompt: userPrompt,
      configuration: configuration.withMaxOutputTokens(min(1200, configuration.maxOutputTokens)).withRequestTimeout(90),
      apiKey: apiKey, webSearchEnabled: false, reasoningEffort: .none, webSearchProgress: nil)
  }
}

private actor LimitedFunctionLiveClient: LLMCompleting {
  let base: DeepSeekResponsesClient
  private(set) var callCount = 0
  private(set) var sawHoldingsOutput = false
  init(base: DeepSeekResponsesClient) { self.base = base }
  func completeJSON(
    systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String
  ) async throws -> String {
    try await completeJSONResult(
      systemPrompt: systemPrompt, userPrompt: userPrompt, configuration: configuration,
      apiKey: apiKey, webSearchEnabled: false, reasoningEffort: .low, webSearchProgress: nil
    ).content
  }
  func completeJSONResult(
    systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration,
    apiKey: String, webSearchEnabled: Bool, reasoningEffort: DeepSeekReasoningEffort,
    webSearchProgress: LLMWebSearchProgressHandler?
  ) async throws -> LLMCompletionResult {
    guard callCount < 2 else { throw AIModelBudgetError.exhausted }
    callCount += 1
    var limited = configuration.withMaxOutputTokens(2_000).withRequestTimeout(90)
    if callCount == 2 {
      limited = limited.withFunctions(
        [], inputItems: limited.functionInputItems, choice: .string("none"))
    }
    for item in limited.functionInputItems ?? [] {
      if case .object(let fields) = item, fields["type"] == .string("function_call_output"),
        case .string(let output) = fields["output"],
        output.contains("total_cost_quote") || output.contains("holding_count")
      {
        sawHoldingsOutput = true
      }
    }
    print("Function live QA request=\(callCount) output_cap=\(limited.maxOutputTokens)")
    return try await base.completeJSONResult(
      systemPrompt: systemPrompt, userPrompt: userPrompt,
      configuration: limited, apiKey: apiKey, webSearchEnabled: false,
      reasoningEffort: reasoningEffort, webSearchProgress: webSearchProgress)
  }
}

private struct FunctionLiveCredentials: ProviderCredentialStoring {
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

private final class LiveVerificationRedirectPolicy: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
