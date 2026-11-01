import AppKit
import SwiftUI

enum CashReductionInput {
    static func amount(_ text: String, available: Decimal) throws -> Decimal {
        guard let amount = PositionClosureMath.decimal(text), amount > 0 else { throw PositionTradeError.invalidCashReduction }
        guard amount <= available else { throw PositionTradeError.insufficientCash }
        return amount
    }
}

struct CashReductionSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let position: Position
    @State private var accountID: UUID
    @State private var amount = "0"
    @State private var errorMessage: String?
    @State private var didAttemptSave = false
    @State private var isSaving = false
    @State private var recordID = UUID()
    @FocusState private var focusedField: Field?
    private enum Field { case amount }

    init(position: Position) {
        self.position = position
        _accountID = State(initialValue: position.id)
    }

    private var cash: Position { store.positions.first { $0.id == accountID } ?? position }
    private var invalidAmount: Bool { didAttemptSave && (try? CashReductionInput.amount(amount, available: cash.quantity)) == nil }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: text("减少现金", "Reduce Cash"), symbol: "minus.circle")
            Divider().overlay(PortfolixTheme.border)
            Form {
                Section {
                    LabeledContent(text("现金资产", "Cash Asset")) {
                        PortfolixGlassMenuPicker(title: text("现金资产", "Cash Asset"), selection: $accountID,
                            options: store.positions.filter { $0.category == .cash }.map(\.id),
                            optionTitle: { id in store.positions.first { $0.id == id }?.name ?? "—" })
                    }
                    LabeledContent(text("当前余额", "Current Balance"), value: formatMoney(cash.quantity, currency: cash.quoteCurrency))
                    LabeledContent(text("计价币种", "Quote Currency"), value: cash.quoteCurrency.rawValue)
                }
                Section {
                    LabeledContent {
                        HStack(spacing: PortfolixSpacing.sm) {
                            AssetEntryTextField(title: text("减少金额", "Reduction Amount"), text: $amount,
                                field: .amount, focus: $focusedField,
                                placeholder: text("填写减少金额", "Enter the reduction amount"),
                                language: store.appLanguage, numeric: true, isInvalid: invalidAmount)
                            Button { amount = PositionClosureMath.string(cash.quantity) } label: {
                                Text(text("全部减少", "Reduce All"))
                                    .font(PortfolixTypography.captionEmphasis)
                                    .padding(.horizontal, PortfolixSpacing.sm)
                                    .portfolixGlassControl(height: AssetEntryLayout.inlineControlHeight)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: AssetEntryLayout.valueFieldWidth, height: AssetEntryLayout.valueFieldHeight)
                    } label: {
                        AssetEntryFieldLabel(title: text("减少金额", "Reduction Amount"), isInvalid: invalidAmount)
                    }
                    LabeledContent(text("减少后余额", "Remaining Balance")) {
                        let remaining = PositionClosureMath.decimal(amount).flatMap {
                            $0 >= 0 && $0 <= cash.quantity ? cash.quantity - $0 : nil
                        }
                        Text(remaining.map { formatMoney($0, currency: cash.quoteCurrency) } ?? "—").monospacedDigit()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .environment(\.defaultMinListRowHeight, AssetEntryLayout.minimumRowHeight)
            .disabled(isSaving)
            Divider().overlay(PortfolixTheme.border)
            SheetActionFooter(errorMessage: errorMessage) {
                Button(text("取消", "Cancel")) { dismiss() }
                    .buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction).disabled(isSaving)
                Button(text("确认减少", "Record Reduction")) {
                    let window = NSApp.keyWindow
                    Task { await save(in: window) }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(isSaving)
            }
        }
        .frame(width: 620, height: 460)
        .background { PortfolixSheetBackground() }
        .interactiveDismissDisabled(isSaving)
        .onChange(of: accountID) { _, _ in amount = "0"; errorMessage = nil; didAttemptSave = false }
        .onChange(of: amount) { _, _ in errorMessage = nil }
    }

    private func save(in window: NSWindow?) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        focusedField = nil
        guard await SheetEditingCommit.commit(in: window) else {
            errorMessage = text("无法结束当前输入，请检查后重试。", "Unable to finish editing. Check the current field and try again.")
            return
        }
        do {
            let value = try CashReductionInput.amount(amount, available: cash.quantity)
            try store.recordTrade(id: recordID, side: .withdraw, position: cash, quantity: value,
                price: 1, fees: 0, tradeDate: .now, cashPositionID: nil)
            dismiss()
        } catch {
            didAttemptSave = true
            errorMessage = (error as? PositionTradeError)?.message(language: store.appLanguage) ?? error.localizedDescription
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}
