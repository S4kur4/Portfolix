import AppKit

@MainActor
enum SheetEditingCommit {
    static func commit(in window: NSWindow?) async -> Bool {
        guard window?.makeFirstResponder(nil) ?? true else { return false }
        // Field-editor callbacks and SwiftUI bindings must settle before the form reads its values.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        return !Task.isCancelled
    }
}
