import AppKit
import SwiftUI

struct PositionsView: View {
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingDeletionID: Position.ID?
    @State private var isBatchSelecting = false
    @State private var selectedBatchPositionIDs: Set<Position.ID> = []
    @State private var isBatchDeletionConfirmationPresented = false
    @State private var operationErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            PageHeader(title: localizedText("持仓明细", "Holdings", language: store.appLanguage)) {
                HStack(spacing: PortfolixSpacing.sm) {
                    if isBatchSelecting {
                        Text(
                            store.appLanguage == .english
                                ? "\(selectedBatchPositionIDs.count) selected"
                                : "\(selectedBatchPositionIDs.count) 项已选"
                        )
                            .font(PortfolixTypography.captionEmphasis)
                            .foregroundStyle(PortfolixTheme.secondaryText)
                            .monospacedDigit()

                        Button(allVisiblePositionsSelected
                            ? localizedText("取消全选", "Deselect All", language: store.appLanguage)
                            : localizedText("全选", "Select All", language: store.appLanguage)
                        ) {
                            toggleAllVisiblePositions()
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(store.filteredPositions.isEmpty)

                        Button(localizedText("取消", "Cancel", language: store.appLanguage)) {
                            exitBatchSelection()
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
                            enterBatchSelection()
                        } label: {
                            Label(localizedText("批量管理", "Batch Manage", language: store.appLanguage), systemImage: "checklist")
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
                        }
                        .padding(.horizontal, PortfolixSpacing.md)
                        .padding(.vertical, PortfolixSpacing.sm)
                        .frame(width: 260)
                        .portfolixGlass(
                            in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous),
                            fallbackTint: PortfolixTheme.panelElevated,
                            fallbackOpacity: 0.62,
                            interactive: true
                        )

                        Spacer()

                        Picker(localizedText("展示币种", "Display Currency", language: store.appLanguage), selection: $store.displayCurrency) {
                            ForEach(DisplayCurrency.allCases) { currency in
                                Text(currency.rawValue).tag(currency)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
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
        .onChange(of: store.positions.map(\.id)) { _, positionIDs in
            selectedBatchPositionIDs.formIntersection(positionIDs)
            if isBatchSelecting, positionIDs.isEmpty {
                exitBatchSelection()
            }
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

    private func isSelected(_ position: Position) -> Bool {
        store.selectedPositionID == position.id
    }

    private func primaryRowColor(for position: Position) -> Color {
        isSelected(position) ? .white : PortfolixTheme.primaryText
    }

    private func secondaryRowColor(for position: Position) -> Color {
        isSelected(position) ? .white.opacity(0.74) : PortfolixTheme.tertiaryText
    }

    private var positionsTable: some View {
        Table(store.filteredPositions, selection: $store.selectedPositionID) {
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
                    .accessibilityHidden(!isBatchSelecting)
                    .allowsHitTesting(isBatchSelecting)
                    .opacity(isBatchSelecting ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isBatchSelecting)
            }
            .width(20)

            TableColumn(localizedText("资产", "Asset", language: store.appLanguage)) { position in
                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    Text(position.name)
                        .foregroundStyle(primaryRowColor(for: position))
                        .lineLimit(1)
                    Text(position.symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(secondaryRowColor(for: position))
                        .lineLimit(1)
                }
            }
            .width(min: 130, ideal: 170)

            TableColumn(localizedText("类别", "Type", language: store.appLanguage)) { position in
                Text(position.category.title(language: store.appLanguage))
                    .foregroundStyle(isSelected(position) ? Color.white : position.category.color)
                    .lineLimit(1)
            }
            .width(76)

            TableColumn(localizedText("份额", "Quantity", language: store.appLanguage)) { position in
                Text(NSDecimalNumber(decimal: position.quantity).stringValue)
                    .foregroundStyle(primaryRowColor(for: position))
                    .monospacedDigit()
            }
            .width(72)

            TableColumn(localizedText("持仓成本", "Cost Basis", language: store.appLanguage)) { position in
                Text(formatMoney(position.averageCost, currency: position.quoteCurrency))
                    .foregroundStyle(primaryRowColor(for: position))
                    .monospacedDigit()
            }
            .width(102)

            TableColumn(localizedText("总成本", "Total Cost", language: store.appLanguage)) { position in
                Text(formatMoney(position.totalCost, currency: position.quoteCurrency))
                    .foregroundStyle(primaryRowColor(for: position))
                    .monospacedDigit()
            }
            .width(116)

            TableColumn(localizedText("最新价格", "Latest Price", language: store.appLanguage)) { position in
                Text(formatMoney(position.latestPrice, currency: position.quoteCurrency))
                    .foregroundStyle(primaryRowColor(for: position))
                    .monospacedDigit()
            }
            .width(104)

            TableColumn(localizedText("当前市值", "Market Value", language: store.appLanguage)) { position in
                Text(formatMoney(store.converted(position.marketValueCNY), currency: store.displayCurrency))
                    .foregroundStyle(primaryRowColor(for: position))
                    .monospacedDigit()
            }
            .width(116)

            TableColumn(localizedText("收益率", "Return Rate", language: store.appLanguage)) { position in
                Text(formatPercent(position.profitRate))
                    .foregroundStyle(
                        isSelected(position)
                            ? Color.white
                            : position.profitRate >= 0 ? PortfolixTheme.mint : PortfolixTheme.danger
                    )
                    .monospacedDigit()
            }
            .width(72)

            TableColumn(localizedText("来源 / 状态", "Source / Status", language: store.appLanguage)) { position in
                HStack(spacing: PortfolixSpacing.sm) {
                    VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                        Text(localizedQuoteSource(position.source, language: store.appLanguage))
                            .foregroundStyle(primaryRowColor(for: position))
                            .lineLimit(1)
                        Text("\(position.priceDateText(language: store.appLanguage)) · \(position.relativeUpdateText(now: store.relativeTimeNow, language: store.appLanguage))")
                            .font(.system(size: 10))
                            .foregroundStyle(secondaryRowColor(for: position))
                            .lineLimit(1)
                    }

                    Spacer(minLength: PortfolixSpacing.sm)

                    if isSelected(position), canRefresh(position) {
                        PositionRefreshButton(
                            position: position,
                            isRefreshing: store.refreshingPositionIDs.contains(position.id),
                            language: store.appLanguage
                        ) {
                            store.refreshPosition(id: position.id)
                        }
                    }
                }
            }
            .width(min: 136, ideal: 160)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .transaction { transaction in
            transaction.animation = nil
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
            if !isBatchSelecting, let positionID = selection.first {
                store.presentPositionEditor(for: positionID)
            }
        }
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

    private func enterBatchSelection() {
        store.selectedPositionID = nil
        selectedBatchPositionIDs = []
        isBatchSelecting = true
    }

    private func exitBatchSelection() {
        selectedBatchPositionIDs = []
        isBatchSelecting = false
    }

    private func toggleAllVisiblePositions() {
        let visibleIDs = Set(store.filteredPositions.map(\.id))
        if visibleIDs.isSubset(of: selectedBatchPositionIDs) {
            selectedBatchPositionIDs.subtract(visibleIDs)
        } else {
            selectedBatchPositionIDs.formUnion(visibleIDs)
        }
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
            exitBatchSelection()
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }
}

struct AIReportView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var draftMessage = ""

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
                hasPositions: !store.positions.isEmpty,
                hasLLMKey: store.hasValidLLMAPIKey,
                hasSearchKey: store.hasValidSearchAPIKey,
                usesConnectedMode: store.searchConfiguration.isEnabled,
                configuredModel: store.aiConfiguration.model,
                draftMessage: $draftMessage,
                language: store.appLanguage,
                generate: requestAnalysis,
                sendFollowUp: sendFollowUp
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear {
            store.refreshProviderCredentialState()
            store.refreshAIAnalysisChatRetention()
        }
    }

    private var isRunning: Bool {
        if case .running = store.aiAnalysisRun.status {
            return true
        }
        return false
    }

    private func requestAnalysis() {
        store.generateAIAnalysis()
    }

    private func sendFollowUp() {
        let question = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !store.isAnsweringAIAnalysisFollowUp else { return }
        draftMessage = ""
        store.submitAIAnalysisFollowUp(question)
    }
}

private struct AIReportChatSurface: View {
    let report: AIAnalysisReport?
    let items: [AIReportChatItem]
    let run: AIAnalysisRun
    let isRunning: Bool
    let isSendingFollowUp: Bool
    let followUpProgress: AIFollowUpProgress?
    let hasPositions: Bool
    let hasLLMKey: Bool
    let hasSearchKey: Bool
    let usesConnectedMode: Bool
    let configuredModel: String
    @Binding var draftMessage: String
    let language: AppLanguage
    let generate: () -> Void
    let sendFollowUp: () -> Void

    var body: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                AIReportChatHeader(
                    report: report,
                    run: run,
                    usesConnectedMode: usesConnectedMode,
                    configuredModel: configuredModel,
                    language: language
                )

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: PortfolixSpacing.lg) {
                            if items.isEmpty && !isRunning {
                                AIReportAgentBubble {
                                    AIReportWelcomeMessage(
                                        hasPositions: hasPositions,
                                        hasLLMKey: hasLLMKey,
                                        hasSearchKey: hasSearchKey,
                                        usesConnectedMode: usesConnectedMode,
                                        language: language
                                    )
                                }
                                .id("welcome")
                            }

                            ForEach(items) { item in
                                switch item.content {
                                case let .user(text):
                                    AIReportUserBubble(text: text)
                                        .id(item.id)
                                case let .report(report, reportRun):
                                    AIReportAgentBubble {
                                        AIReportChatReport(
                                            report: report,
                                            run: reportRun,
                                            language: language
                                        )
                                    }
                                    .id(item.id)
                                case let .assistant(text):
                                    AIReportAgentBubble {
                                        AIReportFollowUpMessage(
                                            text: text,
                                            language: language,
                                            showsDisclaimer: AIChatDisclosurePolicy.shouldShowDisclosure(for: text)
                                        )
                                    }
                                    .id(item.id)
                                }
                            }

                            if isRunning {
                                AIReportAgentBubble {
                                    AIReportAgentProgressMessage(
                                        status: run.status,
                                        language: language
                                    )
                                }
                                .id("analysis-progress")
                            } else if isSendingFollowUp {
                                AIReportAgentBubble {
                                    AIReportFollowUpProgressMessage(
                                        progress: followUpProgress ?? .analyzing,
                                        language: language
                                    )
                                }
                                .id("follow-up-progress")
                            } else if shouldShowStatusMessage {
                                AIReportAgentBubble {
                                    AIReportStaticStatusMessage(
                                        status: run.status,
                                        hasPositions: hasPositions,
                                        hasLLMKey: hasLLMKey,
                                        hasSearchKey: hasSearchKey,
                                        usesConnectedMode: usesConnectedMode,
                                        language: language
                                    )
                                }
                                .id("analysis-status")
                            }

                            Color.clear
                                .frame(height: PortfolixSpacing.xl)
                                .id("chat-bottom")
                        }
                        .padding(.horizontal, PortfolixSpacing.lg)
                        .padding(.top, PortfolixSpacing.lg)
                        .padding(.bottom, PortfolixSpacing.md)
                        .textSelection(.enabled)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear {
                        scrollToBottom(proxy, animated: false, delay: 0.08)
                    }
                    .onChange(of: items.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: run.status) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: followUpProgress) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: isSendingFollowUp) { _, _ in
                        scrollToBottom(proxy)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

                Divider()

                AIReportChatComposer(
                    draftMessage: $draftMessage,
                    canGenerate: hasPositions && !isRunning,
                    canSendFollowUp: report != nil && !isRunning && !isSendingFollowUp,
                    hasReport: hasReport,
                    language: language,
                    generate: generate,
                    sendFollowUp: sendFollowUp
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true, delay: TimeInterval = 0.02) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
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
        case .missingConfiguration, .failed:
            true
        case .running:
            false
        }
    }
}

private struct AIReportChatHeader: View {
    let report: AIAnalysisReport?
    let run: AIAnalysisRun
    let usesConnectedMode: Bool
    let configuredModel: String
    let language: AppLanguage

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

            Spacer()

            HStack(spacing: PortfolixSpacing.md) {
                AIReportHeaderStatusTag(
                    title: model,
                    symbol: "cpu",
                    help: localizedText("当前 LLM 模型", "Current LLM model", language: language)
                )

                AIReportHeaderStatusTag(
                    title: usesConnectedMode
                        ? localizedText("联网增强", "Connected", language: language)
                        : localizedText("基础模式", "Basic", language: language),
                    symbol: usesConnectedMode ? "network" : "lock.laptopcomputer",
                    help: usesConnectedMode
                        ? localizedText("允许按需联网搜索", "Connected search is available when needed", language: language)
                        : localizedText("仅使用持仓数据和模型知识", "Uses holdings and model knowledge only", language: language)
                )
            }
        }
        .font(PortfolixTypography.caption)
        .foregroundStyle(PortfolixTheme.secondaryText)
        .padding(.horizontal, PortfolixSpacing.lg)
        .padding(.vertical, PortfolixSpacing.md)
    }

    private var model: String {
        configuredModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (report?.model ?? run.model ?? localizedText("未配置模型", "Model not configured", language: language))
            : configuredModel
    }
}

private struct AIReportHeaderStatusTag: View {
    let title: String
    let symbol: String
    let help: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(PortfolixTypography.captionEmphasis)
            .lineLimit(1)
            .truncationMode(.middle)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(PortfolixTheme.secondaryText)
            .padding(.horizontal, PortfolixSpacing.sm)
            .padding(.vertical, 6)
            .portfolixGlass(
                in: Capsule(),
                tint: PortfolixTheme.lilac.opacity(0.16),
                fallbackTint: PortfolixTheme.panelSoft,
                fallbackOpacity: 0.48
            )
            .help(help)
    }
}

private struct AIReportUserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: PortfolixSpacing.xxxl)
            Text(text)
                .font(PortfolixTypography.body)
                .foregroundStyle(Color(hex: 0x120F20))
                .padding(.horizontal, PortfolixSpacing.lg)
                .padding(.vertical, PortfolixSpacing.md)
                .background(PortfolixTheme.purpleGradient, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
        }
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

            Spacer(minLength: PortfolixSpacing.xxxl)
        }
    }
}

private struct AIReportFollowUpMessage: View {
    let text: String
    let language: AppLanguage
    let showsDisclaimer: Bool

    init(text: String, language: AppLanguage, showsDisclaimer: Bool = true) {
        self.text = text
        self.language = language
        self.showsDisclaimer = showsDisclaimer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
            Text(AIUserFacingTextSanitizer.sanitize(text))
                .font(PortfolixTypography.body)
                .foregroundStyle(PortfolixTheme.primaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PortfolixSpacing.lg)
                .padding(.vertical, PortfolixSpacing.md)
                .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                        .stroke(PortfolixTheme.border, lineWidth: 1)
                )

            if showsDisclaimer {
                AIReportDisclaimer(language: language)
            }
        }
    }
}

private struct AIReportWelcomeMessage: View {
    let hasPositions: Bool
    let hasLLMKey: Bool
    let hasSearchKey: Bool
    let usesConnectedMode: Bool
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            Text(localizedText("我可以基于你的持仓、风险偏好和行情数据生成组合分析", "I can analyze your portfolio using holdings, risk profile, and market data", language: language))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PortfolixTheme.primaryText)

            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                AIReportReadinessRow(isReady: hasPositions, text: localizedText("已有持仓数据", "Holdings available", language: language))
                AIReportReadinessRow(isReady: hasLLMKey, text: localizedText("LLM API 已验证", "LLM API validated", language: language))
                if usesConnectedMode {
                    AIReportReadinessRow(isReady: hasSearchKey, text: localizedText("Search API 已验证", "Search API validated", language: language))
                }
            }
        }
        .padding(PortfolixSpacing.lg)
        .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
    }
}

private struct AIReportReadinessRow: View {
    let isReady: Bool
    let text: String

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isReady ? PortfolixTheme.mint : PortfolixTheme.amber)
            Text(text)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondaryText)
        }
    }
}

private struct AIReportAgentProgressMessage: View {
    let status: AIAnalysisRunStatus
    let language: AppLanguage

    var body: some View {
        AIReportProgressCard(
            title: status.title(language: language),
            detail: progressDetail
        )
    }

    private var progressDetail: String {
        guard case let .running(progress) = status else {
            return localizedText("等待下一步", "Waiting for the next step", language: language)
        }
        return progress.detail(language: language)
    }
}

private struct AIReportFollowUpProgressMessage: View {
    let progress: AIFollowUpProgress
    let language: AppLanguage

    var body: some View {
        AIReportProgressCard(
            title: progress.title(language: language),
            detail: progress.detail(language: language)
        )
    }
}

private struct AIReportProgressCard: View {
    let title: String
    let detail: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            HStack(alignment: .center, spacing: PortfolixSpacing.md) {
                AIReportAgentThinkingIcon(date: timeline.date)

                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.primaryText)
                    Text(detail)
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.tertiaryText)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(PortfolixSpacing.lg)
            .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
        }
    }
}

private struct AIReportStaticStatusMessage: View {
    let status: AIAnalysisRunStatus
    let hasPositions: Bool
    let hasLLMKey: Bool
    let hasSearchKey: Bool
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
        .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
    }

    private var title: String {
        if !hasPositions {
            return localizedText("等待持仓数据", "Waiting for holdings", language: language)
        }
        if !hasLLMKey || (usesConnectedMode && !hasSearchKey) {
            return localizedText("需要完成 API 配置", "API configuration required", language: language)
        }
        return status.title(language: language)
    }

    private var detail: String {
        if !hasPositions {
            return localizedText("添加持仓后即可生成分析", "Add holdings to generate an analysis", language: language)
        }
        if !hasLLMKey {
            return localizedText("请在系统设置中配置并验证 LLM API Key", "Configure and validate an LLM API key in Settings", language: language)
        }
        if usesConnectedMode && !hasSearchKey {
            return localizedText("联网增强模式需要验证 Search API Key", "Connected mode requires a validated Search API key", language: language)
        }
        return localizedText("请检查配置或稍后重试", "Check settings or try again later", language: language)
    }

    private var symbol: String {
        switch status {
        case .failed:
            "exclamationmark.triangle.fill"
        default:
            "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .failed:
            PortfolixTheme.danger
        default:
            PortfolixTheme.amber
        }
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
                Text(relativeText(report.generatedAt, language: language))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiaryText)
            }

            if run.usedFallback {
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
                .padding(.horizontal, PortfolixSpacing.md)
                .padding(.vertical, PortfolixSpacing.sm)
                .background(PortfolixTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
            }

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

            if let actions = report.rebalanceActions, !actions.isEmpty {
                AIReportChatSection(title: localizedText("投资组合建议", "Portfolio Recommendations", language: language), symbol: "arrow.triangle.2.circlepath") {
                    ForEach(actions) { action in
                        AIReportRebalanceMessageRow(action: action)
                    }
                }
            }

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

            if !report.riskItems.isEmpty {
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

            if !report.questionsToConsider.isEmpty || !report.limitations.isEmpty {
                AIReportChatSection(title: localizedText("后续复核", "Follow-up Review", language: language), symbol: "questionmark.circle") {
                    ForEach(Array(report.questionsToConsider.enumerated()), id: \.offset) { _, question in
                        AIReportBullet(title: AIUserFacingTextSanitizer.sanitize(question), body: nil, color: PortfolixTheme.lilac, symbol: "checkmark.circle.fill")
                    }
                    ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, limitation in
                        AIReportBullet(title: AIUserFacingTextSanitizer.sanitize(limitation), body: nil, color: PortfolixTheme.secondaryText, symbol: "info.circle.fill")
                    }
                }
            }

            AIReportDisclaimer(language: language)
                .padding(.horizontal, 0)
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
    @Binding var draftMessage: String
    let canGenerate: Bool
    let canSendFollowUp: Bool
    let hasReport: Bool
    let language: AppLanguage
    let generate: () -> Void
    let sendFollowUp: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.md) {
            TextField(placeholder, text: $draftMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(PortfolixTypography.body)
                .foregroundStyle(PortfolixTheme.primaryText)
                .lineLimit(1)
                .padding(.horizontal, PortfolixSpacing.lg)
                .frame(height: AIReportComposerMetrics.controlHeight)
                .portfolixGlass(
                    in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous),
                    fallbackTint: PortfolixTheme.panelElevated,
                    fallbackOpacity: 0.68,
                    interactive: true
                )
                .onSubmit {
                    guard canSubmitFollowUp else { return }
                    sendFollowUp()
                }

            AIReportGenerateButton(
                title: hasReport
                    ? localizedText("重新分析", "Analyze Again", language: language)
                    : localizedText("生成分析", "Generate", language: language),
                isEnabled: canGenerate
            ) {
                generate()
            }

            AIReportSendButton(
                isEnabled: canSubmitFollowUp,
                help: localizedText("基于上一份报告追问", "Ask about the latest report", language: language)
            ) {
                sendFollowUp()
            }
        }
        .padding(.horizontal, PortfolixSpacing.lg)
        .padding(.vertical, PortfolixSpacing.md)
    }

    private var placeholder: String {
        hasReport
            ? localizedText("继续追问这份报告", "Ask a follow-up about this report", language: language)
            : localizedText("生成报告后可以继续追问", "Generate a report to continue the conversation", language: language)
    }

    private var canSubmitFollowUp: Bool {
        canSendFollowUp && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private enum AIReportComposerMetrics {
    static let controlHeight: CGFloat = PortfolixSpacing.xxxl
    static let sendButtonWidth: CGFloat = PortfolixSpacing.xxxl
}

private struct AIReportGenerateButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(Color(hex: 0x120F20))
                .padding(.horizontal, PortfolixSpacing.md)
                .frame(height: AIReportComposerMetrics.controlHeight)
                .contentShape(RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                .fill(PortfolixTheme.purpleGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }
}

private struct AIReportSendButton: View {
    let isEnabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(
                    width: AIReportComposerMetrics.sendButtonWidth,
                    height: AIReportComposerMetrics.controlHeight
                )
                .contentShape(RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.black.opacity(0.85) : PortfolixTheme.tertiaryText)
        .background {
            RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                .fill(isEnabled ? AnyShapeStyle(PortfolixTheme.purpleGradient) : AnyShapeStyle(PortfolixTheme.panelSoft))
        }
        .overlay(
            RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                .stroke(isEnabled ? Color.white.opacity(0.16) : PortfolixTheme.border.opacity(0.84), lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.55)
        .disabled(!isEnabled)
        .help(help)
    }
}

private struct AIReportStatusCard: View {
    let status: AIAnalysisRunStatus
    let hasPositions: Bool
    let hasLLMKey: Bool
    let hasSearchKey: Bool
    let usesConnectedMode: Bool
    let report: AIAnalysisReport?
    let run: AIAnalysisRun
    let language: AppLanguage

    var body: some View {
        Panel(padding: PortfolixSpacing.md) {
            if isRunningStatus {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    statusContent(
                        title: title,
                        detail: runningDetail,
                        icon: {
                            AIReportAgentThinkingIcon(date: timeline.date)
                        }
                    )
                }
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
        if !hasLLMKey || (usesConnectedMode && !hasSearchKey) {
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
            return localizedText("请在系统设置中配置并验证 LLM API Key", "Configure and validate an LLM API key in Settings", language: language)
        }
        if usesConnectedMode && !hasSearchKey {
            return localizedText("联网增强模式需要验证 Search API Key", "Connected mode requires a validated Search API key", language: language)
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
        if !hasPositions || !hasLLMKey || (usesConnectedMode && !hasSearchKey) {
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
        if !hasPositions || !hasLLMKey || (usesConnectedMode && !hasSearchKey) {
            return PortfolixTheme.amber
        }
        if case .failed = status {
            return PortfolixTheme.danger
        }
        return PortfolixTheme.mint
    }
}

private struct AIReportAgentThinkingIcon: View {
    let date: Date

    var body: some View {
        AIReportRoseOrbit(date: date, size: 40)
            .frame(width: 40, height: 40, alignment: .center)
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
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            VStack(spacing: PortfolixSpacing.sm) {
                AIReportRoseOrbit(date: timeline.date, size: 78)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            .accessibilityLabel("Generating analysis")
        }
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

struct RiskProfileView: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var isQuestionnairePresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                PageHeader(title: localizedText("风险偏好", "Risk Profile", language: store.appLanguage)) {
                    Button {
                        isQuestionnairePresented = true
                    } label: {
                        Label(localizedText("重新评估", "Reassess", language: store.appLanguage), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                HStack(alignment: .top, spacing: PortfolixSpacing.md) {
                    RiskProfileSummaryCard(
                        level: store.riskProfileConfigured ? localizedRiskLevel : localizedText("未配置", "Not configured", language: store.appLanguage),
                        tolerance: localizedRiskTolerance,
                        description: localizedRiskDescription,
                        versionLabel: riskProfileVersionLabel,
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
                            language: store.appLanguage
                        )

                        RiskConstraintSliderRow(
                            title: localizedText("数字货币最大占比", "Max Crypto", language: store.appLanguage),
                            actualLabel: localizedText("当前数字货币", "Current Crypto", language: store.appLanguage),
                            actualValue: cryptoAllocationPercent,
                            limitLabel: localizedText("上限", "Limit", language: store.appLanguage),
                            value: $store.cryptoLimit,
                            range: 0 ... 50,
                            mode: .maximum,
                            language: store.appLanguage
                        )

                        RiskConstraintSliderRow(
                            title: localizedText("非 CNY 计价资产最大占比", "Max Non-CNY Assets", language: store.appLanguage),
                            actualLabel: localizedText("当前非 CNY", "Current Non-CNY", language: store.appLanguage),
                            actualValue: nonCNYAllocationPercent,
                            limitLabel: localizedText("上限", "Limit", language: store.appLanguage),
                            value: $store.foreignCurrencyLimit,
                            range: 10 ... 90,
                            mode: .maximum,
                            language: store.appLanguage
                        )

                        RiskConstraintSliderRow(
                            title: localizedText("最低现金占比", "Minimum Cash", language: store.appLanguage),
                            actualLabel: localizedText("当前现金", "Current Cash", language: store.appLanguage),
                            actualValue: cashAllocationPercent,
                            limitLabel: localizedText("下限", "Minimum", language: store.appLanguage),
                            value: $store.liquidityMinimum,
                            range: 0 ... 40,
                            mode: .minimum,
                            language: store.appLanguage
                        )

                    }
                }

                RiskMaintenanceCard(
                    status: reviewStatus,
                    versionLabel: riskProfileVersionLabel,
                    language: store.appLanguage
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isQuestionnairePresented) {
            RiskQuestionnaireSheet()
                .environmentObject(store)
        }
    }

    private var riskProfileVersionLabel: String {
        let updatedText = store.riskProfileUpdatedText(now: store.relativeTimeNow, language: store.appLanguage)
        return store.appLanguage == .english
            ? "Version v\(store.riskProfileVersion) · \(updatedText)"
            : "版本 v\(store.riskProfileVersion) · \(updatedText)"
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
    let versionLabel: String
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

                CardMetaLabel(title: versionLabel, symbol: "clock")
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
                    Slider(value: $value, in: range, step: 5)
                        .tint(PortfolixTheme.lilac)

                    VStack(alignment: .trailing, spacing: PortfolixSpacing.xs) {
                        Text("\(limitLabel) \(percentText(value))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PortfolixTheme.secondaryText)
                            .monospacedDigit()
                            .lineLimit(1)

                        RiskLimitBadge(
                            title: isPassing ? localizedText("正常", "OK", language: language) : localizedText("需关注", "Watch", language: language),
                            color: isPassing ? PortfolixTheme.mint : PortfolixTheme.amber
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
    let versionLabel: String
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
                RiskSettingValue(versionLabel)
            }
        }
    }
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

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
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
    @EnvironmentObject private var store: PortfolioStore
    @State private var configurationSheet: SettingsConfigurationSheet?
    @State private var preparedDataImport: PreparedPortfolixDataImport?
    @State private var isImportConfirmationPresented = false
    @State private var dataTransferNotice: DataTransferNotice?
    @State private var exportStatus: DataTransferInlineStatus = .idle
    @State private var importStatus: DataTransferInlineStatus = .idle
    @State private var exportStatusResetTask: Task<Void, Never>?
    @State private var importStatusResetTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                PageHeader(title: settingsText("系统设置", "Settings"))

                SettingsSection(title: settingsText("显示设置", "Display"), symbol: "display") {
                    SettingsRow(title: settingsText("外观模式", "Appearance")) {
                        Picker(settingsText("外观模式", "Appearance"), selection: $store.appearanceMode) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title(language: store.appLanguage)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240, alignment: .trailing)
                    }

                    SettingsDivider()

                    SettingsRow(title: settingsText("界面语言", "Language")) {
                        Picker(settingsText("界面语言", "Language"), selection: $store.appLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.rawValue).tag(language)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240, alignment: .trailing)
                    }

                    SettingsDivider()

                    SettingsRow(title: settingsText("默认展示币种", "Default Currency")) {
                        Picker(settingsText("默认展示币种", "Default Currency"), selection: $store.displayCurrency) {
                            ForEach(DisplayCurrency.allCases) { currency in
                                Text(currency.rawValue).tag(currency)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240, alignment: .trailing)
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
                            "开启后，Portfolix 将通过 LLM 分析您的资产组合、收益及风险偏好",
                            "When enabled, Portfolix uses an LLM to analyze your portfolio, returns, and risk preferences"
                        ),
                        helpPlacement: .trailing,
                        isOn: $store.aiConfiguration.isEnabled
                    )
                    SettingsDivider()
                    SettingsRow(title: settingsText("分析模式", "Analysis Mode")) {
                        Picker(settingsText("分析模式", "Analysis Mode"), selection: smartAnalysisModeBinding) {
                            ForEach(SmartAnalysisMode.allCases) { mode in
                                Text(mode.title(language: store.appLanguage)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240, alignment: .trailing)
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
                    SettingsRow(title: "LLM API") {
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
                    SettingsRow(title: "Search API") {
                        let state = apiCredentialDisplayState(
                            hasKey: store.hasSearchAPIKey,
                            validationState: store.searchAPIKeyValidationState
                        )
                        ProviderConfigurationActions(
                            state: state.title,
                            color: state.color,
                            symbol: state.symbol,
                            buttonTitle: settingsText("配置", "Configure")
                        ) {
                            configurationSheet = .search
                        }
                    }
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
                            "将持仓组合明细、每日收益和资产每日价格导出为结构化数据包，不包含智能分析数据和App设置信息。",
                            "Exports portfolio holding details, daily returns, and daily asset prices as a structured data package. Smart analysis data and app settings are not included."
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
                    .environmentObject(store)
            case .search:
                SearchConfigurationSheet()
                    .environmentObject(store)
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
        return settingsText(
            "\(counts)\n\n同一资产或同一天的现有记录将被更新，其他现有数据不会删除。",
            "\(counts)\n\nExisting records for the same asset or date will be updated. Other existing data will not be deleted."
        )
    }

    private func transferSummary(_ summary: PortfolixDataTransferSummary) -> String {
        settingsText(
            "持仓 \(summary.holdingCount) 条，组合历史 \(summary.portfolioSnapshotCount) 条，资产价格 \(summary.assetPriceSnapshotCount) 条。",
            "\(summary.holdingCount) holdings, \(summary.portfolioSnapshotCount) portfolio history records, and \(summary.assetPriceSnapshotCount) asset price records."
        )
    }

    private var smartAnalysisModeBinding: Binding<SmartAnalysisMode> {
        Binding(
            get: {
                store.searchConfiguration.isEnabled ? .connected : .basic
            },
            set: { mode in
                store.searchConfiguration.isEnabled = mode == .connected
            }
        )
    }

    private func apiCredentialDisplayState(
        hasKey: Bool,
        validationState: ProviderCredentialValidationState
    ) -> (title: String, color: Color, symbol: String) {
        guard hasKey else {
            return (
                settingsText("尚未配置", "Not configured"),
                PortfolixTheme.amber,
                "exclamationmark.circle.fill"
            )
        }

        if validationState == .invalid {
            return (
                settingsText("Key 无效或已失效", "Key invalid or expired"),
                PortfolixTheme.danger,
                "exclamationmark.circle.fill"
            )
        }

        return (
            settingsText("已配置", "Configured"),
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

private struct SettingsMenuPicker<Value: CaseIterable & Identifiable>: View where Value.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Value
    var isEnabled = true
    var width: CGFloat?
    let optionTitle: (Value) -> String

    var body: some View {
        Menu {
            ForEach(Value.allCases, id: \.id) { option in
                Button {
                    selection = option
                } label: {
                    Text(optionTitle(option))
                }
            }
        } label: {
            HStack(spacing: PortfolixSpacing.sm) {
                Text(optionTitle(selection))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isEnabled ? PortfolixTheme.tertiaryText : PortfolixTheme.tertiaryText.opacity(0.72))
            }
            .font(PortfolixTypography.captionEmphasis)
            .foregroundStyle(isEnabled ? PortfolixTheme.primaryText : PortfolixTheme.tertiaryText)
            .padding(.horizontal, PortfolixSpacing.md)
            .frame(width: resolvedWidth, height: 32, alignment: .trailing)
            .background {
                RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                    .fill(PortfolixTheme.panelElevated)
                RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                    .stroke(PortfolixTheme.border.opacity(0.84), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityLabel(title)
        .accessibilityValue(optionTitle(selection))
    }

    private var resolvedWidth: CGFloat {
        if let width {
            return width
        }
        let longestTextWidth = Value.allCases
            .map { renderedTextWidth(optionTitle($0)) }
            .max() ?? 0
        let horizontalPadding = PortfolixSpacing.md * 2
        let chevronWidth: CGFloat = 12
        let minimumWidth: CGFloat = 78
        return ceil(max(minimumWidth, longestTextWidth + horizontalPadding + PortfolixSpacing.sm + chevronWidth))
    }

    private func renderedTextWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        return (text as NSString).size(withAttributes: [.font: font]).width
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
        .foregroundStyle(.white.opacity(isRefreshing ? 0.48 : 0.92))
        .background {
            Circle()
                .fill(.white.opacity(isRefreshing ? 0.10 : 0.16))
        }
        .help(localizedText("更新此资产价格", "Refresh this asset price", language: language))
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
