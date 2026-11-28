import AppKit
import SwiftUI

enum PortfolixTheme {
    // MARK: Neutral colors (v1.4.1 Obsidian Amethyst — 3-level surface elevation)
    // Pure obsidian slate in dark mode (L0 canvas -> L1 surface -> L2 raised) and clean porcelain in light mode.
    static let canvas = adaptive(light: 0xF2F3F7, dark: 0x0B0C10)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x14171F)
    static let raised = adaptive(light: 0xFFFFFF, dark: 0x1E222D)
    static let soft = adaptive(light: 0xECEEF4, dark: 0x262B38)
    static let border = adaptive(light: 0xE2E4EC, dark: 0x292F3D)
    static let borderStrong = adaptive(light: 0x82889C, dark: 0x687189)
    static let cardBorder = adaptive(light: 0x111422, lightAlpha: 0.075, dark: 0xFFFFFF, darkAlpha: 0.042)
    static let controlBorder = adaptive(light: 0x111422, lightAlpha: 0.12, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let cardShadow = adaptive(light: 0x111422, lightAlpha: 0.028, dark: 0x000000, darkAlpha: 0.0)
    static let subtleFill = adaptive(light: 0xF0F2F7, dark: 0x1C202B)
    static let text = adaptive(light: 0x14161F, dark: 0xF4F6FA)
    static let secondary = adaptive(light: 0x53586C, dark: 0xA7AEC2)
    static let tertiary = adaptive(light: 0x676D82, dark: 0x858EA6)
    static let disabled = adaptive(light: 0x9FA5B8, dark: 0x586075)
    static let inverse = adaptive(light: 0xFFFFFF, dark: 0x14171F)

    // MARK: Brand colors for identity, interaction, selection, focus, and single-series data
    static let brandText = adaptive(light: 0x5E47C7, dark: 0xB7A6FF)
    static let brandSolid = adaptive(light: 0x5E47C7, dark: 0x6E56CF)
    static let brandSolidHover = adaptive(light: 0x4C36B2, dark: 0x765FD6)
    static let brandSolidPressed = adaptive(light: 0x3C2994, dark: 0x5B44B8)
    static let brandSolidInk = adaptive(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let brandWash = adaptive(light: 0xEFEBFD, dark: 0x221E3A)
    static let brandWashStrong = adaptive(light: 0xE0D9FA, dark: 0x4C3E8A)
    static let brandWashText = adaptive(light: 0x4C36B2, dark: 0xC8BDFF)
    static let brandFocus = adaptive(light: 0x6C54D9, dark: 0x9B87FF)
    static let brandChart = adaptive(light: 0x6C54D9, dark: 0x9B87FF)
    static let brandLogoStart = adaptive(light: 0xB9A7FF, dark: 0x9B87FF)
    static let brandLogoEnd = adaptive(light: 0x7C63F2, dark: 0x6E56CF)
    static let brandLogoInk = Color(hex: 0xFFFFFF)
    static let brandGradientStart = adaptive(light: 0x9B87FF, dark: 0x9B87FF)
    static let brandGradientEnd = adaptive(light: 0x6C54D9, dark: 0x6E56CF)
    static let brandBubbleStart = adaptive(light: 0xDDD5FA, dark: 0x725AD4)
    static let brandBubbleEnd = adaptive(light: 0xCEC2F8, dark: 0x5E47C7)
    static let brandBubbleInk = adaptive(light: 0x1D1738, dark: 0xFFFFFF)

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

    // MARK: Semantic colors for performance and risk (Steady Botanical Jade & Refined Crimson)
    static let gainFill = adaptive(light: 0x267D60, dark: 0x54BC96)
    static let gainText = adaptive(light: 0x1E6B52, dark: 0x54BC96)
    static let gainOnFill = adaptive(light: 0xFFFFFF, dark: 0x0D1512)
    static let lossFill = adaptive(light: 0xBC404B, dark: 0xE26E78)
    static let lossText = adaptive(light: 0xA6343F, dark: 0xE26E78)
    static let lossOnFill = adaptive(light: 0xFFFFFF, dark: 0x170D0F)
    static let warnFill = adaptive(light: 0x9E6510, dark: 0xE2AE5B)
    static let warnText = adaptive(light: 0x85530C, dark: 0xE2AE5B)
    static let warnOnFill = adaptive(light: 0xFFFFFF, dark: 0x17120A)
    static let lossSolidHover = adaptive(light: 0x9A2E38, dark: 0xEC848D)
    static let lossSolidPressed = adaptive(light: 0x7F232C, dark: 0xCC5B65)

    // Opaque semantic washes from lightest (W1) to strongest (W4) for badges, charts, and tiles.
    static let gainWash1 = adaptive(light: 0xEBF2EF, dark: 0x182622)
    static let gainWash2 = adaptive(light: 0xD7E6DF, dark: 0x1E332D)
    static let gainWash3 = adaptive(light: 0xC0D8CE, dark: 0x27453C)
    static let gainWash4 = adaptive(light: 0xA7C9BC, dark: 0x31584C)
    static let lossWash1 = adaptive(light: 0xF4ECEC, dark: 0x261A1E)
    static let lossWash2 = adaptive(light: 0xECDADB, dark: 0x362025)
    static let lossWash3 = adaptive(light: 0xE1C3C6, dark: 0x492A30)
    static let lossWash4 = adaptive(light: 0xD5ACB1, dark: 0x5E343C)
    static let warnWash1 = adaptive(light: 0xF6EFE4, dark: 0x292117)
    static let warnWash2 = adaptive(light: 0xEDE0CA, dark: 0x3D301E)
    static let warnWash3 = adaptive(light: 0xE4D0AE, dark: 0x524026)
    static let warnWash4 = adaptive(light: 0xDABF91, dark: 0x68512F)
    static let neutralWash = adaptive(light: 0xEFEFF4, dark: 0x1F232E)

    // MARK: Limited-hue, low-saturation 5-class asset palette (Slate Cobalt, Muted Iris, Dusty Plum, Mist Teal, Graphite Pewter)
    static let classStockFill = adaptive(light: 0x4B72C8, dark: 0x6B92E8)
    static let classStockMark = adaptive(light: 0x3B61B5, dark: 0x759BF0)
    static let classFundFill = adaptive(light: 0x8367CC, dark: 0x9B80E4)
    static let classFundMark = adaptive(light: 0x6A4FB5, dark: 0xA68CEB)
    static let classCryptoFill = adaptive(light: 0x9E68A6, dark: 0xBE86C4)
    static let classCryptoMark = adaptive(light: 0x834F8C, dark: 0xC892CE)
    static let classCashFill = adaptive(light: 0x47868B, dark: 0x5BA3A8)
    static let classCashMark = adaptive(light: 0x336E73, dark: 0x66B0B5)
    static let classOtherFill = adaptive(light: 0x808698, dark: 0x9097AB)
    static let classOtherMark = adaptive(light: 0x63697B, dark: 0x9BA2B6)
    static let classOnFill = Color(hex: 0x14161F)
    static let classMarkInk = adaptive(light: 0xFFFFFF, dark: 0x14171F)

    // MARK: Mid-chroma asset class markers for legend dots, category badges, and small accents
    static let classStockArea = adaptive(light: 0x476DC0, dark: 0x6289DF)
    static let classFundArea = adaptive(light: 0x795EC2, dark: 0x9276DB)
    static let classCryptoArea = adaptive(light: 0x935E9B, dark: 0xB37BB9)
    static let classCashArea = adaptive(light: 0x407E83, dark: 0x53999E)
    static let classOtherArea = adaptive(light: 0x73798C, dark: 0x878EA2)
    static let classOnArea = adaptive(light: 0xFFFFFF, dark: 0x14171F)

    // MARK: Pale asset class fills for treemap tiles, holding share bars, and row avatars
    static let classStockPale = adaptive(light: 0xD6E2F7, dark: 0x203356)
    static let classFundPale = adaptive(light: 0xE5DDF8, dark: 0x322854)
    static let classCryptoPale = adaptive(light: 0xF0DFEE, dark: 0x462E4D)
    static let classCashPale = adaptive(light: 0xD4E9E9, dark: 0x1D3A42)
    static let classOtherPale = adaptive(light: 0xE7E9EE, dark: 0x2E323D)
    static let classOnPale = adaptive(light: 0x14161F, dark: 0xF4F6FA)

    // MARK: Distinct gain and loss area fills for return and drawdown charts
    static let lossAreaWash = adaptive(light: 0xDFB3B7, dark: 0x65323A)
    static let gainAreaWash = adaptive(light: 0xB2CFC4, dark: 0x265345)

    // MARK: Glass button shadow
    static let buttonShadow = Color.black.opacity(0.14)

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

    private static func adaptive(
        light: UInt,
        lightAlpha: CGFloat,
        dark: UInt,
        darkAlpha: CGFloat
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
                return NSColor(hex: dark).withAlphaComponent(darkAlpha)
            }
            return NSColor(hex: light).withAlphaComponent(lightAlpha)
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

private struct PortfolixSecondaryGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedCornerRadius: CGFloat? {
        (shape as? RoundedRectangle)?.cornerSize.width
    }

    func body(content: Content) -> some View {
        let lightTint: Color? = colorScheme == .light ? PortfolixTheme.soft.opacity(0.55) : nil
        content
            .background {
                if #available(macOS 26.0, *) {
                    // Use AppKit's NSGlassEffectView across main windows, sheets, and popovers so
                    // modal sheet presentations never flatten SwiftUI `.glassEffect` into dull blocks.
                    ButtonGlassBackground(
                        tint: lightTint,
                        cornerRadius: resolvedCornerRadius ?? PortfolixRadius.compact,
                        isCapsule: resolvedCornerRadius == nil
                    )
                    .allowsHitTesting(false)
                } else {
                    ZStack {
                        shape.fill(.regularMaterial)
                        shape.fill(PortfolixTheme.soft.opacity(0.55))
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                shape
                    .strokeBorder(PortfolixTheme.controlBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

private struct PortfolixGlassControlSurface: ViewModifier {
    let height: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .frame(height: height)
            .foregroundStyle(PortfolixTheme.text)
            .portfolixSecondaryGlass(in: shape, interactive: true)
            .contentShape(shape)
    }
}

extension View {
    func portfolixSecondaryGlass<S: InsettableShape>(
        in shape: S,
        interactive: Bool = true
    ) -> some View {
        modifier(PortfolixSecondaryGlassSurface(shape: shape, interactive: interactive))
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
    var fillsWidth: Bool = false
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
                    .frame(maxWidth: (width != nil || fillsWidth) ? .infinity : nil)
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
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .portfolixGlassControl(height: height)
        .fixedSize(horizontal: width == nil && !fillsWidth, vertical: true)
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
    var fillsWidth: Bool = false
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
                    .lineLimit(1)
                    .fixedSize(horizontal: !fillsWidth, vertical: false)
                if fillsWidth {
                    Spacer(minLength: PortfolixSpacing.xs)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.secondary)
            }
            .font(PortfolixTypography.captionEmphasis)
            .padding(.horizontal, fillsWidth ? PortfolixSpacing.md : PortfolixSpacing.sm)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .portfolixGlassControl(height: height)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .fixedSize(horizontal: !fillsWidth, vertical: true)
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
        let shape = RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
        content
            .padding(padding)
            .background {
                shape
                    .fill(PortfolixTheme.surface)
                    .shadow(color: PortfolixTheme.cardShadow, radius: 1.5, x: 0, y: 0.5)
            }
            .overlay {
                shape
                    .strokeBorder(PortfolixTheme.cardBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
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

struct PortfolixInlineStatusLabel: View {
    let title: String
    let symbol: String
    var color: Color = PortfolixTheme.secondary
    var font: Font = PortfolixTypography.captionEmphasis
    var symbolSize: CGFloat = 11

    var body: some View {
        HStack(spacing: PortfolixSpacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
            Text(title)
                .font(font)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
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
    var isCapsule: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> ButtonGlassView {
        let view = ButtonGlassView()
        view.style = .regular
        view.isCapsule = isCapsule
        view.cornerRadius = cornerRadius
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: ButtonGlassView, context: Context) {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        if nsView.appearance?.name != appearanceName {
            nsView.appearance = appearance
        }
        let targetTint = Self.resolvedTintColor(tint, for: appearance)
        if nsView.tintColor != targetTint {
            nsView.tintColor = targetTint
        }
        if nsView.isCapsule != isCapsule {
            nsView.isCapsule = isCapsule
        }
        if isCapsule {
            nsView.updateCapsuleCornerRadius()
        } else if nsView.cornerRadius != cornerRadius {
            nsView.cornerRadius = cornerRadius
        }
    }

    static func resolvedTintColor(_ tint: Color?, for appearance: NSAppearance?) -> NSColor? {
        guard let tint else { return nil }
        var resolved = NSColor(tint)
        appearance?.performAsCurrentDrawingAppearance {
            let dynamic = NSColor(tint)
            resolved = dynamic.usingColorSpace(.sRGB) ?? dynamic
        }
        return resolved
    }
}

@available(macOS 26.0, *)
final class ButtonGlassView: NSGlassEffectView {
    var isCapsule = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        if isCapsule {
            updateCapsuleCornerRadius()
        }
    }

    func updateCapsuleCornerRadius() {
        let radius = min(bounds.width, bounds.height) / 2
        if radius > 0, abs(cornerRadius - radius) > 0.01 {
            cornerRadius = radius
        }
    }
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let baseLabel = configuration.label
            .font(PortfolixTypography.control)
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, preservesLabelSize ? 0 : PortfolixSpacing.md)
            .padding(.vertical, preservesLabelSize ? 0 : PortfolixSpacing.sm)

        Group {
            if isPrimary {
                baseLabel
                    .background {
                        Group {
                            if #available(macOS 26.0, *) {
                                ButtonGlassBackground(tint: isEnabled ? PortfolixTheme.brandSolid : nil, cornerRadius: cornerRadius)
                                    .overlay {
                                        if isEnabled {
                                            shape.fill(PortfolixTheme.brandSolid.opacity(0.45))
                                        }
                                    }
                            } else {
                                shape
                                    .fill(.regularMaterial)
                                    .overlay {
                                        shape.fill(isEnabled
                                            ? PortfolixTheme.brandSolid.opacity(0.88)
                                            : PortfolixTheme.soft.opacity(0.48))
                                    }
                            }
                        }
                        .clipShape(shape)
                        .shadow(color: PortfolixTheme.buttonShadow, radius: 4, x: 0, y: 2)
                        .allowsHitTesting(false)
                    }
            } else {
                baseLabel
                    .portfolixSecondaryGlass(in: shape, interactive: true)
            }
        }
        .contentShape(shape)
        .opacity(!isEnabled ? 0.5 : configuration.isPressed ? 0.72 : isHovering ? 0.88 : 1)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        if !isEnabled { return PortfolixTheme.disabled }
        if configuration.role == .destructive { return PortfolixTheme.lossFill }
        return isPrimary ? PortfolixTheme.brandSolidInk : PortfolixTheme.text
    }
}

private enum PortfolixNumberFormatters {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var decimalFormatters: [String: NumberFormatter] = [:]
    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func decimal(_ value: Decimal, minFraction: Int, maxFraction: Int) -> String {
        let key = "\(minFraction)-\(maxFraction)"
        return lock.withLock {
            let formatter: NumberFormatter
            if let cached = decimalFormatters[key] {
                formatter = cached
            } else {
                let created = NumberFormatter()
                created.numberStyle = .decimal
                created.minimumFractionDigits = minFraction
                created.maximumFractionDigits = maxFraction
                created.groupingSeparator = ","
                decimalFormatters[key] = created
                formatter = created
            }
            return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
        }
    }

    static func percent(_ value: Decimal) -> String {
        lock.withLock {
            percentFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
        }
    }
}

private let minimumVisibleMoneyValue = Decimal(sign: .plus, exponent: -8, significand: 1)

func formatMoney(_ value: Decimal, currency: DisplayCurrency, maximumFractionDigits: Int = 2) -> String {
    formattedMoney(value, currency: currency, maximumFractionDigits: maximumFractionDigits, separatesSymbol: false)
}

func formatUnitCost(_ value: Decimal, currency: DisplayCurrency) -> String {
    if value != 0, abs(value) < minimumVisibleMoneyValue {
        return formatMoney(value, currency: currency)
    }
    let maxDigits = abs(value) < 0.01 ? 8 : 6
    let formatted = PortfolixNumberFormatters.decimal(value, minFraction: 2, maxFraction: maxDigits)
    return "\(currency.symbol)\(formatted)"
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
    let separator = separatesSymbol ? " " : ""
    if maximumFractionDigits == 2, absoluteValue > 0, absoluteValue < minimumVisibleMoneyValue {
        return "\(currency.symbol)\(separator)< 0.00000001"
    }

    let usesAdaptivePrecision = maximumFractionDigits == 2
        && absoluteValue > 0
        && absoluteValue < 0.01
    let minDigits = usesAdaptivePrecision ? 2 : maximumFractionDigits
    let maxDigits = usesAdaptivePrecision ? 8 : maximumFractionDigits
    let formatted = PortfolixNumberFormatters.decimal(value, minFraction: minDigits, maxFraction: maxDigits)
    return "\(currency.symbol)\(separator)\(formatted)"
}

func formatSignedMoney(_ value: Decimal, currency: DisplayCurrency, maximumFractionDigits: Int = 2) -> String {
    let sign = value >= 0 ? "+" : "-"
    return "\(sign)\(formatMoney(abs(value), currency: currency, maximumFractionDigits: maximumFractionDigits))"
}

func formatPercent(_ value: Decimal) -> String {
    let prefix = value >= 0 ? "+" : ""
    return "\(prefix)\(PortfolixNumberFormatters.percent(value))%"
}
