import Foundation

struct AIModelCallUsage: Codable, Equatable, Sendable {
  let stage: String
  let model: String
  let reasoningEffort: String
  let outcome: String
  let estimatedInputTokens: Int
  let outputTokenLimit: Int
  let inputTokens: Int?
  let cachedInputTokens: Int?
  let outputTokens: Int?
  let reasoningTokens: Int?
  var durationMilliseconds: Int? = nil
}

struct AIModelUsageSummary: Codable, Equatable, Sendable {
  var recordedAt: Date = .now
  let kind: String
  let calls: [AIModelCallUsage]
  var searchUsage: AISearchUsageSummary? = nil

  var knownInputTokens: Int { calls.compactMap(\.inputTokens).reduce(0, +) }
  var knownOutputTokens: Int { calls.compactMap(\.outputTokens).reduce(0, +) }
  var knownCachedInputTokens: Int { calls.compactMap(\.cachedInputTokens).reduce(0, +) }
  var knownReasoningTokens: Int { calls.compactMap(\.reasoningTokens).reduce(0, +) }
  var unknownUsageCallCount: Int {
    calls.filter { $0.inputTokens == nil || $0.outputTokens == nil }.count
  }
  // Reasoning is already part of output; cache hits are already part of input.
  var knownTotalTokens: Int { knownInputTokens + knownOutputTokens }

  static func displayText(for usage: Self?, language: AppLanguage) -> String {
    guard let usage else {
      return localizedText(
        "本次回答的 Token 用量未记录", "Token usage for this response was not recorded", language: language)
    }
    let hasKnownUsage = usage.calls.contains { $0.inputTokens != nil || $0.outputTokens != nil }
    if usage.unknownUsageCallCount > 0 && !hasKnownUsage {
      return localizedText(
        "服务未返回本次回答的 Token 用量", "Token usage for this response is unavailable", language: language)
    }
    let count = usage.knownTotalTokens.formatted(.number.locale(Locale(identifier: "en_US")))
    if usage.unknownUsageCallCount > 0 {
      return localizedText(
        "本次回答至少消耗 \(count) tokens", "This response used at least \(count) tokens",
        language: language)
    }
    return localizedText(
      "本次回答消耗 \(count) tokens", "This response used \(count) tokens", language: language)
  }
}

enum AIModelBudgetError: LocalizedError {
  case exhausted
  var errorDescription: String? { "本次分析已达到请求或上下文预算，请缩小问题范围后重试。" }
}

struct AIModelRunFailure: Error {
  let underlying: Error
  let usage: AIModelUsageSummary
}

actor AIModelUsageLedger {
  let kind: String
  private let maximumCalls: Int
  private let maximumRequestedTokens: Int
  private let deadline: ContinuousClock.Instant
  private var requestedTokens = 0
  private var callCount = 0
  private var calls: [AIModelCallUsage] = []
  private var searchRequestCount = 0
  private var sourceURLs = Set<String>()

  init(
    kind: String, maximumCalls: Int, maximumRequestedTokens: Int = 120_000, seconds: Double = 420
  ) {
    self.kind = kind
    self.maximumCalls = maximumCalls
    self.maximumRequestedTokens = maximumRequestedTokens
    deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
  }

  @discardableResult
  func reserve(inputTokens: Int, outputTokens: Int) throws -> TimeInterval {
    try Task.checkCancellation()
    guard ContinuousClock.now < deadline,
      callCount < maximumCalls,
      inputTokens <= 24_000,
      requestedTokens + inputTokens + outputTokens <= maximumRequestedTokens
    else {
      throw AIModelBudgetError.exhausted
    }
    callCount += 1
    requestedTokens += inputTokens + outputTokens
    let remaining = ContinuousClock.now.duration(to: deadline).components
    return max(0.001, Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)
  }

  func record(_ call: AIModelCallUsage) { calls.append(call) }
  func reserveSearchRequest() throws {
    try Task.checkCancellation()
    guard searchRequestCount < 6 else { throw AIModelBudgetError.exhausted }
    searchRequestCount += 1
  }
  func recordSearchSources(_ sources: [AssetResearchSource]) {
    sourceURLs.formUnion(sources.compactMap {
      guard (try? LLMBaseURLValidator.validatedComponents(from: $0.url)) != nil else { return nil }
      return AISearchSourceIdentity.key($0.url)
    })
  }
  func snapshot() -> AIModelUsageSummary {
    AIModelUsageSummary(kind: kind, calls: calls,
        searchUsage: AISearchUsageSummary(requestCount: searchRequestCount, resultCount: sourceURLs.count))
  }
}

enum AIModelRun {
  @TaskLocal static var ledger: AIModelUsageLedger?

  static func tracked<Value>(kind: String, maximumCalls: Int, operation: () async throws -> Value)
    async throws -> (Value, AIModelUsageSummary)
  {
    let ledger = AIModelUsageLedger(
      kind: kind, maximumCalls: maximumCalls, seconds: kind == "follow_up" ? 180 : 420)
    do {
      let value = try await $ledger.withValue(ledger, operation: operation)
      return (value, await ledger.snapshot())
    } catch {
      let usage = await ledger.snapshot()
      guard !usage.calls.isEmpty else { throw error }
      throw AIModelRunFailure(underlying: error, usage: usage)
    }
  }
}

struct AIUsageTrackingLLM: LLMCompleting {
  let base: LLMCompleting

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
    apiKey: String, webSearchEnabled: Bool, webSearchProgress: LLMWebSearchProgressHandler?
  ) async throws -> LLMCompletionResult {
    try await completeJSONResult(
      systemPrompt: systemPrompt, userPrompt: userPrompt, configuration: configuration,
      apiKey: apiKey, webSearchEnabled: webSearchEnabled, reasoningEffort: .low,
      webSearchProgress: webSearchProgress
    )
  }

  func completeJSONResult(
    systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration,
    apiKey: String, webSearchEnabled: Bool, reasoningEffort: DeepSeekReasoningEffort,
    webSearchProgress: LLMWebSearchProgressHandler?
  ) async throws -> LLMCompletionResult {
    try Task.checkCancellation()
    let schemaText =
      configuration.responseSchema.flatMap { try? JSONEncoder().encode($0.schema) }
      .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    let inputText =
      configuration.functionInputItems.flatMap { try? JSONEncoder().encode($0) }
      .map { String(decoding: $0, as: UTF8.self) } ?? userPrompt
    let toolsText =
      (try? JSONEncoder().encode(configuration.functionTools))
      .map { String(decoding: $0, as: UTF8.self) } ?? ""
    let estimated = AIFollowUpContextOrchestrator.estimatedTokenCount(
      systemPrompt + inputText + schemaText + toolsText)
    let ledger = AIModelRun.ledger
    let remainingSeconds = try await ledger?.reserve(
      inputTokens: estimated, outputTokens: configuration.maxOutputTokens)
    var recorded = false
    let startedAt = ContinuousClock.now
    do {
      let result = try await withThrowingTaskGroup(of: LLMCompletionResult.self) { group in
        group.addTask {
          try await base.completeJSONResult(
            systemPrompt: systemPrompt, userPrompt: userPrompt, configuration: configuration,
            apiKey: apiKey, webSearchEnabled: webSearchEnabled, reasoningEffort: reasoningEffort,
            webSearchProgress: webSearchProgress
          )
        }
        if let remainingSeconds {
          group.addTask {
            try await Task.sleep(for: .seconds(remainingSeconds))
            throw AIModelBudgetError.exhausted
          }
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw CancellationError() }
        return result
      }
      await record(result.diagnostics, outcome: "completed")
      recorded = true
      try Task.checkCancellation()
      return result
    } catch {
      if !recorded {
        await record(
          .empty, outcome: Task.isCancelled || error is CancellationError ? "cancelled" : "failed")
      }
      throw error
    }

    func record(_ usage: LLMCompletionDiagnostics, outcome: String) async {
      var call = AIModelCallUsage(
        stage: configuration.requestStage, model: usage.responseModel ?? configuration.model,
        reasoningEffort: reasoningEffort.rawValue, outcome: outcome,
        estimatedInputTokens: estimated, outputTokenLimit: configuration.maxOutputTokens,
        inputTokens: usage.inputTokenCount, cachedInputTokens: usage.cachedInputTokenCount,
        outputTokens: usage.outputTokenCount, reasoningTokens: usage.reasoningTokenCount
      )
      let elapsed = startedAt.duration(to: .now).components
      call.durationMilliseconds = Int(
        elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
      await ledger?.record(call)
    }
  }
}
