import SwiftUI

struct PositionClosureSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let position: Position
    @State private var isDatePickerPresented = false
    @State private var draft: PositionClosureDraft
    @State private var tradeDate = Date()
    @State private var cashSelection = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?
    private enum Field { case price, fees, proceeds }

    init(position: Position) {
        self.position = position
        _draft = State(initialValue: PositionClosureDraft(position: position))
    }

    private var language: AppLanguage { store.appLanguage }
    private var cashOptions: [Position] {
        store.positions.filter { $0.category == .cash && $0.quoteCurrency == position.quoteCurrency }
    }
    private var cashOptionIDs: [String] {
        (cashOptions.contains { $0.symbol == position.quoteCurrency.rawValue } ? [] : [""])
            + cashOptions.map { $0.id.uuidString }
    }
    private var settlement: PositionClosureSettlement? { try? draft.settlement() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: text("清仓记账", "Close Position"), symbol: "arrow.down.right.circle")
            Divider().overlay(PortfolixTheme.border)
            Form {
                Section {
                    LabeledContent(text("资产", "Asset")) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(position.name).foregroundStyle(PortfolixTheme.primaryText)
                            Text("\(position.symbol) · \(position.quoteCurrency.rawValue)")
                                .font(PortfolixTypography.caption).foregroundStyle(PortfolixTheme.secondaryText)
                        }
                    }
                    LabeledContent(text("清仓数量", "Quantity"), value: PositionClosureMath.string(position.quantity))
                    LabeledContent(text("成交日期", "Trade Date")) {
                        PortfolixDateTimePicker(title: text("成交日期", "Trade Date"), selection: $tradeDate,
                            language: store.appLanguage, includesTime: false, isPresented: $isDatePickerPresented)
                    }
                }
                Section {
                    amountField(text("成交均价", "Average Sale Price"), field: .price,
                        binding: Binding(get: { draft.priceText }, set: { draft.setPrice($0) }))
                    amountField(text("手续费", "Fees"), field: .fees,
                        binding: Binding(get: { draft.feesText }, set: { draft.setFees($0) }))
                    amountField(text("实际到账金额", "Net Proceeds"), field: .proceeds,
                        binding: Binding(get: { draft.proceedsText }, set: { draft.setProceeds($0) }))
                    LabeledContent(text("参考报价", "Reference Quote")) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(formatMoney(position.latestPrice, currency: position.quoteCurrency))
                            Text(position.quoteTime).font(PortfolixTypography.caption)
                        }
                        .foregroundStyle(PortfolixTheme.secondaryText)
                    }
                }
                Section {
                    LabeledContent(text("资金去向", "Deposit To")) {
                        PortfolixGlassMenuPicker(title: text("资金去向", "Deposit To"), selection: $cashSelection,
                            options: cashOptionIDs, optionTitle: { id in
                                cashOptions.first { $0.id.uuidString == id }?.name
                                    ?? text("新建 \(position.quoteCurrency.rawValue) 现金", "New \(position.quoteCurrency.rawValue) Cash")
                            })
                    }
                    LabeledContent(text("入账后现金余额", "Cash After Deposit")) {
                        let balance = cashOptions.first { $0.id.uuidString == cashSelection }?.quantity ?? 0
                        Text(settlement.map { formatMoney(balance + $0.netProceeds, currency: position.quoteCurrency) } ?? "—").monospacedDigit()
                    }
                    LabeledContent(text("已实现盈亏", "Realized P&L")) {
                        let profit = (settlement?.netProceeds ?? 0) - position.totalCost
                        Text(settlement == nil ? "—" : formatSignedMoney(profit, currency: position.quoteCurrency))
                            .foregroundStyle(PortfolixTheme.performanceColor(for: profit, scheme: store.performanceColorScheme))
                            .monospacedDigit()
                    }
                }
            }
            .portfolixSheetForm()
            .foregroundStyle(PortfolixTheme.primaryText)
            Divider().overlay(PortfolixTheme.border)
            SheetActionFooter(errorMessage: errorMessage) {
                Button(text("取消", "Cancel")) { dismiss() }
                    .buttonStyle(QuietButtonStyle()).keyboardShortcut(isDatePickerPresented ? nil : .cancelAction)
                Button(text("确认清仓", "Record Closure"), action: save)
                    .buttonStyle(PrimaryButtonStyle()).disabled(isSaving)
            }
        }
        .interactiveDismissDisabled(isDatePickerPresented)
        .frame(width: 600, height: 660)
        .background { PortfolixSheetBackground() }
        .onAppear { cashSelection = cashOptions.first?.id.uuidString ?? "" }
    }

    private func amountField(_ title: String, field: Field, binding: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack(spacing: PortfolixSpacing.sm) {
                TextField("0", text: binding)
                    .labelsHidden().accessibilityLabel(title)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).monospacedDigit()
                    .focused($focusedField, equals: field)
                    .holdingVoiceInput(text: binding, isFocused: focusedField == field, numeric: true,
                        language: language, appearance: .waveformOnly)
                Text(position.quoteCurrency.rawValue).foregroundStyle(PortfolixTheme.secondaryText)
            }
            .frame(width: 280, height: 28)
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try store.closePosition(position, settlement: draft.settlement(), tradeDate: tradeDate,
                cashPositionID: UUID(uuidString: cashSelection))
            dismiss()
        } catch {
            errorMessage = (error as? PositionClosureError)?.message(language: language) ?? error.localizedDescription
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: language)
    }
}

struct PositionClosureDetailSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: PositionClosureRecord
    @State private var errorMessage: String?
    @State private var confirmsReversal = false

    private var canReverse: Bool {
        guard !record.isReversed, let date = ISO8601DateFormatter().date(from: record.recordedAt) else { return false }
        return Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: text("清仓记录", "Position Closure"), symbol: "checkmark.circle")
            Divider().overlay(PortfolixTheme.border)
            Form {
                Section {
                    LabeledContent(text("资产", "Asset"), value: record.holding.name)
                    LabeledContent(text("资产代码", "Symbol"), value: record.holding.symbol)
                    LabeledContent(text("记录时间", "Record Time"), value: PositionTransactionRow(record).recordedTimeText)
                    LabeledContent(text("清仓数量", "Quantity"), value: record.holding.quantity)
                    LabeledContent(text("成交均价", "Average Sale Price"), value: money(record.executionPrice))
                    LabeledContent(text("手续费", "Fees"), value: money(record.fees))
                    LabeledContent(text("实际到账金额", "Net Proceeds"), value: money(record.netProceeds))
                    LabeledContent(text("资金去向", "Deposit To"), value: record.cashName)
                    LabeledContent(text("已实现盈亏", "Realized P&L")) {
                        Text(formatSignedMoney(record.realizedProfit, currency: record.currency))
                            .foregroundStyle(PortfolixTheme.performanceColor(for: record.realizedProfit, scheme: store.performanceColorScheme))
                    }
                }
            }
            .portfolixSheetForm()
            Divider().overlay(PortfolixTheme.border)
            SheetActionFooter(errorMessage: errorMessage) {
                if canReverse {
                    Button(text("撤销记录", "Reverse Record")) { confirmsReversal = true }
                        .buttonStyle(QuietButtonStyle())
                }
                Button(text("完成", "Done")) { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: 540, height: 610)
        .background { PortfolixSheetBackground() }
        .alert(text("撤销这条记录？", "Reverse this record?"), isPresented: $confirmsReversal) {
            Button(text("取消", "Cancel"), role: .cancel) {}
            Button(text("撤销记录", "Reverse Record")) {
                do { try store.reversePositionClosure(record); dismiss() }
                catch { errorMessage = (error as? PositionClosureError)?.message(language: store.appLanguage) ?? error.localizedDescription }
            }
        } message: {
            Text(text("将恢复持仓，并从现金余额中扣回这笔到账金额。", "The holding will be restored and its proceeds deducted from cash."))
        }
    }

    private func money(_ value: String) -> String { formatMoney(PositionClosureMath.decimal(value) ?? 0, currency: record.currency) }
    private func text(_ chinese: String, _ english: String) -> String { localizedText(chinese, english, language: store.appLanguage) }
}
