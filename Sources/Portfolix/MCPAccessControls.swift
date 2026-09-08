import SwiftUI
import AppKit
import PortfolixCore

struct MCPAccessControls: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var confirmsAccess = false
    @State private var copied = false
    @State private var copyReset: Task<Void, Never>?
    private var executable: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/PortfolixMCP") }
    private var available: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    var body: some View {
        HStack(spacing: PortfolixSpacing.md) {
            Text(available ? text("本机 · 只读", "Local · Read only") : text("组件未打包", "Component not bundled"))
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(PortfolixTheme.secondaryText)
            Button {
                guard let config = try? MCPAccess.clientConfiguration(executableURL: executable) else { return }
                NSPasteboard.general.clearContents()
                copied = NSPasteboard.general.setString(config, forType: .string)
                copyReset?.cancel()
                copyReset = Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PortfolixTheme.lilac)
            .help(text("复制 MCP 连接配置", "Copy MCP connection configuration"))
            .accessibilityLabel(text("复制 MCP 连接配置", "Copy MCP connection configuration"))
            .disabled(!available || !store.mcpReadAccessEnabled)
            Toggle("MCP Server", isOn: Binding(
                get: { store.mcpReadAccessEnabled },
                set: { if $0 { confirmsAccess = true } else { store.setMCPReadAccessEnabled(false) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!available && !store.mcpReadAccessEnabled)
        }
        .alert(text("允许 MCP 读取资产数据？", "Allow MCP to read portfolio data?"), isPresented: $confirmsAccess) {
            Button(text("取消", "Cancel"), role: .cancel) {}
            Button(text("允许只读访问", "Allow Read Access")) { store.setMCPReadAccessEnabled(true) }
        } message: {
            Text(text(
                "您连接的本机 Agent 可读取持仓、成本和收益，并可能将这些信息发送给其模型服务。关闭 App 后授权仍有效，可随时在此关闭。",
                "Local agents you connect can read holdings, costs, and returns, and may send them to their model providers. Access remains enabled when Portfolix is closed. You can revoke it here at any time."
            ))
        }
        .onDisappear { copyReset?.cancel() }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}
