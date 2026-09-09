import Foundation
import Testing
import PortfolixCore
@testable import Portfolix

struct HoldingVoiceInputTests {
    @Test
    func waveformWidthOnlyChangesTheVisibleBarCount() {
        let shortCount = HoldingVoiceWaveformMetrics.visibleBarCount(for: 120)
        let longCount = HoldingVoiceWaveformMetrics.visibleBarCount(for: 720)

        #expect(HoldingVoiceWaveformMetrics.barWidth == 1.75)
        #expect(HoldingVoiceWaveformMetrics.barSpacing == 1.5)
        #expect(longCount > shortCount)
        #expect(
            abs(
                CGFloat(longCount - shortCount) * HoldingVoiceWaveformMetrics.barStep - 600
            ) <= HoldingVoiceWaveformMetrics.barStep
        )
    }

    @Test
    func waveformTimelineUsesOneGlobalSamplingGrid() {
        let date = Date(timeIntervalSinceReferenceDate: 123_456.789)
        let tick = HoldingVoiceWaveformMetrics.tick(at: date)
        let anchor = HoldingVoiceWaveformMetrics.anchor(for: tick)

        #expect(anchor <= date)
        #expect(date.timeIntervalSince(anchor) < HoldingVoiceWaveformMetrics.sampleInterval)
    }

    @Test
    func waveformNoiseFloorKeepsSilentInputStationary() {
        #expect(HoldingVoiceWaveformMetrics.visualLevel(from: 0) == 0)
        #expect(HoldingVoiceWaveformMetrics.visualLevel(from: 0.08) == 0)
        #expect(HoldingVoiceWaveformMetrics.visualLevel(from: 0.54) == 0.5)
        #expect(HoldingVoiceWaveformMetrics.visualLevel(from: 1) == 1)
        #expect(HoldingVoiceWaveformMetrics.activationSampleCount == 2)

        let silent = HoldingVoiceWaveformSnapshot.empty()
        #expect(!silent.hasVisibleSignal(for: 120))
        #expect(!silent.hasVisibleSignal(for: 720))
    }

    @Test
    func waveformStopsAfterTheSignalLeavesTheVisibleWindow() {
        var snapshot = HoldingVoiceWaveformSnapshot.empty()
        snapshot.levels[snapshot.levels.count - 1] = 0.8
        #expect(snapshot.hasVisibleSignal(for: 120))

        let visibleCount = HoldingVoiceWaveformMetrics.visibleBarCount(for: 120)
        snapshot.levels = Array(snapshot.levels.dropLast(visibleCount))
            + Array(repeating: 0, count: visibleCount)
        #expect(!snapshot.hasVisibleSignal(for: 120))
    }

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

    @Test
    func voiceTranscriptUsesBestEffortFormattingWithoutRejectingInput() {
        #expect(HoldingVoiceTranscript.value(from: "  一百零二  ", numeric: true) == "102")
        #expect(HoldingVoiceTranscript.value(from: "1339 7.5", numeric: true) == "13397.5")
        #expect(HoldingVoiceTranscript.value(from: "一 百 零 二", numeric: true) == "102")
        #expect(HoldingVoiceTranscript.value(from: "一百二", numeric: true) == "一百二")
        #expect(HoldingVoiceTranscript.value(from: "苹果", numeric: true) == "苹果")
        #expect(HoldingVoiceTranscript.value(from: "Apple 123", numeric: true) == "Apple 123")
        #expect(HoldingVoiceTranscript.value(from: " Apple ", numeric: false) == "Apple")
        #expect(HoldingVoiceTranscript.value(from: "hello world", numeric: false) == "hello world")
        #expect(HoldingVoiceTranscript.value(from: "   ", numeric: true) == nil)
    }
}
