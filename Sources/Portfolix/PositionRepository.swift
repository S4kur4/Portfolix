import CSQLite
import Foundation
import PortfolixCore

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

    var storageURL: URL { databaseURL }
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
        try migrateOpeningBalances()
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

        let costStates = Dictionary(grouping: try fetchReconciliations().filter { !$0.isReversed }, by: { $0.asset.id }).mapValues { $0.max { $0.sequence < $1.sequence }!.costKnown }
        var positions: [Position] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            positions.append(try position(from: statement, knownCost: costStates[text(at: 0, in: statement)] ?? true))
        }
        return positions
    }

    func exportDataPayload(
        riskProfile: PortfolixDataPackage.RiskProfile? = nil
    ) throws -> PortfolixDataPackage.Payload {
        try migrateOpeningBalances()
        let reconciliationRecords = try reconciliationInputs()
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
                    updatedAt: text(at: 15, in: holdingStatement),
                    costKnown: try UUID(uuidString: text(at: 0, in: holdingStatement)).map { try costIsKnown(for: $0) ? nil : false } ?? nil
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
                    updatedAt: text(at: 5, in: portfolioStatement),
                    costKnown: try snapshotCostIsKnown(day: text(at: 0, in: portfolioStatement), records: reconciliationRecords) ? nil : false
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
                    updatedAt: text(at: 13, in: assetStatement),
                    costKnown: RecordedReconciliation.costKnown(reconciliationRecords, assetID: text(at: 0, in: assetStatement), through: text(at: 1, in: assetStatement)) ? nil : false
                )
            )
        }

        let payload = PortfolixDataPackage.Payload(
            holdings: holdings,
            portfolioSnapshots: portfolioSnapshots,
            assetPriceSnapshots: assetPriceSnapshots,
            riskProfile: try riskProfile ?? storedRiskProfile(),
            closedHoldings: try fetchPositionClosures(),
            trades: try fetchPositionTrades(),
            openingBalances: try fetchOpeningBalances(),
            reconciliations: try fetchReconciliations()
        )
        try PortfolixDataPackageService.validate(payload: payload, requiresRiskProfile: true)
        return payload
    }

    func importDataPayload(_ payload: PortfolixDataPackage.Payload) throws -> PortfolixDataTransferSummary {
        try PortfolixDataPackageService.validate(payload: payload)
        var importedIDMap: [String: String] = [:]
        let archivedIDs = Set((payload.closedHoldings ?? []).filter { !$0.isReversed }.map { $0.holding.id })
        let activeImportIDs = Set(payload.holdings.map(\.id))
        let historicalTradeIDs = Set((payload.trades ?? []).flatMap { $0.accountIDs } + (payload.reconciliations ?? []).map { $0.asset.id }).subtracting(activeImportIDs)
        let reversedOpeningIDs = Set((payload.openingBalances ?? []).filter { $0.isReversed && !activeImportIDs.contains($0.holding.id) }.map { $0.holding.id })
        let existingClosedIDs = Set(try fetchPositionClosures().filter { !$0.isReversed }.map { $0.holding.id })

        try transaction {
            let incomingReconciliations = payload.reconciliations ?? []
            guard Set(try fetchReconciliations().map(\.id)).isSubset(of: Set(incomingReconciliations.map(\.id))) else {
                throw PortfolixDataPackageError.invalidPackage("当前校准记录与备份不一致，不能合并覆盖余额")
            }
            let existingTrades = try fetchPositionTrades()
            let incomingTradeIDs = Set((payload.trades ?? []).map(\.id))
            guard Set(existingTrades.map(\.id)).isSubset(of: incomingTradeIDs) else {
                throw PortfolixDataPackageError.invalidPackage("当前交易记录与备份不一致，不能合并覆盖余额")
            }
            for id in archivedIDs.union(historicalTradeIDs).union(reversedOpeningIDs) {
                if let uuid = UUID(uuidString: id), try fetchPosition(id: uuid) != nil {
                    try removeActiveClosurePosition(id: uuid)
                }
                try deleteClosureAssetSnapshots(id: id, from: "1970-01-01")
            }
            func resolvedAssetID(importedID: String, symbol: String, category: String) throws -> String {
                if let mappedID = importedIDMap[importedID] {
                    return mappedID
                }
                if archivedIDs.contains(importedID) || historicalTradeIDs.contains(importedID) {
                    importedIDMap[importedID] = importedID
                    return importedID
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
                guard !existingClosedIDs.contains(holding.id) else { throw PositionClosureError.invalidRecord }
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

            for closure in payload.closedHoldings ?? [] {
                try savePositionClosure(closure.remapping(
                    positionID: importedIDMap[closure.holding.id] ?? closure.holding.id,
                    cashPositionID: closure.cashPositionID.map { importedIDMap[$0] ?? $0 }))
            }

            // Restoring a backup restores balances and the audit trail, never executes its cash flows again.
            for trade in payload.trades ?? [] {
                if importedIDMap[trade.asset.id] == nil {
                    importedIDMap[trade.asset.id] = trade.asset.id
                }
                if let cash = trade.cash, importedIDMap[cash.id] == nil {
                    importedIDMap[cash.id] = cash.id
                }
                try saveTrade(trade.remapping(importedIDMap))
            }

            for record in incomingReconciliations {
                try saveReconciliation(record.remapping(importedIDMap))
            }
            for opening in payload.openingBalances ?? [] {
                try saveOpeningBalance(opening.remapping(importedIDMap))
            }
            let suppliedOpeningIDs = Set(try (payload.openingBalances ?? []).map { try $0.remapping(importedIDMap).id })
            let importedHoldingIDs = Set(payload.holdings.compactMap { UUID(uuidString: importedIDMap[$0.id] ?? $0.id) })
            try ensureOpeningBalances(replacing: importedHoldingIDs.subtracting(suppliedOpeningIDs))

            if let riskProfile = payload.riskProfile {
                try setAppSetting(
                    key: RiskProfilePersistence.configuredKey,
                    value: riskProfile.configured ? "true" : "false"
                )
                try setAppSetting(key: RiskProfilePersistence.levelKey, value: riskProfile.level)
                try setAppSetting(key: RiskProfilePersistence.versionKey, value: String(riskProfile.version))
                try setAppSetting(key: RiskProfilePersistence.positionLimitKey, value: riskProfile.positionLimit)
                try setAppSetting(key: RiskProfilePersistence.cryptoLimitKey, value: riskProfile.cryptoLimit)
                try setAppSetting(
                    key: RiskProfilePersistence.foreignCurrencyLimitKey,
                    value: riskProfile.foreignCurrencyLimit
                )
                try setAppSetting(
                    key: RiskProfilePersistence.liquidityMinimumKey,
                    value: riskProfile.liquidityMinimum
                )
                try setAppSetting(key: RiskProfilePersistence.updatedAtKey, value: riskProfile.updatedAt)
            }
        }

        return PortfolixDataTransferSummary(
            holdingCount: payload.holdings.count,
            portfolioSnapshotCount: payload.portfolioSnapshots.count,
            assetPriceSnapshotCount: payload.assetPriceSnapshots.count,
            riskProfileIncluded: payload.riskProfile != nil
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
            guard try fetchPosition(id: position.id) != nil else { throw PositionClosureError.holdingChanged }
            try save(position, operation: "update")
        }
    }

    func update(_ positions: [Position]) throws {
        guard !positions.isEmpty else { return }
        try positions.forEach(PositionInputValidator.validate)
        try transaction {
            for position in positions {
                try save(position, operation: "update")
            }
        }
    }

    func applyQuoteRefresh(
        updatedPositions: [Position],
        snapshotPositions _: [Position],
        snapshotDate: Date = .now
    ) throws {
        try updatedPositions.forEach(PositionInputValidator.validate)
        try transaction {
            for position in updatedPositions {
                _ = try updateQuote(position)
            }
            try writeDailySnapshots(positions: fetchPositions(), snapshotDate: snapshotDate)
        }
    }

    private func updateQuote(_ position: Position) throws -> Bool {
        guard let current = try fetchPosition(id: position.id),
              current.symbol == position.symbol, current.category == position.category,
              current.quoteCurrency == position.quoteCurrency else { return false }
        let updated = Position(id: current.id, name: current.name, symbol: current.symbol,
            category: current.category, quoteCurrency: current.quoteCurrency, quantity: current.quantity,
            totalCost: current.totalCost, averageCost: current.averageCost, latestPrice: position.latestPrice,
            marketValueCNY: current.quantity * position.latestPrice / current.quoteCurrency.rateFromCNY,
            profitRate: current.averageCost == 0 ? 0 : (position.latestPrice - current.averageCost) / current.averageCost * 100,
            weeklyTrend: position.weeklyTrend, source: position.source, quoteTime: position.quoteTime,
            fetchedAt: position.fetchedAt, freshness: position.freshness)
        try save(updated, operation: "quote_update")
        return true
    }

    func updateBalances(_ positions: [Position]) throws {
        guard !positions.isEmpty else { return }
        for position in positions {
            try PositionInputValidator.validate(position)
            guard !position.totalCost.isNaN, position.totalCost >= 0 else {
                throw PositionValidationError.invalidTotalCost
            }
        }

        try transaction {
            for position in positions {
                do {
                    let statement = try prepare(
                        """
                        UPDATE positions
                        SET quantity = ?, total_cost = ?, average_cost = ?, updated_at = ?
                        WHERE id = ?
                        """
                    )
                    defer { sqlite3_finalize(statement) }
                    try bind(Self.decimalString(position.quantity), to: 1, in: statement)
                    try bind(Self.decimalString(position.totalCost), to: 2, in: statement)
                    try bind(Self.decimalString(position.averageCost), to: 3, in: statement)
                    try bind(Self.timestamp(), to: 4, in: statement)
                    try bind(position.id.uuidString, to: 5, in: statement)
                    try stepDone(statement)
                    guard sqlite3_changes(database) == 1 else {
                        throw PositionRepositoryError.invalidStoredData("持仓已发生变化，请重新打开更新窗口")
                    }
                }
                try insertRevision(position: position, operation: "balance_update")
            }
        }
    }

    func delete(positionID: Position.ID) throws {
        try delete(positionIDs: [positionID])
    }

    func fetchPositionClosures() throws -> [PositionClosureRecord] {
        let statement = try prepare("SELECT payload_json FROM position_closures ORDER BY trade_date DESC, rowid DESC")
        defer { sqlite3_finalize(statement) }
        var records: [PositionClosureRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let record = try decoder.decode(PositionClosureRecord.self, from: Data(text(at: 0, in: statement).utf8))
            try PositionClosureValidation.validate(record)
            records.append(record)
        }
        return records
    }

    @discardableResult
    func closePosition(expected: Position, settlement: PositionClosureSettlement, tradeDate: Date,
                       cashPositionID: Position.ID?, cashName: String, now: Date = .now) throws -> PositionClosureRecord {
        guard expected.costIsKnown else { throw PositionTradeError.invalidInput }
        try requireAfterReconciliation(accountIDs: Set([expected.id.uuidString, cashPositionID?.uuidString].compactMap { $0 }), date: tradeDate)
        let day = Self.dayString(from: tradeDate)
        let today = Self.dayString(from: now)
        guard day <= today, tradeDate >= Date(timeIntervalSince1970: 0) else { throw PositionClosureError.invalidDate }
        var savedRecord: PositionClosureRecord?
        try transaction {
            guard let current = try fetchPosition(id: expected.id), current.category != .cash,
                  current.quantity == expected.quantity, current.totalCost == expected.totalCost,
                  current.symbol == expected.symbol, current.name == expected.name,
                  current.category == expected.category, current.quoteCurrency == expected.quoteCurrency else {
                throw PositionClosureError.holdingChanged
            }
            guard !settlement.executionPrice.isNaN, !settlement.fees.isNaN, !settlement.netProceeds.isNaN,
                  settlement.executionPrice >= 0, settlement.fees >= 0, settlement.netProceeds >= 0,
                  abs((current.quantity * settlement.executionPrice - settlement.grossProceeds).doubleValue)
                    <= (current.quoteCurrency == .usdt ? 0.00000001 : 0.01) else { throw PositionClosureError.invalidAmount }
            let original = try closureAssetSnapshots(positionID: current.id.uuidString, from: day)
            guard original.allSatisfy({ PositionClosureMath.decimal($0.quantity) == current.quantity }) else {
                throw PositionClosureError.historicalQuantityChange
            }
            // Daily snapshots alone cannot detect an intraday quantity change that was later reversed.
            let revisions = try prepare("SELECT snapshot_json FROM position_revisions WHERE position_id = ? AND created_at >= ? AND ? < ? AND operation IN ('create', 'update', 'balance_update')")
            defer { sqlite3_finalize(revisions) }
            try bind(current.id.uuidString, to: 1, in: revisions)
            try bind(Self.timestamp(from: Calendar.current.startOfDay(for: tradeDate)), to: 2, in: revisions)
            try bind(day, to: 3, in: revisions)
            try bind(today, to: 4, in: revisions)
            while sqlite3_step(revisions) == SQLITE_ROW {
                let snapshot = try decoder.decode([String: String].self, from: Data(text(at: 0, in: revisions).utf8))
                guard snapshot["quantity"].flatMap(PositionClosureMath.decimal) == current.quantity else {
                    throw PositionClosureError.historicalQuantityChange
                }
            }
            let allPositions = try fetchPositions()
            let cash: Position?
            if let cashPositionID {
                guard let selected = allPositions.first(where: { $0.id == cashPositionID }),
                      selected.category == .cash, selected.quoteCurrency == current.quoteCurrency else {
                    throw PositionClosureError.invalidCash
                }
                cash = selected
            } else {
                guard !allPositions.contains(where: { $0.category == .cash && $0.symbol == current.quoteCurrency.rawValue }) else {
                    throw PositionClosureError.invalidCash
                }
                cash = nil
            }
            let targetID = cash?.id ?? UUID()
            let targetName = cash?.name ?? cashName
            let updatedCash = PositionClosureMath.cashPosition(id: targetID, currency: current.quoteCurrency,
                quantity: (cash?.quantity ?? 0) + settlement.netProceeds, name: targetName, symbol: cash?.symbol)
            if updatedCash.quantity > 0 {
                try PositionInputValidator.validate(updatedCash)
                try save(updatedCash, operation: "closure_credit")
            }
            let rate = current.quoteCurrency.rateFromCNY
            let cashHistory = try closureAssetSnapshots(positionID: targetID.uuidString, from: day)
            let portfolioHistory = try closurePortfolioSnapshots(from: day)
            let sourceByDay = Dictionary(uniqueKeysWithValues: original.map { ($0.date, $0) })
            let cashByDay = Dictionary(uniqueKeysWithValues: cashHistory.map { ($0.date, $0) })
            let portfolioDays = Set(portfolioHistory.map(\.date))
            let days = Set(original.map(\.date) + cashHistory.map(\.date) + portfolioHistory.map(\.date) + [day])
                .filter { $0 <= today }.sorted()
            var adjustments: [PositionClosureHistoryAdjustment] = []
            for date in days {
                let previousCash = cashByDay[date]
                let cashQuantity = previousCash.flatMap { PositionClosureMath.decimal($0.quantity) } ?? 0
                let cashUnit = cashQuantity > 0
                    ? (previousCash.flatMap { PositionClosureMath.decimal($0.marketValueCNY) } ?? 0) / cashQuantity
                    : 1 / rate
                let credit = settlement.netProceeds * cashUnit
                let source = sourceByDay[date]
                let sourceValue = source.flatMap { PositionClosureMath.decimal($0.marketValueCNY) } ?? 0
                let sourcePrice = source.flatMap { PositionClosureMath.decimal($0.latestPrice) } ?? 0
                let sourceUnit = sourcePrice > 0 ? sourceValue / current.quantity / sourcePrice : 1 / rate
                let sourceCost = source.flatMap { PositionClosureMath.decimal($0.averageCost) }.map { $0 * current.quantity * sourceUnit } ?? 0
                let adjustsPortfolio = date < today && portfolioDays.contains(date) && source != nil
                let valueDelta = adjustsPortfolio ? credit - sourceValue : 0
                let costDelta = adjustsPortfolio ? credit - sourceCost : 0
                if adjustsPortfolio { try adjustClosurePortfolioSnapshot(day: date, valueDelta: valueDelta, costDelta: costDelta) }
                if updatedCash.quantity > 0, date < today {
                    let quantity = cashQuantity + settlement.netProceeds
                    if quantity > 0 {
                        try writeClosureAssetSnapshot(.init(assetID: targetID.uuidString, date: date, name: targetName,
                            symbol: updatedCash.symbol, category: AssetCategory.cash.rawValue, quoteCurrency: current.quoteCurrency.rawValue,
                            quantity: Self.decimalString(quantity), averageCost: "1", latestPrice: "1",
                            marketValueCNY: Self.decimalString(quantity * cashUnit), source: "手工价格", quoteTime: day,
                            freshness: Freshness.manual.rawValue, updatedAt: Self.timestamp(from: now)))
                    }
                }
                adjustments.append(.init(date: date, valueDeltaCNY: Self.decimalString(valueDelta), costDeltaCNY: Self.decimalString(costDelta),
                    cashUnitValueCNY: Self.decimalString(cashUnit), createdCashSnapshot: previousCash == nil,
                    adjustedPortfolioSnapshot: adjustsPortfolio))
            }
            let prior = try closureAssetSnapshots(positionID: current.id.uuidString, from: "1970-01-01")
                .last { $0.date < day }
            let priorUnit = prior.flatMap { snapshot -> Decimal? in
                guard let quantity = PositionClosureMath.decimal(snapshot.quantity), quantity > 0,
                      let value = PositionClosureMath.decimal(snapshot.marketValueCNY) else { return nil }
                return value / quantity
            }
            let dailyProfit = priorUnit.map { settlement.netProceeds / rate - $0 * current.quantity }
            let record = PositionClosureRecord(id: UUID(), holding: .init(position: current, timestamp: Self.timestamp(from: now)),
                tradeDate: day, executionPrice: Self.decimalString(settlement.executionPrice), fees: Self.decimalString(settlement.fees),
                netProceeds: Self.decimalString(settlement.netProceeds), rateFromCNY: Self.decimalString(rate),
                cashPositionID: updatedCash.quantity > 0 ? targetID.uuidString : nil, cashName: targetName,
                createdCashPosition: cash == nil && updatedCash.quantity > 0,
                dailyProfitCNY: dailyProfit.map(Self.decimalString), originalSnapshots: original,
                historyAdjustments: adjustments, recordedAt: Self.timestamp(from: now))
            try PositionClosureValidation.validate(record)
            try savePositionClosure(record)
            try insertRevision(position: current, operation: "close")
            try removeActiveClosurePosition(id: current.id)
            try deleteClosureAssetSnapshots(id: current.id.uuidString, from: day)
            try writeClosureAssetSnapshot(.init(assetID: current.id.uuidString, date: day, name: current.name, symbol: current.symbol,
                category: current.category.rawValue, quoteCurrency: current.quoteCurrency.rawValue,
                quantity: Self.decimalString(current.quantity), averageCost: Self.decimalString(current.averageCost),
                latestPrice: Self.decimalString(settlement.executionPrice), marketValueCNY: Self.decimalString(settlement.grossProceeds / rate),
                source: "手工价格", quoteTime: day, freshness: Freshness.manual.rawValue, updatedAt: Self.timestamp(from: now)))
            try writeDailySnapshots(positions: fetchPositions(), snapshotDate: now)
            savedRecord = record
        }
        guard let savedRecord else { throw PositionClosureError.invalidRecord }
        return savedRecord
    }

    func reversePositionClosure(id: UUID, now: Date = .now) throws {
        try transaction {
            guard var record = try fetchPositionClosures().first(where: { $0.id == id }), !record.isReversed else {
                throw PositionClosureError.invalidRecord
            }
            try requireAfterReconciliation(accountIDs: Set([record.holding.id, record.cashPositionID].compactMap { $0 }), date: PositionClosureMath.date(record.tradeDate)!)
            guard let recordedAt = ISO8601DateFormatter().date(from: record.recordedAt), Calendar.current.isDate(recordedAt, inSameDayAs: now) else {
                throw PositionClosureError.reversalExpired
            }
            let original = try record.holding.position()
            let positions = try fetchPositions()
            guard !(try fetchPositionTrades()).contains(where: { trade in
                !trade.isReversed && trade.tradeDate >= record.tradeDate &&
                    (trade.asset.id == record.holding.id || record.cashPositionID.map { trade.cash?.id == $0 } == true)
            }) else { throw PositionTradeError.dependentTrade }
            guard !positions.contains(where: { $0.id == original.id || ($0.symbol.caseInsensitiveCompare(original.symbol) == .orderedSame && $0.category == original.category) }) else {
                throw PositionClosureError.activeHoldingExists
            }
            if let cashID = record.cashPositionID, record.netAmount > 0 {
                guard let cash = positions.first(where: { $0.id.uuidString == cashID }), cash.category == .cash,
                      cash.quoteCurrency == original.quoteCurrency, cash.quantity >= record.netAmount else { throw PositionClosureError.insufficientCash }
                let remaining = cash.quantity - record.netAmount
                if remaining == 0 { try removeActiveClosurePosition(id: cash.id) }
                else { try save(PositionClosureMath.cashPosition(id: cash.id, currency: cash.quoteCurrency,
                    quantity: remaining, name: cash.name, symbol: cash.symbol), operation: "closure_reversal") }
                for adjustment in record.historyAdjustments where adjustment.date < Self.dayString(from: now) {
                    if let snapshot = try closureAssetSnapshots(positionID: cashID, from: adjustment.date).first(where: { $0.date == adjustment.date }),
                       let quantity = PositionClosureMath.decimal(snapshot.quantity), quantity >= record.netAmount {
                        let newQuantity = quantity - record.netAmount
                        if newQuantity == 0 { try deleteClosureAssetSnapshot(id: cashID, day: adjustment.date) }
                        else {
                            let unit = (PositionClosureMath.decimal(snapshot.marketValueCNY) ?? 0) / quantity
                            try writeClosureAssetSnapshot(.init(assetID: snapshot.assetID, date: snapshot.date, name: snapshot.name,
                                symbol: snapshot.symbol, category: snapshot.category, quoteCurrency: snapshot.quoteCurrency,
                                quantity: Self.decimalString(newQuantity), averageCost: "1", latestPrice: "1",
                                marketValueCNY: Self.decimalString(newQuantity * unit), source: snapshot.source,
                                quoteTime: snapshot.quoteTime, freshness: snapshot.freshness, updatedAt: Self.timestamp(from: now)))
                        }
                    } else { throw PositionClosureError.insufficientCash }
                }
            }
            for adjustment in record.historyAdjustments where adjustment.adjustedPortfolioSnapshot {
                try adjustClosurePortfolioSnapshot(day: adjustment.date,
                    valueDelta: -(PositionClosureMath.decimal(adjustment.valueDeltaCNY) ?? 0),
                    costDelta: -(PositionClosureMath.decimal(adjustment.costDeltaCNY) ?? 0))
            }
            try deleteClosureAssetSnapshots(id: record.holding.id, from: record.tradeDate)
            for snapshot in record.originalSnapshots { try writeClosureAssetSnapshot(snapshot) }
            try save(original, operation: "reopen")
            record.reversedAt = Self.timestamp(from: now)
            try savePositionClosure(record)
            try writeDailySnapshots(positions: fetchPositions(), snapshotDate: now)
        }
    }

    func delete(positionIDs: [Position.ID]) throws {
        guard !positionIDs.isEmpty else { return }
        try transaction {
            let reconciledIDs = Set(try fetchReconciliations().compactMap { UUID(uuidString: $0.asset.id) })
            guard Set(positionIDs).isDisjoint(with: reconciledIDs) else { throw PositionTradeError.recordedTradesExist }
            let linkedIDs = PositionRecordLinks.activeAccountIDs(trades: try fetchPositionTrades(), closures: try fetchPositionClosures(),
                openings: try fetchOpeningBalances())
            guard Set(positionIDs).isDisjoint(with: linkedIDs) else { throw PositionTradeError.recordedTradesExist }
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

        let reconciliations = try reconciliationInputs()
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
                    profitRate: profitRate,
                    costIsKnown: try snapshotCostIsKnown(day: text(at: 0, in: statement), records: reconciliations)
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
        try fetchAssetPriceSnapshots(
            positionIDs: [positionID],
            lookbackDays: lookbackDays,
            through: date
        )[positionID] ?? []
    }

    func fetchAssetPriceSnapshots(
        positionIDs: [Position.ID],
        lookbackDays: Int = 45,
        through date: Date = .now
    ) throws -> [Position.ID: [AssetPriceSnapshotPoint]] {
        let uniqueIDs = Array(Set(positionIDs))
        guard !uniqueIDs.isEmpty else { return [:] }
        let boundedLookback = max(1, min(lookbackDays, 365))
        let startDate = Calendar.current.date(byAdding: .day, value: -boundedLookback, to: date) ?? date
        var result: [Position.ID: [AssetPriceSnapshotPoint]] = [:]

        for chunkStart in stride(from: 0, to: uniqueIDs.count, by: 400) {
            let chunkEnd = min(chunkStart + 400, uniqueIDs.count)
            let ids = Array(uniqueIDs[chunkStart..<chunkEnd])
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
            let statement = try prepare(
                """
                SELECT asset_id, snapshot_date, latest_price, quantity, market_value_cny
                FROM asset_price_snapshots
                WHERE asset_id IN (\(placeholders))
                  AND snapshot_date >= ?
                  AND snapshot_date <= ?
                ORDER BY asset_id ASC, snapshot_date ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            for (offset, id) in ids.enumerated() {
                try bind(id.uuidString, to: Int32(offset + 1), in: statement)
            }
            try bind(Self.dayString(from: startDate), to: Int32(ids.count + 1), in: statement)
            try bind(Self.dayString(from: date), to: Int32(ids.count + 2), in: statement)

            while sqlite3_step(statement) == SQLITE_ROW {
                guard
                    let positionID = UUID(uuidString: text(at: 0, in: statement)),
                    let snapshotDate = Self.date(fromDayString: text(at: 1, in: statement)),
                    let latestPrice = Decimal(string: text(at: 2, in: statement)),
                    let quantity = Decimal(string: text(at: 3, in: statement)),
                    let marketValueCNY = Decimal(string: text(at: 4, in: statement))
                else {
                    throw PositionRepositoryError.invalidStoredData("无法解析资产历史价格快照")
                }
                result[positionID, default: []].append(
                    AssetPriceSnapshotPoint(
                        date: snapshotDate,
                        latestPrice: latestPrice,
                        quantity: quantity,
                        marketValueCNY: marketValueCNY
                    )
                )
            }
        }
        return result
    }

    func fetchDailyProfitPoints(
        limitDays: Int = 365,
        through date: Date = .now
    ) throws -> [DailyProfitPoint] {
        let boundedLimit = max(1, min(limitDays, 365))
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: date)
        let startDate = calendar.date(
            byAdding: .day,
            value: -(boundedLimit - 1),
            to: endDate
        ) ?? endDate
        let statement = try prepare(
            """
            SELECT asset_id, snapshot_date, quantity, market_value_cny
            FROM asset_price_snapshots
            WHERE snapshot_date <= ?
            ORDER BY asset_id ASC, snapshot_date ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(Self.dayString(from: endDate), to: 1, in: statement)

        var previousUnitValueByAsset: [String: Decimal] = [:]
        var totalsByDate: [Date: Decimal] = [:]
        var contributionCountByDate: [Date: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let assetID = text(at: 0, in: statement)
            guard
                let snapshotDate = Self.date(fromDayString: text(at: 1, in: statement)),
                let quantity = Decimal(string: text(at: 2, in: statement)),
                let marketValueCNY = Decimal(string: text(at: 3, in: statement)),
                quantity > 0
            else {
                throw PositionRepositoryError.invalidStoredData("无法解析每日盈亏历史快照")
            }
            let unitValueCNY = marketValueCNY / quantity
            defer { previousUnitValueByAsset[assetID] = unitValueCNY }
            guard
                snapshotDate >= startDate,
                let previousUnitValueCNY = previousUnitValueByAsset[assetID]
            else { continue }

            totalsByDate[snapshotDate, default: 0] += (unitValueCNY - previousUnitValueCNY) * quantity
            contributionCountByDate[snapshotDate, default: 0] += 1
        }

        for closure in try fetchPositionClosures() where !closure.isReversed {
            guard let day = Self.date(fromDayString: closure.tradeDate), day >= startDate, day <= endDate else { continue }
            totalsByDate[day, default: 0] -= closure.feeAmount / closure.conversionRate
            if closure.feeAmount > 0 { contributionCountByDate[day, default: 0] += 1 }
        }
        for (day, values) in try tradeDailyProfitAdjustments(through: date) {
            guard let day = Self.date(fromDayString: day), day >= startDate, day <= endDate else { continue }
            totalsByDate[day, default: 0] += values.values.reduce(0, +)
            contributionCountByDate[day, default: 0] += 1
        }
        let incomplete = RecordedReconciliation.incompleteDays(try reconciliationInputs())
        return totalsByDate.keys
            .filter { contributionCountByDate[$0, default: 0] > 0 && !incomplete.contains(Self.dayString(from: $0)) }
            .sorted()
            .map { DailyProfitPoint(date: $0, amountCNY: totalsByDate[$0, default: 0]) }
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

    private func storedRiskProfile() throws -> PortfolixDataPackage.RiskProfile {
        let configured = try appSetting(for: RiskProfilePersistence.configuredKey) == "true"
        let level = try appSetting(for: RiskProfilePersistence.levelKey) ?? "未配置"
        let version = try appSetting(for: RiskProfilePersistence.versionKey).flatMap(Int.init) ?? 0
        let positionLimit = try appSetting(for: RiskProfilePersistence.positionLimitKey) ?? "30"
        let cryptoLimit = try appSetting(for: RiskProfilePersistence.cryptoLimitKey) ?? "15"
        let foreignCurrencyLimit = try appSetting(for: RiskProfilePersistence.foreignCurrencyLimitKey) ?? "50"
        let liquidityMinimum = try appSetting(for: RiskProfilePersistence.liquidityMinimumKey) ?? "10"
        let updatedAt = try appSetting(for: RiskProfilePersistence.updatedAtKey) ?? Self.timestamp()
        return PortfolixDataPackage.RiskProfile(
            configured: configured,
            level: level,
            version: version,
            positionLimit: positionLimit,
            cryptoLimit: cryptoLimit,
            foreignCurrencyLimit: foreignCurrencyLimit,
            liquidityMinimum: liquidityMinimum,
            updatedAt: updatedAt
        )
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

                if let trace = artifacts.trace {
                    let traceStatement = try prepare(
                        """
                        INSERT INTO ai_agent_run_traces (run_id, trace_json, created_at)
                        VALUES (?, ?, ?)
                        """
                    )
                    defer { sqlite3_finalize(traceStatement) }
                    let traceJSON = String(
                        data: try aiArtifactEncoder.encode(trace),
                        encoding: .utf8
                    ) ?? "{}"
                    try bind(run.id.uuidString, to: 1, in: traceStatement)
                    try bind(traceJSON, to: 2, in: traceStatement)
                    try bind(Self.timestamp(), to: 3, in: traceStatement)
                    try stepDone(traceStatement)
                }

                if let evidenceLedgerJSON = artifacts.evidenceLedgerJSON {
                    let evidenceStatement = try prepare(
                        """
                        INSERT INTO ai_agent_evidence_ledgers (run_id, evidence_json, created_at)
                        VALUES (?, ?, ?)
                        """
                    )
                    defer { sqlite3_finalize(evidenceStatement) }
                    try bind(run.id.uuidString, to: 1, in: evidenceStatement)
                    try bind(evidenceLedgerJSON, to: 2, in: evidenceStatement)
                    try bind(Self.timestamp(), to: 3, in: evidenceStatement)
                    try stepDone(evidenceStatement)
                }

                if let loopStateJSON = artifacts.loopStateJSON {
                    let loopStatement = try prepare(
                        """
                        INSERT INTO ai_agent_loop_states (run_id, state_json, created_at)
                        VALUES (?, ?, ?)
                        """
                    )
                    defer { sqlite3_finalize(loopStatement) }
                    try bind(run.id.uuidString, to: 1, in: loopStatement)
                    try bind(loopStateJSON, to: 2, in: loopStatement)
                    try bind(Self.timestamp(), to: 3, in: loopStatement)
                    try stepDone(loopStatement)
                }

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
        let trace = try fetchAIAgentRunTrace(runID: runID)
        let bundle = AIAnalysisArtifactBundle(
            inputJSON: text(at: 0, in: statement),
            toolResultsJSON: text(at: 1, in: statement),
            toolPlanJSON: text(at: 2, in: statement),
            evidenceLedgerJSON: try fetchAIAgentEvidenceLedgerJSON(runID: runID),
            loopStateJSON: try fetchAIAgentLoopStateJSON(runID: runID),
            rawReportJSON: text(at: 3, in: statement),
            repairedReportJSON: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : text(at: 4, in: statement),
            finalReportJSON: text(at: 5, in: statement),
            guardrailResultJSON: text(at: 6, in: statement),
            trace: trace
        )
        return trace?.modelUsage.map { bundle.withModelUsage($0) } ?? bundle
    }

    func fetchLatestAIAnalysisArtifacts() throws -> AIAnalysisArtifactBundle? {
        let statement = try prepare(
            """
            SELECT runs.id, artifacts.input_json, artifacts.research_results_json,
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
        guard let runID = UUID(uuidString: text(at: 0, in: statement)) else {
            throw PositionRepositoryError.invalidStoredData("无法解析 AI 运行 ID")
        }
        let trace = try fetchAIAgentRunTrace(runID: runID)
        let bundle = AIAnalysisArtifactBundle(
            inputJSON: text(at: 1, in: statement),
            toolResultsJSON: text(at: 2, in: statement),
            toolPlanJSON: text(at: 3, in: statement),
            evidenceLedgerJSON: try fetchAIAgentEvidenceLedgerJSON(runID: runID),
            loopStateJSON: try fetchAIAgentLoopStateJSON(runID: runID),
            rawReportJSON: text(at: 4, in: statement),
            repairedReportJSON: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : text(at: 5, in: statement),
            finalReportJSON: text(at: 6, in: statement),
            guardrailResultJSON: text(at: 7, in: statement),
            trace: trace
        )
        return trace?.modelUsage.map { bundle.withModelUsage($0) } ?? bundle
    }

    private func fetchAIAgentRunTrace(runID: UUID) throws -> AIAgentRunTrace? {
        let statement = try prepare(
            """
            SELECT trace_json
            FROM ai_agent_run_traces
            WHERE run_id = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(runID.uuidString, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        guard let data = text(at: 0, in: statement).data(using: .utf8) else {
            throw PositionRepositoryError.invalidStoredData("无法解析 Agent 运行轨迹")
        }
        return try aiArtifactDecoder.decode(AIAgentRunTrace.self, from: data)
    }

    private func fetchAIAgentEvidenceLedgerJSON(runID: UUID) throws -> String? {
        let statement = try prepare(
            """
            SELECT evidence_json
            FROM ai_agent_evidence_ledgers
            WHERE run_id = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(runID.uuidString, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return text(at: 0, in: statement)
    }

    private func fetchAIAgentLoopStateJSON(runID: UUID) throws -> String? {
        let statement = try prepare(
            """
            SELECT state_json
            FROM ai_agent_loop_states
            WHERE run_id = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(runID.uuidString, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return text(at: 0, in: statement)
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

    func deleteAllAIAnalysisContent() throws {
        try transaction {
            try execute("DELETE FROM ai_analysis_chat_messages")
            try execute("DELETE FROM ai_analysis_sources")
            try execute("DELETE FROM ai_analysis_reports")
            try execute("DELETE FROM ai_guardrail_results")
            try execute("DELETE FROM ai_analysis_artifacts")
            try execute("DELETE FROM ai_analysis_runs")
        }
    }

    func replaceDailySnapshots(positions: [Position], snapshotDate: Date = .now) throws {
        try transaction {
            try writeDailySnapshots(positions: positions, snapshotDate: snapshotDate)
        }
    }

    private func writeDailySnapshots(positions: [Position], snapshotDate: Date) throws {
        let day = Self.dayString(from: snapshotDate)
        let cutoff = Self.dayString(
            from: Calendar.current.date(byAdding: .day, value: -365, to: snapshotDate) ?? snapshotDate
        )
        let now = Self.timestamp()
        let totalValue = positions.reduce(Decimal.zero) { $0 + $1.marketValueCNY }
        let totalCost = positions.reduce(Decimal.zero) {
            $0 + $1.totalCost / $1.quoteCurrency.rateFromCNY
        }
        let totalProfit = totalValue - totalCost
        let profitRate = totalCost == 0 ? Decimal.zero : totalProfit / totalCost * 100

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
            try autoreleasepool {
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
        }

        try pruneSnapshots(olderThan: cutoff)
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

        let snapshotStatement = try prepare("DELETE FROM asset_price_snapshots WHERE asset_id = ?")
        defer { sqlite3_finalize(snapshotStatement) }
        try bind(positionID.uuidString, to: 1, in: snapshotStatement)
        try stepDone(snapshotStatement)

        let assetStatement = try prepare("DELETE FROM assets WHERE id = ?")
        defer { sqlite3_finalize(assetStatement) }
        try bind(positionID.uuidString, to: 1, in: assetStatement)
        try stepDone(assetStatement)
    }

    private func configure() throws {
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA busy_timeout = 5000")
    }

    private func migrate() throws {
        try execute("CREATE TABLE IF NOT EXISTS position_reconciliations (id TEXT PRIMARY KEY NOT NULL, asset_id TEXT NOT NULL, sequence INTEGER NOT NULL, payload_json TEXT NOT NULL)")
        try execute("CREATE INDEX IF NOT EXISTS reconciliation_asset ON position_reconciliations(asset_id, sequence)")
        try execute("CREATE TABLE IF NOT EXISTS position_opening_balances (position_id TEXT PRIMARY KEY NOT NULL, payload_json TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS position_trades (id TEXT PRIMARY KEY NOT NULL, trade_date TEXT NOT NULL, payload_json TEXT NOT NULL)")
        try execute("""
            CREATE TABLE IF NOT EXISTS position_closures (
                id TEXT PRIMARY KEY NOT NULL,
                position_id TEXT NOT NULL,
                trade_date TEXT NOT NULL,
                fees_cny TEXT NOT NULL,
                reversed_at TEXT,
                payload_json TEXT NOT NULL
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_active_position_closure
                ON position_closures(position_id) WHERE reversed_at IS NULL;
            """)
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
            CREATE TABLE IF NOT EXISTS ai_agent_run_traces (
                run_id TEXT PRIMARY KEY NOT NULL REFERENCES ai_analysis_runs(id) ON DELETE CASCADE,
                trace_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ai_agent_evidence_ledgers (
                run_id TEXT PRIMARY KEY NOT NULL REFERENCES ai_analysis_runs(id) ON DELETE CASCADE,
                evidence_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ai_agent_loop_states (
                run_id TEXT PRIMARY KEY NOT NULL REFERENCES ai_analysis_runs(id) ON DELETE CASCADE,
                state_json TEXT NOT NULL,
                created_at TEXT NOT NULL
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
        try bind(position.fetchedAt, to: 6, in: quoteStatement)
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

    private func position(from statement: OpaquePointer, knownCost: Bool? = nil) throws -> Position {
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
            freshness: freshness,
            dailyPriceBaseline: try dailyPriceBaseline(for: id),
            costIsKnown: try knownCost ?? costIsKnown(for: id)
        )
    }

    private func dailyPriceBaseline(for assetID: UUID, asOf date: Date = .now) throws -> PositionDailyPriceBaseline? {
        let day = Self.dayString(from: date)
        let statement = try prepare("""
            SELECT latest_price, quantity, market_value_cny FROM asset_price_snapshots
            WHERE asset_id = ? AND snapshot_date < ?
            ORDER BY snapshot_date DESC LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }
        try bind(assetID.uuidString, to: 1, in: statement)
        try bind(day, to: 2, in: statement)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else {
            throw PositionRepositoryError.database(String(cString: sqlite3_errmsg(database)))
        }
        guard let price = Decimal(string: text(at: 0, in: statement)) else {
            throw PositionRepositoryError.invalidStoredData("无法解析当日收益参考价格")
        }
        let quantity = Decimal(string: text(at: 1, in: statement)) ?? 0
        let value = Decimal(string: text(at: 2, in: statement)) ?? 0
        return PositionDailyPriceBaseline(day: day, price: price, unitValueCNY: quantity > 0 ? value / quantity : nil)
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

extension PositionRepository {
    private func savePositionClosure(_ record: PositionClosureRecord) throws {
        let statement = try prepare("""
            INSERT INTO position_closures(id, position_id, trade_date, fees_cny, reversed_at, payload_json)
            VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET
                position_id = excluded.position_id, trade_date = excluded.trade_date, fees_cny = excluded.fees_cny,
                reversed_at = excluded.reversed_at, payload_json = excluded.payload_json
            """)
        defer { sqlite3_finalize(statement) }
        try bind(record.id.uuidString, to: 1, in: statement)
        try bind(record.holding.id, to: 2, in: statement)
        try bind(record.tradeDate, to: 3, in: statement)
        try bind(Self.decimalString(record.feeAmount / record.conversionRate), to: 4, in: statement)
        if let reversed = record.reversedAt { try bind(reversed, to: 5, in: statement) }
        else { sqlite3_bind_null(statement, 5) }
        try bind(String(decoding: encoder.encode(record), as: UTF8.self), to: 6, in: statement)
        try stepDone(statement)
    }

    private func removeActiveClosurePosition(id: UUID) throws {
        for sql in ["DELETE FROM positions WHERE id = ?", "DELETE FROM latest_quotes WHERE asset_id = ?", "DELETE FROM assets WHERE id = ?"] {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(id.uuidString, to: 1, in: statement)
            try stepDone(statement)
        }
    }

    private func closureAssetSnapshots(positionID: String, from day: String) throws -> [PortfolixDataPackage.AssetPriceHistory] {
        let statement = try prepare("""
            SELECT snapshot_date, name, symbol, category, quote_currency, quantity, average_cost,
                   latest_price, market_value_cny, source, quote_time, freshness, updated_at
            FROM asset_price_snapshots WHERE asset_id = ? AND snapshot_date >= ? ORDER BY snapshot_date
            """)
        defer { sqlite3_finalize(statement) }
        try bind(positionID, to: 1, in: statement)
        try bind(day, to: 2, in: statement)
        var rows: [PortfolixDataPackage.AssetPriceHistory] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(.init(assetID: positionID, date: text(at: 0, in: statement), name: text(at: 1, in: statement),
                symbol: text(at: 2, in: statement), category: text(at: 3, in: statement), quoteCurrency: text(at: 4, in: statement),
                quantity: text(at: 5, in: statement), averageCost: text(at: 6, in: statement), latestPrice: text(at: 7, in: statement),
                marketValueCNY: text(at: 8, in: statement), source: text(at: 9, in: statement), quoteTime: text(at: 10, in: statement),
                freshness: text(at: 11, in: statement), updatedAt: text(at: 12, in: statement)))
        }
        return rows
    }

    private func closurePortfolioSnapshots(from day: String) throws -> [PortfolixDataPackage.PortfolioHistory] {
        let statement = try prepare("SELECT snapshot_date, total_value_cny, total_cost_cny, total_profit_cny, profit_rate, updated_at FROM portfolio_snapshots WHERE snapshot_date >= ? ORDER BY snapshot_date")
        defer { sqlite3_finalize(statement) }
        try bind(day, to: 1, in: statement)
        var rows: [PortfolixDataPackage.PortfolioHistory] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(.init(date: text(at: 0, in: statement), totalValueCNY: text(at: 1, in: statement), totalCostCNY: text(at: 2, in: statement),
                totalProfitCNY: text(at: 3, in: statement), profitRate: text(at: 4, in: statement), updatedAt: text(at: 5, in: statement)))
        }
        return rows
    }

    private func adjustClosurePortfolioSnapshot(day: String, valueDelta: Decimal, costDelta: Decimal) throws {
        guard let current = try closurePortfolioSnapshots(from: day).first(where: { $0.date == day }),
              let value = PositionClosureMath.decimal(current.totalValueCNY), let cost = PositionClosureMath.decimal(current.totalCostCNY) else { return }
        let newValue = value + valueDelta
        let newCost = cost + costDelta
        guard !newValue.isNaN, !newCost.isNaN, newValue >= 0, newCost >= 0 else { throw PositionClosureError.invalidRecord }
        let statement = try prepare("UPDATE portfolio_snapshots SET total_value_cny = ?, total_cost_cny = ?, total_profit_cny = ?, profit_rate = ?, updated_at = ? WHERE snapshot_date = ?")
        defer { sqlite3_finalize(statement) }
        for (offset, value) in [newValue, newCost, newValue - newCost, newCost == 0 ? 0 : (newValue - newCost) / newCost * 100].enumerated() {
            try bind(Self.decimalString(value), to: Int32(offset + 1), in: statement)
        }
        try bind(Self.timestamp(), to: 5, in: statement)
        try bind(day, to: 6, in: statement)
        try stepDone(statement)
    }

    private func writeClosureAssetSnapshot(_ snapshot: PortfolixDataPackage.AssetPriceHistory) throws {
        let statement = try prepare("""
            INSERT INTO asset_price_snapshots(id, asset_id, snapshot_date, name, symbol, category, quote_currency,
                quantity, average_cost, latest_price, market_value_cny, source, quote_time, freshness, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id, snapshot_date) DO UPDATE SET quantity = excluded.quantity,
                average_cost = excluded.average_cost, latest_price = excluded.latest_price, market_value_cny = excluded.market_value_cny,
                source = excluded.source, quote_time = excluded.quote_time, freshness = excluded.freshness, updated_at = excluded.updated_at
            """)
        defer { sqlite3_finalize(statement) }
        let values = ["\(snapshot.assetID)-\(snapshot.date)", snapshot.assetID, snapshot.date, snapshot.name, snapshot.symbol,
            snapshot.category, snapshot.quoteCurrency, snapshot.quantity, snapshot.averageCost, snapshot.latestPrice,
            snapshot.marketValueCNY, snapshot.source, snapshot.quoteTime, snapshot.freshness, snapshot.updatedAt]
        for (offset, value) in values.enumerated() { try bind(value, to: Int32(offset + 1), in: statement) }
        try stepDone(statement)
    }

    private func deleteClosureAssetSnapshots(id: String, from day: String) throws {
        let statement = try prepare("DELETE FROM asset_price_snapshots WHERE asset_id = ? AND snapshot_date >= ?")
        defer { sqlite3_finalize(statement) }
        try bind(id, to: 1, in: statement)
        try bind(day, to: 2, in: statement)
        try stepDone(statement)
    }

    private func deleteClosureAssetSnapshot(id: String, day: String) throws {
        let statement = try prepare("DELETE FROM asset_price_snapshots WHERE asset_id = ? AND snapshot_date = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id, to: 1, in: statement)
        try bind(day, to: 2, in: statement)
        try stepDone(statement)
    }
}

extension PositionRepository {
    func fetchOpeningBalances() throws -> [PositionOpeningBalanceRecord] {
        let statement = try prepare("SELECT payload_json FROM position_opening_balances ORDER BY position_id")
        defer { sqlite3_finalize(statement) }
        var records: [PositionOpeningBalanceRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let record = try decoder.decode(PositionOpeningBalanceRecord.self, from: Data(text(at: 0, in: statement).utf8))
            try record.validate()
            records.append(record)
        }
        return records
    }

    func migrateOpeningBalances(now: Date = .now) throws {
        try transaction { try ensureOpeningBalances(now: now) }
    }

    private func ensureOpeningBalances(replacing ids: Set<UUID> = [], now: Date = .now) throws {
        let existing = Dictionary(uniqueKeysWithValues: try fetchOpeningBalances().map { ($0.id, $0) })
        let positions = try fetchPositions()
        let trades = try fetchPositionTrades()
        let closures = try fetchPositionClosures()
        let accountIDs = Set(positions.map(\.id))
            .union(trades.flatMap(\.accountIDs).compactMap(UUID.init(uuidString:)))
            .union(closures.flatMap { [$0.holding.id, $0.cashPositionID].compactMap { $0 }.compactMap(UUID.init(uuidString:)) })
        guard !accountIDs.isSubset(of: Set(existing.keys)) || !ids.isEmpty else { return }
        let candidates = try PositionOpeningBalanceMath.reconstruct(positions: positions, trades: trades, closures: closures,
            recordedAt: Self.timestamp(from: now))
        for var candidate in candidates where existing[candidate.id] == nil || ids.contains(candidate.id) {
            if try hasUnexplainedOpeningCorrections(candidate, trades: trades, closures: closures) {
                candidate = .init(id: candidate.id, holding: candidate.holding, quantity: candidate.quantity,
                    totalCost: candidate.totalCost, requiresReview: true, recordedAt: candidate.recordedAt)
            }
            if let previous = existing[candidate.id], previous.quantity == candidate.quantity,
               previous.totalCost == candidate.totalCost, previous.requiresReview == candidate.requiresReview,
               !previous.isReversed { continue }
            try saveOpeningBalance(candidate)
        }
    }

    private func hasUnexplainedOpeningCorrections(_ record: PositionOpeningBalanceRecord,
                                                 trades: [PositionTradeRecord], closures: [PositionClosureRecord]) throws -> Bool {
        guard let quantity = record.units, let cost = record.cost else { return true }
        let id = record.id.uuidString
        let linked = trades.filter { !$0.isReversed && $0.accountIDs.compactMap(UUID.init(uuidString:)).contains(record.id) }
        let relatedClosures = closures.filter { !$0.isReversed && (UUID(uuidString: $0.holding.id) == record.id || $0.cashPositionID.flatMap(UUID.init(uuidString:)) == record.id) }
        guard let firstEvent = (linked.map(\.recordedAt) + relatedClosures.map(\.recordedAt)).min() else { return false }
        let statement = try prepare("SELECT created_at, snapshot_json FROM position_revisions WHERE position_id = ? AND operation IN ('update', 'balance_update') AND created_at >= ?")
        defer { sqlite3_finalize(statement) }
        try bind(id, to: 1, in: statement)
        try bind(firstEvent, to: 2, in: statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = text(at: 0, in: statement)
            guard let revision = try? decoder.decode([String: String].self, from: Data(text(at: 1, in: statement).utf8)) else { return true }
            var expected = PositionTradeReplay.Balance(quantity: quantity, cost: cost)
            for trade in linked where trade.recordedAt < timestamp {
                if UUID(uuidString: trade.asset.id) == record.id { expected.quantity += trade.quantityDelta; expected.cost += trade.costDelta }
                if trade.cash.flatMap({ UUID(uuidString: $0.id) }) == record.id { expected.quantity += trade.cashDelta; expected.cost += trade.cashDelta }
            }
            for closure in relatedClosures where closure.recordedAt < timestamp {
                if UUID(uuidString: closure.holding.id) == record.id {
                    expected.quantity -= closure.quantity
                    expected.cost -= PositionClosureMath.decimal(closure.holding.totalCost) ?? 0
                }
                if closure.cashPositionID.flatMap(UUID.init(uuidString:)) == record.id {
                    expected.quantity += closure.netAmount; expected.cost += closure.netAmount
                }
            }
            var possible = [expected]
            for trade in linked.filter({ $0.recordedAt == timestamp }).sorted(by: { $0.sequence < $1.sequence }) {
                if UUID(uuidString: trade.asset.id) == record.id { expected.quantity += trade.quantityDelta; expected.cost += trade.costDelta }
                if trade.cash.flatMap({ UUID(uuidString: $0.id) }) == record.id { expected.quantity += trade.cashDelta; expected.cost += trade.cashDelta }
                possible.append(expected)
            }
            guard possible.contains(where: { balance in revision["quantity"].flatMap(PositionClosureMath.decimal) == balance.quantity
                && revision["totalCost"].flatMap(PositionClosureMath.decimal).map { abs(($0 - balance.cost).doubleValue) < 0.000001 } == true
            }) else { return true }
        }
        return false
    }

    private func saveOpeningBalance(_ record: PositionOpeningBalanceRecord) throws {
        try record.validate()
        let statement = try prepare("INSERT INTO position_opening_balances(position_id, payload_json) VALUES (?, ?) ON CONFLICT(position_id) DO UPDATE SET payload_json = excluded.payload_json")
        defer { sqlite3_finalize(statement) }
        try bind(record.id.uuidString, to: 1, in: statement)
        try bind(String(decoding: encoder.encode(record), as: UTF8.self), to: 2, in: statement)
        try stepDone(statement)
    }

    func confirmOpeningBalance(id: UUID, quantity: Decimal, totalCost: Decimal) throws {
        try transaction {
            try requireAfterReconciliation(accountIDs: [id.uuidString], date: .distantPast)
            guard let record = try fetchOpeningBalances().first(where: { $0.id == id }), !record.isReversed else { throw PositionOpeningBalanceError.changed }
            let candidates = try PositionOpeningBalanceMath.reconstruct(positions: fetchPositions(), trades: fetchPositionTrades(),
                closures: fetchPositionClosures(), recordedAt: record.recordedAt)
            guard let candidate = candidates.first(where: { $0.id == id }), candidate.units == quantity,
                  candidate.cost.map({ abs(($0 - totalCost).doubleValue) < 0.000001 }) == true else { throw PositionOpeningBalanceError.changed }
            try saveOpeningBalance(.init(id: record.id, holding: record.holding, quantity: PositionClosureMath.string(quantity),
                totalCost: PositionClosureMath.string(totalCost), requiresReview: false, recordedAt: record.recordedAt))
        }
    }

    func reverseOpeningBalance(id: UUID, now: Date = .now) throws {
        try transaction {
            try requireAfterReconciliation(accountIDs: [id.uuidString], date: .distantPast)
            guard var record = try fetchOpeningBalances().first(where: { $0.id == id }), !record.isReversed else { throw PositionOpeningBalanceError.changed }
            guard !record.requiresReview, let units = record.units, let cost = record.cost, units > 0 else { throw PositionOpeningBalanceError.needsReview }
            let links = PositionRecordLinks.activeAccountIDs(trades: try fetchPositionTrades(), closures: try fetchPositionClosures())
            guard !links.contains(id) else { throw PositionOpeningBalanceError.dependentRecords }
            guard let position = try fetchPosition(id: id), position.quantity == units,
                  abs((position.totalCost - cost).doubleValue) < 0.000001 else { throw PositionOpeningBalanceError.changed }
            for snapshot in try closureAssetSnapshots(positionID: id.uuidString, from: "1970-01-01") {
                let value = PositionClosureMath.decimal(snapshot.marketValueCNY) ?? 0
                let quantity = PositionClosureMath.decimal(snapshot.quantity) ?? 0
                let price = PositionClosureMath.decimal(snapshot.latestPrice) ?? 0
                let average = PositionClosureMath.decimal(snapshot.averageCost) ?? 0
                if quantity > 0, average > 0, price == 0, snapshot.quoteCurrency != DisplayCurrency.cny.rawValue {
                    throw PositionOpeningBalanceError.needsReview
                }
                let rate = quantity > 0 && price > 0 ? value / quantity / price : 1 / position.quoteCurrency.rateFromCNY
                try adjustClosurePortfolioSnapshot(day: snapshot.date, valueDelta: -value, costDelta: -quantity * average * rate)
            }
            try removeActiveClosurePosition(id: id)
            try deleteClosureAssetSnapshots(id: id.uuidString, from: "1970-01-01")
            record.reversedAt = Self.timestamp(from: now)
            try saveOpeningBalance(record)
            try writeDailySnapshots(positions: fetchPositions(), snapshotDate: now)
        }
    }

    func fetchPositionTrades() throws -> [PositionTradeRecord] {
        let statement = try prepare("SELECT payload_json FROM position_trades ORDER BY trade_date DESC, rowid DESC")
        defer { sqlite3_finalize(statement) }
        var records: [PositionTradeRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let record = try decoder.decode(PositionTradeRecord.self, from: Data(text(at: 0, in: statement).utf8))
            try record.validate()
            records.append(record)
        }
        return records.sorted { $0.tradeDate == $1.tradeDate ? $0.sequence > $1.sequence : $0.tradeDate > $1.tradeDate }
    }

    @discardableResult
    func recordTrade(id: UUID = UUID(), side: PositionTradeSide, expected: Position, quantity: Decimal,
                     price: Decimal, fees: Decimal, tradeDate: Date, cashPositionID: UUID?,
                     cashName: String, now: Date = .now, quoteUpdate: Position? = nil) throws -> PositionTradeRecord {
        let day = Self.dayString(from: tradeDate)
        guard day <= Self.dayString(from: now), tradeDate >= Date(timeIntervalSince1970: 0),
              quantity > 0, price >= 0, side != .buy || price > 0, fees >= 0,
              !quantity.isNaN, !price.isNaN, !fees.isNaN,
              expected.category != .cash || ((side == .add || side == .withdraw) && price == 1 && fees == 0),
              side != .withdraw || expected.category == .cash,
              side.usesCashAccount || cashPositionID == nil else { throw PositionTradeError.invalidInput }
        var result: PositionTradeRecord?
        try transaction {
            try ensureOpeningBalances(now: now)
            let records = try fetchPositionTrades()
            guard !records.contains(where: { $0.id == id }) else { throw PositionTradeError.changed }
            var positions = try fetchPositions()
            if let current = positions.first(where: { $0.id == expected.id }) {
                guard current.quantity == expected.quantity, current.totalCost == expected.totalCost,
                      current.costIsKnown == expected.costIsKnown,
                      current.symbol == expected.symbol, current.name == expected.name,
                      current.category == expected.category, current.quoteCurrency == expected.quoteCurrency else { throw PositionTradeError.changed }
            } else {
                guard !side.reducesBalance, !positions.contains(where: { $0.symbol == expected.symbol && $0.category == expected.category }),
                      !records.contains(where: { $0.asset.id == expected.id.uuidString }) else { throw PositionTradeError.changed }
            }
            if let quoteUpdate {
                guard (side == .add || side == .buy),
                      quoteUpdate.id == expected.id else { throw PositionTradeError.invalidInput }
                try PositionInputValidator.validate(quoteUpdate)
                guard try updateQuote(quoteUpdate) else { throw PositionTradeError.changed }
                positions = try fetchPositions()
            }
            let cash: Position?
            if !side.usesCashAccount {
                cash = nil
            } else if let cashPositionID, let selected = positions.first(where: { $0.id == cashPositionID }),
               selected.category == .cash, selected.quoteCurrency == expected.quoteCurrency {
                cash = selected
            } else {
                guard side == .sell, cashPositionID == nil,
                      !positions.contains(where: { $0.category == .cash && $0.symbol == expected.quoteCurrency.rawValue }) else {
                    throw PositionTradeError.insufficientCash
                }
                // A positive template is metadata only; the replay starts a new account at zero.
                cash = PositionClosureMath.cashPosition(currency: expected.quoteCurrency, quantity: 1, name: cashName)
            }
            let amount = expected.category == .cash ? quantity
                : PositionClosureMath.rounded(quantity * price, currency: expected.quoteCurrency) + (side == .sell ? -fees : fees)
            guard amount >= 0, !amount.isNaN else { throw PositionTradeError.invalidInput }
            let candidate = PositionTradeRecord(id: id, sequence: (records.map(\.sequence).max() ?? 0) + 1,
                side: side, asset: .init(position: positions.first { $0.id == expected.id } ?? expected, timestamp: Self.timestamp(from: now)),
                cash: cash.map { .init(position: $0, timestamp: Self.timestamp(from: now)) }, tradeDate: day,
                quantity: Self.decimalString(quantity), executionPrice: Self.decimalString(price), fees: Self.decimalString(fees),
                cashAmount: Self.decimalString(amount), allocatedCost: "0", rateFromCNY: Self.decimalString(expected.quoteCurrency.rateFromCNY),
                recordedAt: Self.timestamp(from: now), reversedAt: nil, priceHistory: [], effectiveAt: Self.timestamp(from: tradeDate))
            try candidate.validate()
            try requireAfterReconciliation(accountIDs: candidate.accountIDs, date: tradeDate)
            let later = connectedTradeRecords(records.filter { !$0.isReversed && PositionTradeRecord.precedes(candidate, $0) },
                accountIDs: candidate.accountIDs)
            try writeDailySnapshots(positions: positions, snapshotDate: now)
            let replayed = try replayTrades(old: later, new: [candidate] + later, from: day, now: now)
            try ensureOpeningBalances(now: now)
            result = replayed.first { $0.id == id }
        }
        guard let result else { throw PositionTradeError.invalidInput }
        return result
    }

    func reverseTrade(id: UUID, now: Date = .now) throws {
        try transaction {
            let records = try fetchPositionTrades()
            guard var record = records.first(where: { $0.id == id }), !record.isReversed else { throw PositionTradeError.changed }
            let affected = connectedTradeRecords(records.filter {
                !$0.isReversed && ($0.id == record.id || PositionTradeRecord.precedes(record, $0))
            }, accountIDs: record.accountIDs)
            _ = try replayTrades(old: affected, new: affected.filter { $0.id != id }, from: record.tradeDate, now: now,
                recordedBoundary: record.recordedAt)
            record.reversedAt = Self.timestamp(from: now)
            try saveTrade(record)
        }
    }

    private func saveTrade(_ record: PositionTradeRecord) throws {
        try record.validate()
        let statement = try prepare("INSERT INTO position_trades(id, trade_date, payload_json) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET trade_date = excluded.trade_date, payload_json = excluded.payload_json")
        defer { sqlite3_finalize(statement) }
        try bind(record.id.uuidString, to: 1, in: statement)
        try bind(record.tradeDate, to: 2, in: statement)
        try bind(String(decoding: encoder.encode(record), as: UTF8.self), to: 3, in: statement)
        try stepDone(statement)
    }

    private func connectedTradeRecords(_ candidates: [PositionTradeRecord], accountIDs: Set<String>) -> [PositionTradeRecord] {
        var ids = accountIDs
        var count = 0
        repeat {
            count = ids.count
            for trade in candidates where !ids.isDisjoint(with: trade.accountIDs) {
                ids.formUnion(trade.accountIDs)
            }
        } while ids.count != count
        return candidates.filter { !ids.isDisjoint(with: $0.accountIDs) }
    }

    private func replayTrades(old: [PositionTradeRecord], new: [PositionTradeRecord], from day: String,
                              now: Date, recordedBoundary: String? = nil) throws -> [PositionTradeRecord] {
        let today = Self.dayString(from: now)
        let current = try fetchPositions()
        let all = old + new
        var templates: [String: Position] = [:]
        for record in all {
            templates[record.asset.id] = try record.asset.position()
            if let cash = record.cash { templates[cash.id] = try cash.position() }
        }
        for position in current { templates[position.id.uuidString] = position }
        let ids = Set(all.flatMap { $0.accountIDs })
        for record in all {
            let effective = record.effectiveAt.flatMap { ISO8601DateFormatter().date(from: $0) }
                ?? PositionClosureMath.date(record.tradeDate)!
            try requireAfterReconciliation(accountIDs: ids, date: effective)
        }
        guard !(try fetchPositionClosures()).contains(where: { closure in
            !closure.isReversed && (closure.tradeDate > day ||
                (closure.tradeDate == day && recordedBoundary.map { $0 < closure.recordedAt } == true)) &&
                (ids.contains(closure.holding.id) || closure.cashPositionID.map(ids.contains) == true)
        }) else { throw PositionTradeError.dependentLegacyRecord }
        let currentBalances = Dictionary(uniqueKeysWithValues: current.map { ($0.id.uuidString, PositionTradeReplay.Balance(quantity: $0.quantity, cost: $0.totalCost)) })
        var opening = currentBalances
        for record in old {
            var asset = opening[record.asset.id] ?? .init(quantity: 0, cost: 0)
            asset.quantity -= record.quantityDelta
            asset.cost -= record.costDelta
            opening[record.asset.id] = asset
            if let account = record.cash {
                var cash = opening[account.id] ?? .init(quantity: 0, cost: 0)
                cash.quantity -= record.cashDelta
                cash.cost = cash.quantity
                opening[account.id] = cash
            }
        }
        for (id, balance) in opening where balance.quantity == 0 && abs(balance.cost.doubleValue) < 0.00000001 {
            opening[id]?.cost = 0
        }
        guard opening.values.allSatisfy({ $0.quantity >= 0 && $0.cost >= 0 && !$0.cost.isNaN }) else { throw PositionTradeError.historicalCorrection }
        // A reconciliation is an absolute balance, not a trade. Never reinterpret it as a cash flow.
        for id in ids {
            let statement = try prepare("SELECT created_at, snapshot_json FROM position_revisions WHERE position_id = ? AND operation IN ('update', 'balance_update', 'delete') ORDER BY created_at")
            defer { sqlite3_finalize(statement) }
            try bind(id, to: 1, in: statement)
            while sqlite3_step(statement) == SQLITE_ROW {
                let timestamp = text(at: 0, in: statement)
                guard let revisionDate = ISO8601DateFormatter().date(from: timestamp) else { continue }
                let revisionDay = Self.dayString(from: revisionDate)
                let afterBoundary = recordedBoundary.map { timestamp >= $0 } ?? (revisionDay > day)
                guard afterBoundary, revisionDay <= today else { continue }
                let snapshot = try decoder.decode([String: String].self, from: Data(text(at: 1, in: statement).utf8))
                var expected = opening[id] ?? .init(quantity: 0, cost: 0)
                for trade in old where trade.recordedAt < timestamp {
                    if trade.asset.id == id { expected.quantity += trade.quantityDelta; expected.cost += trade.costDelta }
                    if trade.cash?.id == id { expected.quantity += trade.cashDelta; expected.cost += trade.cashDelta }
                }
                var possibleBalances = [expected]
                // Older revision timestamps have second precision; preserve valid ordering within that second.
                for trade in old.filter({ $0.recordedAt == timestamp }).sorted(by: { $0.sequence < $1.sequence }) {
                    if trade.asset.id == id { expected.quantity += trade.quantityDelta; expected.cost += trade.costDelta }
                    if trade.cash?.id == id { expected.quantity += trade.cashDelta; expected.cost += trade.cashDelta }
                    possibleBalances.append(expected)
                }
                guard possibleBalances.contains(where: {
                    snapshot["quantity"].flatMap(PositionClosureMath.decimal) == $0.quantity &&
                    snapshot["totalCost"].flatMap(PositionClosureMath.decimal) == $0.cost
                }) else { throw PositionTradeError.historicalCorrection }
            }
        }
        var balances = opening
        var replayed: [PositionTradeRecord] = []
        for var trade in new.sorted(by: PositionTradeRecord.precedes) {
            try PositionTradeReplay.apply(&trade, to: &balances)
            try trade.validate()
            replayed.append(trade)
        }
        var identities = Set<String>()
        for (id, template) in templates where (balances[id]?.quantity ?? 0) > 0 {
            guard identities.insert("\(template.category.rawValue)/\(template.symbol.uppercased())").inserted else {
                throw PositionTradeError.identityConflict
            }
        }
        let history = try ids.flatMap { try closureAssetSnapshots(positionID: $0, from: "1970-01-01") }
        if day < today {
            for id in ids where (opening[id]?.quantity ?? 0) > 0 {
                guard history.contains(where: { $0.assetID == id && $0.date <= day }) else { throw PositionTradeError.missingHistory }
            }
        }
        // Check imported history too: imported backups may not contain revision rows.
        for snapshot in history where snapshot.date >= day && snapshot.date < today {
            var expected = opening[snapshot.assetID] ?? .init(quantity: 0, cost: 0)
            for trade in old where trade.tradeDate <= snapshot.date {
                if trade.asset.id == snapshot.assetID { expected.quantity += trade.quantityDelta; expected.cost += trade.costDelta }
                if trade.cash?.id == snapshot.assetID { expected.quantity += trade.cashDelta; expected.cost += trade.cashDelta }
            }
            guard PositionClosureMath.decimal(snapshot.quantity) == expected.quantity,
                  abs(((PositionClosureMath.decimal(snapshot.averageCost) ?? 0) * expected.quantity - expected.cost).doubleValue) < 0.000001 else {
                throw PositionTradeError.historicalCorrection
            }
        }
        let archive = all.flatMap(\.priceHistory)
        let portfolio = try closurePortfolioSnapshots(from: day)
        let dates = Set(history.filter { $0.date >= day }.map(\.date) + portfolio.map(\.date) + all.map(\.tradeDate) + [day])
        for date in dates.sorted() where date >= day && date <= today {
            for id in ids {
                guard let template = templates[id] else { continue }
                let snapshot = history.first { $0.assetID == id && $0.date == date }
                let reference = snapshot ?? archive.first { $0.assetID == id && $0.date == date }
                    ?? (history + archive).filter { $0.assetID == id && $0.date <= date }.max { $0.date < $1.date }
                let oldQuantity = snapshot.flatMap { PositionClosureMath.decimal($0.quantity) } ?? 0
                let oldCost = oldQuantity * (snapshot.flatMap { PositionClosureMath.decimal($0.averageCost) } ?? 0)
                var deltaQuantity = Decimal.zero
                var deltaCost = Decimal.zero
                for (trades, sign) in [(old, Decimal(-1)), (replayed, Decimal(1))] {
                    for trade in trades where trade.tradeDate <= date {
                        if trade.asset.id == id { deltaQuantity += sign * trade.quantityDelta; deltaCost += sign * trade.costDelta }
                        if trade.cash?.id == id { deltaQuantity += sign * trade.cashDelta; deltaCost += sign * trade.cashDelta }
                    }
                }
                guard deltaQuantity != 0 || deltaCost != 0 else { continue }
                let quantity = oldQuantity + deltaQuantity
                let rawCost = oldCost + deltaCost
                // A stored average can round repeating decimals; a fully sold position has exactly zero cost.
                let cost: Decimal = quantity == 0 && abs(rawCost.doubleValue) < 0.00000001 ? 0 : rawCost
                guard quantity >= 0, cost >= 0 else { throw PositionTradeError.historicalCorrection }
                let price = reference.flatMap { PositionClosureMath.decimal($0.latestPrice) }
                    ?? (template.category == .cash ? 1 : replayed.last { $0.asset.id == id && $0.tradeDate <= date }?.price)
                    ?? template.latestPrice
                let referenceQuantity = reference.flatMap { PositionClosureMath.decimal($0.quantity) } ?? 0
                let referencePrice = reference.flatMap { PositionClosureMath.decimal($0.latestPrice) } ?? 0
                let unitRate = referenceQuantity > 0 && referencePrice > 0
                    ? (reference.flatMap { PositionClosureMath.decimal($0.marketValueCNY) } ?? 0) / referenceQuantity / referencePrice
                    : 1 / template.quoteCurrency.rateFromCNY
                let oldValue = snapshot.flatMap { PositionClosureMath.decimal($0.marketValueCNY) } ?? 0
                if portfolio.contains(where: { $0.date == date }) {
                    try adjustClosurePortfolioSnapshot(day: date, valueDelta: quantity * price * unitRate - oldValue, costDelta: deltaCost * unitRate)
                }
                if quantity == 0 {
                    // Retain only prices being removed. Partial trades do not duplicate a year's history.
                    if let snapshot, let index = replayed.firstIndex(where: { $0.accountIDs.contains(id) }),
                       !replayed[index].priceHistory.contains(where: { $0.assetID == id && $0.date == date }) {
                        replayed[index].priceHistory.append(snapshot)
                    }
                    try deleteClosureAssetSnapshot(id: id, day: date)
                }
                else {
                    try writeClosureAssetSnapshot(.init(assetID: id, date: date, name: template.name, symbol: template.symbol,
                        category: template.category.rawValue, quoteCurrency: template.quoteCurrency.rawValue,
                        quantity: Self.decimalString(quantity), averageCost: Self.decimalString(cost / quantity),
                        latestPrice: Self.decimalString(price), marketValueCNY: Self.decimalString(quantity * price * unitRate),
                        source: reference?.source ?? "交易记账", quoteTime: reference?.quoteTime ?? date,
                        freshness: reference?.freshness ?? Freshness.manual.rawValue, updatedAt: Self.timestamp(from: now)))
                }
            }
        }
        for id in ids {
            guard let template = templates[id], let uuid = UUID(uuidString: id) else { throw PositionTradeError.invalidInput }
            let balance = balances[id] ?? .init(quantity: 0, cost: 0)
            if balance.quantity == 0 { try removeActiveClosurePosition(id: uuid); try deleteClosureAssetSnapshot(id: id, day: today) }
            else {
                let updated = Position(id: uuid, name: template.name, symbol: template.symbol, category: template.category,
                    quoteCurrency: template.quoteCurrency, quantity: balance.quantity, totalCost: balance.cost,
                    averageCost: balance.cost / balance.quantity, latestPrice: template.latestPrice,
                    marketValueCNY: balance.quantity * template.latestPrice / template.quoteCurrency.rateFromCNY,
                    profitRate: balance.cost == 0 ? 0 : (balance.quantity * template.latestPrice / balance.cost - 1) * 100,
                    weeklyTrend: template.weeklyTrend, source: template.source, quoteTime: template.quoteTime,
                    fetchedAt: template.fetchedAt, freshness: template.freshness)
                try PositionInputValidator.validate(updated)
                try save(updated, operation: "trade")
            }
        }
        for record in replayed { try saveTrade(record) }
        try writeDailySnapshots(positions: fetchPositions(), snapshotDate: now)
        return replayed
    }

    // Corrections remove the artificial P&L caused by applying end-of-day balances to pre-trade prices.
    func tradeDailyProfitAdjustments(through date: Date = .now) throws -> [String: [String: Decimal]] {
        let end = Self.dayString(from: date)
        let trades = try fetchPositionTrades().filter { !$0.isReversed && $0.tradeDate <= end }

        let statement = try prepare("SELECT asset_id, snapshot_date, quantity, market_value_cny FROM asset_price_snapshots WHERE snapshot_date <= ?")
        defer { sqlite3_finalize(statement) }
        try bind(end, to: 1, in: statement)
        var units: [String: [String: Decimal]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let quantity = PositionClosureMath.decimal(text(at: 2, in: statement)), quantity > 0,
                  let value = PositionClosureMath.decimal(text(at: 3, in: statement)) else { throw PositionTradeError.invalidInput }
            units[text(at: 0, in: statement), default: [:]][text(at: 1, in: statement)] = value / quantity
        }
        let inputs = trades.map { RecordedTradeProfit(assetID: $0.asset.id, cashID: $0.cash?.id, side: $0.side.rawValue,
            tradeDate: $0.tradeDate, quantity: $0.quantity, executionPrice: $0.executionPrice, fees: $0.fees,
            cashAmount: $0.cashAmount, rateFromCNY: $0.rateFromCNY,
            priceHistory: $0.priceHistory.map { .init(assetID: $0.assetID, date: $0.date, quantity: $0.quantity, marketValueCNY: $0.marketValueCNY) }) }
        var adjustments = RecordedTradeProfit.adjustments(trades: inputs, unitValues: units, through: end)
        for record in try fetchReconciliations() where record.effectiveDay <= end {
            if let value = record.profitAdjustmentCNY.flatMap(PositionClosureMath.decimal) {
                adjustments[record.effectiveDay, default: [:]][record.asset.id, default: 0] += value
            }
            if let day = record.reversalDay, day <= end, let value = record.reversalProfitAdjustmentCNY.flatMap(PositionClosureMath.decimal) {
                adjustments[day, default: [:]][record.asset.id, default: 0] += value
            }
        }
        return adjustments
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

extension PositionRepository {
    func fetchReconciliations() throws -> [PositionReconciliationRecord] {
        let statement = try prepare("SELECT payload_json FROM position_reconciliations ORDER BY sequence")
        defer { sqlite3_finalize(statement) }
        var records: [PositionReconciliationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let record = try decoder.decode(PositionReconciliationRecord.self, from: Data(text(at: 0, in: statement).utf8))
            try record.validate()
            records.append(record)
        }
        return records
    }

    private func saveReconciliation(_ record: PositionReconciliationRecord) throws {
        try record.validate()
        let statement = try prepare("INSERT INTO position_reconciliations(id, asset_id, sequence, payload_json) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload_json = excluded.payload_json")
        defer { sqlite3_finalize(statement) }
        try bind(record.id.uuidString, to: 1, in: statement)
        try bind(record.asset.id, to: 2, in: statement)
        try bind(record.sequence, to: 3, in: statement)
        try bind(String(decoding: encoder.encode(record), as: UTF8.self), to: 4, in: statement)
        try stepDone(statement)
    }

    private func snapshotCostIsKnown(day: String, records: [RecordedReconciliation]? = nil) throws -> Bool {
        let records = try records ?? reconciliationInputs()
        guard !records.isEmpty else { return true }
        let statement = try prepare("SELECT asset_id FROM asset_price_snapshots WHERE snapshot_date = ?")
        defer { sqlite3_finalize(statement) }
        try bind(day, to: 1, in: statement)
        var ids = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW { ids.insert(text(at: 0, in: statement)) }
        return RecordedReconciliation.costKnown(records, assetIDs: ids, through: day)
    }

    private func reconciliationInputs() throws -> [RecordedReconciliation] {
        try fetchReconciliations().map { try decoder.decode(RecordedReconciliation.self, from: encoder.encode($0)) }
    }

    private func costIsKnown(for id: UUID) throws -> Bool {
        try fetchReconciliations().last { !$0.isReversed && $0.asset.id == id.uuidString }?.costKnown ?? true
    }

    private func requireAfterReconciliation(accountIDs: Set<String>, date: Date) throws {
        for record in try fetchReconciliations() where accountIDs.contains(record.asset.id) {
            guard let checkpoint = ISO8601DateFormatter().date(from: record.reversedAt ?? record.effectiveAt), date > checkpoint else {
                throw PositionTradeError.historicalCorrection
            }
        }
    }

    @discardableResult
    func reconcilePosition(expected: Position, quantity: Decimal, totalCost: Decimal?, reason: String,
                           note: String = "", now: Date = .now) throws -> PositionReconciliationRecord {
        guard !quantity.isNaN, quantity >= 0, abs(quantity.doubleValue) <= 1e28,
              totalCost == nil || (!totalCost!.isNaN && totalCost! >= 0 && abs(totalCost!.doubleValue) <= 1e28)
        else { throw PositionTradeError.invalidInput }
        var result: PositionReconciliationRecord?
        try transaction {
            try ensureOpeningBalances(now: now)
            guard let current = try fetchPosition(id: expected.id), current.quantity == expected.quantity,
                  current.totalCost == expected.totalCost, current.costIsKnown == expected.costIsKnown,
                  current.symbol == expected.symbol, current.category == expected.category,
                  current.quoteCurrency == expected.quoteCurrency else { throw PositionTradeError.changed }
            let records = try fetchReconciliations()
            let timestamp = Self.timestamp(from: now)
            // Unknown cost is carried internally; it must never be presented as a known zero cost.
            let known = quantity == 0 || current.category == .cash || totalCost != nil
            let cost = quantity == 0 ? 0 : current.category == .cash ? quantity : totalCost ?? current.totalCost
            guard quantity != current.quantity || cost != current.totalCost || known != current.costIsKnown else {
                throw PositionTradeError.unchangedBalance
            }
            let quote = current.latestPrice / current.quoteCurrency.rateFromCNY
            let reference = try dailyPriceBaseline(for: current.id, asOf: now).map { $0.unitValueCNY ?? $0.price / current.quoteCurrency.rateFromCNY }
            let reliable = current.category == .cash || current.wasFetchedOnSameDay(as: now)
            let baseline = current.quantity == quantity ? (reference ?? quote) : current.category == .cash ? quote : reliable ? reference : nil
            let adjustment = baseline.map { (current.quantity - quantity) * (quote - $0) }
            let record = PositionReconciliationRecord(id: UUID(), sequence: (records.map(\.sequence).max() ?? 0) + 1,
                asset: .init(position: current, timestamp: timestamp), quantity: Self.decimalString(quantity),
                totalCost: Self.decimalString(cost), costKnown: known, effectiveAt: timestamp,
                effectiveDay: Self.dayString(from: now), quoteUnitCNY: Self.decimalString(quote),
                baselineUnitCNY: baseline.map(Self.decimalString), profitAdjustmentCNY: adjustment.map(Self.decimalString),
                reason: reason, note: note, reversedAt: nil)
            try record.validate()
            if quantity == 0 {
                try removeActiveClosurePosition(id: current.id)
                try deleteClosureAssetSnapshot(id: current.id.uuidString, day: record.effectiveDay)
            } else {
                let updated = Position(id: current.id, name: current.name, symbol: current.symbol,
                    category: current.category, quoteCurrency: current.quoteCurrency, quantity: quantity, totalCost: cost,
                    averageCost: cost / quantity, latestPrice: current.latestPrice,
                    marketValueCNY: quantity * quote, profitRate: cost == 0 ? 0 : (quantity * current.latestPrice / cost - 1) * 100,
                    weeklyTrend: current.weeklyTrend, source: current.source, quoteTime: current.quoteTime,
                    fetchedAt: current.fetchedAt, freshness: current.freshness, costIsKnown: known)
                try PositionInputValidator.validate(updated)
                try save(updated, operation: "reconciliation")
            }
            try saveReconciliation(record)
            try writeDailySnapshots(positions: fetchPositions(), snapshotDate: now)
            result = record
        }
        guard let result else { throw PositionTradeError.changed }
        return result
    }

    func reverseReconciliation(id: UUID, now: Date = .now) throws {
        try transaction {
            let records = try fetchReconciliations()
            guard var record = records.first(where: { $0.id == id }), !record.isReversed else { throw PositionTradeError.changed }
            guard !records.contains(where: { !$0.isReversed && $0.asset.id == record.asset.id && $0.sequence > record.sequence }),
                  !(try fetchPositionTrades()).contains(where: { !$0.isReversed && $0.accountIDs.contains(record.asset.id) && $0.recordedAt >= record.effectiveAt }),
                  !(try fetchPositionClosures()).contains(where: { !$0.isReversed && ($0.holding.id == record.asset.id || $0.cashPositionID == record.asset.id) && $0.recordedAt >= record.effectiveAt })
            else { throw PositionTradeError.dependentTrade }
            let before = try record.asset.position()
            let current = try fetchPosition(id: before.id)
            guard (current?.quantity ?? 0) == record.units,
                  abs(((current?.totalCost ?? 0) - record.cost).doubleValue) < 0.000001 else { throw PositionTradeError.changed }
            let quote = current ?? before
            let restored = Position(id: before.id, name: before.name, symbol: before.symbol,
                category: before.category, quoteCurrency: before.quoteCurrency, quantity: before.quantity,
                totalCost: before.totalCost, averageCost: before.averageCost, latestPrice: quote.latestPrice,
                marketValueCNY: before.quantity * quote.latestPrice / before.quoteCurrency.rateFromCNY,
                profitRate: before.averageCost == 0 ? 0 : (quote.latestPrice / before.averageCost - 1) * 100,
                weeklyTrend: quote.weeklyTrend, source: quote.source, quoteTime: quote.quoteTime,
                fetchedAt: quote.fetchedAt, freshness: quote.freshness, costIsKnown: before.costIsKnown)
            try save(restored, operation: "reconciliation_reverse")
            record.reversedAt = Self.timestamp(from: now)
            record.reversalDay = Self.dayString(from: now)
            let baseline = try dailyPriceBaseline(for: before.id, asOf: now).map { $0.unitValueCNY ?? $0.price / before.quoteCurrency.rateFromCNY }
            let reference = before.category == .cash ? quote.latestPrice / before.quoteCurrency.rateFromCNY : baseline
            record.reversalProfitAdjustmentCNY = record.units == before.quantity ? "0" : reference.flatMap { base in
                (before.category == .cash || quote.wasFetchedOnSameDay(as: now))
                    ? Self.decimalString((record.units - before.quantity) * (quote.latestPrice / before.quoteCurrency.rateFromCNY - base)) : nil
            }
            try saveReconciliation(record)
            // Historical checkpoints remain historical. Only today's snapshot is refreshed.
            try writeDailySnapshots(positions: fetchPositions(), snapshotDate: now)
        }
    }
}
