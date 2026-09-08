import Foundation
import Testing
import PortfolixCore
@testable import Portfolix
@testable import PortfolixMCPKit

struct MCPTests {
    @Test
    func clientConfigurationEscapesExecutablePath() throws {
        let url = URL(fileURLWithPath: "/Applications/Portfolix \"Test\".app/Contents/MacOS/PortfolixMCP")
        let config = try MCPAccess.clientConfiguration(executableURL: url)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
        let servers = try #require(json["mcpServers"] as? [String: [String: Any]])
        #expect(servers["portfolix"]?["command"] as? String == url.path)
        #expect(servers["portfolix"]?["env"] == nil)
    }

    @Test
    func mcpRejectsMalformedInputAndRequiresInitialization() throws {
        let server = PortfolioMCPServer(databaseURL: URL(fileURLWithPath: "/nonexistent/portfolix.sqlite3"))
        let malformed = try decode(server.respond(to: Data("{".utf8)))
        #expect((malformed["error"] as? [String: Any])?["code"] as? Int == -32700)
        let large = try decode(server.respond(to: Data(repeating: 32, count: 65_537)))
        #expect((large["error"] as? [String: Any])?["code"] as? Int == -32600)
        let early = try request(server, method: "tools/list")
        #expect(early["error"] != nil)
        try initialize(server)
        let listed = try request(server, method: "tools/list")
        let tools = try #require((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.count == 5)
        #expect(tools.allSatisfy { ($0["annotations"] as? [String: Bool])?["readOnlyHint"] == true })
        let unavailable = try call(server, name: "get_portfolio_summary")
        #expect(unavailable["isError"] as? Bool == true)
        let unknown = try request(server, method: "tools/call", params: ["name": "execute_sql", "arguments": ["sql": "SELECT * FROM app_settings"]])
        #expect(unknown["error"] != nil)
    }

    @Test
    func mcpAccessIsOptInRevocableAndNeverReturnsSettings() throws {
        let fixture = try Fixture()
        try initialize(fixture.server)
        #expect(try call(fixture.server, name: "list_holdings")["isError"] as? Bool == true)
        try fixture.repository.setAppSetting(key: "llm_api_key", value: "test-secret-must-not-leak")
        try fixture.repository.setAppSetting(key: MCPAccess.settingKey, value: "true")
        let allowed = try call(fixture.server, name: "list_holdings")
        #expect(allowed["isError"] as? Bool == false)
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: allowed), as: UTF8.self)
        #expect(!serialized.contains("test-secret-must-not-leak"))
        try fixture.repository.setAppSetting(key: MCPAccess.settingKey, value: "false")
        #expect(try call(fixture.server, name: "list_holdings")["isError"] as? Bool == true)
        let readOnly = try MCPDatabase(url: fixture.url)
        #expect(throws: (any Error).self) { try readOnly.query("DELETE FROM positions") }
        #expect(try fixture.repository.appSetting(for: "llm_api_key") == "test-secret-must-not-leak")
    }

    @Test
    func mcpValidatesBoundsAndNeverAcceptsSQLOrPaths() throws {
        let fixture = try Fixture()
        try initialize(fixture.server)
        try fixture.repository.setAppSetting(key: MCPAccess.settingKey, value: "true")
        for args: [String: Any] in [["limit": 101], ["limit": true], ["limit": 1.5], ["offset": -1], ["path": "/etc/passwd"]] {
            #expect(try call(fixture.server, name: "list_holdings", arguments: args)["isError"] as? Bool == true)
        }
        for (start, end) in [("2026-02-30", "2026-03-01"), ("2026-07-02", "2026-07-01"), ("2024-01-01", "2026-01-01"), ("2026-7-01", "2026-07-01")] {
            #expect(try call(fixture.server, name: "get_daily_profit", arguments: ["start_date": start, "end_date": end])["isError"] as? Bool == true)
        }
        #expect(try call(fixture.server, name: "get_asset_price_history", arguments: [
            "asset_id": "' OR 1=1 --", "start_date": "2026-07-01", "end_date": "2026-07-02"
        ])["isError"] as? Bool == true)
    }

    @Test
    func mcpPaginatesHoldingsAndReturnsSnapshotDates() throws {
        let fixture = try Fixture()
        for index in 0..<3 {
            let position = Position(id: UUID(), name: "Holding \(index)", symbol: "TEST\(index)", category: .cnStock,
                quoteCurrency: .cny, quantity: 10, averageCost: 90, latestPrice: 100,
                marketValueCNY: 1000, profitRate: 0, weeklyTrend: [], source: "手工价格", quoteTime: "2026-09-08", freshness: .manual)
            try fixture.repository.insert(position)
        }
        try fixture.repository.setAppSetting(key: MCPAccess.settingKey, value: "true")
        try initialize(fixture.server)
        let first = try #require(try call(fixture.server, name: "list_holdings", arguments: ["limit": 2])["structuredContent"] as? [String: Any])
        let last = try #require(try call(fixture.server, name: "list_holdings", arguments: ["limit": 2, "offset": 2])["structuredContent"] as? [String: Any])
        let firstRows = try #require(first["holdings"] as? [[String: String]])
        let lastRows = try #require(last["holdings"] as? [[String: String]])
        #expect(first["next_offset"] as? Int == 2)
        #expect(last["next_offset"] is NSNull)
        #expect(Set((firstRows + lastRows).compactMap { $0["asset_id"] }).count == 3)
        #expect(firstRows.allSatisfy { $0["quantity"] == "10" && $0["quote_currency"] == "CNY" })
        let summary = try #require(try call(fixture.server, name: "get_portfolio_summary")["structuredContent"] as? [String: Any])
        #expect(summary["holdings_count"] as? String == "3")
        #expect(summary["read_at"] is String)
        let readOnly = try MCPDatabase(url: fixture.url)
        #expect(throws: (any Error).self) { try readOnly.query("DELETE FROM positions") }
        #expect(try fixture.repository.fetchPositions().count == 3)
    }

    @Test
    func mcpStdioHandlesFragmentedInputOversizeAndEOF() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = root.appendingPathComponent(".build/debug/PortfolixMCP")
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
        defer { watchdog.cancel() }
        try input.fileHandleForWriting.write(contentsOf: Data("{\"jsonrpc\":\"2.0\",\"id\":1,".utf8))
        try input.fileHandleForWriting.write(contentsOf: Data("\"method\":\"ping\"}\n".utf8))
        try input.fileHandleForWriting.write(contentsOf: Data(repeating: 32, count: 65_537))
        try input.fileHandleForWriting.write(contentsOf: Data("\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}\n".utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let lines = data.split(separator: 10)
        #expect(lines.count == 3)
        let messages = try lines.map { try decode(Data($0)) }
        #expect(messages.first?["id"] as? Int == 1)
        #expect((messages[1]["error"] as? [String: Any])?["code"] as? Int == -32600)
        #expect(messages.last?["id"] as? Int == 2)
    }

    @Test
    func mcpDailyProfitMatchesAppWithQuantityChangesAndRangePredecessor() throws {
        let fixture = try Fixture()
        let id = UUID()
        let day = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        for (offset, quantity, price): (Int, Decimal, Decimal) in [(0,10,100), (1,20,105), (2,20,105), (3,20,103)] {
            let date = try #require(Calendar.current.date(byAdding: .day, value: offset, to: day))
            let position = Position(id: id, name: "MCP Test", symbol: "TEST", category: .cnStock, quoteCurrency: .cny,
                quantity: quantity, averageCost: 90, latestPrice: price, marketValueCNY: quantity * price,
                profitRate: 0, weeklyTrend: [], source: "手工价格", quoteTime: "2026-07-01", freshness: .manual)
            try fixture.repository.replaceDailySnapshots(positions: [position], snapshotDate: date)
        }
        try fixture.repository.setAppSetting(key: MCPAccess.settingKey, value: "true")
        try initialize(fixture.server)
        let response = try call(fixture.server, name: "get_daily_profit", arguments: ["start_date": "2026-07-02", "end_date": "2026-07-04"])
        let content = try #require(response["structuredContent"] as? [String: Any])
        let days = try #require(content["days"] as? [[String: String]])
        let end = try #require(Calendar.current.date(byAdding: .day, value: 3, to: day))
        let app = try fixture.repository.fetchDailyProfitPoints(limitDays: 3, through: end)
        #expect(days.compactMap { Decimal(string: $0["amount_cny"] ?? "") } == app.map(\.amountCNY))
        #expect(days.map { $0["date"] } == ["2026-07-02", "2026-07-03", "2026-07-04"])
        let history = try call(fixture.server, name: "get_portfolio_history", arguments: ["start_date": "2026-07-01", "end_date": "2026-07-04"])
        #expect(((history["structuredContent"] as? [String: Any])?["snapshots"] as? [[String: String]])?.count == 4)
        let prices = try call(fixture.server, name: "get_asset_price_history", arguments: ["asset_id": id.uuidString, "start_date": "2026-07-01", "end_date": "2026-07-04"])
        #expect(((prices["structuredContent"] as? [String: Any])?["snapshots"] as? [[String: String]])?.count == 4)
    }

    private func initialize(_ server: PortfolioMCPServer) throws {
        let response = try request(server, method: "initialize", params: ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "Tests", "version": "1"]])
        #expect((response["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-11-25")
        let notification = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        #expect(server.respond(to: notification) == nil)
    }

    private func call(_ server: PortfolioMCPServer, name: String, arguments: [String: Any] = [:]) throws -> [String: Any] {
        let response = try request(server, method: "tools/call", params: ["name": name, "arguments": arguments])
        return try #require(response["result"] as? [String: Any])
    }
    private func request(_ server: PortfolioMCPServer, method: String, params: [String: Any] = [:]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        return try decode(server.respond(to: data))
    }
    private func decode(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private struct Fixture {
        let url: URL
        let repository: PositionRepository
        let server: PortfolioMCPServer
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("Portfolix-MCP-tests-\(UUID())/portfolio.sqlite3")
            repository = try PositionRepository(databaseURL: url)
            server = PortfolioMCPServer(databaseURL: url)
        }
    }
}
