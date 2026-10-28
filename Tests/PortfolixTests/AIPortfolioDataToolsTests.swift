import Foundation
import Testing

@testable import Portfolix

@Suite("Read-only portfolio function calling")
struct AIPortfolioDataToolsTests {
  @Test
  func acknowledgementsUseOnlyTheImmediatelyRelevantConversation() {
    let history = [AIReportChatItem.assistant("需要的话，我可以结合你的持仓看看当前回撤和仓位该不该调整。")]
    #expect(AIContextProjection.needsPortfolio("好的，你帮我看看", positions: [], chatHistory: history))
    #expect(AIContextProjection.needsPortfolio("可以", positions: [], chatHistory: history))
    #expect(!AIContextProjection.needsPortfolio("今天黄金价格是多少？", positions: [], chatHistory: history))
    #expect(!AIContextProjection.needsPortfolio("谢谢", positions: [], chatHistory: history))
    #expect(
      !AIContextProjection.needsPortfolio(
        "好的，你帮我看看", positions: [], chatHistory: [.assistant("我可以解释通货膨胀的含义。")]))
    #expect(
      AIContextProjection.needsPortfolio(
        "Go ahead", positions: [],
        chatHistory: [.assistant("I can review your holdings and costs.")]))
  }

  @Test
  func realTransportPairsCallsWithResultsAndKeepsReasoningOutOfStoredMetadata() async throws {
    let (client, key) = transport([
      functionOutput([("call_1", "list_holdings", "{}")]),
      answerOutput("已核对你当前记录的持仓和成本。"),
    ])
    let holding = position()
    let result = try await AIAnalysisAgent(
      llm: client, credentialStore: FunctionCredentials(key: key)
    ).answerFollowUp(
      question: "好的，你帮我看看", report: nil, artifacts: nil,
      chatHistory: [.assistant("我可以结合你的持仓看看。")], positions: [holding],
      llmConfiguration: .default, searchConfiguration: .default)
    #expect(result.localToolCallCount == 1)
    #expect(result.modelUsage?.calls.count == 2)
    #expect(result.modelUsage?.knownTotalTokens == 240)
    let requests = try FunctionProtocol.state.requests(key).map {
      try JSONSerialization.jsonObject(with: $0) as! [String: Any]
    }
    #expect(requests.count == 2)
    let tools = try #require(requests[0]["tools"] as? [[String: Any]])
    #expect(
      Set(tools.compactMap { $0["name"] as? String })
        == Set(AIPortfolioDataTool.allCases.map(\.rawValue)))
    #expect(!tools.contains { ($0["name"] as? String ?? "").contains("delete") })
    let items = try #require(requests[1]["input"] as? [[String: Any]])
    #expect(
      items.compactMap { $0["type"] as? String } == [
        "reasoning", "function_call", "function_call_output",
      ])
    let output = try #require(items.first { $0["type"] as? String == "function_call_output" })
    #expect(output["call_id"] as? String == "call_1")
    let payload = try object(output["output"] as? String ?? "")
    let rows = try #require(payload["data"] as? [[String: Any]])
    #expect(rows.first?["quantity"] as? String == "10")
    #expect(rows.first?["total_cost_quote"] as? String == "100")
    #expect(payload["read_only"] as? Bool == true)
    let saved = String(
      decoding: try JSONEncoder().encode(
        AIReportChatItem.assistant(
          result.answer,
          followUpRunSnapshot: .init(result: result))), as: UTF8.self)
    #expect(!saved.contains("PRIVATE_TRANSIENT_REASONING"))
    #expect(!saved.contains(key))
  }

  @Test
  func parallelToolCallsEachReceiveExactlyOneMatchingOutput() async throws {
    let (client, key) = transport([
      functionOutput([
        ("summary", "get_portfolio_summary", "{}"), ("holdings", "list_holdings", #"{"limit":1}"#),
      ]),
      answerOutput("已核对组合概况和持仓。"),
    ])
    let result = try await AIAnalysisAgent(
      llm: client, credentialStore: FunctionCredentials(key: key)
    )
    .answerFollowUp(
      question: "检查我的持仓", report: nil, artifacts: nil, positions: [position()],
      llmConfiguration: .default, searchConfiguration: .default)
    #expect(result.localToolCallCount == 2)
    let request = try #require(FunctionProtocol.state.requests(key).last)
    let body = try #require(try JSONSerialization.jsonObject(with: request) as? [String: Any])
    let items = try #require(body["input"] as? [[String: Any]])
    #expect(
      Set(
        items.filter { $0["type"] as? String == "function_call_output" }.compactMap {
          $0["call_id"] as? String
        }) == ["summary", "holdings"])
  }

  @Test(arguments: [
    ("delete_holding", "{}"), ("list_holdings", #"{"sql":"DELETE FROM holdings"}"#),
    ("list_holdings", #"{"limit":1000}"#), ("list_holdings", #"{"offset":true}"#),
  ])
  func undeclaredToolsAndInvalidArgumentsNeverReachTheHost(_ name: String, _ arguments: String)
    async throws
  {
    let (client, key) = transport([
      functionOutput([("bad", name, arguments)]), answerOutput("本次读取失败。"),
    ])
    let counter = FunctionCounter()
    _ = try await AIAnalysisAgent(llm: client, credentialStore: FunctionCredentials(key: key))
      .answerFollowUp(
        question: "查看持仓", report: nil, artifacts: nil, positions: [position()],
        localToolHandler: { _ in
          await counter.increment()
          return "{}"
        },
        llmConfiguration: .default, searchConfiguration: .default)
    #expect(await counter.count == 0)
    let request = try #require(FunctionProtocol.state.requests(key).last)
    #expect(String(decoding: request, as: UTF8.self).contains("invalid_arguments_or_tool"))
  }

  @Test
  func toolLoopStopsAndDisablesToolsBeforeTheFinalBudgetedRequest() async throws {
    let (client, key) = transport([
      functionOutput([("one", "get_portfolio_summary", "{}")]),
      functionOutput([("two", "list_holdings", "{}")]),
      functionOutput([("three", "list_holdings", "{}")]),
    ])
    let counter = FunctionCounter()
    await #expect(throws: AIModelRunFailure.self) {
      try await AIAnalysisAgent(llm: client, credentialStore: FunctionCredentials(key: key))
        .answerFollowUp(
          question: "查看持仓", report: nil, artifacts: nil, positions: [position()],
          localToolHandler: { _ in
            await counter.increment()
            return "{}"
          },
          llmConfiguration: .default, searchConfiguration: .default)
    }
    #expect(await counter.count == 2)
    let requests = FunctionProtocol.state.requests(key)
    #expect(requests.count == 3)
    let lastRequest = try #require(requests.last)
    let final = try #require(try JSONSerialization.jsonObject(with: lastRequest) as? [String: Any])
    #expect(final["tools"] == nil)
    #expect(final["tool_choice"] as? String == "none")
  }

  @Test
  func holdingsArePaginatedAndUseRecordedTotalCostRatherThanRoundedAverageCost() throws {
    let positions = (0..<40).map {
      position(name: "Synthetic \($0)", symbol: "TEST\($0)", value: Decimal(100 + $0))
    }
    let snapshot = AIPortfolioToolSnapshot(positions: positions)
    let first = try object(
      AIPortfolioDataToolExecutor.execute(
        request("list_holdings", #"{"limit":25}"#), snapshot: snapshot))
    #expect((first["data"] as? [[String: Any]])?.count == 25)
    #expect(first["next_offset"] as? Int == 25)
    #expect(first["omitted_count"] as? Int == 15)
    let last = try object(
      AIPortfolioDataToolExecutor.execute(
        request("list_holdings", #"{"offset":25,"limit":25}"#), snapshot: snapshot))
    #expect((last["data"] as? [[String: Any]])?.count == 15)
    #expect(last["omitted_count"] as? Int == 0)
    let customCost = Position(
      name: "Synthetic", symbol: "TEST", category: .usStock, quoteCurrency: .cny,
      quantity: 3, totalCost: 100, averageCost: Decimal(string: "33.33")!, latestPrice: 40,
      marketValueCNY: 120, profitRate: 20, weeklyTrend: [], source: "manual",
      quoteTime: "2026-10-27", freshness: .manual)
    let costs = try object(
      AIPortfolioDataToolExecutor.execute(
        request("list_holdings", "{}"), snapshot: .init(positions: [customCost])))
    #expect((costs["data"] as? [[String: Any]])?.first?["total_cost_quote"] as? String == "100")
  }

  @Test
  func missingReportDoesNotHideHoldingsAndMissingPerformanceIsNotInvented() throws {
    let position = position()
    let snapshot = AIPortfolioToolSnapshot(positions: [position])
    let report = try object(
      AIPortfolioDataToolExecutor.execute(
        request("get_latest_analysis_report", "{}"), snapshot: snapshot))
    #expect(report["code"] as? String == "no_saved_report")
    let summary = try object(
      AIPortfolioDataToolExecutor.execute(
        request("get_portfolio_summary", "{}"), snapshot: snapshot))
    #expect((summary["data"] as? [String: Any])?["holding_count"] as? Int == 1)
    let args = #"{"position_refs":["position_\#(position.id.uuidString)"],"period":"one_month"}"#
    let result = try object(
      AIPortfolioDataToolExecutor.execute(
        request("get_holding_performance", args), snapshot: snapshot))
    let rows = try #require(result["data"] as? [[String: Any]])
    #expect(
      (rows.first?["observation"] as? [String: Any])?["status"] as? String == "insufficient_history"
    )
    #expect(
      result["calculation_basis"] as? String
        == "price_change_times_current_quantity_excludes_trades_fees_fx_not_account_return_or_nav_drawdown"
    )
  }

  @Test
  func historyIsBoundedAndDoesNotPretendValueChangesAreInvestmentReturns() throws {
    let now = Date()
    let old = now.addingTimeInterval(-40 * 86_400)
    let snapshot = AIPortfolioToolSnapshot(
      positions: [],
      history: [
        PortfolioSnapshot(date: old, totalValueCNY: 50, profitRate: 0),
        PortfolioSnapshot(date: now.addingTimeInterval(-86_400), totalValueCNY: 100, profitRate: 0),
        PortfolioSnapshot(date: now.addingTimeInterval(86_400), totalValueCNY: 200, profitRate: 0),
      ], dailyProfit: [.init(date: now, amountCNY: 2)], asOf: now)
    let output = try object(
      AIPortfolioDataToolExecutor.execute(
        request("get_portfolio_history", #"{"days":7}"#), snapshot: snapshot))
    #expect((output["data"] as? [[String: Any]])?.count == 1)
    #expect((output["daily_profit"] as? [[String: Any]])?.count == 1)
    #expect(
      (output["limitation"] as? String ?? "").contains("not time-weighted returns or NAV drawdowns")
    )
    #expect(throws: AIPortfolioToolError.self) {
      try request("get_portfolio_history", #"{"days":10000}"#)
    }
  }

  @Test
  func cancellationDuringALocalReadCannotSendAnotherModelRequest() async throws {
    let (client, key) = transport([
      functionOutput([("read", "list_holdings", "{}")]), answerOutput("不应发出"),
    ])
    let gate = FunctionReadGate()
    let task = Task {
      try await AIAnalysisAgent(llm: client, credentialStore: FunctionCredentials(key: key))
        .answerFollowUp(
          question: "查看持仓", report: nil, artifacts: nil, positions: [position()],
          localToolHandler: { _ in
            await gate.enter()
            try? await Task.sleep(for: .seconds(30))
            return "{}"
          }, llmConfiguration: .default, searchConfiguration: .default)
    }
    await gate.wait()
    task.cancel()
    if case .success = await task.result { Issue.record("Cancelled tool read returned an answer") }
    #expect(FunctionProtocol.state.requests(key).count == 1)
  }

  @Test @MainActor
  func storeProvidesCurrentDataAndPersistsTheToolCountWithoutAnyReportPrerequisite() async throws {
    let (client, key) = transport([
      functionOutput([("current", "list_holdings", "{}")]), answerOutput("已读取当前记录的份额和成本。"),
    ])
    let repository = try PositionRepository(
      databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(
        "Portfolix.Functions.\(UUID())/test.sqlite"))
    let credentials = FunctionCredentials(key: key)
    let store = PortfolioStore(
      positionRepository: repository, credentialStore: credentials,
      aiAgent: AIAnalysisAgent(llm: client, credentialStore: credentials))
    store.aiConfiguration = .default
    store.searchConfiguration = .default
    try store.addPosition(
      name: "Synthetic", symbol: "TEST", category: .usStock, quantity: 7, averageCost: 10,
      quoteCurrency: .cny, latestPrice: 12)
    // Keep automatic domain classification out of this test's scripted tool-response queue.
    store.aiConfiguration.isEnabled = false
    store.aiConfiguration.isEnabled = true
    store.submitAIAnalysisFollowUp("好的，你帮我看看")
    await store.waitForAIAnalysisIdle()
    #expect(store.aiAnalysisReport == nil)
    #expect(store.positions.first?.quantity == 7)
    let item = try #require(store.aiAnalysisChatItems.last)
    #expect(item.followUpRunSnapshot?.localToolCallCount == 1)
    #expect(item.responseModelUsage?.calls.count == 2)
    let saved = try repository.fetchAIAnalysisChatItems(since: .distantPast)
    #expect(saved.first { $0.id == item.id }?.followUpRunSnapshot?.localToolCallCount == 1)
    let last = try #require(FunctionProtocol.state.requests(key).last)
    let body = try #require(try JSONSerialization.jsonObject(with: last) as? [String: Any])
    let items = try #require(body["input"] as? [[String: Any]])
    let output = try #require(
      items.first { $0["type"] as? String == "function_call_output" }?["output"] as? String)
    let rows = try #require(try object(output)["data"] as? [[String: Any]])
    #expect(rows.first?["quantity"] as? String == "7")
  }

  private func position(name: String = "Synthetic", symbol: String = "TEST", value: Decimal = 120)
    -> Position
  {
    Position(
      name: name, symbol: symbol, category: .usStock, quoteCurrency: .cny, quantity: 10,
      averageCost: 10, latestPrice: 12, marketValueCNY: value, profitRate: 20, weeklyTrend: [],
      source: "manual", quoteTime: "2026-10-27", freshness: .manual)
  }
  private func request(_ name: String, _ args: String) throws -> AIPortfolioToolRequest {
    try AIPortfolioToolRequest(call: .init(callID: "test", name: name, arguments: args))
  }
  private func object(_ text: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
  }
  private func functionOutput(_ calls: [(String, String, String)]) -> [[String: Any]] {
    [
      [
        "type": "reasoning",
        "content": [["type": "reasoning_text", "text": "PRIVATE_TRANSIENT_REASONING"]],
      ]
    ]
      + calls.map { ["type": "function_call", "call_id": $0.0, "name": $0.1, "arguments": $0.2] }
  }
  private func answerOutput(_ text: String) -> [[String: Any]] {
    let json = String(
      decoding: try! JSONSerialization.data(withJSONObject: ["answer": text, "limitations": []]),
      as: UTF8.self)
    return [
      ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": json]]]
    ]
  }
  private func transport(_ outputs: [[[String: Any]]]) -> (DeepSeekResponsesClient, String) {
    let key = UUID().uuidString
    FunctionProtocol.state.register(key, outputs: outputs)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FunctionProtocol.self]
    return (DeepSeekResponsesClient(session: URLSession(configuration: config)), key)
  }
}

private actor FunctionCounter {
  var count = 0
  func increment() { count += 1 }
}

private actor FunctionReadGate {
  private var entered = false
  private var waiter: CheckedContinuation<Void, Never>?
  func enter() {
    entered = true
    waiter?.resume()
    waiter = nil
  }
  func wait() async {
    if entered { return }
    await withCheckedContinuation { waiter = $0 }
  }
}

private struct FunctionCredentials: ProviderCredentialStoring {
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

private final class FunctionProtocol: URLProtocol, @unchecked Sendable {
  static let state = State()
  final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [String: [[[String: Any]]]] = [:]
    private var captured: [String: [Data]] = [:]
    func register(_ key: String, outputs: [[[String: Any]]]) {
      lock.withLock { self.outputs[key] = outputs }
    }
    func requests(_ key: String) -> [Data] { lock.withLock { captured[key] ?? [] } }
    func next(_ key: String, request: URLRequest) -> [[String: Any]] {
      lock.withLock {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
          stream.open()
          defer { stream.close() }
          var buffer = [UInt8](repeating: 0, count: 4096)
          while stream.hasBytesAvailable {
            let length = stream.read(&buffer, maxLength: buffer.count)
            if length <= 0 { break }
            data.append(contentsOf: buffer.prefix(length))
          }
        }
        captured[key, default: []].append(data)
        var queue = outputs[key] ?? []
        let value = queue.isEmpty ? [] : queue.removeFirst()
        outputs[key] = queue
        return value
      }
    }
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let key = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst(7))
    let output = Self.state.next(key, request: request)
    let event: [String: Any] = [
      "type": "response.completed",
      "response": [
        "status": "completed", "model": "deepseek-flash", "output": output,
        "usage": ["input_tokens": 100, "output_tokens": 20],
      ],
    ]
    let json = try! JSONSerialization.data(withJSONObject: event)
    let data = Data(
      "event: response.completed\ndata: \(String(decoding: json, as: UTF8.self))\n\n".utf8)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "text/event-stream"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
