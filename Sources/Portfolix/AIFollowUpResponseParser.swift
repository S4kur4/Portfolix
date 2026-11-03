import Foundation

enum AIFollowUpResponseParser {
    private static let maximumInputBytes = 128 * 1024
    private static let maximumObjects = 32
    private static let maximumEnvelopeDepth = 3
    private static let leadingMarkdownLink = try! NSRegularExpression(pattern: #"^\[[^\[\]\r\n]+\]\([^\s()]+\)"#)

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

    private static func inspect(_ raw: String, depth: Int) -> Result {
        guard depth <= maximumEnvelopeDepth, raw.utf8.count <= maximumInputBytes else {
            return .invalid(readablePrefix: nil)
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let payload = try? JSONDecoder().decode(LLMFollowUpPayload.self, from: Data(text.utf8)) {
            return normalized(payload, depth: depth)
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
                      ["answer", "limitations"].contains(key) else { return false }
                return keyText[keyText.index(after: index)...].drop(while: \.isWhitespace).first == ":"
            }
        }
        return false
    }
}
