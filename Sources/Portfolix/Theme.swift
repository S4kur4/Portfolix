import AppKit
import SwiftUI

enum PortfolixTheme {
    static let canvas = adaptive(light: 0xF6F6F8, dark: 0x07080A)
    static let sidebar = adaptive(light: 0xEFF0F3, dark: 0x0A0B0E)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x0F1014)
    static let panelElevated = adaptive(light: 0xF3F4F6, dark: 0x14161B)
    static let panelSoft = adaptive(light: 0xE9EAEE, dark: 0x1A1C22)
    static let selectionFill = adaptive(light: 0xE8E3FA, dark: 0x211D30)
    static let selectionText = adaptive(light: 0x513AB6, dark: 0xC9BEFF)
    static let border = Color(nsColor: .separatorColor)
    static let borderStrong = Color(nsColor: .gridColor)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(nsColor: .secondaryLabelColor).opacity(0.78)
    static let lilac = adaptive(light: 0x654BC8, dark: 0xB7A5FF)
    static let violet = adaptive(light: 0x7253DB, dark: 0x8C75FF)
    static let blue = adaptive(light: 0x3B6FCC, dark: 0x7FA7FF)
    static let rose = adaptive(light: 0xA34C98, dark: 0xD184C6)
    static let amber = adaptive(light: 0x9B681E, dark: 0xD7A967)
    static let mint = adaptive(light: 0x287D70, dark: 0x76C7B7)
    static let danger = adaptive(light: 0xB44755, dark: 0xDD7D88)

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
    static let dashboardHeroContentHeight: CGFloat = 268
    static let dashboardTrendContentHeight: CGFloat = 252
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
    var body: some View {
        PortfolixTheme.sidebar
        .ignoresSafeArea()
    }
}

struct PortfolixSheetBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            Rectangle()
                .fill(PortfolixTheme.canvas.opacity(0.88))
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
                    shape.stroke(PortfolixTheme.border.opacity(0.72), lineWidth: 1)
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
}

struct Panel<Content: View>: View {
    let content: Content
    var padding: CGFloat = PortfolixSpacing.lg

    init(padding: CGFloat = PortfolixSpacing.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                    .fill(PortfolixTheme.panel)
                RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                    .stroke(PortfolixTheme.border.opacity(0.82), lineWidth: 1)
            }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var symbol: String? = nil
    let trailing: Trailing

    init(title: String, symbol: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing()
    }

    init(title: String, symbol: String? = nil) where Trailing == EmptyView {
        self.title = title
        self.symbol = symbol
        self.trailing = EmptyView()
    }

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.lilac)
                    .frame(width: 16)
            }

            Text(title)
                .font(PortfolixTypography.sectionTitle)
                .foregroundStyle(PortfolixTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: PortfolixSpacing.sm)
            trailing
        }
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
    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonLabel(configuration: configuration, isPrimary: true)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonLabel(configuration: configuration, isPrimary: false)
    }
}

private struct InteractiveButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    let isPrimary: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(isPrimary ? Color(hex: 0x120F20) : PortfolixTheme.secondaryText)
            .padding(.horizontal, PortfolixSpacing.md)
            .padding(.vertical, PortfolixSpacing.sm)
            .background {
                RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                    .fill(isPrimary ? AnyShapeStyle(PortfolixTheme.purpleGradient) : AnyShapeStyle(.regularMaterial))
                if !isPrimary {
                    RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                        .fill(PortfolixTheme.panelSoft.opacity(isHovering ? 0.54 : 0.38))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                    .stroke(
                        isPrimary ? Color.white.opacity(0.16) : PortfolixTheme.border.opacity(0.84),
                        lineWidth: 1
                    )
            }
            .opacity(configuration.isPressed ? 0.72 : isHovering ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

func formatMoney(_ value: Decimal, currency: DisplayCurrency, maximumFractionDigits: Int = 2) -> String {
    formattedMoney(value, currency: currency, maximumFractionDigits: maximumFractionDigits, separatesSymbol: false)
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
