import AppKit
import SwiftUI

// MARK: - Unified Sheet Multiline Editor (Pixel-Aligned Cursor & Placeholder)

private struct PortfolixSheetMultilineEditor: View {
    let placeholder: String
    @Binding var text: String
    let maxCharacters: Int
    let height: CGFloat
    @State private var isFocused = false

    var body: some View {
        SheetMultilineTextRepresentable(
            placeholder: placeholder,
            text: $text,
            maxCharacters: maxCharacters,
            isFocused: $isFocused
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            PortfolixTheme.surface,
            in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                .strokeBorder(
                    isFocused ? PortfolixTheme.brandFocus : PortfolixTheme.controlBorder,
                    lineWidth: isFocused ? 1 : 0.75
                )
                .allowsHitTesting(false)
        }
    }
}

private struct SheetMultilineTextRepresentable: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let maxCharacters: Int
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = SheetPlaceholderNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.placeholderText = placeholder
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let font = NSFont.systemFont(ofSize: 13)
        textView.font = font
        textView.textColor = .labelColor
        textView.insertionPointColor = NSColor(PortfolixTheme.brandFocus)
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        if #available(macOS 15.2, *) {
            textView.writingToolsBehavior = .none
        }
        textView.onFocusChange = { focused in
            DispatchQueue.main.async {
                context.coordinator.parent.isFocused = focused
            }
        }
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? SheetPlaceholderNSTextView else { return }
        if textView.placeholderText != placeholder {
            textView.placeholderText = placeholder
            textView.needsDisplay = true
        }
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SheetMultilineTextRepresentable

        init(_ parent: SheetMultilineTextRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? SheetPlaceholderNSTextView else { return }
            if textView.hasMarkedText() {
                textView.needsDisplay = true
                return
            }
            var current = textView.string
            if current.count > parent.maxCharacters {
                current = String(current.prefix(parent.maxCharacters))
                textView.string = current
                textView.setSelectedRange(NSRange(location: (current as NSString).length, length: 0))
            }
            if parent.text != current {
                parent.text = current
            }
            textView.needsDisplay = true
        }
    }
}

@MainActor
private final class SheetPlaceholderNSTextView: NSTextView {
    var placeholderText = ""
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange?(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholderText.isEmpty else { return }
        let origin = textContainerOrigin
        let availableWidth = max(1, (textContainer?.containerSize.width ?? bounds.width) - 2)
        let paragraph = (defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: paragraph,
        ]
        let rect = NSRect(
            x: origin.x,
            y: origin.y,
            width: availableWidth,
            height: max(1, bounds.height - origin.y * 2)
        )
        (placeholderText as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }
}

// MARK: - Custom Advisor Preference Sheet (Minimal & Focused)

struct AIAdvisorPersonaSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var customPreference = ""

    private var language: AppLanguage { store.appLanguage }
    private let sheetWidth: CGFloat = 500

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: localizedText("自定义投研偏好", "Custom Research Preference", language: language),
                symbol: "slider.horizontal.3"
            )

            Divider().overlay(PortfolixTheme.border)

            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(localizedText("补充偏好", "Preference", language: language))
                        .font(PortfolixTypography.bodyEmphasis)
                        .foregroundStyle(PortfolixTheme.text)
                    Spacer()
                    Text("\(customPreference.count)/\(AIAdvisorPersonaSettings.maximumCustomPreferenceCharacters)")
                        .font(PortfolixTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(PortfolixTheme.tertiary)
                }

                PortfolixSheetMultilineEditor(
                    placeholder: localizedText(
                        "例如：优先提示单一持仓回撤与流动性红线，少讲宏观背景铺垫。\n将叠加在当前所选投研风格之上，仅调整表达侧重，不覆盖事实核验与本地数据安全边界。",
                        "e.g. Highlight single-holding drawdown and liquidity limits first; keep macro brief.\nApplies on top of your selected style preset without overriding verification or local privacy rules.",
                        language: language
                    ),
                    text: $customPreference,
                    maxCharacters: AIAdvisorPersonaSettings.maximumCustomPreferenceCharacters,
                    height: 136
                )
            }
            .padding(PortfolixSpacing.xl)

            Divider().overlay(PortfolixTheme.border)

            SheetActionFooter(errorMessage: nil) {
                if !customPreference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(localizedText("清空", "Clear", language: language)) {
                        customPreference = ""
                    }
                    .buttonStyle(QuietButtonStyle())
                }

                Button(localizedText("取消", "Cancel", language: language)) {
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(localizedText("保存", "Save", language: language)) {
                    var updated = store.aiAdvisorPersona
                    updated.customPreference = customPreference.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.aiAdvisorPersona = updated
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: sheetWidth)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.portfolixFormGlass, true)
        .background { PortfolixSheetBackground() }
        .onExitCommand { dismiss() }
        .onAppear {
            customPreference = store.aiAdvisorPersona.customPreference
        }
    }
}

// MARK: - Gemini/ChatGPT-Style Memory Summary Sheet

struct AIMemoryManagerSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draftSummary = ""
    @State private var isClearConfirmationPresented = false

    private var language: AppLanguage { store.appLanguage }
    private let sheetWidth: CGFloat = 540

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: localizedText("投研记忆", "Research Memory", language: language),
                symbol: "brain.head.profile"
            )

            Divider().overlay(PortfolixTheme.border)

            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(localizedText("记忆摘要", "Memory Summary", language: language))
                        .font(PortfolixTypography.bodyEmphasis)
                        .foregroundStyle(PortfolixTheme.text)
                    Spacer()
                    Text("\(draftSummary.count)/\(AIMemoryPolicy.maximumSummaryCharacters)")
                        .font(PortfolixTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(PortfolixTheme.tertiary)
                }

                PortfolixSheetMultilineEditor(
                    placeholder: localizedText(
                        "目前暂无已记住的偏好。你在对话中提到的资金用途、投资周期或持仓逻辑会自动汇总于此，也可以直接填写或修改。\n仅保存在本机数据库，可随时编辑或清空。",
                        "No saved preferences yet. Durable goals, cash constraints, or holding theses mentioned in chat will appear here, or write them directly.\nStored locally on this Mac only; edit or clear anytime.",
                        language: language
                    ),
                    text: $draftSummary,
                    maxCharacters: AIMemoryPolicy.maximumSummaryCharacters,
                    height: 240
                )
            }
            .padding(PortfolixSpacing.xl)

            Divider().overlay(PortfolixTheme.border)

            SheetActionFooter(errorMessage: nil) {
                if !draftSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(localizedText("清空", "Clear", language: language)) {
                        isClearConfirmationPresented = true
                    }
                    .buttonStyle(QuietButtonStyle())
                }

                Button(localizedText("取消", "Cancel", language: language)) {
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(localizedText("保存", "Save", language: language)) {
                    store.saveAIMemorySummary(draftSummary)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: sheetWidth)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.portfolixFormGlass, true)
        .background { PortfolixSheetBackground() }
        .onExitCommand { dismiss() }
        .onAppear {
            draftSummary = store.aiMemorySummary
        }
        .alert(
            localizedText("清空投研记忆？", "Clear research memory?", language: language),
            isPresented: $isClearConfirmationPresented
        ) {
            Button(localizedText("取消", "Cancel", language: language), role: .cancel) {}
            Button(localizedText("清空", "Clear", language: language), role: .destructive) {
                draftSummary = ""
                store.clearAllAIMemoryItems()
            }
        } message: {
            Text(localizedText(
                "将清空已保存的投研记忆摘要，不影响持仓数据与历史对话。",
                "Clears the saved research memory summary. Holdings and chat history remain intact.",
                language: language
            ))
        }
    }
}

// MARK: - Top Header Threads Popover (Minimal + Clear All)

struct AIReportThreadsPopover: View {
    let threads: [AIChatThread]
    let activeThreadID: UUID?
    let canClearAll: Bool
    let isInteractionEnabled: Bool
    let language: AppLanguage
    let onSelectThread: (UUID) -> Void
    let onDeleteThread: (UUID) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(localizedText("历史话题", "Conversations", language: language))
                    .font(PortfolixTypography.labelEmphasis)
                    .foregroundStyle(PortfolixTheme.text)
                Spacer()
                Button {
                    onClearAll()
                } label: {
                    Text(localizedText("清空所有", "Clear All", language: language))
                        .font(PortfolixTypography.captionEmphasis)
                        .foregroundStyle(
                            canClearAll && isInteractionEnabled
                                ? PortfolixTheme.lossText
                                : PortfolixTheme.disabled
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canClearAll || !isInteractionEnabled)
            }
            .padding(.horizontal, PortfolixSpacing.md)
            .padding(.vertical, PortfolixSpacing.sm + 2)

            Divider().overlay(PortfolixTheme.border)

            if threads.isEmpty {
                Text(localizedText("暂无历史话题", "No conversations yet", language: language))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(threads) { thread in
                            let isActive = thread.id == activeThreadID
                            HStack(spacing: PortfolixSpacing.sm) {
                                Button {
                                    onSelectThread(thread.id)
                                } label: {
                                    HStack(spacing: PortfolixSpacing.sm) {
                                        Circle()
                                            .fill(isActive ? PortfolixTheme.brandSolid : PortfolixTheme.disabled.opacity(0.4))
                                            .frame(width: 6, height: 6)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(thread.title)
                                                .font(isActive ? PortfolixTypography.captionEmphasis : PortfolixTypography.caption)
                                                .foregroundStyle(isActive ? PortfolixTheme.text : PortfolixTheme.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)

                                            Text(
                                                localizedText(
                                                    "\(thread.messageCount) 条记录 · \(relativeDateText(thread.updatedAt))",
                                                    "\(thread.messageCount) items · \(relativeDateText(thread.updatedAt))",
                                                    language: language
                                                )
                                            )
                                            .font(PortfolixTypography.micro)
                                            .foregroundStyle(PortfolixTheme.tertiary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!isInteractionEnabled)

                                Button {
                                    onDeleteThread(thread.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(PortfolixTheme.tertiary)
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!isInteractionEnabled)
                                .portfolixHelp(localizedText("删除话题", "Delete thread", language: language))
                            }
                            .padding(.horizontal, PortfolixSpacing.sm + 2)
                            .padding(.vertical, 6)
                            .background(
                                isActive ? PortfolixTheme.brandWash : Color.clear,
                                in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                            )
                        }
                    }
                    .padding(PortfolixSpacing.sm)
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 300)
    }

    private func relativeDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .english ? "en_US_POSIX" : "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM/dd"
        return formatter.string(from: date)
    }
}

// MARK: - Inline Extracted Memory Pill (Transparent & Immediately Undoable)

struct AIReportExtractedMemoriesStrip: View {
    let memories: [AIMemoryItem]
    let language: AppLanguage
    let onUndo: (UUID) -> Void
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(memories) { item in
                HStack(spacing: PortfolixSpacing.xs + 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.brandText)

                    Text(
                        localizedText(
                            "已记住：\(item.content)",
                            "Remembered: \(item.content)",
                            language: language
                        )
                    )
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Button {
                        onManage()
                    } label: {
                        Text(localizedText("管理", "Manage", language: language))
                            .font(PortfolixTypography.captionEmphasis)
                            .foregroundStyle(PortfolixTheme.brandText)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onUndo(item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .portfolixHelp(localizedText("删除这条记忆", "Remove this memory", language: language))
                }
                .padding(.horizontal, PortfolixSpacing.sm + 2)
                .padding(.vertical, 5)
                .background(
                    PortfolixTheme.brandWash.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                        .strokeBorder(PortfolixTheme.brandFocus.opacity(0.22), lineWidth: 0.5)
                }
            }
        }
    }
}
