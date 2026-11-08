import Foundation

enum AIFollowUpResponseParser {
    private static let maximumInputBytes = 128 * 1024
    private static let maximumObjects = 32
    private static let maximumEnvelopeDepth = 3
    private static let leadingMarkdownLink = try! NSRegularExpression(pattern: #"^\[[^\[\]\r\n]+\]\([^\s()]+\)"#)
    private static let answerMarker = try! NSRegularExpression(pattern: #"(?im)^[\t ]*<answer(?=[\s>]|$)"#)
    private static let limitationsMarker = try! NSRegularExpression(pattern: #"(?im)(?:^[\t ]*|(?<=[。.!?！？])[\t ]*)<limitations(?=[\s>]|$)"#)
    private static let orphanClosingMarker = try! NSRegularExpression(pattern: #"(?im)^[\t ]*</(?:answer|limitations)(?=[\s>]|$)"#)

    private enum Result {
        case value(LLMFollowUpPayload)
        case invalid(readablePrefix: String?)
    }

    private struct ObjectSpan {
        let range: Range<String.Index>
        let isComplete: Bool
    }

    static func decode(_ raw: String) -> LLMFollowUpPayload? {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard case let .value(payload) = inspect(raw, depth: 0) else { return nil }
        return payload
    }

    static func readableText(_ raw: String) -> String? {
        switch inspect(raw, depth: 0) {
        case let .value(payload): return payload.answer
        case let .invalid(prefix): return prefix
        }
    }

    static func displayText(_ raw: String) -> String {
        readableText(raw) ?? (AIResponseLanguage.detecting(from: raw) == .english
            ? "This reply could not be displayed. Please ask again."
            : "这条回复暂时无法显示，请重新提问。")
    }

    static func containsResponseEnvelope(_ text: String) -> Bool {
        guard text.utf8.count <= maximumInputBytes else { return true }
        let range = NSRange(text.startIndex..., in: text)
        if answerMarker.firstMatch(in: text, range: range) != nil
            || limitationsMarker.firstMatch(in: text, range: range) != nil
            || orphanClosingMarker.firstMatch(in: text, range: range) != nil { return true }
        return objectSpans(in: text)?.contains { startsWithEnvelopeKey(text[$0.range]) } ?? true
    }

    private static func inspect(_ raw: String, depth: Int) -> Result {
        guard depth <= maximumEnvelopeDepth, raw.utf8.count <= maximumInputBytes else {
            return .invalid(readablePrefix: nil)
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let payload = try? JSONDecoder().decode(LLMFollowUpPayload.self, from: Data(text.utf8)) {
            return normalized(payload, depth: depth)
        }
        if let result = inspectTaggedAnswer(in: text, depth: depth) { return result }
        if let result = inspectTaggedLimitations(in: text, depth: depth) { return result }
        if let marker = orphanClosingMarker.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(marker.range, in: text) {
            return .invalid(readablePrefix: readablePrefix(String(text[..<range.lowerBound]), depth: depth + 1))
        }

        guard let spans = objectSpans(in: text) else { return .invalid(readablePrefix: nil) }
        var firstEnvelopeStart: String.Index?
        // A final envelope is authoritative; preceding prose may be a duplicate draft.
        for span in spans.reversed() {
            let candidate = text[span.range]
            let payload = span.isComplete
                ? try? JSONDecoder().decode(LLMFollowUpPayload.self, from: Data(candidate.utf8)) : nil
            guard payload != nil || startsWithEnvelopeKey(candidate) else { continue }
            let suffix = text[span.range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let lineStart = text[..<span.range.lowerBound].lastIndex(of: "\n")
                .map { text.index(after: $0) } ?? text.startIndex
            let beginsLine = text[lineStart..<span.range.lowerBound].allSatisfy(\.isWhitespace)
            guard beginsLine || suffix.isEmpty || suffix == "```" else { continue }
            if let payload, firstEnvelopeStart == nil { return normalized(payload, depth: depth) }
            firstEnvelopeStart = span.range.lowerBound
        }
        if let firstEnvelopeStart {
            var prefix = String(text[..<firstEnvelopeStart]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let fence = prefix.range(of: "```", options: .backwards),
               ["```", "```json"].contains(prefix[fence.lowerBound...].lowercased()) {
                prefix = String(prefix[..<fence.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return .invalid(readablePrefix: prefix.isEmpty ? nil : prefix)
        }
        let beginsWithLink = leadingMarkdownLink.firstMatch(
            in: text, range: NSRange(location: 0, length: (text as NSString).length)
        ) != nil
        guard beginsWithLink || !["{", "[", "\"", "```json"].contains(where: { text.lowercased().hasPrefix($0) }) else {
            return .invalid(readablePrefix: nil)
        }
        return .value(LLMFollowUpPayload(answer: text, limitations: []))
    }

    private static func inspectTaggedAnswer(in text: String, depth: Int) -> Result? {
        guard let marker = answerMarker.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(marker.range, in: text) else { return nil }
        let block = String(text[range.lowerBound...])
        let prefix = String(text[..<range.lowerBound])
        guard let opening = block.range(of: #"(?i)^[\t ]*<answer\s*>"#, options: .regularExpression),
              let closing = block.range(of: #"(?i)</answer\s*>"#, options: .regularExpression),
              closing.lowerBound >= opening.upperBound
        else { return .invalid(readablePrefix: readablePrefix(prefix, depth: depth + 1)) }
        let body = String(block[opening.upperBound..<closing.lowerBound])
        let suffix = block[closing.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if suffix.isEmpty { return inspect(body, depth: depth + 1) }
        guard suffix.range(of: #"(?i)^<limitations(?=[\s>]|$)"#, options: .regularExpression) != nil else {
            return .invalid(readablePrefix: readablePrefix(body, depth: depth + 1))
        }
        return inspect(body + "\n" + suffix, depth: depth + 1)
    }

    private static func readablePrefix(_ text: String, depth: Int) -> String? {
        switch inspect(text, depth: depth) {
        case let .value(payload): return payload.answer.isEmpty ? nil : payload.answer
        case let .invalid(prefix): return prefix
        }
    }

    // Some responses append an XML-style metadata block instead of the JSON envelope.
    // Parse that block separately so live replies, history and conversation memory agree.
    private static func inspectTaggedLimitations(in text: String, depth: Int) -> Result? {
        let markers = limitationsMarker.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let first = markers.first, let range = Range(first.range, in: text) else { return nil }
        let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixResult = inspect(prefix, depth: depth + 1)
        let readablePrefix: String?
        switch prefixResult {
        case let .value(payload): readablePrefix = payload.answer.isEmpty ? nil : payload.answer
        case let .invalid(prefix): readablePrefix = prefix
        }
        let block = String(text[range.lowerBound...])
        guard markers.count == 1,
              let opening = block.range(of: #"(?i)^[\t ]*<limitations\s*>"#, options: .regularExpression),
              let closing = block.range(of: #"(?i)</limitations\s*>\s*$"#, options: .regularExpression),
              closing.lowerBound >= opening.upperBound,
              let limitations = try? JSONDecoder().decode([String].self,
                from: Data(block[opening.upperBound..<closing.lowerBound].utf8)),
              let readablePrefix
        else { return .invalid(readablePrefix: readablePrefix) }
        guard case let .value(payload) = prefixResult else { return prefixResult }
        var seen = Set<String>()
        return .value(LLMFollowUpPayload(answer: readablePrefix,
            limitations: (payload.limitations + limitations).filter { seen.insert($0).inserted }))
    }

    private static func normalized(_ payload: LLMFollowUpPayload, depth: Int) -> Result {
        switch inspect(payload.answer, depth: depth + 1) {
        case let .value(inner):
            var seen = Set<String>()
            let limitations = (payload.limitations + inner.limitations).filter { seen.insert($0).inserted }
            return .value(LLMFollowUpPayload(answer: inner.answer, limitations: limitations))
        case let .invalid(prefix):
            return .invalid(readablePrefix: prefix)
        }
    }

    // Locate object boundaries only; JSONDecoder remains responsible for values and escapes.
    private static func objectSpans(in text: String) -> [ObjectSpan]? {
        var spans: [ObjectSpan] = []
        var start: String.Index?
        var depth = 0
        var inString = false
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if start == nil {
                if character == "{" { start = index; depth = 1 }
                continue
            }
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0, let lowerBound = start {
                    spans.append(ObjectSpan(range: lowerBound..<text.index(after: index), isComplete: true))
                    guard spans.count <= maximumObjects else { return nil }
                    start = nil
                }
            }
        }
        if let start { spans.append(ObjectSpan(range: start..<text.endIndex, isComplete: false)) }
        return spans.count <= maximumObjects ? spans : nil
    }

    private static func startsWithEnvelopeKey(_ text: Substring) -> Bool {
        let keyText = text.dropFirst().drop(while: \.isWhitespace)
        guard keyText.first == "\"" else { return false }
        var escaped = false
        for index in keyText.indices.dropFirst() {
            let character = keyText[index]
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" {
                guard let key = try? JSONDecoder().decode(String.self, from: Data(keyText[...index].utf8)),
                      ["answer", "limitations"].contains(key.lowercased()) else { return false }
                return true
            }
        }
        // A cut-off field name is still an internal envelope, not a prose fallback.
        guard let partial = try? JSONDecoder().decode(String.self, from: Data((String(keyText) + "\"").utf8)) else { return false }
        return ["answer", "limitations"].contains { $0.hasPrefix(partial.lowercased()) }
    }
}
