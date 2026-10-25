import Foundation

public enum MCPAccess {
    public static let settingKey = "mcp_read_access_enabled"

    public enum Client: String, CaseIterable, Sendable {
        case codex, claudeCode, claudeDesktop, deepSeekHarness, workBuddy

        public var title: String {
            switch self {
            case .codex: "ChatGPT / Codex"
            case .claudeCode: "Claude Code"
            case .claudeDesktop: "Claude Desktop"
            case .deepSeekHarness: "DeepSeek Harness"
            case .workBuddy: "WorkBuddy"
            }
        }

        public var configurationFormat: String {
            switch self {
            case .codex: "TOML"
            case .deepSeekHarness: "YAML"
            default: "JSON"
            }
        }

        public var documentationURL: URL {
            let url: String = switch self {
            case .codex: "https://learn.chatgpt.com/docs/extend/mcp"
            case .claudeCode: "https://code.claude.com/docs/en/mcp"
            case .claudeDesktop: "https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop"
            case .deepSeekHarness: "https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/mcp/mcp-client/README.md"
            case .workBuddy: "https://open.workbuddy.cn/docs/connector"
            }
            return URL(string: url)!
        }
    }

    public static func executableURL(appBundleURL: URL) -> URL {
        appBundleURL.appendingPathComponent("Contents/MacOS/PortfolixMCP")
    }

    /// Produces instructions only; never edits another application's configuration.
    public static func connectionCommand(for client: Client, executableURL: URL) -> String? {
        let command = shellQuote(executableURL.path)
        switch client {
        case .codex: return "codex mcp add portfolix -- \(command)"
        case .claudeCode: return "claude mcp add --transport stdio --scope user portfolix -- \(command)"
        case .claudeDesktop, .deepSeekHarness, .workBuddy: return nil
        }
    }

    public static func configuration(for client: Client, executableURL: URL) throws -> String {
        if client == .codex {
            // A JSON basic string is also a valid TOML basic string.
            let path = try JSONSerialization.data(withJSONObject: executableURL.path, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return "[mcp_servers.portfolix]\ncommand = \(String(decoding: path, as: UTF8.self))\nargs = []"
        }
        if client == .deepSeekHarness {
            // JSON double-quoted strings are valid YAML scalars, including escaped paths.
            let path = try JSONSerialization.data(withJSONObject: executableURL.path, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return """
                - insert:
                    - id: mcp-portfolix
                      name: '@deepseek-ai/dsh-mcp-client'
                      config:
                        serverName: portfolix
                        transport: stdio
                        command: \(String(decoding: path, as: UTF8.self))
                        args: []
                """
        }
        if client == .workBuddy {
            return try jsonConfiguration(executableURL: executableURL, explicitTransport: true)
        }
        return try clientConfiguration(executableURL: executableURL)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func databaseURL(appBundleURL: URL?) -> URL {
        let identifier = appBundleURL.flatMap { Bundle(url: $0)?.bundleIdentifier } ?? "app.portfolix.mac"
        let safeIdentifier = !identifier.isEmpty && identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
            && identifier != "." && identifier != ".." ? identifier : "app.portfolix.mac"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent(safeIdentifier).appendingPathComponent("portfolix.sqlite3")
    }

    public static func clientConfiguration(executableURL: URL) throws -> String {
        try jsonConfiguration(executableURL: executableURL, explicitTransport: false)
    }

    private static func jsonConfiguration(executableURL: URL, explicitTransport: Bool) throws -> String {
        var server: [String: Any] = ["command": executableURL.path]
        if explicitTransport { server["type"] = "stdio" }
        let value: [String: Any] = ["mcpServers": ["portfolix": server]]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
