import SwiftUI

struct RiskProfileView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: RiskProfileDraft
    @State private var hasLoadedDraft: Bool
    @State private var isPresetPopoverPresented = false
    @State private var isConsistencyPopoverPresented = false
    @State private var showSavedFeedback = false
    @State private var savedFeedbackTask: Task<Void, Never>?

    init(initialDraft: RiskProfileDraft? = nil) {
        _draft = State(initialValue: initialDraft ?? .defaultBalanced)
        _hasLoadedDraft = State(initialValue: initialDraft != nil)
    }

    private var savedDraft: RiskProfileDraft {
        store.currentRiskProfileDraft
    }

    private var isDirty: Bool {
        hasLoadedDraft && draft != savedDraft
    }

    private var changedFieldCount: Int {
        hasLoadedDraft ? draft.changedFieldCount(comparedTo: savedDraft) : 0
    }

    private var activeDraft: RiskProfileDraft {
        hasLoadedDraft ? draft : savedDraft
    }

    private var evaluation: RiskConstraintEvaluation {
        store.evaluateRiskConstraints(for: activeDraft)
    }

    private var consistencyHints: [String] {
        activeDraft.consistencyHints(language: store.appLanguage)
    }

    private var reviewHealth: RiskProfileReviewHealth {
        activeDraft.reviewHealth(
            isConfigured: store.riskProfileConfigured,
            updatedAt: store.riskProfileUpdatedAt,
            evaluation: evaluation
        )
    }

    var body: some View {
        let currentEvaluation = evaluation
        let language = store.appLanguage

        ScrollView {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                PageHeader(title: localizedText("风险偏好", "Risk Profile", language: language)) {
                    headerTrailing(evaluation: currentEvaluation, language: language)
                }

                HStack(alignment: .top, spacing: PortfolixSpacing.md) {
                    RiskTierOverviewCard(
                        tier: $draft.tier,
                        presetChanges: activeDraft.presetChanges(for: activeDraft.tier, language: language),
                        isPresetPopoverPresented: $isPresetPopoverPresented,
                        language: language,
                        onConfirmApplyRecommended: {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                draft.applyRecommendedGuardrails()
                            }
                            isPresetPopoverPresented = false
                        }
                    )

                    RiskGuardrailSummaryCard(
                        isConfigured: store.riskProfileConfigured,
                        isDirty: isDirty,
                        evaluation: currentEvaluation,
                        reviewHealth: reviewHealth,
                        updatedAt: store.riskProfileUpdatedAt,
                        language: language
                    )
                }

                RiskInvestorProfileCard(
                    investmentGoal: $draft.investmentGoal,
                    investmentHorizon: $draft.investmentHorizon,
                    investmentExperience: $draft.investmentExperience,
                    reviewCadence: $draft.reviewCadence,
                    language: language
                )

                RiskGuardrailsPanel(
                    draft: $draft,
                    evaluation: currentEvaluation,
                    consistencyHints: consistencyHints,
                    isConsistencyPopoverPresented: $isConsistencyPopoverPresented,
                    displayCurrency: store.displayCurrency,
                    language: language
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .onAppear {
            if !hasLoadedDraft {
                syncDraftFromStoreWithoutAnimation()
            } else if draft != savedDraft {
                syncDraftFromStoreWithoutAnimation()
            }
        }
        .onChange(of: draft) { _, newValue in
            guard hasLoadedDraft else { return }
            store.unsavedRiskProfileDraft = (newValue != savedDraft) ? newValue : nil
        }
        .onChange(of: store.riskProfileVersion) { _, _ in
            syncDraftFromStoreWithoutAnimation()
        }
        .onDisappear {
            savedFeedbackTask?.cancel()
            if store.pendingSidebarSelection == nil {
                store.unsavedRiskProfileDraft = nil
            }
        }
    }

    @ViewBuilder
    private func headerTrailing(evaluation: RiskConstraintEvaluation, language: AppLanguage) -> some View {
        let showUnsavedActions = isDirty || !store.riskProfileConfigured

        HStack(spacing: PortfolixSpacing.sm) {
            if showUnsavedActions {
                HStack(spacing: 5) {
                    Circle()
                        .fill(PortfolixTheme.brandFocus)
                        .frame(width: 6, height: 6)
                    Text(unsavedHeaderText(language: language))
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondary)
                        .monospacedDigit()
                        .portfolixNumericTransition(unsavedHeaderText(language: language))
                }
                .padding(.trailing, PortfolixSpacing.xs)

                if isDirty && store.riskProfileConfigured {
                    Button(localizedText("放弃修改", "Discard", language: language), action: discardChanges)
                        .buttonStyle(QuietButtonStyle())
                }

                Button(action: saveChanges) {
                    Label(
                        store.riskProfileConfigured
                            ? localizedText("保存配置", "Save", language: language)
                            : localizedText("确认并保存", "Confirm & Save", language: language),
                        systemImage: "checkmark"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if showSavedFeedback {
                PortfolixInlineStatusLabel(
                    title: localizedText("已保存配置", "Saved", language: language),
                    symbol: "checkmark.circle.fill",
                    color: PortfolixTheme.gainText
                )
                .padding(.horizontal, PortfolixSpacing.sm)
                .padding(.vertical, 4)
                .background(PortfolixTheme.gainWash1, in: Capsule())
                .transition(.opacity)
            } else if store.riskProfileConfigured {
                Text(confirmedDateCaption(language: language))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                    .monospacedDigit()
                    .padding(.trailing, PortfolixSpacing.xs)
            }

            if store.aiConfiguration.isEnabled && evaluation.hasPositions {
                Button {
                    if isDirty || !store.riskProfileConfigured {
                        store.saveRiskProfile(draft)
                    }
                    store.openAIReviewForRiskProfile(prompt: aiReviewPrompt(for: evaluation, language: language))
                } label: {
                    Label(
                        localizedText("AI 诊断", "AI Check", language: language),
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showUnsavedActions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showSavedFeedback)
    }

    private func unsavedHeaderText(language: AppLanguage) -> String {
        if !store.riskProfileConfigured {
            return localizedText("待确认", "Pending", language: language)
        }
        return language == .english
            ? "\(changedFieldCount) unsaved"
            : "\(changedFieldCount) 项未保存"
    }

    private func syncDraftFromStoreWithoutAnimation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draft = store.currentRiskProfileDraft
            hasLoadedDraft = true
            store.unsavedRiskProfileDraft = nil
        }
    }

    private func discardChanges() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            draft = savedDraft
            store.unsavedRiskProfileDraft = nil
        }
    }

    private func saveChanges() {
        store.persistenceErrorMessage = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            store.saveRiskProfile(draft)
        }
        guard store.persistenceErrorMessage == nil else { return }
        savedFeedbackTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            showSavedFeedback = true
        }
        savedFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                showSavedFeedback = false
            }
        }
    }

    private func confirmedDateCaption(language: AppLanguage) -> String {
        let formatted = Self.dateFormatter.string(from: store.riskProfileUpdatedAt)
        return language == .english
            ? "Saved \(formatted)"
            : "上次保存 · \(formatted)"
    }

    private func aiReviewPrompt(for evaluation: RiskConstraintEvaluation, language: AppLanguage) -> String {
        let breached = evaluation.breachedLabels(language: language)
        if language == .english {
            let statusLine = breached.isEmpty
                ? "All \(evaluation.constraintCount) portfolio guardrails are currently within limits (\(evaluation.approachingCount) approaching limit)."
                : "Current guardrail breaches: \(breached.joined(separator: ", "))."
            return "Please review my current portfolio against my saved \(activeDraft.tier.title(language: .english)) risk profile (goal: \(activeDraft.investmentGoal.title(language: .english)), horizon: \(activeDraft.investmentHorizon.title(language: .english)), max drawdown tolerance: \(activeDraft.drawdownToleranceLabel)). \(statusLine) Highlight the key risks and concrete next adjustments to consider."
        } else {
            let statusLine = breached.isEmpty
                ? "当前全部 \(evaluation.constraintCount) 项风险护栏均在范围内（其中 \(evaluation.approachingCount) 项接近临界线）。"
                : "当前超限护栏：\(breached.joined(separator: "、"))。"
            return "请结合我已保存的「\(activeDraft.tier.title(language: .chinese))」风险档案（投资目标：\(activeDraft.investmentGoal.title(language: .chinese))，持有周期：\(activeDraft.investmentHorizon.title(language: .chinese))，最大回撤容忍：\(activeDraft.drawdownToleranceLabel)）诊断当前持仓结构。\(statusLine)请指出最核心的风险点以及优先考虑的调整方向。"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Top Overview Cards (Snug Matched Height, Zero Wasted Whitespace)

private struct RiskTierOverviewCard: View {
    @Binding var tier: RiskProfileTier
    let presetChanges: [RiskPresetChange]
    @Binding var isPresetPopoverPresented: Bool
    let language: AppLanguage
    let onConfirmApplyRecommended: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(
                    title: localizedText("风险定位", "Risk Positioning", language: language),
                    symbol: "person.text.rectangle"
                ) {
                    if !presetChanges.isEmpty {
                        Button {
                            isPresetPopoverPresented = true
                        } label: {
                            HStack(spacing: PortfolixSpacing.xs) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(localizedText("套用推荐护栏", "Apply Preset", language: language))
                                    .font(PortfolixTypography.captionEmphasis)
                            }
                            .foregroundStyle(PortfolixTheme.brandText)
                            .padding(.horizontal, PortfolixSpacing.sm)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(QuietButtonStyle(preservesLabelSize: true))
                        .popover(isPresented: $isPresetPopoverPresented, arrowEdge: .bottom) {
                            RiskPresetPreviewPopover(
                                tier: tier,
                                changes: presetChanges,
                                language: language,
                                onCancel: { isPresetPopoverPresented = false },
                                onConfirm: onConfirmApplyRecommended
                            )
                        }
                    } else {
                        PortfolixInlineStatusLabel(
                            title: localizedText("已用推荐护栏", "Preset Matched", language: language),
                            symbol: "checkmark.seal.fill",
                            color: PortfolixTheme.tertiary,
                            font: PortfolixTypography.caption,
                            symbolSize: 10
                        )
                    }
                }

                VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                    PortfolixGlassSegmentedPicker(
                        title: localizedText("风险等级", "Risk Tier", language: language),
                        selection: $tier,
                        options: RiskProfileTier.allCases,
                        optionTitle: { $0.title(language: language) },
                        fillsWidth: true,
                        height: PortfolixLayout.settingsControlHeight
                    )

                    Text(tier.summary(language: language))
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: tier)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct RiskPresetPreviewPopover: View {
    let tier: RiskProfileTier
    let changes: [RiskPresetChange]
    let language: AppLanguage
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(
                    language == .english
                        ? "Apply \(tier.title(language: .english)) Guardrails"
                        : "套用「\(tier.title(language: .chinese))」推荐护栏"
                )
                .font(PortfolixTypography.subheading)
                .foregroundStyle(PortfolixTheme.text)

                Text(localizedText(
                    "以下护栏将调整为推荐值（写入草稿，点击右上角保存后生效）：",
                    "The following guardrails will update in your draft (click Save in the top-right to apply):",
                    language: language
                ))
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: PortfolixSpacing.xs) {
                ForEach(changes) { change in
                    HStack(spacing: PortfolixSpacing.md) {
                        Text(change.title)
                            .font(PortfolixTypography.caption)
                            .foregroundStyle(PortfolixTheme.text)
                            .lineLimit(1)

                        Spacer(minLength: PortfolixSpacing.sm)

                        HStack(spacing: PortfolixSpacing.xs) {
                            Text(change.currentValue)
                                .foregroundStyle(PortfolixTheme.tertiary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(PortfolixTheme.tertiary)
                            Text(change.targetValue)
                                .foregroundStyle(PortfolixTheme.brandText)
                        }
                        .font(PortfolixTypography.captionEmphasis)
                        .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(PortfolixSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                    .fill(PortfolixTheme.subtleFill)
            )

            HStack(spacing: PortfolixSpacing.sm) {
                Spacer()
                Button(localizedText("取消", "Cancel", language: language), action: onCancel)
                    .buttonStyle(QuietButtonStyle())
                Button(localizedText("确认套用", "Apply Preset", language: language), action: onConfirm)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(PortfolixSpacing.lg)
        .frame(width: 320)
    }
}

private struct RiskGuardrailSummaryCard: View {
    let isConfigured: Bool
    let isDirty: Bool
    let evaluation: RiskConstraintEvaluation
    let reviewHealth: RiskProfileReviewHealth
    let updatedAt: Date
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var totalCount: Int { evaluation.constraintCount }
    private var passedCount: Int { evaluation.passedCount }
    private var breachCount: Int { evaluation.breachCount }
    private var approachingCount: Int { evaluation.approachingCount }
    private var normalCount: Int { evaluation.normalCount }
    private var hasPositions: Bool { evaluation.hasPositions }
    private var showMetrics: Bool { (isConfigured || isDirty) && hasPositions }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(
                    title: localizedText("护栏状态", "Guardrail Status", language: language),
                    symbol: "target"
                ) {
                    if isDirty {
                        Text(localizedText("实时预览", "Live Preview", language: language))
                            .font(PortfolixTypography.micro)
                            .foregroundStyle(PortfolixTheme.brandWashText)
                            .padding(.horizontal, PortfolixSpacing.sm)
                            .padding(.vertical, 3)
                            .background(PortfolixTheme.brandWash, in: Capsule())
                    } else if let scheduleText = secondaryScheduleText {
                        Text(scheduleText)
                            .font(PortfolixTypography.caption)
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .center, spacing: PortfolixSpacing.md) {
                    RiskHealthRing(
                        progress: ringProgress,
                        centerText: ringCenterText,
                        tint: statusRingColor
                    )

                    // Always exactly 2 lines on the left so breaching never causes a vertical 3rd-line jump.
                    VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                        HStack(spacing: PortfolixSpacing.xs) {
                            Image(systemName: statusIcon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(statusTextColor)
                            Text(statusHeadline)
                                .font(PortfolixTypography.sectionTitle)
                                .foregroundStyle(PortfolixTheme.text)
                                .lineLimit(1)
                        }

                        Text(statusDetailLine)
                            .font(PortfolixTypography.caption)
                            .foregroundStyle(statusDetailColor)
                            .monospacedDigit()
                            .portfolixNumericTransition(statusDetailLine)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Balanced 3-tier breakdown flush with the card's right 16pt margin.
                    if showMetrics {
                        HStack(spacing: PortfolixSpacing.md) {
                            statColumn(
                                value: "\(normalCount)",
                                label: localizedText("正常", "Normal", language: language),
                                color: normalCount > 0 ? PortfolixTheme.gainText : PortfolixTheme.tertiary
                            )

                            verticalDivider

                            statColumn(
                                value: "\(approachingCount)",
                                label: localizedText("临界", "Near", language: language),
                                color: approachingCount > 0 ? PortfolixTheme.warnText : PortfolixTheme.tertiary
                            )

                            verticalDivider

                            statColumn(
                                value: "\(breachCount)",
                                label: localizedText("超限", "Over", language: language),
                                color: breachCount > 0 ? PortfolixTheme.lossText : PortfolixTheme.tertiary
                            )
                        }
                        .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: statusHeadline)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: breachCount)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: approachingCount)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func statColumn(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(PortfolixTypography.headlineValue)
                .foregroundStyle(color)
                .monospacedDigit()
                .portfolixNumericTransition(value)
            Text(label)
                .font(PortfolixTypography.micro)
                .foregroundStyle(PortfolixTheme.tertiary)
        }
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(PortfolixTheme.border)
            .frame(width: 0.5, height: 24)
    }

    private var ringProgress: Double {
        guard showMetrics, totalCount > 0 else { return 0 }
        return Double(passedCount) / Double(totalCount)
    }

    private var ringCenterText: String {
        guard showMetrics else { return "--" }
        return "\(passedCount)/\(totalCount)"
    }

    private var statusRingColor: Color {
        guard showMetrics else { return PortfolixTheme.borderStrong }
        if breachCount > 0 { return PortfolixTheme.lossFill }
        if approachingCount > 0 { return PortfolixTheme.warnFill }
        return PortfolixTheme.gainFill
    }

    private var statusTextColor: Color {
        guard showMetrics else { return PortfolixTheme.tertiary }
        if breachCount > 0 { return PortfolixTheme.lossText }
        if approachingCount > 0 { return PortfolixTheme.warnText }
        if case .reviewDue = reviewHealth { return PortfolixTheme.warnText }
        return PortfolixTheme.gainText
    }

    private var statusDetailColor: Color {
        guard showMetrics else { return PortfolixTheme.secondary }
        if breachCount > 0 { return PortfolixTheme.lossText }
        if approachingCount > 0 { return PortfolixTheme.warnText }
        return PortfolixTheme.secondary
    }

    private var statusIcon: String {
        if !isConfigured && !isDirty { return "circle.dashed" }
        if !hasPositions { return "tray" }
        if breachCount > 0 { return "xmark.octagon.fill" }
        if approachingCount > 0 { return "exclamationmark.triangle.fill" }
        if case .reviewDue = reviewHealth { return "calendar.badge.exclamationmark" }
        return "checkmark.shield.fill"
    }

    private var statusHeadline: String {
        if !isConfigured && !isDirty {
            return localizedText("待确认档案", "Confirmation Needed", language: language)
        }
        if !hasPositions {
            return localizedText("暂无持仓可评估", "No Holdings Yet", language: language)
        }
        if breachCount > 0 {
            return localizedText("存在超限指标", "Guardrails Breached", language: language)
        }
        if approachingCount > 0 {
            return localizedText("存在临界风险", "Approaching Limits", language: language)
        }
        if case .reviewDue = reviewHealth {
            return localizedText("已到复评周期", "Review Due", language: language)
        }
        return localizedText("全部符合护栏", "All Guardrails Met", language: language)
    }

    private var statusDetailLine: String {
        if !isConfigured && !isDirty {
            return localizedText("确认以下默认护栏后点击右上角保存生效", "Review defaults below, then click Save above", language: language)
        }
        if !hasPositions {
            return localizedText("添加持仓后将自动实时对照 6 项风险护栏", "Add holdings to evaluate all 6 guardrails automatically", language: language)
        }
        if breachCount > 0 {
            let labels = evaluation.breachedLabels(language: language).prefix(2).joined(separator: " · ")
            return labels.isEmpty
                ? localizedText("\(breachCount) 项超出护栏，请核对下方细项", "\(breachCount) guardrail(s) breached below", language: language)
                : labels
        }
        if approachingCount > 0 {
            return localizedText(
                "\(approachingCount) 项接近临界线（≥80% 阈值）",
                "\(approachingCount) guardrail(s) approaching limit (≥80%)",
                language: language
            )
        }
        if case .reviewDue = reviewHealth {
            return localizedText("建议复核风险定位与护栏后重新保存", "Consider reviewing and re-confirming your profile", language: language)
        }
        return localizedText(
            "全部 \(totalCount) 项量化指标均处于安全区间",
            "All \(totalCount) quantified guardrails are within safe margins",
            language: language
        )
    }

    private var secondaryScheduleText: String? {
        switch reviewHealth {
        case .valid(let nextDate), .reviewDue(let nextDate):
            let text = Self.dateFormatter.string(from: nextDate)
            return language == .english ? "Next review \(text)" : "下次复评 · \(text)"
        case .approaching, .breached:
            guard isConfigured else { return nil }
            let text = Self.dateFormatter.string(from: updatedAt)
            return language == .english ? "Saved \(text)" : "确认于 \(text)"
        case .notConfigured:
            return nil
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct RiskHealthRing: View {
    let progress: Double
    let centerText: String
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(PortfolixTheme.subtleFill, lineWidth: 5)
                .padding(2.5)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2.5)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: progress)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: tint)

            Text(centerText)
                .font(PortfolixTypography.headlineValue)
                .foregroundStyle(PortfolixTheme.text)
                .monospacedDigit()
                .portfolixNumericTransition(centerText)
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }
}

// MARK: - Investor Profile Card (Responsive 4-Col Wide / 2x2 Narrow, Zero Height Shift)

private struct RiskInvestorProfileCard: View {
    @Binding var investmentGoal: RiskInvestmentGoal
    @Binding var investmentHorizon: RiskInvestmentHorizon
    @Binding var investmentExperience: RiskInvestmentExperience
    @Binding var reviewCadence: RiskReviewCadence
    let language: AppLanguage

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(
                    title: localizedText("投资画像", "Investor Profile", language: language),
                    symbol: "person.crop.rectangle.stack"
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: PortfolixSpacing.md) {
                        goalField.frame(minWidth: 170, maxWidth: .infinity)
                        horizonField.frame(minWidth: 170, maxWidth: .infinity)
                        experienceField.frame(minWidth: 170, maxWidth: .infinity)
                        cadenceField.frame(minWidth: 170, maxWidth: .infinity)
                    }

                    VStack(spacing: PortfolixSpacing.md) {
                        HStack(alignment: .top, spacing: PortfolixSpacing.md) {
                            goalField.frame(maxWidth: .infinity)
                            horizonField.frame(maxWidth: .infinity)
                        }
                        HStack(alignment: .top, spacing: PortfolixSpacing.md) {
                            experienceField.frame(maxWidth: .infinity)
                            cadenceField.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var goalField: some View {
        stackedPickerField(title: localizedText("核心投资目标", "Investment Goal", language: language)) {
            PortfolixGlassMenuPicker(
                title: localizedText("核心投资目标", "Investment Goal", language: language),
                selection: $investmentGoal,
                options: RiskInvestmentGoal.allCases,
                optionTitle: { $0.title(language: language) },
                height: PortfolixLayout.settingsControlHeight,
                fillsWidth: true
            )
        }
    }

    private var horizonField: some View {
        stackedPickerField(title: localizedText("预计持有周期", "Holding Horizon", language: language)) {
            PortfolixGlassMenuPicker(
                title: localizedText("预计持有周期", "Holding Horizon", language: language),
                selection: $investmentHorizon,
                options: RiskInvestmentHorizon.allCases,
                optionTitle: { $0.title(language: language) },
                height: PortfolixLayout.settingsControlHeight,
                fillsWidth: true
            )
        }
    }

    private var experienceField: some View {
        stackedPickerField(title: localizedText("投资经验", "Experience", language: language)) {
            PortfolixGlassMenuPicker(
                title: localizedText("投资经验", "Experience", language: language),
                selection: $investmentExperience,
                options: RiskInvestmentExperience.allCases,
                optionTitle: { $0.title(language: language) },
                height: PortfolixLayout.settingsControlHeight,
                fillsWidth: true
            )
        }
    }

    private var cadenceField: some View {
        stackedPickerField(title: localizedText("复评提醒周期", "Review Cadence", language: language)) {
            PortfolixGlassMenuPicker(
                title: localizedText("复评提醒周期", "Review Cadence", language: language),
                selection: $reviewCadence,
                options: RiskReviewCadence.allCases,
                optionTitle: { $0.title(language: language) },
                height: PortfolixLayout.settingsControlHeight,
                fillsWidth: true
            )
        }
    }

    private func stackedPickerField<Control: View>(
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Text(title)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondary)
                .lineLimit(1)

            control()
        }
    }
}

// MARK: - Structured 4-Column Portfolio Guardrails Panel

private enum RiskGuardrailMode {
    case maximum
    case minimum

    var isMinimum: Bool { self == .minimum }
}

private enum RiskGuardrailColumns {
    static let indicatorWidth: CGFloat = 204
    static let thresholdWidth: CGFloat = 248
    static let statusWidth: CGFloat = 96
    static let sliderWidth: CGFloat = 160
    static let limitReadoutWidth: CGFloat = 76
    static let columnSpacing: CGFloat = PortfolixSpacing.lg
}

private struct RiskGuardrailsPanel: View {
    @Binding var draft: RiskProfileDraft
    let evaluation: RiskConstraintEvaluation
    let consistencyHints: [String]
    @Binding var isConsistencyPopoverPresented: Bool
    let displayCurrency: DisplayCurrency
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(
                    title: localizedText("风险护栏", "Portfolio Guardrails", language: language),
                    symbol: "shield.lefthalf.filled"
                ) {
                    if let firstHint = consistencyHints.first {
                        Button {
                            if consistencyHints.count > 1 {
                                isConsistencyPopoverPresented = true
                            }
                        } label: {
                            HStack(spacing: PortfolixSpacing.xs) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(PortfolixTheme.warnText)

                                Text(consistencyHints.count > 1
                                    ? (language == .english
                                        ? "\(firstHint) (+\(consistencyHints.count - 1))"
                                        : "\(firstHint)（另有 \(consistencyHints.count - 1) 项）")
                                    : firstHint
                                )
                                .font(PortfolixTypography.caption)
                                .foregroundStyle(PortfolixTheme.warnText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            }
                            .padding(.horizontal, PortfolixSpacing.sm)
                            .padding(.vertical, 3)
                            .background(PortfolixTheme.warnWash1, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(consistencyHints.count > 1)
                        .popover(isPresented: $isConsistencyPopoverPresented, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                                Text(localizedText("配置一致性提示", "Profile Consistency Notes", language: language))
                                    .font(PortfolixTypography.subheading)
                                    .foregroundStyle(PortfolixTheme.text)
                                ForEach(consistencyHints, id: \.self) { hint in
                                    HStack(alignment: .top, spacing: PortfolixSpacing.xs) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(PortfolixTheme.warnText)
                                            .padding(.top, 2)
                                        Text(hint)
                                            .font(PortfolixTypography.caption)
                                            .foregroundStyle(PortfolixTheme.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(PortfolixSpacing.lg)
                            .frame(width: 320, alignment: .leading)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: consistencyHints.first)

                // Column Header Row
                HStack(spacing: RiskGuardrailColumns.columnSpacing) {
                    Text(localizedText("风险指标", "Indicator", language: language))
                        .frame(width: RiskGuardrailColumns.indicatorWidth, alignment: .leading)

                    Text(localizedText("当前风险水平", "Current Level", language: language))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(localizedText("阈值设置", "Threshold", language: language))
                        .frame(width: RiskGuardrailColumns.thresholdWidth, alignment: .leading)

                    Text(localizedText("风险状态", "Status", language: language))
                        .frame(width: RiskGuardrailColumns.statusWidth, alignment: .trailing)
                }
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(PortfolixTheme.tertiary)
                .padding(.bottom, PortfolixSpacing.sm)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(PortfolixTheme.border)
                        .frame(height: 0.5)
                }

                VStack(spacing: 0) {
                    // 1. Drawdown tolerance
                    RiskGuardrailRow(
                        title: localizedText("阶段性最大回撤", "Max Drawdown", language: language),
                        helpText: localizedText(
                            "对照账户全部历史快照的峰值计算当前回撤幅度；达到容忍阈值 80% 提示临界，超出提示超限。",
                            "Compared against your portfolio's current drawdown from its all-time recorded peak. Warns at 80% of limit and flags breaches above 100%.",
                            language: language
                        ),
                        contextSubtitle: drawdownSubtitle,
                        actualValue: evaluation.currentDrawdownPercent,
                        limitPrefix: localizedText("容忍", "Max", language: language),
                        value: $draft.maxDrawdownLimit,
                        range: 5 ... 50,
                        barScaleMax: 50,
                        mode: .maximum,
                        deviationAmountText: nil,
                        language: language
                    )

                    guardrailDivider

                    // 2. Single non-cash asset concentration
                    RiskGuardrailRow(
                        title: localizedText("单一非现金资产", "Single Non-Cash Asset", language: language),
                        helpText: localizedText(
                            "仅统计非现金持仓，避免高现金仓位误触发集中度超限。",
                            "Evaluates non-cash holdings only so holding cash reserves never triggers concentration warnings.",
                            language: language
                        ),
                        contextSubtitle: largestAssetSubtitle,
                        actualValue: evaluation.hasPositions ? evaluation.largestPositionPercent : nil,
                        limitPrefix: localizedText("上限", "Max", language: language),
                        value: $draft.positionLimit,
                        range: 5 ... 100,
                        barScaleMax: 100,
                        mode: .maximum,
                        deviationAmountText: excessAmountText(
                            actual: evaluation.largestPositionPercent,
                            limit: draft.positionLimit,
                            mode: .maximum
                        ),
                        language: language
                    )

                    guardrailDivider

                    // 3. Stocks & crypto combined high-volatility cap
                    RiskGuardrailRow(
                        title: localizedText("股票与加密敞口", "Stocks & Crypto", language: language),
                        helpText: localizedText(
                            "合并统计股票与加密资产占总组合比例，用于控制高波动风险资产总敞口。",
                            "Combined share of stocks and crypto holdings to cap overall high-volatility exposure.",
                            language: language
                        ),
                        contextSubtitle: localizedText("高波动资产合计", "High-volatility total", language: language),
                        actualValue: evaluation.hasPositions ? evaluation.highVolatilityAllocationPercent : nil,
                        limitPrefix: localizedText("上限", "Max", language: language),
                        value: $draft.riskAssetLimit,
                        range: 0 ... 100,
                        barScaleMax: 100,
                        mode: .maximum,
                        deviationAmountText: excessAmountText(
                            actual: evaluation.highVolatilityAllocationPercent,
                            limit: draft.riskAssetLimit,
                            mode: .maximum
                        ),
                        language: language
                    )

                    guardrailDivider

                    // 4. Crypto cap
                    RiskGuardrailRow(
                        title: localizedText("加密资产占比", "Crypto Allocation", language: language),
                        helpText: localizedText(
                            "全部加密资产占组合总市值的比例上限。",
                            "Maximum share of crypto holdings across your total portfolio.",
                            language: language
                        ),
                        contextSubtitle: localizedText("数字资产单一敞口", "Digital asset exposure", language: language),
                        actualValue: evaluation.hasPositions ? evaluation.cryptoAllocationPercent : nil,
                        limitPrefix: localizedText("上限", "Max", language: language),
                        value: $draft.cryptoLimit,
                        range: 0 ... 100,
                        barScaleMax: 100,
                        mode: .maximum,
                        deviationAmountText: excessAmountText(
                            actual: evaluation.cryptoAllocationPercent,
                            limit: draft.cryptoLimit,
                            mode: .maximum
                        ),
                        language: language
                    )

                    guardrailDivider

                    // 5. Foreign currency cap (ledger accounting base currency is CNY, independent of display currency toggle)
                    RiskGuardrailRow(
                        title: localizedText("外币资产占比", "Non-CNY Exposure", language: language),
                        helpText: localizedText(
                            "按账本本位币（人民币 CNY）统计非人民币计价资产占比，不受页面展示币种切换影响。",
                            "Share of holdings denominated outside the ledger accounting base currency (CNY); unaffected by display currency toggles.",
                            language: language
                        ),
                        contextSubtitle: localizedText("非人民币计价资产", "Non-CNY holdings", language: language),
                        actualValue: evaluation.hasPositions ? evaluation.nonCNYAllocationPercent : nil,
                        limitPrefix: localizedText("上限", "Max", language: language),
                        value: $draft.foreignCurrencyLimit,
                        range: 0 ... 100,
                        barScaleMax: 100,
                        mode: .maximum,
                        deviationAmountText: excessAmountText(
                            actual: evaluation.nonCNYAllocationPercent,
                            limit: draft.foreignCurrencyLimit,
                            mode: .maximum
                        ),
                        language: language
                    )

                    guardrailDivider

                    // 6. Minimum cash liquidity
                    RiskGuardrailRow(
                        title: localizedText("最低现金比例", "Minimum Cash", language: language),
                        helpText: localizedText(
                            "全部现金类持仓占总组合的比例下限；处于下限 100%–120% 区间提示临界，低于下限提示不足。",
                            "Minimum liquidity buffer across cash holdings. Warns within 100%–120% of the floor and flags shortfalls below.",
                            language: language
                        ),
                        contextSubtitle: localizedText("流动性安全垫", "Liquidity buffer", language: language),
                        actualValue: evaluation.hasPositions ? evaluation.cashAllocationPercent : nil,
                        limitPrefix: localizedText("下限", "Min", language: language),
                        value: $draft.liquidityMinimum,
                        range: 0 ... 100,
                        barScaleMax: 100,
                        mode: .minimum,
                        deviationAmountText: excessAmountText(
                            actual: evaluation.cashAllocationPercent,
                            limit: draft.liquidityMinimum,
                            mode: .minimum
                        ),
                        language: language
                    )
                }
            }
        }
    }

    private var guardrailDivider: some View {
        Rectangle()
            .fill(PortfolixTheme.border)
            .frame(height: 0.5)
            .padding(.vertical, PortfolixSpacing.md)
    }

    private var drawdownSubtitle: String {
        guard evaluation.currentDrawdownPercent != nil else {
            return localizedText("暂无历史快照", "No snapshot history", language: language)
        }
        if let maxHist = evaluation.historicalMaxDrawdownPercent {
            return localizedText(
                "历史最大 \(String(format: "%.1f%%", maxHist))",
                "Historical max \(String(format: "%.1f%%", maxHist))",
                language: language
            )
        }
        return localizedText("较峰值实时回撤", "Live drawdown from peak", language: language)
    }

    private var largestAssetSubtitle: String {
        guard evaluation.hasPositions else {
            return localizedText("暂无持仓", "No holdings", language: language)
        }
        guard let name = evaluation.largestPositionName else {
            return localizedText("当前无非现金持仓", "No non-cash holdings", language: language)
        }
        return name
    }

    private func excessAmountText(actual: Double, limit: Double, mode: RiskGuardrailMode) -> String? {
        guard evaluation.totalValueCNY > 0 else { return nil }
        let delta: Double
        switch mode {
        case .maximum:
            guard actual > limit else { return nil }
            delta = actual - limit
        case .minimum:
            guard actual < limit else { return nil }
            delta = limit - actual
        }
        guard delta >= 0.05 else { return nil }
        let amountCNY = evaluation.deviationAmountCNY(forPercentDelta: delta)
        let converted = amountCNY * displayCurrency.rateFromCNY
        let formatted = formatMoney(converted, currency: displayCurrency, maximumFractionDigits: 0)
        return language == .english ? "~\(formatted)" : "约 \(formatted)"
    }
}

private struct RiskGuardrailRow: View {
    let title: String
    let helpText: String?
    let contextSubtitle: String
    let actualValue: Double?
    let limitPrefix: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let barScaleMax: Double
    let mode: RiskGuardrailMode
    let deviationAmountText: String?
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var severity: RiskGuardrailSeverity {
        RiskGuardrailSeverity.evaluate(actual: actualValue, limit: value, isMinimum: mode.isMinimum)
    }

    /// Continuous native macOS Liquid Glass slider without tick marks, rounded smoothly to 1%.
    private var roundedSliderBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                let snapped = min(max(newValue.rounded(), range.lowerBound), range.upperBound)
                if snapped != value {
                    value = snapped
                }
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: RiskGuardrailColumns.columnSpacing) {
            // Col 1: Risk Indicator
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                HStack(spacing: PortfolixSpacing.xs) {
                    Text(title)
                        .font(PortfolixTypography.bodyEmphasis)
                        .foregroundStyle(PortfolixTheme.text)
                        .lineLimit(1)

                    if let helpText {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .portfolixHelp(helpText)
                    }
                }

                Text(contextSubtitle)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: RiskGuardrailColumns.indicatorWidth, alignment: .leading)

            // Col 2: Current Risk Level (Read-Only Visualization)
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.sm) {
                    Text(actualValueText)
                        .font(PortfolixTypography.headlineValue)
                        .foregroundStyle(actualValueColor)
                        .monospacedDigit()
                        .portfolixNumericTransition(actualValueText)
                        .lineLimit(1)

                    Text(marginSubtitle)
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(marginSubtitleColor)
                        .monospacedDigit()
                        .portfolixNumericTransition(marginSubtitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                RiskGuardrailTelemetryBar(
                    actualValue: actualValue,
                    limitValue: value,
                    scaleMax: barScaleMax,
                    severity: severity
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Col 3: Interactive Native Liquid Glass Threshold Slider (Tickless)
            HStack(spacing: PortfolixSpacing.sm) {
                Slider(value: roundedSliderBinding, in: range)
                    .tint(PortfolixTheme.brandFocus)
                    .frame(width: RiskGuardrailColumns.sliderWidth)
                    .accessibilityLabel(title)
                    .accessibilityValue("\(Int(value.rounded()))%")

                HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.xs) {
                    Text(limitPrefix)
                        .font(PortfolixTypography.micro)
                        .foregroundStyle(PortfolixTheme.tertiary)
                    Text("\(Int(value.rounded()))%")
                        .font(PortfolixTypography.headlineValue)
                        .foregroundStyle(PortfolixTheme.text)
                        .monospacedDigit()
                        .portfolixNumericTransition("\(Int(value.rounded()))%")
                }
                .lineLimit(1)
                .frame(width: RiskGuardrailColumns.limitReadoutWidth, alignment: .trailing)
            }
            .frame(width: RiskGuardrailColumns.thresholdWidth, alignment: .leading)

            // Col 4: De-noised 3-Tier Risk Status with Unified System Animation
            statusView
                .frame(width: RiskGuardrailColumns.statusWidth, alignment: .trailing)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: severity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: severity)
    }

    private var actualValueText: String {
        guard let actualValue else { return "--" }
        return String(format: "%.1f%%", actualValue)
    }

    private var actualValueColor: Color {
        switch severity {
        case .noData: PortfolixTheme.tertiary
        case .normal: PortfolixTheme.text
        case .approaching: PortfolixTheme.warnText
        case .breached: PortfolixTheme.lossText
        }
    }

    private var marginSubtitle: String {
        guard let actualValue else {
            return localizedText("待记录数据", "Awaiting data", language: language)
        }
        switch (mode, severity) {
        case (.maximum, .breached):
            let excess = actualValue - value
            if let deviationAmountText {
                return localizedText(
                    "超限 +\(String(format: "%.1f", excess))% · \(deviationAmountText)",
                    "+\(String(format: "%.1f", excess))% over · \(deviationAmountText)",
                    language: language
                )
            }
            return localizedText("超限 +\(String(format: "%.1f", excess))%", "+\(String(format: "%.1f", excess))% over", language: language)

        case (.minimum, .breached):
            let deficit = value - actualValue
            if let deviationAmountText {
                return localizedText(
                    "不足 -\(String(format: "%.1f", deficit))% · \(deviationAmountText)",
                    "-\(String(format: "%.1f", deficit))% short · \(deviationAmountText)",
                    language: language
                )
            }
            return localizedText("不足 -\(String(format: "%.1f", deficit))%", "-\(String(format: "%.1f", deficit))% short", language: language)

        case (.maximum, .approaching):
            let buffer = max(0, value - actualValue)
            return localizedText("余量仅 \(String(format: "%.1f", buffer))%", "\(String(format: "%.1f", buffer))% headroom", language: language)

        case (.minimum, .approaching):
            let buffer = max(0, actualValue - value)
            return localizedText("高于下限 \(String(format: "%.1f", buffer))%", "+\(String(format: "%.1f", buffer))% above min", language: language)

        case (.maximum, .normal):
            let buffer = max(0, value - actualValue)
            return localizedText("余量 \(String(format: "%.1f", buffer))%", "\(String(format: "%.1f", buffer))% headroom", language: language)

        case (.minimum, .normal):
            let buffer = max(0, actualValue - value)
            return localizedText("高于下限 \(String(format: "%.1f", buffer))%", "+\(String(format: "%.1f", buffer))% buffer", language: language)

        case (_, .noData):
            return localizedText("待记录数据", "Awaiting data", language: language)
        }
    }

    private var marginSubtitleColor: Color {
        switch severity {
        case .breached: PortfolixTheme.lossText
        case .approaching: PortfolixTheme.warnText
        case .normal, .noData: PortfolixTheme.tertiary
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch severity {
        case .noData:
            Text(localizedText("待记录", "No Data", language: language))
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.tertiary)
                .lineLimit(1)

        case .normal:
            PortfolixInlineStatusLabel(
                title: localizedText("正常", "Normal", language: language),
                symbol: "checkmark.circle.fill",
                color: PortfolixTheme.gainText
            )

        case .approaching:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(
                    mode == .minimum
                        ? localizedText("接近下限", "Near Min", language: language)
                        : localizedText("接近上限", "Near Max", language: language)
                )
                .font(PortfolixTypography.captionEmphasis)
            }
            .foregroundStyle(PortfolixTheme.warnText)
            .lineLimit(1)
            .padding(.horizontal, PortfolixSpacing.sm)
            .padding(.vertical, 3)
            .background(PortfolixTheme.warnWash1, in: Capsule())

        case .breached:
            let deltaText: String = {
                guard let actualValue else { return localizedText("超限", "Breached", language: language) }
                if mode == .minimum {
                    return language == .english
                        ? "-\(String(format: "%.1f", value - actualValue))%"
                        : "缺 -\(String(format: "%.1f", value - actualValue))%"
                }
                return language == .english
                    ? "+\(String(format: "%.1f", actualValue - value))%"
                    : "超 +\(String(format: "%.1f", actualValue - value))%"
            }()
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(deltaText)
                    .font(PortfolixTypography.captionEmphasis)
                    .monospacedDigit()
                    .portfolixNumericTransition(deltaText)
            }
            .foregroundStyle(PortfolixTheme.lossText)
            .lineLimit(1)
            .padding(.horizontal, PortfolixSpacing.sm)
            .padding(.vertical, 3)
            .background(PortfolixTheme.lossWash1, in: Capsule())
        }
    }
}

// MARK: - Read-Only Telemetry Bar

private struct RiskGuardrailTelemetryBar: View {
    let actualValue: Double?
    let limitValue: Double
    let scaleMax: Double
    let severity: RiskGuardrailSeverity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let limitFraction = min(max(limitValue / scaleMax, 0), 1)
            let actualFraction = actualValue.map { min(max($0 / scaleMax, 0), 1) } ?? 0

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PortfolixTheme.subtleFill)
                    .frame(height: 6)

                if actualValue != nil && actualFraction > 0 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barFill)
                        .frame(width: max(width * actualFraction, 4), height: 6)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: barFill)
                }

                // Clear threshold reference marker distinct from the native glass slider
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(PortfolixTheme.text.opacity(0.68))
                    .frame(width: 2, height: 12)
                    .offset(x: min(max(width * limitFraction - 1, 0), max(width - 2, 0)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: limitFraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private var barFill: Color {
        switch severity {
        case .noData: PortfolixTheme.borderStrong
        case .normal: PortfolixTheme.gainFill
        case .approaching: PortfolixTheme.warnFill
        case .breached: PortfolixTheme.lossFill
        }
    }
}
