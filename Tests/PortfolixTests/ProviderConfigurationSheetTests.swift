import AppKit
import Testing
@testable import Portfolix

@Suite("Provider configuration sheet")
@MainActor
struct ProviderConfigurationSheetTests {
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
