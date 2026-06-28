import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum PortfolixDataPackage {
    struct ArchiveManifest: Codable, Equatable, Sendable {
        let formatIdentifier: String
        let schemaVersion: Int
        let exportedAt: String
        let appVersion: String
        let integrityAlgorithm: String
        let recordCounts: RecordCounts
        let files: [ArchiveFile]
        let excludedData: [String]
    }

    struct ArchiveFile: Codable, Equatable, Sendable {
        let name: String
        let recordCount: Int
        let sha256: String
    }

    struct RecordCounts: Codable, Equatable, Sendable {
        let holdings: Int
        let portfolioSnapshots: Int
        let assetPriceSnapshots: Int
    }

    struct Payload: Codable, Equatable, Sendable {
        let holdings: [Holding]
        let portfolioSnapshots: [PortfolioHistory]
        let assetPriceSnapshots: [AssetPriceHistory]
    }

    struct Holding: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let symbol: String
        let category: String
        let quoteCurrency: String
        let quantity: String
        let totalCost: String
        let averageCost: String
        let latestPrice: String
        let marketValueCNY: String
        let profitRate: String
        let source: String
        let quoteTime: String
        let fetchedAt: String
        let freshness: String
        let weeklyTrend: [Double]
        let createdAt: String
        let updatedAt: String
    }

    struct PortfolioHistory: Codable, Equatable, Sendable {
        let date: String
        let totalValueCNY: String
        let totalCostCNY: String
        let totalProfitCNY: String
        let profitRate: String
        let updatedAt: String
    }

    struct AssetPriceHistory: Codable, Equatable, Sendable {
        let assetID: String
        let date: String
        let name: String
        let symbol: String
        let category: String
        let quoteCurrency: String
        let quantity: String
        let averageCost: String
        let latestPrice: String
        let marketValueCNY: String
        let source: String
        let quoteTime: String
        let freshness: String
        let updatedAt: String
    }
}

struct PortfolixDataTransferSummary: Equatable, Sendable {
    let holdingCount: Int
    let portfolioSnapshotCount: Int
    let assetPriceSnapshotCount: Int
}

struct PreparedPortfolixDataImport: Equatable, Sendable {
    let payload: PortfolixDataPackage.Payload
    let summary: PortfolixDataTransferSummary
}

enum PortfolixDataPackageError: LocalizedError {
    case fileTooLarge
    case invalidPackage(String)
    case unsupportedVersion(Int)
    case integrityCheckFailed
    case archiveOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "数据包超过 64 MB 安全限制"
        case let .invalidPackage(reason):
            "数据包内容无效：\(reason)"
        case let .unsupportedVersion(version):
            "暂不支持此数据包版本（\(version)）"
        case .integrityCheckFailed:
            "数据包完整性校验失败，文件可能已损坏或被修改"
        case let .archiveOperationFailed(reason):
            "压缩包处理失败：\(reason)"
        }
    }
}

enum PortfolixDataPackageService {
    static let fileExtension = "zip"
    static let contentType = UTType.zip

    private static let formatIdentifier = "app.portfolix.data-export.archive"
    private static let schemaVersion = 2
    private static let maximumFileSize = 64 * 1_024 * 1_024
    private static let maximumUncompressedSize = 128 * 1_024 * 1_024
    private static let maximumHoldingCount = 10_000
    private static let maximumPortfolioSnapshotCount = 10_000
    private static let maximumAssetPriceSnapshotCount = 500_000
    private static let manifestFilename = "manifest.json"
    private static let holdingsFilename = "holdings.json"
    private static let dailyReturnsFilename = "daily_returns.json"
    private static let dailyAssetPricesFilename = "daily_asset_prices.json"

    private static var archiveFilenames: [String] {
        [manifestFilename, holdingsFilename, dailyReturnsFilename, dailyAssetPricesFilename]
    }

    private static var dataFilenames: Set<String> {
        [holdingsFilename, dailyReturnsFilename, dailyAssetPricesFilename]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func write(payload: PortfolixDataPackage.Payload, to destinationURL: URL) throws -> PortfolixDataTransferSummary {
        try validate(payload: payload)
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let holdingsData = try encoder.encode(payload.holdings)
        let dailyReturnsData = try encoder.encode(payload.portfolioSnapshots)
        let dailyAssetPricesData = try encoder.encode(payload.assetPriceSnapshots)
        let uncompressedDataSize = holdingsData.count + dailyReturnsData.count + dailyAssetPricesData.count
        guard uncompressedDataSize <= maximumUncompressedSize else {
            throw PortfolixDataPackageError.fileTooLarge
        }

        let archiveFiles = [
            PortfolixDataPackage.ArchiveFile(
                name: holdingsFilename,
                recordCount: payload.holdings.count,
                sha256: sha256(holdingsData)
            ),
            PortfolixDataPackage.ArchiveFile(
                name: dailyReturnsFilename,
                recordCount: payload.portfolioSnapshots.count,
                sha256: sha256(dailyReturnsData)
            ),
            PortfolixDataPackage.ArchiveFile(
                name: dailyAssetPricesFilename,
                recordCount: payload.assetPriceSnapshots.count,
                sha256: sha256(dailyAssetPricesData)
            ),
        ]
        let counts = recordCounts(for: payload)
        let manifest = PortfolixDataPackage.ArchiveManifest(
            formatIdentifier: formatIdentifier,
            schemaVersion: schemaVersion,
            exportedAt: ISO8601DateFormatter().string(from: .now),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            integrityAlgorithm: "SHA-256",
            recordCounts: counts,
            files: archiveFiles,
            excludedData: [
                "smart analysis data",
                "app settings and API credentials",
            ]
        )
        try encoder.encode(manifest).write(to: temporaryDirectory.appendingPathComponent(manifestFilename), options: .atomic)
        try holdingsData.write(to: temporaryDirectory.appendingPathComponent(holdingsFilename), options: .atomic)
        try dailyReturnsData.write(to: temporaryDirectory.appendingPathComponent(dailyReturnsFilename), options: .atomic)
        try dailyAssetPricesData.write(to: temporaryDirectory.appendingPathComponent(dailyAssetPricesFilename), options: .atomic)

        let temporaryArchiveURL = temporaryDirectory.appendingPathComponent("Portfolix-Export-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: temporaryArchiveURL) }
        _ = try runArchiveTool(
            executable: "/usr/bin/zip",
            arguments: ["-q", "-X", temporaryArchiveURL.path] + archiveFilenames,
            currentDirectoryURL: temporaryDirectory
        )
        let archiveData = try Data(contentsOf: temporaryArchiveURL, options: [.mappedIfSafe])
        guard archiveData.count <= maximumFileSize else {
            throw PortfolixDataPackageError.fileTooLarge
        }

        let scopedAccess = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }
        try archiveData.write(to: destinationURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
        return summary(for: payload)
    }

    static func prepareImport(from sourceURL: URL) throws -> PreparedPortfolixDataImport {
        let resourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard resourceValues.isRegularFile == true else {
            throw PortfolixDataPackageError.invalidPackage("请选择有效的数据包文件")
        }
        guard (resourceValues.fileSize ?? 0) <= maximumFileSize else {
            throw PortfolixDataPackageError.fileTooLarge
        }

        let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let archiveData = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        guard archiveData.count <= maximumFileSize else {
            throw PortfolixDataPackageError.fileTooLarge
        }
        let archiveEntries = try PortfolixZIPArchiveInspector.inspect(
            data: archiveData,
            maximumUncompressedSize: maximumUncompressedSize
        )
        guard Set(archiveEntries.map(\.name)) == Set(archiveFilenames),
              archiveEntries.count == archiveFilenames.count
        else {
            throw PortfolixDataPackageError.invalidPackage("压缩包目录结构不受支持")
        }

        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let immutableArchiveURL = temporaryDirectory.appendingPathComponent("import.zip")
        try archiveData.write(to: immutableArchiveURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: immutableArchiveURL.path)
        _ = try runArchiveTool(
            executable: "/usr/bin/unzip",
            arguments: ["-qq", immutableArchiveURL.path] + archiveFilenames + ["-d", temporaryDirectory.path]
        )

        var fileData: [String: Data] = [:]
        for entry in archiveEntries {
            let fileURL = temporaryDirectory.appendingPathComponent(entry.name)
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  values.fileSize == entry.uncompressedSize
            else {
                throw PortfolixDataPackageError.invalidPackage("压缩包包含无效文件")
            }
            fileData[entry.name] = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }

        let manifest: PortfolixDataPackage.ArchiveManifest
        do {
            manifest = try decoder.decode(
                PortfolixDataPackage.ArchiveManifest.self,
                from: try requiredData(named: manifestFilename, in: fileData)
            )
        } catch {
            throw PortfolixDataPackageError.invalidPackage("无法解析文件结构")
        }

        guard manifest.formatIdentifier == formatIdentifier else {
            throw PortfolixDataPackageError.invalidPackage("文件类型不受支持")
        }
        guard manifest.schemaVersion == schemaVersion else {
            throw PortfolixDataPackageError.unsupportedVersion(manifest.schemaVersion)
        }
        guard manifest.integrityAlgorithm == "SHA-256" else {
            throw PortfolixDataPackageError.invalidPackage("完整性算法不受支持")
        }
        try validateTimestamp(manifest.exportedAt, field: "manifest.exported_at")

        var manifestFiles: [String: PortfolixDataPackage.ArchiveFile] = [:]
        for file in manifest.files {
            guard manifestFiles.updateValue(file, forKey: file.name) == nil else {
                throw PortfolixDataPackageError.invalidPackage("manifest 包含重复文件记录")
            }
        }
        guard Set(manifestFiles.keys) == dataFilenames else {
            throw PortfolixDataPackageError.invalidPackage("manifest 文件清单无效")
        }
        for filename in dataFilenames {
            let data = try requiredData(named: filename, in: fileData)
            guard manifestFiles[filename]?.sha256.lowercased() == sha256(data) else {
                throw PortfolixDataPackageError.integrityCheckFailed
            }
        }

        let payload: PortfolixDataPackage.Payload
        do {
            payload = PortfolixDataPackage.Payload(
                holdings: try decoder.decode(
                    [PortfolixDataPackage.Holding].self,
                    from: try requiredData(named: holdingsFilename, in: fileData)
                ),
                portfolioSnapshots: try decoder.decode(
                    [PortfolixDataPackage.PortfolioHistory].self,
                    from: try requiredData(named: dailyReturnsFilename, in: fileData)
                ),
                assetPriceSnapshots: try decoder.decode(
                    [PortfolixDataPackage.AssetPriceHistory].self,
                    from: try requiredData(named: dailyAssetPricesFilename, in: fileData)
                )
            )
        } catch let error as PortfolixDataPackageError {
            throw error
        } catch {
            throw PortfolixDataPackageError.invalidPackage("无法解析结构化数据文件")
        }
        guard manifest.recordCounts == recordCounts(for: payload),
              manifestFiles[holdingsFilename]?.recordCount == payload.holdings.count,
              manifestFiles[dailyReturnsFilename]?.recordCount == payload.portfolioSnapshots.count,
              manifestFiles[dailyAssetPricesFilename]?.recordCount == payload.assetPriceSnapshots.count
        else {
            throw PortfolixDataPackageError.invalidPackage("记录计数不一致")
        }
        try validate(payload: payload)
        return PreparedPortfolixDataImport(payload: payload, summary: summary(for: payload))
    }

    static func validate(payload: PortfolixDataPackage.Payload) throws {
        guard payload.holdings.count <= maximumHoldingCount else {
            throw PortfolixDataPackageError.invalidPackage("持仓记录数量超出限制")
        }
        guard payload.portfolioSnapshots.count <= maximumPortfolioSnapshotCount else {
            throw PortfolixDataPackageError.invalidPackage("组合历史记录数量超出限制")
        }
        guard payload.assetPriceSnapshots.count <= maximumAssetPriceSnapshotCount else {
            throw PortfolixDataPackageError.invalidPackage("资产价格记录数量超出限制")
        }

        var holdingIdentities = Set<String>()
        for holding in payload.holdings {
            try validateUUID(holding.id, field: "holding.id")
            try validateText(holding.name, field: "holding.name", maximumLength: 256)
            try validateText(holding.symbol, field: "holding.symbol", maximumLength: 64)
            try validateCategory(holding.category)
            try validateCurrency(holding.quoteCurrency)
            try validateDecimal(holding.quantity, field: "holding.quantity", allowsNegative: false)
            try validateDecimal(holding.totalCost, field: "holding.total_cost", allowsNegative: false)
            try validateDecimal(holding.averageCost, field: "holding.average_cost", allowsNegative: false)
            try validateDecimal(holding.latestPrice, field: "holding.latest_price", allowsNegative: false)
            try validateDecimal(holding.marketValueCNY, field: "holding.market_value_cny", allowsNegative: false)
            try validateDecimal(holding.profitRate, field: "holding.profit_rate", allowsNegative: true)
            try validateText(holding.source, field: "holding.source", maximumLength: 256)
            try validateText(holding.quoteTime, field: "holding.quote_time", maximumLength: 128)
            try validateTimestamp(holding.fetchedAt, field: "holding.fetched_at")
            try validateFreshness(holding.freshness)
            try validateTimestamp(holding.createdAt, field: "holding.created_at")
            try validateTimestamp(holding.updatedAt, field: "holding.updated_at")
            guard holding.weeklyTrend.count <= 366,
                  holding.weeklyTrend.allSatisfy({ $0.isFinite && $0 >= 0 })
            else {
                throw PortfolixDataPackageError.invalidPackage("holding.weekly_trend 无效")
            }

            let identity = "\(holding.category)|\(holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())"
            guard holdingIdentities.insert(identity).inserted else {
                throw PortfolixDataPackageError.invalidPackage("存在重复持仓")
            }

            guard
                let category = AssetCategory(rawValue: holding.category),
                let currency = DisplayCurrency(rawValue: holding.quoteCurrency),
                let quantity = Decimal(string: holding.quantity),
                let averageCost = Decimal(string: holding.averageCost),
                let latestPrice = Decimal(string: holding.latestPrice)
            else {
                throw PortfolixDataPackageError.invalidPackage("持仓数值无法解析")
            }
            do {
                try PositionInputValidator.validate(
                    name: holding.name,
                    symbol: holding.symbol,
                    quantity: quantity,
                    averageCost: averageCost,
                    latestPrice: latestPrice
                )
                try PositionInputValidator.validateProviderIdentity(
                    category: category,
                    quoteCurrency: currency,
                    source: holding.source
                )
            } catch {
                throw PortfolixDataPackageError.invalidPackage(error.localizedDescription)
            }
        }

        var portfolioDates = Set<String>()
        for snapshot in payload.portfolioSnapshots {
            try validateDay(snapshot.date, field: "portfolio_snapshot.date")
            try validateDecimal(snapshot.totalValueCNY, field: "portfolio_snapshot.total_value_cny", allowsNegative: false)
            try validateDecimal(snapshot.totalCostCNY, field: "portfolio_snapshot.total_cost_cny", allowsNegative: false)
            try validateDecimal(snapshot.totalProfitCNY, field: "portfolio_snapshot.total_profit_cny", allowsNegative: true)
            try validateDecimal(snapshot.profitRate, field: "portfolio_snapshot.profit_rate", allowsNegative: true)
            try validateTimestamp(snapshot.updatedAt, field: "portfolio_snapshot.updated_at")
            guard portfolioDates.insert(snapshot.date).inserted else {
                throw PortfolixDataPackageError.invalidPackage("存在重复组合历史记录")
            }
        }

        var assetSnapshotKeys = Set<String>()
        for snapshot in payload.assetPriceSnapshots {
            try validateUUID(snapshot.assetID, field: "asset_price_snapshot.asset_id")
            try validateDay(snapshot.date, field: "asset_price_snapshot.date")
            try validateText(snapshot.name, field: "asset_price_snapshot.name", maximumLength: 256)
            try validateText(snapshot.symbol, field: "asset_price_snapshot.symbol", maximumLength: 64)
            try validateCategory(snapshot.category)
            try validateCurrency(snapshot.quoteCurrency)
            try validateDecimal(snapshot.quantity, field: "asset_price_snapshot.quantity", allowsNegative: false)
            try validateDecimal(snapshot.averageCost, field: "asset_price_snapshot.average_cost", allowsNegative: false)
            try validateDecimal(snapshot.latestPrice, field: "asset_price_snapshot.latest_price", allowsNegative: false)
            try validateDecimal(snapshot.marketValueCNY, field: "asset_price_snapshot.market_value_cny", allowsNegative: false)
            try validateText(snapshot.source, field: "asset_price_snapshot.source", maximumLength: 256)
            try validateText(snapshot.quoteTime, field: "asset_price_snapshot.quote_time", maximumLength: 128)
            try validateFreshness(snapshot.freshness)
            try validateTimestamp(snapshot.updatedAt, field: "asset_price_snapshot.updated_at")
            guard assetSnapshotKeys.insert("\(snapshot.assetID)|\(snapshot.date)").inserted else {
                throw PortfolixDataPackageError.invalidPackage("存在重复资产价格记录")
            }
        }
    }

    private static func recordCounts(for payload: PortfolixDataPackage.Payload) -> PortfolixDataPackage.RecordCounts {
        PortfolixDataPackage.RecordCounts(
            holdings: payload.holdings.count,
            portfolioSnapshots: payload.portfolioSnapshots.count,
            assetPriceSnapshots: payload.assetPriceSnapshots.count
        )
    }

    private static func summary(for payload: PortfolixDataPackage.Payload) -> PortfolixDataTransferSummary {
        PortfolixDataTransferSummary(
            holdingCount: payload.holdings.count,
            portfolioSnapshotCount: payload.portfolioSnapshots.count,
            assetPriceSnapshotCount: payload.assetPriceSnapshots.count
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortfolixDataPackage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static func requiredData(named filename: String, in files: [String: Data]) throws -> Data {
        guard let data = files[filename] else {
            throw PortfolixDataPackageError.invalidPackage("缺少 \(filename)")
        }
        return data
    }

    @discardableResult
    private static func runArchiveTool(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = archiveToolEnvironment()
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw PortfolixDataPackageError.archiveOperationFailed(error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let message = String(data: output.prefix(4_096), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PortfolixDataPackageError.archiveOperationFailed(
                message?.isEmpty == false ? message! : "系统压缩工具返回错误"
            )
        }
        return output
    }

    private static func archiveToolEnvironment() -> [String: String] {
        var environment: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
        ]
        if let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"], !tmpdir.isEmpty {
            environment["TMPDIR"] = tmpdir
        }
        return environment
    }

    private static func validateUUID(_ value: String, field: String) throws {
        guard UUID(uuidString: value) != nil else {
            throw PortfolixDataPackageError.invalidPackage("\(field) 不是有效 UUID")
        }
    }

    private static func validateText(_ value: String, field: String, maximumLength: Int) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw PortfolixDataPackageError.invalidPackage("\(field) 无效")
        }
    }

    private static func validateDecimal(_ value: String, field: String, allowsNegative: Bool) throws {
        guard let decimal = Decimal(string: value), !decimal.isNaN, allowsNegative || decimal >= 0 else {
            throw PortfolixDataPackageError.invalidPackage("\(field) 不是有效数值")
        }
    }

    private static func validateTimestamp(_ value: String, field: String) throws {
        guard ISO8601DateFormatter().date(from: value) != nil else {
            throw PortfolixDataPackageError.invalidPackage("\(field) 不是有效时间")
        }
    }

    private static func validateDay(_ value: String, field: String) throws {
        let components = value.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3,
              let date = Calendar(identifier: .gregorian).date(
                  from: DateComponents(year: components[0], month: components[1], day: components[2])
              )
        else {
            throw PortfolixDataPackageError.invalidPackage("\(field) 不是有效日期")
        }
        let normalized = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let formatted = String(format: "%04d-%02d-%02d", normalized.year ?? 0, normalized.month ?? 0, normalized.day ?? 0)
        guard formatted == value else {
            throw PortfolixDataPackageError.invalidPackage("\(field) 不是有效日期")
        }
    }

    private static func validateCategory(_ value: String) throws {
        guard AssetCategory(rawValue: value) != nil else {
            throw PortfolixDataPackageError.invalidPackage("资产类别不受支持")
        }
    }

    private static func validateCurrency(_ value: String) throws {
        guard DisplayCurrency(rawValue: value) != nil else {
            throw PortfolixDataPackageError.invalidPackage("币种不受支持")
        }
    }

    private static func validateFreshness(_ value: String) throws {
        guard Freshness(rawValue: value) != nil else {
            throw PortfolixDataPackageError.invalidPackage("价格状态不受支持")
        }
    }
}

private enum PortfolixZIPArchiveInspector {
    struct Entry: Equatable, Sendable {
        let name: String
        let compressedSize: Int
        let uncompressedSize: Int
    }

    private static let endOfCentralDirectorySignature = 0x0605_4B50
    private static let centralDirectorySignature = 0x0201_4B50
    private static let localFileSignature = 0x0403_4B50
    private static let maximumEndRecordSearch = 65_557

    static func inspect(data: Data, maximumUncompressedSize: Int) throws -> [Entry] {
        guard data.count >= 22 else {
            throw PortfolixDataPackageError.invalidPackage("ZIP 文件不完整")
        }
        let earliestOffset = max(0, data.count - maximumEndRecordSearch)
        var candidateOffset = data.count - 22
        var endRecordOffset: Int?
        while candidateOffset >= earliestOffset {
            if try uint32(data, at: candidateOffset) == endOfCentralDirectorySignature {
                let commentLength = try uint16(data, at: candidateOffset + 20)
                if candidateOffset + 22 + commentLength == data.count {
                    endRecordOffset = candidateOffset
                    break
                }
            }
            candidateOffset -= 1
        }
        guard let endRecordOffset else {
            throw PortfolixDataPackageError.invalidPackage("无法定位 ZIP 目录")
        }

        let diskNumber = try uint16(data, at: endRecordOffset + 4)
        let centralDirectoryDisk = try uint16(data, at: endRecordOffset + 6)
        let entriesOnDisk = try uint16(data, at: endRecordOffset + 8)
        let totalEntries = try uint16(data, at: endRecordOffset + 10)
        let centralDirectorySize = try uint32(data, at: endRecordOffset + 12)
        let centralDirectoryOffset = try uint32(data, at: endRecordOffset + 16)
        guard diskNumber == 0,
              centralDirectoryDisk == 0,
              entriesOnDisk == totalEntries,
              totalEntries > 0,
              totalEntries < 0xFFFF,
              centralDirectorySize < 0xFFFF_FFFF,
              centralDirectoryOffset < 0xFFFF_FFFF,
              centralDirectoryOffset + centralDirectorySize == endRecordOffset
        else {
            throw PortfolixDataPackageError.invalidPackage("不支持多卷或 ZIP64 压缩包")
        }

        var entries: [Entry] = []
        var names = Set<String>()
        var totalUncompressedSize = 0
        var offset = centralDirectoryOffset

        for _ in 0..<totalEntries {
            guard offset + 46 <= endRecordOffset,
                  try uint32(data, at: offset) == centralDirectorySignature
            else {
                throw PortfolixDataPackageError.invalidPackage("ZIP 目录记录无效")
            }
            let versionMadeBy = try uint16(data, at: offset + 4)
            let flags = try uint16(data, at: offset + 8)
            let compressionMethod = try uint16(data, at: offset + 10)
            let compressedSize = try uint32(data, at: offset + 20)
            let uncompressedSize = try uint32(data, at: offset + 24)
            let filenameLength = try uint16(data, at: offset + 28)
            let extraLength = try uint16(data, at: offset + 30)
            let commentLength = try uint16(data, at: offset + 32)
            let externalAttributes = try uint32(data, at: offset + 38)
            let localHeaderOffset = try uint32(data, at: offset + 42)
            let recordLength = 46 + filenameLength + extraLength + commentLength
            guard offset + recordLength <= endRecordOffset,
                  compressedSize < 0xFFFF_FFFF,
                  uncompressedSize < 0xFFFF_FFFF,
                  flags & 0x41 == 0,
                  compressionMethod == 0 || compressionMethod == 8
            else {
                throw PortfolixDataPackageError.invalidPackage("ZIP 文件条目不受支持")
            }

            let name = try string(data, at: offset + 46, length: filenameLength)
            guard isSafeFlatFilename(name), names.insert(name).inserted else {
                throw PortfolixDataPackageError.invalidPackage("ZIP 文件名无效或重复")
            }
            let creatorPlatform = versionMadeBy >> 8
            let unixMode = externalAttributes >> 16
            if creatorPlatform == 3 {
                let fileType = unixMode & 0xF000
                guard fileType != 0xA000, fileType != 0x4000 else {
                    throw PortfolixDataPackageError.invalidPackage("ZIP 不允许包含链接或目录条目")
                }
            }

            guard localHeaderOffset + 30 <= centralDirectoryOffset,
                  try uint32(data, at: localHeaderOffset) == localFileSignature
            else {
                throw PortfolixDataPackageError.invalidPackage("ZIP 本地文件头无效")
            }
            let localFlags = try uint16(data, at: localHeaderOffset + 6)
            let localCompressionMethod = try uint16(data, at: localHeaderOffset + 8)
            let localFilenameLength = try uint16(data, at: localHeaderOffset + 26)
            let localExtraLength = try uint16(data, at: localHeaderOffset + 28)
            let localName = try string(data, at: localHeaderOffset + 30, length: localFilenameLength)
            let localDataOffset = localHeaderOffset + 30 + localFilenameLength + localExtraLength
            guard localName == name,
                  localFlags & 0x41 == 0,
                  localCompressionMethod == compressionMethod,
                  localDataOffset + compressedSize <= centralDirectoryOffset
            else {
                throw PortfolixDataPackageError.invalidPackage("ZIP 文件头信息不一致")
            }

            totalUncompressedSize += uncompressedSize
            guard totalUncompressedSize <= maximumUncompressedSize else {
                throw PortfolixDataPackageError.fileTooLarge
            }
            entries.append(
                Entry(name: name, compressedSize: compressedSize, uncompressedSize: uncompressedSize)
            )
            offset += recordLength
        }

        guard offset == centralDirectoryOffset + centralDirectorySize else {
            throw PortfolixDataPackageError.invalidPackage("ZIP 目录大小不一致")
        }
        return entries
    }

    private static func isSafeFlatFilename(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func string(_ data: Data, at offset: Int, length: Int) throws -> String {
        guard offset >= 0, length >= 0, offset + length <= data.count,
              let value = String(data: data.subdata(in: offset..<(offset + length)), encoding: .utf8)
        else {
            throw PortfolixDataPackageError.invalidPackage("ZIP 文件名编码无效")
        }
        return value
    }

    private static func uint16(_ data: Data, at offset: Int) throws -> Int {
        guard offset >= 0, offset + 2 <= data.count else {
            throw PortfolixDataPackageError.invalidPackage("ZIP 结构越界")
        }
        return Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func uint32(_ data: Data, at offset: Int) throws -> Int {
        guard offset >= 0, offset + 4 <= data.count else {
            throw PortfolixDataPackageError.invalidPackage("ZIP 结构越界")
        }
        return Int(data[offset])
            | (Int(data[offset + 1]) << 8)
            | (Int(data[offset + 2]) << 16)
            | (Int(data[offset + 3]) << 24)
    }
}

@MainActor
enum PortfolixDataFilePanel {
    static func chooseExportDestination(language: AppLanguage) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [PortfolixDataPackageService.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFilename()
        panel.title = localizedText("导出 Portfolix 数据", "Export Portfolix Data", language: language)
        panel.prompt = localizedText("创建导出", "Export", language: language)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseImportSource(language: AppLanguage) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [PortfolixDataPackageService.contentType]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = localizedText("选择 Portfolix 数据包", "Choose Portfolix Data Package", language: language)
        panel.prompt = localizedText("选择文件", "Choose File", language: language)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func defaultFilename(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return "Portfolix-Data-\(formatter.string(from: now)).\(PortfolixDataPackageService.fileExtension)"
    }
}
