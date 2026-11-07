import AppKit
import SwiftUI

struct PositionTradeSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let position: Position
    @State private var isDatePickerPresented = false
    @State private var draft: PositionTradeDraft
    @State private var cashSelection = ""
    @State private var assetSelection: UUID
    @State private var errorMessage: String?
    @State private var tradeID = UUID()
    @State private var actualTradeDate = Date.now
    @State private var isSaving = false
    @State private var didAttemptSave = false
    @FocusState private var focusedField: Field?
    private enum Field { case quantity, price, fees, amount }

    init(position: Position) {
        self.position = position
        _assetSelection = State(initialValue: position.id)
        _draft = State(initialValue: PositionTradeDraft(side: .sell, position: position))
    }

    private var asset: Position { store.positions.first { $0.id == assetSelection } ?? position }
    private var cashOptions: [Position] { store.positions.filter { $0.category == .cash && $0.quoteCurrency == asset.quoteCurrency } }
    private var cashIDs: [String] {
        (cashOptions.contains { $0.symbol == asset.quoteCurrency.rawValue } ? [] : [""]) + cashOptions.map { $0.id.uuidString }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: text("卖出资产", "Sell Asset"), symbol: "arrow.down.right.circle")
            Divider().overlay(PortfolixTheme.border)
            Form {
                Section {
                    LabeledContent(text("实际操作时间", "Actual Trade Time")) {
                        PortfolixDateTimePicker(title: localizedText("实际操作时间", "Actual Trade Time", language: store.appLanguage), selection: $actualTradeDate, language: store.appLanguage, isPresented: $isDatePickerPresented)
                    }
                    LabeledContent(text("资产", "Asset")) {
                        PortfolixGlassMenuPicker(title: text("资产", "Asset"), selection: $assetSelection,
                            options: store.positions.filter { $0.category != .cash }.map(\.id),
                            optionTitle: { id in store.positions.first { $0.id == id }?.name ?? "—" })
                    }
                    LabeledContent(text("当前份额", "Current Quantity"), value: PositionClosureMath.string(asset.quantity))
                    LabeledContent(text("计价币种", "Quote Currency"), value: asset.quoteCurrency.rawValue)
                }
                Section {
                    LabeledContent {
                        HStack(spacing: PortfolixSpacing.sm) {
                            input(.quantity, title: text("卖出份额", "Sell Quantity"),
                                placeholder: text("填写卖出份额", "Enter sell quantity"),
                                binding: Binding(get: { draft.quantityText }, set: { draft.setQuantity($0) }))
                            Button { draft.setQuantity(PositionClosureMath.string(asset.quantity)) } label: {
                                Text(text("全部卖出", "Sell All"))
                                    .font(PortfolixTypography.captionEmphasis)
                                    .padding(.horizontal, PortfolixSpacing.sm)
                                    .portfolixGlassControl(height: AssetEntryLayout.inlineControlHeight)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: AssetEntryLayout.valueFieldWidth, height: AssetEntryLayout.valueFieldHeight)
                    } label: {
                        AssetEntryFieldLabel(title: text("卖出份额", "Sell Quantity"), isInvalid: invalid(.quantity))
                    }
                    amountField(text("成交均价", "Trade Price"), field: .price, placeholder: text("填写成交均价", "Enter trade price"),
                        binding: Binding(get: { draft.priceText }, set: { draft.setPrice($0) }))
                    amountField(text("手续费", "Fees"), field: .fees, placeholder: text("选填，默认为 0", "Optional, defaults to 0"),
                        binding: Binding(get: { draft.feesText }, set: { draft.setFees($0) }))
                    amountField(text("实际到账", "Net Proceeds"), field: .amount, placeholder: text("填写实际到账金额", "Enter net proceeds"),
                        binding: Binding(get: { draft.amountText }, set: { draft.setAmount($0) }))
                }
                Section {
                    LabeledContent(text("收款账户", "Deposit To")) {
                        PortfolixGlassMenuPicker(title: text("收款账户", "Deposit To"), selection: $cashSelection, options: cashIDs,
                            optionTitle: { id in cashOptions.first { $0.id.uuidString == id }?.name
                                ?? text("新建 \(asset.quoteCurrency.rawValue) 现金", "New \(asset.quoteCurrency.rawValue) Cash") })
                    }
                    LabeledContent(text("卖出后剩余份额", "Remaining Quantity")) {
                        let remaining = PositionClosureMath.decimal(draft.quantityText) == 0 ? asset.quantity
                            : (try? draft.values(availableQuantity: asset.quantity)).map { asset.quantity - $0.quantity }
                        Text(remaining.map(PositionClosureMath.string) ?? "—").monospacedDigit()
                    }
                    LabeledContent(text("预计已实现盈亏", "Estimated Realized P&L")) {
                        let values = try? draft.values(availableQuantity: asset.quantity)
                        let profit = PositionClosureMath.decimal(draft.quantityText) == 0 ? Decimal.zero
                            : values.map { $0.amount - asset.totalCost * $0.quantity / asset.quantity }
                        Text(asset.costIsKnown ? profit.map { formatSignedMoney($0, currency: asset.quoteCurrency) } ?? "—" : "—")
                            .foregroundStyle(PortfolixTheme.performanceColor(for: profit ?? 0, scheme: store.performanceColorScheme)).monospacedDigit()
                    }
                }
            }
            .portfolixSheetForm()
            Divider().overlay(PortfolixTheme.border)
            SheetActionFooter(errorMessage: errorMessage) {
                Button(text("取消", "Cancel")) { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(isDatePickerPresented ? nil : .cancelAction)
                Button(text("确认卖出", "Record Sell")) {
                    let window = NSApp.keyWindow
                    Task { await save(committing: window) }
                }.buttonStyle(PrimaryButtonStyle()).disabled(isSaving)
            }
        }
        .interactiveDismissDisabled(isDatePickerPresented)
        .frame(width: 620, height: 700)
        .background { PortfolixSheetBackground() }
        .onAppear { cashSelection = cashOptions.first?.id.uuidString ?? "" }
        .onChange(of: assetSelection) { _, _ in
            draft = PositionTradeDraft(side: .sell, position: asset)
            cashSelection = cashOptions.first?.id.uuidString ?? ""
            errorMessage = nil
            didAttemptSave = false
        }
        .onChange(of: draft.quantityText) { _, _ in errorMessage = nil }
        .onChange(of: draft.priceText) { _, _ in errorMessage = nil }
        .onChange(of: draft.feesText) { _, _ in errorMessage = nil }
        .onChange(of: draft.amountText) { _, _ in errorMessage = nil }
        .onChange(of: cashSelection) { _, _ in errorMessage = nil }
    }

    private func input(_ field: Field, title: String, placeholder: String, binding: Binding<String>) -> some View {
        AssetEntryTextField(title: title, text: binding, field: field, focus: $focusedField,
            placeholder: placeholder, language: store.appLanguage, numeric: true, isInvalid: invalid(field))
    }
    private func amountField(_ title: String, field: Field, placeholder: String, binding: Binding<String>) -> some View {
        LabeledContent {
            input(field, title: title, placeholder: placeholder, binding: binding)
                .frame(width: AssetEntryLayout.valueFieldWidth, height: AssetEntryLayout.valueFieldHeight)
        } label: {
            AssetEntryFieldLabel(title: title, isInvalid: invalid(field), showsRequiredIndicator: field != .fees)
        }
    }
    private func invalid(_ field: Field) -> Bool {
        guard didAttemptSave else { return false }
        switch field {
        case .quantity: return PositionClosureMath.decimal(draft.quantityText).map { $0 > 0 && $0 <= asset.quantity } != true
        case .price: return PositionClosureMath.decimal(draft.priceText).map { $0 >= 0 } != true
        case .fees: return PositionTradeInput.fees(draft.feesText).map { $0 >= 0 } != true
        case .amount: return PositionClosureMath.decimal(draft.amountText).map { $0 >= 0 } != true
        }
    }
    private func save(committing window: NSWindow?) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        focusedField = nil
        guard await SheetEditingCommit.commit(in: window) else {
            errorMessage = text("无法结束当前输入，请检查后重试。", "Unable to finish editing. Check the current field and try again.")
            return
        }
        do {
            let values = try draft.values(availableQuantity: asset.quantity)
            try store.recordTrade(id: tradeID, side: .sell, position: asset, quantity: values.quantity,
                price: values.price, fees: values.fees, tradeDate: actualTradeDate, cashPositionID: UUID(uuidString: cashSelection))
            dismiss()
        } catch {
            didAttemptSave = true
            errorMessage = (error as? PositionTradeError)?.message(language: store.appLanguage) ?? error.localizedDescription
        }
    }
    private func text(_ chinese: String, _ english: String) -> String { localizedText(chinese, english, language: store.appLanguage) }
}

struct PositionTradeDetailSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: PositionTradeRecord
    @State private var confirmsReversal = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: text("交易记录", "Transaction"), symbol: "arrow.left.arrow.right")
            Divider().overlay(PortfolixTheme.border)
            Form {
                Section {
                    LabeledContent(text("资产", "Asset"), value: "\(record.asset.name) · \(record.asset.symbol)")
                    LabeledContent(text("交易类型", "Type"), value: record.side.title(language: store.appLanguage))
                    LabeledContent(text("实际操作时间", "Actual Trade Time"), value: record.effectiveAt.flatMap { ISO8601DateFormatter().date(from: $0) }.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? record.tradeDate)
                    LabeledContent(text("记录时间", "Record Time"), value: PositionTransactionRow(record).recordedTimeText)
                    LabeledContent(text("成交份额", "Quantity"), value: record.quantity)
                    LabeledContent(text("成交均价", "Trade Price"), value: formatMoney(record.price, currency: record.currency))
                    LabeledContent(text("手续费", "Fees"), value: formatMoney(record.fee, currency: record.currency))
                    LabeledContent(record.side == .sell ? text("实际到账", "Proceeds") : text("增持总成本", "Added Cost"), value: formatMoney(record.amount, currency: record.currency))
                    LabeledContent(text("资金来源 / 去向", "Funding / Destination"), value: record.cash?.name ?? text("外部增持", "External Funds"))
                    LabeledContent(text("已实现盈亏", "Realized P&L"), value: record.realizedProfit.map { formatSignedMoney($0, currency: record.currency) } ?? "—")
                }
            }.portfolixSheetForm()
            Divider().overlay(PortfolixTheme.border)
            SheetActionFooter(errorMessage: errorMessage) {
                Button(text("撤销记录", "Reverse Record")) { confirmsReversal = true }.buttonStyle(QuietButtonStyle())
                Button(text("完成", "Done")) { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }.frame(width: 580, height: 620)
        .background { PortfolixSheetBackground() }
        .alert(text("撤销这条记录？", "Reverse this record?"), isPresented: $confirmsReversal) {
            Button(text("取消", "Cancel"), role: .cancel) {}
            Button(text("撤销记录", "Reverse Record")) {
                do { try store.reverseTrade(record); dismiss() }
                catch { errorMessage = (error as? PositionTradeError)?.message(language: store.appLanguage) ?? error.localizedDescription }
            }
        } message: { Text(text("将恢复对应份额及现金，并重新计算后续交易。", "Restore units and cash, and recalculate subsequent transactions.")) }
    }
    private func text(_ chinese: String, _ english: String) -> String { localizedText(chinese, english, language: store.appLanguage) }
}
