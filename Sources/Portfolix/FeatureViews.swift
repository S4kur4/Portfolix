import AppKit
import SwiftUI

struct PositionsView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var operationErrorMessage: String?
    @State private var positionSortOrder: [KeyPathComparator<Position>] = []
    @State private var showsClosedPositions = false
    @State private var pendingClosure: Position?
    @State private var selectedClosureID: UUID?
    @State private var pendingReversal: PositionTransactionRow?
    @State private var pendingOpeningReview: PositionOpeningBalanceRecord?
    @State private var pendingReconciliation: Position?
    @State private var recordDetail: PositionTransactionRow?
    @State private var pendingCashReduction: Position?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            PageHeader(title: localizedText("持仓明细", "Holdings", language: store.appLanguage)) {
                HStack(spacing: PortfolixSpacing.sm) {
                    if !showsClosedPositions {
                        Button { pendingReconciliation = reductionTarget } label: {
                            Label(localizedText("更新持仓", "Update Holding", language: store.appLanguage), systemImage: "equal.circle")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(reductionTarget == nil)

                        Button {
                            guard let target = reductionTarget else { return }
                            if target.category == .cash { pendingCashReduction = target }
                            else { pendingClosure = target }
                        } label: {
                            Label(reductionTarget?.category == .cash
                                ? localizedText("转出现金", "Cash Out", language: store.appLanguage)
                                : localizedText("卖出资产", "Sell Asset", language: store.appLanguage), systemImage: "minus")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(reductionTarget == nil)

                        Button {
                            store.presentNewPositionEditor()
                        } label: {
                            Label(localizedText("添加资产", "Add Asset", language: store.appLanguage), systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        PortfolixGlassSegmentedPicker(
                            title: localizedText("持仓状态", "Holding Status", language: store.appLanguage),
                            selection: $showsClosedPositions, options: [false, true],
                            optionTitle: { $0 ? localizedText("操作记录", "Activity", language: store.appLanguage)
                                : localizedText("持有中", "Open", language: store.appLanguage) },
                            width: 184, height: PortfolixLayout.positionsToolbarControlHeight
                        )
                        HStack(spacing: PortfolixSpacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(PortfolixTheme.tertiary)
                            TextField(localizedText("搜索资产代码或名称", "Search code or name", language: store.appLanguage), text: $store.searchText)
                                .textFieldStyle(.plain)
                                .font(PortfolixTypography.label)
                                .focused($isSearchFieldFocused)
                        }
                        .padding(.horizontal, PortfolixSpacing.md)
                        .frame(width: 220, height: PortfolixLayout.positionsToolbarControlHeight)
                        .portfolixSecondaryGlass(
                            in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous),
                            interactive: false
                        )
                        .holdingVoiceInput(
                            text: $store.searchText,
                            isFocused: isSearchFieldFocused,
                            numeric: false,
                            language: store.appLanguage,
                            appearance: .highlightedField
                        )
                        .portfolixHelp(localizedText(
                            "选中搜索框后，可按住 Fn 进行语音输入。",
                            "Focus the search field, then hold Fn to dictate.",
                            language: store.appLanguage
                        ))

                        Spacer()

                        PortfolixGlassSegmentedPicker(
                            title: localizedText("展示币种", "Display Currency", language: store.appLanguage),
                            selection: $store.displayCurrency,
                            options: DisplayCurrency.allCases,
                            optionTitle: { $0.rawValue },
                            width: 240,
                            height: PortfolixLayout.positionsToolbarControlHeight
                        )
                    }
                    .padding(PortfolixSpacing.lg)

                    Divider().overlay(PortfolixTheme.border)

                    if showsClosedPositions { closedPositionsTable }
                    else { positionsTable }
                }
            }
        }
        .alert(localizedText("撤销这条记录？", "Reverse this record?", language: store.appLanguage), isPresented: reversalAlertPresented, presenting: pendingReversal) { record in
            Button(localizedText("取消", "Cancel", language: store.appLanguage), role: .cancel) {
                pendingReversal = nil
            }
            Button(localizedText("撤销记录", "Reverse Record", language: store.appLanguage), role: .destructive) {
                do {
                    try store.reverseRecord(record)
                    selectedClosureID = nil
                    operationErrorMessage = nil
                } catch {
                    operationErrorMessage = (error as? PositionTradeError)?.message(language: store.appLanguage)
                        ?? (error as? PositionClosureError)?.message(language: store.appLanguage)
                        ?? (error as? PositionOpeningBalanceError)?.message(language: store.appLanguage) ?? error.localizedDescription
                }
                pendingReversal = nil
            }
        } message: { record in
            Text(record.reconciliation != nil
                ? localizedText("将撤销 \(record.name) 的这次持仓校准，恢复校准前的余额和成本。", "Reverse this balance checkpoint for \(record.name) and restore its previous balance and cost.", language: store.appLanguage)
                : record.opening != nil
                    ? localizedText("将撤销 \(record.name) 的期初持仓，并移除该资产的余额及相关历史。", "Reverse the opening balance for \(record.name) and remove its balance and related history.", language: store.appLanguage)
                    : localizedText("将撤销 \(record.name) 的这条记录，并重新计算相关份额、现金和后续记录。", "Reverse this record for \(record.name) and recalculate related units, cash, and later records.", language: store.appLanguage))
        }
        .alert(localizedText("无法完成操作", "Unable to Complete", language: store.appLanguage), isPresented: operationErrorPresented) {
            Button(localizedText("好", "OK", language: store.appLanguage), role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "")
        }
        .sheet(item: $pendingClosure) { position in
            PositionTradeSheet(position: position).environment(store)
        }
        .sheet(item: $pendingOpeningReview) { record in
            PositionOpeningBalanceSheet(record: record).environment(store)
        }
        .sheet(item: $pendingReconciliation) { position in
            PositionReconciliationSheet(position: position).environment(store)
        }
        .sheet(item: $recordDetail) { row in
            Group {
                if let record = row.reconciliation { PositionReconciliationDetailSheet(record: record) }
                else if let record = row.trade { PositionTradeDetailSheet(record: record) }
                else if let record = row.closure { PositionClosureDetailSheet(record: record) }
                else if let record = row.opening { PositionOpeningBalanceDetailSheet(record: record) }
            }.environment(store)
        }
        .sheet(item: $pendingCashReduction) { position in
            CashReductionSheet(position: position).environment(store)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var reversalAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingReversal != nil },
            set: { isPresented in
                if !isPresented {
                    pendingReversal = nil
                }
            }
        )
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding(
            get: { operationErrorMessage != nil },
            set: { if !$0 { operationErrorMessage = nil } }
        )
    }

    private var positionsTable: some View {
        let positions = sortedFilteredPositions
        let numbers = PositionDetailOrdering.displayNumbers(for: positions)
        return Table(positions, selection: selectedPositionBinding, sortOrder: $positionSortOrder) {
            TableColumn(localizedText("序号", "No.", language: store.appLanguage)) { position in
                Text(String(numbers[position.id] ?? 0))
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.text))
                    .monospacedDigit()
                    .padding(.leading, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(36)
            .alignment(.leading)

            TableColumn(localizedText("资产", "Asset", language: store.appLanguage)) { position in
                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    Text(position.name)
                        .foregroundStyle(PositionTableForeground(color: PortfolixTheme.text))
                        .lineLimit(1)
                    Text(position.symbol)
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PositionTableForeground(color: PortfolixTheme.tertiary, selectedOpacity: 0.74))
                        .lineLimit(1)
                }
            }
            .width(min: 96, ideal: 124)

            TableColumn(localizedText("类别", "Type", language: store.appLanguage)) { position in
                HStack(spacing: PortfolixSpacing.xs) {
                    Circle()
                        .fill(PositionTableForeground(color: position.category.assetClass.area))
                        .frame(width: 5, height: 5)
                    Text(position.category.title(language: store.appLanguage))
                        .foregroundStyle(PositionTableForeground(color: PortfolixTheme.secondary))
                        .lineLimit(1)
                }
            }
            .width(76)

            TableColumn(localizedText("份额", "Quantity", language: store.appLanguage)) { position in
                Text(NSDecimalNumber(decimal: position.quantity).stringValue)
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.text))
                    .monospacedDigit()
            }
            .width(72)

            TableColumn(
                localizedText("成本价", "Unit Cost", language: store.appLanguage),
                value: \.averageCostCNY
            ) { position in
                Text(position.costIsKnown ? formatUnitCost(position.averageCost, currency: position.quoteCurrency) : "—")
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.text))
                    .monospacedDigit()
            }
            .width(104)

            TableColumn(
                localizedText("总成本", "Total Cost", language: store.appLanguage),
                value: \.totalCostCNY
            ) { position in
                Text(position.costIsKnown ? formatMoney(position.totalCost, currency: position.quoteCurrency) : "—")
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.text))
                    .monospacedDigit()
            }
            .width(116)

            TableColumn(
                localizedText("当前市值", "Market Value", language: store.appLanguage),
                value: \.marketValueCNY
            ) { position in
                Text(formatMoney(store.converted(position.marketValueCNY), currency: store.displayCurrency))
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.text))
                    .monospacedDigit()
            }
            .width(116)

            TableColumn(
                localizedText("收益率", "Return", language: store.appLanguage),
                value: \.profitRate
            ) { position in
                Text(position.costIsKnown ? formatPercent(position.profitRate) : "—")
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.performanceColor(for: position.profitRate, scheme: store.performanceColorScheme)))
                    .monospacedDigit()
            }
            .width(72)

            TableColumn(localizedText("行情来源", "Quote Source", language: store.appLanguage)) { position in
                PositionSourceCell(position: position, store: store)
            }
            .width(min: 136, ideal: 160)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: colorScheme != .dark))
        .scrollContentBackground(.hidden)
        .background(PortfolixTheme.surface)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .contextMenu(forSelectionType: Position.ID.self) { selection in
            if let positionID = selection.first {
                if canRefresh(positionID: positionID) {
                    Button {
                        store.refreshPosition(id: positionID)
                    } label: {
                        Label(localizedText("更新价格", "Refresh Price", language: store.appLanguage), systemImage: "arrow.clockwise")
                    }
                }

                Button {
                    store.presentPositionEditor(for: positionID)
                } label: {
                    Label(localizedText("添加资产", "Add Asset", language: store.appLanguage), systemImage: "plus")
                }

                if let position = store.positions.first(where: { $0.id == positionID }) {
                    Button { pendingReconciliation = position } label: {
                        Label(localizedText(position.category == .cash ? "更新余额" : "更新持仓", "Update Balance", language: store.appLanguage), systemImage: "equal.circle")
                    }
                    if position.category == .cash {
                        Button { pendingCashReduction = position } label: {
                            Label(localizedText("转出现金", "Cash Out", language: store.appLanguage), systemImage: "minus.circle")
                        }
                    } else {
                        Button { pendingClosure = position } label: {
                            Label(localizedText("卖出资产", "Sell Asset", language: store.appLanguage), systemImage: "arrow.down.right.circle")
                        }
                    }
                }

            }
        } primaryAction: { selection in
            if let positionID = selection.first {
                store.presentPositionEditor(for: positionID)
            }
        }
    }

    private var selectedPositionBinding: Binding<Position.ID?> {
        Binding(
            get: { store.selectedPositionID },
            set: { store.selectedPositionID = $0 }
        )
    }

    private var closedPositionsTable: some View {
        let records = PositionTransactionRow.listed(trades: store.positionTrades, closures: store.positionClosures,
            openings: store.positionOpeningBalances, reconciliations: store.positionReconciliations, query: store.searchText)
        return Table(records, selection: $selectedClosureID) {
            TableColumn(localizedText("序号", "No.", language: store.appLanguage)) {
                activityText(String($0.displayNumber))
                    .monospacedDigit()
                    // Match the native header label's inset within the column.
                    .padding(.leading, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.width(36)
                .alignment(.leading)
            TableColumn(localizedText("资产", "Asset", language: store.appLanguage)) { record in
                VStack(alignment: .leading, spacing: 4) {
                    activityText(record.name).lineLimit(1)
                    activityText(record.symbol, color: PortfolixTheme.secondary).font(PortfolixTypography.caption)
                }
            }.width(min: 96, ideal: 140)
            TableColumn(localizedText("记录时间", "Record Time", language: store.appLanguage)) { record in
                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    activityText(record.recordedDateText)
                    activityText(record.recordedClockText, color: PortfolixTheme.secondary).font(PortfolixTypography.caption)
                }.monospacedDigit()
            }.width(88)
            TableColumn(localizedText("类型", "Type", language: store.appLanguage)) {
                activityText($0.needsOpeningReview ? localizedText("期初待核对", "Verify Opening", language: store.appLanguage) : ($0.reconciliation?.units == 0 ? localizedText("已清仓", "Closed", language: store.appLanguage) : $0.kind.title(language: store.appLanguage))).lineLimit(1)
            }.width(76)
            TableColumn(localizedText("份额", "Quantity", language: store.appLanguage)) { activityText($0.needsOpeningReview ? "—" : $0.quantity).monospacedDigit() }.width(72)
            TableColumn(localizedText("成交均价", "Trade Price", language: store.appLanguage)) {
                activityText($0.opening != nil || $0.reconciliation != nil || $0.kind == .withdraw ? "—" : formatMoney($0.price, currency: $0.currency)).monospacedDigit()
            }.width(96)
            TableColumn(localizedText("手续费", "Fees", language: store.appLanguage)) {
                activityText($0.opening != nil || $0.reconciliation != nil || $0.kind == .withdraw ? "—" : formatMoney($0.fee, currency: $0.currency)).monospacedDigit()
            }.width(72)
            TableColumn(localizedText("记录金额", "Recorded Amount", language: store.appLanguage)) {
                activityText($0.needsOpeningReview || $0.reconciliation != nil ? "—" : formatMoney($0.amount, currency: $0.currency)).monospacedDigit()
            }.width(104)
            TableColumn(localizedText("已实现盈亏", "Realized P&L", language: store.appLanguage)) { record in
                activityText(record.profit(in: store.displayCurrency).map { formatSignedMoney($0, currency: store.displayCurrency) } ?? "—",
                    color: PortfolixTheme.performanceColor(for: record.profit ?? 0, scheme: store.performanceColorScheme))
                    .monospacedDigit()
            }.width(116)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: colorScheme != .dark))
        .scrollContentBackground(.hidden).background(PortfolixTheme.surface)
        .contextMenu(forSelectionType: UUID.self) { selection in
            if let record = records.first(where: { selection.contains($0.id) }) {
                Button { recordDetail = record } label: {
                    Label(record.reconciliation != nil
                        ? localizedText("查看校准详情", "View Reconciliation", language: store.appLanguage)
                        : localizedText("查看记录详情", "View Details", language: store.appLanguage), systemImage: "doc.text.magnifyingglass")
                }
                if let opening = record.opening, opening.requiresReview {
                    Button { pendingOpeningReview = opening } label: {
                        Label(localizedText("核对期初持仓", "Review Opening Balance", language: store.appLanguage), systemImage: "checkmark.circle")
                    }
                }
                Button {
                    operationErrorMessage = nil
                    pendingReversal = record
                } label: {
                    Label(localizedText("撤销记录", "Reverse Record", language: store.appLanguage), systemImage: "arrow.uturn.backward")
                }
                .disabled(!record.canReverse() || (record.opening.map { opening in
                    PositionRecordLinks.activeAccountIDs(trades: store.positionTrades, closures: store.positionClosures).contains(opening.id)
                } ?? false))
            }
        } primaryAction: { selection in
            if let record = records.first(where: { selection.contains($0.id) }) { recordDetail = record }
        }
        .overlay {
            if records.isEmpty {
                Text(localizedText("暂无交易与调整记录", "No activity yet", language: store.appLanguage))
                    .font(PortfolixTypography.body).foregroundStyle(PortfolixTheme.secondary).allowsHitTesting(false)
            }
        }
    }

    private func activityText(_ value: String, color: Color = PortfolixTheme.text) -> some View {
        Text(value).foregroundStyle(PositionTableForeground(color: color))
    }

    private var sortedFilteredPositions: [Position] {
        PositionDetailOrdering.sorted(
            store.filteredPositions,
            using: positionSortOrder
        )
    }

    private var reductionTarget: Position? {
        store.positions.first { $0.id == store.selectedPositionID }
            ?? store.positions.first { $0.category != .cash }
            ?? store.positions.first
    }

    private func canRefresh(_ position: Position) -> Bool {
        MarketDataAdapter.supportsQuote(for: position)
    }

    private func canRefresh(positionID: Position.ID) -> Bool {
        guard let position = store.positions.first(where: { $0.id == positionID }) else { return false }
        return canRefresh(position)
    }

}

// Resolve selection styling with the native row background, rather than redrawing
// every column from a separate copy of the table selection state.
struct PositionTableForeground: ShapeStyle {
    let color: Color
    var selectedOpacity: Double = 1

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.backgroundProminence == .increased ? .white.opacity(selectedOpacity) : color
    }
}

struct PositionSourceCell: View {
    let position: Position
    // Table cells can be hosted and recycled outside the parent environment tree.
    let store: PortfolioStore

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(localizedQuoteSource(position.source, language: store.appLanguage))
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.text))
                    .lineLimit(1)
                RelativeTimeText { now in
                    "\(position.priceDateText(language: store.appLanguage)) · \(position.relativeUpdateText(now: now, language: store.appLanguage))"
                }
                .font(PortfolixTypography.caption)
                .foregroundStyle(PositionTableForeground(color: PortfolixTheme.tertiary, selectedOpacity: 0.74))
                .lineLimit(1)
            }

            Spacer(minLength: PortfolixSpacing.sm)

            if MarketDataAdapter.supportsQuote(for: position) {
                PositionSourceRefreshSlot(position: position, store: store)
            }
        }
    }
}

/// Isolates `selectedPositionID` and `refreshingPositionIDs` observation to the trailing
/// refresh button so changing table selection does not rebuild the entire source cell.
private struct PositionSourceRefreshSlot: View {
    let position: Position
    let store: PortfolioStore

    var body: some View {
        let isSelected = store.selectedPositionID == position.id
        PositionRefreshButton(
            position: position,
            isRefreshing: store.refreshingPositionIDs.contains(position.id),
            language: store.appLanguage
        ) {
            store.refreshPosition(id: position.id)
        }
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
    }
}

enum PositionDetailOrdering {
    static func displayNumbers(for positions: [Position]) -> [Position.ID: Int] {
        Dictionary(uniqueKeysWithValues: positions.enumerated().map { ($0.element.id, $0.offset + 1) })
    }

    static func sorted(
        _ positions: [Position],
        using comparators: [KeyPathComparator<Position>]
    ) -> [Position] {
        guard !comparators.isEmpty else { return positions }
        return positions.sorted(using: comparators)
    }
}

struct AIReportView: View {
    @Environment(PortfolioStore.self) private var store
    @State private var composerResetID = UUID()
    @State private var isClearHistoryConfirmationPresented = false
    @State private var clearHistoryErrorMessage: String?
    @State private var isMemorySheetPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            PageHeader(title: localizedText("AI 投研", "AI Insights", language: store.appLanguage))

            AIReportChatSurface(
                report: store.aiAnalysisReport,
                items: store.aiAnalysisChatItems,
                threads: store.aiChatThreads,
                activeThreadID: store.activeAIChatThreadID,
                run: store.aiAnalysisRun,
                isRunning: isRunning,
                isSendingFollowUp: store.isAnsweringAIAnalysisFollowUp,
                followUpProgress: store.aiAnalysisFollowUpProgress,
                activityLines: store.aiAnalysisActivityLines,
                activitySteps: store.aiAnalysisActivitySteps,
                positions: store.positions,
                hasPositions: !store.positions.isEmpty,
                llmReadiness: AIReportReadiness.credential(
                    isConfigured: store.hasLLMAPIKey,
                    validationState: store.llmAPIKeyValidationState
                ),
                searchReadiness: connectedSearchReadiness,
                selectedModel: aiModelBinding,
                availableModels: availableModelOptions,
                selectedAnalysisMode: aiAnalysisModeBinding,
                composerResetID: composerResetID,
                language: store.appLanguage,
                canClearHistory: hasAIAnalysisHistory,
                clearHistory: { isClearHistoryConfirmationPresented = true },
                onNewThread: {
                    guard !store.aiAnalysisChatItems.isEmpty else { return }
                    store.startNewAIChatThread()
                    composerResetID = UUID()
                },
                onSelectThread: { id in
                    store.selectAIChatThread(id: id)
                },
                onDeleteThread: { id in
                    store.deleteAIChatThread(id: id)
                },
                onOpenMemory: { isMemorySheetPresented = true },
                onUndoMemory: { id in
                    store.deleteAIMemoryItem(id: id)
                },
                generate: requestAnalysis,
                cancel: store.cancelAIAnalysis,
                sendFollowUp: sendFollowUp,
                openHolding: openHoldingForAlert
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .sheet(isPresented: $isMemorySheetPresented) {
            AIMemoryManagerSheet()
                .environment(store)
        }
        .alert(localizedText("清空分析历史？", "Clear analysis history?", language: store.appLanguage), isPresented: $isClearHistoryConfirmationPresented) {
            Button(localizedText("取消", "Cancel", language: store.appLanguage), role: .cancel) {}
            Button(localizedText("清空", "Clear", language: store.appLanguage), role: .destructive) {
                clearAIAnalysisHistory()
            }
        } message: {
            Text(
                localizedText(
                    "将删除 AI 投研报告、追问、回答与诊断记录。",
                    "This will delete AI Insights reports, follow-ups, responses, and diagnostics.",
                    language: store.appLanguage
                )
            )
        }
        .alert(localizedText("无法清空历史", "Unable to clear history", language: store.appLanguage), isPresented: clearHistoryErrorPresented) {
            Button(localizedText("好", "OK", language: store.appLanguage), role: .cancel) {
                clearHistoryErrorMessage = nil
            }
        } message: {
            Text(clearHistoryErrorMessage ?? localizedText("请稍后重试", "Please try again later", language: store.appLanguage))
        }
        .onAppear {
            store.refreshProviderCredentialState()
            store.refreshAIAnalysisChatRetention()
            store.refreshDeepSeekModelCatalog()
        }
    }

    private var isRunning: Bool {
        if case .running = store.aiAnalysisRun.status {
            return true
        }
        return false
    }

    private var hasAIAnalysisHistory: Bool {
        store.aiAnalysisReport != nil || !store.aiAnalysisChatItems.isEmpty
    }

    private func requestAnalysis() {
        store.generateAIAnalysis()
    }

    private func sendFollowUp(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !store.isAnsweringAIAnalysisFollowUp else { return }
        store.submitAIAnalysisFollowUp(question)
    }

    private func clearAIAnalysisHistory() {
        do {
            try store.clearAIAnalysisHistory()
            composerResetID = UUID()
        } catch {
            clearHistoryErrorMessage = error.localizedDescription
        }
    }

    private var clearHistoryErrorPresented: Binding<Bool> {
        Binding(
            get: { clearHistoryErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    clearHistoryErrorMessage = nil
                }
            }
        )
    }

    private var aiModelBinding: Binding<String> {
        Binding(
            get: { store.aiConfiguration.model },
            set: { model in
                store.selectAIModel(model)
            }
        )
    }

    private var aiAnalysisModeBinding: Binding<SmartAnalysisMode> {
        Binding(
            get: { store.searchConfiguration.isEnabled ? .connected : .basic },
            set: { mode in
                store.selectSmartAnalysisMode(mode)
            }
        )
    }

    private var availableModelOptions: [String] {
        store.availableLLMModels
    }

    private var connectedSearchReadiness: AIReportReadiness {
        guard store.searchConfiguration.isEnabled else { return .ready }
        let providers = store.searchConfiguration.orderedEnabledProviders
        guard !providers.isEmpty else { return .missing }
        let readiness: [AIReportReadiness] = providers.map { provider in
            switch provider {
            case .parallel:
                .ready
            case .deepseek:
                AIReportReadiness.credential(isConfigured: store.hasLLMAPIKey, validationState: store.llmAPIKeyValidationState)
            case .tavily:
                AIReportReadiness.credential(
                    isConfigured: store.hasTavilyAPIKey,
                    validationState: store.tavilyAPIKeyValidationState
                )
            case .bocha:
                AIReportReadiness.credential(
                    isConfigured: store.hasBochaAPIKey,
                    validationState: store.bochaAPIKeyValidationState
                )
            case .exa:
                AIReportReadiness.credential(isConfigured: store.hasExaAPIKey, validationState: store.exaAPIKeyValidationState)
            case .anysearch:
                AIReportReadiness.credential(isConfigured: store.hasAnySearchAPIKey, validationState: store.anySearchAPIKeyValidationState)
            }
        }
        if readiness.contains(.ready) { return .ready }
        if readiness.contains(.invalid) { return .invalid }
        if readiness.contains(.needsValidation) { return .needsValidation }
        return .missing
    }

    private func openHoldingForAlert(_ alert: AIAssetAlert) {
        let match = store.positions.first {
            (!alert.symbol.isEmpty && $0.symbol.caseInsensitiveCompare(alert.symbol) == .orderedSame)
                || (!alert.assetName.isEmpty && $0.name.caseInsensitiveCompare(alert.assetName) == .orderedSame)
        }
        guard let match else { return }
        store.selectedPositionID = match.id
        store.selection = .positions
    }
}

private enum AIReportChatRenderPolicy {
    static let timestampWidth: CGFloat = 40
}

private struct AIReportChatSurface: View {
    let report: AIAnalysisReport?
    let items: [AIReportChatItem]
    let threads: [AIChatThread]
    let activeThreadID: UUID?
    let run: AIAnalysisRun
    let isRunning: Bool
    let isSendingFollowUp: Bool
    let followUpProgress: AIFollowUpProgress?
    let activityLines: [AIAgentActivityLine]
    let activitySteps: [AIAgentActivityStep]
    let positions: [Position]
    let hasPositions: Bool
    let llmReadiness: AIReportReadiness
    let searchReadiness: AIReportReadiness
    @Binding var selectedModel: String
    let availableModels: [String]
    @Binding var selectedAnalysisMode: SmartAnalysisMode
    let composerResetID: UUID
    let language: AppLanguage
    let canClearHistory: Bool
    let clearHistory: () -> Void
    let onNewThread: () -> Void
    let onSelectThread: (UUID) -> Void
    let onDeleteThread: (UUID) -> Void
    let onOpenMemory: () -> Void
    let onUndoMemory: (UUID) -> Void
    let generate: () -> Void
    let cancel: () -> Void
    let sendFollowUp: (String) -> Void
    let openHolding: (AIAssetAlert) -> Void
    @State private var pendingScrollTask: Task<Void, Never>?
    @State private var reviewQuestionRequest: AIReportComposerReviewRequest?

    var body: some View {
        let indexedItems = Array(items.enumerated())

        Panel(padding: 0) {
            VStack(spacing: 0) {
                AIReportChatHeader(
                    threads: threads,
                    activeThreadID: activeThreadID,
                    canStartNewThread: !items.isEmpty,
                    isInteractionEnabled: !isRunning && !isSendingFollowUp,
                    language: language,
                    canClearHistory: canClearHistory,
                    clearHistory: clearHistory,
                    onNewThread: onNewThread,
                    onSelectThread: onSelectThread,
                    onDeleteThread: onDeleteThread
                )

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: PortfolixSpacing.lg) {

                            if items.isEmpty && !isRunning {
                                AIReportAgentBubble {
                                    AIReportUntimestampedAgentRow {
                                        AIReportWelcomeMessage(
                                            hasPositions: hasPositions,
                                            llmReadiness: llmReadiness,
                                            searchReadiness: searchReadiness,
                                            usesConnectedMode: usesConnectedMode,
                                            language: language
                                        )
                                    }
                                }
                            }

                            ForEach(indexedItems, id: \.element.id) { index, item in
                                VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                                    if shouldShowDateSeparator(for: item, at: index, items: items) {
                                        AIReportChatDateSeparator(date: item.createdAt, language: language)
                                    }

                                    switch item.content {
                                    case let .user(text):
                                        AIReportUserBubble(text: text, createdAt: item.createdAt, language: language)
                                    case let .report(report, reportRun):
                                        AIReportAgentBubble {
                                            AIReportChatReport(
                                                report: report,
                                                run: reportRun,
                                                language: language,
                                                modelUsage: item.responseModelUsage,
                                                activitySteps: item.activitySteps ?? [],
                                                positions: positions,
                                                isInteractive: !isRunning && !isSendingFollowUp,
                                                onAskFollowUp: sendFollowUp,
                                                onPrefillFollowUp: { question in
                                                    reviewQuestionRequest = AIReportComposerReviewRequest(question: question)
                                                },
                                                onOpenHolding: openHolding
                                            )
                                        }
                                    case let .assistant(text):
                                        let fallbackQuestion = item.retryQuestion ?? precedingUserQuestion(before: index, in: items)
                                        AIReportAgentBubble {
                                            AIReportFollowUpMessage(
                                                text: text,
                                                citations: item.displayedCitations,
                                                createdAt: item.createdAt,
                                                language: language,
                                                modelUsage: item.responseModelUsage,
                                                showsDisclaimer: AIChatDisclosurePolicy.shouldShowDisclosure(for: text),
                                                activitySteps: item.activitySteps ?? [],
                                                extractedMemories: item.extractedMemories ?? [],
                                                retryQuestion: fallbackQuestion,
                                                isFailure: item.retryQuestion != nil,
                                                canRetry: !isRunning && !isSendingFollowUp,
                                                onRetry: { question in sendFollowUp(question) },
                                                onUndoMemory: onUndoMemory,
                                                onManageMemories: onOpenMemory
                                            )
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if isRunning {
                                AIReportAgentBubble {
                                    AIReportUntimestampedAgentRow {
                                        AIReportAgentProgressMessage(
                                            status: run.status,
                                            activityLines: activityLines,
                                            activitySteps: AIAgentActivityStepPolicy.liveStepsWithPending(
                                                activitySteps,
                                                isReport: true,
                                                usesConnectedSearch: usesConnectedMode,
                                                language: language
                                            ),
                                            language: language
                                        )
                                    }
                                }
                            } else if isSendingFollowUp {
                                AIReportAgentBubble {
                                    AIReportUntimestampedAgentRow {
                                        AIReportFollowUpProgressMessage(
                                            progress: followUpProgress ?? .analyzing,
                                            activityLines: activityLines,
                                            activitySteps: AIAgentActivityStepPolicy.liveStepsWithPending(
                                                activitySteps,
                                                isReport: false,
                                                usesConnectedSearch: usesConnectedMode,
                                                language: language
                                            ),
                                            language: language
                                        )
                                    }
                                }
                            } else if shouldShowStatusMessage {
                                AIReportAgentBubble {
                                    AIReportUntimestampedAgentRow {
                                        AIReportStaticStatusMessage(
                                            status: run.status,
                                            hasPositions: hasPositions,
                                            llmReadiness: llmReadiness,
                                            searchReadiness: searchReadiness,
                                            usesConnectedMode: usesConnectedMode,
                                            language: language
                                        )
                                    }
                                }
                            }

                            Color.clear
                                .frame(height: PortfolixSpacing.xl)
                                .id("chat-bottom")
                        }
                        .padding(.horizontal, PortfolixSpacing.lg)
                        .padding(.top, PortfolixSpacing.lg)
                        .padding(.bottom, PortfolixSpacing.md)
                    }
                    .scrollIndicators(.never)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear {
                        scheduleScrollToBottom(proxy, animated: false, delay: 0.08)
                    }
                    .onChange(of: items.count) { _, _ in
                        scheduleScrollToBottom(proxy, animated: false)
                    }
                    .onDisappear {
                        pendingScrollTask?.cancel()
                        pendingScrollTask = nil
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

                Divider()

                AIReportChatComposer(
                    canGenerate: hasPositions && !isRunning,
                    canSendFollowUp: !isRunning && !isSendingFollowUp,
                    isAwaitingResponse: isSendingFollowUp || isRunning,
                    hasReport: hasReport,
                    selectedModel: $selectedModel,
                    availableModels: availableModels,
                    selectedAnalysisMode: $selectedAnalysisMode,
                    fallbackModelName: report?.model ?? run.model,
                    language: language,
                    reviewQuestionRequest: $reviewQuestionRequest,
                    generate: generate,
                    cancel: cancel,
                    sendFollowUp: sendFollowUp
                )
                .id(composerResetID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shouldShowDateSeparator(for item: AIReportChatItem, at index: Int, items: [AIReportChatItem]) -> Bool {
        guard index > 0 else { return true }
        let previous = items[index - 1]
        return !Calendar.current.isDate(previous.createdAt, inSameDayAs: item.createdAt)
    }

    private func scheduleScrollToBottom(
        _ proxy: ScrollViewProxy,
        animated: Bool,
        delay: TimeInterval = 0.02
    ) {
        pendingScrollTask?.cancel()
        pendingScrollTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            } else {
                withTransaction(Transaction(animation: nil)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var hasReport: Bool {
        report != nil || items.contains { item in
            if case .report = item.content {
                return true
            }
            return false
        }
    }

    private var shouldShowStatusMessage: Bool {
        switch run.status {
        case .idle, .completed:
            false
        case let .missingConfiguration(message):
            !lastAssistantMessageMatches(message)
        case .failed:
            true
        case .running:
            false
        }
    }

    private func lastAssistantMessageMatches(_ message: String) -> Bool {
        guard
            let lastItem = items.last,
            case let .assistant(text) = lastItem.content
        else {
            return false
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            == message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usesConnectedMode: Bool {
        selectedAnalysisMode == .connected
    }

    private func precedingUserQuestion(before index: Int, in items: [AIReportChatItem]) -> String? {
        guard index > 0 else { return nil }
        for cursor in stride(from: index - 1, through: 0, by: -1) {
            if items[cursor].kind == .user,
               let text = items[cursor].text?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty
            {
                return text
            }
            if items[cursor].kind == .report { break }
        }
        return nil
    }
}

private struct AIReportChatHeader: View {
    let threads: [AIChatThread]
    let activeThreadID: UUID?
    let canStartNewThread: Bool
    let isInteractionEnabled: Bool
    let language: AppLanguage
    let canClearHistory: Bool
    let clearHistory: () -> Void
    let onNewThread: () -> Void
    let onSelectThread: (UUID) -> Void
    let onDeleteThread: (UUID) -> Void
    @State private var isThreadsPopoverPresented = false

    var body: some View {
        HStack(spacing: PortfolixSpacing.md) {
            ZStack {
                Circle()
                    .fill(PortfolixTheme.brandGradient)
                PortfolixBrandGlyph(size: 20)
            }
            .frame(width: 28, height: 28)

            Text(localizedText("Portfolix Agent", "Portfolix Agent", language: language))
                .font(PortfolixTypography.subheading)
                .foregroundStyle(PortfolixTheme.text)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    onNewThread()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isInteractionEnabled && canStartNewThread
                                ? PortfolixTheme.text
                                : PortfolixTheme.disabled
                        )
                        .frame(width: 34, height: PortfolixLayout.glassControlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isInteractionEnabled || !canStartNewThread)
                .portfolixHelp(
                    canStartNewThread
                        ? localizedText("新建对话", "New Conversation", language: language)
                        : localizedText("当前已是空白对话", "Already on a new conversation", language: language)
                )

                Rectangle()
                    .fill(PortfolixTheme.border)
                    .frame(width: 0.5, height: 14)

                Button {
                    isThreadsPopoverPresented.toggle()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(threads.count > 1 ? PortfolixTheme.brandText : PortfolixTheme.text)
                        .frame(width: 34, height: PortfolixLayout.glassControlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .portfolixHelp(localizedText("历史话题（\(threads.count)）", "Conversations (\(threads.count))", language: language))
                .popover(isPresented: $isThreadsPopoverPresented, arrowEdge: .bottom) {
                    AIReportThreadsPopover(
                        threads: threads,
                        activeThreadID: activeThreadID,
                        canClearAll: canClearHistory || !threads.isEmpty,
                        isInteractionEnabled: isInteractionEnabled,
                        language: language,
                        onSelectThread: { id in
                            isThreadsPopoverPresented = false
                            onSelectThread(id)
                        },
                        onDeleteThread: onDeleteThread,
                        onClearAll: {
                            isThreadsPopoverPresented = false
                            clearHistory()
                        }
                    )
                }
            }
            .portfolixGlassControl()
        }
        .font(PortfolixTypography.caption)
        .foregroundStyle(PortfolixTheme.secondary)
        .padding(.horizontal, PortfolixSpacing.lg)
        .padding(.vertical, PortfolixSpacing.md)
    }
}

private struct AIReportUserBubble: View {
    let text: String
    let createdAt: Date
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
            Spacer(minLength: PortfolixSpacing.sm)

            AIReportMessageTimestamp(date: createdAt, language: language)
                .frame(width: AIReportChatRenderPolicy.timestampWidth, alignment: .trailing)

            Text(text)
                .font(PortfolixTypography.body)
                .foregroundStyle(PortfolixTheme.brandBubbleInk)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, PortfolixSpacing.lg)
                .padding(.vertical, PortfolixSpacing.md)
                .background(PortfolixTheme.brandBubbleGradient, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct AIReportAgentBubble<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: PortfolixSpacing.md) {
            ZStack {
                Circle()
                    .fill(PortfolixTheme.brandGradient)
                PortfolixBrandGlyph(size: 20)
            }
                .frame(width: 28, height: 28)
                .padding(.top, 2)

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: PortfolixSpacing.sm)
        }
    }
}

private struct AIReportFollowUpMessage: View {
    let text: String
    let citations: [AIMessageCitation]
    let createdAt: Date
    let language: AppLanguage
    let modelUsage: AIModelUsageSummary?
    let showsDisclaimer: Bool
    let activitySteps: [AIAgentActivityStep]
    let extractedMemories: [AIMemoryItem]
    let retryQuestion: String?
    let isFailure: Bool
    let canRetry: Bool
    let onRetry: ((String) -> Void)?
    let onUndoMemory: ((UUID) -> Void)?
    let onManageMemories: (() -> Void)?

    init(
        text: String,
        citations: [AIMessageCitation] = [],
        createdAt: Date,
        language: AppLanguage,
        modelUsage: AIModelUsageSummary? = nil,
        showsDisclaimer: Bool = true,
        activitySteps: [AIAgentActivityStep] = [],
        extractedMemories: [AIMemoryItem] = [],
        retryQuestion: String? = nil,
        isFailure: Bool = false,
        canRetry: Bool = false,
        onRetry: ((String) -> Void)? = nil,
        onUndoMemory: ((UUID) -> Void)? = nil,
        onManageMemories: (() -> Void)? = nil
    ) {
        self.text = text
        self.citations = citations
        self.createdAt = createdAt
        self.language = language
        self.modelUsage = modelUsage
        self.showsDisclaimer = showsDisclaimer
        self.activitySteps = activitySteps
        self.extractedMemories = extractedMemories
        self.retryQuestion = retryQuestion
        self.isFailure = isFailure
        self.canRetry = canRetry
        self.onRetry = onRetry
        self.onUndoMemory = onUndoMemory
        self.onManageMemories = onManageMemories
    }

    private var uniqueCitations: [AIMessageCitation] {
        var seen = Set<String>()
        return citations.filter { citation in
            guard let components = try? LLMBaseURLValidator.validatedComponents(from: citation.url),
                  components.scheme?.lowercased() == "https",
                  components.url != nil
            else { return false }
            return seen.insert(AISearchSourceIdentity.key(citation.url)).inserted
        }
    }

    var body: some View {
        let resolvedCitations = uniqueCitations
        VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
            if !activitySteps.isEmpty {
                AIReportUntimestampedAgentRow {
                    AIReportResearchTraceDisclosure(steps: activitySteps, language: language)
                }
            }

            AIReportTimestampedAgentRow(date: createdAt, language: language) {
                VStack(alignment: .leading, spacing: 0) {
                    AIReportCitedText(text: text, citations: citations)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !resolvedCitations.isEmpty {
                        Rectangle()
                            .fill(PortfolixTheme.border)
                            .frame(height: 0.5)
                            .padding(.top, PortfolixSpacing.md)
                            .padding(.bottom, PortfolixSpacing.xs)

                        AIReportFollowUpSourcesDisclosure(
                            citations: resolvedCitations,
                            language: language
                        )
                    }
                }
                .padding(.horizontal, PortfolixSpacing.lg)
                .padding(.vertical, PortfolixSpacing.md)
                .background(
                    isFailure ? PortfolixTheme.warnWash1 : PortfolixTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                        .strokeBorder(PortfolixTheme.cardBorder, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }

            if !extractedMemories.isEmpty, let onUndoMemory, let onManageMemories {
                AIReportExtractedMemoriesStrip(
                    memories: extractedMemories,
                    language: language,
                    onUndo: onUndoMemory,
                    onManage: onManageMemories
                )
                .padding(.trailing, AIReportChatRenderPolicy.timestampWidth + PortfolixSpacing.sm)
            }

            HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.md) {
                AIReportDisclaimer(language: language, modelUsage: modelUsage, showsDisclosure: showsDisclaimer)
                Spacer(minLength: PortfolixSpacing.sm)
                HStack(spacing: PortfolixSpacing.md) {
                    AIReportCopyActionButton(
                        textToCopy: text,
                        idleTitle: localizedText("复制", "Copy", language: language),
                        copiedTitle: localizedText("已复制", "Copied", language: language),
                        helpText: localizedText("复制此条回复", "Copy this reply", language: language)
                    )

                    if let retryQuestion, let onRetry, canRetry {
                        Button {
                            onRetry(retryQuestion)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .medium))
                                    .frame(width: 11, alignment: .center)
                                Text(
                                    isFailure
                                        ? localizedText("重试", "Retry", language: language)
                                        : localizedText("重新生成", "Regenerate", language: language)
                                )
                                .font(PortfolixTypography.caption)
                                .lineLimit(1)
                            }
                            .foregroundStyle(isFailure ? PortfolixTheme.brandText : PortfolixTheme.tertiary)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help(localizedText("重新发起这条提问", "Ask this question again", language: language))
                    }
                }
                .fixedSize()
            }
            .padding(.trailing, AIReportChatRenderPolicy.timestampWidth + PortfolixSpacing.sm)
        }
    }
}

private struct AIReportFollowUpSourcesDisclosure: View {
    let citations: [AIMessageCitation]
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private func domain(for rawURL: String) -> String {
        guard let host = URL(string: rawURL)?.host?.lowercased() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.brandText)
                    Text(localizedText("参考来源（\(citations.count)）", "Sources (\(citations.count))", language: language))
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.tertiary)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    ForEach(citations) { citation in
                        Button {
                            guard let components = try? LLMBaseURLValidator.validatedComponents(from: citation.url),
                                  components.scheme?.lowercased() == "https",
                                  let url = components.url
                            else { return }
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.sm) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(PortfolixTheme.brandText)
                                Text(AIUserFacingTextSanitizer.sanitize(citation.title))
                                    .font(PortfolixTypography.captionEmphasis)
                                    .foregroundStyle(PortfolixTheme.brandText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                let host = domain(for: citation.url)
                                if !host.isEmpty {
                                    Text(host)
                                        .font(PortfolixTypography.caption)
                                        .foregroundStyle(PortfolixTheme.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .portfolixHelp("\(citation.title)\n\(citation.url)")
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct AIReportCopyActionButton: View {
    let textToCopy: String
    let idleTitle: String
    let copiedTitle: String
    let helpText: String
    @State private var copied = false

    private var widestTitle: String {
        copiedTitle.count >= idleTitle.count ? copiedTitle : idleTitle
    }

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        } label: {
            ZStack(alignment: .trailing) {
                // Reserve constant width for the wider label so toggling never shifts sibling layout.
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 11, alignment: .center)
                    Text(widestTitle)
                        .font(PortfolixTypography.caption)
                        .lineLimit(1)
                }
                .hidden()

                HStack(spacing: 3) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 11, alignment: .center)
                    Text(copied ? copiedTitle : idleTitle)
                        .font(PortfolixTypography.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(copied ? PortfolixTheme.gainText : PortfolixTheme.tertiary)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(helpText)
    }
}

private struct AIReportCitedText: NSViewRepresentable {
    let text: String
    let citations: [AIMessageCitation]

    func makeNSView(context _: Context) -> AIReportCitationTextView {
        AIReportCitationTextView()
    }

    func updateNSView(_ nsView: AIReportCitationTextView, context _: Context) {
        nsView.update(text: text, citations: citations)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: AIReportCitationTextView,
        context _: Context
    ) -> CGSize? {
        nsView.fittingSize(for: proposal.width)
    }
}

@MainActor
final class AIReportCitationTextView: NSView, NSTextViewDelegate {
    private static let citationHelpKey = AIMessageMarkdownRenderer.citationHelpKey
    private let textView = AIReportCitationNSTextView(frame: .zero)
    private var citationHelpAnchors: [(range: NSRange, view: HoverHelpView)] = []
    private var renderedText = ""
    private var renderedCitations: [AIMessageCitation] = []
    private var renderedAppearanceName: NSAppearance.Name?
    private var lastMeasuredWidth: CGFloat = 320
    private var cachedHeight: (width: CGFloat, height: CGFloat)?
    var urlOpener: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.delegate = self
        textView.onOpenLink = { [weak self] link in
            self?.openCitation(link) ?? false
        }
        textView.linkTextAttributes = [
            .foregroundColor: citationColor,
            .cursor: NSCursor.pointingHand,
        ]
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    override func layout() {
        super.layout()
        textView.frame = bounds
        layoutCitationHelp()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let currentName = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        guard currentName != renderedAppearanceName, !renderedText.isEmpty else { return }
        let text = renderedText
        let citations = renderedCitations
        renderedText = ""
        update(text: text, citations: citations)
    }

    func update(text: String, citations: [AIMessageCitation]) {
        let currentAppearance = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        guard text != renderedText || citations != renderedCitations || currentAppearance != renderedAppearanceName else { return }
        renderedText = text
        renderedCitations = citations
        renderedAppearanceName = currentAppearance
        cachedHeight = nil

        let resolvedCitationColor = citationColor
        textView.linkTextAttributes = [
            .foregroundColor: resolvedCitationColor,
            .cursor: NSCursor.pointingHand,
        ]
        let attributed = AIMessageMarkdownRenderer.render(text, citations: citations, citationColor: resolvedCitationColor)
        textView.textStorage?.setAttributedString(attributed)
        for anchor in citationHelpAnchors {
            anchor.view.dismissTooltip()
            anchor.view.removeFromSuperview()
        }
        citationHelpAnchors.removeAll()
        attributed.enumerateAttribute(Self.citationHelpKey, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            guard let text = value as? String else { return }
            let anchor = HoverHelpView()
            anchor.text = text
            textView.addSubview(anchor)
            citationHelpAnchors.append((range, anchor))
        }
        textView.layoutManager?.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: attributed.length),
            actualCharacterRange: nil
        )
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func layoutCitationHelp() {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return }
        manager.ensureLayout(for: container)
        for anchor in citationHelpAnchors {
            let glyphs = manager.glyphRange(forCharacterRange: anchor.range, actualCharacterRange: nil)
            anchor.view.frame = manager.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        }
    }

    func fittingSize(for proposedWidth: CGFloat?) -> CGSize {
        let width = resolvedMeasurementWidth(proposedWidth)
        return CGSize(width: width, height: fittingHeight(for: width))
    }

    func fittingHeight(for width: CGFloat) -> CGFloat {
        let resolvedWidth = max(1, width)
        lastMeasuredWidth = resolvedWidth
        if let cachedHeight, abs(cachedHeight.width - resolvedWidth) < 0.5 {
            return cachedHeight.height
        }
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return 17
        }
        textView.frame.size.width = resolvedWidth
        textContainer.containerSize = NSSize(
            width: resolvedWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let height = max(17, ceil(usedHeight))
        cachedHeight = (width: resolvedWidth, height: height)
        return height
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: fittingHeight(for: lastMeasuredWidth)
        )
    }

    func textView(
        _: NSTextView,
        clickedOnLink link: Any,
        at _: Int
    ) -> Bool {
        openCitation(link)
    }

    func openCitation(_ link: Any) -> Bool {
        let rawURL: String
        switch link {
        case let url as URL:
            rawURL = url.absoluteString
        case let url as NSURL:
            rawURL = url.absoluteString ?? ""
        case let value as String:
            rawURL = value
        default:
            return false
        }
        guard let components = try? LLMBaseURLValidator.validatedComponents(from: rawURL),
              let url = components.url else { return false }
        return urlOpener(url)
    }

    private func resolvedMeasurementWidth(_ proposedWidth: CGFloat?) -> CGFloat {
        if let proposedWidth, proposedWidth.isFinite, proposedWidth > 1 {
            return proposedWidth
        }
        if bounds.width.isFinite, bounds.width > 1 {
            return bounds.width
        }
        return lastMeasuredWidth
    }

    private var citationColor: NSColor {
        let appearance = NSApp?.appearance ?? effectiveAppearance
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(PortfolixTheme.brandText).usingColorSpace(.sRGB) ?? NSColor(PortfolixTheme.brandText)
        }
        return resolved ?? NSColor(PortfolixTheme.brandText)
    }
}

@MainActor
private final class AIReportCitationNSTextView: NSTextView {
    var onOpenLink: ((Any) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        if let link = link(at: event.locationInWindow) {
            _ = onOpenLink?(link)
            return
        }
        super.mouseDown(with: event)
    }

    private func link(at windowPoint: NSPoint) -> Any? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else {
            return nil
        }
        let localPoint = convert(windowPoint, from: nil)
        let containerPoint = NSPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil)
    }
}

private struct AIReportTimestampedAgentRow<Content: View>: View {
    let date: Date
    let language: AppLanguage
    let content: Content

    init(date: Date, language: AppLanguage, @ViewBuilder content: () -> Content) {
        self.date = date
        self.language = language
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            AIReportMessageTimestamp(date: date, language: language)
                .frame(width: AIReportChatRenderPolicy.timestampWidth, alignment: .leading)
        }
    }
}

private struct AIReportUntimestampedAgentRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Color.clear
                .frame(width: AIReportChatRenderPolicy.timestampWidth)
        }
    }
}

private struct AIReportChatDateSeparator: View {
    let date: Date
    let language: AppLanguage

    var body: some View {
        Text(chatDateText(date, language: language))
            .font(PortfolixTypography.caption)
            .foregroundStyle(PortfolixTheme.tertiary)
            .lineLimit(1)
            .monospacedDigit()
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AIReportMessageTimestamp: View {
    let date: Date
    let language: AppLanguage

    var body: some View {
        Text(chatTimestampText(date, language: language))
            .font(PortfolixTypography.caption)
            .foregroundStyle(PortfolixTheme.tertiary)
            .lineLimit(1)
            .monospacedDigit()
            .textSelection(.enabled)
    }
}

enum AIReportReadiness: Equatable {
    case ready
    case missing
    case needsValidation
    case invalid

    static func credential(
        isConfigured: Bool,
        validationState: ProviderCredentialValidationState
    ) -> AIReportReadiness {
        guard isConfigured else { return .missing }
        return switch validationState {
        case .unknown: .needsValidation
        case .valid: .ready
        case .invalid: .invalid
        }
    }

    func apiStatusText(name: String, language: AppLanguage) -> String {
        switch self {
        case .ready:
            localizedText("\(name) 已验证", "\(name) validated", language: language)
        case .missing:
            localizedText("\(name) 未配置", "\(name) not configured", language: language)
        case .needsValidation:
            localizedText("\(name) 待验证", "\(name) needs validation", language: language)
        case .invalid:
            localizedText("\(name) 验证失败", "\(name) validation failed", language: language)
        }
    }

    func configurationGuidance(name: String, language: AppLanguage) -> String {
        switch self {
        case .ready:
            ""
        case .missing:
            localizedText(
                "请在设置中配置 \(name)",
                "Configure \(name) in Settings",
                language: language
            )
        case .needsValidation:
            localizedText(
                "请在设置中验证已配置的 \(name)",
                "Validate the configured \(name) in Settings",
                language: language
            )
        case .invalid:
            localizedText(
                "\(name) 验证失败，请检查配置后重试",
                "\(name) validation failed. Check the configuration and try again",
                language: language
            )
        }
    }

    func shortStatusText(language: AppLanguage) -> String {
        switch self {
        case .ready:
            localizedText("已验证", "Validated", language: language)
        case .missing:
            localizedText("未配置", "Not configured", language: language)
        case .needsValidation:
            localizedText("待验证", "Needs validation", language: language)
        case .invalid:
            localizedText("验证失败", "Validation failed", language: language)
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .missing: "minus.circle.fill"
        case .needsValidation: "exclamationmark.circle.fill"
        case .invalid: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: PortfolixTheme.gainText
        case .missing: PortfolixTheme.tertiary
        case .needsValidation: PortfolixTheme.warnText
        case .invalid: PortfolixTheme.lossText
        }
    }
}

private struct AIReportWelcomeMessage: View {
    let hasPositions: Bool
    let llmReadiness: AIReportReadiness
    let searchReadiness: AIReportReadiness
    let usesConnectedMode: Bool
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            Text(localizedText("结合当前持仓、历史收益与风险边界，为你生成深度组合诊断。", "Generate a portfolio review based on your holdings, performance, and risk limits.", language: language))
                .font(PortfolixTypography.body)
                .foregroundStyle(PortfolixTheme.text)

            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                AIReportReadinessRow(
                    readiness: hasPositions ? .ready : .missing,
                    text: hasPositions
                        ? localizedText("持仓数据已就绪", "Holdings ready", language: language)
                        : localizedText("尚未添加持仓", "No holdings added", language: language)
                )
                AIReportReadinessRow(
                    readiness: llmReadiness,
                    text: llmReadiness.apiStatusText(name: "DeepSeek API", language: language)
                )
                if usesConnectedMode {
                    AIReportReadinessRow(
                        readiness: searchReadiness,
                        text: searchReadiness.apiStatusText(name: localizedText("搜索 API", "Search API", language: language), language: language)
                    )
                }
            }
        }
        .padding(PortfolixSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PortfolixTheme.subtleFill, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                .strokeBorder(PortfolixTheme.cardBorder, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

private struct AIReportReadinessRow: View {
    let readiness: AIReportReadiness
    let text: String

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Image(systemName: readiness.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(readiness.color)
            Text(text)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondary)
        }
    }

}

private struct AIReportAgentProgressMessage: View {
    let status: AIAnalysisRunStatus
    let activityLines: [AIAgentActivityLine]
    var activitySteps: [AIAgentActivityStep] = []
    let language: AppLanguage

    var body: some View {
        AIReportProgressCard(
            title: localizedText("正在生成投研报告", "Generating investment report", language: language),
            activityLines: activityLines,
            activitySteps: activitySteps
        )
    }
}

private struct AIReportFollowUpProgressMessage: View {
    let progress: AIFollowUpProgress
    let activityLines: [AIAgentActivityLine]
    var activitySteps: [AIAgentActivityStep] = []
    let language: AppLanguage

    var body: some View {
        AIReportProgressCard(
            title: localizedText("正在分析你的问题", "Analyzing your question", language: language),
            activityLines: activityLines,
            activitySteps: activitySteps
        )
    }
}

struct AIReportProgressCard: View {
    let title: String
    let activityLines: [AIAgentActivityLine]
    let activitySteps: [AIAgentActivityStep]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSteps = true

    init(
        title: String,
        activityLines: [AIAgentActivityLine],
        activitySteps: [AIAgentActivityStep] = []
    ) {
        self.title = title
        self.activityLines = activityLines
        self.activitySteps = activitySteps
    }

    private var displayLine: AIAgentActivityLine {
        activityLines.last
            ?? AIAgentActivityLine(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                text: title
            )
    }

    private var headerTitle: String {
        activitySteps.isEmpty ? displayLine.text : title
    }

    private var activeStepNumber: Int {
        if let runningIndex = activitySteps.firstIndex(where: { $0.status == .running }) {
            return runningIndex + 1
        }
        return min(activitySteps.filter { $0.status == .completed }.count + 1, max(1, activitySteps.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: PortfolixSpacing.md) {
                AIReportAgentThinkingIcon(size: 36)

                Text(headerTitle)
                    .font(PortfolixTypography.labelEmphasis)
                    .foregroundStyle(PortfolixTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .portfolixNumericTransition(headerTitle)
                    .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .leading)
                    .clipped()

                if !activitySteps.isEmpty {
                    Button {
                        if reduceMotion {
                            showsSteps.toggle()
                        } else {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                showsSteps.toggle()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(activeStepNumber)/\(activitySteps.count)")
                                .font(PortfolixTypography.caption)
                                .foregroundStyle(PortfolixTheme.tertiary)
                                .portfolixNumericTransition("\(activeStepNumber)/\(activitySteps.count)")
                            Image(systemName: showsSteps ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(PortfolixTheme.tertiary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !activitySteps.isEmpty && showsSteps {
                Rectangle()
                    .fill(PortfolixTheme.border)
                    .frame(height: 0.5)
                    .padding(.vertical, 10)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activitySteps.enumerated()), id: \.element.id) { index, step in
                        AIReportActivityStepRow(
                            step: step,
                            showsTopConnector: index > 0,
                            showsBottomConnector: index < activitySteps.count - 1
                        )
                    }
                }
            }
        }
        .padding(.horizontal, PortfolixSpacing.lg)
        .padding(.vertical, PortfolixSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PortfolixTheme.subtleFill, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                .strokeBorder(PortfolixTheme.cardBorder, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

private struct AIReportActivityStepRow: View {
    let step: AIAgentActivityStep
    var showsTopConnector: Bool = false
    var showsBottomConnector: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(showsTopConnector ? PortfolixTheme.border : Color.clear)
                        .frame(width: 1)
                    Rectangle()
                        .fill(showsBottomConnector ? PortfolixTheme.border : Color.clear)
                        .frame(width: 1)
                }
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(symbolColor)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: step.status)
                    .padding(.vertical, 1)
                    .background(PortfolixTheme.subtleFill)
            }
            .frame(width: 14, height: 22)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(step.title)
                    .font(step.status == .running ? PortfolixTypography.captionEmphasis : PortfolixTypography.caption)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                if let detail = step.detail, !detail.isEmpty {
                    Text("· \(detail)")
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .portfolixNumericTransition(detail)
                }
            }
        }
    }

    private var symbolName: String {
        switch step.status {
        case .completed: "checkmark.circle.fill"
        case .running: "circle.inset.filled"
        case .pending: "circle"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var symbolColor: Color {
        switch step.status {
        case .completed: PortfolixTheme.gainText
        case .running: PortfolixTheme.brandText
        case .pending: PortfolixTheme.disabled
        case .failed: PortfolixTheme.warnText
        }
    }

    private var titleColor: Color {
        switch step.status {
        case .running: PortfolixTheme.text
        case .completed: PortfolixTheme.secondary
        case .pending: PortfolixTheme.tertiary
        case .failed: PortfolixTheme.warnText
        }
    }
}

private struct AIReportResearchTraceDisclosure: View {
    let steps: [AIAgentActivityStep]
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var summaryText: String {
        let completed = steps.filter { $0.status == .completed }.count
        let localUsed = steps.contains { $0.kind == .localData }
        let webUsed = steps.contains { $0.kind == .webSearch }
        var tags: [String] = []
        if localUsed {
            tags.append(localizedText("本地账本", "Local ledger", language: language))
        }
        if webUsed {
            tags.append(localizedText("联网资料", "Web sources", language: language))
        }
        let stepCount = localizedText("已完成 \(max(completed, steps.count)) 步投研", "\(max(completed, steps.count)) research steps", language: language)
        if tags.isEmpty { return stepCount }
        return "\(stepCount)（\(tags.joined(separator: " · "))）"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.gainText)
                    Text(summaryText)
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.tertiary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.tertiary)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        AIReportActivityStepRow(
                            step: step,
                            showsTopConnector: index > 0,
                            showsBottomConnector: index < steps.count - 1
                        )
                    }
                }
                .padding(.horizontal, PortfolixSpacing.md)
                .padding(.vertical, PortfolixSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    PortfolixTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                        .strokeBorder(PortfolixTheme.cardBorder, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct AIReportStaticStatusMessage: View {
    let status: AIAnalysisRunStatus
    let hasPositions: Bool
    let llmReadiness: AIReportReadiness
    let searchReadiness: AIReportReadiness
    let usesConnectedMode: Bool
    let language: AppLanguage

    var body: some View {
        HStack(spacing: PortfolixSpacing.md) {
            StatusSymbolIcon(symbol: symbol, color: color, background: symbolBackground)
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(title)
                    .font(PortfolixTypography.subheading)
                    .foregroundStyle(PortfolixTheme.text)
                Text(detail)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
            }
        }
        .padding(PortfolixSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PortfolixTheme.subtleFill, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                .strokeBorder(PortfolixTheme.cardBorder, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var title: String {
        if !hasPositions {
            return localizedText("等待持仓数据", "Waiting for holdings", language: language)
        }
        if hasInvalidRequiredCredential {
            return localizedText("API 验证失败", "API validation failed", language: language)
        }
        if llmReadiness != .ready || (usesConnectedMode && searchReadiness != .ready) {
            return localizedText("需要完成 API 配置", "API configuration required", language: language)
        }
        return status.title(language: language)
    }

    private var detail: String {
        if !hasPositions {
            return localizedText("添加持仓后即可生成分析", "Add holdings to generate an analysis", language: language)
        }
        if llmReadiness != .ready {
            return llmReadiness.configurationGuidance(name: "DeepSeek API", language: language)
        }
        if usesConnectedMode, searchReadiness != .ready {
            return searchReadiness.configurationGuidance(
                name: localizedText("搜索 API", "Search API", language: language),
                language: language
            )
        }
        return localizedText("请检查配置或稍后重试", "Check settings or try again later", language: language)
    }

    private var symbol: String {
        if hasInvalidRequiredCredential {
            return "xmark.circle.fill"
        }
        return switch status {
        case .failed:
            "exclamationmark.triangle.fill"
        default:
            "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        if hasInvalidRequiredCredential {
            return PortfolixTheme.lossText
        }
        return switch status {
        case .failed:
            PortfolixTheme.lossText
        default:
            PortfolixTheme.warnText
        }
    }

    private var symbolBackground: Color {
        if hasInvalidRequiredCredential {
            return PortfolixTheme.lossWash1
        }
        if case .failed = status { return PortfolixTheme.lossWash1 }
        return PortfolixTheme.warnWash1
    }

    private var hasInvalidRequiredCredential: Bool {
        llmReadiness == .invalid || (usesConnectedMode && searchReadiness == .invalid)
    }
}

private struct AIReportChatReport: View {
    let report: AIAnalysisReport
    let run: AIAnalysisRun
    let language: AppLanguage
    let modelUsage: AIModelUsageSummary?
    var activitySteps: [AIAgentActivityStep] = []
    var positions: [Position] = []
    var isInteractive: Bool = true
    var onAskFollowUp: ((String) -> Void)? = nil
    var onPrefillFollowUp: ((String) -> Void)? = nil
    var onOpenHolding: ((AIAssetAlert) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            HStack(spacing: PortfolixSpacing.sm) {
                CapsuleLabel(title: localizedText("分析报告", "Analysis Report", language: language), color: PortfolixTheme.brandText, symbol: "doc.text.magnifyingglass")
                if run.usedFallback {
                    CapsuleLabel(title: localizedText("本地简报", "Local Summary", language: language), color: PortfolixTheme.warnText, symbol: "exclamationmark.triangle.fill")
                } else if run.qualityStatus == "needs_review" {
                    CapsuleLabel(
                        title: localizedText("建议复核数据", "Review Suggested", language: language),
                        color: PortfolixTheme.warnText,
                        symbol: "checkmark.shield"
                    )
                    .portfolixHelp(
                        localizedText(
                            "部分推导数字或结论缺少直接本地指标绑定，建议结合持仓明细与参考来源核对。",
                            "Some derived figures or statements were not directly bound to local ledger metrics. Verify against holdings and sources.",
                            language: language
                        )
                    )
                }
                Spacer()
                AIReportCopyActionButton(
                    textToCopy: plainTextExport,
                    idleTitle: localizedText("复制报告", "Copy", language: language),
                    copiedTitle: localizedText("已复制", "Copied", language: language),
                    helpText: localizedText("复制报告摘要与建议", "Copy report summary and recommendations", language: language)
                )
                .padding(.trailing, AIReportChatRenderPolicy.timestampWidth + PortfolixSpacing.sm)
            }

            if !activitySteps.isEmpty {
                AIReportUntimestampedAgentRow {
                    AIReportResearchTraceDisclosure(steps: activitySteps, language: language)
                }
            }

            if run.usedFallback {
                AIReportUntimestampedAgentRow {
                    HStack(alignment: .top, spacing: PortfolixSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PortfolixTheme.warnText)
                            .padding(.top, 2)
                        Text(
                            run.fallbackReason
                                ?? localizedText(
                                    "在线模型暂未完成响应，已基于本地持仓规则生成摘要。",
                                    "Cloud analysis didn't finish, so a local rule-based summary was generated.",
                                    language: language
                                )
                        )
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PortfolixSpacing.md)
                    .padding(.vertical, PortfolixSpacing.sm)
                    .background(
                        PortfolixTheme.warnWash1,
                        in: RoundedRectangle(
                            cornerRadius: PortfolixRadius.compact,
                            style: .continuous
                        )
                    )
                }

                if let diagnostic = run.diagnostic {
                    AIReportUntimestampedAgentRow {
                        AIAnalysisDiagnosticCard(diagnostic: diagnostic, language: language)
                    }
                }
            }

            AIReportTimestampedAgentRow(date: report.generatedAt, language: language) {
                AIReportChatSection(title: localizedText("核心结论", "Core Takeaway", language: language), symbol: "target") {
                    Text(AIUserFacingTextSanitizer.sanitize(report.summary))
                        .font(PortfolixTypography.body)
                        .lineSpacing(4)
                        .foregroundStyle(PortfolixTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AIUserFacingTextSanitizer.sanitize(report.healthScoreExplanation))
                        .font(PortfolixTypography.body)
                        .lineSpacing(4)
                        .foregroundStyle(PortfolixTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actions = report.rebalanceActions, !actions.isEmpty {
                AIReportTimestampedAgentRow(date: report.generatedAt, language: language) {
                    AIReportChatSection(title: localizedText("投资组合建议", "Portfolio Recommendations", language: language), symbol: "arrow.triangle.2.circlepath") {
                        ForEach(actions) { action in
                            AIReportRebalanceMessageRow(action: action)
                        }
                    }
                }
            }

            AIReportTimestampedAgentRow(date: report.generatedAt, language: language) {
                AIReportChatSection(title: localizedText("重点关注", "Watchlist", language: language), symbol: "scope") {
                    if report.assetAlerts.isEmpty {
                        AIReportBullet(
                            title: localizedText("暂无需要单独关注的资产", "No individual holdings require special attention", language: language),
                            body: localizedText(
                                "当前持仓结构整体均衡，暂无异常标的需要单独预警；建议持续关注集中度与币种敞口变化。",
                                "No individual positions require immediate attention. Continue monitoring concentration, currency exposure, and recent performance.",
                                language: language
                            ),
                            color: PortfolixTheme.secondary,
                            symbol: "checkmark.circle.fill"
                        )
                    } else {
                        ForEach(report.assetAlerts) { alert in
                            let hasMatchingHolding = positions.contains {
                                (!alert.symbol.isEmpty && $0.symbol.caseInsensitiveCompare(alert.symbol) == .orderedSame)
                                    || (!alert.assetName.isEmpty && $0.name.caseInsensitiveCompare(alert.assetName) == .orderedSame)
                            }
                            AIReportAssetAlertMessageRow(
                                alert: alert,
                                language: language,
                                canOpenHolding: hasMatchingHolding && onOpenHolding != nil,
                                canAskFollowUp: isInteractive && onAskFollowUp != nil,
                                onOpenHolding: { onOpenHolding?(alert) },
                                onAskFollowUp: {
                                    let target = alert.assetName.isEmpty ? alert.symbol : alert.assetName
                                    let prompt = localizedText(
                                        "请深入分析 \(target) 当前的风险、催化剂和仓位应对方案。",
                                        "Analyze the key risks, catalysts, and positioning options for \(target).",
                                        language: language
                                    )
                                    onAskFollowUp?(prompt)
                                }
                            )
                        }
                    }
                }
            }

            if !report.riskItems.isEmpty {
                AIReportTimestampedAgentRow(date: report.generatedAt, language: language) {
                    AIReportChatSection(title: localizedText("风险因素", "Risk Factors", language: language), symbol: "exclamationmark.triangle") {
                        ForEach(report.riskItems) { item in
                            let sanitizedEvidence = AIUserFacingTextSanitizer.sanitize(item.evidence)
                            let sanitizedImpact = AIUserFacingTextSanitizer.sanitize(item.impact)
                            let combinedBody = sanitizedEvidence.isEmpty
                                ? sanitizedImpact
                                : "\(sanitizedEvidence)\n\(sanitizedImpact)"
                            AIReportBullet(
                                title: AIUserFacingTextSanitizer.sanitize(item.title),
                                body: combinedBody,
                                color: color(for: item.severity),
                                symbol: item.severity == "high" ? "exclamationmark.octagon.fill" : "exclamationmark.circle.fill"
                            )
                        }
                    }
                }
            }

            if !report.questionsToConsider.isEmpty || !report.limitations.isEmpty || !report.dataQualityNotes.isEmpty {
                AIReportTimestampedAgentRow(date: report.generatedAt, language: language) {
                    AIReportChatSection(title: localizedText("后续复核", "Follow-up Review", language: language), symbol: "questionmark.circle") {
                        ForEach(Array(report.questionsToConsider.enumerated()), id: \.offset) { _, rawQuestion in
                            let question = AIUserFacingTextSanitizer.sanitize(rawQuestion)
                            if let onPrefillFollowUp, isInteractive {
                                Button {
                                    onPrefillFollowUp(question)
                                } label: {
                                    HStack(alignment: .top, spacing: PortfolixSpacing.sm) {
                                        Image(systemName: "questionmark.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(PortfolixTheme.brandText)
                                            .frame(width: 18)
                                            .padding(.top, 2)
                                        Text(question)
                                            .font(PortfolixTypography.labelEmphasis)
                                            .lineSpacing(3)
                                            .foregroundStyle(PortfolixTheme.text)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        HStack(spacing: 2) {
                                            Text(localizedText("回复", "Reply", language: language))
                                                .font(PortfolixTypography.captionEmphasis)
                                            Image(systemName: "arrow.turn.down.left")
                                                .font(.system(size: 9, weight: .semibold))
                                        }
                                        .foregroundStyle(PortfolixTheme.brandText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(PortfolixTheme.brandWash, in: Capsule())
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(localizedText("点击带入输入框，填写你的想法后发送", "Click to reply in the input box", language: language))
                            } else {
                                AIReportBullet(title: question, body: nil, color: PortfolixTheme.brandText, symbol: "questionmark.circle.fill")
                            }
                        }
                        ForEach(Array(report.dataQualityNotes.enumerated()), id: \.offset) { _, note in
                            AIReportBullet(title: AIUserFacingTextSanitizer.sanitize(note), body: nil, color: PortfolixTheme.warnText, symbol: "doc.badge.clock")
                        }
                        ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, limitation in
                            AIReportBullet(title: AIUserFacingTextSanitizer.sanitize(limitation), body: nil, color: PortfolixTheme.secondary, symbol: "info.circle.fill")
                        }
                    }
                }
            }

            if !report.sources.isEmpty {
                AIReportTimestampedAgentRow(date: report.generatedAt, language: language) {
                    AIReportChatSection(title: localizedText("参考来源", "Sources", language: language), symbol: "link") {
                        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                            ForEach(report.sources) { source in
                                Button {
                                    guard let components = try? LLMBaseURLValidator.validatedComponents(from: source.url),
                                          components.scheme?.lowercased() == "https",
                                          let url = components.url
                                    else { return }
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.sm) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(PortfolixTheme.brandText)
                                        Text(AIUserFacingTextSanitizer.sanitize(source.title))
                                            .font(PortfolixTypography.captionEmphasis)
                                            .foregroundStyle(PortfolixTheme.brandText)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Text(source.domain)
                                            .font(PortfolixTypography.caption)
                                            .foregroundStyle(PortfolixTheme.tertiary)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(source.url)
                            }
                        }
                    }
                }
            }

            AIReportDisclaimer(language: language, modelUsage: modelUsage)
                .padding(.horizontal, 0)
        }
        .textSelection(.enabled)
    }

    private var plainTextExport: String {
        var lines: [String] = [
            AIUserFacingTextSanitizer.sanitize(report.summary),
            AIUserFacingTextSanitizer.sanitize(report.healthScoreExplanation),
        ]
        if let actions = report.rebalanceActions, !actions.isEmpty {
            lines.append("")
            lines.append(localizedText("投资组合建议：", "Portfolio Recommendations:", language: language))
            for action in actions {
                lines.append("- \(AIUserFacingTextSanitizer.sanitize(action.title))：\(AIUserFacingTextSanitizer.sanitize(action.rationale))")
            }
        }
        if !report.riskItems.isEmpty {
            lines.append("")
            lines.append(localizedText("风险因素：", "Risk Factors:", language: language))
            for item in report.riskItems {
                lines.append("- \(AIUserFacingTextSanitizer.sanitize(item.title))：\(AIUserFacingTextSanitizer.sanitize(item.evidence)) \(AIUserFacingTextSanitizer.sanitize(item.impact))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func color(for severity: String) -> Color {
        switch severity {
        case "high": PortfolixTheme.lossText
        case "warning": PortfolixTheme.warnText
        default: PortfolixTheme.brandText
        }
    }
}

private struct AIAnalysisDiagnosticCard: View {
    let diagnostic: AIAnalysisDiagnostic
    let language: AppLanguage
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            HStack(spacing: PortfolixSpacing.sm) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.warnText)
                Text(localizedText("诊断信息", "Diagnostics", language: language))
                    .font(PortfolixTypography.subheading)
                    .foregroundStyle(PortfolixTheme.text)
                Spacer()
                Button(action: copyDiagnostic) {
                    Label(
                        copied
                            ? localizedText("已复制", "Copied", language: language)
                            : localizedText("复制", "Copy", language: language),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .font(PortfolixTypography.captionEmphasis)
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel(localizedText("复制脱敏诊断信息", "Copy redacted diagnostic details", language: language))
            }

            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                diagnosticRow(
                    localizedText("阶段", "Stage", language: language),
                    "\(diagnostic.stageTitle) · \(diagnostic.stageID)"
                )
                diagnosticRow(localizedText("类型", "Type", language: language), diagnostic.errorKind)
                diagnosticRow(
                    localizedText("模型", "Model", language: language),
                    "\(diagnostic.provider) · \(diagnostic.model)"
                )
                diagnosticRow(
                    localizedText("ID", "ID", language: language),
                    diagnostic.displayID
                )
                diagnosticRow(
                    localizedText("时间", "Time", language: language),
                    diagnosticTimestampText(diagnostic.finishedAt)
                )
                diagnosticRow(localizedText("错误摘要", "Error", language: language), diagnostic.errorSummary)
                diagnosticRow(localizedText("建议", "Suggestion", language: language), diagnostic.recoveryHint)
            }
        }
        .padding(PortfolixSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PortfolixTheme.warnWash1, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: PortfolixSpacing.sm) {
            Text(title)
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(PortfolixTheme.tertiary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyDiagnostic() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnostic.copyText(language: language), forType: .string)
        copied = true
    }
}

private struct AIReportChatSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            SectionHeader(title: title, symbol: symbol)
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                content
            }
        }
        .padding(PortfolixSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PortfolixTheme.subtleFill, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                .strokeBorder(PortfolixTheme.cardBorder, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

private struct AIReportRebalanceMessageRow: View {
    let action: AIRebalanceAction

    var body: some View {
        HStack(alignment: .top, spacing: PortfolixSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(AIUserFacingTextSanitizer.sanitize(action.title))
                    .font(PortfolixTypography.subheading)
                    .foregroundStyle(PortfolixTheme.text)
                if let assetName = action.assetName, !assetName.isEmpty {
                    Text([assetName, action.symbol].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(PortfolixTypography.captionEmphasis)
                        .foregroundStyle(PortfolixTheme.brandText)
                }
                Text(recommendationDetails(for: action))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var symbol: String {
        switch action.action {
        case "buy", "increase": "arrow.up.right.circle.fill"
        case "sell", "exit": "xmark.circle.fill"
        case "reduce": "arrow.down.right.circle.fill"
        case "hold": "pause.circle.fill"
        case "review_reduce": "arrow.down.right.circle.fill"
        case "review_replenish": "plus.circle.fill"
        case "rebalance": "arrow.triangle.2.circlepath.circle.fill"
        case "maintain": "checkmark.circle.fill"
        default: "eye.circle.fill"
        }
    }

    private var color: Color {
        switch action.action {
        case "buy", "increase": PortfolixTheme.gainText
        case "sell", "exit": PortfolixTheme.lossText
        case "reduce": PortfolixTheme.warnText
        case "hold": PortfolixTheme.brandText
        case "review_reduce": PortfolixTheme.warnText
        case "review_replenish": PortfolixTheme.gainText
        case "rebalance": PortfolixTheme.brandText
        case "maintain": PortfolixTheme.gainText
        default: PortfolixTheme.secondary
        }
    }
}

private struct AIReportAssetAlertMessageRow: View {
    let alert: AIAssetAlert
    let language: AppLanguage
    var canOpenHolding: Bool = false
    var canAskFollowUp: Bool = false
    var onOpenHolding: (() -> Void)? = nil
    var onAskFollowUp: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: PortfolixSpacing.sm) {
            Image(systemName: risk.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(risk.color)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.sm) {
                    Text(AIUserFacingTextSanitizer.sanitize(alert.title))
                        .font(PortfolixTypography.subheading)
                        .foregroundStyle(PortfolixTheme.text)
                }
                if !assetLabel.isEmpty {
                    Text(assetLabel)
                        .font(PortfolixTypography.captionEmphasis)
                        .foregroundStyle(PortfolixTheme.brandText)
                }
                Text(AIUserFacingTextSanitizer.sanitize(alert.reason))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !alert.sourceDomains.isEmpty {
                    Text(alert.sourceDomains.prefix(3).joined(separator: " · "))
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.tertiary)
                }
                if canOpenHolding || canAskFollowUp {
                    HStack(spacing: PortfolixSpacing.md) {
                        if canOpenHolding, let onOpenHolding {
                            Button(action: onOpenHolding) {
                                Label(
                                    localizedText("查看持仓", "View Holding", language: language),
                                    systemImage: "arrow.right.circle"
                                )
                                .font(PortfolixTypography.captionEmphasis)
                                .foregroundStyle(PortfolixTheme.brandText)
                            }
                            .buttonStyle(.plain)
                        }
                        if canAskFollowUp, let onAskFollowUp {
                            Button(action: onAskFollowUp) {
                                Label(
                                    localizedText("深入追问", "Ask AI", language: language),
                                    systemImage: "sparkles"
                                )
                                .font(PortfolixTypography.captionEmphasis)
                                .foregroundStyle(PortfolixTheme.brandText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var assetLabel: String {
        [alert.assetName, alert.symbol]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var risk: (color: Color, symbol: String) {
        let text = "\(alert.title) \(alert.reason)".lowercased()
        let highRiskHints = ["高风险", "剧烈", "回撤", "监管", "亏损", "集中", "超限", "high", "drawdown", "regulatory", "concentration"]
        let isHigh = highRiskHints.contains { text.localizedCaseInsensitiveContains($0) }
        if isHigh {
            return (
                PortfolixTheme.lossText,
                "exclamationmark.triangle.fill"
            )
        }
        return (
            PortfolixTheme.warnText,
            "exclamationmark.circle.fill"
        )
    }
}

private struct AIReportComposerReviewRequest: Equatable {
    let id = UUID()
    let question: String
}

private struct AIReportChatComposer: View {
    let canGenerate: Bool
    let canSendFollowUp: Bool
    let isAwaitingResponse: Bool
    let hasReport: Bool
    @Binding var selectedModel: String
    let availableModels: [String]
    @Binding var selectedAnalysisMode: SmartAnalysisMode
    let fallbackModelName: String?
    let language: AppLanguage
    @Binding var reviewQuestionRequest: AIReportComposerReviewRequest?
    let generate: () -> Void
    let cancel: () -> Void
    let sendFollowUp: (String) -> Void
    @State private var draftBuffer = AIReportComposerDraftBuffer()
    @State private var hasDraftText = false
    @State private var draftRevision = 0
    @State private var isSubmitting = false
    @State private var isComposerFocused = false
    @State private var focusRequestID = 0
    @State private var isReviewExpanded = false
    @State private var editorContentHeight: CGFloat = AIReportComposerMetrics.defaultEditorHeight
    @StateObject private var voiceRecorder = HoldingVoiceRecorder()

    private var displayedModelName: String {
        let trimmed = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let fallback = fallbackModelName, !fallback.isEmpty { return fallback }
        return localizedText("未配置模型", "No Model", language: language)
    }

    private var minimumEditorHeight: CGFloat {
        isReviewExpanded ? AIReportComposerMetrics.reviewEditorMinHeight : AIReportComposerMetrics.defaultEditorHeight
    }

    private var displayedEditorHeight: CGFloat {
        min(
            AIReportComposerMetrics.maximumEditorHeight,
            max(minimumEditorHeight, editorContentHeight)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AIReportComposerTextInput(
                placeholder: placeholder,
                text: draftTextBinding,
                minHeight: minimumEditorHeight,
                maxHeight: AIReportComposerMetrics.maximumEditorHeight,
                focusRequestID: focusRequestID,
                isFocused: $isComposerFocused,
                measuredHeight: $editorContentHeight,
                onSubmit: { queueFollowUpSubmission() }
            )
            .frame(maxWidth: .infinity)
            .frame(height: displayedEditorHeight)
            .opacity(isVoiceActive ? 0 : 1)
            .allowsHitTesting(!isVoiceActive)
            .overlay {
                if isVoiceActive {
                    AIReportVoiceListeningOverlay(
                        waveformBuffer: voiceRecorder.waveformBuffer,
                        isTranscribing: voiceRecorder.isTranscribing,
                        language: language
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: isVoiceActive)
            .padding(.horizontal, PortfolixSpacing.md)
            .padding(.top, 10)
            .padding(.bottom, 4)

            HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
                HStack(spacing: PortfolixSpacing.sm) {
                    PortfolixGlassMenuPicker(
                        title: displayedModelName,
                        selection: $selectedModel,
                        options: availableModels,
                        optionTitle: { $0 },
                        selectionTitle: displayedModelName,
                        height: 28
                    )
                    .disabled(isAwaitingResponse || availableModels.isEmpty)

                    PortfolixGlassMenuPicker(
                        title: selectedAnalysisMode.title(language: language),
                        selection: $selectedAnalysisMode,
                        options: SmartAnalysisMode.availableCases,
                        optionTitle: { $0.title(language: language) },
                        selectionTitle: selectedAnalysisMode.title(language: language),
                        height: 28
                    )
                    .disabled(isAwaitingResponse)
                }

                Spacer(minLength: PortfolixSpacing.sm)

                Button {
                    isComposerFocused = false
                    voiceRecorder.toggle()
                } label: {
                    Image(systemName: isVoiceActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: isVoiceActive ? 10 : 12, weight: .semibold))
                        .foregroundStyle(isVoiceActive ? PortfolixTheme.brandText : PortfolixTheme.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            isVoiceActive ? PortfolixTheme.brandWash : Color.clear,
                            in: Circle()
                        )
                        .overlay {
                            if isVoiceActive {
                                Circle()
                                    .strokeBorder(PortfolixTheme.brandFocus.opacity(0.35), lineWidth: 0.5)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isAwaitingResponse)
                .opacity(isAwaitingResponse ? 0.4 : 1)
                .accessibilityLabel(voiceButtonHelp)
                .portfolixHelp(voiceButtonHelp)

                AIReportComposerActionButton(
                    mode: composerAction,
                    title: composerAction.title(hasReport: hasReport, language: language),
                    isEnabled: canPerformComposerAction
                ) {
                    guard canPerformComposerAction else { return }
                    switch composerAction {
                    case .send: queueFollowUpSubmission()
                    case .analyze: generate()
                    case .stop: cancel()
                    }
                }
            }
            .padding(.leading, PortfolixSpacing.md)
            .padding(.trailing, PortfolixSpacing.sm)
            .padding(.top, 2)
            .padding(.bottom, PortfolixSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .background(
            PortfolixTheme.raised,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isVoiceActive
                        ? PortfolixTheme.brandFocus.opacity(0.45)
                        : isComposerFocused
                            ? PortfolixTheme.borderStrong.opacity(0.45)
                            : PortfolixTheme.controlBorder,
                    lineWidth: isVoiceActive || isComposerFocused ? 0.75 : 0.5
                )
                .animation(.easeOut(duration: 0.14), value: isComposerFocused)
                .animation(.easeOut(duration: 0.14), value: isVoiceActive)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.14), value: displayedEditorHeight)
        .padding(.horizontal, PortfolixLayout.chatComposerHorizontalInset)
        .padding(.top, PortfolixLayout.chatComposerTopInset)
        .padding(.bottom, PortfolixLayout.chatComposerBottomInset)
        .onAppear { configureVoiceRecorder() }
        .onChange(of: language) { _, _ in configureVoiceRecorder() }
        .onChange(of: reviewQuestionRequest) { _, request in
            guard let request else { return }
            draftBuffer.appendReviewQuestion(request.question, language: language)
            hasDraftText = draftBuffer.hasContent
            isReviewExpanded = true
            draftRevision &+= 1
            focusRequestID &+= 1
            reviewQuestionRequest = nil
        }
        .onChange(of: isAwaitingResponse) { wasAwaitingResponse, isAwaitingResponse in
            guard AIReportComposerFocusPolicy.shouldRestoreFocus(
                wasAwaitingResponse: wasAwaitingResponse,
                isAwaitingResponse: isAwaitingResponse,
                isVoiceActive: isVoiceActive
            ) else { return }
            Task { @MainActor in
                await Task.yield()
                guard !self.isAwaitingResponse, !isVoiceActive else { return }
                focusRequestID &+= 1
            }
        }
        .onDisappear { voiceRecorder.blur() }
        .alert(
            localizedText("语音输入", "Voice Input", language: language),
            isPresented: Binding(
                get: { voiceRecorder.errorMessage != nil },
                set: { if !$0 { voiceRecorder.errorMessage = nil } }
            )
        ) {
            Button(localizedText("好", "OK", language: language)) {
                voiceRecorder.errorMessage = nil
            }
        } message: {
            Text(voiceRecorder.errorMessage ?? "")
        }
    }

    private var placeholder: String {
        if isAwaitingResponse {
            return localizedText("正在生成分析…", "Generating response…", language: language)
        }
        return localizedText("围绕持仓、风险或市场变化提问…", "Ask about your portfolio, risks, or markets…", language: language)
    }

    private var canSubmitFollowUp: Bool {
        hasDraftText && AIReportComposerAction.send.isEnabled(
            canGenerate: canGenerate, canSendFollowUp: canSendFollowUp,
            isSubmitting: isSubmitting, isAwaitingResponse: isAwaitingResponse, isVoiceActive: isVoiceActive
        )
    }

    private var composerAction: AIReportComposerAction {
        isAwaitingResponse ? .stop : AIReportComposerAction(hasDraftText: hasDraftText)
    }

    private var canPerformComposerAction: Bool {
        composerAction.isEnabled(
            canGenerate: canGenerate, canSendFollowUp: canSendFollowUp,
            isSubmitting: isSubmitting, isAwaitingResponse: isAwaitingResponse, isVoiceActive: isVoiceActive
        )
    }

    private var isVoiceActive: Bool {
        voiceRecorder.isRecording || voiceRecorder.isFinishing
    }

    private var voiceButtonHelp: String {
        localizedText(
            isVoiceActive ? "结束语音输入。" : "开始语音输入，也可按住 F1。",
            isVoiceActive ? "Finish voice input." : "Start voice input, or hold F1.",
            language: language
        )
    }

    private var draftTextBinding: Binding<String> {
        let _ = draftRevision
        return Binding(
            get: { draftBuffer.text },
            set: { value in
                draftBuffer.replace(with: value)
                let containsText = draftBuffer.hasContent
                if hasDraftText != containsText {
                    hasDraftText = containsText
                }
                if !containsText {
                    isReviewExpanded = false
                }
            }
        )
    }

    private func configureVoiceRecorder() {
        voiceRecorder.focus(
            numeric: false,
            english: language == .english,
            shortcut: .f1
        ) { value in
            isComposerFocused = false
            draftBuffer.replace(with: value)
            hasDraftText = draftBuffer.hasContent
            draftRevision &+= 1
        }
    }

    private func queueFollowUpSubmission() {
        guard canSubmitFollowUp,
              let question = draftBuffer.submissionText else { return }

        // Let AppKit finish the current text-input command before the chat tree changes.
        isSubmitting = true
        isComposerFocused = false
        draftBuffer.clear()
        hasDraftText = false
        isReviewExpanded = false
        editorContentHeight = AIReportComposerMetrics.defaultEditorHeight
        draftRevision &+= 1
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            isSubmitting = false
            sendFollowUp(question)
        }
    }
}

private struct AIReportVoiceListeningOverlay: View {
    let waveformBuffer: HoldingVoiceWaveformBuffer
    let isTranscribing: Bool
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseExpanded = false

    private var statusTitle: String {
        if isTranscribing {
            return localizedText("正在识别…", "Transcribing…", language: language)
        }
        return localizedText("正在聆听…", "Listening…", language: language)
    }

    var body: some View {
        HStack(spacing: PortfolixSpacing.md) {
            HStack(spacing: PortfolixSpacing.sm) {
                ZStack {
                    if !reduceMotion {
                        Circle()
                            .fill(PortfolixTheme.brandFocus.opacity(pulseExpanded ? 0.0 : 0.28))
                            .frame(width: 14, height: 14)
                            .scaleEffect(pulseExpanded ? 1.25 : 0.65)
                    }
                    Circle()
                        .fill(PortfolixTheme.brandFocus)
                        .frame(width: 6, height: 6)
                }
                .frame(width: 14, height: 14)

                Text(statusTitle)
                    .font(PortfolixTypography.labelEmphasis)
                    .foregroundStyle(PortfolixTheme.brandText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isTranscribing)
            }

            HoldingVoiceWaveform(
                buffer: waveformBuffer,
                isTranscribing: isTranscribing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: false)) {
                pulseExpanded = true
            }
        }
    }
}

struct AIReportComposerTextInput: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = AIReportComposerMetrics.defaultEditorHeight
    var maxHeight: CGFloat = AIReportComposerMetrics.maximumEditorHeight
    var focusRequestID: Int = 0
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat
    var onSubmit: () -> Void = {}

    init(
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat = AIReportComposerMetrics.defaultEditorHeight,
        maxHeight: CGFloat = AIReportComposerMetrics.maximumEditorHeight,
        focusRequestID: Int = 0,
        isFocused: Binding<Bool> = .constant(false),
        measuredHeight: Binding<CGFloat> = .constant(AIReportComposerMetrics.defaultEditorHeight),
        onSubmit: @escaping () -> Void = {}
    ) {
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.focusRequestID = focusRequestID
        self._isFocused = isFocused
        self._measuredHeight = measuredHeight
        self.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = ComposerNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 2
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        if #available(macOS 15.2, *) {
            textView.writingToolsBehavior = .none
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.placeholderText = placeholder
        textView.string = text
        textView.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSubmit()
        }
        textView.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.updateFocus(focused)
        }
        textView.onBoundsWidthChange = { [weak coordinator = context.coordinator] in
            coordinator?.recalculateHeight()
        }

        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.lastFocusRequestID = focusRequestID
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.recalculateHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let boundsChanged = context.coordinator.parent.minHeight != minHeight
            || context.coordinator.parent.maxHeight != maxHeight
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.placeholderText != placeholder {
            textView.placeholderText = placeholder
            textView.needsDisplay = true
        }
        var textChanged = false
        if !textView.hasMarkedText(), textView.string != text {
            textChanged = true
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            let end = (text as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            context.coordinator.isProgrammaticUpdate = false
            textView.needsDisplay = true
        }
        if focusRequestID != context.coordinator.lastFocusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                let end = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            }
        }
        if textChanged || boundsChanged {
            context.coordinator.recalculateHeight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AIReportComposerTextInput
        weak var scrollView: NSScrollView?
        weak var textView: ComposerNSTextView?
        var isProgrammaticUpdate = false
        var lastFocusRequestID = 0

        init(parent: AIReportComposerTextInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView else { return }
            let latest = textView.string
            if parent.text != latest {
                parent.text = latest
            }
            textView.needsDisplay = true
            recalculateHeight()
        }

        func updateFocus(_ focused: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.isFocused != focused else { return }
                self.parent.isFocused = focused
            }
        }

        func recalculateHeight() {
            guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            var used = layoutManager.usedRect(for: textContainer).height
            let extra = layoutManager.extraLineFragmentRect.height
            if extra > 0, textView.string.hasSuffix("\n") {
                used += extra
            }
            let inset = textView.textContainerInset.height * 2
            let rawHeight = ceil(used + inset + 2)
            let clamped = min(parent.maxHeight, max(parent.minHeight, rawHeight))
            let needsScroll = rawHeight > parent.maxHeight + 1
            if let scrollView, scrollView.hasVerticalScroller != needsScroll {
                scrollView.hasVerticalScroller = needsScroll
            }
            if abs(parent.measuredHeight - clamped) > 0.5 {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.parent.measuredHeight = clamped
                }
            }
        }
    }
}

@MainActor
final class ComposerNSTextView: NSTextView {
    var placeholderText: String = ""
    var onSubmit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onBoundsWidthChange: (() -> Void)?
    private var lastBoundsWidth: CGFloat = 0

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if abs(newSize.width - lastBoundsWidth) > 0.5 {
            lastBoundsWidth = newSize.width
            onBoundsWidthChange?()
        }
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !hasMarkedText() {
            let modifiers = event.modifierFlags.intersection([.shift, .option, .control, .command])
            if modifiers.isEmpty {
                onSubmit?()
                return
            }
            if modifiers == [.shift] || modifiers == [.option] {
                insertNewlineIgnoringFieldEditor(nil)
                return
            }
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholderText.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let padding = (textContainer?.lineFragmentPadding ?? 0) + textContainerInset.width
        let rect = NSRect(
            x: padding,
            y: textContainerInset.height,
            width: max(0, bounds.width - padding * 2),
            height: max(0, bounds.height - textContainerInset.height * 2)
        )
        (placeholderText as NSString).draw(in: rect, withAttributes: attributes)
    }
}

enum AIReportComposerMetrics {
    static let controlHeight: CGFloat = PortfolixSpacing.xxxl
    static let controlSpacing: CGFloat = PortfolixLayout.chatComposerHorizontalInset
    static let defaultEditorHeight: CGFloat = 30
    static let reviewEditorMinHeight: CGFloat = 86
    static let maximumEditorHeight: CGFloat = 220
}

enum AIReportComposerAction: CaseIterable {
    case analyze
    case send
    case stop

    init(hasDraftText: Bool) {
        self = hasDraftText ? .send : .analyze
    }

    var symbol: String {
        switch self {
        case .send: "arrow.up"
        case .analyze: "apple.intelligence"
        case .stop: "stop.fill"
        }
    }

    func title(hasReport: Bool, language: AppLanguage) -> String {
        switch self {
        case .stop: localizedText("停止生成", "Stop generating", language: language)
        case .send: localizedText("发送问题", "Send question", language: language)
        case .analyze: hasReport
            ? localizedText("重新分析", "Analyze Again", language: language)
            : localizedText("生成分析", "Generate", language: language)
        }
    }

    func isEnabled(canGenerate: Bool, canSendFollowUp: Bool, isSubmitting: Bool,
                   isAwaitingResponse: Bool, isVoiceActive: Bool) -> Bool {
        if self == .stop { return isAwaitingResponse }
        guard !isSubmitting, !isAwaitingResponse, !isVoiceActive else { return false }
        return self == .send ? canSendFollowUp : canGenerate
    }
}

enum AIReportComposerFocusPolicy {
    static func shouldRestoreFocus(
        wasAwaitingResponse: Bool,
        isAwaitingResponse: Bool,
        isVoiceActive: Bool
    ) -> Bool {
        wasAwaitingResponse && !isAwaitingResponse && !isVoiceActive
    }
}

@MainActor
final class AIReportComposerDraftBuffer {
    private(set) var text = ""

    var hasContent: Bool {
        submissionText != nil
    }

    var submissionText: String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func replace(with value: String) {
        text = value
    }

    func appendReviewQuestion(_ question: String, language: AppLanguage) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return }
        let promptLine = localizedText(
            "关于「\(trimmedQuestion)」：\n",
            "Regarding \"\(trimmedQuestion)\":\n",
            language: language
        )
        if text.contains(trimmedQuestion) {
            return
        }
        let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            text = promptLine
        } else {
            text = existing + "\n\n" + promptLine
        }
    }

    func clear() {
        text = ""
    }
}

struct AIReportComposerActionButton: View {
    let mode: AIReportComposerAction
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if mode == .stop {
                Button(action: action) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.lossOnFill)
                        .frame(width: AIReportComposerMetrics.controlHeight, height: AIReportComposerMetrics.controlHeight)
                        .background(PortfolixTheme.lossFill, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Button(action: action) {
                    Group {
                        if mode == .analyze {
                            PortfolixAnalysisGlyph()
                        } else {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .frame(width: AIReportComposerMetrics.controlHeight, height: AIReportComposerMetrics.controlHeight)
                    .contentShape(Circle())
                }
                .buttonStyle(PrimaryButtonStyle(
                    preservesLabelSize: true,
                    cornerRadius: AIReportComposerMetrics.controlHeight / 2
                ))
            }
        }
        .disabled(!isEnabled)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
        .portfolixHelp(title)
    }
}

private struct AIReportAgentThinkingIcon: View {
    let size: CGFloat

    init(size: CGFloat = 40) {
        self.size = size
    }

    var body: some View {
        AIReportRoseOrbit(date: Date(), size: size)
            .frame(width: size, height: size, alignment: .center)
    }
}

private struct StatusSymbolIcon: View {
    let symbol: String
    let color: Color
    var background: Color = PortfolixTheme.neutralWash

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: 32, height: 32)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 40, height: 40, alignment: .center)
    }
}

private func recommendationDetails(for action: AIRebalanceAction) -> String {
    let rationale = AIUserFacingTextSanitizer.sanitize(action.rationale)
    guard let rawRiskNote = action.riskNote, !rawRiskNote.isEmpty else {
        return rationale
    }
    let riskNote = AIUserFacingTextSanitizer.sanitize(rawRiskNote)
    guard !riskNote.isEmpty else { return rationale }
    let punctuation = "。！？；.!?;"
    let separator = rationale.last.map { punctuation.contains($0) } == true ? " " : "；"
    return "\(rationale)\(separator)\(riskNote)"
}

struct AIReportDisclaimer: View {
    let language: AppLanguage
    var modelUsage: AIModelUsageSummary? = nil
    var showsDisclosure = true

    var text: String {
        let tokenUsage = AIModelUsageSummary.displayText(for: modelUsage, language: language)
        let usage = [tokenUsage, modelUsage?.searchUsage?.displayText(language: language)].compactMap { $0 }.joined(separator: " · ")
        guard showsDisclosure else { return usage }
        let separator = language == .english ? "; " : "；"
        return usage + separator + localizedText(AIAdviceDisclosure.text, "Generated by AI from available data for reference only. Not investment advice.", language: language)
    }

    var body: some View {
        Text(text)
            .font(PortfolixTypography.caption)
            .foregroundStyle(PortfolixTheme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AIReportBullet: View {
    let title: String
    let bodyText: String?
    let color: Color
    let symbol: String

    init(title: String, body: String?, color: Color, symbol: String) {
        self.title = title
        self.bodyText = body
        self.color = color
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .top, spacing: PortfolixSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(title)
                    .font(PortfolixTypography.bodyEmphasis)
                    .foregroundStyle(PortfolixTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let bodyText {
                    Text(bodyText)
                        .font(PortfolixTypography.caption)
                        .lineSpacing(4)
                        .foregroundStyle(PortfolixTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private func chatTimestampText(_ date: Date, language _: AppLanguage) -> String {
    AIReportChatDateFormatters.timestamp.string(from: date)
}

private func chatDateText(_ date: Date, language: AppLanguage) -> String {
    let formatter = language == .english
        ? AIReportChatDateFormatters.englishDate
        : AIReportChatDateFormatters.chineseDate
    return formatter.string(from: date)
}

private func diagnosticTimestampText(_ date: Date) -> String {
    AIReportChatDateFormatters.diagnosticTimestamp.string(from: date)
}

private enum AIReportChatDateFormatters {
    static let timestamp = make("HH:mm", locale: "en_US_POSIX")
    static let englishDate = make("MMM d", locale: "en_US_POSIX")
    static let chineseDate = make("M月d日", locale: "zh_CN")
    static let diagnosticTimestamp = make("yyyy-MM-dd HH:mm", locale: "en_US_POSIX")

    private static func make(_ format: String, locale: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = format
        return formatter
    }
}

struct RiskProfileView: View {
    @Environment(PortfolioStore.self) private var store
    @State private var isQuestionnairePresented = false

    var body: some View {
        @Bindable var store = store
        let evaluation = store.riskConstraintEvaluation
        let constraintCount = evaluation.results.count
        let passedConstraintCount = evaluation.results.count { $0 }
        let breachCount = constraintCount - passedConstraintCount
        let largestPositionLabel = evaluation.largestPositionName
            ?? localizedText("暂无持仓", "No holdings", language: store.appLanguage)

        ScrollView {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                PageHeader(title: localizedText("风险偏好", "Risk Profile", language: store.appLanguage)) {
                    Button {
                        isQuestionnairePresented = true
                    } label: {
                        Label(
                            store.riskProfileConfigured
                                ? localizedText("重新评估", "Reassess", language: store.appLanguage)
                                : localizedText("开始评估", "Start Assessment", language: store.appLanguage),
                            systemImage: store.riskProfileConfigured ? "arrow.clockwise" : "play.circle.fill"
                        )
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                HStack(alignment: .top, spacing: PortfolixSpacing.md) {
                    RiskProfileSummaryCard(
                        level: store.riskProfileConfigured ? localizedRiskLevel : localizedText("未配置", "Not configured", language: store.appLanguage),
                        tolerance: localizedRiskTolerance,
                        description: localizedRiskDescription,
                        isConfigured: store.riskProfileConfigured,
                        version: store.riskProfileVersion,
                        updatedAt: store.riskProfileUpdatedAt,
                        language: store.appLanguage
                    )

                    RiskPortfolioMatchCard(
                        score: evaluation.matchScore,
                        passedCount: passedConstraintCount,
                        totalCount: constraintCount,
                        breachCount: breachCount,
                        language: store.appLanguage
                    )
                }

                Panel {
                    VStack(alignment: .leading, spacing: PortfolixSpacing.lg) {
                        SectionHeader(title: localizedText("关键约束", "Key Constraints", language: store.appLanguage), symbol: "slider.horizontal.3")

                        RiskConstraintSliderRow(
                            title: localizedText("单一资产最大占比", "Max Single Asset", language: store.appLanguage),
                            actualLabel: largestPositionLabel,
                            actualValue: evaluation.largestPositionPercent,
                            limitLabel: localizedText("上限", "Limit", language: store.appLanguage),
                            value: $store.positionLimit,
                            range: 10 ... 60,
                            mode: .maximum,
                            language: store.appLanguage,
                            onCommit: { store.saveRiskThresholdVersion() }
                        )

                        RiskConstraintSliderRow(
                            title: localizedText("加密资产上限", "Max Crypto", language: store.appLanguage),
                            actualLabel: localizedText("当前加密资产", "Current Crypto", language: store.appLanguage),
                            actualValue: evaluation.cryptoAllocationPercent,
                            limitLabel: localizedText("上限", "Limit", language: store.appLanguage),
                            value: $store.cryptoLimit,
                            range: 0 ... 50,
                            mode: .maximum,
                            language: store.appLanguage,
                            onCommit: { store.saveRiskThresholdVersion() }
                        )

                        RiskConstraintSliderRow(
                            title: localizedText("外币资产上限", "Max Non-Base Currency", language: store.appLanguage),
                            actualLabel: localizedText("当前外币占比", "Current Non-Base", language: store.appLanguage),
                            actualValue: evaluation.nonCNYAllocationPercent,
                            limitLabel: localizedText("上限", "Limit", language: store.appLanguage),
                            value: $store.foreignCurrencyLimit,
                            range: 10 ... 90,
                            mode: .maximum,
                            language: store.appLanguage,
                            onCommit: { store.saveRiskThresholdVersion() }
                        )

                        RiskConstraintSliderRow(
                            title: localizedText("最低现金比例", "Minimum Cash", language: store.appLanguage),
                            actualLabel: localizedText("当前现金占比", "Current Cash", language: store.appLanguage),
                            actualValue: evaluation.cashAllocationPercent,
                            limitLabel: localizedText("下限", "Minimum", language: store.appLanguage),
                            value: $store.liquidityMinimum,
                            range: 0 ... 40,
                            mode: .minimum,
                            language: store.appLanguage,
                            onCommit: { store.saveRiskThresholdVersion() }
                        )

                    }
                }

                RiskMaintenanceCard(
                    status: reviewStatus(for: evaluation),
                    isConfigured: store.riskProfileConfigured,
                    version: store.riskProfileVersion,
                    updatedAt: store.riskProfileUpdatedAt,
                    language: store.appLanguage
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .sheet(isPresented: $isQuestionnairePresented) {
            RiskQuestionnaireSheet()
                .environment(store)
        }
    }

    private var localizedRiskLevel: String {
        switch store.riskLevel {
        case "保守稳健":
            return localizedText("保守型", "Conservative", language: store.appLanguage)
        case "稳健平衡":
            return localizedText("平衡型", "Balanced", language: store.appLanguage)
        case "积极成长":
            return localizedText("进取型", "Growth", language: store.appLanguage)
        case "未配置":
            return localizedText("未配置", "Not configured", language: store.appLanguage)
        default:
            return store.riskLevel
        }
    }

    private var localizedRiskTolerance: String {
        guard store.riskProfileConfigured else {
            return localizedText("--", "--", language: store.appLanguage)
        }
        switch store.riskLevel {
        case "保守稳健":
            return localizedText("低", "Low", language: store.appLanguage)
        case "积极成长":
            return localizedText("较高", "Higher", language: store.appLanguage)
        default:
            return localizedText("中等", "Medium", language: store.appLanguage)
        }
    }

    private var localizedRiskDescription: String {
        guard store.riskProfileConfigured else {
            return localizedText("完成评估后生成风险偏好说明", "Complete the assessment to generate a risk profile summary", language: store.appLanguage)
        }
        switch store.riskLevel {
        case "保守稳健":
            return localizedText("以本金安全与低回撤为首要目标，核心仓位偏向低波动与固收资产。", "Prioritizes capital preservation and low drawdowns with lower-volatility core holdings.", language: store.appLanguage)
        case "积极成长":
            return localizedText("愿意承受阶段性较大回撤，以高弹性权益与成长资产博取长期复利。", "Accepts deeper drawdowns in pursuit of higher long-term compounding from growth assets.", language: store.appLanguage)
        case "稳健平衡":
            return localizedText("兼顾长期增值与回撤控制，通过股债与多资产分散降低单一波动。", "Balances long-term growth with drawdown control through multi-asset diversification.", language: store.appLanguage)
        default:
            return localizedText("基于问卷与关键约束生成的风险偏好说明", "A risk profile summary based on the questionnaire and key constraints", language: store.appLanguage)
        }
    }

    private func reviewStatus(for evaluation: RiskConstraintEvaluation) -> RiskReviewStatus {
        if !store.riskProfileConfigured {
            return .notConfigured
        }
        if evaluation.shouldSuggestReview {
            return .reviewSuggested
        }
        return .valid
    }
}

private enum RiskConstraintMode {
    case maximum
    case minimum
}

private enum RiskReviewStatus {
    case valid
    case reviewSuggested
    case notConfigured

    func title(language: AppLanguage) -> String {
        switch self {
        case .valid:
            localizedText("有效", "Valid", language: language)
        case .reviewSuggested:
            localizedText("建议复评", "Review Suggested", language: language)
        case .notConfigured:
            localizedText("待评估", "Pending", language: language)
        }
    }

    var color: Color {
        switch self {
        case .valid:
            PortfolixTheme.gainText
        case .reviewSuggested:
            PortfolixTheme.warnText
        case .notConfigured:
            PortfolixTheme.tertiary
        }
    }

    var symbol: String {
        switch self {
        case .valid:
            "checkmark.circle.fill"
        case .reviewSuggested:
            "exclamationmark.triangle.fill"
        case .notConfigured:
            "circle.dashed"
        }
    }
}

private struct RiskProfileSummaryCard: View {
    let level: String
    let tolerance: String
    let description: String
    let isConfigured: Bool
    let version: Int
    let updatedAt: Date
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.lg) {
                SectionHeader(title: localizedText("风险档案", "Risk Profile", language: language), symbol: "person.text.rectangle")

                HStack(alignment: .center, spacing: PortfolixSpacing.xl) {
                    VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                        Text(level)
                            .font(PortfolixTypography.secondaryValue)
                            .foregroundStyle(PortfolixTheme.brandText)
                            .lineLimit(1)

                        Text(description)
                            .font(PortfolixTypography.caption)
                            .foregroundStyle(PortfolixTheme.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: PortfolixSpacing.xs) {
                        Text(tolerance)
                            .font(PortfolixTypography.secondaryValue)
                            .foregroundStyle(PortfolixTheme.text)
                            .monospacedDigit()
                            .portfolixNumericTransition(tolerance)
                            .lineLimit(1)
                        Text(localizedText("风险承受度", "Risk Tolerance", language: language))
                            .font(PortfolixTypography.captionEmphasis)
                            .foregroundStyle(PortfolixTheme.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                if isConfigured {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        CardMetaLabel(
                            title: riskProfileVersionLabel(
                                isConfigured: true,
                                version: version,
                                updatedAt: updatedAt,
                                now: context.date,
                                language: language
                            ),
                            symbol: "clock"
                        )
                    }
                } else {
                    CardMetaLabel(
                        title: riskProfileVersionLabel(
                            isConfigured: false,
                            version: version,
                            updatedAt: updatedAt,
                            now: .now,
                            language: language
                        ),
                        symbol: "clock"
                    )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        }
    }
}

private struct RiskPortfolioMatchCard: View {
    let score: Double?
    let passedCount: Int
    let totalCount: Int
    let breachCount: Int
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.lg) {
                SectionHeader(title: localizedText("约束状态", "Limit Status", language: language), symbol: "target")

                HStack(alignment: .center, spacing: PortfolixSpacing.xl) {
                    VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                        Text(scoreText)
                            .font(PortfolixTypography.heroValueCompact)
                            .monospacedDigit()
                            .foregroundStyle(scoreColor)
                            .portfolixNumericTransition(scoreText)
                        Text(localizedText("关键约束匹配", "Key constraint fit", language: language))
                            .font(PortfolixTypography.caption)
                            .foregroundStyle(PortfolixTheme.tertiary)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: PortfolixSpacing.sm) {
                        RiskCountPill(
                            title: localizedText("正常", "Within Limits", language: language),
                            value: "\(passedCount)/\(totalCount)",
                            color: PortfolixTheme.gainText
                        )
                        RiskCountPill(
                            title: localizedText("需关注", "Watch", language: language),
                            value: "\(breachCount)",
                            color: breachCount == 0 ? PortfolixTheme.tertiary : PortfolixTheme.warnText
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                CardMetaLabel(
                    title: localizedText("基于下方关键约束计算", "Based on key constraints below", language: language),
                    symbol: "slider.horizontal.3"
                )
            }
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        }
    }

    private var scoreText: String {
        guard let score else {
            return "--"
        }
        return "\(Int(score.rounded()))%"
    }

    private var scoreColor: Color {
        guard let score else {
            return PortfolixTheme.tertiary
        }
        if score >= 75 {
            return PortfolixTheme.gainText
        }
        if score >= 50 {
            return PortfolixTheme.warnText
        }
        return PortfolixTheme.lossText
    }
}

private struct RiskConstraintSliderRow: View {
    let title: String
    let actualLabel: String
    let actualValue: Double
    let limitLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let mode: RiskConstraintMode
    let language: AppLanguage
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let spacing = PortfolixSpacing.md
            let availableWidth = max(proxy.size.width - spacing, 0)
            let leadingWidth = availableWidth / 1.618
            let trailingWidth = availableWidth - leadingWidth

            HStack(spacing: spacing) {
                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    Text(title)
                        .font(PortfolixTypography.bodyEmphasis)
                        .foregroundStyle(PortfolixTheme.text)
                        .lineLimit(1)

                    Text(actualCaption)
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.tertiary)
                        .lineLimit(1)
                        .portfolixNumericTransition(actualCaption)
                }
                .frame(width: leadingWidth, alignment: .leading)

                HStack(spacing: PortfolixSpacing.md) {
                    Slider(value: $value, in: range, step: 5) { isEditing in
                        if !isEditing {
                            onCommit()
                        }
                    }
                        .tint(PortfolixTheme.brandFocus)

                    VStack(alignment: .trailing, spacing: PortfolixSpacing.xs) {
                        Text("\(limitLabel) \(percentText(value))")
                            .font(PortfolixTypography.labelEmphasis)
                            .foregroundStyle(PortfolixTheme.secondary)
                            .monospacedDigit()
                            .portfolixNumericTransition(percentText(value))
                            .lineLimit(1)

                        RiskLimitBadge(
                            title: isPassing ? localizedText("正常", "Within Limits", language: language) : localizedText("需关注", "Watch", language: language),
                            color: isPassing ? PortfolixTheme.gainText : PortfolixTheme.warnText,
                            textColor: isPassing ? PortfolixTheme.gainText : PortfolixTheme.warnText
                        )
                    }
                    .frame(width: 92, alignment: .trailing)
                }
                .frame(width: trailingWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(height: 48)
    }

    private var actualCaption: String {
        "\(actualLabel) \(percentText(actualValue))"
    }

    private var isPassing: Bool {
        switch mode {
        case .maximum:
            actualValue <= value
        case .minimum:
            actualValue >= value
        }
    }
}

private struct RiskMaintenanceCard: View {
    let status: RiskReviewStatus
    let isConfigured: Bool
    let version: Int
    let updatedAt: Date
    let language: AppLanguage

    var body: some View {
        SettingsSection(title: localizedText("复评周期", "Review Schedule", language: language), symbol: "calendar.badge.clock") {
            SettingsRow(title: localizedText("当前状态", "Status", language: language)) {
                RiskStatusValue(status: status, language: language)
            }
            SettingsDivider()
            SettingsRow(title: localizedText("复评周期", "Cadence", language: language)) {
                RiskSettingValue(localizedText("6 个月", "6 months", language: language))
            }
            SettingsDivider()
            SettingsRow(title: localizedText("档案版本", "Version", language: language)) {
                if isConfigured {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        RiskSettingValue(
                            riskProfileVersionLabel(
                                isConfigured: true,
                                version: version,
                                updatedAt: updatedAt,
                                now: context.date,
                                language: language
                            )
                        )
                    }
                } else {
                    RiskSettingValue(
                        riskProfileVersionLabel(
                            isConfigured: false,
                            version: version,
                            updatedAt: updatedAt,
                            now: .now,
                            language: language
                        )
                    )
                }
            }
        }
    }
}

private func riskProfileVersionLabel(
    isConfigured: Bool,
    version: Int,
    updatedAt: Date,
    now: Date,
    language: AppLanguage
) -> String {
    guard isConfigured else {
        return localizedText("等待首次评估", "Not assessed yet", language: language)
    }
    let seconds = max(0, Int(now.timeIntervalSince(updatedAt)))
    let updatedText: String
    if seconds < 60 {
        updatedText = localizedText("刚刚更新", "Just updated", language: language)
    } else if seconds < 3_600 {
        let minutes = seconds / 60
        updatedText = language == .english ? "\(minutes)m ago" : "\(minutes) 分钟前更新"
    } else if seconds < 86_400 {
        let hours = seconds / 3_600
        updatedText = language == .english ? "\(hours)h ago" : "\(hours) 小时前更新"
    } else {
        let days = seconds / 86_400
        updatedText = language == .english ? "\(days)d ago" : "\(days) 天前更新"
    }
    return language == .english
        ? "Version v\(version) · \(updatedText)"
        : "版本 v\(version) · \(updatedText)"
}

private struct RiskStatusValue: View {
    let status: RiskReviewStatus
    let language: AppLanguage

    var body: some View {
        HStack(spacing: PortfolixSpacing.xs) {
            Image(systemName: status.symbol)
            Text(status.title(language: language))
        }
        .font(PortfolixTypography.labelEmphasis)
        .foregroundStyle(status.color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct RiskSettingValue: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(PortfolixTypography.labelEmphasis)
            .foregroundStyle(PortfolixTheme.text)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct RiskCountPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: PortfolixSpacing.xs) {
            Text(title)
                .foregroundStyle(PortfolixTheme.tertiary)
            Text(value)
                .foregroundStyle(color)
                .monospacedDigit()
                .portfolixNumericTransition(value)
        }
        .font(PortfolixTypography.captionEmphasis)
    }
}

private struct RiskLimitBadge: View {
    let title: String
    let color: Color
    let textColor: Color

    var body: some View {
        Text(title)
            .font(PortfolixTypography.captionEmphasis)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, PortfolixSpacing.sm)
            .padding(.vertical, PortfolixSpacing.xs)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private func percentText(_ value: Double) -> String {
    "\(Int(value.rounded()))%"
}

struct SettingsView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var configurationSheet: SettingsConfigurationSheet?
    @State private var preparedDataImport: PreparedPortfolixDataImport?
    @State private var isImportConfirmationPresented = false
    @State private var isDisableMemoryConfirmationPresented = false
    @State private var dataTransferNotice: DataTransferNotice?
    @State private var exportStatus: DataTransferInlineStatus = .idle
    @State private var importStatus: DataTransferInlineStatus = .idle
    @State private var exportStatusResetTask: Task<Void, Never>?
    @State private var importStatusResetTask: Task<Void, Never>?

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                PageHeader(title: settingsText("设置", "Settings"))

                SettingsSection(title: settingsText("显示设置", "Display"), symbol: "display") {
                    SettingsRow(title: settingsText("外观模式", "Appearance")) {
                        PortfolixGlassSegmentedPicker(
                            title: settingsText("外观模式", "Appearance"),
                            selection: $store.appearanceMode,
                            options: AppearanceMode.allCases,
                            optionTitle: { $0.title(language: store.appLanguage) },
                            width: 240,
                            height: PortfolixLayout.settingsControlHeight
                        )
                    }

                    SettingsDivider()

                    SettingsRow(title: settingsText("界面语言", "Language")) {
                        PortfolixGlassSegmentedPicker(
                            title: settingsText("界面语言", "Language"),
                            selection: $store.appLanguage,
                            options: AppLanguage.allCases,
                            optionTitle: { $0.rawValue },
                            width: 240,
                            height: PortfolixLayout.settingsControlHeight
                        )
                    }

                    SettingsDivider()

                    SettingsRow(title: settingsText("默认展示币种", "Default Currency")) {
                        PortfolixGlassSegmentedPicker(
                            title: settingsText("默认展示币种", "Default Currency"),
                            selection: $store.displayCurrency,
                            options: DisplayCurrency.allCases,
                            optionTitle: { $0.rawValue },
                            width: 240,
                            height: PortfolixLayout.settingsControlHeight
                        )
                    }

                    SettingsDivider()

                    SettingsRow(title: settingsText("涨跌配色", "Gain/Loss Colors")) {
                        PortfolixGlassSegmentedPicker(
                            title: settingsText("涨跌配色", "Gain/Loss Colors"),
                            selection: $store.performanceColorScheme,
                            options: PerformanceColorScheme.allCases,
                            optionTitle: { $0.title(language: store.appLanguage) },
                            optionAttributedTitle: { $0.selectorTitle(language: store.appLanguage) },
                            width: store.appLanguage == .english ? 340 : 240,
                            height: PortfolixLayout.settingsControlHeight
                        )
                    }
                }

                SettingsSection(title: settingsText("行情更新", "Price Updates"), symbol: "clock.arrow.circlepath") {
                    SettingsToggleRow(
                        title: settingsText("自动获取最新价格", "Automatic Price Updates"),
                        isOn: $store.backgroundUpdatesEnabled
                    )
                    SettingsDivider()
                    SettingsRow(title: settingsText("更新频率", "Frequency")) {
                        SettingsMenuPicker(
                            title: settingsText("更新频率", "Frequency"),
                            selection: $store.automaticPriceUpdateFrequency
                        ) { frequency in
                            frequency.title(language: store.appLanguage)
                        }
                    }
                }

                SettingsSection(title: settingsText("AI 投研", "AI Insights"), symbol: "sparkles.rectangle.stack") {
                    SettingsToggleRow(
                        title: settingsText("AI 资产分析", "AI Asset Analysis"),
                        helpText: settingsText(
                            "开启后，通过 DeepSeek 分析当前持仓、收益表现与风险约束。",
                            "Uses DeepSeek to analyze your portfolio, performance, and risk limits."
                        ),
                        helpPlacement: .trailing,
                        isOn: $store.aiConfiguration.isEnabled
                    )
                    SettingsDivider()
                    SettingsRow(
                        title: settingsText("分析模式", "Analysis Mode"),
                        helpText: settingsText(
                            "基础分析仅使用本机组合数据；联网研究会按需调用已启用的搜索源检索公开市场信息。",
                            "Basic uses local portfolio data only; Web Research calls enabled search sources for public market data."
                        ),
                        helpPlacement: .trailing
                    ) {
                        PortfolixGlassSegmentedPicker(
                            title: settingsText("分析模式", "Analysis Mode"),
                            selection: smartAnalysisModeBinding,
                            options: SmartAnalysisMode.availableCases,
                            optionTitle: { $0.title(language: store.appLanguage) },
                            width: 240,
                            height: PortfolixLayout.settingsControlHeight
                        )
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: settingsText("投研风格", "Advisor Style"),
                        helpText: settingsText(
                            "选择默认投研风格，也可在下拉菜单中补充个性表达偏好。",
                            "Choose a default analysis style, or add optional custom preferences from the menu."
                        ),
                        helpPlacement: .trailing
                    ) {
                        AdvisorStyleMenuPicker(
                            selection: Binding(
                                get: { store.aiAdvisorPersona.preset },
                                set: { newPreset in
                                    var updated = store.aiAdvisorPersona
                                    updated.preset = newPreset
                                    store.aiAdvisorPersona = updated
                                }
                            ),
                            hasCustomPreference: !store.aiAdvisorPersona.sanitizedCustomPreference.isEmpty,
                            language: store.appLanguage
                        ) {
                            configurationSheet = .persona
                        }
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: settingsText("投研记忆", "Research Memory"),
                        helpText: settingsText(
                            "开启后自动汇总并记录对话中提到的资金约束、投资周期与持仓逻辑（仅保存于本机）；关闭将清空已保存的记忆。",
                            "Automatically summarizes goals, cash constraints, and holding theses locally on this Mac. Turning off clears saved memory."
                        ),
                        helpPlacement: .trailing
                    ) {
                        HStack(spacing: PortfolixSpacing.sm) {
                            Button(settingsText("管理", "Manage")) {
                                configurationSheet = .memory
                            }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(!store.aiAdvisorPersona.autoExtractMemory)

                            Toggle(
                                settingsText("投研记忆", "Research Memory"),
                                isOn: Binding(
                                    get: { store.aiAdvisorPersona.autoExtractMemory },
                                    set: { enabled in
                                        if enabled {
                                            store.setAIMemoryEnabled(true)
                                        } else if !store.aiMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.aiMemoryItems.isEmpty {
                                            isDisableMemoryConfirmationPresented = true
                                        } else {
                                            store.setAIMemoryEnabled(false)
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(settingsText("投研记忆", "Research Memory"))
                        }
                    }
                    SettingsDivider()
                    SettingsRow(title: settingsText("内容保留时长", "Content Retention")) {
                        SettingsMenuPicker(
                            title: settingsText("内容保留时长", "Content Retention"),
                            selection: $store.aiChatRetentionPeriod
                        ) { period in
                            period.title(language: store.appLanguage)
                        }
                    }
                    SettingsDivider()
                    SettingsRow(title: "DeepSeek API") {
                        let state = apiCredentialDisplayState(
                            hasKey: store.hasLLMAPIKey,
                            validationState: store.llmAPIKeyValidationState
                        )
                        ProviderConfigurationActions(
                            state: state.title,
                            color: state.color,
                            symbol: state.symbol,
                            buttonTitle: settingsText("配置", "Configure")
                        ) {
                            configurationSheet = .llm
                        }
                    }
                    SettingsDivider()
                    SettingsRow(title: settingsText("搜索 API", "Search APIs")) {
                        let state = searchCredentialDisplayState()
                        ProviderConfigurationActions(
                            state: state.title,
                            color: state.color,
                            symbol: state.symbol,
                            buttonTitle: settingsText("配置", "Configure")
                        ) {
                            configurationSheet = .search
                        }
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: settingsText("MCP 服务器", "MCP Server"),
                        helpText: settingsText(
                            "允许本机 Agent 只读访问持仓与历史收益，不开放 API Key 或聊天记录。",
                            "Allow local agents to read holdings and historical returns. API keys and chat history are excluded."
                        ),
                        helpPlacement: .trailing
                    ) { MCPAccessControls() }
                }

                SettingsSection(title: settingsText("数据备份", "Data Backup"), symbol: "externaldrive.badge.timemachine") {
                    SettingsRow(title: settingsText("数据存储", "Data Storage")) {
                        Label(settingsText("仅本地存储", "On this Mac only"), systemImage: "lock.shield.fill")
                            .font(PortfolixTypography.captionEmphasis)
                            .foregroundStyle(PortfolixTheme.gainText)
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: settingsText("数据导出", "Data Export"),
                        helpText: settingsText(
                            "导出持仓、历史净值、行情快照与风险配置为本地备份包（不含 AI 对话、API 密钥与本机设置）。",
                            "Exports holdings, history, price snapshots, and risk profile to a local backup package (excludes AI chats, API keys, and local settings)."
                        ),
                        helpPlacement: .trailing
                    ) {
                        HStack(spacing: PortfolixSpacing.md) {
                            DataTransferInlineStatusView(status: exportStatus)
                            Button(settingsText("导出备份", "Export Backup"), action: createDataExport)
                                .buttonStyle(QuietButtonStyle())
                                .disabled(exportStatus.isWorking)
                        }
                    }
                    SettingsDivider()
                    SettingsRow(title: settingsText("恢复备份", "Restore Backup")) {
                        HStack(spacing: PortfolixSpacing.md) {
                            DataTransferInlineStatusView(status: importStatus)
                            Button(settingsText("选择文件", "Choose File"), action: chooseDataImport)
                                .buttonStyle(QuietButtonStyle())
                                .disabled(importStatus.isWorking)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .onAppear {
            store.refreshProviderCredentialState()
        }
        .onDisappear {
            exportStatusResetTask?.cancel()
            importStatusResetTask?.cancel()
        }
        .sheet(item: $configurationSheet) { sheet in
            switch sheet {
            case .llm:
                LLMConfigurationSheet()
                    .environment(store)
            case .search:
                SearchConfigurationSheet()
                    .environment(store)
            case .persona:
                AIAdvisorPersonaSheet()
                    .environment(store)
            case .memory:
                AIMemoryManagerSheet()
                    .environment(store)
            }
        }
        .alert(
            settingsText("关闭投研记忆？", "Turn off Research Memory?"),
            isPresented: $isDisableMemoryConfirmationPresented
        ) {
            Button(settingsText("取消", "Cancel"), role: .cancel) {}
            Button(settingsText("关闭并清空", "Turn Off & Clear"), role: .destructive) {
                store.setAIMemoryEnabled(false)
            }
        } message: {
            Text(settingsText(
                "关闭后将立即清空已保存的投研记忆摘要并停止自动记录，不会影响持仓数据与历史对话。",
                "Turning this off immediately clears your saved memory summary and stops auto-recording. Holdings and chat history remain intact."
            ))
        }
        .alert(
            settingsText("确认导入数据？", "Import this data?"),
            isPresented: $isImportConfirmationPresented,
            presenting: preparedDataImport
        ) { preparedImport in
            Button(settingsText("取消", "Cancel"), role: .cancel) {
                preparedDataImport = nil
            }
            Button(settingsText("确认导入", "Import"), role: .destructive) {
                importData(preparedImport)
            }
        } message: { preparedImport in
            Text(importConfirmationMessage(preparedImport.summary))
        }
        .alert(
            dataTransferNotice?.title ?? "",
            isPresented: Binding(
                get: { dataTransferNotice != nil },
                set: { if !$0 { dataTransferNotice = nil } }
            ),
            presenting: dataTransferNotice
        ) { _ in
            Button(settingsText("完成", "Done"), role: .cancel) {
                dataTransferNotice = nil
            }
        } message: { notice in
            Text(notice.message)
        }
    }

    private func settingsText(_ chinese: String, _ english: String) -> String {
        store.appLanguage == .english ? english : chinese
    }

    private func createDataExport() {
        guard let url = PortfolixDataFilePanel.chooseExportDestination(language: store.appLanguage) else { return }
        exportStatusResetTask?.cancel()
        exportStatus = .working(settingsText("正在导出...", "Exporting..."))

        Task { @MainActor in
            await Task.yield()
            do {
                let summary = try store.exportFinancialData(to: url)
                showExportSuccess(summary)
            } catch {
                exportStatus = .idle
                dataTransferNotice = DataTransferNotice(
                    title: settingsText("无法导出数据", "Unable to Export Data"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func chooseDataImport() {
        guard let url = PortfolixDataFilePanel.chooseImportSource(language: store.appLanguage) else { return }
        importStatusResetTask?.cancel()
        importStatus = .working(settingsText("正在读取...", "Reading..."))

        Task { @MainActor in
            await Task.yield()
            do {
                preparedDataImport = try store.prepareFinancialDataImport(from: url)
                importStatus = .idle
                isImportConfirmationPresented = true
            } catch {
                importStatus = .idle
                dataTransferNotice = DataTransferNotice(
                    title: settingsText("无法读取数据包", "Unable to Read Data Package"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func importData(_ preparedImport: PreparedPortfolixDataImport) {
        importStatusResetTask?.cancel()
        importStatus = .working(settingsText("正在导入...", "Importing..."))

        Task { @MainActor in
            await Task.yield()
            do {
                let summary = try store.importFinancialData(preparedImport)
                showImportSuccess(summary)
            } catch {
                importStatus = .idle
                dataTransferNotice = DataTransferNotice(
                    title: settingsText("无法导入数据", "Unable to Import Data"),
                    message: error.localizedDescription
                )
            }
            preparedDataImport = nil
        }
    }

    private func showExportSuccess(_ summary: PortfolixDataTransferSummary) {
        exportStatus = .success(
            title: settingsText("导出完成", "Exported"),
            detail: transferSummary(summary)
        )
        exportStatusResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                exportStatus = .idle
            }
        }
    }

    private func showImportSuccess(_ summary: PortfolixDataTransferSummary) {
        importStatus = .success(
            title: settingsText("导入完成", "Imported"),
            detail: transferSummary(summary)
        )
        importStatusResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                importStatus = .idle
            }
        }
    }

    private func importConfirmationMessage(_ summary: PortfolixDataTransferSummary) -> String {
        let counts = transferSummary(summary)
        let riskProfileNotice = summary.riskProfileIncluded
            ? settingsText("风险偏好将替换为备份中的设置。", "Risk preferences will be replaced with the settings in this backup.")
            : settingsText("此旧版备份不包含风险偏好，当前设置将保留。", "This legacy backup does not include risk preferences, so the current settings will be preserved.")
        return settingsText(
            "\(counts)\n\n\(riskProfileNotice)同一资产或同一天的现有记录将被更新，其他现有数据不会删除。",
            "\(counts)\n\n\(riskProfileNotice) Existing records for the same asset or date will be updated. Other existing data will not be deleted."
        )
    }

    private func transferSummary(_ summary: PortfolixDataTransferSummary) -> String {
        let riskProfileText = summary.riskProfileIncluded
            ? settingsText("，风险偏好 1 份", ", and 1 risk profile")
            : ""
        return settingsText(
            "持仓 \(summary.holdingCount) 条，组合历史 \(summary.portfolioSnapshotCount) 条，资产价格 \(summary.assetPriceSnapshotCount) 条\(riskProfileText)。",
            "\(summary.holdingCount) holdings, \(summary.portfolioSnapshotCount) portfolio history records, \(summary.assetPriceSnapshotCount) asset price records\(riskProfileText)."
        )
    }

    private var smartAnalysisModeBinding: Binding<SmartAnalysisMode> {
        Binding(
            get: {
                store.searchConfiguration.isEnabled ? .connected : .basic
            },
            set: { mode in
                store.selectSmartAnalysisMode(mode)
            }
        )
    }

    private func apiCredentialDisplayState(
        hasKey: Bool,
        validationState: ProviderCredentialValidationState
    ) -> (title: String, color: Color, symbol: String) {
        let readiness = AIReportReadiness.credential(
            isConfigured: hasKey,
            validationState: validationState
        )
        return (
            readiness.shortStatusText(language: store.appLanguage),
            readiness.color,
            readiness.symbol
        )
    }

    private func searchCredentialDisplayState() -> (title: String, color: Color, symbol: String) {
        let providers = store.searchConfiguration.orderedEnabledProviders
        guard !providers.isEmpty else {
            return (
                settingsText("未启用", "Disabled"),
                PortfolixTheme.tertiary,
                "minus.circle.fill"
            )
        }
        let states = providers.map { provider -> AIReportReadiness in
            switch provider {
            case .parallel:
                .ready
            case .deepseek:
                AIReportReadiness.credential(isConfigured: store.hasLLMAPIKey, validationState: store.llmAPIKeyValidationState)
            case .tavily:
                AIReportReadiness.credential(
                    isConfigured: store.hasTavilyAPIKey,
                    validationState: store.tavilyAPIKeyValidationState
                )
            case .bocha:
                AIReportReadiness.credential(
                    isConfigured: store.hasBochaAPIKey,
                    validationState: store.bochaAPIKeyValidationState
                )
            case .exa:
                AIReportReadiness.credential(isConfigured: store.hasExaAPIKey, validationState: store.exaAPIKeyValidationState)
            case .anysearch:
                AIReportReadiness.credential(isConfigured: store.hasAnySearchAPIKey, validationState: store.anySearchAPIKeyValidationState)
            }
        }
        if states.contains(.invalid) {
            return (settingsText("验证失败", "Validation failed"), PortfolixTheme.lossText, "xmark.circle.fill")
        }
        if states.contains(where: { $0 != .ready }) {
            return (settingsText("待验证", "Needs validation"), PortfolixTheme.warnText, "exclamationmark.circle.fill")
        }
        return (
            settingsText("已启用 \(providers.count) 个", "\(providers.count) enabled"),
            PortfolixTheme.gainText,
            "checkmark.circle.fill"
        )
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        Panel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: title, symbol: symbol)
                    .padding(.horizontal, PortfolixSpacing.lg)
                    .padding(.top, PortfolixSpacing.lg)
                    .padding(.bottom, PortfolixSpacing.md)
                content
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String?
    let helpText: String?
    let helpPlacement: HelpTooltipPlacement
    let trailing: Trailing

    init(
        title: String,
        detail: String? = nil,
        helpText: String? = nil,
        helpPlacement: HelpTooltipPlacement = .top,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.helpText = helpText
        self.helpPlacement = helpPlacement
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            HStack(spacing: PortfolixSpacing.xs) {
                SettingsText(title: title, detail: detail)
                if let helpText {
                    HelpIcon(text: helpText, placement: helpPlacement)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, PortfolixSpacing.lg)
        .frame(height: 56)
        .accessibilityHint(helpText ?? detail ?? "")
    }
}

private struct SettingsMenuPicker<Value: CaseIterable & Identifiable & Hashable>: View where Value.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Value
    var isEnabled = true
    var width: CGFloat?
    let optionTitle: (Value) -> String

    var body: some View {
        PortfolixGlassMenuPicker(
            title: title,
            selection: $selection,
            options: Array(Value.allCases),
            optionTitle: optionTitle,
            height: PortfolixLayout.settingsControlHeight
        )
        .frame(width: width, alignment: .trailing)
        .disabled(!isEnabled)
    }
}

struct AdvisorStyleMenuPicker: View {
    @Binding var selection: AIAdvisorPersonaPreset
    let hasCustomPreference: Bool
    let language: AppLanguage
    let onCustomize: () -> Void

    var selectionLabel: String {
        let baseTitle = selection.title(language: language)
        guard hasCustomPreference else { return baseTitle }
        return language == .english ? "\(baseTitle) · Custom" : "\(baseTitle) · 已自定义"
    }

    var customizeActionTitle: String {
        if hasCustomPreference {
            return localizedText("编辑自定义偏好…", "Edit Custom Preference…", language: language)
        }
        return localizedText("自定义偏好…", "Customize Preference…", language: language)
    }

    var body: some View {
        Menu {
            ForEach(AIAdvisorPersonaPreset.allCases) { preset in
                Button {
                    selection = preset
                } label: {
                    Text(preset.title(language: language))
                }
            }

            Divider()

            Button(action: onCustomize) {
                Text(customizeActionTitle)
            }
        } label: {
            HStack(spacing: PortfolixSpacing.sm) {
                Text(selectionLabel)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(PortfolixTypography.captionEmphasis)
            .padding(.horizontal, PortfolixSpacing.sm)
            .portfolixGlassControl(height: PortfolixLayout.settingsControlHeight)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(localizedText("投研风格", "Advisor Style", language: language))
        .accessibilityValue(selectionLabel)
    }
}

private struct DataTransferNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum DataTransferInlineStatus: Equatable {
    case idle
    case working(String)
    case success(title: String, detail: String)

    var isWorking: Bool {
        if case .working = self {
            return true
        }
        return false
    }
}

private struct DataTransferInlineStatusView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: DataTransferInlineStatus

    var body: some View {
        ZStack(alignment: .trailing) {
            switch status {
            case .idle:
                Color.clear
            case let .working(title):
                HStack(spacing: PortfolixSpacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                    Text(title)
                }
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(PortfolixTheme.tertiary)
                .transition(.opacity)
            case let .success(title, detail):
                Label(title, systemImage: "checkmark.circle.fill")
                    .font(PortfolixTypography.captionEmphasis)
                    .foregroundStyle(PortfolixTheme.gainText)
                    .portfolixHelp(detail)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .trailing)))
            }
        }
        .lineLimit(1)
        .frame(width: 120, height: 20, alignment: .trailing)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: status)
        .accessibilityHidden(status == .idle)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String?
    let helpText: String?
    let helpPlacement: HelpTooltipPlacement
    @Binding var isOn: Bool

    init(
        title: String,
        detail: String? = nil,
        helpText: String? = nil,
        helpPlacement: HelpTooltipPlacement = .top,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.detail = detail
        self.helpText = helpText
        self.helpPlacement = helpPlacement
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            HStack(spacing: PortfolixSpacing.xs) {
                SettingsText(title: title, detail: detail)
                if let helpText {
                    HelpIcon(text: helpText, placement: helpPlacement)
                }
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
        .toggleStyle(.switch)
        .padding(.horizontal, PortfolixSpacing.lg)
        .frame(height: 56)
        .accessibilityLabel(title)
        .accessibilityHint(helpText ?? detail ?? "")
    }
}

enum HelpTooltipPlacement {
    case top
    case trailing
}

struct HelpIcon: View {
    let text: String
    var placement: HelpTooltipPlacement = .top

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PortfolixTheme.tertiary)
            .contentShape(Rectangle())
            .portfolixHelp(text, placement: placement)
            .accessibilityLabel(text)
    }
}

struct HelpTooltipBubble: View {
    let text: String
    private let maximumWidth: CGFloat = 260
    private let textSize: CGFloat = 11

    var body: some View {
        tooltipText
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: contentWidth, alignment: .leading)
            .portfolixTooltipSurface()
    }

    private var contentWidth: CGFloat {
        min(measuredRenderedTextWidth, maximumTextWidth)
    }

    private var maximumTextWidth: CGFloat {
        maximumWidth - PortfolixSpacing.sm * 2
    }

    private var measuredRenderedTextWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: textSize),
        ]
        let rawWidth = ceil((text as NSString).size(withAttributes: attributes).width)
        guard rawWidth > maximumTextWidth else {
            return max(rawWidth, 1)
        }

        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: maximumTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return max(ceil(boundingRect.width), 1)
    }

    private var tooltipText: some View {
        Text(text)
            .font(PortfolixTypography.caption)
            .foregroundStyle(PortfolixTheme.tertiary)
            .multilineTextAlignment(.leading)
    }
}

private struct SettingsText: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Text(title)
                .font(PortfolixTypography.bodyEmphasis)
                .foregroundStyle(PortfolixTheme.text)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, PortfolixSpacing.lg)
    }
}

private struct ProviderConfigurationActions: View {
    let state: String
    let color: Color
    let symbol: String
    let buttonTitle: String
    let configure: () -> Void

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Label(state, systemImage: symbol)
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button(buttonTitle, action: configure)
                .buttonStyle(QuietButtonStyle())
        }
    }
}

private struct PositionRefreshButton: View {
    let position: Position
    let isRefreshing: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .symbolEffect(.rotate, isActive: isRefreshing)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(PortfolixTheme.text)
        .portfolixSecondaryGlass(in: Circle(), interactive: true)
        .opacity(isRefreshing ? 0.5 : 1)
        .accessibilityLabel(
            language == .english
                ? "Refresh \(position.name) price"
                : "更新 \(position.name) 价格"
        )
        .disabled(isRefreshing)
    }
}

private enum SettingsConfigurationSheet: String, Identifiable {
    case llm
    case search
    case persona
    case memory

    var id: String { rawValue }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    init(title: String, subtitle: String? = nil) where Trailing == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                Text(title)
                    .font(PortfolixTypography.pageTitle)
                    .foregroundStyle(PortfolixTheme.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(PortfolixTypography.label)
                        .foregroundStyle(PortfolixTheme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            trailing
        }
    }
}
