import AppKit
import PortfolixCore
import SwiftUI

struct MCPAccessControls: View {
    @Environment(PortfolioStore.self) private var store
    @State private var confirmsAccess = false
    @State private var showsConnection = false

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Button(text("配置参考", "Configuration Reference")) { showsConnection = true }
                .buttonStyle(QuietButtonStyle())
            Toggle(
                text("MCP 服务器", "MCP Server"),
                isOn: Binding(
                    get: { store.mcpReadAccessEnabled },
                    set: { if $0 { confirmsAccess = true } else { store.setMCPReadAccessEnabled(false) } }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(text("MCP 服务器", "MCP Server"))
        }
        .sheet(isPresented: $showsConnection) { MCPConnectionSheet() }
        .alert(text("允许 MCP 读取资产数据？", "Allow MCP to read portfolio data?"), isPresented: $confirmsAccess) {
            Button(text("取消", "Cancel"), role: .cancel) {}
            Button(text("允许只读访问", "Allow Read Access")) { store.setMCPReadAccessEnabled(true) }
        } message: {
            Text(
                text(
                    "您连接的本机 Agent 可读取持仓、成本和收益，并可能将这些信息发送给其模型服务。关闭 App 后授权仍有效，可随时在此关闭。",
                    "Local agents you connect can read holdings, costs, and returns, and may send them to their model providers. Access remains enabled when Portfolix is closed. You can revoke it here at any time."
                ))
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}

struct MCPConnectionSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var client = MCPAccess.Client.codex
    @State private var copiedValue: String?
    @State private var referenceKind = MCPReferenceKind.configuration

    private let sheetWidth: CGFloat = 640
    private var codeWidth: CGFloat { sheetWidth - PortfolixSpacing.xl * 2 }

    private var executable: URL { MCPAccess.executableURL(appBundleURL: Bundle.main.bundleURL) }
    private var helperAvailable: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }
    private var command: String? { MCPAccess.connectionCommand(for: client, executableURL: executable) }
    private var configuration: String { (try? MCPAccess.configuration(for: client, executableURL: executable)) ?? "" }
    private var displayedCode: String { referenceKind == .command ? (command ?? configuration) : configuration }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: text("MCP 配置参考", "MCP Configuration Reference"), symbol: "point.3.connected.trianglepath.dotted")
            Divider().overlay(PortfolixTheme.border)
            VStack(alignment: .leading, spacing: PortfolixSpacing.xl) {
                HStack(spacing: PortfolixSpacing.md) {
                    Text(text("Agent 客户端", "Agent client"))
                        .font(PortfolixTypography.body.weight(.medium))
                        .foregroundStyle(PortfolixTheme.primaryText)
                    Spacer(minLength: 0)
                    clientMenu
                }

                VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                    Text(text("配置位置", "Configuration location"))
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondaryText)
                    Text(configurationTitle)
                        .font(PortfolixTypography.body)
                        .foregroundStyle(PortfolixTheme.primaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                codeBlock

                Text(
                    text(
                        "仅合并 Portfolix 的配置条目，勿覆盖已有服务器。更换 App 位置后需重新配置，连接后重启客户端。授权对当前 macOS 用户生效，不区分客户端；Agent 可能将数据发送至其模型服务。",
                        "Merge only the Portfolix configuration; keep existing servers. Reconfigure if the App moves, then restart the client. Access applies to this macOS user, not individual clients; agents may send data to their model providers."
                    )
                )
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                if !helperAvailable {
                    Text(text("MCP 组件缺失，请重新安装完整 App。", "MCP helper missing. Reinstall the complete App."))
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.danger)
                }
            }
            .padding(PortfolixSpacing.xl)
            Divider().overlay(PortfolixTheme.border)
            HStack {
                Button {
                    NSWorkspace.shared.open(client.documentationURL)
                } label: {
                    Label(text("官方文档", "Official documentation"), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(QuietButtonStyle())
                Spacer()
                Button(text("完成", "Done")) { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(PortfolixSpacing.xl)
        }
        .frame(width: sheetWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background { PortfolixSheetBackground() }
        .onExitCommand { dismiss() }
    }

    private var clientMenu: some View {
        PortfolixGlassMenuPicker(
            title: text("Agent 客户端", "Agent client"),
            selection: Binding(
                get: { client },
                set: { option in
                    referenceKind = .configuration
                    copiedValue = nil
                    client = option
                }
            ),
            options: MCPAccess.Client.allCases,
            optionTitle: { $0.title },
            height: PortfolixLayout.settingsControlHeight
        )
    }

    private var configurationTitle: String {
        switch client {
        case .codex: "~/.codex/config.toml"
        case .claudeCode: text("Claude Code 用户级 MCP 设置", "Claude Code user-scoped MCP settings")
        case .claudeDesktop: "~/Library/Application Support/Claude/claude_desktop_config.json"
        case .deepSeekHarness: text("所用配置层的 cordis.patch.yml", "cordis.patch.yml in your active configuration layer")
        case .workBuddy: text("WorkBuddy 自定义 MCP 的 mcp.json", "mcp.json in WorkBuddy custom MCP settings")
        }
    }

    private var codeBlock: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
            HStack {
                if command != nil {
                    PortfolixGlassSegmentedPicker(
                        title: text("参考内容", "Reference content"), selection: $referenceKind,
                        options: MCPReferenceKind.allCases,
                        optionTitle: { $0 == .configuration ? text("配置内容", "Configuration") : text("命令行", "Command") },
                        width: 208, height: PortfolixLayout.settingsControlHeight
                    )
                } else {
                    Text(text("配置内容", "Configuration"))
                        .font(PortfolixTypography.captionEmphasis)
                        .foregroundStyle(PortfolixTheme.secondaryText)
                }
                Spacer()
                Text(referenceKind == .command ? "Shell" : client.configurationFormat)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.secondaryText)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayedCode, forType: .string)
                    copiedValue = displayedCode
                } label: {
                    Image(systemName: copiedValue == displayedCode ? "checkmark" : "doc.on.doc")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel(text("复制", "Copy"))
                .disabled(!helperAvailable || displayedCode.isEmpty)
            }
            MCPReferenceCodeView(text: displayedCode)
                .id(client)
                .frame(width: codeWidth, height: MCPReferenceCodeLayout.viewportHeight(for: displayedCode, width: codeWidth))
                .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact))
                .clipShape(RoundedRectangle(cornerRadius: PortfolixRadius.compact))
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}

private enum MCPReferenceKind: CaseIterable {
    case configuration, command
}
