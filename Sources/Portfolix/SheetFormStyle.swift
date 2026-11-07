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
                .foregroundStyle(PortfolixTheme.primaryText)
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
                                    .foregroundStyle(PortfolixTheme.secondaryText)
                            }
                        }
                        VStack(spacing: 0) {
                            ForEach(section.content) { row in
                                row
                                    .padding(.horizontal, PortfolixSpacing.md)
                                    .frame(minHeight: SheetFormLayout.minimumRowHeight)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if row.id != section.content.last?.id {
                                    Divider().padding(.horizontal, PortfolixSpacing.md)
                                }
                            }
                        }
                        .background(PortfolixTheme.panel, in: RoundedRectangle(cornerRadius: PortfolixRadius.card))
                        if !section.footer.isEmpty {
                            ForEach(section.footer) { footer in
                                footer.font(PortfolixTypography.caption)
                                    .foregroundStyle(PortfolixTheme.secondaryText)
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
            .environment(\.portfolixFormGlass, true)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .environment(\.defaultMinListRowHeight, SheetFormLayout.minimumRowHeight)
    }
}
