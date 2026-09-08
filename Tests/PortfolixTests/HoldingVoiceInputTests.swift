import Testing
import PortfolixCore

struct HoldingVoiceInputTests {
    @Test(arguments: [
        ("12345.67", "12345.67"), ("12,345.67", "12345.67"),
        ("１２３．４５", "123.45"), ("一二三点四五。", "123.45"),
        ("一千二百三十四点五六", "1234.56"), ("零点零五", "0.05"),
        ("十二", "12"), ("一百零二", "102"), ("一万零五", "10005"),
        ("一万二千三百四十五", "12345"), ("零", "0")
    ])
    func normalizesUnambiguousNumbers(input: String, expected: String) {
        #expect(SpokenNumber.normalize(input) == expected)
    }

    @Test(arguments: ["", "一百二", "一万二", "12 34", "12,34", "10 或 20", "-100", "NaN", "Infinity", "12元", "百分之五", "一二百", "一千百", "一亿亿", "999999999999999999999999999999999999999999"])
    func rejectsAmbiguousOrUnsafeNumbers(_ input: String) {
        #expect(SpokenNumber.normalize(input) == nil)
    }
}
