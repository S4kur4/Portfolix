import Testing
@testable import Portfolix

@Suite("Agent activity policy")
struct AIAgentActivityPolicyTests {
    @Test
    func keepsOnlyThreeLatestDistinctNonemptyLines() {
        var lines: [AIAgentActivityLine] = []
        lines = AIAgentActivityPolicy.appending("  Preparing input  ", to: lines)
        lines = AIAgentActivityPolicy.appending("Preparing input", to: lines)
        lines = AIAgentActivityPolicy.appending("Reasoning", to: lines)
        lines = AIAgentActivityPolicy.appending("Searching", to: lines)
        lines = AIAgentActivityPolicy.appending("Generating output", to: lines)
        lines = AIAgentActivityPolicy.appending("   ", to: lines)

        #expect(lines.map(\.text) == ["Reasoning", "Searching", "Generating output"])
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
