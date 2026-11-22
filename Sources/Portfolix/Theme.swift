import AppKit
import SwiftUI

enum PortfolixTheme {
    // MARK: Neutral colors
    // Use canvas, surface, or raised for large surfaces. Avoid pure black and white.
    static let canvas = adaptive(light: 0xEFEDF2, dark: 0x0A090D)
    static let surface = adaptive(light: 0xF7F5FA, dark: 0x121016)
    static let raised = adaptive(light: 0xFDFCFF, dark: 0x1A1720)
    static let soft = adaptive(light: 0xE5E2EA, dark: 0x241F2C)
    static let border = adaptive(light: 0xD7D3DE, dark: 0x302A3B)
    static let borderStrong = adaptive(light: 0x8F87A1, dark: 0x696079)
    static let text = adaptive(light: 0x1B1722, dark: 0xF5F3F8)
    static let secondary = adaptive(light: 0x5C5668, dark: 0xB2ABBF)
    static let tertiary = adaptive(light: 0x6F687C, dark: 0x8C8499)
    static let disabled = adaptive(light: 0xA9A2B4, dark: 0x5B5468)
    static let inverse = adaptive(light: 0xF7F5FA, dark: 0x121016)

    // MARK: Brand colors for identity, interaction, selection, focus, and single-series data
    static let brandText = adaptive(light: 0x654BC8, dark: 0xB7A5FF)
    static let brandSolid = adaptive(light: 0x654BC8, dark: 0xB7A5FF)
    static let brandSolidHover = adaptive(light: 0x513AB6, dark: 0xC2BAFC)
    static let brandSolidPressed = adaptive(light: 0x3E308F, dark: 0x9D8CFF)
    static let brandSolidInk = adaptive(light: 0xFFFFFF, dark: 0x1A1428)
    static let brandWash = adaptive(light: 0xEAE7FE, dark: 0x231D39)
    static let brandWashStrong = adaptive(light: 0xD8D2FD, dark: 0x302754)
    static let brandWashText = adaptive(light: 0x513AB6, dark: 0xC2BAFC)
    static let brandFocus = adaptive(light: 0x7C63F2, dark: 0xB7A5FF)
    static let brandChart = adaptive(light: 0x7C63F2, dark: 0xB7A5FF)
    static let brandLogoStart = adaptive(light: 0x7C63F2, dark: 0xB7A5FF)
    static let brandLogoEnd = adaptive(light: 0x654BC8, dark: 0x7C63F2)
    static let brandLogoInk = Color(hex: 0xFFFFFF)
    static let brandGradientStart = adaptive(light: 0xB7A5FF, dark: 0xB7A5FF)
    static let brandGradientEnd = adaptive(light: 0x7C63F2, dark: 0x9D8CFF)
    static let brandBubbleStart = adaptive(light: 0xC2BAFC, dark: 0xB7A5FF)
    static let brandBubbleEnd = adaptive(light: 0xB7A5FF, dark: 0x9D8CFF)
    static let brandBubbleInk = Color(hex: 0x1A1428)

    static let brandLogoGradient = LinearGradient(
        colors: [brandLogoStart, brandLogoEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let brandGradient = LinearGradient(
        colors: [brandGradientStart, brandGradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let brandBubbleGradient = LinearGradient(
        colors: [brandBubbleStart, brandBubbleEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Semantic colors for performance and risk
    static let gainFill = adaptive(light: 0x287D70, dark: 0x76C7B7)
    static let gainText = adaptive(light: 0x20675C, dark: 0x76C7B7)
    static let gainOnFill = adaptive(light: 0xFFFFFF, dark: 0x121016)
    static let lossFill = adaptive(light: 0xB44755, dark: 0xDD7D88)
    static let lossText = adaptive(light: 0x9E3947, dark: 0xDD7D88)
    static let lossOnFill = adaptive(light: 0xFFFFFF, dark: 0x121016)
    static let warnFill = adaptive(light: 0x9B681E, dark: 0xD7A967)
    static let warnText = adaptive(light: 0x805319, dark: 0xD7A967)
    static let warnOnFill = adaptive(light: 0xFFFFFF, dark: 0x121016)
    static let lossSolidHover = adaptive(light: 0x9E3947, dark: 0xE89AA4)
    static let lossSolidPressed = adaptive(light: 0x7A2B35, dark: 0xF0B0B8)

    // Opaque semantic washes from lightest (W1) to strongest (W4) for badges, charts, and calendar cells.
    static let gainWash1 = adaptive(light: 0xE2E9EC, dark: 0x202A2D)
    static let gainWash2 = adaptive(light: 0xD2DFE1, dark: 0x2A3C3D)
    static let gainWash3 = adaptive(light: 0xC1D6D6, dark: 0x344E4D)
    static let gainWash4 = adaptive(light: 0xB1CCCB, dark: 0x3E615D)
    static let lossWash1 = adaptive(light: 0xF0E4EA, dark: 0x2E1F26)
    static let lossWash2 = adaptive(light: 0xEBD6DC, dark: 0x432A31)
    static let lossWash3 = adaptive(light: 0xE6C8CF, dark: 0x57353D)
    static let lossWash4 = adaptive(light: 0xE0BAC2, dark: 0x6B4048)
    static let warnWash1 = adaptive(light: 0xEEE7E4, dark: 0x2E2521)
    static let warnWash2 = adaptive(light: 0xE6DCD2, dark: 0x413529)
    static let warnWash3 = adaptive(light: 0xDFD0C1, dark: 0x554432)
    static let warnWash4 = adaptive(light: 0xD8C5AF, dark: 0x69533A)
    static let neutralWash = adaptive(light: 0xEBE8EE, dark: 0x222027)

    // MARK: A+ asset class colors with a 12% brand purple blend, shared across the app
    static let classStockFill = adaptive(light: 0x6D85F7, dark: 0x7089FF)
    static let classStockMark = adaptive(light: 0x5F74D9, dark: 0x7089FF)
    static let classFundFill = adaptive(light: 0xAF71E4, dark: 0xB373E9)
    static let classFundMark = adaptive(light: 0x9862C6, dark: 0xB373E9)
    static let classCryptoFill = adaptive(light: 0xCC6DA9, dark: 0xE078BA)
    static let classCryptoMark = adaptive(light: 0xBE669E, dark: 0xE078BA)
    static let classCashFill = adaptive(light: 0x728FBB, dark: 0x728FBB)
    static let classCashMark = adaptive(light: 0x617A9F, dark: 0x728FBB)
    static let classOtherFill = adaptive(light: 0x9D898F, dark: 0xB49DA4)
    static let classOtherMark = adaptive(light: 0x958288, dark: 0xB49DA4)
    static let classOnFill = Color(hex: 0x121016)
    static let classMarkInk = adaptive(light: 0xFFFFFF, dark: 0x121016)

    // MARK: Muted asset class colors with 55% A+ fill and 45% neutral
    static let classStockArea = adaptive(light: 0x7C86D0, dark: 0x535EA7)
    static let classFundArea = adaptive(light: 0xA17BC6, dark: 0x78529B)
    static let classCryptoArea = adaptive(light: 0xB179A5, dark: 0x915581)
    static let classCashArea = adaptive(light: 0x7F8BAF, dark: 0x546281)
    static let classOtherArea = adaptive(light: 0x978897, dark: 0x796975)
    static let classOnArea = adaptive(light: 0x121016, dark: 0xF5F3F8)

    // MARK: Pale asset class fills with roughly 35% A+ fill over surface
    // Small markers use classMark or classArea for legibility.
    static let classStockPale = adaptive(light: 0xC8CFFC, dark: 0x333A68)
    static let classFundPale = adaptive(light: 0xDFC8F4, dark: 0x4A3360)
    static let classCryptoPale = adaptive(light: 0xEFC9E4, dark: 0x5A344F)
    static let classCashPale = adaptive(light: 0xC8D1E4, dark: 0x343C50)
    static let classOtherPale = adaptive(light: 0xE0D6DC, dark: 0x4B4148)
    static let classOnPale = adaptive(light: 0x121016, dark: 0xF5F3F8)

    // MARK: Distinct gain and loss area fills for charts without a line
    static let lossAreaWash = adaptive(light: 0xE58A96, dark: 0x7C3F4A)
    static let gainAreaWash = adaptive(light: 0xA8CBC3, dark: 0x3E615D)

    // MARK: Legacy token aliases
    // Keep existing callers compiling during migration. Use semantic tokens in new code.
    static let sidebar = surface
    static let panel = surface
    static let panelElevated = raised
    static let panelSoft = soft
    static let selectionFill = brandWash
    static let selectionText = brandWashText
    static let controlSelectionFill = brandWashStrong
    static let primaryText = text
    static let secondaryText = secondary
    static let tertiaryText = tertiary
    static let disabledText = disabled
    static let glassControlText = text
    static let lilac = brandText
    static let violet = brandFocus
    static let blue = classStockFill
    static let rose = classOtherFill
    static let amber = warnFill
    static let mint = gainFill
    static let danger = lossFill
    static let positiveStatusText = gainText
    static let negativeStatusText = lossText
    static let warningStatusText = warnText
    static let controlAccent = brandFocus
    static let primaryButtonTint = brandSolid
    static let primaryButtonText = brandSolidInk
    static let buttonShadow = Color.black.opacity(0.12)
    static let userMessageText = brandBubbleInk
    static let userMessageGradient = brandBubbleGradient
    static let userMessageGradientColors: [Color] = [brandBubbleStart, brandBubbleEnd]
    static let purpleGradient = brandGradient

    // MARK: Performance color mapping (Fill for graphics, Text for compact labels)
    static func performanceColor(for value: Decimal, scheme: PerformanceColorScheme = .greenUpRedDown) -> Color {
        if value > 0 { return scheme == .greenUpRedDown ? gainFill : lossFill }
        if value < 0 { return scheme == .greenUpRedDown ? lossFill : gainFill }
        return secondary
    }

    static func performanceColor(for value: Double, scheme: PerformanceColorScheme = .greenUpRedDown) -> Color {
        if value > 0 { return scheme == .greenUpRedDown ? gainFill : lossFill }
        if value < 0 { return scheme == .greenUpRedDown ? lossFill : gainFill }
        return secondary
    }

    static func performanceStatusText(for value: Decimal, scheme: PerformanceColorScheme = .greenUpRedDown) -> Color {
        if value > 0 { return scheme == .greenUpRedDown ? gainText : lossText }
        if value < 0 { return scheme == .greenUpRedDown ? lossText : gainText }
        return secondary
    }

    static func performanceWash(for value: Decimal, scheme: PerformanceColorScheme = .greenUpRedDown) -> Color {
        if value > 0 { return scheme == .greenUpRedDown ? gainWash2 : lossWash2 }
        if value < 0 { return scheme == .greenUpRedDown ? lossWash2 : gainWash2 }
        return neutralWash
    }

    static func dailyProfitTileFill(for amount: Decimal?, scheme: PerformanceColorScheme = .greenUpRedDown) -> Color {
        guard let amount, amount != 0 else { return neutralWash }
        return performanceWash(for: amount, scheme: scheme)
    }

    // MARK: Asset class color mapping
    static func classFill(_ assetClass: AssetClass) -> Color {
        switch assetClass {
        case .stock: return classStockFill
        case .fund: return classFundFill
        case .crypto: return classCryptoFill
        case .cash: return classCashFill
        case .other: return classOtherFill
        }
    }

    static func classMark(_ assetClass: AssetClass) -> Color {
        switch assetClass {
        case .stock: return classStockMark
        case .fund: return classFundMark
        case .crypto: return classCryptoMark
        case .cash: return classCashMark
        case .other: return classOtherMark
        }
    }

    static func classArea(_ assetClass: AssetClass) -> Color {
        switch assetClass {
        case .stock: return classStockArea
        case .fund: return classFundArea
        case .crypto: return classCryptoArea
        case .cash: return classCashArea
        case .other: return classOtherArea
        }
    }

    static func classPale(_ assetClass: AssetClass) -> Color {
        switch assetClass {
        case .stock: return classStockPale
        case .fund: return classFundPale
        case .crypto: return classCryptoPale
        case .cash: return classCashPale
        case .other: return classOtherPale
        }
    }

    private static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: match == .darkAqua ? dark : light)
        })
    }
}

/// Asset classes shared across markets and views.
enum AssetClass: String, CaseIterable, Identifiable, Sendable {
    case stock
    case fund
    case crypto
    case cash
    case other

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .stock: return language == .chinese ? "股票" : "Stocks"
        case .fund: return language == .chinese ? "基金" : "Funds"
        case .crypto: return language == .chinese ? "加密" : "Crypto"
        case .cash: return language == .chinese ? "现金" : "Cash"
        case .other: return language == .chinese ? "其他" : "Other"
        }
    }

    var fill: Color { PortfolixTheme.classFill(self) }
    var mark: Color { PortfolixTheme.classMark(self) }
    var area: Color { PortfolixTheme.classArea(self) }
    var pale: Color { PortfolixTheme.classPale(self) }
}

extension AssetCategory {
    var assetClass: AssetClass {
        switch self {
        case .cnStock, .bStock, .hkStock, .usStock: return .stock
        case .fund: return .fund
        case .crypto: return .crypto
        case .cash: return .cash
        }
    }
}

enum PortfolixSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum PortfolixRadius {
    static let compact: CGFloat = 8
    static let card: CGFloat = 10
}

enum PortfolixLayout {
    static let dataTileSpacing: CGFloat = PortfolixSpacing.xs
    static let cardPadding: CGFloat = PortfolixSpacing.lg
    static let cardHeaderHeight: CGFloat = 24
    static let dashboardRowContentHeight: CGFloat = 252
    static let dashboardHeroContentHeight = dashboardRowContentHeight
    static let dashboardTrendContentHeight = dashboardRowContentHeight
    static let accentLineWidth: CGFloat = 2
    static let glassControlHeight: CGFloat = 24
    static let positionsToolbarControlHeight: CGFloat = 30
    static let settingsControlHeight: CGFloat = 30
    static let chatComposerTopInset: CGFloat = PortfolixSpacing.lg
    static let chatComposerBottomInset: CGFloat = PortfolixSpacing.lg
    static let chatComposerHorizontalInset: CGFloat = PortfolixSpacing.lg
    static let controlSpacing: CGFloat = PortfolixSpacing.sm
    static let controlSelectionInset: CGFloat = 2
    static let distributionContentHeight: CGFloat = 180
    static let reportSummaryContentHeight: CGFloat = 144
    static let riskProfileSummaryContentHeight: CGFloat = 104
}

/// Shared type roles keep text sizes and weights consistent across views.
/// Size SF Symbols independently.
enum PortfolixTypography {
    // MARK: Rounded display numbers for metrics
    /// Portfolio total in the Overview value card.
    static let portfolioHeroValue = Font.system(size: 56, weight: .medium, design: .rounded)
    /// Primary statistic, at most one per screen.
    static let heroValue = Font.system(size: 36, weight: .light, design: .rounded)
    /// Secondary statistic shown alongside `heroValue`.
    static let heroValueCompact = Font.system(size: 32, weight: .light, design: .rounded)
    /// Primary card statistic, at most one per card.
    static let secondaryValue = Font.system(size: 24, weight: .medium, design: .rounded)

    // MARK: Headings
    /// PageHeader title, 27 pt semibold.
    static let pageTitle = Font.system(size: 27, weight: .semibold)
    /// SheetHeader title, 19 pt semibold.
    static let sheetTitle = Font.system(size: 19, weight: .semibold)
    /// SectionHeader title, 15 pt semibold.
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    /// Key figures in card summaries, 15 pt semibold.
    static let headlineValue = Font.system(size: 15, weight: .semibold)
    /// Report and form subheadings, 13 pt semibold.
    static let subheading = Font.system(size: 13, weight: .semibold)

    // MARK: Body text and labels
    /// Body text, table cells, and form inputs, 13 pt regular.
    static let body = Font.system(size: 13)
    /// Emphasized body text and derived values, 13 pt medium.
    static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    /// Labels and secondary descriptions, 12 pt regular.
    static let label = Font.system(size: 12)
    /// Emphasized labels and status badges, 12 pt medium.
    static let labelEmphasis = Font.system(size: 12, weight: .medium)
    /// Control and link labels, 12 pt medium.
    static let control = Font.system(size: 12, weight: .medium)
    /// Supporting text, times, and counts, 11 pt regular.
    static let caption = Font.system(size: 11)
    /// Emphasized supporting text, 11 pt medium.
    static let captionEmphasis = Font.system(size: 11, weight: .medium)
    /// Tooltip and compact badge text, 10 pt medium.
    static let micro = Font.system(size: 10, weight: .medium)
    /// Sidebar navigation labels, 15 pt medium.
    static let sidebarLabel = Font.system(size: 15, weight: .medium)
    /// Chart axes, legends, and calendar dates, 9 pt medium.
    static let chartAxis = Font.system(size: 9, weight: .medium)
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension NSColor {
    convenience init(hex: UInt) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

struct PortfolixSidebarBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                PortfolixTheme.surface
            } else if #available(macOS 26.0, *) {
                PortfolixTheme.surface
                    .glassEffect(.clear, in: Rectangle())
                    // Extend the glass rim beyond the clipped sidebar so it does not read as a divider.
                    .padding(-PortfolixSpacing.xs)
            } else {
                PortfolixTheme.surface
            }
        }
        .clipped()
        .ignoresSafeArea()
    }
}

struct PortfolixSheetBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            Rectangle()
                .fill(PortfolixTheme.canvas.opacity(0.96))
        }
    }
}

struct PortfolixGlassGroup<Content: View>: View {
    let spacing: CGFloat?
    let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private struct PortfolixGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var fallbackTint: Color
    var fallbackOpacity: Double
    var isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(resolvedGlass, in: shape)
        } else {
            content
                .background {
                    shape.fill(.regularMaterial)
                    shape.fill(fallbackTint.opacity(fallbackOpacity))
                }
        }
    }

    @available(macOS 26.0, *)
    private var resolvedGlass: Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if isInteractive {
            glass = glass.interactive()
        }
        return glass
    }
}

private struct PortfolixFormGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var portfolixFormGlass: Bool {
        get { self[PortfolixFormGlassKey.self] }
        set { self[PortfolixFormGlassKey.self] = newValue }
    }
}

private struct PortfolixGlassControlSurface: ViewModifier {
    let height: CGFloat
    @Environment(\.portfolixFormGlass) private var isInForm

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
    }

    func body(content: Content) -> some View {
        let label = content.frame(height: height).foregroundStyle(PortfolixTheme.text)
        Group {
            if isInForm {
                label.background {
                    Group {
                        if #available(macOS 26.0, *) {
                            ButtonGlassBackground(tint: nil)
                        } else {
                            shape.fill(.regularMaterial)
                                .overlay { shape.fill(PortfolixTheme.panelSoft.opacity(0.48)) }
                        }
                    }
                    .clipShape(shape)
                    .shadow(color: PortfolixTheme.buttonShadow, radius: 8, x: 0, y: 3)
                    .allowsHitTesting(false)
                }
            } else {
                label.portfolixGlass(in: shape, fallbackTint: PortfolixTheme.panelSoft,
                    fallbackOpacity: 0.48, interactive: true)
            }
        }
        .contentShape(shape)
    }
}

extension View {
    func portfolixGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        fallbackTint: Color = PortfolixTheme.soft,
        fallbackOpacity: Double = 0.42,
        interactive: Bool = false
    ) -> some View {
        modifier(
            PortfolixGlassSurface(
                shape: shape,
                tint: tint,
                fallbackTint: fallbackTint,
                fallbackOpacity: fallbackOpacity,
                isInteractive: interactive
            )
        )
    }

    func portfolixGlassControl(height: CGFloat = PortfolixLayout.glassControlHeight) -> some View {
        modifier(PortfolixGlassControlSurface(height: height))
    }
}

struct PortfolixSelectionBoundsKey<Value: Hashable>: PreferenceKey {
    static var defaultValue: [Value: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [Value: Anchor<CGRect>], nextValue: () -> [Value: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct PortfolixSelectionBackground<Value: Hashable>: ViewModifier {
    let selection: Value
    let cornerRadius: CGFloat
    let fill: Color
    let height: CGFloat?
    let animates: Bool
    let indicatorFill: Color?
    let indicatorWidth: CGFloat
    let indicatorHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.backgroundPreferenceValue(PortfolixSelectionBoundsKey<Value>.self) { bounds in
            GeometryReader { geometry in
                if let selectedBounds = bounds[selection] {
                    let frame = geometry[selectedBounds]
                    let resolvedHeight = min(height ?? frame.height, frame.height)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(fill)
                            .frame(width: frame.width, height: resolvedHeight)
                            .offset(x: frame.minX, y: frame.minY + (frame.height - resolvedHeight) / 2)

                        if let indicatorFill {
                            let barHeight = min(indicatorHeight ?? 18, max(resolvedHeight - 14, 8))
                            Capsule()
                                .fill(indicatorFill)
                                .frame(width: indicatorWidth, height: barHeight)
                                .offset(
                                    x: frame.minX + 2,
                                    y: frame.minY + (frame.height - barHeight) / 2
                                )
                        }
                    }
                    .animation(
                        animates && !reduceMotion ? .easeInOut(duration: 0.22) : nil,
                        value: selection
                    )
                    .transaction { transaction in
                        // Page switches remain immediate; only this persistent background animates.
                        transaction.disablesAnimations = !animates || reduceMotion
                        if !animates || reduceMotion { transaction.animation = nil }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func portfolixSelectionBackground<Value: Hashable>(
        selection: Value,
        cornerRadius: CGFloat = PortfolixRadius.compact,
        fill: Color = PortfolixTheme.brandWashStrong,
        height: CGFloat? = nil,
        animates: Bool = true,
        indicatorFill: Color? = nil,
        indicatorWidth: CGFloat = 3,
        indicatorHeight: CGFloat? = nil
    ) -> some View {
        modifier(PortfolixSelectionBackground(
            selection: selection,
            cornerRadius: cornerRadius,
            fill: fill,
            height: height,
            animates: animates,
            indicatorFill: indicatorFill,
            indicatorWidth: indicatorWidth,
            indicatorHeight: indicatorHeight
        ))
    }
}

struct PortfolixGlassSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let optionTitle: (Value) -> String
    var optionSymbol: ((Value) -> String)? = nil
    var optionAttributedTitle: ((Value) -> AttributedString)? = nil
    var width: CGFloat? = nil
    var height: CGFloat = PortfolixLayout.glassControlHeight
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focusedOption: Value?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Group {
                        if let optionSymbol {
                            Image(systemName: optionSymbol(option))
                                .frame(width: 14)
                        } else if let optionAttributedTitle {
                            Text(optionAttributedTitle(option))
                        } else {
                            Text(optionTitle(option))
                        }
                    }
                    .font(PortfolixTypography.control)
                    .foregroundStyle(PortfolixTheme.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, optionSymbol == nil ? PortfolixSpacing.md : PortfolixSpacing.sm)
                    .frame(maxWidth: width == nil ? nil : .infinity)
                    .frame(height: height - PortfolixLayout.controlSelectionInset * 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focusedOption, equals: option)
                .overlay(alignment: .trailing) {
                    if showsDivider(after: option) {
                        Rectangle()
                            .fill(PortfolixTheme.border)
                            .frame(width: 0.5, height: PortfolixSpacing.md)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(optionTitle(option))
                .accessibilityAddTraits(selection == option ? .isSelected : [])
                .onMoveCommand { moveSelection($0) }
                .anchorPreference(key: PortfolixSelectionBoundsKey<Value>.self, value: .bounds) { [option: $0] }
            }
        }
        // Keep one background alive so its bounds move continuously between buttons.
        .portfolixSelectionBackground(selection: selection,
            cornerRadius: PortfolixRadius.compact - PortfolixLayout.controlSelectionInset)
        .padding(PortfolixLayout.controlSelectionInset)
        .frame(width: width)
        .portfolixGlassControl(height: height)
        .fixedSize(horizontal: width == nil, vertical: true)
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func showsDivider(after option: Value) -> Bool {
        guard let index = options.firstIndex(of: option), index + 1 < options.count else { return false }
        return selection != option && selection != options[index + 1]
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let index = options.firstIndex(of: selection) else { return }
        let next: Int
        switch direction {
        case .left: next = index - 1
        case .right: next = index + 1
        default: return
        }
        guard options.indices.contains(next) else { return }
        selection = options[next]
        focusedOption = options[next]
    }
}

struct PortfolixGlassMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let optionTitle: (Value) -> String
    var selectionTitle: String? = nil
    var height: CGFloat = PortfolixLayout.glassControlHeight
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(optionTitle(option))
                }
            }
        } label: {
            HStack(spacing: PortfolixSpacing.sm) {
                Text(selectionTitle ?? optionTitle(selection))
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(PortfolixTypography.captionEmphasis)
            .padding(.horizontal, PortfolixSpacing.sm)
            .portfolixGlassControl(height: height)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityLabel(title)
        .accessibilityValue(selectionTitle ?? optionTitle(selection))
    }
}

struct Panel<Content: View>: View {
    let content: Content
    var padding: CGFloat = PortfolixLayout.cardPadding

    init(padding: CGFloat = PortfolixLayout.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                    .fill(PortfolixTheme.surface)
            }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var symbol: String? = nil
    let helpText: String?
    let trailing: Trailing

    init(title: String, symbol: String? = nil, helpText: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.symbol = symbol
        self.helpText = helpText
        self.trailing = trailing()
    }

    init(title: String, symbol: String? = nil, helpText: String? = nil) where Trailing == EmptyView {
        self.title = title
        self.symbol = symbol
        self.helpText = helpText
        self.trailing = EmptyView()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.secondary)
                    .frame(width: 16, height: PortfolixLayout.cardHeaderHeight)
            }

            Text(title)
                .font(PortfolixTypography.sectionTitle)
                .foregroundStyle(PortfolixTheme.text)
                .lineLimit(1)
                .frame(height: PortfolixLayout.cardHeaderHeight)

            if let helpText {
                HelpIcon(text: helpText)
            }

            Spacer(minLength: PortfolixSpacing.sm)
            trailing
        }
    }
}

/// Shared surface for chart readouts and help tooltips in both appearances.
/// Uses a raised fill, 1 pt borderStrong stroke, compact radius, and 8 by 5 pt padding.
struct PortfolixTooltipSurfaceStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, PortfolixSpacing.sm)
            .padding(.vertical, 5)
            .background(
                PortfolixTheme.raised,
                in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                    .strokeBorder(PortfolixTheme.borderStrong, lineWidth: 1)
            }
    }
}

struct PortfolixChartTooltipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(PortfolixTypography.micro)
            .portfolixTooltipSurface()
    }
}

extension View {
    func portfolixTooltipSurface() -> some View {
        modifier(PortfolixTooltipSurfaceStyle())
    }

    func portfolixChartTooltip() -> some View {
        modifier(PortfolixChartTooltipStyle())
    }

    func portfolixNumericTransition<Value: Equatable>(_ value: Value) -> some View {
        modifier(PortfolixNumericTextStyle(value: value))
    }
}

private struct PortfolixNumericTextStyle<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: value)
    }
}

extension PerformanceColorScheme {
    func selectorTitle(language: AppLanguage) -> AttributedString {
        var title = AttributedString(self.title(language: language) + " ")
        var up = AttributedString("↑")
        up.foregroundColor = PortfolixTheme.performanceColor(for: Decimal(1), scheme: self)
        var down = AttributedString("↓")
        down.foregroundColor = PortfolixTheme.performanceColor(for: Decimal(-1), scheme: self)
        title += up
        title += down
        return title
    }
}

struct CardMetaLabel: View {
    let title: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: PortfolixSpacing.xs) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(title)
        }
        .font(PortfolixTypography.caption)
        .foregroundStyle(PortfolixTheme.tertiary)
        .lineLimit(1)
    }
}

struct RelativeTimeText: View {
    var refreshInterval: TimeInterval = 30
    let value: (Date) -> String

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            Text(value(context.date))
        }
    }
}

struct StatusBadge: View {
    let freshness: Freshness
    var isSelected = false

    private var badgeForeground: Color {
        if isSelected { return PortfolixTheme.brandWashText }
        switch freshness {
        case .updated: return PortfolixTheme.secondary
        case .stale: return PortfolixTheme.warnText
        case .manual: return PortfolixTheme.secondary
        }
    }

    private var badgeBackground: Color {
        if isSelected { return PortfolixTheme.brandWash }
        switch freshness {
        case .stale: return PortfolixTheme.warnWash1
        default: return PortfolixTheme.neutralWash
        }
    }

    var body: some View {
        Label(freshness.rawValue, systemImage: freshness.symbol)
            .font(PortfolixTypography.captionEmphasis)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(badgeBackground, in: Capsule())
    }
}

struct CapsuleLabel: View {
    let title: String
    let color: Color
    var symbol: String? = nil
    var background: Color = PortfolixTheme.neutralWash

    var body: some View {
        HStack(spacing: PortfolixSpacing.xs) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(title)
        }
        .font(PortfolixTypography.captionEmphasis)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var preservesLabelSize = false
    var cornerRadius: CGFloat = PortfolixRadius.compact

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonLabel(configuration: configuration, isPrimary: true, preservesLabelSize: preservesLabelSize, cornerRadius: cornerRadius)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var preservesLabelSize = false

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonLabel(configuration: configuration, isPrimary: false, preservesLabelSize: preservesLabelSize)
    }
}

@available(macOS 26.0, *)
struct ButtonGlassBackground: NSViewRepresentable {
    let tint: Color?
    var cornerRadius: CGFloat = PortfolixRadius.compact
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> ButtonGlassView {
        let view = ButtonGlassView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: ButtonGlassView, context: Context) {
        nsView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        nsView.tintColor = tint.map { NSColor($0) }
        nsView.cornerRadius = cornerRadius
    }
}

@available(macOS 26.0, *)
final class ButtonGlassView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct InteractiveButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    let isPrimary: Bool
    let preservesLabelSize: Bool
    var cornerRadius: CGFloat = PortfolixRadius.compact

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(PortfolixTypography.control)
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, preservesLabelSize ? 0 : PortfolixSpacing.md)
            .padding(.vertical, preservesLabelSize ? 0 : PortfolixSpacing.sm)
            .background {
                Group {
                    if #available(macOS 26.0, *) {
                        ButtonGlassBackground(tint: isPrimary && isEnabled ? PortfolixTheme.primaryButtonTint : nil, cornerRadius: cornerRadius)
                            .overlay {
                                if isPrimary && isEnabled {
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                        .fill(PortfolixTheme.primaryButtonTint.opacity(0.45))
                                }
                            }
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(isPrimary && isEnabled
                                        ? PortfolixTheme.primaryButtonTint.opacity(0.88)
                                        : PortfolixTheme.panelSoft.opacity(0.48))
                            }
                    }
                }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .shadow(color: PortfolixTheme.buttonShadow, radius: 4, x: 0, y: 2)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(!isEnabled ? 0.5 : configuration.isPressed ? 0.72 : isHovering ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        if !isEnabled { return PortfolixTheme.disabled }
        if configuration.role == .destructive { return PortfolixTheme.lossFill }
        return isPrimary ? PortfolixTheme.primaryButtonText : PortfolixTheme.text
    }
}

func formatMoney(_ value: Decimal, currency: DisplayCurrency, maximumFractionDigits: Int = 2) -> String {
    formattedMoney(value, currency: currency, maximumFractionDigits: maximumFractionDigits, separatesSymbol: false)
}

func formatUnitCost(_ value: Decimal, currency: DisplayCurrency) -> String {
    if value != 0, abs(value) < Decimal(string: "0.00000001")! {
        return formatMoney(value, currency: currency)
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = abs(value) < 0.01 ? 8 : 6
    formatter.groupingSeparator = ","
    return "\(currency.symbol)\(formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00")"
}

func formatHeroMoney(_ value: Decimal, currency: DisplayCurrency, maximumFractionDigits: Int = 2) -> String {
    formattedMoney(value, currency: currency, maximumFractionDigits: maximumFractionDigits, separatesSymbol: true)
}

private func formattedMoney(
    _ value: Decimal,
    currency: DisplayCurrency,
    maximumFractionDigits: Int,
    separatesSymbol: Bool
) -> String {
    let absoluteValue = abs(value)
    let minimumVisibleValue = Decimal(string: "0.00000001")!
    let separator = separatesSymbol ? " " : ""
    if maximumFractionDigits == 2, absoluteValue > 0, absoluteValue < minimumVisibleValue {
        return "\(currency.symbol)\(separator)< 0.00000001"
    }

    let usesAdaptivePrecision = maximumFractionDigits == 2
        && absoluteValue > 0
        && absoluteValue < 0.01
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = usesAdaptivePrecision ? 8 : maximumFractionDigits
    formatter.minimumFractionDigits = usesAdaptivePrecision ? 2 : maximumFractionDigits
    formatter.groupingSeparator = ","
    return "\(currency.symbol)\(separator)\(formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00")"
}

func formatSignedMoney(_ value: Decimal, currency: DisplayCurrency, maximumFractionDigits: Int = 2) -> String {
    let sign = value >= 0 ? "+" : "-"
    return "\(sign)\(formatMoney(abs(value), currency: currency, maximumFractionDigits: maximumFractionDigits))"
}

func formatPercent(_ value: Decimal) -> String {
    let prefix = value >= 0 ? "+" : ""
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return "\(prefix)\(formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00")%"
}
