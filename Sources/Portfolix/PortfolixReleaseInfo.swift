import AppKit
import Foundation

enum PortfolixReleaseInfo {
    static let fallbackVersion = "0.1.4"
    static let fallbackBuild = "12"
    static let fallbackCopyright = "Copyright © 2026 S4kur4. All rights reserved."

    static var version: String {
        normalizedBundleValue(for: "CFBundleShortVersionString") ?? fallbackVersion
    }

    static var build: String {
        normalizedBundleValue(for: "CFBundleVersion") ?? fallbackBuild
    }

    static var copyright: String {
        normalizedBundleValue(for: "NSHumanReadableCopyright") ?? fallbackCopyright
    }

    @MainActor
    static func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "Portfolix",
                .applicationVersion: "Version \(version)",
                .version: "Build \(build)",
            ]
        )
    }

    private static func normalizedBundleValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
