import Foundation
import Sparkle
import SwiftUI

struct PortfolixAvailableUpdate: Equatable {
    let displayVersion: String
    let buildVersion: String
}

@MainActor
final class PortfolixSparkleUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var availableUpdate: PortfolixAvailableUpdate?

    private let isConfigured: Bool
    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    private static let noUpdateErrorCode = 1001
    private static let lastProbeDateKey = "portfolix.sparkle.lastProbeDate"
    private static let probeInterval: TimeInterval = 24 * 60 * 60

    override init() {
        isConfigured = Self.hasRequiredSparkleConfiguration
        super.init()

        guard isConfigured else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            probeForAvailableUpdateIfNeeded()
        }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func probeForAvailableUpdateIfNeeded(force: Bool = false) {
        guard
            let updater = updaterController?.updater,
            updater.canCheckForUpdates
        else { return }

        if !force {
            let lastProbeDate = UserDefaults.standard.object(forKey: Self.lastProbeDateKey) as? Date
            if let lastProbeDate, Date().timeIntervalSince(lastProbeDate) < Self.probeInterval {
                return
            }
        }

        UserDefaults.standard.set(Date(), forKey: Self.lastProbeDateKey)
        updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableUpdate = PortfolixAvailableUpdate(
            displayVersion: item.displayVersionString,
            buildVersion: item.versionString
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableUpdate = nil
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableUpdate = nil
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain, nsError.code == Self.noUpdateErrorCode {
            availableUpdate = nil
        }
    }

    private static var hasRequiredSparkleConfiguration: Bool {
        normalizedBundleValue(for: "SUFeedURL") != nil
            && normalizedBundleValue(for: "SUPublicEDKey") != nil
    }

    private static func normalizedBundleValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CheckForUpdatesMenuItem: View {
    @ObservedObject var updater: PortfolixSparkleUpdater

    var body: some View {
        Button(systemUpdateLocalizedText("检查更新…", "Check for Updates…")) {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}

private func systemUpdateLocalizedText(_ chinese: String, _ english: String) -> String {
    let preferredLanguage = Locale.preferredLanguages.first ?? Locale.current.identifier
    return preferredLanguage.lowercased().hasPrefix("zh") ? chinese : english
}
