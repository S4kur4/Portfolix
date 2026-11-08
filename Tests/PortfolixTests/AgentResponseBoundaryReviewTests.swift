import AppKit
import Foundation
import Testing
@testable import Portfolix

@Suite("Agent response boundary review")
struct AgentResponseBoundaryReviewTests {
    @Test(arguments: [
        "<answer>先核对报价日期。</answer>",
        "<answer>先核对报价日期。</answer><limitations>[\"不是实时行情。\"]</limitations>",
        "之前的草稿。\n<answer>先核对报价日期。</answer>\n<limitations>[]</limitations>",
        "先核对报价日期。 <limitations>[\"不是实时行情。\"]</limitations>",
    ])
    func taggedAnswersDoNotPublishInternalWrappers(raw: String) throws {
        #expect(try AIAnalysisAgent.validatedFollowUpPayload(raw).answer == "先核对报价日期。")
        #expect(AIFollowUpResponseParser.displayText(raw) == "先核对报价日期。")
    }

    @Test(arguments: ["<answer>未完成", "先核对日期。 <limitations>[\"未完成", "先核对日期。\n</limitations>"])
    func incompleteTagsRequireRepair(raw: String) {
        #expect(throws: AIFollowUpResponseError.invalidStructure) {
            try AIAnalysisAgent.validatedFollowUpPayload(raw)
        }
        #expect(!AIFollowUpResponseParser.displayText(raw).contains("<"))
    }

    @Test(arguments: [AIAdviceDisclosure.text, "[ ](source_1)"])
    func emptyVisibleAnswersCannotPassValidation(answer: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["answer": answer, "limitations": []])
        #expect(throws: AIFollowUpResponseError.emptyAnswer) {
            try AIAnalysisAgent.validatedFollowUpPayload(String(decoding: data, as: UTF8.self), citationCatalog: [
                AICitationCatalogEntry(id: "source_1", title: "Source", url: "https://example.com/source")])
        }
    }

    @Test(arguments: ["<u></u>", "<u>  </u>", "![](https://example.com/test.png)", "[ ](https://example.com/unknown)"])
    @MainActor
    func invisibleMarkupCannotCreateAnEmptyChatBubble(answer: String) throws {
        let rendered = AIMessageMarkdownRenderer.render(answer, citationColor: .labelColor)
        #expect(rendered.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: ["answer": answer, "limitations": []]), as: UTF8.self)
        #expect(throws: AIFollowUpResponseError.emptyAnswer) { try AIAnalysisAgent.validatedFollowUpPayload(raw) }
    }

    @Test(arguments: ["**建议是**", "<u>具体如下：</u>"])
    func incompleteFormattedAnswersStillRequireRepair(answer: String) throws {
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: ["answer": answer, "limitations": []]), as: UTF8.self)
        #expect(throws: AIFollowUpResponseError.incompleteAnswer) { try AIAnalysisAgent.validatedFollowUpPayload(raw) }
    }

    @Test(arguments: ["<u>先核对日期😀。</u>", "**Keep a cash buffer.**", "`<u></u>`"])
    func meaningfulFormattingAndLiteralMarkupRemainSupported(answer: String) throws {
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: ["answer": answer, "limitations": []]), as: UTF8.self)
        #expect(try AIAnalysisAgent.validatedFollowUpPayload(raw).answer == answer)
    }

    @Test @MainActor
    func historicalCitationsStayOnTheSameSentenceAfterTextCleanup() {
        let prefix = "tool_results 提示核对日期😀。"
        let text = prefix + "后一句保留。"
        let citation = AIMessageCitation(utf16Offset: prefix.utf16.count, title: "Source", url: "https://example.com/source")
        let rendered = AIMessageMarkdownRenderer.render(text, citations: [citation], citationColor: .labelColor)
        #expect(rendered.string == "联网资料 提示核对日期😀。\u{FFFC}后一句保留。")
    }

    @Test @MainActor
    func removingADisclosurePreservesOnlyCitationsAttachedToVisibleClaims() {
        let text = AIAdviceDisclosure.text + "\n\n先核对日期😀。\n"
        let hidden = AIMessageCitation(utf16Offset: AIAdviceDisclosure.text.utf16.count, title: "Hidden", url: "https://example.com/hidden")
        let body = AIMessageCitation(utf16Offset: text.utf16.count - 1, title: "Source", url: "https://example.com/source")
        let rendered = AIMessageMarkdownRenderer.render(text, citations: [hidden, body], citationColor: .labelColor)
        #expect(rendered.string == "先核对日期😀。\u{FFFC}")
    }

    @Test(arguments: [
        [#"data: {"choices":[{"index":0,"delta":{"content":"正文。"},"finish_reason":"stop"}]}"#],
        [#"data: {"choices":[{"delta":{"content":"正文。"}}]}"#, "data: [DONE]"],
        [#"{"choices":[{"index":1,"message":{"content":"草稿。"}},{"index":0,"message":{"content":"正文。"},"finish_reason":"stop"}]}"#],
    ])
    func completedCompatibilityResponsesRemainSupported(lines: [String]) throws {
        #expect(try OpenAICompatibleClient.content(fromResponseLines: lines) == "正文。")
    }

    @Test
    func filteredCompatibilityOutputCannotBePresentedAsACompleteAnswer() {
        #expect(throws: LLMClientError.self) {
            try OpenAICompatibleClient.content(fromResponseLines: [
                #"data: {"choices":[{"delta":{"content":"部分正文。"},"finish_reason":"content_filter"}]}"#,
                "data: [DONE]",
            ])
        }
    }

    @Test
    func interruptedCompatibilityStreamCannotPublishItsPartialContent() {
        #expect(throws: LLMClientError.self) {
            try OpenAICompatibleClient.content(fromResponseLines: [
                #"data: {"choices":[{"delta":{"content":"看起来完整的一句话。"}}]}"#,
            ])
        }
    }

    @Test
    func alternativeCompatibilityChoicesCannotBeJoinedIntoOneAnswer() throws {
        let content = try OpenAICompatibleClient.content(fromResponseLines: [
            #"data: {"choices":[{"index":1,"delta":{"content":"另一份草稿。"}},{"index":0,"delta":{"content":"最终正文。"}}]}"#,
            #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"},{"index":1,"delta":{},"finish_reason":"length"}]}"#,
            "data: [DONE]",
        ])
        #expect(content == "最终正文。")
    }

    @Test
    func unfinishedFinalMessageCannotBeUsedEvenWhenTheResponseSaysCompleted() throws {
        let body: [String: Any] = ["status": "completed", "output": [["type": "message", "role": "assistant",
            "status": "incomplete", "content": [["type": "output_text", "text": "未完成的草稿。"]]]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        #expect(throws: LLMClientError.self) { try DeepSeekResponsesClient.parseResponseObject(data) }
    }

    @Test(arguments: ["incomplete", "failed", "in_progress", "cancelled"])
    func nonFinalResponsesCannotBeUsedAsCompletedAnswers(status: String) throws {
        let body: [String: Any] = ["status": status, "output": [["type": "message", "role": "assistant",
            "content": [["type": "output_text", "text": "未完成的草稿。"]]]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        #expect(throws: LLMClientError.self) { try DeepSeekResponsesClient.parseResponseObject(data) }
    }

    @Test(arguments: ["<answer>先核对日期。</answer>", #"{"answer":"先核对日期。","limitations":[]}"#])
    func reportsRejectResponseEnvelopesInsideUserFacingFields(summary: String) throws {
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: [
            "summary": summary, "health_score_explanation": "请先核对记录。"
        ]), as: UTF8.self)
        #expect(throws: AIReportPayloadValidationError.self) { try AIAnalysisAgent.validatedPayload(raw) }
    }

    @Test
    func reportsCannotPublishARequiredSummaryThatBecomesEmptyAfterCleanup() throws {
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: [
            "summary": AIAdviceDisclosure.text, "health_score_explanation": "请先核对记录。"
        ]), as: UTF8.self)
        #expect(throws: AIReportPayloadValidationError.self) { try AIAnalysisAgent.validatedPayload(raw) }
    }
}
