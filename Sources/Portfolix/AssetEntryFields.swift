import SwiftUI

enum AssetEntryLayout {
    static let valueFieldWidth: CGFloat = 320
    static let valueFieldHeight: CGFloat = 28
    static let minimumRowHeight: CGFloat = 36
    static let inlineControlHeight = PortfolixLayout.glassControlHeight
}

struct AssetAdditionCopy {
    let isExistingAsset: Bool
    let isCash: Bool
    let language: AppLanguage

    var quantityTitle: String {
        if isCash { return text(isExistingAsset ? "增持金额" : "现金金额", isExistingAsset ? "Additional Amount" : "Cash Amount") }
        return text(isExistingAsset ? "增持份额" : "资产份额", isExistingAsset ? "Additional Units" : "Asset Quantity")
    }

    var quantityPlaceholder: String {
        if isCash { return text(isExistingAsset ? "填写本次增持的金额" : "填写现金金额", isExistingAsset ? "Enter the amount to add" : "Enter cash amount") }
        return text(isExistingAsset ? "填写本次增持的份额" : "填写资产份额", isExistingAsset ? "Enter the units to add" : "Enter asset quantity")
    }

    func costTitle(mode: CostEntryMode) -> String {
        if mode == .totalCost {
            return text(isExistingAsset ? "增持成本（不含手续费）" : "资产成本（不含手续费）", isExistingAsset ? "Added Cost (Before Fees)" : "Asset Cost (Before Fees)")
        }
        return text(isExistingAsset ? "增持成本价" : "资产成本价", isExistingAsset ? "Additional Unit Cost" : "Asset Unit Cost")
    }

    func costPlaceholder(mode: CostEntryMode) -> String {
        if mode == .totalCost {
            return text(isExistingAsset ? "填写本次增持总成本" : "填写资产总成本", isExistingAsset ? "Enter the cost of the added units" : "Enter total asset cost")
        }
        return text(isExistingAsset ? "填写本次增持成本价" : "填写资产成本价", isExistingAsset ? "Enter cost per added unit" : "Enter asset unit cost")
    }

    var totalCostTitle: String {
        text(isExistingAsset ? "本次增持成本（含手续费）" : "资产成本（含手续费）", isExistingAsset ? "Added Cost Including Fees" : "Asset Cost Including Fees")
    }

    var externalFundsTitle: String {
        text(isExistingAsset ? "外部增持" : "外部资金", "External Funds")
    }

    var resultingQuantityTitle: String {
        if isCash { return text(isExistingAsset ? "增持后现金余额" : "添加后现金余额", "Cash After Addition") }
        return text(isExistingAsset ? "增持后份额" : "添加后份额", "Quantity After Addition")
    }

    private func text(_ chinese: String, _ english: String) -> String { localizedText(chinese, english, language: language) }
}

struct AssetEntryTextField<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    let field: Field
    let focus: FocusState<Field?>.Binding
    let placeholder: String
    let language: AppLanguage
    var numeric = false
    var isInvalid = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if focus.wrappedValue != field, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(PortfolixTypography.body)
                    .foregroundStyle(isInvalid ? PortfolixTheme.danger : PortfolixTheme.tertiaryText)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text)
                .accessibilityLabel(title)
                .textFieldStyle(.plain)
                .font(PortfolixTypography.body)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isInvalid ? PortfolixTheme.danger : PortfolixTheme.primaryText)
                .focused(focus, equals: field)
                .frame(height: AssetEntryLayout.valueFieldHeight, alignment: .center)
                .holdingVoiceInput(text: $text, isFocused: focus.wrappedValue == field,
                    numeric: numeric, language: language, appearance: .waveformOnly)
        }
        .frame(height: AssetEntryLayout.valueFieldHeight)
    }
}

struct AssetEntryFieldLabel: View {
    let title: String
    let isInvalid: Bool
    var showsRequiredIndicator = true

    var body: some View {
        HStack(spacing: PortfolixSpacing.xs) {
            Text(title)
            if showsRequiredIndicator {
                Text("·")
                    .font(.system(size: 22, weight: .heavy))
                    .baselineOffset(1)
                    .foregroundStyle(isInvalid ? PortfolixTheme.danger : PortfolixTheme.lilac)
                    .accessibilityHidden(true)
            }
        }
    }
}
