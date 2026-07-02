import AppKit
import SwiftUI

@main
struct PortfolixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PortfolioStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(systemLocalizedText("关于 Portfolix", "About Portfolix")) {
                    PortfolixReleaseInfo.showAboutPanel()
                }
            }
        }
    }
}

private func systemLocalizedText(_ chinese: String, _ english: String) -> String {
    let preferredLanguage = Locale.preferredLanguages.first ?? Locale.current.identifier
    return preferredLanguage.lowercased().hasPrefix("zh") ? chinese : english
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            self.activateMainWindow()
            try? await Task.sleep(for: .milliseconds(400))
            self.activateMainWindow()
        }
    }

    @MainActor
    private func activateMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.windows
            .filter { $0.canBecomeKey }
            .forEach { $0.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct RootView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var sidebarWidth: CGFloat = 198
    private let relativeTimeTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarWidth)
                .overlay(alignment: .trailing) {
                    SidebarResizeHandle(width: $sidebarWidth)
                }

            ZStack {
                detailBackground

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .padding(PortfolixSpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
        }
        .background(PortfolixTheme.canvas)
        .preferredColorScheme(store.appearanceMode.colorScheme)
        .tint(PortfolixTheme.violet)
        .sheet(item: $store.positionEditorPresentation) { presentation in
            PositionEditorSheet(presentation: presentation)
                .environmentObject(store)
        }
        .alert("运行提示", isPresented: persistenceErrorAlertPresented) {
            Button("好", role: .cancel) {
                store.persistenceErrorMessage = nil
            }
        } message: {
            Text(store.persistenceErrorMessage ?? "")
        }
        .onReceive(relativeTimeTimer) { now in
            store.updateRelativeTime(now: now)
        }
    }

    private var detailBackground: some View {
        ZStack {
            PortfolixTheme.canvas
                .ignoresSafeArea()

            AmbientGlow()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch store.selection {
        case .overview:
            DashboardView()
        case .positions:
            PositionsView()
        case .report:
            AIReportView()
        case .riskProfile:
            RiskProfileView()
        case .settings:
            SettingsView()
        }
    }

    private struct SidebarResizeHandle: View {
        @Binding var width: CGFloat
        @State private var dragStartWidth: CGFloat?
        @State private var isHovering = false
        @State private var isDragging = false

        private let hitWidth: CGFloat = 12
        private let minimumSidebarWidth: CGFloat = 178
        private let maximumSidebarWidth: CGFloat = 280

        var body: some View {
            Rectangle()
                .fill(Color.clear)
                .frame(width: hitWidth)
                .frame(maxHeight: .infinity)
                .background(ResizeCursorArea())
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(PortfolixTheme.border.opacity(isActive ? 1 : 0.72))
                        .frame(width: isActive ? 2 : 1)
                }
                .ignoresSafeArea(edges: .vertical)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            let start = dragStartWidth ?? width
                            dragStartWidth = start
                            isDragging = true
                            setWidth(start + value.translation.width)
                        }
                        .onEnded { _ in
                            dragStartWidth = nil
                            isDragging = false
                        }
                )
                .help("拖动调整侧边栏宽度")
        }

        private var isActive: Bool {
            isHovering || isDragging
        }

        private func setWidth(_ proposedWidth: CGFloat) {
            let clampedWidth = min(max(proposedWidth, minimumSidebarWidth), maximumSidebarWidth)
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                width = clampedWidth
            }
        }
    }

    private struct ResizeCursorArea: NSViewRepresentable {
        func makeNSView(context: Context) -> CursorView {
            CursorView()
        }

        func updateNSView(_ nsView: CursorView, context: Context) {}

        final class CursorView: NSView {
            override func resetCursorRects() {
                super.resetCursorRects()
                addCursorRect(bounds, cursor: .resizeLeftRight)
            }
        }
    }

    private var persistenceErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { store.persistenceErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.persistenceErrorMessage = nil
                }
            }
        )
    }
}
