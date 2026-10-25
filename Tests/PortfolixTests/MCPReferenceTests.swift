import AppKit
import PortfolixCore
import SwiftUI
import Testing

@testable import Portfolix

@Suite("MCP configuration reference")
@MainActor
struct MCPReferenceTests {
    private var longExecutable: URL {
        URL(fileURLWithPath: "/Applications/\(String(repeating: "Long 路径 QA ", count: 10))'quoted'.app/Contents/MacOS/PortfolixMCP")
    }

    @Test
    func clientsUseTheirDocumentedConfigurationFormats() throws {
        #expect(MCPAccess.Client.codex.title == "ChatGPT / Codex")
        let harness = try MCPAccess.configuration(for: .deepSeekHarness, executableURL: longExecutable)
        #expect(harness.hasPrefix("- insert:\n    - id: mcp-portfolix"))
        #expect(harness.contains("name: '@deepseek-ai/dsh-mcp-client'"))
        #expect(harness.contains("serverName: portfolix\n        transport: stdio"))
        let command = try #require(harness.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("command:") })
        let quoted = command.trimmingCharacters(in: .whitespaces).dropFirst("command: ".count)
        #expect(try JSONSerialization.jsonObject(with: Data(quoted.utf8), options: .fragmentsAllowed) as? String == longExecutable.path)
        let buddy = try MCPAccess.configuration(for: .workBuddy, executableURL: longExecutable)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(buddy.utf8)) as? [String: Any])
        let server = try #require((json["mcpServers"] as? [String: [String: Any]])?["portfolix"])
        #expect(server["type"] as? String == "stdio")
        #expect(server["command"] as? String == longExecutable.path)
        #expect(server["args"] == nil)
        #expect(!buddy.contains("\n\n"))
        #expect(server["env"] == nil)
        for client in MCPAccess.Client.allCases {
            #expect(client.documentationURL.scheme == "https")
        }
    }

    @Test
    func clientPickerUsesTheExistingGlassControlHeight() {
        for client in MCPAccess.Client.allCases {
            let picker = NSHostingView(
                rootView: PortfolixGlassMenuPicker(
                    title: "Agent client", selection: .constant(client), options: MCPAccess.Client.allCases,
                    optionTitle: { $0.title }, height: PortfolixLayout.settingsControlHeight
                ))
            #expect(picker.fittingSize.height == 30)
            #expect(picker.fittingSize.width < 248)
        }
    }

    @Test
    func longPathsWrapWithoutHorizontalOverflowOrChangingCopiedText() throws {
        for width: CGFloat in [344, 592] {
            for client in MCPAccess.Client.allCases {
                let text = try MCPAccess.configuration(for: client, executableURL: longExecutable)
                let height = MCPReferenceCodeLayout.viewportHeight(for: text, width: width)
                let view = MCPReferenceCodeScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
                view.setText(text)
                view.layoutSubtreeIfNeeded()
                let textView = view.codeTextView
                let manager = try #require(textView.layoutManager)
                let container = try #require(textView.textContainer)
                manager.ensureLayout(for: container)
                #expect(manager.usedRect(for: container).width <= width - MCPReferenceCodeLayout.inset * 2 + 1)
                #expect(textView.frame.width == width)
                #expect(!view.hasHorizontalScroller)
                #expect(!textView.isHorizontallyResizable)
                #expect(!textView.isEditable)
                #expect(textView.isSelectable)
                #expect(textView.string == text)
                #expect(height <= MCPReferenceCodeLayout.maximumHeight)
            }
        }
    }

    @Test
    func codeHeightTracksContentAndResetsAfterSwitching() {
        let width: CGFloat = 592
        let short = "args = []"
        let long = String(repeating: "command = '/Applications/Portfolix.app/Contents/MacOS/PortfolixMCP'\n", count: 100)
        let shortHeight = MCPReferenceCodeLayout.viewportHeight(for: short, width: width)
        #expect(shortHeight < 60)
        #expect(MCPReferenceCodeLayout.viewportHeight(for: long, width: width) == MCPReferenceCodeLayout.maximumHeight)
        let view = MCPReferenceCodeScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.setText(long)
        view.layoutSubtreeIfNeeded()
        view.contentView.scroll(to: NSPoint(x: 0, y: 200))
        view.setText(short)
        view.layoutSubtreeIfNeeded()
        #expect(view.codeTextView.string == short)
        #expect(view.contentView.bounds.origin == .zero)
        #expect(view.codeTextView.frame.height == view.contentSize.height)
    }
}
