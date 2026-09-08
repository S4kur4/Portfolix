import Foundation

/// Rejects ambiguous speech instead of guessing a holding's quantity or cost.
public enum SpokenNumber {
    public static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? input
        while let last = text.last, "。｡！？!?".contains(last) { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 80 else { return nil }
        if text.allSatisfy({ "0123456789.,".contains($0) }),
           text.range(of: #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?$"#, options: .regularExpression) != nil {
            return checked(text.replacingOccurrences(of: ",", with: ""))
        }
        let digits: [Character: String] = ["零":"0", "〇":"0", "一":"1", "二":"2", "两":"2", "三":"3", "四":"4", "五":"5", "六":"6", "七":"7", "八":"8", "九":"9"]
        let parts = text.components(separatedBy: "点")
        guard parts.count <= 2, !parts[0].isEmpty else { return nil }
        let integer: String
        if parts[0].allSatisfy({ digits[$0] != nil }) {
            integer = parts[0].compactMap { digits[$0] }.joined()
        } else {
            // Explicit units only: "一百二" is deliberately not interpreted as 102 or 120.
            let units: [Character: Int64] = ["十":10, "百":100, "千":1_000, "万":10_000, "亿":100_000_000]
            var total: Int64 = 0
            var section: Int64 = 0
            var digit: Int64?
            var lastSmall: Int64 = 10_000
            var lastLarge: Int64 = Int64.max
            var hadZero = false
            for char in parts[0] {
                if let value = digits[char], let number = Int64(value) {
                    if number == 0 { guard digit == nil else { return nil }; hadZero = true; continue }
                    guard digit == nil else { return nil }
                    digit = number
                } else if let unit = units[char] {
                    if unit < 10_000 {
                        guard unit < lastSmall, digit != nil || (unit == 10 && section == 0) else { return nil }
                        section += (digit ?? 1) * unit
                        lastSmall = unit
                    } else {
                        guard unit < lastLarge, section + (digit ?? 0) > 0 else { return nil }
                        total += (section + (digit ?? 0)) * unit
                        section = 0
                        lastLarge = unit
                        lastSmall = 10_000
                    }
                    digit = nil
                    hadZero = false
                } else { return nil }
            }
            if digit != nil, lastSmall != 10, !hadZero, lastSmall != 10_000 { return nil }
            if digit != nil, lastLarge != Int64.max, lastSmall == 10_000, !hadZero { return nil }
            integer = String(total + section + (digit ?? 0))
        }
        if parts.count == 2 {
            guard !parts[1].isEmpty, parts[1].allSatisfy({ digits[$0] != nil }) else { return nil }
            return checked(integer + "." + parts[1].compactMap { digits[$0] }.joined())
        }
        return checked(integer)
    }

    private static func checked(_ value: String) -> String? {
        guard value.filter({ $0 != "." }).count <= 28,
              let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN, number >= 0 else { return nil }
        return value
    }
}
