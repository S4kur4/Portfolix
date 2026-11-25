import AppKit
import Foundation

@MainActor
enum AIMessageMarkdownRenderer {
    static let citationHelpKey = NSAttributedString.Key("PortfolixCitationHelp")
    private static let literalKey = NSAttributedString.Key("PortfolixMarkdownLiteral")
    private static let listPrefix = try! NSRegularExpression(pattern: #"(?m)^([ \t]*)([-+*]|[0-9]{1,9}[.)])[ \t]+(?=\S)"#)
    private static let headingPrefix = try! NSRegularExpression(pattern: #"(?m)^(##|###)[ \t]+(?=\S)"#)
    private static let quotePrefix = try! NSRegularExpression(pattern: #"(?m)^>[ \t]?(?=\S)"#)
    private static let underlineTags = try! NSRegularExpression(pattern: #"</?u>"#, options: .caseInsensitive)

    static let bodyLineSpacing: CGFloat = 5
    static let bodyParagraphSpacing: CGFloat = 8
    static let listLineSpacing: CGFloat = 4.5
    static let listParagraphSpacing: CGFloat = 4

    static func render(_ text: String, citations: [AIMessageCitation] = [], citationColor: NSColor) -> NSAttributedString {
        let sanitized = AIUserFacingTextSanitizer.sanitize(text, citations: citations)
        let source = NSMutableString(string: sanitized.text)
        let sourceLength = source.length
        let nonce = UUID().uuidString
        var markers: [(String, AIMessageCitation, URL)] = []
        let ordered = sanitized.citations.enumerated().sorted {
            $0.element.utf16Offset == $1.element.utf16Offset
                ? $0.offset > $1.offset : $0.element.utf16Offset > $1.element.utf16Offset
        }
        for (index, citation) in ordered {
            guard let components = try? LLMBaseURLValidator.validatedComponents(from: citation.url), let url = components.url else { continue }
            let offset = min(max(0, citation.utf16Offset), sourceLength)
            // A persisted offset must not split a UTF-16 surrogate pair (for example, an emoji).
            if offset > 0, offset < sourceLength,
               (0xD800...0xDBFF).contains(source.character(at: offset - 1)),
               (0xDC00...0xDFFF).contains(source.character(at: offset)) { continue }
            let marker = "⟦PFLC\(nonce)C\(index)⟧"
            source.insert(marker, at: offset)
            markers.append((marker, citation, url))
        }

        let headings = protectHeadingPrefixes(source, nonce: nonce)
        let quotes = protectQuotePrefixes(source, nonce: nonce)
        let lists = protectListPrefixes(source, nonce: nonce)
        let result = inlineText(source as String)
        decorateLists(result, lists: lists)
        decorateQuotes(result, quotes: quotes, accentColor: citationColor)
        decorateHeadings(result, headings: headings)
        for (marker, citation, url) in markers {
            let range = (result.string as NSString).range(of: marker)
            guard range.location != NSNotFound else { continue }
            let attachment = NSTextAttachment()
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [citationColor]))
            attachment.image = NSImage(systemSymbolName: "link", accessibilityDescription: "\(citation.title), \(citation.url)")?
                .withSymbolConfiguration(symbolConfig)
            attachment.bounds = NSRect(x: 0, y: -1, width: 12, height: 12)
            let icon = NSMutableAttributedString(attachment: attachment)
            icon.addAttributes([
                .link: url, citationHelpKey: "\(citation.title)\n\(citation.url)",
                .foregroundColor: citationColor, .cursor: NSCursor.pointingHand,
            ], range: NSRange(location: 0, length: icon.length))
            result.replaceCharacters(in: range, with: icon)
        }
        result.removeAttribute(literalKey, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func inlineText(_ source: String) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = bodyLineSpacing
        paragraph.paragraphSpacing = bodyParagraphSpacing
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        guard let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSMutableAttributedString(string: source, attributes: base)
        }
        var pieces: [(text: String, intent: InlinePresentationIntent)] = []
        for run in parsed.runs {
            guard run.imageURL == nil else { continue }
            let text = String(parsed[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            let matches = underlineTags.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            if intent.contains(.inlineHTML), !matches.isEmpty,
               matches.reduce(0, { $0 + $1.range.length }) == (text as NSString).length {
                pieces += matches.map { ((text as NSString).substring(with: $0.range), intent) }
            } else {
                pieces.append((text, intent))
            }
        }
        var stack: [Int] = []
        var pairedUnderlineTags = Set<Int>()
        for (index, piece) in pieces.enumerated() where piece.intent.contains(.inlineHTML) {
            let tag = piece.text.lowercased()
            if tag == "<u>" { stack.append(index) }
            if tag == "</u>", let opening = stack.popLast() {
                pairedUnderlineTags.insert(opening)
                pairedUnderlineTags.insert(index)
            }
        }
        let result = NSMutableAttributedString(string: "")
        var underlineDepth = 0
        for (index, piece) in pieces.enumerated() {
            let content = piece.text
            if pairedUnderlineTags.contains(index) {
                underlineDepth += content.lowercased() == "<u>" ? 1 : -1
                continue
            }
            let intent = piece.intent
            var attributes = base
            var font = NSFont.systemFont(ofSize: 13)
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            attributes[.font] = font
            if underlineDepth > 0 { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if intent.contains(.code) { attributes[literalKey] = true }
            // Only the supported emphasis attributes survive; Markdown links/images/HTML never become interactive content.
            result.append(NSAttributedString(string: content, attributes: attributes))
        }
        return result
    }

    private struct ListMarker {
        let token: String
        let original: String
        let whitespace: String
        let marker: String
    }

    private static func protectListPrefixes(_ source: NSMutableString, nonce: String) -> [ListMarker] {
        let matches = listPrefix.matches(in: source as String, range: NSRange(location: 0, length: source.length))
        var markers: [ListMarker] = []
        for (index, match) in matches.enumerated().reversed() {
            let token = "⟦PFLL\(nonce)L\(index)⟧"
            markers.append(ListMarker(token: token, original: source.substring(with: match.range),
                whitespace: source.substring(with: match.range(at: 1)), marker: source.substring(with: match.range(at: 2))))
            source.replaceCharacters(in: match.range, with: token)
        }
        return markers
    }

    private struct HeadingMarker {
        let token: String
        let original: String
        let level: Int
    }

    private struct QuoteMarker {
        let token: String
        let original: String
    }

    private static func protectHeadingPrefixes(_ source: NSMutableString, nonce: String) -> [HeadingMarker] {
        let matches = headingPrefix.matches(in: source as String, range: NSRange(location: 0, length: source.length))
        var markers: [HeadingMarker] = []
        for (index, match) in matches.enumerated().reversed() {
            let token = "⟦PFLH\(nonce)H\(index)⟧"
            let hashes = source.substring(with: match.range(at: 1))
            markers.append(HeadingMarker(token: token, original: source.substring(with: match.range), level: hashes.count))
            source.replaceCharacters(in: match.range, with: token)
        }
        return markers
    }

    private static func protectQuotePrefixes(_ source: NSMutableString, nonce: String) -> [QuoteMarker] {
        let matches = quotePrefix.matches(in: source as String, range: NSRange(location: 0, length: source.length))
        var markers: [QuoteMarker] = []
        for (index, match) in matches.enumerated().reversed() {
            let token = "⟦PFLQ\(nonce)Q\(index)⟧"
            markers.append(QuoteMarker(token: token, original: source.substring(with: match.range)))
            source.replaceCharacters(in: match.range, with: token)
        }
        return markers
    }

    private static func decorateHeadings(_ text: NSMutableAttributedString, headings: [HeadingMarker]) {
        for heading in headings {
            let range = (text.string as NSString).range(of: heading.token)
            guard range.location != NSNotFound else { continue }
            if text.attribute(literalKey, at: range.location, effectiveRange: nil) != nil {
                text.replaceCharacters(in: range, with: heading.original)
                continue
            }
            text.replaceCharacters(in: range, with: "")
            guard range.location < text.length else { continue }
            let paragraphRange = (text.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0))
            let fontSize: CGFloat = heading.level == 2 ? 15 : 13
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacingBefore = paragraphRange.location == 0 ? 0 : (heading.level == 2 ? 10 : 8)
            paragraph.paragraphSpacing = 4
            text.addAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ], range: paragraphRange)
        }
    }

    private static func decorateQuotes(_ text: NSMutableAttributedString, quotes: [QuoteMarker], accentColor: NSColor) {
        for quote in quotes {
            let range = (text.string as NSString).range(of: quote.token)
            guard range.location != NSNotFound else { continue }
            if text.attribute(literalKey, at: range.location, effectiveRange: nil) != nil {
                text.replaceCharacters(in: range, with: quote.original)
                continue
            }
            let bar = NSAttributedString(
                string: "▎\t",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: accentColor,
                ]
            )
            text.replaceCharacters(in: range, with: bar)
            let paragraphRange = (text.string as NSString).paragraphRange(for: NSRange(location: range.location, length: bar.length))
            let bodyStart = range.location + bar.length
            if bodyStart < NSMaxRange(paragraphRange) {
                text.addAttribute(
                    .foregroundColor,
                    value: NSColor.secondaryLabelColor,
                    range: NSRange(location: bodyStart, length: NSMaxRange(paragraphRange) - bodyStart)
                )
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = listLineSpacing
            paragraph.paragraphSpacing = 6
            paragraph.firstLineHeadIndent = 2
            paragraph.headIndent = 14
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 14)]
            text.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
        }
    }

    private static func decorateLists(_ text: NSMutableAttributedString, lists: [ListMarker]) {
        for list in lists {
            let range = (text.string as NSString).range(of: list.token)
            guard range.location != NSNotFound else { continue }
            if text.attribute(literalKey, at: range.location, effectiveRange: nil) != nil {
                text.replaceCharacters(in: range, with: list.original)
                continue
            }
            let whitespace = list.whitespace
            let sourceMarker = list.marker
            let marker = ["-", "+", "*"].contains(sourceMarker) ? "•" : sourceMarker
            let indentation = CGFloat(min(3, whitespace.replacingOccurrences(of: "\t", with: "  ").count / 2)) * 16
            let markerWidth = (marker as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
            let textIndent = indentation + max(16, ceil(markerWidth / 4) * 4 + 4)
            text.replaceCharacters(in: range, with: marker + "\t")
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = listLineSpacing
            paragraph.paragraphSpacing = listParagraphSpacing
            paragraph.firstLineHeadIndent = indentation
            paragraph.headIndent = textIndent
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: textIndent)]
            let paragraphRange = (text.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 1))
            text.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
        }
    }
}
