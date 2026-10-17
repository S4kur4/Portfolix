import AppKit
import SwiftUI
import Testing
@testable import Portfolix

@Suite("Text color hierarchy")
@MainActor
struct ThemeTests {
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
        #expect(surface.redComponent > background.redComponent + 0.04)
        #expect(abs(surface.blueComponent - surface.redComponent) < 0.02)
        #expect(surface == NSColor(hex: 0x0B0C0E).usingColorSpace(.sRGB))
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
