import CSQLite
import Darwin
import Foundation
import Testing

@testable import Portfolix

@Suite("Opt-in DeepSeek contract integration")
struct AIOptimizationLiveTests {
  @Test
  func reliabilityBudgetSurvivesReloadAndConcurrentReservationsWithoutNetworkCalls() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Portfolix-Budget-Offline-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let url = directory.appendingPathComponent("budget.json")
    let requests = Array(repeating: ["scenario": "offline", "stage": "offline", "outcome": "received"], count: 9)
    try JSONSerialization.data(withJSONObject: ["maximum": 10, "requests": requests, "scenarios": [:]]).write(to: url)
    let first = try ReliabilityLiveBudget(url: url)
    let second = try ReliabilityLiveBudget(url: url)
    let accepted = await withTaskGroup(of: Bool.self) { group in
      for budget in [first, second] {
        group.addTask { (try? await budget.reserve(scenario: "offline_budget_guard", stage: "no_network")) != nil }
      }
      var count = 0
      for await success in group where success { count += 1 }
      return count
    }
    #expect(accepted == 1)
    let reloaded = try ReliabilityLiveBudget(url: url)
    #expect(await reloaded.remaining == 0)
    do {
      _ = try await reloaded.reserve(scenario: "offline_budget_guard", stage: "no_network")
      Issue.record("Reloading cannot reset an exhausted API budget")
    } catch is AIModelBudgetError {}
  }

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

  @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTFOLIX_RUN_REPORT_SCOPE_LIVE"] == "1"))
  func syntheticReportScopeUsesAtMostThreeRequestsWithoutExternalSearch() async throws {
    let key = try readConfiguredKeyWithoutLoadingPortfolio()
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.urlCache = nil
    sessionConfiguration.urlCredentialStorage = nil
    sessionConfiguration.httpShouldSetCookies = false
    let session = URLSession(configuration: sessionConfiguration,
      delegate: LiveVerificationRedirectPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let client = LimitedReportScopeLiveClient(base: DeepSeekResponsesClient(session: session))
    let positions = (1...16).map { index in
      let quantity = Decimal(17 - index)
      return Position(name: "虚构测试资产\(index)", symbol: "SYNTH\(index)", category: .usStock,
        quoteCurrency: .cny, quantity: quantity, averageCost: 10, latestPrice: 12,
        marketValueCNY: quantity * 12, profitRate: 20, weeklyTrend: [], source: "manual",
        quoteTime: "2026-11-07", freshness: .manual)
    }
    let value = positions.reduce(Decimal.zero) { $0 + $1.marketValueCNY }
    let cost = positions.reduce(Decimal.zero) { $0 + $1.totalCost }
    let evaluation = RiskConstraintEvaluation.evaluate(positions: positions, positionLimit: 30,
      cryptoLimit: 15, foreignCurrencyLimit: 50, liquidityMinimum: 10)
    let context = AIAnalysisStoreContext(displayCurrency: .cny, convertedTotalValue: value,
      convertedTotalProfit: value - cost, totalProfitRate: 20, riskProfileConfigured: true,
      riskProfileVersion: 1, riskLevel: "稳健型", positionLimit: 30, cryptoLimit: 15,
      foreignCurrencyLimit: 50, liquidityMinimum: 10, riskConstraintEvaluation: evaluation)
    do {
      let result = try await AIAnalysisAgent(llm: client, search: NoExternalReportScopeSearch(),
        credentialStore: ReportScopeLiveCredentials(key: key)).generateReportResult(
          positions: positions, storeContext: context, llmConfiguration: .default,
          searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.parallel], quality: .basic), trigger: .manual)
      #expect(!result.report.summary.isEmpty)
      #expect(await client.callCount <= 3)
      let planning = result.artifacts.trace?.events.first { $0.stageID == "planning_tool_calls" }
      #expect(planning?.outcome == "passed")
      #expect(result.artifacts.guardrailResultJSON.contains("passed") || result.artifacts.guardrailResultJSON.contains("needs_review"))
      print("Report scope live QA passed requests=\(await client.callCount) external_search_requests=0 repairs=\(result.artifacts.modelUsage?.calls.filter { $0.stage == "report_repair" }.count ?? 0)")
    } catch {
      print("Report scope live QA failed requests=\(await client.callCount) error_type=\(type(of: error))")
      throw error
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTFOLIX_RUN_AGENT_RELIABILITY_LIVE"] == "1"))
  func syntheticReliabilityCampaignWithinTenRequests() async throws {
    let key = try readConfiguredKeyWithoutLoadingPortfolio()
    let budget = try ReliabilityLiveBudget()
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.urlCache = nil
    sessionConfiguration.urlCredentialStorage = nil
    sessionConfiguration.httpShouldSetCookies = false
    sessionConfiguration.timeoutIntervalForResource = 180
    let session = URLSession(configuration: sessionConfiguration, delegate: LiveVerificationRedirectPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let base = DeepSeekResponsesClient(session: session)
    let credentials = ReportScopeLiveCredentials(key: key)
    let positions = (1...16).map { index in
      let units = Decimal(17 - index)
      return Position(name: "虚构测试资产\(index)", symbol: "SYNTH\(index)", category: .usStock,
        quoteCurrency: .cny, quantity: units, averageCost: 10, latestPrice: 12,
        marketValueCNY: units * 12, profitRate: 20, weeklyTrend: [], source: "synthetic",
        quoteTime: "2026-11-08", freshness: .manual)
    }
    let value = positions.reduce(Decimal.zero) { $0 + $1.marketValueCNY }
    let cost = positions.reduce(Decimal.zero) { $0 + $1.totalCost }
    let context = AIAnalysisStoreContext(displayCurrency: .cny, convertedTotalValue: value,
      convertedTotalProfit: value - cost, totalProfitRate: 20, riskProfileConfigured: true,
      riskProfileVersion: 1, riskLevel: "稳健型", positionLimit: 30, cryptoLimit: 15,
      foreignCurrencyLimit: 50, liquidityMinimum: 10,
      riskConstraintEvaluation: .evaluate(positions: positions, positionLimit: 30,
        cryptoLimit: 15, foreignCurrencyLimit: 50, liquidityMinimum: 10))
    var report: AIAnalysisReport?
    var passed = 0
    let scenarios = ["report", "local_tools", "citations", "english", "classification", "repair", "history"]
    for scenario in scenarios {
      if await budget.completedScenarios.contains(scenario) { passed += 1; continue }
      let minimum = ["local_tools", "citations"].contains(scenario) ? 2 : 1
      guard await budget.remaining >= minimum else {
        try await budget.recordScenario(scenario, outcome: "skipped_budget")
        continue
      }
      let client = ReliabilityLiveClient(base: base, budget: budget, scenario: scenario)
      do {
        switch scenario {
        case "report":
          let result = try await AIAnalysisAgent(llm: client, credentialStore: credentials)
            .generateReportResult(positions: positions, storeContext: context, llmConfiguration: .default,
              searchConfiguration: .default, trigger: .manual)
          try #require(!result.report.summary.isEmpty)
          try #require(!AIFollowUpResponseParser.containsResponseEnvelope(result.report.summary))
          try #require(result.artifacts.modelUsage?.unknownUsageCallCount == 0)
          report = result.report
        case "local_tools":
          let result = try await AIAnalysisAgent(llm: client, credentialStore: credentials).answerFollowUp(
            question: "请读取持仓明细，核对 SYNTH1 和 SYNTH16 的份额、总成本和当前市值，用两三句话说明。这些都是虚构测试资产。",
            report: report, artifacts: nil, positions: positions, llmConfiguration: .default, searchConfiguration: .default)
          try #require(result.localToolCallCount > 0)
          try #require(!result.answer.isEmpty)
          try #require(!AIFollowUpResponseParser.containsResponseEnvelope(result.answer))
          try #require(result.modelUsage?.unknownUsageCallCount == 0)
        case "citations":
          let search = SyntheticReliabilitySearch()
          let result = try await AIAnalysisAgent(llm: client, search: search, credentialStore: credentials).answerFollowUp(
            question: "请检索虚构公司 SYNTH1 的最新公告，简短概括公告内容并标出来源。这是测试，请只分析返回的模拟材料。",
            report: report, artifacts: nil, positions: positions, llmConfiguration: .default,
            searchConfiguration: SearchConfiguration(isEnabled: true, enabledProviders: [.parallel], quality: .basic))
          try #require(await search.calls > 0)
          try #require(!result.citations.isEmpty)
          try #require(result.citations.allSatisfy { $0.url == "https://example.com/synthetic-announcement" && $0.utf16Offset <= result.answer.utf16.count })
          try #require(!AIFollowUpResponseParser.containsResponseEnvelope(result.answer))
        case "english":
          let result = try await AIAnalysisAgent(llm: client, credentialStore: credentials).answerFollowUp(
            question: "Explain compound interest in two short English sentences. Do not use portfolio or market data.",
            report: nil, artifacts: nil, positions: [], llmConfiguration: .default, searchConfiguration: .default)
          try #require(AIResponseLanguage.english.matchesUserFacingText(result.answer))
          try #require(!AIFollowUpResponseParser.containsResponseEnvelope(result.answer))
          try #require(result.localToolCallCount == 0)
        case "classification":
          let funds = [("华安黄金ETF", "518880"), ("华夏国证半导体芯片ETF", "159995"), ("虚构灵活配置混合", "SYNTHFUND")].map { name, symbol in
            Position(name: name, symbol: symbol, category: .fund, quoteCurrency: .cny, quantity: 1,
              averageCost: 1, latestPrice: 1, marketValueCNY: 1, profitRate: 0, weeklyTrend: [],
              source: "synthetic", quoteTime: "2026-11-08", freshness: .manual)
          }
          let result = try await AIAnalysisAgent(llm: client, credentialStore: credentials).generateInvestmentDistribution(
            positions: funds, llmConfiguration: .default, searchConfiguration: .default, requestFingerprint: "reliability-synthetic")
          let byRef = Dictionary(uniqueKeysWithValues: result.assets.map { ($0.positionRef, $0) })
          try #require(byRef[InvestmentProfileEngine.positionRef(for: funds[0])]?.allocations.first?.domain.id == "gold")
          try #require(byRef[InvestmentProfileEngine.positionRef(for: funds[1])]?.allocations.first?.domain.id == "cn_semiconductors")
          try #require(byRef[InvestmentProfileEngine.positionRef(for: funds[2])]?.allocations.isEmpty == true)
        case "history":
          let old = "先核对每条记录的实际日期，保留原始凭证。\n<limitations>[\"SYNTHETIC_METADATA_NOTE_73491\"]</limitations>"
          let result = try await AIAnalysisAgent(llm: client, credentialStore: credentials).answerFollowUp(
            question: "我正在学习如何记账。请用两句中文解释你刚才提到的核对日期和保留记录，无需查询行情或账户。",
            report: nil, artifacts: nil, chatHistory: [.assistant(old)], positions: [],
            llmConfiguration: .default, searchConfiguration: .default)
          try #require(!result.answer.isEmpty)
          try #require(AIResponseLanguage.simplifiedChinese.matchesUserFacingText(result.answer))
          try #require(!AIFollowUpResponseParser.containsResponseEnvelope(result.answer))
          try #require(result.localToolCallCount == 0)
        default:
          let injected = InjectedMalformedReliabilityReply(base: client)
          let result = try await AIAnalysisAgent(llm: injected, credentialStore: credentials).answerFollowUp(
            question: "请简短说明为什么需要核对报价日期。", report: nil, artifacts: nil, positions: [],
            llmConfiguration: .default, searchConfiguration: .default)
          try #require(result.guardrailResultJSON.contains("follow_up_response_repaired"))
          try #require(!result.answer.isEmpty)
          try #require(!AIFollowUpResponseParser.containsResponseEnvelope(result.answer))
        }
        passed += 1
        try await budget.recordScenario(scenario, outcome: "completed")
      } catch {
        try await budget.recordScenario(scenario, outcome: "failed_\(type(of: error))")
        if let pipeline = error as? AIAnalysisPipelineError {
          try await budget.recordFailure(scenario, detail: pipeline.underlyingDescription)
        } else { try await budget.recordFailure(scenario, detail: error.localizedDescription) }
        Issue.record("Synthetic live scenario failed: \(scenario), error type: \(type(of: error))")
      }
    }
    try #require(passed >= 4)
    try #require(await budget.remaining >= 0)
    FileHandle.standardOutput.write(Data("Reliability live campaign finished completed=\(passed) requests=\(10 - (await budget.remaining))/10 external_search_requests=0\n".utf8))
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

private actor ReliabilityLiveBudget {
  private let url: URL
  private struct Ledger: Codable {
    let maximum: Int
    var requests: [Request]
    var scenarios: [String: String]
    var failureDetails: [String: String]?
  }
  private struct Request: Codable {
    let scenario: String
    let stage: String
    var outcome: String
    var inputTokens: Int?
    var outputTokens: Int?
  }
  init(url suppliedURL: URL? = nil) throws {
    guard let path = suppliedURL?.path ?? ProcessInfo.processInfo.environment["PORTFOLIX_RELIABILITY_LIVE_BUDGET_FILE"] else { throw AIModelBudgetError.exhausted }
    let candidate = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
    guard candidate.path.hasPrefix(temporary + "/") else { throw AIModelBudgetError.exhausted }
    url = candidate
    let ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: candidate))
    guard ledger.maximum == 10, ledger.requests.count <= 10 else { throw AIModelBudgetError.exhausted }
  }
  private func read() throws -> Ledger { try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: url)) }
  private func write(_ ledger: Ledger) throws {
    try JSONEncoder().encode(ledger).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  private func withLock<T>(_ operation: () throws -> T) throws -> T {
    let descriptor = open(url.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw AIModelBudgetError.exhausted }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw AIModelBudgetError.exhausted }
    defer { _ = flock(descriptor, LOCK_UN) }
    return try operation()
  }
  var remaining: Int { get async { (try? 10 - read().requests.count) ?? 0 } }
  var completedScenarios: Set<String> { get async { Set((try? read().scenarios.filter { $0.value == "completed" }.map(\.key)) ?? []) } }
  func reserve(scenario: String, stage: String) throws -> Int {
    try withLock {
      var ledger = try read()
      guard ledger.requests.count < 10 else { throw AIModelBudgetError.exhausted }
      ledger.requests.append(Request(scenario: scenario, stage: stage, outcome: "reserved"))
      try write(ledger)
      FileHandle.standardOutput.write(Data("Reliability live request=\(ledger.requests.count)/10 scenario=\(scenario) stage=\(stage)\n".utf8))
      return ledger.requests.count
    }
  }
  func finish(_ ordinal: Int, result: LLMCompletionResult?) throws {
    try withLock {
      var ledger = try read()
      ledger.requests[ordinal - 1].outcome = result == nil ? "failed" : "received"
      ledger.requests[ordinal - 1].inputTokens = result?.diagnostics.inputTokenCount
      ledger.requests[ordinal - 1].outputTokens = result?.diagnostics.outputTokenCount
      try write(ledger)
      if let result {
        let safe = (try? AIInformationSecurityGuardrail.validateGeneratedText(result.content)) != nil
          ? result.content : #"{"status":"redacted_unsafe_response"}"#
        let response = url.deletingLastPathComponent().appendingPathComponent("response-\(ordinal).json")
        try Data(safe.utf8).write(to: response, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: response.path)
      }
    }
  }
  func recordScenario(_ scenario: String, outcome: String) throws {
    try withLock {
      var ledger = try read()
      ledger.scenarios[scenario] = outcome
      try write(ledger)
      FileHandle.standardOutput.write(Data("Reliability live scenario=\(scenario) outcome=\(outcome)\n".utf8))
    }
  }
  func recordFailure(_ scenario: String, detail: String) throws {
    try withLock {
      var ledger = try read()
      let safe = (try? AIInformationSecurityGuardrail.validateGeneratedText(detail)) != nil
        ? String(detail.prefix(500)) : "redacted_unsafe_error"
      ledger.failureDetails = (ledger.failureDetails ?? [:]).merging([scenario: safe]) { _, new in new }
      try write(ledger)
      FileHandle.standardOutput.write(Data("Reliability live failure scenario=\(scenario) detail=\(safe)\n".utf8))
    }
  }
}

private actor ReliabilityLiveClient: LLMCompleting {
  let base: DeepSeekResponsesClient
  let budget: ReliabilityLiveBudget
  let scenario: String
  init(base: DeepSeekResponsesClient, budget: ReliabilityLiveBudget, scenario: String) {
    self.base = base; self.budget = budget; self.scenario = scenario
  }
  func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String {
    try await completeJSONResult(systemPrompt: systemPrompt, userPrompt: userPrompt, configuration: configuration,
      apiKey: apiKey, webSearchEnabled: false, reasoningEffort: .low, webSearchProgress: nil).content
  }
  func completeJSONResult(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration,
    apiKey: String, webSearchEnabled: Bool, reasoningEffort: DeepSeekReasoningEffort,
    webSearchProgress: LLMWebSearchProgressHandler?) async throws -> LLMCompletionResult {
    guard !webSearchEnabled, configuration.baseURL == AIProviderConfiguration.default.baseURL,
      configuration.providerOption == .deepSeek else { throw LLMClientError.invalidBaseURL }
    guard !userPrompt.contains("SYNTHETIC_METADATA_NOTE_73491") else { throw LLMClientError.invalidResponse }
    let ordinal = try await budget.reserve(scenario: scenario, stage: configuration.requestStage)
    do {
      let result = try await base.completeJSONResult(systemPrompt: systemPrompt, userPrompt: userPrompt,
        configuration: configuration,
        apiKey: apiKey, webSearchEnabled: false, reasoningEffort: reasoningEffort, webSearchProgress: webSearchProgress)
      try await budget.finish(ordinal, result: result)
      return result
    } catch {
      try await budget.finish(ordinal, result: nil)
      throw error
    }
  }
}

private actor SyntheticReliabilitySearch: WebSearching {
  private(set) var calls = 0
  func search(query: String, positions: [Position], configuration: SearchConfiguration, apiKey: String) async throws -> [AssetResearchSource] {
    calls += 1
    return [AssetResearchSource(title: "虚构公司 SYNTH1 模拟公告", url: "https://example.com/synthetic-announcement",
      domain: "example.com", publishedDate: "2026-11-08",
      snippet: "仅用于测试：虚构公司 SYNTH1 在模拟公告中将一项虚构项目的验收时间从一季度调整至二季度。这不是现实市场信息。", credibility: .general)]
  }
}

private actor InjectedMalformedReliabilityReply: LLMCompleting {
  let base: ReliabilityLiveClient
  private var injected = false
  init(base: ReliabilityLiveClient) { self.base = base }
  func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String {
    if !injected { injected = true; return "先核对报价日期。\n<limitations>[\"未完成" }
    return try await base.completeJSON(systemPrompt: systemPrompt, userPrompt: userPrompt, configuration: configuration, apiKey: apiKey)
  }
}

private actor LimitedReportScopeLiveClient: LLMCompleting {
  let base: DeepSeekResponsesClient
  private(set) var callCount = 0
  private let responseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Portfolix-ReportScope-Live-\(UUID())")
  init(base: DeepSeekResponsesClient) { self.base = base }
  func completeJSON(systemPrompt: String, userPrompt: String,
    configuration: AIProviderConfiguration, apiKey: String) async throws -> String {
    try await completeJSONResult(systemPrompt: systemPrompt, userPrompt: userPrompt,
      configuration: configuration, apiKey: apiKey, webSearchEnabled: false,
      reasoningEffort: .low, webSearchProgress: nil).content
  }
  func completeJSONResult(systemPrompt: String, userPrompt: String,
    configuration: AIProviderConfiguration, apiKey: String, webSearchEnabled: Bool,
    reasoningEffort: DeepSeekReasoningEffort,
    webSearchProgress: LLMWebSearchProgressHandler?) async throws -> LLMCompletionResult {
    guard callCount < 3 else { throw AIModelBudgetError.exhausted }
    guard let path = ProcessInfo.processInfo.environment["PORTFOLIX_REPORT_SCOPE_LIVE_BUDGET_FILE"],
      URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"),
      let reserved = Int(try String(contentsOfFile: path, encoding: .utf8)), reserved < 3
    else { throw AIModelBudgetError.exhausted }
    try String(reserved + 1).write(toFile: path, atomically: true, encoding: .utf8)
    callCount += 1
    print("Report scope live QA request=\(callCount) model=\(configuration.model)")
    let result = try await base.completeJSONResult(systemPrompt: systemPrompt, userPrompt: userPrompt,
      configuration: configuration.withRequestTimeout(120), apiKey: apiKey,
      webSearchEnabled: false, reasoningEffort: reasoningEffort, webSearchProgress: webSearchProgress)
    try FileManager.default.createDirectory(at: responseDirectory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let response = responseDirectory.appendingPathComponent("response-\(reserved + 1).json")
    try result.content.write(to: response, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: response.path)
    print("Report scope live QA response_file=\(response.path)")
    return result
  }
}

private struct NoExternalReportScopeSearch: WebSearching {
  func search(query: String, positions: [Position], configuration: SearchConfiguration,
    apiKey: String) async throws -> [AssetResearchSource] { [] }
}

private struct ReportScopeLiveCredentials: ProviderCredentialStoring {
  let key: String
  func read(kind: ProviderCredentialKind) throws -> String? { kind == .llm ? key : "synthetic-no-network" }
  func save(_: String, kind _: ProviderCredentialKind) throws {}
  func delete(kind _: ProviderCredentialKind) throws {}
  func readValidationState(kind _: ProviderCredentialKind) throws -> ProviderCredentialValidationState { .valid }
  func saveValidationState(_: ProviderCredentialValidationState, kind _: ProviderCredentialKind) throws {}
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
