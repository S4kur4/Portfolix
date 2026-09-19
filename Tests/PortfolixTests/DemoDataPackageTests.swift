import Foundation
import Testing
@testable import Portfolix

@Suite("Demo data package")
struct DemoDataPackageTests {
    @Test
    func generatedPackageImportsWithOneMonthOfPrivacySafeData() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortfolixDemoPackageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let archiveURL = outputDirectory.appendingPathComponent("Portfolix-Demo-Portfolio-30D.zip")
        let generator = Process()
        generator.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        generator.arguments = [
            "python3",
            packageRoot.appendingPathComponent("scripts/generate-demo-data.py").path,
            "--output", archiveURL.path,
            "--end-date", "2026-09-19",
        ]
        try generator.run()
        generator.waitUntilExit()
        try #require(generator.terminationStatus == 0)

        let prepared = try PortfolixDataPackageService.prepareImport(from: archiveURL)

        #expect(prepared.summary.holdingCount == 14)
        #expect(prepared.summary.portfolioSnapshotCount == 30)
        #expect(prepared.summary.assetPriceSnapshotCount == 434)
        #expect(prepared.summary.riskProfileIncluded)
        #expect(Set(prepared.payload.holdings.map(\.category)).count >= 6)
        #expect(prepared.payload.riskProfile?.configured == true)

        let serializedPayload = try JSONEncoder().encode(prepared.payload)
        let payloadText = try #require(String(data: serializedPayload, encoding: .utf8))
        #expect(!payloadText.localizedCaseInsensitiveContains("api key"))
        #expect(!payloadText.localizedCaseInsensitiveContains("chat"))

        let databaseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortfolixDemoDataTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: databaseDirectory) }
        let repository = try PositionRepository(
            databaseURL: databaseDirectory.appendingPathComponent("portfolix.sqlite3")
        )
        _ = try repository.importDataPayload(prepared.payload)

        let endDate = try #require(
            prepared.payload.assetPriceSnapshots
                .map(\.date)
                .max()
                .flatMap(Self.dayFormatter.date(from:))
        )
        let dailyProfit = try repository.fetchDailyProfitPoints(limitDays: 365, through: endDate)
        #expect(dailyProfit.count == 30)
        #expect(dailyProfit.contains { $0.amountCNY > 0 })
        #expect(dailyProfit.contains { $0.amountCNY < 0 })
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
