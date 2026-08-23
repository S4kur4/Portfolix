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
}
