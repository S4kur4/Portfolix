import SwiftUI

struct SheetNotice: Equatable {
    enum Kind: Equatable { case error, warning, information, progress, success }
    let message: String
    let kind: Kind

    var singleLineMessage: String {
        message.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    var symbol: String {
        switch kind {
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .information: "info.circle"
        case .progress: "clock.arrow.circlepath"
        case .success: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch kind {
        case .error: PortfolixTheme.danger
        case .warning: PortfolixTheme.amber
        case .information: PortfolixTheme.secondaryText
        case .progress: PortfolixTheme.lilac
        case .success: PortfolixTheme.mint
        }
    }
}

struct SheetActionFooter<Leading: View, Actions: View>: View {
    let errorMessage: String?
    let notices: [SheetNotice]
    let leading: Leading
    let actions: Actions

    init(errorMessage: String?, notices: [SheetNotice] = [], @ViewBuilder leading: () -> Leading, @ViewBuilder actions: () -> Actions) {
        self.errorMessage = errorMessage
        self.notices = notices
        self.leading = leading()
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.md) {
            HStack(alignment: .top, spacing: 0) {
                if let notice = displayedNotices.first {
                    HStack(spacing: PortfolixSpacing.sm) {
                        Image(systemName: notice.symbol)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        ViewThatFits(in: .horizontal) {
                            Text(notice.singleLineMessage).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            Text(notice.singleLineMessage)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .portfolixHelp(notice.message)
                        }
                    }
                    .font(PortfolixTypography.captionEmphasis)
                    .foregroundStyle(notice.color)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(notice.kind == .error ? "sheet-action-error" : "sheet-action-notice")
                } else {
                    leading
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: PortfolixSpacing.sm) { actions }
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(PortfolixSpacing.xl)
    }

    var displayedNotices: [SheetNotice] {
        if let errorMessage, !errorMessage.isEmpty { return [.init(message: errorMessage, kind: .error)] }
        return notices.last(where: { !$0.message.isEmpty }).map { [$0] } ?? []
    }
}

extension SheetActionFooter where Leading == EmptyView {
    init(errorMessage: String?, notices: [SheetNotice] = [], @ViewBuilder actions: () -> Actions) {
        self.init(errorMessage: errorMessage, notices: notices, leading: { EmptyView() }, actions: actions)
    }
}
