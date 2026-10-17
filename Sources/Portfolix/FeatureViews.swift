import AppKit
import SwiftUI

struct PositionsView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingDeletionID: Position.ID?
    @State private var selectedBatchPositionIDs: Set<Position.ID> = []
    @State private var isBatchDeletionConfirmationPresented = false
    @State private var isPositionUpdatePresented = false
    @State private var operationErrorMessage: String?
    @State private var positionSortOrder: [KeyPathComparator<Position>] = []
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            PageHeader(title: localizedText("持仓明细", "Holdings", language: store.appLanguage)) {
                HStack(spacing: PortfolixSpacing.sm) {
                    if hasBatchSelection {
                        Text(
                            store.appLanguage == .english
                                ? "\(selectedBatchPositionIDs.count) selected"
                                : "\(selectedBatchPositionIDs.count) 项已选"
                        )
                            .font(PortfolixTypography.captionEmphasis)
                            .foregroundStyle(PortfolixTheme.secondaryText)
                            .monospacedDigit()

                        Button(localizedText("全选", "Select All", language: store.appLanguage)) {
                            selectAllVisiblePositions()
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(store.filteredPositions.isEmpty || allVisiblePositionsSelected)

                        Button(localizedText("取消", "Cancel", language: store.appLanguage)) {
                            clearBatchSelection()
                        }
                        .buttonStyle(QuietButtonStyle())

                        Button(role: .destructive) {
                            isBatchDeletionConfirmationPresented = true
                        } label: {
                            Label(localizedText("删除", "Delete", language: store.appLanguage), systemImage: "trash")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(selectedBatchPositionIDs.isEmpty)
                    } else {
                        Button {
                            isPositionUpdatePresented = true
                        } label: {
                            Label(localizedText("更新持仓", "Update Holdings", language: store.appLanguage), systemImage: "square.and.pencil")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(store.positions.isEmpty)

                        Button {
                            store.presentNewPositionEditor()
                        } label: {
                            Label(localizedText("添加持仓", "Add Holding", language: store.appLanguage), systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }

            Panel(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: PortfolixSpacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(PortfolixTheme.tertiaryText)
                            TextField(localizedText("搜索资产代码或名称", "Search code or name", language: store.appLanguage), text: $store.searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .focused($isSearchFieldFocused)
                        }
                        .padding(.horizontal, PortfolixSpacing.md)
                        .frame(width: 260, height: PortfolixLayout.positionsToolbarControlHeight)
                        .portfolixGlass(
                            in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous),
                            fallbackTint: PortfolixTheme.panelElevated,
                            fallbackOpacity: 0.62
                        )
                        .holdingVoiceInput(
                            text: $store.searchText,
                            isFocused: isSearchFieldFocused,
                            numeric: false,
                            language: store.appLanguage,
                            appearance: .highlightedField
                        )
                        .help(localizedText(
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

                    positionsTable
                }
            }
        }
        .alert(localizedText("删除持仓？", "Delete holding?", language: store.appLanguage), isPresented: deletionAlertPresented) {
            Button(localizedText("取消", "Cancel", language: store.appLanguage), role: .cancel) {
                pendingDeletionID = nil
            }
            Button(localizedText("删除", "Delete", language: store.appLanguage), role: .destructive) {
                guard let pendingDeletionID else { return }
                do {
                    try store.deletePosition(for: pendingDeletionID)
                } catch {
                    operationErrorMessage = error.localizedDescription
                }
                self.pendingDeletionID = nil
            }
        } message: {
            Text(deletionMessage)
        }
        .alert(localizedText("删除所选持仓？", "Delete selected holdings?", language: store.appLanguage), isPresented: $isBatchDeletionConfirmationPresented) {
            Button(localizedText("取消", "Cancel", language: store.appLanguage), role: .cancel) {}
            Button(localizedText("删除", "Delete", language: store.appLanguage), role: .destructive) {
                deleteSelectedPositions()
            }
        } message: {
            Text(
                store.appLanguage == .english
                    ? "This will delete \(selectedBatchPositionIDs.count) holdings. This cannot be undone"
                    : "将删除 \(selectedBatchPositionIDs.count) 项持仓，此操作无法撤销"
            )
        }
        .alert(localizedText("无法删除持仓", "Unable to delete holding", language: store.appLanguage), isPresented: operationErrorAlertPresented) {
            Button(localizedText("好", "OK", language: store.appLanguage), role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? localizedText("请稍后重试", "Please try again later", language: store.appLanguage))
        }
        .sheet(isPresented: $isPositionUpdatePresented) {
            BatchPositionUpdateSheet(positions: store.positions)
                .environment(store)
        }
        .onChange(of: store.positions.map(\.id)) { _, positionIDs in
            selectedBatchPositionIDs.formIntersection(positionIDs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var deletionAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletionID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletionID = nil
                }
            }
        )
    }

    private var deletionMessage: String {
        guard
            let pendingDeletionID,
            let position = store.positions.first(where: { $0.id == pendingDeletionID })
        else {
            return localizedText("此操作无法撤销", "This cannot be undone", language: store.appLanguage)
        }
        return store.appLanguage == .english
            ? "This will delete \(position.name) (\(position.symbol)). This cannot be undone"
            : "将删除 \(position.name)（\(position.symbol)），此操作无法撤销"
    }

    private var operationErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { operationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    operationErrorMessage = nil
                }
            }
        )
    }

    private var positionsTable: some View {
        Table(sortedFilteredPositions, selection: selectedPositionBinding, sortOrder: $positionSortOrder) {
            TableColumn("") { position in
                Toggle("", isOn: batchSelectionBinding(for: position.id))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .frame(width: 16, alignment: .center)
                    .accessibilityLabel(
                        store.appLanguage == .english
                            ? "Select \(position.name)"
                            : "选择 \(position.name)"
                    )
            }
            .width(20)

            TableColumn(localizedText("资产", "Asset", language: store.appLanguage)) { position in
                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    Text(position.name)
                        .foregroundStyle(PositionTableForeground(color: PortfolixTheme.primaryText))
                        .lineLimit(1)
                    Text(position.symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(PositionTableForeground(color: PortfolixTheme.tertiaryText, selectedOpacity: 0.74))
                        .lineLimit(1)
                }
            }
            .width(min: 112, ideal: 140)

            TableColumn(localizedText("类别", "Type", language: store.appLanguage)) { position in
                HStack(spacing: PortfolixSpacing.xs) {
                    Circle()
                        .fill(PositionTableForeground(color: position.category.color))
                        .frame(width: 5, height: 5)
                    Text(position.category.title(language: store.appLanguage))
                        .foregroundStyle(PositionTableForeground(color: PortfolixTheme.secondaryText))
                        .lineLimit(1)
                }
            }
            .width(76)

            TableColumn(localizedText("份额", "Quantity", language: store.appLanguage)) { position in
                Text(NSDecimalNumber(decimal: position.quantity).stringValue)
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.primaryText))
                    .monospacedDigit()
            }
            .width(72)

            TableColumn(
                localizedText("总成本", "Total Cost", language: store.appLanguage),
                value: \.totalCost
            ) { position in
                Text(formatMoney(position.totalCost, currency: position.quoteCurrency))
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.primaryText))
                    .monospacedDigit()
            }
            .width(116)

            TableColumn(
                localizedText("当前市值", "Market Value", language: store.appLanguage),
                value: \.marketValueCNY
            ) { position in
                Text(formatMoney(store.converted(position.marketValueCNY), currency: store.displayCurrency))
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.primaryText))
                    .monospacedDigit()
            }
            .width(116)

            TableColumn(
                localizedText("收益率", "Return Rate", language: store.appLanguage),
                value: \.profitRate
            ) { position in
                Text(formatPercent(position.profitRate))
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.performanceColor(for: position.profitRate)))
                    .monospacedDigit()
            }
            .width(72)

            TableColumn(localizedText("来源 / 状态", "Source / Status", language: store.appLanguage)) { position in
                PositionSourceCell(position: position, store: store)
            }
            .width(min: 136, ideal: 160)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: colorScheme != .dark))
        .scrollContentBackground(.hidden)
        .background(PortfolixTheme.panel)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .contextMenu(forSelectionType: Position.ID.self) { selection in
            if let positionID = selection.first {
                Button {
                    store.refreshPosition(id: positionID)
                } label: {
                    Label(localizedText("更新价格", "Refresh Price", language: store.appLanguage), systemImage: "arrow.clockwise")
                }
                .disabled(!canRefresh(positionID: positionID))

                Button {
                    store.presentPositionEditor(for: positionID)
                } label: {
                    Label(localizedText("编辑持仓", "Edit Holding", language: store.appLanguage), systemImage: "square.and.pencil")
                }

                Divider()

                Button(role: .destructive) {
                    pendingDeletionID = positionID
                } label: {
                    Label(localizedText("删除持仓", "Delete Holding", language: store.appLanguage), systemImage: "trash")
                }
            }
        } primaryAction: { selection in
            if !hasBatchSelection, let positionID = selection.first {
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

    private var sortedFilteredPositions: [Position] {
        PositionDetailOrdering.sorted(
            store.filteredPositions,
            using: positionSortOrder
        )
    }

    private func canRefresh(_ position: Position) -> Bool {
        position.category != .cash
    }

    private func canRefresh(positionID: Position.ID) -> Bool {
        guard let position = store.positions.first(where: { $0.id == positionID }) else { return false }
        return canRefresh(position)
    }

    private var allVisiblePositionsSelected: Bool {
        let visibleIDs = Set(store.filteredPositions.map(\.id))
        return !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedBatchPositionIDs)
    }

    private var hasBatchSelection: Bool {
        !selectedBatchPositionIDs.isEmpty
    }

    private func clearBatchSelection() {
        selectedBatchPositionIDs = []
    }

    private func selectAllVisiblePositions() {
        let visibleIDs = Set(store.filteredPositions.map(\.id))
        selectedBatchPositionIDs.formUnion(visibleIDs)
    }

    private func batchSelectionBinding(for positionID: Position.ID) -> Binding<Bool> {
        Binding(
            get: { selectedBatchPositionIDs.contains(positionID) },
            set: { isSelected in
                if isSelected {
                    selectedBatchPositionIDs.insert(positionID)
                } else {
                    selectedBatchPositionIDs.remove(positionID)
                }
            }
        )
    }

    private func deleteSelectedPositions() {
        do {
            try store.deletePositions(for: selectedBatchPositionIDs)
            clearBatchSelection()
        } catch {
            operationErrorMessage = error.localizedDescription
        }
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
        let isSelected = store.selectedPositionID == position.id

        HStack(spacing: PortfolixSpacing.sm) {
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(localizedQuoteSource(position.source, language: store.appLanguage))
                    .foregroundStyle(PositionTableForeground(color: PortfolixTheme.primaryText))
                    .lineLimit(1)
                RelativeTimeText { now in
                    "\(position.priceDateText(language: store.appLanguage)) · \(position.relativeUpdateText(now: now, language: store.appLanguage))"
                }
                .font(.system(size: 10))
                .foregroundStyle(PositionTableForeground(color: PortfolixTheme.tertiaryText, selectedOpacity: 0.74))
                .lineLimit(1)
            }

            Spacer(minLength: PortfolixSpacing.sm)

            if position.category != .cash {
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
    }
}

enum PositionDetailOrdering {
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

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            PageHeader(title: localizedText("智能分析", "Smart Analysis", language: store.appLanguage))

            AIReportChatSurface(
                report: store.aiAnalysisReport,
                items: store.aiAnalysisChatItems,
                run: store.aiAnalysisRun,
                isRunning: isRunning,
                isSendingFollowUp: store.isAnsweringAIAnalysisFollowUp,
                followUpProgress: store.aiAnalysisFollowUpProgress,
                activityLines: store.aiAnalysisActivityLines,
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
                generate: requestAnalysis,
                sendFollowUp: sendFollowUp
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .alert(localizedText("清空智能分析历史？", "Clear analysis history?", language: store.appLanguage), isPresented: $isClearHistoryConfirmationPresented) {
            Button(localizedText("取消", "Cancel", language: store.appLanguage), role: .cancel) {}
            Button(localizedText("清空", "Clear", language: store.appLanguage), role: .destructive) {
                clearAIAnalysisHistory()
            }
        } message: {
            Text(
                localizedText(
                    "将删除智能分析报告、追问、回答和诊断记录。",
                    "This will delete analysis reports, follow-up questions, answers, and diagnostics.",
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
            }
        }
        if readiness.contains(.ready) { return .ready }
        if readiness.contains(.invalid) { return .invalid }
        if readiness.contains(.needsValidation) { return .needsValidation }
        return .missing
    }
}

private enum AIReportChatRenderPolicy {
    static let timestampWidth: CGFloat = 40
}

private struct AIReportChatSurface: View {
    let report: AIAnalysisReport?
    let items: [AIReportChatItem]
    let run: AIAnalysisRun
    let isRunning: Bool
    let isSendingFollowUp: Bool
    let followUpProgress: AIFollowUpProgress?
    let activityLines: [AIAgentActivityLine]
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
    let generate: () -> Void
    let sendFollowUp: (String) -> Void
    @State private var pendingScrollTask: Task<Void, Never>?

    var body: some View {
        let indexedItems = Array(items.enumerated())

        Panel(padding: 0) {
            VStack(spacing: 0) {
                AIReportChatHeader(
                    report: report,
                    run: run,
                    selectedModel: $selectedModel,
                    availableModels: availableModels,
                    selectedAnalysisMode: $selectedAnalysisMode,
                    isInteractionEnabled: !isRunning && !isSendingFollowUp,
                    language: language,
                    canClearHistory: canClearHistory,
                    clearHistory: clearHistory
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
                                                language: language
                                            )
                                        }
                                    case let .assistant(text):
                                        AIReportAgentBubble {
                                            AIReportFollowUpMessage(
                                                text: text,
                                                citations: item.citations ?? [],
                                                createdAt: item.createdAt,
                                                language: language,
                                                showsDisclaimer: AIChatDisclosurePolicy.shouldShowDisclosure(for: text)
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
                    .scrollIndicators(.hidden)
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
                    canSendFollowUp: report != nil && !isRunning && !isSendingFollowUp,
                    isAwaitingResponse: isSendingFollowUp,
                    hasReport: hasReport,
                    language: language,
                    generate: generate,
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

    private var hasLLMKey: Bool {
        llmReadiness == .ready
    }

}

private struct AIReportChatHeader: View {
    let report: AIAnalysisReport?
    let run: AIAnalysisRun
    @Binding var selectedModel: String
    let availableModels: [String]
    @Binding var selectedAnalysisMode: SmartAnalysisMode
    let isInteractionEnabled: Bool
    let language: AppLanguage
    let canClearHistory: Bool
    let clearHistory: () -> Void

    var body: some View {
        HStack(spacing: PortfolixSpacing.md) {
            ZStack {
                Circle()
                    .fill(PortfolixTheme.purpleGradient)
                PortfolixBrandGlyph(size: 20)
            }
                .frame(width: 28, height: 28)

            Text(localizedText("Portfolix Agent", "Portfolix Agent", language: language))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PortfolixTheme.primaryText)

            AIReportChatActionsMenu(
                canClearHistory: isInteractionEnabled && canClearHistory,
                language: language,
                clearHistory: clearHistory
            )

            Spacer()

            HStack(spacing: PortfolixLayout.controlSpacing) {
                AIReportHeaderMenuTag(
                    title: model,
                    options: availableModels,
                    selection: $selectedModel,
                    isEnabled: isInteractionEnabled && !availableModels.isEmpty,
                    optionTitle: { $0 }
                )

                AIReportHeaderMenuTag(
                    title: selectedAnalysisMode.title(language: language),
                    options: SmartAnalysisMode.availableCases,
                    selection: $selectedAnalysisMode,
                    isEnabled: isInteractionEnabled,
                    optionTitle: { $0.title(language: language) }
                )
            }
        }
        .font(PortfolixTypography.caption)
        .foregroundStyle(PortfolixTheme.secondaryText)
        .padding(.horizontal, PortfolixSpacing.lg)
        .padding(.vertical, PortfolixSpacing.md)
    }

    private var model: String {
        selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (report?.model ?? run.model ?? localizedText("未配置模型", "Model not configured", language: language))
            : selectedModel
    }
}

private struct AIReportHeaderMenuTag<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let isEnabled: Bool
    let optionTitle: (Option) -> String

    var body: some View {
        PortfolixGlassMenuPicker(
            title: title,
            selection: $selection,
            options: options,
            optionTitle: optionTitle,
            selectionTitle: title
        )
        .disabled(!isEnabled)
    }
}

private struct AIReportChatActionsMenu: View {
    let canClearHistory: Bool
    let language: AppLanguage
    let clearHistory: () -> Void

    var body: some View {
        Menu {
            Button(role: .destructive) {
                clearHistory()
            } label: {
                Label(
                    localizedText("清空智能分析历史", "Clear Analysis History", language: language),
                    systemImage: "trash"
                )
            }
            .disabled(!canClearHistory)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PortfolixTheme.glassControlText)
                .frame(width: PortfolixLayout.glassControlHeight)
                .portfolixGlassControl()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(!canClearHistory)
        .opacity(canClearHistory ? 1 : 0.56)
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
                .foregroundStyle(PortfolixTheme.userMessageText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, PortfolixSpacing.lg)
                .padding(.vertical, PortfolixSpacing.md)
                .background(PortfolixTheme.userMessageGradient, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
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
                    .fill(PortfolixTheme.purpleGradient)
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
    let showsDisclaimer: Bool

    init(
        text: String,
        citations: [AIMessageCitation] = [],
        createdAt: Date,
        language: AppLanguage,
        showsDisclaimer: Bool = true
    ) {
        self.text = text
        self.citations = citations
        self.createdAt = createdAt
        self.language = language
        self.showsDisclaimer = showsDisclaimer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
            AIReportTimestampedAgentRow(date: createdAt, language: language) {
                Group {
                    if citations.isEmpty {
                        Text(AIUserFacingTextSanitizer.sanitize(text))
                            .font(PortfolixTypography.body)
                            .foregroundStyle(PortfolixTheme.primaryText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else {
                        AIReportCitedText(text: text, citations: citations)
                    }
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PortfolixSpacing.lg)
                    .padding(.vertical, PortfolixSpacing.md)
                    .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
            }

            if showsDisclaimer {
                AIReportDisclaimer(language: language)
            }
        }
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
    private let textView = AIReportCitationNSTextView(frame: .zero)
    private var renderedText = ""
    private var renderedCitations: [AIMessageCitation] = []
    private var lastMeasuredWidth: CGFloat = 320
    var urlOpener: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
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
    }

    func update(text: String, citations: [AIMessageCitation]) {
        guard text != renderedText || citations != renderedCitations else { return }
        renderedText = text
        renderedCitations = citations

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributed = NSMutableAttributedString(
            string: AIUserFacingTextSanitizer.sanitize(text),
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        let orderedCitations = citations.enumerated().sorted { lhs, rhs in
            if lhs.element.utf16Offset == rhs.element.utf16Offset {
                return lhs.offset > rhs.offset
            }
            return lhs.element.utf16Offset > rhs.element.utf16Offset
        }
        for (_, citation) in orderedCitations {
            guard let components = try? LLMBaseURLValidator.validatedComponents(from: citation.url),
                  let url = components.url else { continue }
            let offset = min(max(0, citation.utf16Offset), attributed.length)
            let attachment = NSTextAttachment()
            attachment.image = NSImage(
                systemSymbolName: "link",
                accessibilityDescription: "\(citation.title), \(citation.url)"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            )
            attachment.bounds = NSRect(x: 0, y: -1, width: 12, height: 12)
            let icon = NSMutableAttributedString(attachment: attachment)
            icon.addAttributes(
                [
                    .link: url,
                    .toolTip: "\(citation.title)\n\(citation.url)",
                    .foregroundColor: citationColor,
                    .cursor: NSCursor.pointingHand,
                ],
                range: NSRange(location: 0, length: icon.length)
            )
            attributed.insert(icon, at: offset)
        }
        textView.textStorage?.setAttributedString(attributed)
        textView.layoutManager?.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: attributed.length),
            actualCharacterRange: nil
        )
        invalidateIntrinsicContentSize()
    }

    func fittingSize(for proposedWidth: CGFloat?) -> CGSize {
        let width = resolvedMeasurementWidth(proposedWidth)
        return CGSize(width: width, height: fittingHeight(for: width))
    }

    func fittingHeight(for width: CGFloat) -> CGFloat {
        let resolvedWidth = max(1, width)
        lastMeasuredWidth = resolvedWidth
        textView.frame.size.width = resolvedWidth
        textView.textContainer?.containerSize = NSSize(
            width: resolvedWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        return max(17, ceil(usedHeight))
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
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: 0xB7A5FF)
                : NSColor(hex: 0x654BC8)
        }
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
            .foregroundStyle(PortfolixTheme.tertiaryText)
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
            .foregroundStyle(PortfolixTheme.tertiaryText)
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
                "请在系统设置中配置 \(name)",
                "Configure \(name) in Settings",
                language: language
            )
        case .needsValidation:
            localizedText(
                "请在系统设置中验证已配置的 \(name)",
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
        case .ready: PortfolixTheme.mint
        case .missing: PortfolixTheme.tertiaryText
        case .needsValidation: PortfolixTheme.amber
        case .invalid: PortfolixTheme.danger
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
            Text(localizedText("我可以基于你的持仓、风险偏好和行情数据生成组合分析", "I can analyze your portfolio using holdings, risk profile, and market data", language: language))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PortfolixTheme.primaryText)

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
        .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
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
                .foregroundStyle(PortfolixTheme.secondaryText)
        }
    }

}

private struct AIReportAgentProgressMessage: View {
    let status: AIAnalysisRunStatus
    let activityLines: [AIAgentActivityLine]
    let language: AppLanguage

    var body: some View {
        AIReportProgressCard(
            title: status.title(language: language),
            activityLines: activityLines
        )
    }
}

private struct AIReportFollowUpProgressMessage: View {
    let progress: AIFollowUpProgress
    let activityLines: [AIAgentActivityLine]
    let language: AppLanguage

    var body: some View {
        AIReportProgressCard(
            title: progress.title(language: language),
            activityLines: activityLines
        )
    }
}

private struct AIReportProgressCard: View {
    let title: String
    let activityLines: [AIAgentActivityLine]

    private var displayLine: AIAgentActivityLine {
        activityLines.last
            ?? AIAgentActivityLine(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                text: title
            )
    }

    var body: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.md) {
            AIReportAgentThinkingIcon(size: 36)

            ZStack(alignment: .leading) {
                Text(displayLine.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(displayLine.id)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 16).combined(with: .opacity),
                            removal: .offset(y: -16).combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .leading)
            .clipped()
            .animation(.easeInOut(duration: 0.28), value: displayLine.id)
        }
        .padding(.horizontal, PortfolixSpacing.lg)
        .padding(.vertical, PortfolixSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
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
            StatusSymbolIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.primaryText)
                Text(detail)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiaryText)
            }
        }
        .padding(PortfolixSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
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
            return PortfolixTheme.danger
        }
        return switch status {
        case .failed:
            PortfolixTheme.danger
        default:
            PortfolixTheme.amber
        }
    }

    private var hasInvalidRequiredCredential: Bool {
        llmReadiness == .invalid || (usesConnectedMode && searchReadiness == .invalid)
    }
}

private struct AIReportChatReport: View {
    let report: AIAnalysisReport
    let run: AIAnalysisRun
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            HStack(spacing: PortfolixSpacing.sm) {
                CapsuleLabel(title: localizedText("分析报告", "Analysis Report", language: language), color: PortfolixTheme.lilac, symbol: "doc.text.magnifyingglass")
                if run.usedFallback {
                    CapsuleLabel(title: localizedText("安全回退", "Fallback", language: language), color: PortfolixTheme.amber, symbol: "exclamationmark.triangle.fill")
                }
                Spacer()
            }

            if run.usedFallback {
                AIReportUntimestampedAgentRow {
                    HStack(alignment: .top, spacing: PortfolixSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PortfolixTheme.amber)
                            .padding(.top, 2)
                        Text(
                            run.fallbackReason
                                ?? localizedText(
                                    "在线分析未完成，本报告由本地规则生成。",
                                    "Online analysis did not complete; this report was generated from local rules.",
                                    language: language
                                )
                        )
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PortfolixSpacing.md)
                    .padding(.vertical, PortfolixSpacing.sm)
                    .background(
                        PortfolixTheme.amber.opacity(0.10),
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AIUserFacingTextSanitizer.sanitize(report.healthScoreExplanation))
                        .font(PortfolixTypography.body)
                        .foregroundStyle(PortfolixTheme.secondaryText)
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
                                "当前报告未发现需要从组合中单独拎出的持仓，后续可继续观察集中度、币种敞口和区间表现变化。",
                                "This report did not identify a holding that needs to be singled out; keep watching concentration, currency exposure, and recent performance.",
                                language: language
                            ),
                            color: PortfolixTheme.secondaryText,
                            symbol: "checkmark.circle.fill"
                        )
                    } else {
                        ForEach(report.assetAlerts) { alert in
                            AIReportAssetAlertMessageRow(alert: alert, language: language)
                        }
                    }
                }
            }

            if !report.riskItems.isEmpty {
                AIReportTimestampedAgentRow(date: report.generatedAt, language: language) {
                    AIReportChatSection(title: localizedText("风险因素", "Risk Factors", language: language), symbol: "exclamationmark.triangle") {
                        ForEach(report.riskItems) { item in
                            AIReportBullet(
                                title: AIUserFacingTextSanitizer.sanitize(item.title),
                                body: AIUserFacingTextSanitizer.sanitize(item.impact),
                                color: color(for: item.severity),
                                symbol: item.severity == "high" ? "exclamationmark.octagon.fill" : "exclamationmark.circle.fill"
                            )
                        }
                    }
                }
            }

            if !report.questionsToConsider.isEmpty || !report.limitations.isEmpty {
                AIReportTimestampedAgentRow(date: report.generatedAt, language: language) {
                    AIReportChatSection(title: localizedText("后续复核", "Follow-up Review", language: language), symbol: "questionmark.circle") {
                        ForEach(Array(report.questionsToConsider.enumerated()), id: \.offset) { _, question in
                            AIReportBullet(title: AIUserFacingTextSanitizer.sanitize(question), body: nil, color: PortfolixTheme.lilac, symbol: "checkmark.circle.fill")
                        }
                        ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, limitation in
                            AIReportBullet(title: AIUserFacingTextSanitizer.sanitize(limitation), body: nil, color: PortfolixTheme.secondaryText, symbol: "info.circle.fill")
                        }
                    }
                }
            }

            AIReportDisclaimer(language: language)
                .padding(.horizontal, 0)
        }
        .textSelection(.enabled)
    }

    private func color(for severity: String) -> Color {
        switch severity {
        case "high": PortfolixTheme.danger
        case "warning": PortfolixTheme.amber
        default: PortfolixTheme.lilac
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
                    .foregroundStyle(PortfolixTheme.amber)
                Text(localizedText("诊断信息", "Diagnostics", language: language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.primaryText)
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
        .background(PortfolixTheme.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: PortfolixSpacing.sm) {
            Text(title)
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(PortfolixTheme.tertiaryText)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondaryText)
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
        .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.primaryText)
                if let assetName = action.assetName, !assetName.isEmpty {
                    Text([assetName, action.symbol].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(PortfolixTypography.captionEmphasis)
                        .foregroundStyle(PortfolixTheme.lilac)
                }
                Text(recommendationDetails(for: action))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.secondaryText)
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
        case "buy", "increase": PortfolixTheme.mint
        case "sell", "exit": PortfolixTheme.danger
        case "reduce": PortfolixTheme.amber
        case "hold": PortfolixTheme.lilac
        case "review_reduce": PortfolixTheme.amber
        case "review_replenish": PortfolixTheme.mint
        case "rebalance": PortfolixTheme.lilac
        case "maintain": PortfolixTheme.mint
        default: PortfolixTheme.secondaryText
        }
    }
}

private struct AIReportAssetAlertMessageRow: View {
    let alert: AIAssetAlert
    let language: AppLanguage

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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.primaryText)
                }
                if !assetLabel.isEmpty {
                    Text(assetLabel)
                        .font(PortfolixTypography.captionEmphasis)
                        .foregroundStyle(PortfolixTheme.lilac)
                }
                Text(AIUserFacingTextSanitizer.sanitize(alert.reason))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !alert.sourceDomains.isEmpty {
                    Text(alert.sourceDomains.prefix(3).joined(separator: " · "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PortfolixTheme.tertiaryText)
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
                PortfolixTheme.danger,
                "exclamationmark.triangle.fill"
            )
        }
        return (
            PortfolixTheme.amber,
            "exclamationmark.circle.fill"
        )
    }
}

private struct AIReportChatComposer: View {
    let canGenerate: Bool
    let canSendFollowUp: Bool
    let isAwaitingResponse: Bool
    let hasReport: Bool
    let language: AppLanguage
    let generate: () -> Void
    let sendFollowUp: (String) -> Void
    @State private var draftBuffer = AIReportComposerDraftBuffer()
    @State private var hasDraftText = false
    @State private var isSubmitting = false
    @StateObject private var voiceRecorder = HoldingVoiceRecorder()
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AIReportComposerMetrics.controlSpacing) {
            HStack(spacing: PortfolixSpacing.sm) {
                ZStack {
                    TextField(placeholder, text: draftTextBinding)
                        .textFieldStyle(.plain)
                        .font(PortfolixTypography.body)
                        .foregroundStyle(PortfolixTheme.primaryText)
                        .lineLimit(1)
                        .focused($isComposerFocused)
                        .opacity(isVoiceActive ? 0 : 1)
                        .allowsHitTesting(!isVoiceActive)
                        .onSubmit {
                            queueFollowUpSubmission()
                        }

                    if isVoiceActive {
                        HoldingVoiceWaveform(snapshot: voiceRecorder.waveform)
                        .padding(.vertical, PortfolixSpacing.xs)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)

                Button {
                    isComposerFocused = false
                    voiceRecorder.toggle()
                } label: {
                    Image(systemName: isVoiceActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isVoiceActive ? PortfolixTheme.lilac : PortfolixTheme.secondaryText)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(voiceButtonHelp)
            }
            .padding(.leading, PortfolixSpacing.lg)
            .padding(.trailing, PortfolixSpacing.sm)
            .frame(maxWidth: .infinity)
            .frame(height: AIReportComposerMetrics.controlHeight)
            .background {
                Color.clear
                    .portfolixGlass(
                        in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous),
                        tint: isVoiceActive ? PortfolixTheme.violet.opacity(0.18) : nil,
                        fallbackTint: isVoiceActive ? PortfolixTheme.violet : PortfolixTheme.panelElevated,
                        fallbackOpacity: isVoiceActive ? 0.14 : 0.68
                    )
            }
            .layoutPriority(1)

            AIReportComposerActionButton(
                mode: composerAction,
                title: composerAction.title(hasReport: hasReport, language: language),
                isEnabled: canPerformComposerAction
            ) {
                guard canPerformComposerAction else { return }
                switch composerAction {
                case .send: queueFollowUpSubmission()
                case .analyze: generate()
                }
            }
        }
        .padding(.horizontal, PortfolixLayout.chatComposerHorizontalInset)
        .padding(.top, PortfolixLayout.chatComposerTopInset)
        .padding(.bottom, PortfolixLayout.chatComposerBottomInset)
        .onAppear { configureVoiceRecorder() }
        .onChange(of: language) { _, _ in configureVoiceRecorder() }
        .onChange(of: isAwaitingResponse) { wasAwaitingResponse, isAwaitingResponse in
            guard AIReportComposerFocusPolicy.shouldRestoreFocus(
                wasAwaitingResponse: wasAwaitingResponse,
                isAwaitingResponse: isAwaitingResponse,
                isVoiceActive: isVoiceActive
            ) else { return }
            Task { @MainActor in
                await Task.yield()
                guard !self.isAwaitingResponse, !isVoiceActive else { return }
                isComposerFocused = true
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
        localizedText("向 Portfolix Agent 提问", "Ask Portfolix Agent", language: language)
    }

    private var canSubmitFollowUp: Bool {
        hasDraftText && AIReportComposerAction.send.isEnabled(
            canGenerate: canGenerate, canSendFollowUp: canSendFollowUp,
            isSubmitting: isSubmitting, isAwaitingResponse: isAwaitingResponse, isVoiceActive: isVoiceActive
        )
    }

    private var composerAction: AIReportComposerAction {
        AIReportComposerAction(hasDraftText: hasDraftText)
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
        Binding(
            get: { draftBuffer.text },
            set: { value in
                draftBuffer.replace(with: value)
                let containsText = draftBuffer.hasContent
                if hasDraftText != containsText {
                    hasDraftText = containsText
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
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            isSubmitting = false
            sendFollowUp(question)
        }
    }
}

enum AIReportComposerMetrics {
    static let controlHeight: CGFloat = PortfolixSpacing.xxxl
    static let controlSpacing: CGFloat = PortfolixLayout.chatComposerHorizontalInset
}

enum AIReportComposerAction: CaseIterable {
    case analyze
    case send

    init(hasDraftText: Bool) {
        self = hasDraftText ? .send : .analyze
    }

    var symbol: String { self == .send ? "arrow.up" : "sparkles" }

    func title(hasReport: Bool, language: AppLanguage) -> String {
        switch self {
        case .send: localizedText("发送问题", "Send question", language: language)
        case .analyze: hasReport
            ? localizedText("重新分析", "Analyze Again", language: language)
            : localizedText("生成分析", "Generate", language: language)
        }
    }

    func isEnabled(canGenerate: Bool, canSendFollowUp: Bool, isSubmitting: Bool,
                   isAwaitingResponse: Bool, isVoiceActive: Bool) -> Bool {
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
        Button(action: action) {
            Image(systemName: mode.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: AIReportComposerMetrics.controlHeight, height: AIReportComposerMetrics.controlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(PrimaryButtonStyle(
            preservesLabelSize: true, cornerRadius: AIReportComposerMetrics.controlHeight / 2
        ))
        .disabled(!isEnabled)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct AIReportStatusCard: View {
    let status: AIAnalysisRunStatus
    let hasPositions: Bool
    let hasLLMKey: Bool
    let usesConnectedMode: Bool
    let report: AIAnalysisReport?
    let run: AIAnalysisRun
    let language: AppLanguage

    var body: some View {
        Panel(padding: PortfolixSpacing.md) {
            if isRunningStatus {
                statusContent(
                    title: title,
                    detail: runningDetail,
                    icon: {
                        AIReportAgentThinkingIcon()
                    }
                )
            } else {
                statusContent(
                    title: title,
                    detail: detail,
                    icon: {
                        StatusSymbolIcon(symbol: symbol, color: color)
                    }
                )
            }
        }
    }

    private func statusContent<Icon: View>(title: String, detail: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.md) {
            icon()

            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.primaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: PortfolixSpacing.md)

            if isRunningStatus {
                CapsuleLabel(
                    title: localizedText("Agent 工作中", "Agent Running", language: language),
                    color: PortfolixTheme.lilac,
                    symbol: "sparkles"
                )
            }
        }
        .frame(height: 64, alignment: .center)
    }

    private var isRunningStatus: Bool {
        if case .running = status {
            return true
        }
        return false
    }

    private var runningDetail: String {
        guard case let .running(progress) = status else {
            return status.title(language: language)
        }
        return progress.detail(language: language)
    }

    private var title: String {
        if !hasPositions {
            return localizedText("等待持仓数据", "Waiting for holdings", language: language)
        }
        if !hasLLMKey {
            return localizedText("需要完成 API 配置", "API configuration required", language: language)
        }
        if case .running = status {
            return status.title(language: language)
        }
        if case .failed = status {
            return status.title(language: language)
        }
        if report != nil {
            return localizedText("上次分析已生成", "Last Analysis Ready", language: language)
        }
        return status.title(language: language)
    }

    private var detail: String {
        if !hasPositions {
            return localizedText("添加持仓后即可生成标准分析", "Add holdings to generate a standard analysis", language: language)
        }
        if !hasLLMKey {
            return localizedText("请在系统设置中配置并验证 DeepSeek API Key", "Configure and validate a DeepSeek API key in Settings", language: language)
        }
        if case .running = status {
            return status.title(language: language)
        }
        if case .failed = status {
            return localizedText("请检查 API 配置或稍后重试", "Check API settings or try again later", language: language)
        }
        if let report {
            let modeText = report.sources.isEmpty ? localizedText("基础模式", "Basic", language: language) : localizedText("联网增强", "Connected", language: language)
            let sourceText = report.sources.isEmpty ? localizedText("未使用外部检索", "No external search", language: language) : localizedText("\(report.sources.count) 个来源", "\(report.sources.count) sources", language: language)
            let fallbackText = run.usedFallback ? localizedText(" · 已使用回退", " · fallback used", language: language) : ""
            return "\(relativeText(report.generatedAt, language: language)) · \(modeText) · \(report.model) · \(sourceText)\(fallbackText)"
        }
        return usesConnectedMode
            ? localizedText("使用本地持仓、风险偏好和联网检索生成增强报告", "Uses local holdings, risk profile, and web search for an enhanced report", language: language)
            : localizedText("使用本地持仓、风险偏好和结构化行情生成标准报告", "Uses local holdings, risk profile, and structured market data for a standard report", language: language)
    }

    private var symbol: String {
        if !hasPositions || !hasLLMKey {
            return "exclamationmark.circle.fill"
        }
        if case .running = status {
            return "sparkles"
        }
        if case .failed = status {
            return "exclamationmark.triangle.fill"
        }
        return report == nil ? "sparkles" : "checkmark.circle.fill"
    }

    private var color: Color {
        if !hasPositions || !hasLLMKey {
            return PortfolixTheme.amber
        }
        if case .failed = status {
            return PortfolixTheme.danger
        }
        return PortfolixTheme.mint
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

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 32, height: 32)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 40, height: 40, alignment: .center)
    }
}

private struct AIReportEmptyCard: View {
    let language: AppLanguage
    let hasPositions: Bool

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(
                    title: localizedText("尚无持仓分析", "No Analysis Yet", language: language),
                    symbol: "doc.text.magnifyingglass"
                )
                Text(
                    hasPositions
                        ? localizedText("点击生成分析后，Agent 会结合持仓、风险偏好和行情数据生成报告", "Generate an analysis from holdings, risk profile, and market data", language: language)
                        : localizedText("添加持仓后可生成分析", "Add holdings to generate an analysis", language: language)
                )
                .font(PortfolixTypography.body)
                .foregroundStyle(PortfolixTheme.secondaryText)
            }
            .frame(minHeight: 160, alignment: .topLeading)
        }
    }
}

private struct AIReportSummaryCard: View {
    let report: AIAnalysisReport?
    let isLoading: Bool
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.lg) {
                SectionHeader(
                    title: localizedText("核心结论", "Core Takeaway", language: language),
                    symbol: "target"
                )

                if isLoading {
                    AIReportLoadingBlock(lineCount: 4)
                } else if let report {
                    Text(AIUserFacingTextSanitizer.sanitize(report.summary))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.primaryText)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AIUserFacingTextSanitizer.sanitize(report.healthScoreExplanation))
                        .font(PortfolixTypography.body)
                        .foregroundStyle(PortfolixTheme.secondaryText)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    AIReportPlaceholder(text: localizedText("生成后显示今日结论与评分解释", "The summary and score explanation will appear here", language: language))
                }
            }
            .frame(minHeight: 240, alignment: .topLeading)
        }
    }
}

private struct AIReportMetaCard: View {
    let report: AIAnalysisReport
    let run: AIAnalysisRun
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(
                    title: localizedText("报告状态", "Report Status", language: language),
                    symbol: "checkmark.shield"
                )
                AIReportMetaRow(title: localizedText("模型", "Model", language: language), value: report.model)
                AIReportMetaRow(title: localizedText("风险档案", "Risk Profile", language: language), value: "v\(report.riskProfileVersion)")
                AIReportMetaRow(title: localizedText("生成时间", "Generated", language: language), value: relativeText(report.generatedAt, language: language))
                AIReportMetaRow(
                    title: localizedText("检索来源", "Sources", language: language),
                    value: report.sources.isEmpty ? localizedText("基础模式", "Basic", language: language) : "\(report.sources.count)"
                )
                if run.usedFallback {
                    CapsuleLabel(
                        title: localizedText("已使用安全回退", "Fallback Used", language: language),
                        color: PortfolixTheme.amber,
                        symbol: "exclamationmark.triangle.fill"
                    )
                }
            }
            .frame(minHeight: 184, alignment: .topLeading)
        }
    }
}

private struct AIReportMetaRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.tertiaryText)
            Spacer()
            Text(value)
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(PortfolixTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

private struct AIReportRebalanceCard: View {
    let report: AIAnalysisReport?
    let isLoading: Bool
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(
                    title: localizedText("投资组合建议", "Portfolio Recommendations", language: language),
                    symbol: "arrow.triangle.2.circlepath"
                )
                let actions = report?.rebalanceActions ?? []
                if isLoading {
                    AIReportLoadingBlock(lineCount: 4)
                } else if report == nil {
                    AIReportPlaceholder(text: localizedText("生成后显示投资组合优化建议", "Portfolio recommendations will appear here", language: language))
                } else if actions.isEmpty {
                    AIReportPlaceholder(text: localizedText("暂无明确投资组合建议", "No portfolio recommendations", language: language))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: PortfolixSpacing.md) {
                        ForEach(actions.prefix(4)) { action in
                            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                                HStack(spacing: PortfolixSpacing.sm) {
                                    Image(systemName: symbol(for: action.action))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(color(for: action.action))
                                        .frame(width: 18)
                                    Text(AIUserFacingTextSanitizer.sanitize(action.title))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(PortfolixTheme.primaryText)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                if let assetName = action.assetName, !assetName.isEmpty {
                                    Text([assetName, action.symbol].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(PortfolixTypography.captionEmphasis)
                                        .foregroundStyle(PortfolixTheme.lilac)
                                        .lineLimit(1)
                                }
                                Text(recommendationDetails(for: action))
                                    .font(PortfolixTypography.caption)
                                    .foregroundStyle(PortfolixTheme.secondaryText)
                                    .lineLimit(5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(PortfolixSpacing.md)
                            .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
                        }
                    }
                }
            }
            .frame(minHeight: 240, alignment: .topLeading)
        }
    }

    private func symbol(for action: String) -> String {
        switch action {
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

    private func color(for action: String) -> Color {
        switch action {
        case "buy", "increase": PortfolixTheme.mint
        case "sell", "exit": PortfolixTheme.danger
        case "reduce": PortfolixTheme.amber
        case "hold": PortfolixTheme.lilac
        case "review_reduce": PortfolixTheme.amber
        case "review_replenish": PortfolixTheme.mint
        case "rebalance": PortfolixTheme.lilac
        case "maintain": PortfolixTheme.mint
        default: PortfolixTheme.secondaryText
        }
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

private struct AIReportRiskList: View {
    let report: AIAnalysisReport?
    let isLoading: Bool
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("风险因素", "Risk Factors", language: language), symbol: "exclamationmark.triangle")
                if isLoading {
                    AIReportLoadingBlock(lineCount: 5)
                } else if report == nil {
                    AIReportPlaceholder(text: localizedText("生成后显示需要关注的风险因素", "Risk factors will appear here", language: language))
                } else if report?.riskItems.isEmpty ?? true {
                    AIReportPlaceholder(text: localizedText("暂无明显风险项", "No prominent risk items", language: language))
                } else {
                    ForEach((report?.riskItems ?? []).prefix(6)) { item in
                        AIReportBullet(
                            title: item.title,
                            body: item.impact,
                            color: color(for: item.severity),
                            symbol: item.severity == "high" ? "exclamationmark.octagon.fill" : "exclamationmark.circle.fill"
                        )
                    }
                }
            }
            .frame(minHeight: 240, alignment: .topLeading)
        }
    }

    private func color(for severity: String) -> Color {
        switch severity {
        case "high": PortfolixTheme.danger
        case "warning": PortfolixTheme.amber
        default: PortfolixTheme.lilac
        }
    }
}

private struct AIReportAssetAlerts: View {
    let report: AIAnalysisReport?
    let isLoading: Bool
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("重点关注", "Watchlist", language: language), symbol: "scope")
                if isLoading {
                    AIReportLoadingBlock(lineCount: 5)
                } else if report == nil {
                    AIReportPlaceholder(text: localizedText("生成后显示重点资产与相关来源", "Key assets and embedded sources will appear here", language: language))
                } else if report?.assetAlerts.isEmpty ?? true {
                    AIReportPlaceholder(text: localizedText("暂无资产关注项", "No asset alerts", language: language))
                } else {
                    ForEach((report?.assetAlerts ?? []).prefix(6)) { alert in
                        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.assetName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(PortfolixTheme.primaryText)
                                        .lineLimit(1)
                                    Text(alert.symbol)
                                        .font(PortfolixTypography.captionEmphasis)
                                        .foregroundStyle(PortfolixTheme.tertiaryText)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: PortfolixSpacing.md)

                                riskBadge(for: alert)
                            }
                            Text(alert.reason)
                                .font(PortfolixTypography.caption)
                                .foregroundStyle(PortfolixTheme.secondaryText)
                                .lineLimit(3)
                        }
                        .padding(PortfolixSpacing.md)
                        .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
                    }
                }
            }
            .frame(minHeight: 240, alignment: .topLeading)
        }
    }

    private func riskBadge(for alert: AIAssetAlert) -> some View {
        let risk = riskLevel(for: alert)
        return CapsuleLabel(title: risk.title, color: risk.color, symbol: risk.symbol)
    }

    private func riskLevel(for alert: AIAssetAlert) -> (title: String, color: Color, symbol: String) {
        let text = "\(alert.title) \(alert.reason)".lowercased()
        let highRiskHints = ["高风险", "剧烈", "回撤", "监管", "亏损", "集中", "超限", "high", "drawdown", "regulatory", "concentration"]
        let isHigh = highRiskHints.contains { text.localizedCaseInsensitiveContains($0) }
        if isHigh {
            return (
                localizedText("高风险", "High Risk", language: language),
                PortfolixTheme.danger,
                "exclamationmark.triangle.fill"
            )
        }
        return (
            localizedText("中风险", "Medium Risk", language: language),
            PortfolixTheme.amber,
            "exclamationmark.circle.fill"
        )
    }
}

private struct AIReportQuestionCard: View {
    let report: AIAnalysisReport?
    let isLoading: Bool
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("可复核问题", "Questions", language: language), symbol: "questionmark.circle")
                if isLoading {
                    AIReportLoadingBlock(lineCount: 4)
                } else if report == nil {
                    AIReportPlaceholder(text: localizedText("生成后显示适合你复核的问题", "Review questions will appear here", language: language))
                } else {
                    let questions = report?.questionsToConsider ?? []
                    if questions.isEmpty {
                        AIReportPlaceholder(text: localizedText("暂无需要额外复核的问题", "No review questions for now", language: language))
                    } else {
                        ForEach(Array(questions.prefix(5).enumerated()), id: \.offset) { _, question in
                            AIReportBullet(title: question, body: nil, color: PortfolixTheme.lilac, symbol: "checkmark.circle.fill")
                        }
                    }
                }
            }
            .frame(minHeight: 196, alignment: .topLeading)
        }
    }
}

private struct AIReportLimitationsCard: View {
    let report: AIAnalysisReport?
    let isLoading: Bool
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("限制说明", "Limitations", language: language), symbol: "shield.lefthalf.filled")
                if isLoading {
                    AIReportLoadingBlock(lineCount: 4)
                } else if report == nil {
                    AIReportPlaceholder(text: localizedText("生成后显示本次分析的边界与假设", "Analysis boundaries and assumptions will appear here", language: language))
                } else {
                    let limitations = report?.limitations ?? []
                    if limitations.isEmpty {
                        AIReportPlaceholder(text: localizedText("暂无额外限制说明", "No extra limitations", language: language))
                    } else {
                        ForEach(Array(limitations.prefix(5).enumerated()), id: \.offset) { _, limitation in
                            AIReportBullet(title: limitation, body: nil, color: PortfolixTheme.secondaryText, symbol: "info.circle.fill")
                        }
                    }
                }
            }
            .frame(minHeight: 196, alignment: .topLeading)
        }
    }
}

private struct AIReportSourceLinks: View {
    let sources: [AIReportSource]

    var body: some View {
        if !sources.isEmpty {
            HStack(spacing: PortfolixSpacing.xs) {
                ForEach(sources) { source in
                    if let url = URL(string: source.url) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(source.domain)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PortfolixTheme.lilac)
                            .padding(.horizontal, PortfolixSpacing.sm)
                            .padding(.vertical, 4)
                            .background(PortfolixTheme.lilac.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct AIReportDataQualityCard: View {
    let report: AIAnalysisReport
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("数据质量", "Data Quality", language: language), symbol: "waveform.path.ecg")
                ForEach(Array(report.dataQualityNotes.prefix(5).enumerated()), id: \.offset) { _, note in
                    AIReportBullet(title: note, body: nil, color: PortfolixTheme.mint, symbol: "info.circle.fill")
                }
            }
        }
    }
}

private struct AIReportSourcesCard: View {
    let report: AIAnalysisReport
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("引用来源", "Sources", language: language), symbol: "link")
                if report.sources.isEmpty {
                    AIReportPlaceholder(text: localizedText("本次报告未包含外部来源", "No external sources in this report", language: language))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: PortfolixSpacing.md) {
                        ForEach(report.sources.prefix(12)) { source in
                            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                                HStack(spacing: PortfolixSpacing.sm) {
                                    Text(source.domain)
                                        .font(PortfolixTypography.captionEmphasis)
                                        .foregroundStyle(PortfolixTheme.primaryText)
                                        .lineLimit(1)
                                    CapsuleLabel(title: source.credibility.title(language: language), color: PortfolixTheme.lilac)
                                }
                                Text(source.title)
                                    .font(PortfolixTypography.caption)
                                    .foregroundStyle(PortfolixTheme.secondaryText)
                                    .lineLimit(2)
                                Text(source.assetName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(PortfolixTheme.tertiaryText)
                                    .lineLimit(1)
                            }
                            .padding(PortfolixSpacing.md)
                            .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
                        }
                    }
                }
            }
        }
    }
}

private struct AIReportDisclaimer: View {
    let language: AppLanguage

    var body: some View {
        Text(localizedText(AIAdviceDisclosure.text, "Generated by AI from available data for reference only. Not investment advice.", language: language))
            .font(PortfolixTypography.caption)
            .foregroundStyle(PortfolixTheme.tertiaryText)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PortfolixTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let bodyText {
                    Text(bodyText)
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct AIReportPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PortfolixTypography.body)
            .foregroundStyle(PortfolixTheme.tertiaryText)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }
}

private struct AIReportLoadingBlock: View {
    let lineCount: Int

    var body: some View {
        VStack(spacing: PortfolixSpacing.sm) {
            AIReportAgentThinkingIcon(size: 78)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        .accessibilityLabel("Generating analysis")
    }
}

private func relativeText(_ date: Date, language: AppLanguage) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 {
        return localizedText("刚刚", "Just now", language: language)
    }
    let minutes = seconds / 60
    if minutes < 60 {
        return language == .english ? "\(minutes)m ago" : "\(minutes) 分钟前"
    }
    let hours = minutes / 60
    if hours < 24 {
        return language == .english ? "\(hours)h ago" : "\(hours) 小时前"
    }
    let days = hours / 24
    return language == .english ? "\(days)d ago" : "\(days) 天前"
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
                        score: portfolioMatchScore,
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
                            actualValue: largestPositionPercent,
                            limitLabel: localizedText("上限", "Limit", language: store.appLanguage),
                            value: $store.positionLimit,
                            range: 10 ... 60,
                            mode: .maximum,
                            language: store.appLanguage,
                            onCommit: { store.saveRiskThresholdVersion() }
                        )

                        RiskConstraintSliderRow(
                            title: localizedText("数字货币最大占比", "Max Crypto", language: store.appLanguage),
                            actualLabel: localizedText("当前数字货币", "Current Crypto", language: store.appLanguage),
                            actualValue: cryptoAllocationPercent,
                            limitLabel: localizedText("上限", "Limit", language: store.appLanguage),
                            value: $store.cryptoLimit,
                            range: 0 ... 50,
                            mode: .maximum,
                            language: store.appLanguage,
                            onCommit: { store.saveRiskThresholdVersion() }
                        )

                        RiskConstraintSliderRow(
                            title: localizedText("非 CNY 计价资产最大占比", "Max Non-CNY Assets", language: store.appLanguage),
                            actualLabel: localizedText("当前非 CNY", "Current Non-CNY", language: store.appLanguage),
                            actualValue: nonCNYAllocationPercent,
                            limitLabel: localizedText("上限", "Limit", language: store.appLanguage),
                            value: $store.foreignCurrencyLimit,
                            range: 10 ... 90,
                            mode: .maximum,
                            language: store.appLanguage,
                            onCommit: { store.saveRiskThresholdVersion() }
                        )

                        RiskConstraintSliderRow(
                            title: localizedText("最低现金占比", "Minimum Cash", language: store.appLanguage),
                            actualLabel: localizedText("当前现金", "Current Cash", language: store.appLanguage),
                            actualValue: cashAllocationPercent,
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
                    status: reviewStatus,
                    isConfigured: store.riskProfileConfigured,
                    version: store.riskProfileVersion,
                    updatedAt: store.riskProfileUpdatedAt,
                    language: store.appLanguage
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isQuestionnairePresented) {
            RiskQuestionnaireSheet()
                .environment(store)
        }
    }

    private var localizedRiskLevel: String {
        guard store.appLanguage == .english else { return store.riskLevel }
        switch store.riskLevel {
        case "保守稳健":
            return "Conservative"
        case "稳健平衡":
            return "Balanced"
        case "积极成长":
            return "Growth"
        case "未配置":
            return "Not configured"
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
            return localizedText("更重视本金稳定与波动控制，适合以低波动资产为核心", "Prioritizes capital stability and volatility control, with lower-volatility assets as the core", language: store.appLanguage)
        case "积极成长":
            return localizedText("可承受较高波动，偏向以长期增长和资产弹性换取潜在收益", "Accepts higher volatility in pursuit of long-term growth and portfolio upside", language: store.appLanguage)
        case "稳健平衡":
            return localizedText("在收益机会与波动控制之间保持平衡，适合多资产分散配置", "Balances return opportunities with volatility control through diversified allocation", language: store.appLanguage)
        default:
            return localizedText("基于问卷与关键约束生成的风险偏好说明", "A risk profile summary based on the questionnaire and key constraints", language: store.appLanguage)
        }
    }

    private var riskEvaluation: RiskConstraintEvaluation {
        store.riskConstraintEvaluation
    }

    private var largestPositionPercent: Double {
        riskEvaluation.largestPositionPercent
    }

    private var largestPositionLabel: String {
        riskEvaluation.largestPositionName ?? localizedText("暂无持仓", "No holdings", language: store.appLanguage)
    }

    private var cryptoAllocationPercent: Double {
        riskEvaluation.cryptoAllocationPercent
    }

    private var nonCNYAllocationPercent: Double {
        riskEvaluation.nonCNYAllocationPercent
    }

    private var cashAllocationPercent: Double {
        riskEvaluation.cashAllocationPercent
    }

    private var constraintResults: [Bool] {
        riskEvaluation.results
    }

    private var constraintCount: Int {
        constraintResults.count
    }

    private var passedConstraintCount: Int {
        constraintResults.filter(\.self).count
    }

    private var breachCount: Int {
        constraintCount - passedConstraintCount
    }

    private var portfolioMatchScore: Double? {
        riskEvaluation.matchScore
    }

    private var reviewStatus: RiskReviewStatus {
        if !store.riskProfileConfigured {
            return .notConfigured
        }
        if riskEvaluation.shouldSuggestReview {
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
            PortfolixTheme.mint
        case .reviewSuggested:
            PortfolixTheme.amber
        case .notConfigured:
            PortfolixTheme.tertiaryText
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
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(PortfolixTheme.lilac)
                            .lineLimit(1)

                        Text(description)
                            .font(PortfolixTypography.caption)
                            .foregroundStyle(PortfolixTheme.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: PortfolixSpacing.xs) {
                        Text(tolerance)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(PortfolixTheme.primaryText)
                            .lineLimit(1)
                        Text(localizedText("风险承受度", "Risk Tolerance", language: language))
                            .font(PortfolixTypography.captionEmphasis)
                            .foregroundStyle(PortfolixTheme.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    CardMetaLabel(
                        title: riskProfileVersionLabel(
                            isConfigured: isConfigured,
                            version: version,
                            updatedAt: updatedAt,
                            now: context.date,
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
                SectionHeader(title: localizedText("约束匹配度", "Constraint Fit", language: language), symbol: "target")

                HStack(alignment: .center, spacing: PortfolixSpacing.xl) {
                    VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                        Text(scoreText)
                            .font(.system(size: 32, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(scoreColor)
                        Text(localizedText("关键约束匹配", "Key constraint fit", language: language))
                            .font(PortfolixTypography.caption)
                            .foregroundStyle(PortfolixTheme.tertiaryText)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: PortfolixSpacing.sm) {
                        RiskCountPill(
                            title: localizedText("通过", "Passed", language: language),
                            value: "\(passedCount)/\(totalCount)",
                            color: PortfolixTheme.mint
                        )
                        RiskCountPill(
                            title: localizedText("需关注", "Watch", language: language),
                            value: "\(breachCount)",
                            color: breachCount == 0 ? PortfolixTheme.tertiaryText : PortfolixTheme.amber
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
            return PortfolixTheme.tertiaryText
        }
        if score >= 75 {
            return PortfolixTheme.mint
        }
        if score >= 50 {
            return PortfolixTheme.amber
        }
        return PortfolixTheme.danger
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PortfolixTheme.primaryText)
                        .lineLimit(1)

                    Text(actualCaption)
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.tertiaryText)
                        .lineLimit(1)
                }
                .frame(width: leadingWidth, alignment: .leading)

                HStack(spacing: PortfolixSpacing.md) {
                    Slider(value: $value, in: range, step: 5) { isEditing in
                        if !isEditing {
                            onCommit()
                        }
                    }
                        .tint(PortfolixTheme.controlAccent)

                    VStack(alignment: .trailing, spacing: PortfolixSpacing.xs) {
                        Text("\(limitLabel) \(percentText(value))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PortfolixTheme.secondaryText)
                            .monospacedDigit()
                            .lineLimit(1)

                        RiskLimitBadge(
                            title: isPassing ? localizedText("正常", "OK", language: language) : localizedText("需关注", "Watch", language: language),
                            color: isPassing ? PortfolixTheme.mint : PortfolixTheme.amber,
                            textColor: isPassing ? PortfolixTheme.positiveStatusText : PortfolixTheme.warningStatusText
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
        SettingsSection(title: localizedText("复评维护", "Review", language: language), symbol: "calendar.badge.clock") {
            SettingsRow(title: localizedText("当前状态", "Status", language: language)) {
                RiskStatusValue(status: status, language: language)
            }
            SettingsDivider()
            SettingsRow(title: localizedText("复评周期", "Cadence", language: language)) {
                RiskSettingValue(localizedText("6 个月", "6 months", language: language))
            }
            SettingsDivider()
            SettingsRow(title: localizedText("档案版本", "Version", language: language)) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    RiskSettingValue(
                        riskProfileVersionLabel(
                            isConfigured: isConfigured,
                            version: version,
                            updatedAt: updatedAt,
                            now: context.date,
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
        .font(.system(size: 12, weight: .semibold))
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
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PortfolixTheme.primaryText)
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
                .foregroundStyle(PortfolixTheme.tertiaryText)
            Text(value)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
    }
}

private struct RiskLimitBadge: View {
    let title: String
    let color: Color
    let textColor: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
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
    @State private var configurationSheet: SettingsConfigurationSheet?
    @State private var preparedDataImport: PreparedPortfolixDataImport?
    @State private var isImportConfirmationPresented = false
    @State private var dataTransferNotice: DataTransferNotice?
    @State private var exportStatus: DataTransferInlineStatus = .idle
    @State private var importStatus: DataTransferInlineStatus = .idle
    @State private var exportStatusResetTask: Task<Void, Never>?
    @State private var importStatusResetTask: Task<Void, Never>?

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                PageHeader(title: settingsText("系统设置", "Settings"))

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

                SettingsSection(title: settingsText("智能分析", "Smart Analysis"), symbol: "sparkles.rectangle.stack") {
                    SettingsToggleRow(
                        title: settingsText("AI 资产分析", "AI Asset Analysis"),
                        helpText: settingsText(
                            "开启后，Portfolix 将通过 DeepSeek 分析您的资产组合、收益及风险偏好。",
                            "When enabled, Portfolix uses DeepSeek to analyze your portfolio, returns, and risk preferences."
                        ),
                        helpPlacement: .trailing,
                        isOn: $store.aiConfiguration.isEnabled
                    )
                    SettingsDivider()
                    SettingsRow(
                        title: settingsText("分析模式", "Analysis Mode"),
                        helpText: settingsText(
                            "基础模式仅使用组合数据；联网增强会按需调用已启用的搜索服务。",
                            "Basic uses portfolio data only; Connected calls enabled search services when needed."
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
                        Label(settingsText("仅本机", "Local only"), systemImage: "lock.shield.fill")
                            .font(PortfolixTypography.captionEmphasis)
                            .foregroundStyle(PortfolixTheme.mint)
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: settingsText("数据导出", "Data Export"),
                        helpText: settingsText(
                            "将持仓、历史收益、资产价格和风险偏好导出为结构化数据包，不包含智能分析数据、API Key 和设备相关设置。",
                            "Exports holdings, return history, asset prices, and risk preferences as a structured data package. Smart analysis data, API keys, and device-specific settings are excluded."
                        ),
                        helpPlacement: .trailing
                    ) {
                        HStack(spacing: PortfolixSpacing.md) {
                            DataTransferInlineStatusView(status: exportStatus)
                            Button(settingsText("创建导出", "Create Export"), action: createDataExport)
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
        .scrollIndicators(.hidden)
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
            }
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
        .alert(item: $dataTransferNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(settingsText("完成", "Done")))
            )
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
            withAnimation(.easeOut(duration: 0.15)) {
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
            withAnimation(.easeOut(duration: 0.15)) {
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
                PortfolixTheme.tertiaryText,
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
            }
        }
        if states.contains(.invalid) {
            return (settingsText("验证失败", "Validation failed"), PortfolixTheme.danger, "xmark.circle.fill")
        }
        if states.contains(where: { $0 != .ready }) {
            return (settingsText("待验证", "Needs validation"), PortfolixTheme.amber, "exclamationmark.circle.fill")
        }
        return (
            settingsText("已启用 \(providers.count) 个", "\(providers.count) enabled"),
            PortfolixTheme.mint,
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
                .foregroundStyle(PortfolixTheme.tertiaryText)
                .transition(.opacity)
            case let .success(title, detail):
                Label(title, systemImage: "checkmark.circle.fill")
                    .font(PortfolixTypography.captionEmphasis)
                    .foregroundStyle(PortfolixTheme.mint)
                    .help(detail)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .trailing)))
            }
        }
        .lineLimit(1)
        .frame(width: 120, height: 20, alignment: .trailing)
        .animation(.easeOut(duration: 0.15), value: status)
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

    var alignment: Alignment {
        switch self {
        case .top:
            .top
        case .trailing:
            .leading
        }
    }

    var offset: CGSize {
        switch self {
        case .top:
            CGSize(width: 0, height: -PortfolixSpacing.xxxl)
        case .trailing:
            CGSize(width: PortfolixSpacing.xxl, height: 0)
        }
    }

    var transitionAnchor: UnitPoint {
        switch self {
        case .top:
            .bottom
        case .trailing:
            .leading
        }
    }
}

struct HelpIcon: View {
    let text: String
    var placement: HelpTooltipPlacement = .top
    @State private var isHovering = false
    @State private var showsTooltip = false

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PortfolixTheme.tertiaryText)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        guard isHovering else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            showsTooltip = true
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.10)) {
                        showsTooltip = false
                    }
                }
            }
            .overlay(alignment: placement.alignment) {
                if showsTooltip {
                    HelpTooltipBubble(text: text)
                        .overlay {
                            RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                                .stroke(PortfolixTheme.border, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
                        .offset(placement.offset)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: placement.transitionAnchor)))
                        .zIndex(10)
                }
            }
            .accessibilityLabel(text)
    }
}

private struct HelpTooltipBubble: View {
    let text: String
    private let maximumWidth: CGFloat = 260
    private let textSize: CGFloat = 11

    var body: some View {
        tooltipText
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: contentWidth, alignment: .leading)
            .padding(.horizontal, PortfolixSpacing.sm)
            .padding(.vertical, PortfolixSpacing.xs)
        .background(PortfolixTheme.panelSoft, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
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
            .font(.system(size: textSize))
            .foregroundStyle(PortfolixTheme.primaryText)
            .multilineTextAlignment(.leading)
    }
}

private struct SettingsText: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PortfolixTheme.primaryText)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiaryText)
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
                .font(.system(size: 11, weight: .medium))
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
        .foregroundStyle(PortfolixTheme.glassControlText)
        .portfolixGlass(in: Circle(), interactive: true)
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
                    .foregroundStyle(PortfolixTheme.primaryText)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(PortfolixTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            trailing
        }
    }
}
