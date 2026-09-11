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
    func connectedRequestUsesExplicitSearchAndReasoningConfiguration() throws {
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
        let reasoning = try #require(object["reasoning"] as? [String: String])
        let toolChoice = try #require(object["tool_choice"] as? [String: String])
        let tools = try #require(object["tools"] as? [[String: String]])

        #expect(object["model"] as? String == "deepseek-flash")
        #expect(object["temperature"] == nil)
        #expect(reasoning["effort"] == "high")
        #expect(toolChoice["type"] == "web_search")
        #expect(tools == [["type": "web_search"]])
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
    func connectedResponseMustContainEvidenceOfAnActualSearch() throws {
        let noSearch = LLMCompletionResult(content: #"{"answer":"cached knowledge"}"#)

        #expect(throws: LLMClientError.webSearchUnavailable("deepseek-flash")) {
            try DeepSeekResponsesClient.validatedSearchResult(
                noSearch,
                webSearchEnabled: true,
                model: "deepseek-flash"
            )
        }

        let searched = LLMCompletionResult(
            content: #"{"answer":"current"}"#,
            webSearchCallCount: 1
        )
        #expect(try DeepSeekResponsesClient.validatedSearchResult(
            searched,
            webSearchEnabled: true,
            model: "deepseek-v4-pro"
        ) == searched)
    }

    @Test
    func liveConnectionJSONAndBuiltInSearchUsingEnvironmentCredential() async throws {
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

        let liveModels = try await client.listModels(configuration: configuration, apiKey: apiKey)

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

        let connectedModel = try #require(LLMProviderOption.preferredConnectedModel(in: liveModels))
        let connectedConfiguration = AIProviderConfiguration(
            provider: configuration.provider,
            baseURL: configuration.baseURL,
            model: connectedModel,
            isEnabled: configuration.isEnabled,
            requestTimeout: configuration.requestTimeout,
            maxOutputTokens: configuration.maxOutputTokens
        )
        let connected = try await client.completeJSONResult(
            systemPrompt: "Use web search. Return only a valid JSON object with answer and searched fields.",
            userPrompt: "Search the official DeepSeek documentation and identify the current production text model IDs. Set searched to true.",
            configuration: connectedConfiguration,
            apiKey: apiKey,
            webSearchEnabled: true,
            webSearchProgress: nil
        )
        let connectedObject = try #require(
            try JSONSerialization.jsonObject(with: Data(connected.content.utf8)) as? [String: Any]
        )
        #expect(connectedObject["searched"] as? Bool == true)
        #expect(connected.webSearchCallCount > 0)
        #expect(!connected.webSearchQueries.isEmpty)
    }
}
