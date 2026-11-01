import AppKit
import Testing
@testable import Portfolix

@Suite("Sheet field-editor submission")
@MainActor
struct SheetEditingCommitTests {
    private final class Editor: NSView {
        var canResign = true
        var didResign: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func resignFirstResponder() -> Bool {
            guard canResign else { return false }
            didResign?()
            return true
        }
    }

    private final class BindingState {
        var value = ""
        var commits = 0
    }

    @Test
    func firstSubmissionReadsTheLastEditAfterItsBindingCallback() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = Editor(frame: window.contentView!.bounds)
        window.contentView = editor
        let state = BindingState()
        editor.didResign = {
            DispatchQueue.main.async {
                state.value = "125.75"
                state.commits += 1
            }
        }
        #expect(window.makeFirstResponder(editor))
        #expect(state.value.isEmpty)
        #expect(await SheetEditingCommit.commit(in: window))
        #expect(state.value == "125.75")
        #expect(state.commits == 1)
    }

    @Test
    func rejectedEditingCommitDoesNotContinueSubmission() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = Editor(frame: window.contentView!.bounds)
        window.contentView = editor
        defer { editor.canResign = true; window.close() }
        #expect(window.makeFirstResponder(editor))
        editor.canResign = false
        #expect(await !SheetEditingCommit.commit(in: window))
        #expect(window.firstResponder === editor)
    }
}
