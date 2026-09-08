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
    private var deadline = Date.distantPast

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            handle = nil
            throw MCPFailure.unavailable
        }
        sqlite3_busy_timeout(handle, 500)
        sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 2_000_000)
        guard sqlite3_exec(handle, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            handle = nil
            throw MCPFailure.unavailable
        }
        sqlite3_progress_handler(handle, 1_000, { context in
            guard let context else { return 1 }
            let database = Unmanaged<MCPDatabase>.fromOpaque(context).takeUnretainedValue()
            return Date() > database.deadline ? 1 : 0
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { sqlite3_close(handle) }

    func checkAccess() throws {
        let rows = try query("SELECT value FROM app_settings WHERE key = ?", [MCPAccess.settingKey])
        guard rows.first?["value"] == "true" else { throw MCPFailure.disabled }
    }

    func query(_ sql: String, _ parameters: [String] = [], limit: Int = 20_000) throws -> [[String: String]] {
        deadline = Date().addingTimeInterval(2)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MCPFailure.unavailable
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_stmt_readonly(statement) != 0 else { throw MCPFailure.unavailable }
        for (index, value) in parameters.enumerated() {
            let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw MCPFailure.unavailable }
        }
        var rows: [[String: String]] = []
        var byteCount = 0
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw status == SQLITE_INTERRUPT ? MCPFailure.queryLimit : MCPFailure.unavailable }
            guard rows.count < limit else { throw MCPFailure.queryLimit }
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                      let name = sqlite3_column_name(statement, index), let value = sqlite3_column_text(statement, index) else { continue }
                byteCount += Int(sqlite3_column_bytes(statement, index))
                guard byteCount <= 2_000_000 else { throw MCPFailure.queryLimit }
                row[String(cString: name)] = String(cString: value)
            }
            rows.append(row)
        }
    }
}
