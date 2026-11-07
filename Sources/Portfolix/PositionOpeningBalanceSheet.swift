import AppKit
import SwiftUI

struct PositionOpeningBalanceSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: PositionOpeningBalanceRecord
    @State private var quantity: String
    @State private var totalCost: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?
    private enum Field { case quantity, cost }

    init(record: PositionOpeningBalanceRecord) {
        self.record = record
        _quantity = State(initialValue: record.quantity ?? "")
        _totalCost = State(initialValue: record.totalCost ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: text("核对期初持仓", "Review Opening Balance"), symbol: "tray.full")
            Divider().overlay(PortfolixTheme.border)
            Form {
                Section {
                    LabeledContent(text("资产", "Asset"), value: record.holding.name)
                    LabeledContent(text("计价币种", "Quote Currency"), value: record.currency.rawValue)
                }
                Section {
                    LabeledContent(text("期初份额", "Opening Quantity")) {
                        field(.quantity, title: text("期初份额", "Opening Quantity"), value: $quantity)
                    }
                    LabeledContent(text("期初总成本", "Opening Total Cost")) {
                        field(.cost, title: text("期初总成本", "Opening Total Cost"), value: $totalCost)
                    }
                }
            }
            .portfolixSheetForm()
            .disabled(isSaving)
            Divider().overlay(PortfolixTheme.border)
            SheetActionFooter(errorMessage: errorMessage) {
                Button(text("取消", "Cancel")) { dismiss() }
                    .buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button(text("确认期初", "Confirm Opening")) {
                    let window = NSApp.keyWindow
                    Task { await save(in: window) }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(isSaving)
            }
        }
        .frame(width: 620, height: 400)
        .background(PortfolixTheme.canvas)
        .interactiveDismissDisabled(isSaving)
    }

    private func field(_ field: Field, title: String, value: Binding<String>) -> some View {
        AssetEntryTextField(title: title, text: value, field: field, focus: $focusedField,
            placeholder: text("填写核对后的金额或份额", "Enter the verified amount or quantity"),
            language: store.appLanguage, numeric: true)
            .frame(width: AssetEntryLayout.valueFieldWidth)
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
            guard let units = PositionClosureMath.decimal(quantity), units >= 0,
                  let cost = PositionClosureMath.decimal(totalCost), cost >= 0 else { throw PositionOpeningBalanceError.invalidInput }
            try store.confirmOpeningBalance(record, quantity: units, totalCost: cost)
            dismiss()
        } catch {
            errorMessage = (error as? PositionOpeningBalanceError)?.message(language: store.appLanguage) ?? error.localizedDescription
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}

struct PositionOpeningBalanceDetailSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: PositionOpeningBalanceRecord

    private func text(_ cn: String, _ en: String) -> String {
        localizedText(cn, en, language: store.appLanguage)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: text("期初持仓", "Opening Balance"), symbol: "tray.full")
            Divider().overlay(PortfolixTheme.border)
            Form {
                Section {
                    LabeledContent(text("资产", "Asset"), value: record.holding.name)
                    LabeledContent(text("资产代码", "Symbol"), value: record.holding.symbol)
                    LabeledContent(text("记录时间", "Record Time"), value: PositionTransactionRow(record).recordedTimeText)
                    LabeledContent(text("计价币种", "Currency"), value: record.currency.rawValue)
                    LabeledContent(text("期初份额", "Opening Quantity"), value: record.requiresReview ? "—" : record.quantity ?? "—")
                    LabeledContent(text("期初总成本", "Opening Total Cost"), value: record.requiresReview ? "—" : record.cost.map { formatMoney($0, currency: record.currency) } ?? "—")
                }
            }.portfolixSheetForm()
            Divider().overlay(PortfolixTheme.border)
            SheetActionFooter(errorMessage: nil) {
                Button(text("完成", "Done")) { dismiss() }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: 620, height: 440)
        .background(PortfolixTheme.canvas)
    }
}
