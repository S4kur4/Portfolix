import SwiftUI

struct BatchPositionUpdateSheet: View {
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [PositionUpdateDraft]
    @State private var didAttemptSave = false
    @State private var saveErrorMessage: String?

    init(positions: [Position]) {
        _drafts = State(initialValue: positions.map(PositionUpdateDraft.init))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: text("更新持仓", "Update Holdings"),
                symbol: "square.and.pencil"
            )

            Divider().overlay(PortfolixTheme.border)

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    PositionUpdateTableHeader(language: store.appLanguage)

                    Divider().overlay(PortfolixTheme.border)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach($drafts) { $draft in
                                PositionUpdateRow(
                                    draft: $draft,
                                    language: store.appLanguage,
                                    highlightsInvalidFields: didAttemptSave
                                )

                                if draft.id != drafts.last?.id {
                                    Divider()
                                        .overlay(PortfolixTheme.border)
                                        .padding(.leading, PortfolixSpacing.lg)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, PortfolixSpacing.xl)
            .padding(.vertical, PortfolixSpacing.xl)

            Divider().overlay(PortfolixTheme.border)

            HStack(spacing: PortfolixSpacing.sm) {
                Text(pendingUpdateText)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.secondaryText)
                    .monospacedDigit()

                Spacer()

                Button(text("取消", "Cancel")) {
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(text("保存更新", "Save Updates")) {
                    saveUpdates()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!hasEditedInput)
                .keyboardShortcut(.defaultAction)
            }
            .padding(PortfolixSpacing.xl)
        }
        .frame(width: PositionUpdateLayout.sheetWidth, height: 640)
        .background {
            PortfolixSheetBackground()
        }
        .alert(text("无法更新持仓", "Unable to update holdings"), isPresented: errorAlertPresented) {
            Button(text("好", "OK"), role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? text("请稍后重试", "Please try again later"))
        }
    }

    private var pendingUpdates: [PositionBalanceUpdate] {
        drafts.compactMap(\.balanceUpdate)
    }

    private var hasEditedInput: Bool {
        drafts.contains(where: \.hasEditedInput)
    }

    private var pendingUpdateText: String {
        let count = pendingUpdates.count
        if store.appLanguage == .english {
            return count == 1 ? "1 holding changed" : "\(count) holdings changed"
        }
        return "\(count) 项待更新"
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private func saveUpdates() {
        didAttemptSave = true
        guard drafts.allSatisfy(\.isValid), !pendingUpdates.isEmpty else { return }

        do {
            try store.updatePositionBalances(pendingUpdates)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}

private struct PositionUpdateTableHeader: View {
    let language: AppLanguage

    var body: some View {
        HStack(spacing: PositionUpdateLayout.columnSpacing) {
            header(text("资产", "Asset"), width: PositionUpdateLayout.assetWidth, alignment: .leading)
            header(text("当前份额", "Current Quantity"), width: PositionUpdateLayout.currentQuantityWidth)
            header(text("最新份额", "New Quantity"), width: PositionUpdateLayout.inputWidth)
            header(text("当前成本价", "Current Cost"), width: PositionUpdateLayout.currentCostWidth)
            header(text("最新成本价", "New Cost"), width: PositionUpdateLayout.inputWidth)
            header(text("持仓总成本", "Total Cost"), width: PositionUpdateLayout.totalCostWidth)
        }
        .padding(.horizontal, PortfolixSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: PositionUpdateLayout.headerHeight, alignment: .leading)
        .background(PortfolixTheme.panelElevated)
    }

    private func header(
        _ title: String,
        width: CGFloat,
        alignment: Alignment = .leading
    ) -> some View {
        Text(title)
            .font(PortfolixTypography.captionEmphasis)
            .foregroundStyle(PortfolixTheme.secondaryText)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: language)
    }
}

private struct PositionUpdateRow: View {
    @Binding var draft: PositionUpdateDraft
    let language: AppLanguage
    let highlightsInvalidFields: Bool

    var body: some View {
        HStack(spacing: PositionUpdateLayout.columnSpacing) {
            assetCell
                .frame(width: PositionUpdateLayout.assetWidth, alignment: .leading)

            readOnlyNumber(decimalEntryString(draft.position.quantity))
                .frame(width: PositionUpdateLayout.currentQuantityWidth, alignment: .leading)

            numericField(
                text: quantityBinding,
                field: .quantity,
                placeholder: text("填写最新份额", "Enter quantity")
            )
            .frame(width: PositionUpdateLayout.inputWidth)

            readOnlyNumber(formatMoney(draft.position.averageCost, currency: draft.position.quoteCurrency))
                .frame(width: PositionUpdateLayout.currentCostWidth, alignment: .leading)

            numericField(
                text: averageCostBinding,
                field: .averageCost,
                placeholder: text("填写最新成本", "Enter cost"),
                isDisabled: draft.isCash
            )
            .frame(width: PositionUpdateLayout.inputWidth)

            numericField(
                text: totalCostBinding,
                field: .totalCost,
                placeholder: text("填写总成本", "Enter total cost"),
                isDisabled: draft.isCash
            )
            .frame(width: PositionUpdateLayout.totalCostWidth)
        }
        .padding(.horizontal, PortfolixSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: PositionUpdateLayout.rowHeight, alignment: .leading)
        .background(draft.isChanged ? PortfolixTheme.selectionFill.opacity(0.34) : Color.clear)
    }

    private var assetCell: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Circle()
                .fill(draft.position.category.color)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(draft.position.name)
                    .font(PortfolixTypography.body)
                    .foregroundStyle(PortfolixTheme.primaryText)
                    .lineLimit(1)

                Text("\(draft.position.symbol) · \(draft.position.quoteCurrency.rawValue)")
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiaryText)
                    .lineLimit(1)
            }
        }
    }

    private func readOnlyNumber(_ value: String) -> some View {
        Text(value)
            .font(PortfolixTypography.body)
            .foregroundStyle(PortfolixTheme.secondaryText)
            .lineLimit(1)
            .monospacedDigit()
    }

    private func numericField(
        text: Binding<String>,
        field: PositionUpdateField,
        placeholder: String,
        isDisabled: Bool = false
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(PortfolixTypography.body)
            .foregroundStyle(isDisabled ? PortfolixTheme.secondaryText : PortfolixTheme.primaryText)
            .multilineTextAlignment(.leading)
            .monospacedDigit()
            .padding(.horizontal, PortfolixSpacing.sm)
            .frame(height: PositionUpdateLayout.inputHeight)
            .background {
                RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                    .fill(isDisabled ? PortfolixTheme.panelSoft.opacity(0.5) : PortfolixTheme.panelElevated)
            }
            .overlay {
                RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                    .stroke(
                        highlightsInvalidFields && !draft.isValid(field)
                            ? PortfolixTheme.danger
                            : PortfolixTheme.border,
                        lineWidth: 1
                    )
            }
            .disabled(isDisabled)
            .accessibilityLabel("\(draft.position.name) \(field.title(language: language))")
    }

    private var quantityBinding: Binding<String> {
        Binding(
            get: { draft.quantityText },
            set: { draft.setQuantityText($0) }
        )
    }

    private var averageCostBinding: Binding<String> {
        Binding(
            get: { draft.averageCostText },
            set: { draft.setAverageCostText($0) }
        )
    }

    private var totalCostBinding: Binding<String> {
        Binding(
            get: { draft.totalCostText },
            set: { draft.setTotalCostText($0) }
        )
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: language)
    }
}

private struct PositionUpdateDraft: Identifiable {
    let position: Position
    var quantityText: String
    var averageCostText: String
    var totalCostText: String

    var id: Position.ID { position.id }
    var isCash: Bool { position.category == .cash }

    init(position: Position) {
        self.position = position
        quantityText = decimalEntryString(position.quantity)
        averageCostText = decimalEntryString(position.averageCost)
        totalCostText = decimalEntryString(position.totalCost)
    }

    var isValid: Bool {
        isValid(.quantity) && isValid(.averageCost) && isValid(.totalCost)
    }

    var hasEditedInput: Bool {
        quantityText != decimalEntryString(position.quantity)
            || averageCostText != decimalEntryString(position.averageCost)
            || totalCostText != decimalEntryString(position.totalCost)
    }

    var isChanged: Bool {
        guard let update = balanceUpdate else { return false }
        return update.quantity != position.quantity || update.totalCost != position.totalCost
    }

    var balanceUpdate: PositionBalanceUpdate? {
        guard
            let quantity = parsedDecimal(quantityText),
            quantity > 0,
            let totalCost = parsedDecimal(totalCostText),
            totalCost >= 0,
            isValid
        else { return nil }

        let resolvedTotalCost = isCash ? quantity : totalCost
        guard quantity != position.quantity || resolvedTotalCost != position.totalCost else { return nil }
        return PositionBalanceUpdate(
            positionID: position.id,
            quantity: quantity,
            totalCost: resolvedTotalCost
        )
    }

    mutating func setQuantityText(_ value: String) {
        quantityText = value
        guard let quantity = parsedDecimal(value), quantity > 0 else { return }
        if isCash {
            averageCostText = "1"
            totalCostText = decimalEntryString(quantity)
        } else if let averageCost = parsedDecimal(averageCostText), averageCost >= 0 {
            totalCostText = decimalEntryString(quantity * averageCost)
        }
    }

    mutating func setAverageCostText(_ value: String) {
        guard !isCash else { return }
        averageCostText = value
        guard
            let quantity = parsedDecimal(quantityText),
            quantity > 0,
            let averageCost = parsedDecimal(value),
            averageCost >= 0
        else { return }
        totalCostText = decimalEntryString(quantity * averageCost)
    }

    mutating func setTotalCostText(_ value: String) {
        guard !isCash else { return }
        totalCostText = value
        guard
            let quantity = parsedDecimal(quantityText),
            quantity > 0,
            let totalCost = parsedDecimal(value),
            totalCost >= 0
        else { return }
        averageCostText = decimalEntryString(roundedDecimal(totalCost / quantity, scale: 12))
    }

    func isValid(_ field: PositionUpdateField) -> Bool {
        switch field {
        case .quantity:
            parsedDecimal(quantityText).map { !$0.isNaN && $0 > 0 } == true
        case .averageCost:
            isCash || parsedDecimal(averageCostText).map { !$0.isNaN && $0 >= 0 } == true
        case .totalCost:
            isCash || parsedDecimal(totalCostText).map { !$0.isNaN && $0 >= 0 } == true
        }
    }
}

private enum PositionUpdateField: Hashable {
    case quantity
    case averageCost
    case totalCost

    func title(language: AppLanguage) -> String {
        switch self {
        case .quantity:
            localizedText("最新份额", "New Quantity", language: language)
        case .averageCost:
            localizedText("最新成本价", "New Cost", language: language)
        case .totalCost:
            localizedText("持仓总成本", "Total Cost", language: language)
        }
    }
}

private enum PositionUpdateLayout {
    static let assetWidth: CGFloat = 188
    static let currentQuantityWidth: CGFloat = 100
    static let currentCostWidth: CGFloat = 104
    static let inputWidth: CGFloat = 116
    static let totalCostWidth: CGFloat = 132
    static let columnSpacing: CGFloat = PortfolixSpacing.md
    static let tableWidth: CGFloat = assetWidth
        + currentQuantityWidth
        + inputWidth
        + currentCostWidth
        + inputWidth
        + totalCostWidth
        + columnSpacing * 5
        + PortfolixSpacing.lg * 2
    static let sheetWidth: CGFloat = tableWidth + PortfolixSpacing.xl * 2
    static let headerHeight: CGFloat = 40
    static let rowHeight: CGFloat = 56
    static let inputHeight: CGFloat = 32
}

private func parsedDecimal(_ value: String) -> Decimal? {
    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: "，", with: "")
    guard !normalized.isEmpty else { return nil }
    return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
}

private func decimalEntryString(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

private func roundedDecimal(_ value: Decimal, scale: Int16) -> Decimal {
    var input = value
    var output = Decimal()
    NSDecimalRound(&output, &input, Int(scale), .bankers)
    return output
}
