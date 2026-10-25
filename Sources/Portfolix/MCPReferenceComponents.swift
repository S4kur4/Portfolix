import AppKit
import SwiftUI

@MainActor
enum MCPReferenceCodeLayout {
    static let inset: CGFloat = 12
    static let maximumHeight: CGFloat = 280
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    static func attributes(color: NSColor = .labelColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        return [.font: font, .paragraphStyle: paragraph, .foregroundColor: color]
    }

    static func measuredHeight(for text: String, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(string: text, attributes: attributes())
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(1, width - inset * 2), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byCharWrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return max(ceil(manager.usedRect(for: container).height), ceil(manager.defaultLineHeight(for: font))) + inset * 2
    }

    static func viewportHeight(for text: String, width: CGFloat) -> CGFloat {
        min(maximumHeight, measuredHeight(for: text, width: width))
    }
}

struct MCPReferenceCodeView: NSViewRepresentable {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> MCPReferenceCodeScrollView { MCPReferenceCodeScrollView() }

    func updateNSView(_ view: MCPReferenceCodeScrollView, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.setText(text)
    }
}

/// Display-only TextKit view: soft wraps never alter the copied configuration.
final class MCPReferenceCodeScrollView: NSScrollView {
    let codeTextView = NSTextView(frame: .zero)

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.isRichText = false
        codeTextView.drawsBackground = false
        codeTextView.isHorizontallyResizable = false
        codeTextView.isVerticallyResizable = true
        codeTextView.autoresizingMask = [.width]
        codeTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        codeTextView.textContainerInset = NSSize(width: MCPReferenceCodeLayout.inset, height: MCPReferenceCodeLayout.inset)
        codeTextView.textContainer?.widthTracksTextView = true
        codeTextView.textContainer?.lineFragmentPadding = 0
        codeTextView.textContainer?.lineBreakMode = .byCharWrapping
        codeTextView.isAutomaticLinkDetectionEnabled = false
        codeTextView.isAutomaticQuoteSubstitutionEnabled = false
        codeTextView.isAutomaticDashSubstitutionEnabled = false
        codeTextView.isAutomaticTextReplacementEnabled = false
        codeTextView.isAutomaticSpellingCorrectionEnabled = false
        codeTextView.isContinuousSpellCheckingEnabled = false
        documentView = codeTextView
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    func setText(_ text: String) {
        guard codeTextView.string != text else { return }
        codeTextView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: MCPReferenceCodeLayout.attributes()))
        codeTextView.setSelectedRange(NSRange(location: 0, length: 0))
        resizeDocument()
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }

    override func layout() {
        super.layout()
        resizeDocument()
    }

    private func resizeDocument() {
        guard contentSize.width > MCPReferenceCodeLayout.inset * 2 else { return }
        let width = max(1, contentSize.width)
        let height = MCPReferenceCodeLayout.measuredHeight(for: codeTextView.string, width: width)
        let size = NSSize(width: width, height: max(contentSize.height, height))
        if codeTextView.frame.size != size { codeTextView.setFrameSize(size) }
    }
}
