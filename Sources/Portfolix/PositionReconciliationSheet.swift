import AppKit
import SwiftUI

struct PositionReconciliationSheet: View {
    @Environment(PortfolioStore.self) private var store
    @State private var selectedPosition: Position

    init(position: Position) {
        _selectedPosition = State(initialValue: position)
    }

    private var assetSelection: Binding<UUID> {
        Binding(get: { selectedPosition.id }, set: { id in
            guard id != selectedPosition.id, let position = store.positions.first(where: { $0.id == id }) else { return }
            selectedPosition = position
        })
    }

    var body: some View {
        // A fresh editor prevents values and field focus from following a different asset.
        // Keep the selected snapshot intact so concurrent balance changes still fail validation.
        PositionReconciliationForm(position: selectedPosition, assetSelection: assetSelection)
            .id(selectedPosition.id)
    }
}

private struct PositionReconciliationForm: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let position: Position
    @Binding var assetSelection: UUID
    @State private var quantity = ""
    @State private var cost = ""
    @State private var costKnown = true
    @State private var unitCost = false
    @State private var reason = "reconcile"
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var isCash: Bool { position.category == .cash }
    private func text(_ cn: String, _ en: String) -> String { localizedText(cn, en, language: store.appLanguage) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isCash ? text("更新余额", "Update Balance") : text("更新持仓", "Update Holding"), symbol: "equal.circle")
            Divider().overlay(PortfolixTheme.border)
            Form {
                Section {
                    LabeledContent(text("资产", "Asset")) {
                        PortfolixGlassMenuPicker(title: text("资产", "Asset"), selection: $assetSelection,
                            options: store.positions.map(\.id),
                            optionTitle: { id in store.positions.first { $0.id == id }?.name ?? position.name })
                    }
                    .accessibilityElement(children: .contain)
                    LabeledContent(text("当前份额", "Current Quantity"), value: PositionClosureMath.string(position.quantity))
                    if !isCash {
                        LabeledContent(text("当前成本价", "Current Unit Cost"), value: position.costIsKnown ? formatUnitCost(position.averageCost, currency: position.quoteCurrency) : text("暂不确定", "Unknown"))
                    }
                    LabeledContent(text("计价币种", "Currency"), value: position.quoteCurrency.rawValue)
                }
                Section {
                    LabeledContent(isCash ? text("实际余额", "Actual Balance") : text("实际份额", "Actual Quantity")) {
                        TextField(text("填写当前实际数值", "Enter the actual balance"), text: $quantity)
                            .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: AssetEntryLayout.valueFieldWidth)
                    }
                    if !isCash {
                        LabeledContent(text("成本状态", "Cost Status")) {
                            PortfolixGlassSegmentedPicker(title: text("成本状态", "Cost Status"), selection: $costKnown,
                                options: [true, false], optionTitle: { $0 ? text("已核对", "Known") : text("暂不确定", "Unknown") }, width: 240)
                        }
                        if costKnown {
                            LabeledContent(text("成本录入方式", "Cost Entry")) {
                                PortfolixGlassSegmentedPicker(title: text("成本录入方式", "Cost Entry"), selection: $unitCost,
                                    options: [false, true], optionTitle: { $0 ? text("成本价", "Unit Cost") : text("总成本", "Total Cost") }, width: 240)
                            }
                            LabeledContent(unitCost ? text("实际成本价", "Actual Unit Cost") : text("实际总成本", "Actual Total Cost")) {
                                TextField(text("填写核对后的成本", "Enter verified cost"), text: $cost)
                                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: AssetEntryLayout.valueFieldWidth)
                            }
                        }
                    }
                } footer: {
                    Text(text("填写平台当前显示的余额和成本；份额为 0 时将归零。成本不确定时，持仓收益和收益率显示为 —。", "Use your platform’s current balance and cost. Zero clears the holding. Unknown cost hides holding P&L and return rates."))
                }
                Section {
                    LabeledContent(text("更新原因", "Reason")) {
                        PortfolixGlassMenuPicker(title: text("更新原因", "Reason"), selection: $reason,
                            options: ["reconcile", "missing", "correction", "other"], optionTitle: { value in
                                switch value {
                                case "missing": text("长期未记账", "Missing Records")
                                case "correction": text("更正录入", "Correct Entry")
                                case "other": text("其他", "Other")
                                default: text("与平台核对", "Platform Reconciliation")
                                }
                            })
                    }
                    LabeledContent(text("备注", "Note")) {
                        TextField(text("选填，最多 1000 字", "Optional, up to 1,000 characters"), text: $note)
                            .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: AssetEntryLayout.valueFieldWidth)
                    }
                } footer: {
                    Text(text("保存时立即生效，不联动现金账户，也不计为收入或交易。此前遗漏的收益和交易不会被自动补出。", "Takes effect when saved. Cash accounts stay separate. This is not income or a trade; missing historical events are not reconstructed."))
                }
            }
            .portfolixSheetForm()
            .disabled(isSaving)
            Divider().overlay(PortfolixTheme.border)
            SheetActionFooter(errorMessage: errorMessage) {
                Button(text("取消", "Cancel")) { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction).disabled(isSaving)
                Button(text("保存更新", "Save Update")) {
                    let window = NSApp.keyWindow
                    Task { await save(committing: window) }
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(isSaving)
            }
        }
        .frame(width: 620, height: isCash ? 580 : 760)
        .background(PortfolixTheme.canvas)
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            quantity = PositionClosureMath.string(position.quantity)
            cost = position.costIsKnown ? PositionClosureMath.string(position.totalCost) : ""
            costKnown = position.costIsKnown
        }
        .onChange(of: unitCost) { old, new in
            if let value = PositionClosureMath.decimal(cost), let units = PositionClosureMath.decimal(quantity), units > 0 {
                cost = PositionClosureMath.string(new ? value / units : value * units)
            }
        }
    }

    private func save(committing window: NSWindow?) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        guard await SheetEditingCommit.commit(in: window) else {
            errorMessage = text("无法结束当前输入，请检查后重试。", "Unable to finish editing. Check the current field and retry.")
            return
        }
        do {
            guard let units = PositionClosureMath.decimal(quantity), units >= 0 else { throw PositionTradeError.invalidInput }
            let total: Decimal?
            if isCash || units == 0 { total = isCash ? units : 0 }
            else if costKnown {
                guard let value = PositionClosureMath.decimal(cost), value >= 0 else { throw PositionTradeError.invalidInput }
                total = unitCost ? units * value : value
            } else { total = nil }
            try store.reconcilePosition(position, quantity: units, totalCost: total, reason: reason, note: note)
            dismiss()
        } catch { errorMessage = (error as? PositionTradeError)?.message(language: store.appLanguage) ?? error.localizedDescription }
    }
}

struct PositionReconciliationDetailSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: PositionReconciliationRecord

    private var reasonText: String {
        let values = ["reconcile": ("与平台核对", "Platform Reconciliation"), "missing": ("长期未记账", "Missing Records"), "correction": ("更正录入", "Correct Entry"), "other": ("其他", "Other")]
        let value = values[record.reason]
        return value.map { localizedText($0.0, $0.1, language: store.appLanguage) } ?? record.reason
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: localizedText("持仓校准详情", "Reconciliation Details", language: store.appLanguage), symbol: "equal.circle")
            Form {
                Section {
                    LabeledContent(localizedText("资产", "Asset", language: store.appLanguage), value: record.asset.name)
                    LabeledContent(localizedText("生效时间", "Effective Time", language: store.appLanguage), value: PositionTransactionRow(record).recordedTimeText)
                    LabeledContent(localizedText("份额变化", "Quantity Change", language: store.appLanguage), value: "\(record.asset.quantity) → \(record.quantity)")
                    LabeledContent(localizedText("成本状态", "Cost Status", language: store.appLanguage), value: record.costKnown ? localizedText("已核对", "Known", language: store.appLanguage) : localizedText("暂不确定", "Unknown", language: store.appLanguage))
                    LabeledContent(localizedText("更新前总成本", "Previous Total Cost", language: store.appLanguage), value: record.asset.costKnown == false ? "—" : record.asset.totalCost + " " + record.asset.quoteCurrency)
                    if record.costKnown { LabeledContent(localizedText("更新后总成本", "New Total Cost", language: store.appLanguage), value: record.totalCost + " " + record.asset.quoteCurrency) }
                    LabeledContent(localizedText("更新原因", "Reason", language: store.appLanguage), value: reasonText)
                    LabeledContent(localizedText("备注", "Note", language: store.appLanguage), value: record.note.isEmpty ? "—" : record.note).lineLimit(1).portfolixHelp(record.note)
                } footer: {
                    Text(localizedText("此记录是余额校准，未产生现金流或已实现收益。校准前的遗漏记录仍未补齐。", "This balance checkpoint creates no cash flow or realized profit. Missing historical records remain incomplete.", language: store.appLanguage))
                }
            }.portfolixSheetForm()
            HStack { Spacer(); Button(localizedText("完成", "Done", language: store.appLanguage)) { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction) }.padding(20)
        }.frame(width: 620, height: 540).background(PortfolixTheme.canvas)
    }
}
