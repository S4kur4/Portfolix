import SwiftUI

enum SheetFormLayout {
    static let rowContentHeight: CGFloat = 28
    static let minimumRowHeight: CGFloat = 42
}

struct SheetFormRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.md) {
            configuration.label
                .font(PortfolixTypography.body)
                .foregroundStyle(PortfolixTheme.text)
            Spacer(minLength: PortfolixSpacing.md)
            configuration.content
                .font(PortfolixTypography.body)
                .multilineTextAlignment(.trailing)
        }
        .frame(height: SheetFormLayout.rowContentHeight, alignment: .center)
    }
}

private struct CompactSheetFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                ForEach(sections: configuration.content) { section in
                    VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                        if !section.header.isEmpty {
                            ForEach(section.header) { header in
                                header.font(PortfolixTypography.captionEmphasis)
                                    .foregroundStyle(PortfolixTheme.secondary)
                            }
                        }
                        let cardShape = RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                        VStack(spacing: 0) {
                            ForEach(section.content) { row in
                                row
                                    .padding(.horizontal, PortfolixSpacing.md)
                                    .frame(minHeight: SheetFormLayout.minimumRowHeight)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if row.id != section.content.last?.id {
                                    Divider()
                                        .overlay(PortfolixTheme.border)
                                        .padding(.horizontal, PortfolixSpacing.md)
                                }
                            }
                        }
                        .background {
                            cardShape
                                .fill(PortfolixTheme.surface)
                                .shadow(color: PortfolixTheme.cardShadow, radius: 1.5, x: 0, y: 0.5)
                        }
                        .overlay {
                            cardShape
                                .strokeBorder(PortfolixTheme.cardBorder, lineWidth: 0.5)
                                .allowsHitTesting(false)
                        }
                        if !section.footer.isEmpty {
                            ForEach(section.footer) { footer in
                                footer.font(PortfolixTypography.caption)
                                    .foregroundStyle(PortfolixTheme.secondary)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, PortfolixSpacing.md)
                            }
                        }
                    }
                }
            }
            .padding(PortfolixSpacing.xl)
        }
    }
}

extension View {
    func portfolixSheetForm() -> some View {
        self
            .formStyle(CompactSheetFormStyle())
            .labeledContentStyle(SheetFormRowStyle())
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .environment(\.defaultMinListRowHeight, SheetFormLayout.minimumRowHeight)
    }
}
