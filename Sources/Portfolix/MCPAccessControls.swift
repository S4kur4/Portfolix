import SwiftUI

struct MCPAccessControls: View {
    @Environment(PortfolioStore.self) private var store
    @State private var confirmsAccess = false

    var body: some View {
        Toggle(text("MCP 服务器", "MCP Server"), isOn: Binding(
            get: { store.mcpReadAccessEnabled },
            set: { if $0 { confirmsAccess = true } else { store.setMCPReadAccessEnabled(false) } }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .accessibilityLabel(text("MCP 服务器", "MCP Server"))
        .alert(text("允许 MCP 读取资产数据？", "Allow MCP to read portfolio data?"), isPresented: $confirmsAccess) {
            Button(text("取消", "Cancel"), role: .cancel) {}
            Button(text("允许只读访问", "Allow Read Access")) { store.setMCPReadAccessEnabled(true) }
        } message: {
            Text(text(
                "您连接的本机 Agent 可读取持仓、成本和收益，并可能将这些信息发送给其模型服务。关闭 App 后授权仍有效，可随时在此关闭。",
                "Local agents you connect can read holdings, costs, and returns, and may send them to their model providers. Access remains enabled when Portfolix is closed. You can revoke it here at any time."
            ))
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}
