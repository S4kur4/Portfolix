import Foundation
import Darwin
import PortfolixMCPKit
import PortfolixCore

// No command-line path or environment override can grant access to an arbitrary database.
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let appBundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let database = MCPAccess.databaseURL(appBundleURL: appBundle.pathExtension == "app" ? appBundle : nil)
let version = (Bundle(url: appBundle)?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.1.0"
let options = Array(CommandLine.arguments.dropFirst())
if !options.isEmpty {
    switch options {
    case ["--version"]:
        print("PortfolixMCP \(version)")
    case ["--help"]:
        print("""
            PortfolixMCP: read-only local MCP server over stdio.
            Run with no arguments for JSON-RPC. No network listener, API key or runtime installation is needed.
            --version       Show the bundled version.
            --help          Show this help.
            Enable MCP Server in Portfolix settings before reading data. No database path overrides are accepted.
            """)
    default:
        FileHandle.standardError.write(Data("Unsupported arguments. Run PortfolixMCP --help.\n".utf8))
        exit(64)
    }
    exit(0)
}
let server = PortfolioMCPServer(databaseURL: database, serverVersion: version)
var line = Data()
var oversized = false
var buffer = [UInt8](repeating: 0, count: 4096)
signal(SIGPIPE, SIG_IGN)

func send(_ data: Data?) {
    guard var data else { return }
    data.append(10)
    do { try FileHandle.standardOutput.write(contentsOf: data) } catch { exit(0) }
}

while true {
    let count = read(STDIN_FILENO, &buffer, buffer.count)
    if count < 0, errno == EINTR { continue }
    if count <= 0 { break }
    for byte in buffer.prefix(count) {
        if byte == 10 {
            send(server.respond(to: oversized ? Data(repeating: 32, count: 65_537) : line))
            line.removeAll(keepingCapacity: true)
            oversized = false
        } else if !oversized {
            if line.count == 65_536 { oversized = true; line.removeAll(keepingCapacity: true) }
            else { line.append(byte) }
        }
    }
}
