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

        let connected = try await client.completeJSONResult(
            systemPrompt: "Use web search. Return only a valid JSON object with answer and searched fields.",
            userPrompt: "Search the official DeepSeek documentation and identify the current production text model IDs. Set searched to true.",
            configuration: configuration,
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
