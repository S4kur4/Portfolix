import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var displayedSelection: SidebarSection = .overview

    var body: some View {
        ZStack {
            PortfolixSidebarBackground()

            VStack(alignment: .leading, spacing: PortfolixSpacing.lg) {
                BrandMark()
                    .padding(.top, 16)
                    .padding(.horizontal, 14)

                VStack(spacing: PortfolixSpacing.xs) {
                    ForEach(SidebarSection.allCases) { item in
                        SidebarItem(
                            item: item,
                            title: item.title(language: store.appLanguage),
                            isSelected: displayedSelection == item
                        ) {
                            select(item)
                        }
                    }
                }
                .padding(.horizontal, PortfolixSpacing.sm)

                Spacer()

                SidebarVersion()
                    .padding(.horizontal, PortfolixSpacing.xl)
                    .padding(.bottom, PortfolixSpacing.lg)
            }
        }
        .onAppear {
            displayedSelection = store.selection
        }
        .onChange(of: store.selection) { _, selection in
            displayedSelection = selection
        }
    }

    private func select(_ item: SidebarSection) {
        guard displayedSelection != item else { return }
        displayedSelection = item
        DispatchQueue.main.async {
            guard store.selection != item else { return }
            store.selection = item
        }
    }
}

private struct SidebarVersion: View {
    private var version: String {
        normalizedBundleValue(for: "CFBundleShortVersionString") ?? "0.1.0"
    }

    private var build: String {
        normalizedBundleValue(for: "CFBundleVersion") ?? "6"
    }

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))

            Text("v\(version) (\(build))")
        }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(PortfolixTheme.secondaryText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .padding(.top, PortfolixSpacing.sm)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(PortfolixTheme.border)
                    .frame(height: 1)
            }
    }

    private func normalizedBundleValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct BrandMark: View {
    var body: some View {
        HStack(spacing: PortfolixSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PortfolixTheme.purpleGradient)
                    .frame(width: 34, height: 34)

                PortfolixBrandGlyph(size: 24)
            }

            Text("Portfolix")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PortfolixTheme.primaryText)
        }
    }
}

private struct SidebarItem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: SidebarSection
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PortfolixSpacing.md) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Spacer()
            }
            .foregroundStyle(isSelected ? Color(hex: 0x171025) : PortfolixTheme.secondaryText)
            .padding(.horizontal, PortfolixSpacing.md)
            .padding(.vertical, PortfolixSpacing.md)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(PortfolixTheme.purpleGradient)
                        .opacity(isSelected ? 1 : 0)

                    RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                        .fill(PortfolixTheme.panelSoft)
                        .opacity(!isSelected && isHovering ? 1 : 0)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
}
