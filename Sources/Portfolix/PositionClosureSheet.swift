import SwiftUI

struct PositionClosureDetailSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: PositionClosureRecord
    @State private var errorMessage: String?
    @State private var confirmsReversal = false

    private var canReverse: Bool {
        guard !record.isReversed, let date = PositionClosureMath.isoDate(record.recordedAt) else { return false }
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
