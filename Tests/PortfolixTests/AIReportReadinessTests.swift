import Testing
@testable import Portfolix

@Suite("Agent activity policy")
struct AIAgentActivityPolicyTests {
    @Test @MainActor
    func composerActionTracksMeaningfulDraftWithoutChangingItsSize() {
        let buffer = AIReportComposerDraftBuffer()
        for (text, expected): (String, AIReportComposerAction) in [
            ("", .analyze), ("  \n ", .analyze), ("继续分析", .send), (" Gold price? ", .send), ("", .analyze),
        ] {
            buffer.replace(with: text)
            let mode = AIReportComposerAction(hasDraftText: buffer.hasContent)
            #expect(mode == expected)
            #expect(mode.symbol == (expected == .send ? "arrow.up" : "sparkles"))
        }
        #expect(AIReportComposerAction.analyze.title(hasReport: false, language: .chinese) == "生成分析")
        #expect(AIReportComposerAction.analyze.title(hasReport: true, language: .chinese) == "重新分析")
        #expect(AIReportComposerAction.send.title(hasReport: true, language: .english) == "Send question")
    }

    @Test
    func composerActionHonorsTheSelectedOperationAndBusyStates() {
        for mode in AIReportComposerAction.allCases {
            #expect(mode.isEnabled(canGenerate: true, canSendFollowUp: true,
                                   isSubmitting: false, isAwaitingResponse: false, isVoiceActive: false))
            for (submitting, awaiting, voice) in [(true, false, false), (false, true, false), (false, false, true)] {
                #expect(!mode.isEnabled(canGenerate: true, canSendFollowUp: true,
                                        isSubmitting: submitting, isAwaitingResponse: awaiting, isVoiceActive: voice))
            }
            #expect(mode.isEnabled(canGenerate: true, canSendFollowUp: false,
                                  isSubmitting: false, isAwaitingResponse: false, isVoiceActive: false) == (mode == .analyze))
            #expect(mode.isEnabled(canGenerate: false, canSendFollowUp: true,
                                  isSubmitting: false, isAwaitingResponse: false, isVoiceActive: false) == (mode == .send))
        }
    }

    @Test
    func keepsOnlyTheLatestDistinctNonemptyLine() {
        var lines: [AIAgentActivityLine] = []
        lines = AIAgentActivityPolicy.appending("  Preparing input  ", to: lines)
        lines = AIAgentActivityPolicy.appending("Preparing input", to: lines)
        lines = AIAgentActivityPolicy.appending("Reasoning", to: lines)
        lines = AIAgentActivityPolicy.appending("Searching", to: lines)
        lines = AIAgentActivityPolicy.appending("Generating output", to: lines)
        lines = AIAgentActivityPolicy.appending("   ", to: lines)

        #expect(lines.map(\.text) == ["Generating output"])
    }

    @Test
    func restoresComposerFocusOnlyAfterAnAgentResponseFinishes() {
        #expect(
            AIReportComposerFocusPolicy.shouldRestoreFocus(
                wasAwaitingResponse: true,
                isAwaitingResponse: false,
                isVoiceActive: false
            )
        )
        #expect(
            !AIReportComposerFocusPolicy.shouldRestoreFocus(
                wasAwaitingResponse: false,
                isAwaitingResponse: false,
                isVoiceActive: false
            )
        )
        #expect(
            !AIReportComposerFocusPolicy.shouldRestoreFocus(
                wasAwaitingResponse: true,
                isAwaitingResponse: false,
                isVoiceActive: true
            )
        )
    }

    @MainActor
    @Test
    func composerDraftBufferNormalizesSubmissionWithoutPublishingEveryCharacter() {
        let buffer = AIReportComposerDraftBuffer()
        buffer.replace(with: "   ")
        #expect(!buffer.hasContent)
        #expect(buffer.submissionText == nil)

        buffer.replace(with: "  继续分析这项持仓  ")
        #expect(buffer.hasContent)
        #expect(buffer.submissionText == "继续分析这项持仓")

        buffer.clear()
        #expect(buffer.text.isEmpty)
        #expect(!buffer.hasContent)
    }
}

struct AIReportReadinessTests {
    @Test
    func missingCredentialTakesPrecedenceOverPersistedValidationState() {
        #expect(
            AIReportReadiness.credential(
                isConfigured: false,
                validationState: .valid
            ) == .missing
        )
    }

    @Test
    func configuredCredentialReflectsEveryValidationState() {
        #expect(
            AIReportReadiness.credential(
                isConfigured: true,
                validationState: .unknown
            ) == .needsValidation
        )
        #expect(
            AIReportReadiness.credential(
                isConfigured: true,
                validationState: .invalid
            ) == .invalid
        )
        #expect(
            AIReportReadiness.credential(
                isConfigured: true,
                validationState: .valid
            ) == .ready
        )
    }

    @Test
    func readinessMessagesDescribeTheActualCredentialState() {
        #expect(
            AIReportReadiness.missing.apiStatusText(
                name: "DeepSeek API",
                language: .chinese
            ) == "DeepSeek API 未配置"
        )
        #expect(
            AIReportReadiness.needsValidation.apiStatusText(
                name: "DeepSeek API",
                language: .english
            ) == "DeepSeek API needs validation"
        )
        #expect(
            AIReportReadiness.invalid.configurationGuidance(
                name: "DeepSeek API",
                language: .chinese
            ) == "DeepSeek API 验证失败，请检查配置后重试"
        )
        #expect(AIReportReadiness.missing.shortStatusText(language: .chinese) == "未配置")
        #expect(AIReportReadiness.missing.symbol == "minus.circle.fill")
        #expect(AIReportReadiness.needsValidation.shortStatusText(language: .english) == "Needs validation")
        #expect(AIReportReadiness.invalid.symbol == "xmark.circle.fill")
    }
}
