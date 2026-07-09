import Testing
@testable import Portfolix

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
                name: "LLM API",
                language: .chinese
            ) == "LLM API 未配置"
        )
        #expect(
            AIReportReadiness.needsValidation.apiStatusText(
                name: "Search API",
                language: .english
            ) == "Search API needs validation"
        )
        #expect(
            AIReportReadiness.invalid.configurationGuidance(
                name: "LLM API",
                language: .chinese
            ) == "LLM API 验证失败，请检查配置后重试"
        )
        #expect(AIReportReadiness.missing.shortStatusText(language: .chinese) == "未配置")
        #expect(AIReportReadiness.missing.symbol == "minus.circle.fill")
        #expect(AIReportReadiness.needsValidation.shortStatusText(language: .english) == "Needs validation")
        #expect(AIReportReadiness.invalid.symbol == "xmark.circle.fill")
    }
}
