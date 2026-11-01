import AppKit
import SwiftUI
import Testing
@testable import Portfolix

private final class TooltipTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

private struct SidebarLayoutProbe: NSViewRepresentable {
    let capture: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        capture(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@Suite("Text color hierarchy")
@MainActor
struct ThemeTests {
    @Test(arguments: [CGFloat(29), 38, 39])
    func sidebarIconsShareTheWindowButtonCenter(centerX: CGFloat) {
        let brandInset = SidebarIconLayout.leadingInset(
            centerX: centerX, iconWidth: SidebarIconLayout.brandSize
        )
        let navigationInset = SidebarIconLayout.leadingInset(
            centerX: centerX, iconWidth: SidebarIconLayout.navigationWidth,
            outerInset: PortfolixSpacing.sm
        )
        #expect(brandInset + SidebarIconLayout.brandSize / 2 == centerX)
        #expect(PortfolixSpacing.sm + navigationInset + SidebarIconLayout.navigationWidth / 2 == centerX)
        #expect(SidebarIconLayout.brandSize == 34)
        #expect(SidebarIconLayout.navigationWidth == 24)
        #expect(SidebarIconLayout.collapsedWidth(centerX: centerX) / 2 == centerX)
    }

    @Test(arguments: [AppLanguage.chinese, .english])
    func sidebarCollapseControlKeepsItsSizeAndExpandedLabelsFit(language: AppLanguage) {
        for collapsed in [true, false] {
            let button = NSHostingView(rootView: SidebarCollapseButton(
                isCollapsed: collapsed, language: language, action: {}
            ))
            #expect(button.fittingSize == SidebarIconLayout.toggleSize)
        }
        let iconLeading = SidebarIconLayout.leadingInset(
            centerX: 39, iconWidth: SidebarIconLayout.navigationWidth, outerInset: PortfolixSpacing.sm
        )
        let available = SidebarIconLayout.minimumExpandedWidth - PortfolixSpacing.sm * 2
            - iconLeading - SidebarIconLayout.navigationWidth - PortfolixSpacing.md * 2
        let font = NSFont.systemFont(ofSize: SidebarIconLayout.navigationTextSize, weight: .medium)
        for section in SidebarSection.allCases {
            let width = (section.title(language: language) as NSString).size(withAttributes: [.font: font]).width
            #expect(width <= available)
        }
        #expect(SidebarIconLayout.navigationIconSize == 16)
        #expect(SidebarIconLayout.navigationTextSize == 15)
        #expect(SidebarIconLayout.collapsedWidth(centerX: .nan).isFinite)
    }

    @Test
    func sidebarBrandKeepsItsIconSizeWhenTextIsHidden() {
        let host = NSHostingView(rootView: SidebarBrandMark(isCollapsed: false).fixedSize())
        let expandedSize = host.fittingSize
        for collapsed in [false, true, false, true] {
            host.rootView = SidebarBrandMark(isCollapsed: collapsed).fixedSize()
            let size = host.fittingSize
            #expect(size.height == SidebarIconLayout.brandSize)
            #expect(size == expandedSize)
        }
    }

    @Test(arguments: [CGFloat(29), 38, 39])
    func sidebarHeaderFitsTheBrandAndCollapseButtonInOneRow(centerX: CGFloat) {
        let brandSize = NSHostingView(rootView: SidebarBrandMark(isCollapsed: false).fixedSize()).fittingSize
        let leadingInset = SidebarIconLayout.leadingInset(
            centerX: centerX, iconWidth: SidebarIconLayout.brandSize
        )
        let requiredWidth = leadingInset + brandSize.width + PortfolixSpacing.sm * 2
            + SidebarIconLayout.toggleSize.width + SidebarIconLayout.edgeInset
        #expect(requiredWidth <= SidebarIconLayout.minimumExpandedWidth)
        #expect(brandSize.height >= SidebarIconLayout.toggleSize.height)
    }

    @Test(arguments: [AppLanguage.chinese, .english])
    func collapsedNavigationKeepsTheSameBoundsAcrossSelections(language: AppLanguage) {
        let width = SidebarIconLayout.collapsedWidth(centerX: 39) - SidebarIconLayout.edgeInset * 2
        for selected in [true, false] {
            for item in SidebarSection.allCases {
                let host = NSHostingView(rootView: SidebarItem(
                    item: item, title: item.title(language: language), isSelected: selected,
                    iconCenterX: 39, isCollapsed: true, action: {}
                ).frame(width: width))
                #expect(host.fittingSize == CGSize(width: width, height: 40))
            }
        }
        #expect(SidebarIconLayout.edgeInset == PortfolixSpacing.sm)
    }

    @Test(arguments: [CGFloat(78), 112, 160, 218, 280])
    func sidebarStaysPinnedWhenTheDetailPageHasADifferentMinimumWidth(sidebarWidth: CGFloat) throws {
        for detailMinimumWidth in [CGFloat(0), 600, 1800] {
            var sidebarProbe: NSView?
            var detailProbe: NSView?
            let host = NSHostingView(rootView:
                SidebarSplitLayout(sidebarWidth: sidebarWidth) {
                    SidebarLayoutProbe { sidebarProbe = $0 }
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    Color.clear
                        .frame(minWidth: detailMinimumWidth)
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .clipped()
                        .background(SidebarLayoutProbe { detailProbe = $0 })
                }
            )
            host.frame = CGRect(x: 0, y: 0, width: 1180, height: 760)
            host.layoutSubtreeIfNeeded()
            let sidebar = try #require(sidebarProbe)
            let detail = try #require(detailProbe)
            let sidebarFrame = sidebar.convert(sidebar.bounds, to: host)
            let detailFrame = detail.convert(detail.bounds, to: host)
            #expect(abs(sidebarFrame.minX) < 0.001)
            #expect(abs(sidebarFrame.width - sidebarWidth) < 0.001)
            #expect(abs(detailFrame.minX - sidebarWidth) < 0.001)
            #expect(abs(detailFrame.width - (1180 - sidebarWidth)) < 0.001)
        }
    }

    @Test
    func sidebarIconColumnDoesNotChangeBetweenCollapsedAndExpandedLayout() {
        let centerX: CGFloat = 39
        let iconCenter = SidebarIconLayout.edgeInset
            + SidebarIconLayout.navigationIconLeading(centerX: centerX) + SidebarIconLayout.navigationWidth / 2
        #expect(iconCenter == centerX)
        #expect(iconCenter == SidebarIconLayout.collapsedWidth(centerX: centerX) / 2)
        #expect(SidebarIconLayout.headerHeight(isCollapsed: false) == SidebarIconLayout.brandSize)
        #expect(SidebarIconLayout.headerHeight(isCollapsed: true) == 74)
    }

    @Test(arguments: [CGFloat(218), 280, 308])
    func sidebarToggleFitsThroughoutTheSameCollapseAnimation(expandedWidth: CGFloat) {
        let collapsedWidth = SidebarIconLayout.collapsedWidth(centerX: 39)
        let start = SidebarIconLayout.toggleCenter(isCollapsed: false, expandedWidth: expandedWidth, iconCenterX: 39)
        let end = SidebarIconLayout.toggleCenter(isCollapsed: true, expandedWidth: expandedWidth, iconCenterX: 39)
        for step in 0...20 {
            let progress = CGFloat(step) / 20
            let width = expandedWidth + (collapsedWidth - expandedWidth) * progress
            let height = SidebarIconLayout.headerHeight(isCollapsed: false)
                + (SidebarIconLayout.headerHeight(isCollapsed: true) - SidebarIconLayout.headerHeight(isCollapsed: false)) * progress
            let point = CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
            #expect(point.x + SidebarIconLayout.toggleSize.width / 2 <= width - SidebarIconLayout.edgeInset)
            #expect(point.y + SidebarIconLayout.toggleSize.height / 2 <= height)
            #expect(point.x - SidebarIconLayout.toggleSize.width / 2 >= 0)
        }
    }

    @Test
    func hoverHelpIsCompactAndDoesNotAffectControlBounds() {
        let short = NSHostingView(rootView: HelpTooltipBubble(text: "持仓明细")).fittingSize
        let long = NSHostingView(rootView: HelpTooltipBubble(text: String(repeating: "投资分布功能由AI分析计算，仅供参考。", count: 5))).fittingSize
        #expect(short.width < long.width)
        #expect(long.width <= 260)
        #expect(long.height > short.height)
        let host = NSHostingView(rootView: Text("Test").frame(width: 28, height: 24).portfolixHelp("提示"))
        #expect(host.fittingSize == CGSize(width: 28, height: 24))
        let anchor = HoverHelpView(frame: CGRect(x: 0, y: 0, width: 30, height: 24))
        #expect(anchor.hitTest(CGPoint(x: 10, y: 10)) == nil)
        anchor.dismissTooltip()
    }

    @Test
    func hoverHelpStaysOnScreenNearEveryEdge() {
        let screen = CGRect(x: -1200, y: 100, width: 1200, height: 800)
        for x in [screen.minX, screen.midX, screen.maxX - 24] {
            for y in [screen.minY, screen.midY, screen.maxY - 24] {
                for placement in [HelpTooltipPlacement.top, .trailing] {
                    let frame = HoverHelpLayout.frame(
                        size: CGSize(width: 260, height: 60),
                        anchor: CGRect(x: x, y: y, width: 24, height: 24),
                        screen: screen, placement: placement
                    )
                    #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))
                }
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTFOLIX_RUN_WINDOW_TESTS"] == "1"))
    func hoverHelpWindowNeverTakesKeyboardFocusAndIsRemovedOnDismiss() throws {
        let window = TooltipTestWindow(
            contentRect: CGRect(x: 200, y: 200, width: 120, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let anchor = HoverHelpView(frame: CGRect(x: 10, y: 10, width: 50, height: 30))
        window.contentView?.addSubview(anchor)
        anchor.text = "持仓明细"
        defer {
            anchor.dismissTooltip()
            window.close()
        }
        window.orderFront(nil)
        #expect(anchor.window === window)
        #expect(!anchor.isHiddenOrHasHiddenAncestor)
        #expect(!anchor.visibleRect.isEmpty)
        #expect(window.screen != nil)
        anchor.showTooltip()
        let tooltip = try #require(window.childWindows?.first)
        #expect(!tooltip.canBecomeKey)
        #expect(!tooltip.canBecomeMain)
        #expect(tooltip.ignoresMouseEvents)
        anchor.isHelpEnabled = false
        #expect(window.childWindows?.isEmpty ?? true)
        anchor.showTooltip()
        #expect(window.childWindows?.isEmpty ?? true)
        anchor.isHelpEnabled = true
        anchor.showTooltip()
        #expect(window.childWindows?.count == 1)
        anchor.removeFromSuperview()
        #expect(window.childWindows?.isEmpty ?? true)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func tonalStatusTextHasSufficientContrast(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        appearance.performAsCurrentDrawingAppearance {
            let panel = NSColor(PortfolixTheme.panel).usingColorSpace(.sRGB)!
            let pairs: [(Color, Color, CGFloat)] = [
                (PortfolixTheme.performanceStatusText(for: 1), PortfolixTheme.mint, 0.13),
                (PortfolixTheme.performanceStatusText(for: -1), PortfolixTheme.danger, 0.13),
                (PortfolixTheme.positiveStatusText, PortfolixTheme.mint, 0.12),
                (PortfolixTheme.warningStatusText, PortfolixTheme.amber, 0.12),
            ]
            for (text, fill, opacity) in pairs {
                let background = blend(NSColor(fill).usingColorSpace(.sRGB)!, over: panel, alpha: opacity)
                #expect(contrast(NSColor(text).usingColorSpace(.sRGB)!, background) >= 4.5)
            }
            #expect(NSColor(PortfolixTheme.performanceStatusText(for: 0)).usingColorSpace(.sRGB)
                == NSColor(PortfolixTheme.secondaryText).usingColorSpace(.sRGB))
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func performanceColorPreferenceOnlySwapsGainAndLossColors(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        appearance.performAsCurrentDrawingAppearance {
            func resolved(_ color: Color) -> NSColor? { NSColor(color).usingColorSpace(.sRGB) }
            for scheme in PerformanceColorScheme.allCases {
                let gain = scheme == .greenUpRedDown ? PortfolixTheme.mint : PortfolixTheme.danger
                let loss = scheme == .greenUpRedDown ? PortfolixTheme.danger : PortfolixTheme.mint
                let gainText = scheme == .greenUpRedDown ? PortfolixTheme.positiveStatusText : PortfolixTheme.negativeStatusText
                let lossText = scheme == .greenUpRedDown ? PortfolixTheme.negativeStatusText : PortfolixTheme.positiveStatusText
                #expect(resolved(PortfolixTheme.performanceColor(for: Decimal(1), scheme: scheme)) == resolved(gain))
                #expect(resolved(PortfolixTheme.performanceColor(for: Double(1), scheme: scheme)) == resolved(gain))
                #expect(resolved(PortfolixTheme.performanceColor(for: Decimal(-1), scheme: scheme)) == resolved(loss))
                #expect(resolved(PortfolixTheme.performanceColor(for: Double(-1), scheme: scheme)) == resolved(loss))
                #expect(resolved(PortfolixTheme.performanceStatusText(for: 1, scheme: scheme)) == resolved(gainText))
                #expect(resolved(PortfolixTheme.performanceStatusText(for: -1, scheme: scheme)) == resolved(lossText))
                #expect(resolved(PortfolixTheme.performanceColor(for: Decimal(0), scheme: scheme)) == resolved(PortfolixTheme.secondaryText))
                #expect(resolved(PortfolixTheme.performanceColor(for: Double(0), scheme: scheme)) == resolved(PortfolixTheme.secondaryText))
                #expect(resolved(PortfolixTheme.dailyProfitTileFill(for: 1, scheme: scheme)) == resolved(gain.opacity(0.13)))
                #expect(resolved(PortfolixTheme.dailyProfitTileFill(for: -1, scheme: scheme)) == resolved(loss.opacity(0.13)))
                #expect(resolved(PortfolixTheme.dailyProfitTileFill(for: nil, scheme: scheme)) == resolved(.clear))
            }
        }
    }

    @Test(arguments: [AppLanguage.chinese, .english])
    func performanceColorSelectorKeepsItsHeightAndColoredArrowLabels(language: AppLanguage) throws {
        for scheme in PerformanceColorScheme.allCases {
            let title = scheme.selectorTitle(language: language)
            let upRange = try #require(title.range(of: "↑"))
            let downRange = try #require(title.range(of: "↓"))
            #expect(title[upRange].foregroundColor == PortfolixTheme.performanceColor(for: Decimal(1), scheme: scheme))
            #expect(title[downRange].foregroundColor == PortfolixTheme.performanceColor(for: Decimal(-1), scheme: scheme))
            let width: CGFloat = language == .english ? 340 : 240
            let labelWidth = (String(title.characters) as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            ]).width
            #expect(labelWidth + PortfolixSpacing.md * 2 <= (width - PortfolixLayout.controlSelectionInset * 2) / 2)
            let host = NSHostingView(rootView: PortfolixGlassSegmentedPicker(
                title: "Colors", selection: .constant(scheme), options: PerformanceColorScheme.allCases,
                optionTitle: { $0.title(language: language) },
                optionAttributedTitle: { $0.selectorTitle(language: language) },
                width: width, height: PortfolixLayout.settingsControlHeight
            ))
            #expect(host.fittingSize == CGSize(width: width, height: 30))
        }
    }

    @Test
    func dashboardRowsAndAccentStrokesUseSharedDimensions() {
        #expect(PortfolixLayout.dashboardHeroContentHeight == PortfolixLayout.dashboardTrendContentHeight)
        #expect(PortfolixLayout.dashboardRowContentHeight == 252)
        #expect(PortfolixLayout.accentLineWidth == 2)
    }

    @Test
    func numericTransitionsRespectFixedControlBounds() {
        for value in ["¥1,602,824.55", "-¥93.20", "0.00%", "21.8%"] {
            let host = NSHostingView(rootView: Text(value)
                .frame(width: 180, height: 24)
                .portfolixNumericTransition(value))
            #expect(host.fittingSize == CGSize(width: 180, height: 24))
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func userMessageTextHasContrastThroughoutItsGradient(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        appearance.performAsCurrentDrawingAppearance {
            let text = NSColor(PortfolixTheme.userMessageText).usingColorSpace(.sRGB)!
            let stops = PortfolixTheme.userMessageGradientColors.map { NSColor($0).usingColorSpace(.sRGB)! }
            #expect(stops.count == 2)
            for step in 0...100 {
                let background = blend(stops[1], over: stops[0], alpha: CGFloat(step) / 100)
                #expect(contrast(text, background) >= 4.5)
            }
        }
    }

    @Test
    func darkStatusAndChatColorsRemainUnchanged() throws {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        appearance.performAsCurrentDrawingAppearance {
            let pairs: [(Color, Color)] = [
                (PortfolixTheme.positiveStatusText, PortfolixTheme.mint),
                (PortfolixTheme.negativeStatusText, PortfolixTheme.danger),
                (PortfolixTheme.warningStatusText, PortfolixTheme.amber),
                (PortfolixTheme.userMessageText, Color(hex: 0x120F20)),
                (PortfolixTheme.userMessageGradientColors[0], Color(hex: 0xC3B1FF)),
                (PortfolixTheme.userMessageGradientColors[1], Color(hex: 0x8068EF)),
            ]
            for (actual, expected) in pairs {
                let actual = NSColor(actual).usingColorSpace(.sRGB)!
                let expected = NSColor(expected).usingColorSpace(.sRGB)!
                #expect(abs(actual.redComponent - expected.redComponent) < 0.00001)
                #expect(abs(actual.greenComponent - expected.greenComponent) < 0.00001)
                #expect(abs(actual.blueComponent - expected.blueComponent) < 0.00001)
                #expect(abs(actual.alphaComponent - expected.alphaComponent) < 0.00001)
            }
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func nativeControlsShareTheExistingAccent(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        appearance.performAsCurrentDrawingAppearance {
            #expect(NSColor(PortfolixTheme.controlAccent).usingColorSpace(.sRGB)
                == NSColor(PortfolixTheme.violet).usingColorSpace(.sRGB))
        }
    }

    private func blend(_ foreground: NSColor, over background: NSColor, alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: foreground.redComponent * alpha + background.redComponent * (1 - alpha),
            green: foreground.greenComponent * alpha + background.greenComponent * (1 - alpha),
            blue: foreground.blueComponent * alpha + background.blueComponent * (1 - alpha),
            alpha: 1
        )
    }

    private func contrast(_ first: NSColor, _ second: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            func linear(_ component: CGFloat) -> CGFloat {
                component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.redComponent)
                + 0.7152 * linear(color.greenComponent)
                + 0.0722 * linear(color.blueComponent)
        }
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    @Test(arguments: [AssetCategory.cnStock, .cash])
    func sourceCellRendersWithoutInheritedStoreEnvironment(category: AssetCategory) throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortfolixSourceCellTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("portfolio.sqlite3")
        let repository = try PositionRepository(databaseURL: databaseURL)
        let position = Position(
            name: "Test Asset", symbol: "TEST", category: category, quoteCurrency: .cny,
            quantity: 10, averageCost: 10, latestPrice: 10, marketValueCNY: 100,
            profitRate: 0, weeklyTrend: [10, 10], source: "手工价格", quoteTime: "刚刚", freshness: .manual
        )
        try repository.insert(position)
        let store = PortfolioStore(positionRepository: repository)

        // Deliberately omit .environment(store), as happens when native table cells recycle.
        let host = NSHostingView(rootView: PositionSourceCell(position: position, store: store)
            .frame(width: 200, height: 44))
        for index in 0..<20 {
            store.selectedPositionID = index.isMultiple(of: 2) ? position.id : nil
            host.rootView = PositionSourceCell(position: position, store: store)
                .frame(width: 200, height: 44)
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize == NSSize(width: 200, height: 44))
        }
    }

    @Test
    func chatComposerUsesEqualInsetsOnEverySide() {
        #expect(PortfolixLayout.chatComposerTopInset == PortfolixSpacing.lg)
        #expect(PortfolixLayout.chatComposerBottomInset == PortfolixSpacing.lg)
        #expect(PortfolixLayout.chatComposerHorizontalInset == PortfolixSpacing.lg)
        #expect(AIReportComposerMetrics.controlSpacing == PortfolixLayout.chatComposerHorizontalInset)
    }

    @Test(arguments: [5, 6])
    func profitCalendarRowsFillAvailableHeightWithoutExtraBottomSpace(rows: Int) {
        for height: CGFloat in [196, 212, 248] {
            let cellHeight = DailyProfitCalendarLayout.cellHeight(in: height, rows: rows)
            let usedHeight = DailyProfitCalendarLayout.weekdayHeight
                + PortfolixLayout.dataTileSpacing * CGFloat(rows) + cellHeight * CGFloat(rows)
            #expect(abs(usedHeight - height) < 0.000001)
            #expect(cellHeight >= 26)
        }
        #expect(DailyProfitCalendarLayout.cellHeight(in: 0, rows: rows) == 0)
        #expect(DailyProfitCalendarLayout.cellHeight(in: .infinity, rows: rows) == 0)
        #expect(DailyProfitCalendarLayout.cellHeight(in: 212, rows: 0) == 0)
        #expect(PortfolixLayout.cardPadding == 16)
        #expect(PortfolixLayout.dataTileSpacing == 4)
    }

    @Test
    func sidebarMaterialKeepsItsFixedSize() {
        let sidebar = PortfolixSidebarBackground().frame(width: 218, height: 760)
        let glass = NSHostingView(rootView: sidebar).fittingSize
        #expect(glass == NSSize(width: 218, height: 760))
    }

    @Test(arguments: [AppLanguage.chinese, .english])
    func collapsedVersionIndicatorKeepsItsSizeAndOnlyOpensAvailableUpdates(language: AppLanguage) {
        var updateWindowRequests = 0
        let versionLabel = "Portfolix v1.0 (1)"
        for update in [nil, PortfolixAvailableUpdate(displayVersion: "1.1", buildVersion: "2")] {
            let indicator = SidebarCollapsedVersionIndicator(
                availableUpdate: update, versionLabel: versionLabel, language: language
            ) { updateWindowRequests += 1 }
            let host = NSHostingView(rootView: indicator)
            #expect(host.fittingSize == SidebarCollapsedVersionIndicator.controlSize)
            if update == nil {
                #expect(indicator.symbolName == "info.circle")
                #expect(indicator.symbolColor == PortfolixTheme.secondaryText)
                #expect(indicator.helpText == versionLabel)
                indicator.openUpdateWindow()
                #expect(updateWindowRequests == 0)
            } else {
                #expect(indicator.symbolName == "arrow.up.circle.fill")
                #expect(indicator.symbolColor == PortfolixTheme.violet)
                #expect(indicator.helpText == (language == .chinese ? "检测到新版本 1.1" : "New version 1.1 available"))
                indicator.openUpdateWindow()
                #expect(updateWindowRequests == 1)
            }
        }
        #expect(SidebarCollapsedVersionIndicator.symbolSize == 14)
    }

    @Test
    func darkCardsHaveNeutralSeparationFromTheCanvas() throws {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        var panel: NSColor?
        var canvas: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            panel = NSColor(PortfolixTheme.panel).usingColorSpace(.sRGB)
            canvas = NSColor(PortfolixTheme.canvas).usingColorSpace(.sRGB)
        }
        let surface = try #require(panel)
        let background = try #require(canvas)
        #expect(surface.redComponent > background.redComponent + 0.025)
        #expect(abs(surface.blueComponent - surface.redComponent) < 0.000001)
        #expect(surface == NSColor(hex: 0x080808).usingColorSpace(.sRGB))
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func largeSurfacesUseOpaqueNeutralGrays(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        let colors = [PortfolixTheme.canvas, PortfolixTheme.sidebar, PortfolixTheme.panel,
                      PortfolixTheme.panelElevated, PortfolixTheme.panelSoft]
        appearance.performAsCurrentDrawingAppearance {
            for surface in colors {
                let color = NSColor(surface).usingColorSpace(.sRGB)!
                #expect(abs(color.redComponent - color.greenComponent) < 0.000001)
                #expect(abs(color.redComponent - color.blueComponent) < 0.000001)
                #expect(color.alphaComponent == 1)
            }
            let canvas = NSColor(PortfolixTheme.canvas).usingColorSpace(.sRGB)!
            let panel = NSColor(PortfolixTheme.panel).usingColorSpace(.sRGB)!
            let dark = appearanceName == .darkAqua
            #expect(canvas == NSColor(hex: dark ? 0x000000 : 0xE8E8E8).usingColorSpace(.sRGB))
            #expect(panel == NSColor(hex: dark ? 0x080808 : 0xF3F3F3).usingColorSpace(.sRGB))
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func neutralSurfacesDoNotChangeBrandPurples(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        let pairs: [(Color, UInt, UInt)] = [
            (PortfolixTheme.lilac, 0x654BC8, 0xB7A5FF),
            (PortfolixTheme.violet, 0x7253DB, 0x8C75FF),
            (PortfolixTheme.controlAccent, 0x7253DB, 0x8C75FF),
            (PortfolixTheme.primaryButtonTint, 0xAF9AFF, 0xB7A5FF),
            (PortfolixTheme.controlSelectionFill, 0xDCD7E7, 0x3F3B4B),
            (PortfolixTheme.selectionFill, 0xE2DDF1, 0x18151F),
            (PortfolixTheme.selectionText, 0x513AB6, 0xC5BAF8),
        ]
        appearance.performAsCurrentDrawingAppearance {
            for (color, light, dark) in pairs {
                #expect(NSColor(color).usingColorSpace(.sRGB)
                    == NSColor(hex: appearanceName == .darkAqua ? dark : light).usingColorSpace(.sRGB))
            }
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func tableTextFollowsNativeSelectionProminence(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        var environment = EnvironmentValues()
        let styles = [
            PositionTableForeground(color: PortfolixTheme.primaryText),
            PositionTableForeground(color: PortfolixTheme.secondaryText, selectedOpacity: 0.74),
            PositionTableForeground(color: PortfolixTheme.performanceColor(for: Decimal(-1))),
            PositionTableForeground(color: PortfolixTheme.performanceColor(for: Decimal(0))),
            PositionTableForeground(color: PortfolixTheme.performanceColor(for: Decimal(1))),
        ]
        appearance.performAsCurrentDrawingAppearance {
            for style in styles {
                environment.backgroundProminence = .standard
                let normal = NSColor(style.resolve(in: environment)).usingColorSpace(.sRGB)
                #expect(normal == NSColor(style.color).usingColorSpace(.sRGB))
                environment.backgroundProminence = .increased
                #expect(NSColor(style.resolve(in: environment)).usingColorSpace(.sRGB)
                    == NSColor(Color.white.opacity(style.selectedOpacity)).usingColorSpace(.sRGB))
                environment.backgroundProminence = .standard
                #expect(NSColor(style.resolve(in: environment)).usingColorSpace(.sRGB) == normal)
            }
        }
    }

    @Test
    func glassActionButtonsPreserveTheirLayoutWhenDisabled() {
        let primary = Button("添加持仓") {}.buttonStyle(PrimaryButtonStyle())
        let quiet = Button("取消") {}.buttonStyle(QuietButtonStyle())
        #expect(NSHostingView(rootView: primary).fittingSize == NSHostingView(rootView: primary.disabled(true)).fittingSize)
        #expect(NSHostingView(rootView: quiet).fittingSize == NSHostingView(rootView: quiet.disabled(true)).fittingSize)

        let icon = Button {} label: {
            Image(systemName: "paperplane.fill").frame(width: 32, height: 32)
        }
        .buttonStyle(PrimaryButtonStyle(preservesLabelSize: true))
        #expect(NSHostingView(rootView: icon).fittingSize == NSSize(width: 32, height: 32))
    }

    @Test
    func sharedButtonsKeepTheirLayoutWithSheetControlDefaults() {
        let primary = Button("保存修改") {}.buttonStyle(PrimaryButtonStyle())
        let quiet = Button("取消") {}.buttonStyle(QuietButtonStyle())
        #expect(NSHostingView(rootView: primary).fittingSize == NSHostingView(rootView: primary
            .controlSize(.large).keyboardShortcut(.defaultAction)).fittingSize)
        #expect(NSHostingView(rootView: quiet).fittingSize == NSHostingView(rootView: quiet
            .controlSize(.large).keyboardShortcut(.cancelAction)).fittingSize)
    }

    @Test
    func nativeGlassBackgroundDoesNotInterceptButtonClicks() {
        if #available(macOS 26.0, *) {
            let view = ButtonGlassView(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
            #expect(view.hitTest(NSPoint(x: 50, y: 16)) == nil)
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func sidebarUsesTheSameBaseColorAsCards(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        var tint: NSColor?
        var panel: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            tint = NSColor(PortfolixTheme.sidebar).usingColorSpace(.sRGB)
            panel = NSColor(PortfolixTheme.panel).usingColorSpace(.sRGB)
        }
        let color = try #require(tint)
        let background = try #require(panel)
        #expect(color == background)
    }

    @Test
    func lightPrimaryButtonsUseTheSameTextColorAsGlassSelectors() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        appearance.performAsCurrentDrawingAppearance {
            #expect(NSColor(PortfolixTheme.primaryButtonText).usingColorSpace(.sRGB)
                == NSColor(PortfolixTheme.glassControlText).usingColorSpace(.sRGB))
        }
    }

    @Test
    func darkPurpleButtonsKeepTheirOriginalTintAndText() throws {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        appearance.performAsCurrentDrawingAppearance {
            #expect(NSColor(PortfolixTheme.primaryButtonTint).usingColorSpace(.sRGB)
                == NSColor(hex: 0xB7A5FF).usingColorSpace(.sRGB))
            #expect(NSColor(PortfolixTheme.primaryButtonText).usingColorSpace(.sRGB)
                == NSColor(hex: 0x120F20).usingColorSpace(.sRGB))
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func purpleButtonTextHasSufficientContrast(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        var contrast: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            func luminance(_ color: Color) -> CGFloat {
                let color = NSColor(color).usingColorSpace(.sRGB)!
                func linear(_ component: CGFloat) -> CGFloat {
                    component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
                }
                return 0.2126 * linear(color.redComponent)
                    + 0.7152 * linear(color.greenComponent)
                    + 0.0722 * linear(color.blueComponent)
            }
            let foreground = luminance(PortfolixTheme.primaryButtonText)
            let background = luminance(PortfolixTheme.primaryButtonTint)
            contrast = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
        }
        #expect(contrast >= 4.5)
    }

    @Test(arguments: [CGFloat(24), CGFloat(30)])
    func glassControlsRespectTheirContextHeight(height: CGFloat) {
        let segmented = NSHostingView(rootView: PortfolixGlassSegmentedPicker(
            title: "Currency",
            selection: .constant(DisplayCurrency.cny),
            options: DisplayCurrency.allCases,
            optionTitle: { $0.rawValue },
            width: 240,
            height: height
        ))
        let menu = NSHostingView(rootView: PortfolixGlassMenuPicker(
            title: "Model",
            selection: .constant("deepseek-flash"),
            options: ["deepseek-flash"],
            optionTitle: { $0 },
            height: height
        ))
        #expect(segmented.fittingSize.height == height)
        #expect(segmented.fittingSize.width == 240)
        #expect(menu.fittingSize.height == height)
        #expect(PortfolixLayout.positionsToolbarControlHeight == 30)
        #expect(PortfolixLayout.settingsControlHeight == 30)
    }

    @Test
    func menuAndDisabledControlsKeepTheSharedHeight() {
        let picker = PortfolixGlassMenuPicker(
            title: "Model",
            selection: .constant("deepseek-v4-pro"),
            options: ["deepseek-v4-pro", "deepseek-flash"],
            optionTitle: { $0 }
        )
        let enabled = NSHostingView(rootView: picker).fittingSize
        let disabled = NSHostingView(rootView: picker.disabled(true)).fittingSize

        #expect(enabled.height == PortfolixLayout.glassControlHeight)
        #expect(enabled.width > 100)
        #expect(disabled == enabled)
    }

    @Test(arguments: [AppLanguage.chinese, .english])
    func chatActionButtonsKeepTheirNewSizesAcrossEnabledStates(language: AppLanguage) {
        for enabled in [true, false] {
            for mode in AIReportComposerAction.allCases {
                let button = NSHostingView(rootView: AIReportComposerActionButton(
                    mode: mode, title: mode.title(hasReport: true, language: language),
                    isEnabled: enabled, action: {}
                ))
                #expect(button.fittingSize == CGSize(width: 32, height: 32))
            }
        }
        #expect(PrimaryButtonStyle().cornerRadius == PortfolixRadius.compact)
        #expect(PortfolixLayout.chatComposerTopInset == PortfolixLayout.chatComposerBottomInset)
    }

    @Test(arguments: [AppLanguage.chinese, .english])
    func settingsSegmentLabelsFitTheirExistingWidth(language: AppLanguage) {
        let groups = [
            AppearanceMode.allCases.map { $0.title(language: language) },
            AppLanguage.allCases.map(\.rawValue),
            DisplayCurrency.allCases.map(\.rawValue),
            SmartAnalysisMode.availableCases.map { $0.title(language: language) },
        ]
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        for labels in groups {
            let requiredWidth = labels.reduce(CGFloat.zero) { sum, label in
                sum + (label as NSString).size(withAttributes: [.font: font]).width + PortfolixSpacing.md * 2
            } + PortfolixLayout.controlSelectionInset * 2
            #expect(requiredWidth <= 240)
        }
    }

    @Test
    func fixedCurrencyControlsKeepTheirOriginalDimensions() {
        #expect(DisplayCurrency.allCases == [.cny, .hkd, .usd, .usdt])
        for width: CGFloat in [240, 270] {
            for scheme: ColorScheme in [.light, .dark] {
                let host = NSHostingView(rootView: PortfolixGlassSegmentedPicker(
                    title: "Display Currency", selection: .constant(DisplayCurrency.cny), options: DisplayCurrency.allCases,
                    optionTitle: { $0.rawValue }, width: width, height: PortfolixLayout.positionsToolbarControlHeight
                ).environment(\.colorScheme, scheme))
                #expect(host.fittingSize == CGSize(width: width, height: PortfolixLayout.positionsToolbarControlHeight))
            }
        }
    }

    @Test
    func dashboardControlsHaveTheSameFixedHeight() {
        let segmented = NSHostingView(rootView: PortfolixGlassSegmentedPicker(
            title: "Currency",
            selection: .constant(DisplayCurrency.cny),
            options: DisplayCurrency.allCases,
            optionTitle: { $0.rawValue },
            width: 270
        ))
        let button = NSHostingView(rootView: Image(systemName: "list.bullet")
            .frame(width: PortfolixLayout.glassControlHeight)
            .portfolixGlassControl())

        #expect(segmented.fittingSize.width == 270)
        #expect(segmented.fittingSize.height == PortfolixLayout.glassControlHeight)
        #expect(button.fittingSize.height == segmented.fittingSize.height)
        #expect(PortfolixLayout.controlSpacing == 8)
        #expect(PortfolixLayout.controlSelectionInset == 2)
    }

    @Test
    func segmentedControlDoesNotResizeWhenSelectionChanges() {
        func size(for selection: DisplayCurrency) -> NSSize {
            NSHostingView(rootView: PortfolixGlassSegmentedPicker(
                title: "Currency",
                selection: .constant(selection),
                options: DisplayCurrency.allCases,
                optionTitle: { $0.rawValue }
            )).fittingSize
        }
        #expect(size(for: .cny) == size(for: .usdt))
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func selectionBackgroundUsesAPurpleGray(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        var color: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor(PortfolixTheme.controlSelectionFill).usingColorSpace(.sRGB)
        }
        let resolved = try #require(color)
        #expect(resolved.blueComponent > resolved.redComponent)
        #expect(resolved.redComponent > resolved.greenComponent)
    }

    @Test
    func defaultCardsUseEqualHorizontalAndVerticalInsets() {
        let view = NSHostingView(rootView: Panel {
            Color.clear.frame(width: 100, height: 40)
        })
        let size = view.fittingSize
        #expect(size.width == 100 + PortfolixLayout.cardPadding * 2)
        #expect(size.height == 40 + PortfolixLayout.cardPadding * 2)
        #expect(PortfolixLayout.cardPadding == 16)
    }

    @Test
    func darkGlassControlsUseOpaquePureWhite() throws {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        var color: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor(PortfolixTheme.glassControlText).usingColorSpace(.sRGB)
        }
        let resolved = try #require(color)
        #expect(abs(resolved.redComponent - 1) < 0.001)
        #expect(abs(resolved.greenComponent - 1) < 0.001)
        #expect(abs(resolved.blueComponent - 1) < 0.001)
        #expect(abs(resolved.alphaComponent - 1) < 0.001)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func textUsesSystemLabelHierarchy(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        appearance.performAsCurrentDrawingAppearance {
            #expect(NSColor(PortfolixTheme.primaryText).usingColorSpace(.sRGB)
                == NSColor.labelColor.usingColorSpace(.sRGB))
            #expect(NSColor(PortfolixTheme.secondaryText).usingColorSpace(.sRGB)
                == NSColor.secondaryLabelColor.usingColorSpace(.sRGB))
            #expect(NSColor(PortfolixTheme.tertiaryText).usingColorSpace(.sRGB)
                == NSColor.secondaryLabelColor.usingColorSpace(.sRGB))
        }
    }

    @Test
    func lightGlassControlsUseOpaqueDarkGray() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        appearance.performAsCurrentDrawingAppearance {
            #expect(NSColor(PortfolixTheme.glassControlText).usingColorSpace(.sRGB)
                == NSColor(hex: 0x3E3E3E).usingColorSpace(.sRGB))
        }
    }
}
