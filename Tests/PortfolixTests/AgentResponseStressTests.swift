import Foundation
import Testing
@testable import Portfolix

@Suite("Agent output stress and round-trip contracts")
struct AgentResponseStressTests {
    private func envelope(_ text: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["answer": text, "limitations": []]), as: UTF8.self)
    }

    @Test(arguments: [
        "**先核对日期😀**。\n\n- 保留原始记录。",
        "引号 \"示例\"、{括号} 和路径 C:\\Demo 都是正文。",
        "<u>先核对日期</u>，再看变化。",
        "行内标签 <limitations>[]</limitations> 只是写法示例。",
    ])
    func supportedEnvelopesPreserveTheSameReadableAnswer(answer: String) throws {
        let json = try envelope(answer)
        let tagged = "<answer>\(answer)</answer>\n<limitations>[]</limitations>"
        let variants = [answer, json, "```json\n\(json)\n```", "草稿。\n\(json)", tagged, try envelope(tagged)]
        for raw in variants {
            #expect(try AIAnalysisAgent.validatedFollowUpPayload(raw).answer == answer)
            #expect(AIFollowUpResponseParser.readableText(raw) == answer)
        }
    }

    @Test(arguments: [#"{""#, #"{"a"#, #"{"ans"#, #"{"answer"#, #"{"lim"#, #"{"limitations"#, #"{"\u0061ns"#,
                      #"{"answer"}"#, #"{"limitations"=[]}"#, #"{"Answer":7}"#, #"{"LIMITATIONS":[]}"#])
    func truncatedEnvelopeKeysCannotFallBackToVisibleInternalText(header: String) {
        let raw = "先核对日期。\n\n" + header
        #expect(throws: AIFollowUpResponseError.invalidStructure) { try AIAnalysisAgent.validatedFollowUpPayload(raw) }
        #expect(AIFollowUpResponseParser.readableText(raw) == "先核对日期。")
    }

    @Test
    func oversizedOrDeeplyNestedRepliesFailWithoutPublishingRawStructures() throws {
        var nested = "先核对日期。"
        for _ in 0..<5 { nested = try envelope(nested) }
        let many = Array(repeating: try envelope("先核对日期。"), count: 33).joined(separator: "\n")
        for raw in [String(repeating: "x", count: 128 * 1024 + 1), nested, many] {
            #expect(AIFollowUpResponseParser.decode(raw) == nil)
            #expect(AIFollowUpResponseParser.readableText(raw) == nil)
            #expect(!AIFollowUpResponseParser.displayText(raw).contains("\"answer\""))
        }
    }

    @Test(arguments: ["tool_results", "web_search", "JSON", "status = insufficient_history"])
    func textCleanupAndCitationMappingAreIdempotent(term: String) {
        let body = "\(term) 提示先核对日期😀。"
        let raw = "\n" + body + "\n" + AIAdviceDisclosure.text
        let citation = AIMessageCitation(utf16Offset: 1 + body.utf16.count, title: "Source", url: "https://example.com/source")
        let once = AIUserFacingTextSanitizer.sanitize(raw, citations: [citation], language: .simplifiedChinese)
        let twice = AIUserFacingTextSanitizer.sanitize(once.text, citations: once.citations, language: .simplifiedChinese)
        #expect(twice.text == once.text)
        #expect(twice.citations == once.citations)
        #expect(once.citations.count == 1)
        #expect(once.citations.first?.utf16Offset == once.text.utf16.count)
    }
}
