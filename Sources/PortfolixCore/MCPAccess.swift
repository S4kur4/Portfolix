import Foundation

public enum MCPAccess {
    public static let settingKey = "mcp_read_access_enabled"

    public static func databaseURL(appBundleURL: URL?) -> URL {
        let identifier = appBundleURL.flatMap { Bundle(url: $0)?.bundleIdentifier } ?? "app.portfolix.mac"
        let safeIdentifier = !identifier.isEmpty && identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
            && identifier != "." && identifier != ".." ? identifier : "app.portfolix.mac"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent(safeIdentifier).appendingPathComponent("portfolix.sqlite3")
    }

    public static func clientConfiguration(executableURL: URL) throws -> String {
        let value: [String: Any] = ["mcpServers": ["portfolix": ["command": executableURL.path, "args": [String]()]]]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
