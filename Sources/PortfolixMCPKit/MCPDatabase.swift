import Foundation
import CSQLite
import PortfolixCore

enum MCPFailure: Error {
    case unavailable, disabled, invalidArguments, queryLimit, invalidData

    var message: String {
        switch self {
        case .unavailable: "Local portfolio data is unavailable. Open Portfolix and retry."
        case .disabled: "Read access is disabled. Enable MCP Server in Portfolix settings first."
        case .invalidArguments: "Invalid arguments. Use the advertised tool schema and a date range of at most 366 days."
        case .queryLimit: "The query exceeds the safe size or time limit. Request a smaller range."
        case .invalidData: "Stored data could not be interpreted. No partial financial result was returned."
        }
    }
}

final class MCPDatabase {
    private var handle: OpaquePointer?
    private var deadline = ContinuousClock.now

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            handle = nil
            throw MCPFailure.unavailable
        }
        sqlite3_busy_timeout(handle, 500)
        sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 2_000_000)
        guard sqlite3_exec(handle, "PRAGMA query_only = ON; PRAGMA trusted_schema = OFF", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            handle = nil
            throw MCPFailure.unavailable
        }
        sqlite3_progress_handler(handle, 1_000, { context in
            guard let context else { return 1 }
            let database = Unmanaged<MCPDatabase>.fromOpaque(context).takeUnretainedValue()
            return ContinuousClock.now > database.deadline ? 1 : 0
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { sqlite3_close(handle) }

    func checkAccess() throws {
        let rows = try query("SELECT value FROM app_settings WHERE key = ?", [MCPAccess.settingKey])
        guard rows.first?["value"] == "true" else { throw MCPFailure.disabled }
    }

    /// Keep multi-query results consistent, then check revocation outside this snapshot.
    func readSnapshot<T>(_ body: () throws -> T) throws -> T {
        deadline = ContinuousClock.now.advanced(by: .seconds(2))
        guard sqlite3_exec(handle, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw MCPFailure.unavailable }
        defer { sqlite3_exec(handle, "ROLLBACK", nil, nil, nil) }
        let result = try body()
        guard sqlite3_exec(handle, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw MCPFailure.unavailable }
        return result
    }

    func query(_ sql: String, _ parameters: [String] = [], limit: Int = 20_000) throws -> [[String: String]] {
        var rows: [[String: String]] = []
        try forEachRow(sql, parameters, limit: limit, byteLimit: 2_000_000) { rows.append($0) }
        return rows
    }

    func forEachRow(_ sql: String, _ parameters: [String] = [], limit: Int = 200_000, byteLimit: Int = 32_000_000,
                    _ body: ([String: String]) throws -> Void) throws {
        if sqlite3_get_autocommit(handle) != 0 { deadline = ContinuousClock.now.advanced(by: .seconds(2)) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MCPFailure.unavailable
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_stmt_readonly(statement) != 0 else { throw MCPFailure.unavailable }
        for (index, value) in parameters.enumerated() {
            let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, Int32(value.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw MCPFailure.unavailable }
        }
        var rowCount = 0
        var byteCount = 0
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return }
            guard status == SQLITE_ROW else { throw status == SQLITE_INTERRUPT ? MCPFailure.queryLimit : MCPFailure.unavailable }
            rowCount += 1
            guard rowCount <= limit, ContinuousClock.now <= deadline else { throw MCPFailure.queryLimit }
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                      let name = sqlite3_column_name(statement, index), let value = sqlite3_column_text(statement, index) else { continue }
                let length = Int(sqlite3_column_bytes(statement, index))
                byteCount += length
                guard byteCount <= byteLimit else { throw MCPFailure.queryLimit }
                guard let text = String(bytes: UnsafeBufferPointer(start: value, count: length), encoding: .utf8) else { throw MCPFailure.invalidData }
                row[String(cString: name)] = text
            }
            try body(row)
        }
    }
}
