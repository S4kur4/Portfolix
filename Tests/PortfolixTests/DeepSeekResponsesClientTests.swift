import Foundation
import Testing
@testable import Portfolix

@Suite("DeepSeek Responses client")
struct DeepSeekResponsesClientTests {
    @Test
    func parsesStructuredOutputSearchMetadataAndHTTPSCitations() throws {
        let payload = #"""
        {
          "id":"response_1",
          "output":[
            {
              "type":"web_search_call",
              "id":"search_1",
              "action":{
                "type":"search",
                "queries":[
                  "latest US market news",
                  "official market close data",
                  "ws_call_id=search_1"
                ]
              }
            },
            {
              "type":"message",
              "content":[{
                "type":"output_text",
                "text":"{\"answer\":\"Markets were mixed.\"}",
                "annotations":[
                  {"type":"url_citation","title":"Market update","url":"https://example.com/market"},
                  {"type":"url_citation","title":"Duplicate","url":"https://example.com/market"},
                  {"type":"url_citation","title":"Unsafe","url":"http://example.com/unsafe"}
                ]
              }]
            }
          ]
        }
        """#

        let result = try DeepSeekResponsesClient.parseResponseObject(Data(payload.utf8))

        #expect(result.content == #"{"answer":"Markets were mixed."}"#)
        #expect(result.webSearchCallCount == 1)
        #expect(result.webSearchQueries == ["latest US market news", "official market close data"])
        #expect(result.citations == [
            LLMWebCitation(title: "Market update", url: "https://example.com/market"),
        ])
    }

    @Test
    func rejectsResponsesErrorObjects() {
        let payload = #"{"error":{"message":"invalid request"}}"#

        #expect(throws: LLMClientError.self) {
            try DeepSeekResponsesClient.parseResponseObject(Data(payload.utf8))
        }
    }

    @Test
    func recognizesReasoningDeltaEventsWithoutTreatingFinalOutputAsReasoning() {
        #expect(DeepSeekResponsesClient.isReasoningDeltaEvent("response.reasoning_text.delta"))
        #expect(DeepSeekResponsesClient.isReasoningDeltaEvent("response.reasoning_summary_text.delta"))
        #expect(!DeepSeekResponsesClient.isReasoningDeltaEvent("response.output_text.delta"))
        #expect(!DeepSeekResponsesClient.isReasoningDeltaEvent("response.reasoning_text.done"))
    }

    @Test
    func parsedNonStreamingObjectsUseEmptyTimingDiagnostics() throws {
        let payload = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"status\":\"ok\"}"}]}]}"#

        let result = try DeepSeekResponsesClient.parseResponseObject(Data(payload.utf8))

        #expect(result.diagnostics == .empty)
    }

    @Test
    func parsesUsageAndResponseIdentityDiagnostics() throws {
        let payload = #"""
        {
          "id":"response_usage_1",
          "model":"deepseek-flash",
          "usage":{
            "input_tokens":120,
            "input_tokens_details":{"cached_tokens":24},
            "output_tokens":48,
            "output_tokens_details":{"reasoning_tokens":12}
          },
          "output":[{"type":"message","content":[{"type":"output_text","text":"{\"status\":\"ok\"}"}]}]
        }
        """#

        let result = try DeepSeekResponsesClient.parseResponseObject(Data(payload.utf8))

        #expect(result.diagnostics.inputTokenCount == 120)
        #expect(result.diagnostics.cachedInputTokenCount == 24)
        #expect(result.diagnostics.outputTokenCount == 48)
        #expect(result.diagnostics.reasoningTokenCount == 12)
        #expect(result.diagnostics.responseID == "response_usage_1")
        #expect(result.diagnostics.responseModel == "deepseek-flash")
    }

    @Test
    func requestNeverIncludesRetiredBuiltInSearchParameters() throws {
        let request = try DeepSeekResponsesClient().makeRequest(
            configuration: AIProviderConfiguration.default,
            apiKey: "test-key",
            instructions: "Return JSON.",
            input: "Search first.",
            expectsJSON: true,
            webSearchEnabled: true,
            stream: true
        )
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "deepseek-flash")
        #expect(object["tools"] == nil)
        #expect(object["tool_choice"] == nil)
    }

    @Test
    func validationRequestDisablesReasoning() throws {
        let request = try DeepSeekResponsesClient().makeRequest(
            configuration: AIProviderConfiguration.default,
            apiKey: "test-key",
            instructions: "Reply OK.",
            input: "Hi",
            expectsJSON: false,
            webSearchEnabled: false,
            stream: false,
            reasoningEffort: .none
        )
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let reasoning = try #require(object["reasoning"] as? [String: String])

        #expect(reasoning["effort"] == "none")
        #expect(object["tools"] == nil)
        #expect(object["tool_choice"] == nil)
    }

    @Test
    func requestSupportsTaskSpecificReasoningEffort() throws {
        let request = try DeepSeekResponsesClient().makeRequest(
            configuration: AIProviderConfiguration.default,
            apiKey: "test-key",
            instructions: "Return JSON.",
            input: "Repair this object.",
            expectsJSON: true,
            webSearchEnabled: false,
            stream: true,
            reasoningEffort: .low
        )
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let reasoning = try #require(object["reasoning"] as? [String: String])

        #expect(reasoning["effort"] == "low")
        #expect(object["tools"] == nil)
        #expect(object["tool_choice"] == nil)
    }

    @Test
    func liveConnectionAndJSONUsingEnvironmentCredential() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PORTFOLIX_RUN_LIVE_DEEPSEEK_TEST"] == "1" else { return }
        let apiKey = try #require(environment["PORTFOLIX_DEEPSEEK_API_KEY"])
        let model = environment["PORTFOLIX_DEEPSEEK_MODEL"] ?? LLMProviderOption.deepSeek.defaultModel
        let configuration = AIProviderConfiguration(
            provider: LLMProviderOption.deepSeek.rawValue,
            baseURL: LLMProviderOption.deepSeek.defaultBaseURL,
            model: model,
            isEnabled: true,
            requestTimeout: 120,
            maxOutputTokens: 4_096
        )
        let client = DeepSeekResponsesClient.shared

        _ = try await client.listModels(configuration: configuration, apiKey: apiKey)

        try await client.validateConnection(configuration: configuration, apiKey: apiKey)

        let basic = try await client.completeJSONResult(
            systemPrompt: "Return only a valid JSON object.",
            userPrompt: #"Return {"status":"ok"}."#,
            configuration: configuration.withMaxOutputTokens(512),
            apiKey: apiKey,
            webSearchEnabled: false,
            webSearchProgress: nil
        )
        let basicObject = try #require(
            try JSONSerialization.jsonObject(with: Data(basic.content.utf8)) as? [String: String]
        )
        #expect(basicObject["status"] == "ok")
        #expect(basic.webSearchCallCount == 0)

        #expect(LLMProviderOption.preferredConnectedModel(in: LLMProviderOption.deepSeekModels) == nil)
    }
}
