import AppKit
import SwiftUI
import Testing
@testable import Portfolix

@Suite("Provider configuration sheet")
@MainActor
struct ProviderConfigurationSheetTests {
    @Test
    func footerNoticesKeepValidationIconsColorsAndProviderNames() {
        let statuses: [ProviderConnectionStatus] = [.validatingAPI(language: .chinese), .validatedAPI(language: .english), .failure("Invalid key")]
        for status in statuses {
            let notice = status.footerNotice(prefix: "Tavily Search")
            #expect(notice.symbol == status.symbol)
            #expect(notice.color == status.color)
            #expect(notice.message == "Tavily Search · \(status.message)")
        }
        let notices = statuses.map { $0.footerNotice() }
        let footer = SheetActionFooter(errorMessage: nil, notices: notices) { Text("Save") }
        #expect(footer.displayedNotices == Array(notices.suffix(1)))
        let failed = SheetActionFooter(errorMessage: "Save failed", notices: notices) { Text("Save") }
        #expect(failed.displayedNotices == [.init(message: "Save failed", kind: .error)])
    }

    @Test
    func onlyOneFooterNoticeUsesOneLineInBothThemes() {
        for scheme: ColorScheme in [.light, .dark] {
            let notices = [
                ProviderConnectionStatus.validatingAPI(language: .english).footerNotice(prefix: "DeepSeek Search"),
                ProviderConnectionStatus.validatedAPI(language: .english).footerNotice(prefix: "Tavily Search"),
                ProviderConnectionStatus.failure("API Key 无效或已失效，请检查后重新填写。").footerNotice(prefix: "博查")
            ]
            let host = NSHostingView(rootView: SheetActionFooter(errorMessage: nil, notices: notices) {
                Button("Cancel") {}.buttonStyle(QuietButtonStyle())
                Button("Save") {}.buttonStyle(PrimaryButtonStyle())
            }.frame(width: 560).environment(\.colorScheme, scheme))
            #expect(host.fittingSize.width == 560)
            let baseline = NSHostingView(rootView: SheetActionFooter(errorMessage: nil) {
                Button("Cancel") {}.buttonStyle(QuietButtonStyle())
                Button("Save") {}.buttonStyle(PrimaryButtonStyle())
            }.frame(width: 560).environment(\.colorScheme, scheme))
            #expect(host.fittingSize.height == baseline.fittingSize.height)
        }
    }

    @Test
    func latestProviderOperationWinsEvenWhenAnOlderValidationFinishesLater() {
        var state = SearchProviderNoticeState()
        state.begin(.tavily)
        state.update(.failure("请先填写 API Key"), for: .tavily)
        #expect(state.currentNotice(language: .chinese)?.message == "Tavily · 请先填写 API Key")
        state.begin(.bocha)
        state.update(.validating("正在验证 API 配置"), for: .bocha)
        state.update(.failure("Old Tavily request failed"), for: .tavily)
        #expect(state.currentNotice(language: .chinese)?.message == "博查 · 正在验证 API 配置")
        state.update(.failure("API Key 无效或已失效"), for: .bocha)
        #expect(state.currentNotice(language: .chinese)?.message == "博查 · API Key 无效或已失效")
        state.begin(.parallel)
        state.update(.failure("Late Bocha failure"), for: .bocha)
        #expect(state.currentNotice(language: .chinese) == nil)
    }

    @Test
    func footerNormalizesLineBreaksWithoutCombiningMultipleErrors() {
        let notice = SheetNotice(message: "First line\nSecond line\r\nThird line", kind: .error)
        #expect(notice.singleLineMessage == "First line Second line Third line")
        let footer = SheetActionFooter(errorMessage: "Current action failed", notices: [notice]) { Text("Save") }
        #expect(footer.displayedNotices.count == 1)
        #expect(footer.displayedNotices.first?.message == "Current action failed")
    }

    @Test
    func validatingProviderUsesTheDeepSeekAccentColor() {
        #expect(
            ProviderConnectionStatus.validating("Validating API").color
                == PortfolixTheme.lilac
        )
    }

    @Test
    func providerValidationNoticesUseConsistentSymbolsAndColors() {
        let validating = ProviderConnectionStatus.validating("正在验证 API 配置")
        let success = ProviderConnectionStatus.success("API 已验证")
        let failure = ProviderConnectionStatus.failure("API 验证失败")

        #expect(validating.symbol == "clock.arrow.circlepath")
        #expect(validating.color == PortfolixTheme.lilac)
        #expect(success.symbol == "checkmark.circle.fill")
        #expect(success.color == PortfolixTheme.mint)
        #expect(failure.symbol == "xmark.circle.fill")
        #expect(failure.color == PortfolixTheme.danger)
    }

    @Test
    func providerValidationMessagesUseSharedChineseAndEnglishCopy() {
        #expect(ProviderConnectionStatus.validatingAPI(language: .chinese) == .validating("正在验证 API 配置"))
        #expect(ProviderConnectionStatus.validatingAPI(language: .english) == .validating("Validating API configuration"))
        #expect(ProviderConnectionStatus.validatedAPI(language: .chinese) == .success("API 已验证"))
        #expect(ProviderConnectionStatus.validatedAPI(language: .english) == .success("API validated"))
    }

    @Test
    func providerNoticesPreserveErrorsAndShareStatusPresentation() {
        let statuses: [ProviderConnectionStatus] = [
            .validatingAPI(language: .chinese),
            .validatedAPI(language: .english),
            .failure(LLMClientError.unauthorized.localizedDescription),
            .failure(TavilyClientError.unauthorized.localizedDescription),
            .failure(BochaAIClientError.unauthorized.localizedDescription),
            .failure(DeepSeekSearchError.unauthorized.localizedDescription),
            .failure("请先填写 API Key"),
        ]

        for status in statuses {
            let notice = ProviderNoticeRow(status: status)
            #expect(notice.symbol == status.symbol)
            #expect(notice.title == status.message)
            #expect(notice.tint == status.color)
            #expect(notice.titleColor == status.color)
            #expect(notice.message == nil)
        }
    }

    @Test
    func providerNoticeRowsHaveConsistentHeightInBothAppearances() {
        for scheme: ColorScheme in [.light, .dark] {
            let statuses: [ProviderConnectionStatus] = [
                .validatingAPI(language: .chinese),
                .validatedAPI(language: .chinese),
                .validatingAPI(language: .english),
                .validatedAPI(language: .english),
                .failure(BochaAIClientError.unauthorized.localizedDescription),
            ]
            let heights = statuses.map { status in
                let view = NSHostingView(
                    rootView: ProviderNoticeRow(status: status)
                        .frame(width: 500)
                        .environment(\.colorScheme, scheme)
                )
                return view.fittingSize.height
            }
            #expect(heights.allSatisfy { $0 > 0 && $0 == heights.first })
        }
    }

    @Test
    func emptyAPIKeyIsImmediatelyEditableWithoutRevealingItFirst() {
        #expect(ProviderAPIKeyPresentation.displaysEditableText(isVisible: false, text: ""))
        #expect(ProviderAPIKeyPresentation.shouldRevealWhenEditing(isVisible: false, text: ""))
        #expect(!ProviderAPIKeyPresentation.displaysEditableText(isVisible: false, text: "stored-secret"))
        #expect(!ProviderAPIKeyPresentation.shouldRevealWhenEditing(isVisible: false, text: "stored-secret"))
        #expect(ProviderAPIKeyPresentation.displaysEditableText(isVisible: true, text: "stored-secret"))
    }

    @Test
    func hiddenAPIKeyUsesAConstantNonSelectableMask() throws {
        let view = ProviderAPIKeyTextInputView(frame: NSRect(x: 0, y: 0, width: 340, height: 28))
        let key = "sk-" + String(repeating: "a", count: 64)

        view.update(text: key, isVisible: false, textColor: .labelColor)

        #expect(view.plainField.isHidden)
        let maskedField = try #require(
            view.subviews
                .compactMap { $0 as? NSTextField }
                .first { !$0.isHidden }
        )
        #expect(maskedField.stringValue == String(repeating: "x", count: 12))
        #expect(maskedField.stringValue.count == 12)
        #expect(maskedField.stringValue != key)
        #expect(!maskedField.isEditable)
        #expect(!maskedField.isSelectable)
    }

    @Test
    func visibleAPIKeyUsesTheEditablePlainTextField() {
        let view = ProviderAPIKeyTextInputView(frame: NSRect(x: 0, y: 0, width: 340, height: 28))
        let key = "sk-visible-edit-test"

        view.update(text: key, isVisible: true, textColor: .labelColor)

        #expect(!view.plainField.isHidden)
        #expect(view.plainField.isEditable)
        #expect(view.plainField.isSelectable)
        #expect(view.plainField.stringValue == key)
        #expect(view.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }.count == 1)
    }

    @Test
    func clickingHiddenAPIKeyRequestsReveal() throws {
        let view = ProviderAPIKeyTextInputView(frame: NSRect(x: 0, y: 0, width: 340, height: 28))
        var revealCount = 0
        view.onReveal = { revealCount += 1 }
        view.update(text: "sk-hidden", isVisible: false, textColor: .labelColor)

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        view.mouseDown(with: event)

        #expect(revealCount == 1)
        #expect(view.plainField.isHidden)
        #expect(view.plainField.currentEditor() == nil)
    }

    @Test
    func deepSeekModelCatalogRejectsUnexpectedIdentifiers() {
        let models = LLMProviderOption.sanitizedDeepSeekModels([
            " deepseek-v4-pro ",
            "deepseek-v4-pro",
            "deepseek-v5-preview",
            "../unexpected",
            "deepseek-model with spaces",
        ])

        #expect(models == ["deepseek-v4-pro", "deepseek-v5-preview"])
    }

    @Test
    func cachedDeepSeekModelCanBeSelectedAndRestored() throws {
        let suiteName = "Portfolix.ProviderConfigurationSheetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = "deepseek-v5-preview"

        AIProviderConfigurationStore.saveCachedModels(
            [model],
            provider: .deepSeek,
            defaults: defaults
        )
        AIProviderConfigurationStore.saveLLM(
            AIProviderConfiguration(
                provider: LLMProviderOption.deepSeek.rawValue,
                baseURL: LLMProviderOption.deepSeek.defaultBaseURL,
                model: model,
                isEnabled: true
            ),
            defaults: defaults
        )

        #expect(AIProviderConfigurationStore.loadLLM(defaults: defaults).model == model)
    }

    @Test
    func successfulServerCatalogReplacesBundledFallbackModels() throws {
        let suiteName = "Portfolix.ProviderConfigurationSheetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AIProviderConfigurationStore.availableDeepSeekModels(defaults: defaults) == [
            "deepseek-flash",
            "deepseek-v4-pro",
        ])

        AIProviderConfigurationStore.saveCachedModels(
            ["deepseek-next"],
            provider: .deepSeek,
            defaults: defaults
        )

        #expect(AIProviderConfigurationStore.availableDeepSeekModels(defaults: defaults) == ["deepseek-next"])
    }

    @Test
    func retiredSelectionMigratesToCurrentServerModel() throws {
        let suiteName = "Portfolix.ProviderConfigurationSheetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AIProviderConfigurationStore.saveCachedModels(
            ["deepseek-flash", "deepseek-v4-pro"],
            provider: .deepSeek,
            defaults: defaults
        )
        defaults.set("deepseek-v4-flash", forKey: "portfolix.ai.llm.model")

        #expect(AIProviderConfigurationStore.loadLLM(defaults: defaults).model == "deepseek-flash")
    }

    @Test
    func currentDeepSeekModelsUseExternalSearchForConnectedMode() {
        let models = ["deepseek-flash", "deepseek-v4-pro"]

        #expect(!LLMProviderOption.supportsBuiltInWebSearch(model: "deepseek-flash"))
        #expect(!LLMProviderOption.supportsBuiltInWebSearch(model: "deepseek-v4-pro"))
        #expect(LLMProviderOption.preferredConnectedModel(in: models) == nil)
        #expect(SmartAnalysisMode.availableCases == [.basic, .connected])
    }
}
