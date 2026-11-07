import AppKit
import SwiftUI

enum PortfolixTheme {
    // Keep large surfaces neutral so brand color is reserved for meaning and interaction.
    static let canvas = adaptive(light: 0xE8E8E8, dark: 0x000000)
    private static let primarySurface = adaptive(light: 0xF3F3F3, dark: 0x080808)
    static let sidebar = primarySurface
    static let panel = primarySurface
    static let panelElevated = adaptive(light: 0xE8E8E8, dark: 0x141414)
    static let panelSoft = adaptive(light: 0xE0E0E0, dark: 0x1A1A1A)
    static let selectionFill = adaptive(light: 0xE2DDF1, dark: 0x18151F)
    static let selectionText = adaptive(light: 0x513AB6, dark: 0xC5BAF8)
    static let controlSelectionFill = adaptive(light: 0xDCD7E7, dark: 0x3F3B4B)
    static let border = Color(nsColor: .separatorColor)
    static let borderStrong = Color(nsColor: .gridColor)
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    // Keep useful metadata readable; reserve the dimmer system color for disabled controls.
    static let tertiaryText = secondaryText
    static let disabledText = Color(nsColor: .disabledControlTextColor)
    // Opaque text avoids different vibrancy blending between AppKit and SwiftUI glass.
    private static let lightGlassText: UInt = 0x3E3E3E
    static let glassControlText = adaptive(light: lightGlassText, dark: 0xFFFFFF)
    static let lilac = adaptive(light: 0x654BC8, dark: 0xB7A5FF)
    static let violet = adaptive(light: 0x7253DB, dark: 0x8C75FF)
    static let blue = adaptive(light: 0x3B6FCC, dark: 0x7FA7FF)
    static let rose = adaptive(light: 0xA34C98, dark: 0xD184C6)
    static let amber = adaptive(light: 0x9B681E, dark: 0xD7A967)
    static let mint = adaptive(light: 0x287D70, dark: 0x76C7B7)
    static let danger = adaptive(light: 0xB44755, dark: 0xDD7D88)
    // Text on tonal status backgrounds needs more contrast than the decorative fill.
    static let positiveStatusText = adaptive(light: 0x20675C, dark: 0x76C7B7)
    static let negativeStatusText = adaptive(light: 0x9E3947, dark: 0xDD7D88)
    static let warningStatusText = adaptive(light: 0x805319, dark: 0xD7A967)
    static let controlAccent = violet
    static let primaryButtonTint = adaptive(light: 0xAF9AFF, dark: 0xB7A5FF)
    static let primaryButtonText = adaptive(light: lightGlassText, dark: 0x120F20)
    static let buttonShadow = Color.black.opacity(0.12)

    static func performanceColor(for value: Decimal, scheme: PerformanceColorScheme = .greenUpRedDown) -> Color {
        if value > 0 { return scheme == .greenUpRedDown ? mint : danger }
        if value < 0 { return scheme == .greenUpRedDown ? danger : mint }
        return secondaryText
    }

    static func performanceColor(for value: Double, scheme: PerformanceColorScheme = .greenUpRedDown) -> Color {
        if value > 0 { return scheme == .greenUpRedDown ? mint : danger }
        if value < 0 { return scheme == .greenUpRedDown ? danger : mint }
        return secondaryText
    }

    static func performanceStatusText(for value: Decimal, scheme: PerformanceColorScheme = .greenUpRedDown) -> Color {
        if value > 0 { return scheme == .greenUpRedDown ? positiveStatusText : negativeStatusText }
        if value < 0 { return scheme == .greenUpRedDown ? negativeStatusText : positiveStatusText }
        return secondaryText
    }

    static func dailyProfitTileFill(for amount: Decimal?, scheme: PerformanceColorScheme = .greenUpRedDown) -> Color {
        guard let amount else { return .clear }
        if amount != 0 { return performanceColor(for: amount, scheme: scheme).opacity(0.13) }
        return panelSoft.opacity(0.55)
    }

    static let userMessageText = Color(hex: 0x120F20)
    static let userMessageGradientColors = [
        adaptive(light: 0xAF9AFF, dark: 0xC3B1FF),
        adaptive(light: 0x8F75EB, dark: 0x8068EF),
    ]
    static let userMessageGradient = LinearGradient(
        colors: userMessageGradientColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let purpleGradient = LinearGradient(
        colors: [adaptive(light: 0xAF9AFF, dark: 0xC3B1FF), adaptive(light: 0x7457E2, dark: 0x8068EF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: match == .darkAqua ? dark : light)
        })
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

enum PortfolixTypography {
    static let heroValue = Font.system(size: 36, weight: .light, design: .rounded)
    static let portfolioHeroValue = Font.system(size: 56, weight: .medium, design: .rounded)
    static let secondaryValue = Font.system(size: 24, weight: .light, design: .rounded)
    static let pageTitle = Font.system(size: 27, weight: .semibold)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11)
    static let captionEmphasis = Font.system(size: 11, weight: .medium)
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
                PortfolixTheme.sidebar
            } else if #available(macOS 26.0, *) {
                PortfolixTheme.sidebar
                    .glassEffect(.clear, in: Rectangle())
                    // Extend the glass rim beyond the clipped sidebar so it does not read as a divider.
                    .padding(-PortfolixSpacing.xs)
            } else {
                PortfolixTheme.sidebar
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
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
    }

    func body(content: Content) -> some View {
        let label = content.frame(height: height).foregroundStyle(PortfolixTheme.glassControlText)
        Group {
            if isInForm && colorScheme == .light {
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
        fallbackTint: Color = PortfolixTheme.panelSoft,
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

struct PortfolixGlassSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let optionTitle: (Value) -> String
    var optionSymbol: ((Value) -> String)? = nil
    var optionAttributedTitle: ((Value) -> AttributedString)? = nil
    var width: CGFloat? = nil
    var height: CGFloat = PortfolixLayout.glassControlHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PortfolixTheme.glassControlText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, optionSymbol == nil ? PortfolixSpacing.md : PortfolixSpacing.sm)
                    .frame(maxWidth: width == nil ? nil : .infinity)
                    .frame(height: height - PortfolixLayout.controlSelectionInset * 2)
                    .background {
                        if selection == option {
                            RoundedRectangle(
                                cornerRadius: PortfolixRadius.compact - PortfolixLayout.controlSelectionInset,
                                style: .continuous
                            )
                            .fill(PortfolixTheme.controlSelectionFill)
                        }
                    }
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
            }
        }
        .padding(PortfolixLayout.controlSelectionInset)
        .frame(width: width)
        .portfolixGlassControl(height: height)
        .fixedSize(horizontal: width == nil, vertical: true)
        .opacity(isEnabled ? 1 : 0.58)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection)
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
                    .fill(PortfolixTheme.panel)
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
                    .foregroundStyle(PortfolixTheme.lilac)
                    .frame(width: 16, height: PortfolixLayout.cardHeaderHeight)
            }

            Text(title)
                .font(PortfolixTypography.sectionTitle)
                .foregroundStyle(PortfolixTheme.primaryText)
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

struct PortfolixChartTooltipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(PortfolixTheme.panelSoft, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact))
            .overlay {
                RoundedRectangle(cornerRadius: PortfolixRadius.compact)
                    .stroke(PortfolixTheme.borderStrong, lineWidth: 1)
            }
    }
}

extension View {
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
        .foregroundStyle(PortfolixTheme.tertiaryText)
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

    var body: some View {
        Label(freshness.rawValue, systemImage: freshness.symbol)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isSelected ? Color.white : freshness.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.white.opacity(0.16) : freshness.color.opacity(0.11), in: Capsule())
    }
}

struct CapsuleLabel: View {
    let title: String
    let color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: PortfolixSpacing.xs) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(title)
        }
        .font(.system(size: 10, weight: .medium))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.11), in: Capsule())
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
            .font(.system(size: 12, weight: .medium))
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
        if !isEnabled { return PortfolixTheme.disabledText }
        if configuration.role == .destructive { return PortfolixTheme.danger }
        return isPrimary ? PortfolixTheme.primaryButtonText : PortfolixTheme.glassControlText
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
