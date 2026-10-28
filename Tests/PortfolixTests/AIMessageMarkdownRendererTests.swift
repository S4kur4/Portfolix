import AppKit
import Foundation
import Testing
@testable import Portfolix

@Suite("Lightweight Agent message Markdown") @MainActor
struct AIMessageMarkdownRendererTests {
    private func render(_ text: String, citations: [AIMessageCitation] = []) -> NSAttributedString {
        AIMessageMarkdownRenderer.render(text, citations: citations, citationColor: .systemPurple)
    }

    private func range(_ substring: String, in text: NSAttributedString) throws -> NSRange {
        let range = (text.string as NSString).range(of: substring)
        #expect(range.location != NSNotFound)
        return try #require(range.location == NSNotFound ? nil : range)
    }

    @Test
    func emphasisKeepsTheExistingBodySize() throws {
        let result = render("普通 **重点**，*斜体*，***both***，__strong__。")
        #expect(result.string == "普通 重点，斜体，both，strong。")
        for word in ["重点", "strong", "both"] {
            let font = try #require(result.attribute(.font, at: range(word, in: result).location, effectiveRange: nil) as? NSFont)
            #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        }
        for word in ["斜体", "both"] {
            let font = try #require(result.attribute(.font, at: range(word, in: result).location, effectiveRange: nil) as? NSFont)
            #expect(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        }
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            #expect((value as? NSFont)?.pointSize == 13)
        }
    }

    @Test
    func underlineSupportsPairsWithoutLeakingIntoLaterText() throws {
        let result = render("<u>下划线 **重点**</u> 普通 <u><u>嵌套</u></u><u>相邻</u> 结尾")
        #expect(result.string == "下划线 重点 普通 嵌套相邻 结尾")
        for word in ["下划线", "重点", "嵌套", "相邻"] {
            #expect(result.attribute(.underlineStyle, at: try range(word, in: result).location, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        }
        for word in ["普通", "结尾"] {
            #expect(result.attribute(.underlineStyle, at: try range(word, in: result).location, effectiveRange: nil) == nil)
        }
        let unpaired = render("<u>未闭合，</u>正常 <u>未闭合")
        #expect(unpaired.string == "未闭合，正常 <u>未闭合")
        #expect(unpaired.attribute(.underlineStyle, at: try range("正常", in: unpaired).location, effectiveRange: nil) == nil)
        #expect(unpaired.attribute(.underlineStyle, at: unpaired.length - 1, effectiveRange: nil) == nil)
    }

    @Test
    func listsUseHangingIndentAndKeepParagraphBreaks() throws {
        let result = render("先看结论。\n\n- **核对持仓**\n  * 看清费用\n+ 保留余地\n1. 不追涨\n12) 分步调整\n\n结束。")
        #expect(result.string == "先看结论。\n\n•\t核对持仓\n•\t看清费用\n•\t保留余地\n1.\t不追涨\n12)\t分步调整\n\n结束。")
        for word in ["核对持仓", "看清费用", "保留余地", "不追涨", "分步调整"] {
            let style = try #require(result.attribute(.paragraphStyle, at: range(word, in: result).location, effectiveRange: nil) as? NSParagraphStyle)
            #expect(style.headIndent > style.firstLineHeadIndent)
            #expect(style.lineSpacing == 3)
            #expect(style.tabStops.first?.location == style.headIndent)
        }
        let nested = try #require(result.attribute(.paragraphStyle, at: range("看清费用", in: result).location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(nested.firstLineHeadIndent == 16)
        let normal = try #require(result.attribute(.paragraphStyle, at: range("结束", in: result).location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(normal.headIndent == 0)
    }

    @Test
    func escapesAndNegativeNumbersAreNotMisreadAsLists() {
        let result = render(#"\*\*literal\*\* and \*literal\*"# + "\n" + #"\- literal"# + "\n-5%\n**- not a list**")
        #expect(result.string == "**literal** and *literal*\n- literal\n-5%\n- not a list")
        #expect(!result.string.contains("•"))
        #expect(!result.string.contains("PFLL"))
    }

    @Test
    func unsupportedMarkupCannotCreateLargeFontsTablesOrInteractiveContent() {
        let result = render("# 标题\n| 资产 | 金额 |\n| --- | --- |\n| 示例 | 100 |\n`代码` ~~删除线~~ [网页](https://example.com) ![图片](https://example.com/image.png) <span style=\"font-size:99px\">原文</span>")
        #expect(result.string.contains("# 标题\n| 资产 | 金额 |"))
        #expect(result.string.contains("<span style=\"font-size:99px\">原文</span>"))
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { attributes, _, _ in
            #expect((attributes[.font] as? NSFont)?.pointSize == 13)
            #expect(attributes[.link] == nil)
            #expect(attributes[.attachment] == nil)
            #expect(attributes[.strikethroughStyle] == nil)
            #expect((attributes[.paragraphStyle] as? NSParagraphStyle)?.textBlocks.isEmpty == true)
        }
    }

    @Test
    func literalCodeNeverReceivesListDecoration() {
        let result = render("`<u>literal</u>`\n```\n- literal\n```")
        #expect(!result.string.contains("•"))
        #expect(!result.string.contains("PFLL"))
        #expect(result.string.contains("<u>literal</u>"))
        result.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            #expect(value == nil)
        }
    }

    @Test
    func citationsFollowTheCorrectSentenceAfterFormattingAndListNormalization() throws {
        let prefix = "- **黄金🪙上涨。**"
        let result = render(prefix + "\n- <u>观察风险。</u>", citations: [
            AIMessageCitation(utf16Offset: (prefix as NSString).length, title: "行情", url: "https://example.com/gold"),
            AIMessageCitation(utf16Offset: (prefix as NSString).length, title: "说明", url: "https://example.com/note"),
        ])
        #expect(result.string == "•\t黄金🪙上涨。\u{FFFC}\u{FFFC}\n•\t观察风险。")
        let index = ("•\t黄金🪙上涨。" as NSString).length
        #expect((result.attribute(.link, at: index, effectiveRange: nil) as? URL)?.absoluteString == "https://example.com/gold")
        #expect((result.attribute(.link, at: index + 1, effectiveRange: nil) as? URL)?.absoluteString == "https://example.com/note")
        #expect(result.attribute(AIMessageMarkdownRenderer.citationHelpKey, at: index, effectiveRange: nil) as? String == "行情\nhttps://example.com/gold")
        #expect(!result.string.contains("PFLC"))
    }

    @Test
    func unsafeCitationsAndOffsetsInsideEmojiAreIgnored() {
        let result = render("🪙黄金", citations: [
            AIMessageCitation(utf16Offset: 1, title: "Invalid offset", url: "https://example.com/offset"),
            AIMessageCitation(utf16Offset: 2, title: "Local", url: "https://127.0.0.1/private"),
            AIMessageCitation(utf16Offset: 2, title: "Insecure", url: "http://example.com"),
            AIMessageCitation(utf16Offset: 2, title: "Script", url: "javascript:alert(1)"),
        ])
        #expect(result.string == "🪙黄金")
        result.enumerateAttribute(.link, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            #expect(value == nil)
        }
    }

    @Test
    func legacyOutOfBoundsOffsetsCannotCorruptCitationMarkers() {
        let result = render("**重点**", citations: [500, 200, 100].map {
            AIMessageCitation(utf16Offset: $0, title: "说明", url: "https://example.com/note")
        })
        #expect(result.string == "重点\u{FFFC}\u{FFFC}\u{FFFC}")
        #expect(!result.string.contains("PFLC"))
    }

    @Test
    func nativeMessageViewRetainsContentAndStableHeightAcrossResizingAndLinkClicks() throws {
        let text = "**先核对持仓。**\n\n- 这是一条足够长的中文项目，用于检查窄窗口换行以后文字是否继续对齐。\n- <u>保留余地</u>，*分步调整*。"
        let citations = [AIMessageCitation(utf16Offset: (text as NSString).length, title: "说明", url: "https://example.com/note")]
        let view = AIReportCitationTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        view.update(text: text, citations: citations)
        let textView = try #require(view.subviews.compactMap { $0 as? NSTextView }.first)
        let content = textView.string
        let wide = view.fittingSize(for: 640)
        let narrow = view.fittingSize(for: 180)
        #expect(narrow.height > wide.height)
        #expect(narrow.height < 600)
        var opened = false
        view.urlOpener = { _ in opened = true; return true }
        #expect(view.openCitation("https://example.com/note"))
        #expect(opened)
        for width: CGFloat in [640, 180, 420, 180, 640] {
            view.update(text: text, citations: citations)
            let size = view.fittingSize(for: width)
            view.frame.size = size
            view.layoutSubtreeIfNeeded()
            #expect(textView.string == content)
            #expect(size.height == (width == 180 ? narrow.height : view.fittingSize(for: width).height))
        }
        #expect(view.fittingSize(for: 640) == wide)
    }

    @Test
    func syntheticVisualPreviewWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["PORTFOLIX_MARKDOWN_PREVIEW_DIRECTORY"] else { return }
        let text = "今天先看结构，不急着追涨。\n\n**真正值得关注的是持仓集中度。**\n- 核对 **同一行业** 的重复敞口；长句换行时，正文仍然对齐，不挤到项目符号下方。\n- *分步调整*，给自己留一点余地。\n- <u>费用和到账时间</u>也要一起核对。\n\n1. 先看证据，再做判断。\n2. 行情会变，计划不必跟着每一根 K 线跑。"
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try #require(NSAppearance(named: appearanceName))
            let view = AIReportCitationTextView(frame: NSRect(x: 24, y: 24, width: 440, height: 1))
            view.appearance = appearance
            view.update(text: text, citations: [AIMessageCitation(utf16Offset: (text as NSString).length, title: "示例来源", url: "https://example.com/note")])
            view.frame.size = view.fittingSize(for: 440)
            let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 488, height: view.frame.height + 48))
            wrapper.appearance = appearance
            wrapper.wantsLayer = true
            wrapper.layer?.backgroundColor = (name == "light" ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.09, alpha: 1)).cgColor
            wrapper.addSubview(view)
            wrapper.layoutSubtreeIfNeeded()
            let bitmap = try #require(wrapper.bitmapImageRepForCachingDisplay(in: wrapper.bounds))
            appearance.performAsCurrentDrawingAppearance { wrapper.cacheDisplay(in: wrapper.bounds, to: bitmap) }
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("agent-markdown-\(name).png"))
        }
    }
}
