import AppKit
import SwiftUI

struct SidebarSplitLayout: Layout {
    var sidebarWidth: CGFloat

    var animatableData: CGFloat {
        get { sidebarWidth }
        set { sidebarWidth = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 1180, height: 760))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let width = min(max(sidebarWidth, 0), bounds.width)
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + width, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width - width, height: bounds.height))
    }
}

enum SidebarIconLayout {
    static let defaultCenterX: CGFloat = 38
    static let brandSize: CGFloat = 34
    static let navigationWidth: CGFloat = 24
    static let navigationIconSize: CGFloat = 16
    static let navigationTextSize: CGFloat = 15
    static let navigationRowHeight: CGFloat = 40
    static let expandedNavigationRowHeight: CGFloat = 44
    static let selectionHeight: CGFloat = 40
    static let edgeInset = PortfolixSpacing.sm
    static let minimumExpandedWidth: CGFloat = 218
    static let toggleSize = CGSize(width: 28, height: 24)

    static func headerHeight(isCollapsed: Bool) -> CGFloat {
        brandSize + (isCollapsed ? PortfolixSpacing.lg + toggleSize.height : 0)
    }

    static func toggleCenter(isCollapsed: Bool, expandedWidth: CGFloat, iconCenterX: CGFloat) -> CGPoint {
        CGPoint(
            x: isCollapsed ? iconCenterX : expandedWidth - edgeInset - toggleSize.width / 2,
            y: isCollapsed ? brandSize + PortfolixSpacing.lg + toggleSize.height / 2 : brandSize / 2
        )
    }

    static func navigationIconLeading(centerX: CGFloat) -> CGFloat {
        leadingInset(centerX: centerX, iconWidth: navigationWidth, outerInset: edgeInset)
    }

    static func collapsedWidth(centerX: CGFloat) -> CGFloat {
        let center = centerX.isFinite && centerX >= brandSize / 2 + PortfolixSpacing.sm
            ? centerX : defaultCenterX
        return center * 2
    }

    static func leadingInset(centerX: CGFloat, iconWidth: CGFloat, outerInset: CGFloat = 0) -> CGFloat {
        max(centerX - outerInset - iconWidth / 2, 0)
    }
}

struct SidebarView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isCollapsed: Bool
    @Binding var iconCenterX: CGFloat
    let expandedWidth: CGFloat

    var body: some View {
        ZStack {
            PortfolixSidebarBackground()

            VStack(alignment: .leading, spacing: PortfolixSpacing.lg) {
                Color.clear
                    .frame(height: SidebarIconLayout.headerHeight(isCollapsed: isCollapsed))
                    .overlay(alignment: .topLeading) {
                        SidebarBrandMark(isCollapsed: isCollapsed)
                            .fixedSize()
                            .offset(x: SidebarIconLayout.leadingInset(
                                centerX: iconCenterX, iconWidth: SidebarIconLayout.brandSize
                            ))
                    }
                    .overlay(alignment: .topLeading) {
                        collapseButton
                            .position(SidebarIconLayout.toggleCenter(
                                isCollapsed: isCollapsed, expandedWidth: expandedWidth, iconCenterX: iconCenterX
                            ))
                    }
                    .padding(.top, 16)

                VStack(spacing: PortfolixSpacing.xs) {
                    ForEach(SidebarSection.allCases) { item in
                        SidebarItem(
                            item: item,
                            title: item.title(language: store.appLanguage),
                            isSelected: store.selection == item,
                            iconCenterX: iconCenterX,
                            isCollapsed: isCollapsed
                        ) {
                            select(item)
                        }
                        .anchorPreference(key: PortfolixSelectionBoundsKey<SidebarSection>.self, value: .bounds) { [item: $0] }
                    }
                }
                .portfolixSelectionBackground(
                    selection: store.selection,
                    fill: PortfolixTheme.brandWash,
                    height: SidebarIconLayout.selectionHeight,
                    animates: false,
                    indicatorFill: PortfolixTheme.brandChart
                )
                .padding(.horizontal, SidebarIconLayout.edgeInset)

                Spacer()

                SidebarVersion(isCollapsed: isCollapsed)
                    .padding(.horizontal, isCollapsed ? PortfolixSpacing.sm : PortfolixSpacing.xl)
                    .padding(.bottom, PortfolixSpacing.lg)
            }
            .clipped()
        }
        .background {
            SidebarWindowAlignmentReader { iconCenterX = $0 }
        }
    }

    private var collapseButton: some View {
        SidebarCollapseButton(isCollapsed: isCollapsed, language: store.appLanguage) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                isCollapsed.toggle()
            }
        }
    }

    private func select(_ item: SidebarSection) {
        guard store.selection != item else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            store.selection = item
        }
    }
}

private struct SidebarWindowAlignmentReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> AlignmentView {
        let view = AlignmentView()
        view.onChange = onChange
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: AlignmentView, context: Context) {
        nsView.onChange = onChange
    }

    final class AlignmentView: NSView {
        var onChange: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Window controls are stationary; do not remeasure during page or sidebar layout changes.
            DispatchQueue.main.async { [weak self] in self?.updateAlignment() }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func updateAlignment() {
            guard let button = window?.standardWindowButton(.miniaturizeButton) else { return }
            guard let contentView = window?.contentView else { return }
            // Use window coordinates, not this view's animated layout coordinates.
            let centerX = button.convert(button.bounds, to: contentView).midX - contentView.bounds.minX
            guard centerX.isFinite, centerX >= SidebarIconLayout.brandSize / 2 else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { onChange?(centerX) }
        }
    }
}

struct SidebarCollapseButton: View {
    let isCollapsed: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .frame(width: SidebarIconLayout.toggleSize.width, height: SidebarIconLayout.toggleSize.height)
        }
        .buttonStyle(QuietButtonStyle(preservesLabelSize: true))
        .accessibilityLabel(title)
    }

    private var title: String {
        isCollapsed
            ? localizedText("展开侧边栏", "Expand Sidebar", language: language)
            : localizedText("收起侧边栏", "Collapse Sidebar", language: language)
    }
}

private struct SidebarVersion: View {
    @Environment(PortfolioStore.self) private var store
    @EnvironmentObject private var sparkleUpdater: PortfolixSparkleUpdater
    let isCollapsed: Bool

    private var version: String {
        PortfolixReleaseInfo.version
    }

    private var build: String {
        PortfolixReleaseInfo.build
    }

    var body: some View {
        Group {
            if isCollapsed {
                SidebarCollapsedVersionIndicator(
                    availableUpdate: sparkleUpdater.availableUpdate,
                    versionLabel: "Portfolix v\(version) (\(build))",
                    language: store.appLanguage
                ) {
                    sparkleUpdater.checkForUpdates()
                }
            } else {
                expandedContent
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24)
    }

    private var expandedContent: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            HStack(spacing: PortfolixSpacing.sm) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))

                Text("v\(version) (\(build))")
            }
            .lineLimit(1)

            Spacer(minLength: PortfolixSpacing.xs)

            if sparkleUpdater.availableUpdate != nil {
                Button {
                    sparkleUpdater.checkForUpdates()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(updateButtonTitle)
                    }
                        .font(PortfolixTypography.captionEmphasis)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(PortfolixTheme.brandWash)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(PortfolixTheme.brandWashText)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
            .font(PortfolixTypography.captionEmphasis.monospacedDigit())
            .monospacedDigit()
            .foregroundStyle(PortfolixTheme.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .padding(.top, PortfolixSpacing.sm)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(PortfolixTheme.border)
                    .frame(height: 1)
            }
    }

    private var updateButtonTitle: String {
        localizedText("更新", "Update", language: store.appLanguage)
    }
}

struct SidebarCollapsedVersionIndicator: View {
    let availableUpdate: PortfolixAvailableUpdate?
    let versionLabel: String
    let language: AppLanguage
    let onOpenUpdate: () -> Void

    static let symbolSize: CGFloat = 14
    static let controlSize = CGSize(width: 28, height: 24)

    var symbolName: String { availableUpdate == nil ? "info.circle" : "arrow.up.circle.fill" }
    var symbolColor: Color { availableUpdate == nil ? PortfolixTheme.secondary : PortfolixTheme.brandText }

    var helpText: String {
        guard let availableUpdate else { return versionLabel }
        return localizedText(
            "检测到新版本 \(availableUpdate.displayVersion)",
            "New version \(availableUpdate.displayVersion) available",
            language: language
        )
    }

    var body: some View {
        Group {
            if availableUpdate != nil {
                Button(action: openUpdateWindow) {
                    symbol
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localizedText("查看更新", "View Update", language: language))
            } else {
                symbol
                    .accessibilityLabel(versionLabel)
            }
        }
        .portfolixHelp(helpText, placement: .trailing)
    }

    private var symbol: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.monochrome)
            .resizable()
            .scaledToFit()
            .frame(width: Self.symbolSize, height: Self.symbolSize)
            .foregroundStyle(symbolColor)
            .frame(width: Self.controlSize.width, height: Self.controlSize.height)
            .contentShape(Rectangle())
    }

    func openUpdateWindow() {
        guard availableUpdate != nil else { return }
        onOpenUpdate()
    }
}

struct SidebarBrandMark: View {
    let isCollapsed: Bool

    var body: some View {
        HStack(spacing: PortfolixSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PortfolixTheme.brandLogoGradient)
                    .frame(width: SidebarIconLayout.brandSize, height: SidebarIconLayout.brandSize)

                PortfolixBrandGlyph(size: 24)
            }
            .frame(width: SidebarIconLayout.brandSize, height: SidebarIconLayout.brandSize)

            Text("Portfolix")
                .font(PortfolixTypography.sectionTitle)
                .foregroundStyle(PortfolixTheme.text)
                .fixedSize()
                .opacity(isCollapsed ? 0 : 1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Portfolix")
    }
}

struct SidebarItem: View {
    let item: SidebarSection
    let title: String
    let isSelected: Bool
    let iconCenterX: CGFloat
    let isCollapsed: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var rowHeight: CGFloat {
        isCollapsed ? SidebarIconLayout.navigationRowHeight : SidebarIconLayout.expandedNavigationRowHeight
    }

    var body: some View {
        Button(action: action) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .overlay(alignment: .leading) {
                    HStack(spacing: PortfolixSpacing.md) {
                        Image(systemName: item.symbol)
                            .font(.system(size: SidebarIconLayout.navigationIconSize, weight: .medium))
                            .frame(width: SidebarIconLayout.navigationWidth, height: SidebarIconLayout.navigationWidth)

                        Text(title)
                            .font(PortfolixTypography.sidebarLabel)
                            .fixedSize()
                            .opacity(isCollapsed ? 0 : 1)
                    }
                    .fixedSize()
                    .padding(.leading, SidebarIconLayout.navigationIconLeading(centerX: iconCenterX))
                }
            .foregroundStyle(navigationForegroundStyle)
            .background {
                if isHovered && !isSelected && !isCollapsed {
                    RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                        .fill(PortfolixTheme.soft)
                        .frame(height: SidebarIconLayout.selectionHeight)
                }
            }
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarNavigationButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .portfolixHelp(title, placement: .trailing, isEnabled: isCollapsed)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var navigationForegroundStyle: Color {
        if isSelected { return PortfolixTheme.brandWashText }
        return isHovered ? PortfolixTheme.text : PortfolixTheme.secondary
    }
}

private struct SidebarNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
