import CSQLite
import Foundation
import SwiftUI

enum PositionRepositoryError: LocalizedError {
    case database(String)
    case invalidStoredData(String)

    var errorDescription: String? {
        switch self {
        case let .database(message):
            "本地数据库操作失败：\(message)"
        case let .invalidStoredData(message):
            "本地持仓数据无效：\(message)"
        }
    }
}

struct AssetPriceSnapshotPoint: Equatable, Sendable {
    let date: Date
    let latestPrice: Decimal
    let quantity: Decimal
    let marketValueCNY: Decimal
}

final class PositionRepository {
    private let database: OpaquePointer
    private let databaseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let aiArtifactEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let aiArtifactDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(databaseURL: URL = PositionRepository.defaultDatabaseURL()) throws {
        self.databaseURL = databaseURL
        let directoryURL = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try Self.applyDirectoryPermissions(at: directoryURL)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let handle {
                sqlite3_close(handle)
            }
            throw PositionRepositoryError.database(message)
        }

        database = handle
        try configure()
        try migrate()
        try applyDatabaseFilePermissions()
    }

    deinit {
        sqlite3_close(database)
    }

    static func defaultDatabaseURL() -> URL {
#if DEBUG
        if let overridePath = ProcessInfo.processInfo.environment["PORTFOLIX_DATABASE_PATH"] {
            let overrideURL = URL(fileURLWithPath: overridePath).standardizedFileURL
            let temporaryDirectoryURL = FileManager.default.temporaryDirectory.standardizedFileURL
            if overrideURL.path.hasPrefix(temporaryDirectoryURL.path + "/") {
                return overrideURL
            }
        }
#endif
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        return baseURL
            .appendingPathComponent(applicationSupportFolderName(), isDirectory: true)
            .appendingPathComponent("portfolix.sqlite3")
    }

    private static func applicationSupportFolderName() -> String {
        let fallback = "app.portfolix.mac"
        let identifier = Bundle.main.bundleIdentifier ?? fallback
        let helperSuffix = ".PriceUpdater"
        let normalizedIdentifier = identifier.hasSuffix(helperSuffix)
            ? String(identifier.dropLast(helperSuffix.count))
            : identifier
        return normalizedIdentifier.isEmpty ? fallback : normalizedIdentifier
    }

    func fetchPositions() throws -> [Position] {
        let statement = try prepare(
            """
            SELECT
                p.id,
                a.name,
                a.symbol,
                a.category,
                a.quote_currency,
                p.quantity,
                p.total_cost,
                p.average_cost,
                q.price,
                q.source,
                q.quote_time,
                q.fetched_at,
                q.freshness,
                q.weekly_trend_json
            FROM positions p
            JOIN assets a ON a.id = p.asset_id
            JOIN latest_quotes q ON q.asset_id = a.id
            ORDER BY p.created_at, a.name
            """
        )
        defer { sqlite3_finalize(statement) }

        var positions: [Position] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            positions.append(try position(from: statement))
        }
        return positions
    }

    func exportDataPayload() throws -> PortfolixDataPackage.Payload {
        let holdingStatement = try prepare(
            """
            SELECT
                p.id, a.name, a.symbol, a.category, a.quote_currency,
                p.quantity, p.total_cost, p.average_cost,
                q.price, q.source, q.quote_time, q.fetched_at, q.freshness, q.weekly_trend_json,
                p.created_at, p.updated_at
            FROM positions p
            JOIN assets a ON a.id = p.asset_id
            JOIN latest_quotes q ON q.asset_id = a.id
            ORDER BY p.created_at, a.name
            """
        )
        defer { sqlite3_finalize(holdingStatement) }

        var holdings: [PortfolixDataPackage.Holding] = []
        while sqlite3_step(holdingStatement) == SQLITE_ROW {
            guard
                let category = AssetCategory(rawValue: text(at: 3, in: holdingStatement)),
                let currency = DisplayCurrency(rawValue: text(at: 4, in: holdingStatement)),
                let quantity = Decimal(string: text(at: 5, in: holdingStatement)),
                let averageCost = Decimal(string: text(at: 7, in: holdingStatement)),
                let latestPrice = Decimal(string: text(at: 8, in: holdingStatement)),
                let trendData = text(at: 13, in: holdingStatement).data(using: .utf8),
                let weeklyTrend = try? decoder.decode([Double].self, from: trendData)
            else {
                throw PositionRepositoryError.invalidStoredData("无法导出持仓记录")
            }
            let marketValue = calculateMarketValueCNY(
                category: category,
                quantity: quantity,
                latestPrice: latestPrice,
                quoteCurrency: currency
            )
            let profitRate = averageCost == 0 ? Decimal.zero : (latestPrice - averageCost) / averageCost * 100
            holdings.append(
                PortfolixDataPackage.Holding(
                    id: text(at: 0, in: holdingStatement),
                    name: text(at: 1, in: holdingStatement),
                    symbol: text(at: 2, in: holdingStatement),
                    category: category.rawValue,
                    quoteCurrency: currency.rawValue,
                    quantity: Self.decimalString(quantity),
                    totalCost: text(at: 6, in: holdingStatement),
                    averageCost: Self.decimalString(averageCost),
                    latestPrice: Self.decimalString(latestPrice),
                    marketValueCNY: Self.decimalString(marketValue),
                    profitRate: Self.decimalString(profitRate),
                    source: text(at: 9, in: holdingStatement),
                    quoteTime: text(at: 10, in: holdingStatement),
                    fetchedAt: text(at: 11, in: holdingStatement),
                    freshness: text(at: 12, in: holdingStatement),
                    weeklyTrend: weeklyTrend,
                    createdAt: text(at: 14, in: holdingStatement),
                    updatedAt: text(at: 15, in: holdingStatement)
                )
            )
        }

        let portfolioStatement = try prepare(
            """
            SELECT snapshot_date, total_value_cny, total_cost_cny, total_profit_cny, profit_rate, updated_at
            FROM portfolio_snapshots
            ORDER BY snapshot_date ASC
            """
        )
        defer { sqlite3_finalize(portfolioStatement) }
        var portfolioSnapshots: [PortfolixDataPackage.PortfolioHistory] = []
        while sqlite3_step(portfolioStatement) == SQLITE_ROW {
            portfolioSnapshots.append(
                PortfolixDataPackage.PortfolioHistory(
                    date: text(at: 0, in: portfolioStatement),
                    totalValueCNY: text(at: 1, in: portfolioStatement),
                    totalCostCNY: text(at: 2, in: portfolioStatement),
                    totalProfitCNY: text(at: 3, in: portfolioStatement),
                    profitRate: text(at: 4, in: portfolioStatement),
                    updatedAt: text(at: 5, in: portfolioStatement)
                )
            )
        }

        let assetStatement = try prepare(
            """
            SELECT
                asset_id, snapshot_date, name, symbol, category, quote_currency,
                quantity, average_cost, latest_price, market_value_cny,
                source, quote_time, freshness, updated_at
            FROM asset_price_snapshots
            ORDER BY snapshot_date ASC, asset_id ASC
            """
        )
        defer { sqlite3_finalize(assetStatement) }
        var assetPriceSnapshots: [PortfolixDataPackage.AssetPriceHistory] = []
        while sqlite3_step(assetStatement) == SQLITE_ROW {
            assetPriceSnapshots.append(
                PortfolixDataPackage.AssetPriceHistory(
                    assetID: text(at: 0, in: assetStatement),
                    date: text(at: 1, in: assetStatement),
                    name: text(at: 2, in: assetStatement),
                    symbol: text(at: 3, in: assetStatement),
                    category: text(at: 4, in: assetStatement),
                    quoteCurrency: text(at: 5, in: assetStatement),
                    quantity: text(at: 6, in: assetStatement),
                    averageCost: text(at: 7, in: assetStatement),
                    latestPrice: text(at: 8, in: assetStatement),
                    marketValueCNY: text(at: 9, in: assetStatement),
                    source: text(at: 10, in: assetStatement),
                    quoteTime: text(at: 11, in: assetStatement),
                    freshness: text(at: 12, in: assetStatement),
                    updatedAt: text(at: 13, in: assetStatement)
                )
            )
        }

        let payload = PortfolixDataPackage.Payload(
            holdings: holdings,
            portfolioSnapshots: portfolioSnapshots,
            assetPriceSnapshots: assetPriceSnapshots
        )
        try PortfolixDataPackageService.validate(payload: payload)
        return payload
    }

    func importDataPayload(_ payload: PortfolixDataPackage.Payload) throws -> PortfolixDataTransferSummary {
        try PortfolixDataPackageService.validate(payload: payload)
        var importedIDMap: [String: String] = [:]

        try transaction {
            func resolvedAssetID(importedID: String, symbol: String, category: String) throws -> String {
                if let mappedID = importedIDMap[importedID] {
                    return mappedID
                }
                if let matchingID = try existingAssetID(symbol: symbol, category: category) {
                    importedIDMap[importedID] = matchingID
                    return matchingID
                }
                if let existingIdentity = try assetIdentity(id: importedID),
                   existingIdentity.symbol != symbol || existingIdentity.category != category {
                    let replacementID = UUID().uuidString
                    importedIDMap[importedID] = replacementID
                    return replacementID
                }
                importedIDMap[importedID] = importedID
                return importedID
            }

            for holding in payload.holdings {
                let targetID = try resolvedAssetID(
                    importedID: holding.id,
                    symbol: holding.symbol,
                    category: holding.category
                )
                try upsertImportedHolding(holding, targetID: targetID)
            }

            for snapshot in payload.portfolioSnapshots {
                let statement = try prepare(
                    """
                    INSERT INTO portfolio_snapshots (
                        snapshot_date, total_value_cny, total_cost_cny, total_profit_cny, profit_rate, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(snapshot_date) DO UPDATE SET
                        total_value_cny = excluded.total_value_cny,
                        total_cost_cny = excluded.total_cost_cny,
                        total_profit_cny = excluded.total_profit_cny,
                        profit_rate = excluded.profit_rate,
                        updated_at = excluded.updated_at
                    """
                )
                defer { sqlite3_finalize(statement) }
                try bind(snapshot.date, to: 1, in: statement)
                try bind(snapshot.totalValueCNY, to: 2, in: statement)
                try bind(snapshot.totalCostCNY, to: 3, in: statement)
                try bind(snapshot.totalProfitCNY, to: 4, in: statement)
                try bind(snapshot.profitRate, to: 5, in: statement)
                try bind(snapshot.updatedAt, to: 6, in: statement)
                try stepDone(statement)
            }

            for snapshot in payload.assetPriceSnapshots {
                let targetID = try resolvedAssetID(
                    importedID: snapshot.assetID,
                    symbol: snapshot.symbol,
                    category: snapshot.category
                )
                let statement = try prepare(
                    """
                    INSERT INTO asset_price_snapshots (
                        id, asset_id, snapshot_date, name, symbol, category, quote_currency,
                        quantity, average_cost, latest_price, market_value_cny,
                        source, quote_time, freshness, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(asset_id, snapshot_date) DO UPDATE SET
                        name = excluded.name,
                        symbol = excluded.symbol,
                        category = excluded.category,
                        quote_currency = excluded.quote_currency,
                        quantity = excluded.quantity,
                        average_cost = excluded.average_cost,
                        latest_price = excluded.latest_price,
                        market_value_cny = excluded.market_value_cny,
                        source = excluded.source,
                        quote_time = excluded.quote_time,
                        freshness = excluded.freshness,
                        updated_at = excluded.updated_at
                    """
                )
                defer { sqlite3_finalize(statement) }
                try bind("\(targetID)-\(snapshot.date)", to: 1, in: statement)
                try bind(targetID, to: 2, in: statement)
                try bind(snapshot.date, to: 3, in: statement)
                try bind(snapshot.name, to: 4, in: statement)
                try bind(snapshot.symbol, to: 5, in: statement)
                try bind(snapshot.category, to: 6, in: statement)
                try bind(snapshot.quoteCurrency, to: 7, in: statement)
                try bind(snapshot.quantity, to: 8, in: statement)
                try bind(snapshot.averageCost, to: 9, in: statement)
                try bind(snapshot.latestPrice, to: 10, in: statement)
                try bind(snapshot.marketValueCNY, to: 11, in: statement)
                try bind(snapshot.source, to: 12, in: statement)
                try bind(snapshot.quoteTime, to: 13, in: statement)
                try bind(snapshot.freshness, to: 14, in: statement)
                try bind(snapshot.updatedAt, to: 15, in: statement)
                try stepDone(statement)
            }
        }

        return PortfolixDataTransferSummary(
            holdingCount: payload.holdings.count,
            portfolioSnapshotCount: payload.portfolioSnapshots.count,
            assetPriceSnapshotCount: payload.assetPriceSnapshots.count
        )
    }

    func insert(_ position: Position) throws {
        try PositionInputValidator.validate(position)
        try transaction {
            try save(position, operation: "create")
        }
    }

    func update(_ position: Position) throws {
        try PositionInputValidator.validate(position)
        try transaction {
            try save(position, operation: "update")
        }
    }

    func delete(positionID: Position.ID) throws {
        try delete(positionIDs: [positionID])
    }

    func delete(positionIDs: [Position.ID]) throws {
        guard !positionIDs.isEmpty else { return }
        try transaction {
            for positionID in Set(positionIDs) {
                try deletePosition(id: positionID)
            }
        }
    }

    func fetchPortfolioSnapshots(limitDays: Int = 365) throws -> [PortfolioSnapshot] {
        let statement = try prepare(
            """
            SELECT snapshot_date, total_value_cny, profit_rate
            FROM portfolio_snapshots
            ORDER BY snapshot_date ASC
            LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(limitDays, to: 1, in: statement)

        var snapshots: [PortfolioSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let date = Self.date(fromDayString: text(at: 0, in: statement)),
                let totalValue = Double(text(at: 1, in: statement)),
                let profitRate = Double(text(at: 2, in: statement))
            else {
                throw PositionRepositoryError.invalidStoredData("无法解析组合快照")
            }
            snapshots.append(
                PortfolioSnapshot(
                    date: date,
                    totalValueCNY: totalValue,
                    profitRate: profitRate
                )
            )
        }
        return snapshots
    }

    func fetchAssetPriceSnapshots(
        positionID: Position.ID,
        lookbackDays: Int = 45,
        through date: Date = .now
    ) throws -> [AssetPriceSnapshotPoint] {
        let boundedLookback = max(1, min(lookbackDays, 365))
        let startDate = Calendar.current.date(byAdding: .day, value: -boundedLookback, to: date) ?? date
        let statement = try prepare(
            """
            SELECT snapshot_date, latest_price, quantity, market_value_cny
            FROM asset_price_snapshots
            WHERE asset_id = ?
              AND snapshot_date >= ?
              AND snapshot_date <= ?
            ORDER BY snapshot_date ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(positionID.uuidString, to: 1, in: statement)
        try bind(Self.dayString(from: startDate), to: 2, in: statement)
        try bind(Self.dayString(from: date), to: 3, in: statement)

        var snapshots: [AssetPriceSnapshotPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let snapshotDate = Self.date(fromDayString: text(at: 0, in: statement)),
                let latestPrice = Decimal(string: text(at: 1, in: statement)),
                let quantity = Decimal(string: text(at: 2, in: statement)),
                let marketValueCNY = Decimal(string: text(at: 3, in: statement))
            else {
                throw PositionRepositoryError.invalidStoredData("无法解析资产历史价格快照")
            }
            snapshots.append(
                AssetPriceSnapshotPoint(
                    date: snapshotDate,
                    latestPrice: latestPrice,
                    quantity: quantity,
                    marketValueCNY: marketValueCNY
                )
            )
        }
        return snapshots
    }

    func fetchDataSourceStatuses() throws -> [DataSourceStatus] {
        let statement = try prepare(
            """
            SELECT name, detail, symbol, state, color_key
            FROM data_source_health
            ORDER BY display_order ASC, name ASC
            """
        )
        defer { sqlite3_finalize(statement) }

        var statuses: [DataSourceStatus] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            statuses.append(
                DataSourceStatus(
                    name: normalizedDataSourceName(text(at: 0, in: statement)),
                    detail: text(at: 1, in: statement),
                    symbol: text(at: 2, in: statement),
                    state: text(at: 3, in: statement),
                    color: Self.statusColor(for: text(at: 4, in: statement))
                )
            )
        }
        return statuses
    }

    func replaceDataSourceStatuses(_ statuses: [DataSourceStatus]) throws {
        try transaction {
            let deleteStatement = try prepare("DELETE FROM data_source_health")
            defer { sqlite3_finalize(deleteStatement) }
            try stepDone(deleteStatement)

            for (index, status) in statuses.enumerated() {
                let statement = try prepare(
                    """
                    INSERT INTO data_source_health (
                        name, detail, symbol, state, color_key, checked_at, display_order
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """
                )
                defer { sqlite3_finalize(statement) }
                try bind(status.name, to: 1, in: statement)
                try bind(status.detail, to: 2, in: statement)
                try bind(status.symbol, to: 3, in: statement)
                try bind(status.state, to: 4, in: statement)
                try bind(Self.colorKey(for: status), to: 5, in: statement)
                try bind(Self.timestamp(), to: 6, in: statement)
                try bind(index, to: 7, in: statement)
                try stepDone(statement)
            }
        }
    }

    func setAppSetting(key: String, value: String) throws {
        let now = Self.timestamp()
        let statement = try prepare(
            """
            INSERT INTO app_settings (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(key, to: 1, in: statement)
        try bind(value, to: 2, in: statement)
        try bind(now, to: 3, in: statement)
        try stepDone(statement)
    }

    func appSetting(for key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM app_settings WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(key, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return text(at: 0, in: statement)
    }

    func deleteAppSetting(key: String) throws {
        let statement = try prepare("DELETE FROM app_settings WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(key, to: 1, in: statement)
        try stepDone(statement)
    }

    func insertAIAnalysisRun(_ run: PersistedAIAnalysisRun) throws {
        try transaction {
            let runStatement = try prepare(
                """
                INSERT INTO ai_analysis_runs (
                    id, trigger, status, analysis_mode, model, provider, privacy_mode,
                    risk_profile_version, input_fingerprint, started_at, finished_at,
                    used_fallback, error_code, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            )
            defer { sqlite3_finalize(runStatement) }
            try bind(run.id.uuidString, to: 1, in: runStatement)
            try bind(run.trigger, to: 2, in: runStatement)
            try bind(run.status, to: 3, in: runStatement)
            try bind(run.analysisMode, to: 4, in: runStatement)
            try bind(run.model, to: 5, in: runStatement)
            try bind(run.provider, to: 6, in: runStatement)
            try bind(run.privacyMode, to: 7, in: runStatement)
            try bind(run.riskProfileVersion, to: 8, in: runStatement)
            try bind(run.inputFingerprint, to: 9, in: runStatement)
            try bind(Self.timestamp(from: run.startedAt), to: 10, in: runStatement)
            try bindOptional(run.finishedAt.map { Self.timestamp(from: $0) }, to: 11, in: runStatement)
            try bind(run.usedFallback ? 1 : 0, to: 12, in: runStatement)
            try bindOptional(run.errorCode, to: 13, in: runStatement)
            try bind(Self.timestamp(), to: 14, in: runStatement)
            try stepDone(runStatement)

            if let artifacts = run.artifacts {
                let artifactsStatement = try prepare(
                    """
                    INSERT INTO ai_analysis_artifacts (
                        run_id, input_json, research_results_json, research_brief_json,
                        raw_report_json, repaired_report_json, final_report_json,
                        guardrail_result_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """
                )
                defer { sqlite3_finalize(artifactsStatement) }
                try bind(run.id.uuidString, to: 1, in: artifactsStatement)
                try bind(artifacts.inputJSON, to: 2, in: artifactsStatement)
                try bind(artifacts.toolResultsJSON, to: 3, in: artifactsStatement)
                try bind(artifacts.toolPlanJSON, to: 4, in: artifactsStatement)
                try bind(artifacts.rawReportJSON, to: 5, in: artifactsStatement)
                try bindOptional(artifacts.repairedReportJSON, to: 6, in: artifactsStatement)
                try bind(artifacts.finalReportJSON, to: 7, in: artifactsStatement)
                try bind(artifacts.guardrailResultJSON, to: 8, in: artifactsStatement)
                try stepDone(artifactsStatement)

                let guardrailStatement = try prepare(
                    """
                    INSERT INTO ai_guardrail_results (
                        id, run_id, validator, status, result_json, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """
                )
                defer { sqlite3_finalize(guardrailStatement) }
                try bind(UUID().uuidString, to: 1, in: guardrailStatement)
                try bind(run.id.uuidString, to: 2, in: guardrailStatement)
                try bind("AIAnalysisAgent.validate", to: 3, in: guardrailStatement)
                try bind(run.usedFallback ? "fallback" : "passed", to: 4, in: guardrailStatement)
                try bind(artifacts.guardrailResultJSON, to: 5, in: guardrailStatement)
                try bind(Self.timestamp(), to: 6, in: guardrailStatement)
                try stepDone(guardrailStatement)
            }

            if let report = run.report {
                let reportJSON = String(data: try aiArtifactEncoder.encode(report), encoding: .utf8) ?? "{}"
                let reportStatement = try prepare(
                    """
                    INSERT INTO ai_analysis_reports (
                        id, run_id, prompt_version, risk_profile_version,
                        generated_at, report_json
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """
                )
                defer { sqlite3_finalize(reportStatement) }
                try bind(report.id.uuidString, to: 1, in: reportStatement)
                try bind(run.id.uuidString, to: 2, in: reportStatement)
                try bind(report.promptVersion, to: 3, in: reportStatement)
                try bind(report.riskProfileVersion, to: 4, in: reportStatement)
                try bind(Self.timestamp(from: report.generatedAt), to: 5, in: reportStatement)
                try bind(reportJSON, to: 6, in: reportStatement)
                try stepDone(reportStatement)

                for source in report.sources {
                    let sourceStatement = try prepare(
                        """
                        INSERT INTO ai_analysis_sources (
                            id, run_id, report_id, title, url, domain,
                            asset_name, credibility
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """
                    )
                    defer { sqlite3_finalize(sourceStatement) }
                    try bind(source.id.uuidString, to: 1, in: sourceStatement)
                    try bind(run.id.uuidString, to: 2, in: sourceStatement)
                    try bind(report.id.uuidString, to: 3, in: sourceStatement)
                    try bind(source.title, to: 4, in: sourceStatement)
                    try bind(source.url, to: 5, in: sourceStatement)
                    try bind(source.domain, to: 6, in: sourceStatement)
                    try bind(source.assetName, to: 7, in: sourceStatement)
                    try bind(source.credibility.rawValue, to: 8, in: sourceStatement)
                    try stepDone(sourceStatement)
                }
            }
        }
    }

    func fetchLatestAIAnalysisReport() throws -> AIAnalysisReport? {
        let statement = try prepare(
            """
            SELECT report_json
            FROM ai_analysis_reports
            ORDER BY generated_at DESC
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        guard let data = text(at: 0, in: statement).data(using: .utf8) else {
            throw PositionRepositoryError.invalidStoredData("无法解析 AI 报告 JSON")
        }
        return try aiArtifactDecoder.decode(AIAnalysisReport.self, from: data)
    }

    func fetchAIAnalysisRunCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM ai_analysis_runs")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw currentError()
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    func fetchAIAnalysisArtifacts(runID: UUID) throws -> AIAnalysisArtifactBundle? {
        let statement = try prepare(
            """
            SELECT input_json, research_results_json, research_brief_json,
                   raw_report_json, repaired_report_json, final_report_json,
                   guardrail_result_json
            FROM ai_analysis_artifacts
            WHERE run_id = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(runID.uuidString, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return AIAnalysisArtifactBundle(
            inputJSON: text(at: 0, in: statement),
            toolResultsJSON: text(at: 1, in: statement),
            toolPlanJSON: text(at: 2, in: statement),
            rawReportJSON: text(at: 3, in: statement),
            repairedReportJSON: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : text(at: 4, in: statement),
            finalReportJSON: text(at: 5, in: statement),
            guardrailResultJSON: text(at: 6, in: statement)
        )
    }

    func fetchLatestAIAnalysisArtifacts() throws -> AIAnalysisArtifactBundle? {
        let statement = try prepare(
            """
            SELECT artifacts.input_json, artifacts.research_results_json,
                   artifacts.research_brief_json, artifacts.raw_report_json,
                   artifacts.repaired_report_json, artifacts.final_report_json,
                   artifacts.guardrail_result_json
            FROM ai_analysis_artifacts artifacts
            INNER JOIN ai_analysis_runs runs ON runs.id = artifacts.run_id
            ORDER BY runs.created_at DESC
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return AIAnalysisArtifactBundle(
            inputJSON: text(at: 0, in: statement),
            toolResultsJSON: text(at: 1, in: statement),
            toolPlanJSON: text(at: 2, in: statement),
            rawReportJSON: text(at: 3, in: statement),
            repairedReportJSON: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : text(at: 4, in: statement),
            finalReportJSON: text(at: 5, in: statement),
            guardrailResultJSON: text(at: 6, in: statement)
        )
    }

    func upsertAIAnalysisChatItem(_ item: AIReportChatItem) throws {
        let payload = String(data: try aiArtifactEncoder.encode(item), encoding: .utf8) ?? "{}"
        let statement = try prepare(
            """
            INSERT INTO ai_analysis_chat_messages (id, created_at, payload_json)
            VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                created_at = excluded.created_at,
                payload_json = excluded.payload_json
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(item.id.uuidString, to: 1, in: statement)
        try bind(Self.timestamp(from: item.createdAt), to: 2, in: statement)
        try bind(payload, to: 3, in: statement)
        try stepDone(statement)
    }

    func fetchAIAnalysisChatItems(since cutoff: Date) throws -> [AIReportChatItem] {
        let statement = try prepare(
            """
            SELECT payload_json
            FROM ai_analysis_chat_messages
            WHERE created_at >= ?
            ORDER BY created_at ASC, id ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(Self.timestamp(from: cutoff), to: 1, in: statement)

        var items: [AIReportChatItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let data = text(at: 0, in: statement).data(using: .utf8) else {
                continue
            }
            if let item = try? aiArtifactDecoder.decode(AIReportChatItem.self, from: data) {
                items.append(item)
            }
        }
        return items
    }

    func deleteAIAnalysisChatItems(before cutoff: Date) throws {
        let statement = try prepare("DELETE FROM ai_analysis_chat_messages WHERE created_at < ?")
        defer { sqlite3_finalize(statement) }
        try bind(Self.timestamp(from: cutoff), to: 1, in: statement)
        try stepDone(statement)
    }

    func deleteAIAnalysisRuns(before cutoff: Date) throws {
        let statement = try prepare("DELETE FROM ai_analysis_runs WHERE started_at < ?")
        defer { sqlite3_finalize(statement) }
        try bind(Self.timestamp(from: cutoff), to: 1, in: statement)
        try stepDone(statement)
    }

    func deleteExpiredAIAnalysisContent(before cutoff: Date) throws {
        try transaction {
            try deleteAIAnalysisChatItems(before: cutoff)
            try deleteAIAnalysisRuns(before: cutoff)
        }
    }

    func replaceDailySnapshots(positions: [Position], snapshotDate: Date = .now) throws {
        let day = Self.dayString(from: snapshotDate)
        let cutoff = Self.dayString(
            from: Calendar.current.date(byAdding: .day, value: -365, to: snapshotDate) ?? snapshotDate
        )
        let now = Self.timestamp()
        let totalValue = positions.reduce(Decimal.zero) { $0 + $1.marketValueCNY }
        let totalCost = positions.reduce(Decimal.zero) {
            $0 + calculateTotalCostCNY(
                category: $1.category,
                quantity: $1.quantity,
                averageCost: $1.averageCost,
                quoteCurrency: $1.quoteCurrency
            )
        }
        let totalProfit = totalValue - totalCost
        let profitRate = totalCost == 0 ? Decimal.zero : totalProfit / totalCost * 100

        try transaction {
            let portfolioStatement = try prepare(
                """
                INSERT INTO portfolio_snapshots (
                    snapshot_date, total_value_cny, total_cost_cny, total_profit_cny, profit_rate, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(snapshot_date) DO UPDATE SET
                    total_value_cny = excluded.total_value_cny,
                    total_cost_cny = excluded.total_cost_cny,
                    total_profit_cny = excluded.total_profit_cny,
                    profit_rate = excluded.profit_rate,
                    updated_at = excluded.updated_at
                """
            )
            defer { sqlite3_finalize(portfolioStatement) }
            try bind(day, to: 1, in: portfolioStatement)
            try bind(Self.decimalString(totalValue), to: 2, in: portfolioStatement)
            try bind(Self.decimalString(totalCost), to: 3, in: portfolioStatement)
            try bind(Self.decimalString(totalProfit), to: 4, in: portfolioStatement)
            try bind(Self.decimalString(profitRate), to: 5, in: portfolioStatement)
            try bind(now, to: 6, in: portfolioStatement)
            try stepDone(portfolioStatement)

            for position in positions {
                let statement = try prepare(
                    """
                    INSERT INTO asset_price_snapshots (
                        id, asset_id, snapshot_date, name, symbol, category, quote_currency,
                        quantity, average_cost, latest_price, market_value_cny,
                        source, quote_time, freshness, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(asset_id, snapshot_date) DO UPDATE SET
                        name = excluded.name,
                        symbol = excluded.symbol,
                        category = excluded.category,
                        quote_currency = excluded.quote_currency,
                        quantity = excluded.quantity,
                        average_cost = excluded.average_cost,
                        latest_price = excluded.latest_price,
                        market_value_cny = excluded.market_value_cny,
                        source = excluded.source,
                        quote_time = excluded.quote_time,
                        freshness = excluded.freshness,
                        updated_at = excluded.updated_at
                    """
                )
                defer { sqlite3_finalize(statement) }
                try bind("\(position.id.uuidString)-\(day)", to: 1, in: statement)
                try bind(position.id.uuidString, to: 2, in: statement)
                try bind(day, to: 3, in: statement)
                try bind(position.name, to: 4, in: statement)
                try bind(position.symbol, to: 5, in: statement)
                try bind(position.category.rawValue, to: 6, in: statement)
                try bind(position.quoteCurrency.rawValue, to: 7, in: statement)
                try bind(Self.decimalString(position.quantity), to: 8, in: statement)
                try bind(Self.decimalString(position.averageCost), to: 9, in: statement)
                try bind(Self.decimalString(position.latestPrice), to: 10, in: statement)
                try bind(Self.decimalString(position.marketValueCNY), to: 11, in: statement)
                try bind(position.source, to: 12, in: statement)
                try bind(position.quoteTime, to: 13, in: statement)
                try bind(position.freshness.rawValue, to: 14, in: statement)
                try bind(now, to: 15, in: statement)
                try stepDone(statement)
            }

            try pruneSnapshots(olderThan: cutoff)
        }
    }

    private func deletePosition(id positionID: Position.ID) throws {
        guard let position = try fetchPosition(id: positionID) else { return }
        try insertRevision(position: position, operation: "delete")

        let statement = try prepare("DELETE FROM positions WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(positionID.uuidString, to: 1, in: statement)
        try stepDone(statement)

        let quoteStatement = try prepare("DELETE FROM latest_quotes WHERE asset_id = ?")
        defer { sqlite3_finalize(quoteStatement) }
        try bind(positionID.uuidString, to: 1, in: quoteStatement)
        try stepDone(quoteStatement)

        let assetStatement = try prepare("DELETE FROM assets WHERE id = ?")
        defer { sqlite3_finalize(assetStatement) }
        try bind(positionID.uuidString, to: 1, in: assetStatement)
        try stepDone(assetStatement)
    }

    private func configure() throws {
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS assets (
                id TEXT PRIMARY KEY NOT NULL,
                symbol TEXT NOT NULL,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                quote_currency TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(symbol, category)
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS positions (
                id TEXT PRIMARY KEY NOT NULL,
                asset_id TEXT NOT NULL UNIQUE REFERENCES assets(id),
                quantity TEXT NOT NULL,
                total_cost TEXT NOT NULL,
                average_cost TEXT NOT NULL,
                cost_currency TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS latest_quotes (
                asset_id TEXT PRIMARY KEY NOT NULL REFERENCES assets(id),
                price TEXT NOT NULL,
                currency TEXT NOT NULL,
                source TEXT NOT NULL,
                quote_time TEXT NOT NULL,
                fetched_at TEXT NOT NULL,
                freshness TEXT NOT NULL,
                weekly_trend_json TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS position_revisions (
                id TEXT PRIMARY KEY NOT NULL,
                position_id TEXT NOT NULL,
                operation TEXT NOT NULL,
                snapshot_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS portfolio_snapshots (
                snapshot_date TEXT PRIMARY KEY NOT NULL,
                total_value_cny TEXT NOT NULL,
                total_cost_cny TEXT NOT NULL,
                total_profit_cny TEXT NOT NULL,
                profit_rate TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS asset_price_snapshots (
                id TEXT PRIMARY KEY NOT NULL,
                asset_id TEXT NOT NULL,
                snapshot_date TEXT NOT NULL,
                name TEXT NOT NULL,
                symbol TEXT NOT NULL,
                category TEXT NOT NULL,
                quote_currency TEXT NOT NULL,
                quantity TEXT NOT NULL,
                average_cost TEXT NOT NULL,
                latest_price TEXT NOT NULL,
                market_value_cny TEXT NOT NULL,
                source TEXT NOT NULL,
                quote_time TEXT NOT NULL,
                freshness TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(asset_id, snapshot_date)
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS data_source_health (
                name TEXT PRIMARY KEY NOT NULL,
                detail TEXT NOT NULL,
                symbol TEXT NOT NULL,
                state TEXT NOT NULL,
                color_key TEXT NOT NULL,
                checked_at TEXT NOT NULL,
                display_order INTEGER NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ai_analysis_runs (
                id TEXT PRIMARY KEY NOT NULL,
                trigger TEXT NOT NULL,
                status TEXT NOT NULL,
                analysis_mode TEXT NOT NULL,
                model TEXT NOT NULL,
                provider TEXT NOT NULL,
                privacy_mode TEXT NOT NULL,
                risk_profile_version INTEGER NOT NULL,
                input_fingerprint TEXT NOT NULL,
                started_at TEXT NOT NULL,
                finished_at TEXT,
                used_fallback INTEGER NOT NULL,
                error_code TEXT,
                created_at TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ai_analysis_artifacts (
                run_id TEXT PRIMARY KEY NOT NULL REFERENCES ai_analysis_runs(id) ON DELETE CASCADE,
                input_json TEXT NOT NULL,
                research_results_json TEXT NOT NULL,
                research_brief_json TEXT NOT NULL,
                raw_report_json TEXT NOT NULL,
                repaired_report_json TEXT,
                final_report_json TEXT NOT NULL,
                guardrail_result_json TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ai_analysis_reports (
                id TEXT PRIMARY KEY NOT NULL,
                run_id TEXT NOT NULL REFERENCES ai_analysis_runs(id) ON DELETE CASCADE,
                prompt_version TEXT NOT NULL,
                risk_profile_version INTEGER NOT NULL,
                generated_at TEXT NOT NULL,
                report_json TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ai_analysis_sources (
                id TEXT PRIMARY KEY NOT NULL,
                run_id TEXT NOT NULL REFERENCES ai_analysis_runs(id) ON DELETE CASCADE,
                report_id TEXT NOT NULL REFERENCES ai_analysis_reports(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                url TEXT NOT NULL,
                domain TEXT NOT NULL,
                asset_name TEXT NOT NULL,
                credibility TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ai_guardrail_results (
                id TEXT PRIMARY KEY NOT NULL,
                run_id TEXT NOT NULL REFERENCES ai_analysis_runs(id) ON DELETE CASCADE,
                validator TEXT NOT NULL,
                status TEXT NOT NULL,
                result_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ai_analysis_chat_messages (
                id TEXT PRIMARY KEY NOT NULL,
                created_at TEXT NOT NULL,
                payload_json TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_assets_search
            ON assets(name, symbol)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_position_revisions_position
            ON position_revisions(position_id, created_at)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_asset_price_snapshots_day
            ON asset_price_snapshots(snapshot_date)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_ai_analysis_runs_created
            ON ai_analysis_runs(created_at)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_ai_analysis_reports_generated
            ON ai_analysis_reports(generated_at)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_ai_analysis_chat_created
            ON ai_analysis_chat_messages(created_at)
            """
        )
    }

    private func save(_ position: Position, operation: String) throws {
        let now = Self.timestamp()
        let assetStatement = try prepare(
            """
            INSERT INTO assets (
                id, symbol, name, category, quote_currency, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                symbol = excluded.symbol,
                name = excluded.name,
                category = excluded.category,
                quote_currency = excluded.quote_currency,
                updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(assetStatement) }
        try bind(position.id.uuidString, to: 1, in: assetStatement)
        try bind(position.symbol, to: 2, in: assetStatement)
        try bind(position.name, to: 3, in: assetStatement)
        try bind(position.category.rawValue, to: 4, in: assetStatement)
        try bind(position.quoteCurrency.rawValue, to: 5, in: assetStatement)
        try bind(now, to: 6, in: assetStatement)
        try bind(now, to: 7, in: assetStatement)
        try stepDone(assetStatement)

        let positionStatement = try prepare(
            """
            INSERT INTO positions (
                id, asset_id, quantity, total_cost, average_cost, cost_currency, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                quantity = excluded.quantity,
                total_cost = excluded.total_cost,
                average_cost = excluded.average_cost,
                cost_currency = excluded.cost_currency,
                updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(positionStatement) }
        try bind(position.id.uuidString, to: 1, in: positionStatement)
        try bind(position.id.uuidString, to: 2, in: positionStatement)
        try bind(Self.decimalString(position.quantity), to: 3, in: positionStatement)
        try bind(Self.decimalString(position.totalCost), to: 4, in: positionStatement)
        try bind(Self.decimalString(position.averageCost), to: 5, in: positionStatement)
        try bind(position.quoteCurrency.rawValue, to: 6, in: positionStatement)
        try bind(now, to: 7, in: positionStatement)
        try bind(now, to: 8, in: positionStatement)
        try stepDone(positionStatement)

        let trendJSON = String(data: try encoder.encode(position.weeklyTrend), encoding: .utf8) ?? "[]"
        let quoteStatement = try prepare(
            """
            INSERT INTO latest_quotes (
                asset_id, price, currency, source, quote_time, fetched_at, freshness, weekly_trend_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                price = excluded.price,
                currency = excluded.currency,
                source = excluded.source,
                quote_time = excluded.quote_time,
                fetched_at = excluded.fetched_at,
                freshness = excluded.freshness,
                weekly_trend_json = excluded.weekly_trend_json
            """
        )
        defer { sqlite3_finalize(quoteStatement) }
        try bind(position.id.uuidString, to: 1, in: quoteStatement)
        try bind(Self.decimalString(position.latestPrice), to: 2, in: quoteStatement)
        try bind(position.quoteCurrency.rawValue, to: 3, in: quoteStatement)
        try bind(position.source, to: 4, in: quoteStatement)
        try bind(position.quoteTime, to: 5, in: quoteStatement)
        try bind(now, to: 6, in: quoteStatement)
        try bind(position.freshness.rawValue, to: 7, in: quoteStatement)
        try bind(trendJSON, to: 8, in: quoteStatement)
        try stepDone(quoteStatement)

        try insertRevision(position: position, operation: operation)
    }

    private func upsertImportedHolding(_ holding: PortfolixDataPackage.Holding, targetID: String) throws {
        let assetStatement = try prepare(
            """
            INSERT INTO assets (
                id, symbol, name, category, quote_currency, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                symbol = excluded.symbol,
                name = excluded.name,
                category = excluded.category,
                quote_currency = excluded.quote_currency,
                updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(assetStatement) }
        try bind(targetID, to: 1, in: assetStatement)
        try bind(holding.symbol, to: 2, in: assetStatement)
        try bind(holding.name, to: 3, in: assetStatement)
        try bind(holding.category, to: 4, in: assetStatement)
        try bind(holding.quoteCurrency, to: 5, in: assetStatement)
        try bind(holding.createdAt, to: 6, in: assetStatement)
        try bind(holding.updatedAt, to: 7, in: assetStatement)
        try stepDone(assetStatement)

        let positionStatement = try prepare(
            """
            INSERT INTO positions (
                id, asset_id, quantity, total_cost, average_cost, cost_currency, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                quantity = excluded.quantity,
                total_cost = excluded.total_cost,
                average_cost = excluded.average_cost,
                cost_currency = excluded.cost_currency,
                updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(positionStatement) }
        try bind(targetID, to: 1, in: positionStatement)
        try bind(targetID, to: 2, in: positionStatement)
        try bind(holding.quantity, to: 3, in: positionStatement)
        try bind(holding.totalCost, to: 4, in: positionStatement)
        try bind(holding.averageCost, to: 5, in: positionStatement)
        try bind(holding.quoteCurrency, to: 6, in: positionStatement)
        try bind(holding.createdAt, to: 7, in: positionStatement)
        try bind(holding.updatedAt, to: 8, in: positionStatement)
        try stepDone(positionStatement)

        let trendData = try encoder.encode(holding.weeklyTrend)
        let trendJSON = String(data: trendData, encoding: .utf8) ?? "[]"
        let quoteStatement = try prepare(
            """
            INSERT INTO latest_quotes (
                asset_id, price, currency, source, quote_time, fetched_at, freshness, weekly_trend_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                price = excluded.price,
                currency = excluded.currency,
                source = excluded.source,
                quote_time = excluded.quote_time,
                fetched_at = excluded.fetched_at,
                freshness = excluded.freshness,
                weekly_trend_json = excluded.weekly_trend_json
            """
        )
        defer { sqlite3_finalize(quoteStatement) }
        try bind(targetID, to: 1, in: quoteStatement)
        try bind(holding.latestPrice, to: 2, in: quoteStatement)
        try bind(holding.quoteCurrency, to: 3, in: quoteStatement)
        try bind(holding.source, to: 4, in: quoteStatement)
        try bind(holding.quoteTime, to: 5, in: quoteStatement)
        try bind(holding.fetchedAt, to: 6, in: quoteStatement)
        try bind(holding.freshness, to: 7, in: quoteStatement)
        try bind(trendJSON, to: 8, in: quoteStatement)
        try stepDone(quoteStatement)
    }

    private func existingAssetID(symbol: String, category: String) throws -> String? {
        let statement = try prepare("SELECT id FROM assets WHERE symbol = ? AND category = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        try bind(symbol, to: 1, in: statement)
        try bind(category, to: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(at: 0, in: statement)
    }

    private func assetIdentity(id: String) throws -> (symbol: String, category: String)? {
        let statement = try prepare("SELECT symbol, category FROM assets WHERE id = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        try bind(id, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return (text(at: 0, in: statement), text(at: 1, in: statement))
    }

    private func insertRevision(position: Position, operation: String) throws {
        let snapshot = PositionRevisionSnapshot(
            name: position.name,
            symbol: position.symbol,
            category: position.category.rawValue,
            quantity: Self.decimalString(position.quantity),
            totalCost: Self.decimalString(position.totalCost),
            averageCost: Self.decimalString(position.averageCost),
            costCurrency: position.quoteCurrency.rawValue
        )
        let snapshotJSON = String(data: try encoder.encode(snapshot), encoding: .utf8) ?? "{}"
        let statement = try prepare(
            """
            INSERT INTO position_revisions (
                id, position_id, operation, snapshot_json, created_at
            ) VALUES (?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(UUID().uuidString, to: 1, in: statement)
        try bind(position.id.uuidString, to: 2, in: statement)
        try bind(operation, to: 3, in: statement)
        try bind(snapshotJSON, to: 4, in: statement)
        try bind(Self.timestamp(), to: 5, in: statement)
        try stepDone(statement)
    }

    private func pruneSnapshots(olderThan cutoff: String) throws {
        let portfolioStatement = try prepare("DELETE FROM portfolio_snapshots WHERE snapshot_date < ?")
        defer { sqlite3_finalize(portfolioStatement) }
        try bind(cutoff, to: 1, in: portfolioStatement)
        try stepDone(portfolioStatement)

        let assetStatement = try prepare("DELETE FROM asset_price_snapshots WHERE snapshot_date < ?")
        defer { sqlite3_finalize(assetStatement) }
        try bind(cutoff, to: 1, in: assetStatement)
        try stepDone(assetStatement)
    }

    private func fetchPosition(id: Position.ID) throws -> Position? {
        let statement = try prepare(
            """
            SELECT
                p.id,
                a.name,
                a.symbol,
                a.category,
                a.quote_currency,
                p.quantity,
                p.total_cost,
                p.average_cost,
                q.price,
                q.source,
                q.quote_time,
                q.fetched_at,
                q.freshness,
                q.weekly_trend_json
            FROM positions p
            JOIN assets a ON a.id = p.asset_id
            JOIN latest_quotes q ON q.asset_id = a.id
            WHERE p.id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try position(from: statement)
    }

    private func position(from statement: OpaquePointer) throws -> Position {
        guard
            let id = UUID(uuidString: text(at: 0, in: statement)),
            let category = AssetCategory(rawValue: text(at: 3, in: statement)),
            let currency = DisplayCurrency(rawValue: text(at: 4, in: statement)),
            let quantity = Decimal(string: text(at: 5, in: statement)),
            let totalCost = Decimal(string: text(at: 6, in: statement)),
            let averageCost = Decimal(string: text(at: 7, in: statement)),
            let latestPrice = Decimal(string: text(at: 8, in: statement)),
            let freshness = Freshness(rawValue: text(at: 12, in: statement))
        else {
            throw PositionRepositoryError.invalidStoredData("无法解析持仓记录")
        }

        let weeklyTrend = try weeklyTrend(for: id, latestPrice: latestPrice)
        return Position(
            id: id,
            name: text(at: 1, in: statement),
            symbol: text(at: 2, in: statement),
            category: category,
            quoteCurrency: currency,
            quantity: quantity,
            totalCost: totalCost,
            averageCost: averageCost,
            latestPrice: latestPrice,
            marketValueCNY: calculateMarketValueCNY(
                category: category,
                quantity: quantity,
                latestPrice: latestPrice,
                quoteCurrency: currency
            ),
            profitRate: averageCost == 0 ? 0 : (latestPrice - averageCost) / averageCost * 100,
            weeklyTrend: weeklyTrend,
            source: normalizedQuoteSource(text(at: 9, in: statement), category: category),
            quoteTime: text(at: 10, in: statement),
            fetchedAt: text(at: 11, in: statement),
            freshness: freshness
        )
    }

    private func weeklyTrend(for assetID: UUID, latestPrice: Decimal) throws -> [Double] {
        let statement = try prepare(
            """
            SELECT latest_price
            FROM asset_price_snapshots
            WHERE asset_id = ?
              AND snapshot_date >= date('now', '-6 day')
            ORDER BY snapshot_date ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(assetID.uuidString, to: 1, in: statement)

        var trend: [Double] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let price = Decimal(string: text(at: 0, in: statement)) else {
                throw PositionRepositoryError.invalidStoredData("无法解析资产价格快照")
            }
            trend.append(price.doubleValue)
        }
        return trend.isEmpty ? [latestPrice.doubleValue] : trend
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(errorMessage)
            throw PositionRepositoryError.database(message)
        }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        defer { try? applyDatabaseFilePermissions() }
        do {
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func applyDatabaseFilePermissions() throws {
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }

    private static func applyDirectoryPermissions(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw currentError()
        }
        return statement
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw currentError()
        }
    }

    private func bindOptional(_ value: String?, to index: Int32, in statement: OpaquePointer) throws {
        if let value {
            try bind(value, to: index, in: statement)
            return
        }
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
            throw currentError()
        }
    }

    private func bind(_ value: Int, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int(statement, index, Int32(value)) == SQLITE_OK else {
            throw currentError()
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw currentError()
        }
    }

    private func text(at index: Int32, in statement: OpaquePointer) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func currentError() -> PositionRepositoryError {
        .database(String(cString: sqlite3_errmsg(database)))
    }

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: .now)
    }

    private static func timestamp(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func colorKey(for status: DataSourceStatus) -> String {
        switch status.state {
        case "可用", "连接正常":
            "mint"
        case "不可用", "未使用", "连接异常", "部分异常", "待检查":
            "danger"
        default:
            "danger"
        }
    }

    private static func statusColor(for key: String) -> Color {
        switch key {
        case "mint":
            PortfolixTheme.mint
        case "lilac":
            PortfolixTheme.lilac
        case "tertiary":
            PortfolixTheme.tertiaryText
        case "danger":
            PortfolixTheme.danger
        default:
            PortfolixTheme.amber
        }
    }

    private static func dayString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private static func date(fromDayString value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }
}

private struct PositionRevisionSnapshot: Encodable {
    let name: String
    let symbol: String
    let category: String
    let quantity: String
    let totalCost: String
    let averageCost: String
    let costCurrency: String
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
