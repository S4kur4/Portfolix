import SwiftUI
import AppKit
@preconcurrency import AVFoundation
@preconcurrency import Speech
import OSLog
import PortfolixCore

enum HoldingVoiceWaveformMetrics {
    static let barWidth: CGFloat = 1.75
    static let barSpacing: CGFloat = 1.5
    static let sampleInterval: TimeInterval = 1.0 / 30.0
    static let historyCount = 768
    static let noiseFloor: CGFloat = 0.08
    static let activationSampleCount = 2
    static let activationLevel: CGFloat = 0.04
    static let silenceEpsilon: CGFloat = 0.01

    static var barStep: CGFloat { barWidth + barSpacing }

    static func visibleBarCount(for width: CGFloat) -> Int {
        max(1, Int(ceil(width / barStep)) + 1)
    }

    static func tick(at date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSinceReferenceDate / sampleInterval))
    }

    static func anchor(for tick: Int64) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(tick) * sampleInterval)
    }

    static func visualLevel(from rawLevel: CGFloat) -> CGFloat {
        guard rawLevel > noiseFloor else { return 0 }
        return min(1, (rawLevel - noiseFloor) / (1 - noiseFloor))
    }

    static func phase(from anchor: Date, to date: Date) -> CGFloat {
        CGFloat(max(0, date.timeIntervalSince(anchor) / sampleInterval))
    }
}

struct HoldingVoiceWaveformSnapshot: Equatable {
    var levels: [CGFloat]
    var anchor: Date

    static func empty(at date: Date = Date()) -> HoldingVoiceWaveformSnapshot {
        let tick = HoldingVoiceWaveformMetrics.tick(at: date)
        return HoldingVoiceWaveformSnapshot(
            levels: Array(repeating: 0, count: HoldingVoiceWaveformMetrics.historyCount),
            anchor: HoldingVoiceWaveformMetrics.anchor(for: tick)
        )
    }

    func hasVisibleSignal(for width: CGFloat) -> Bool {
        let visibleCount = min(
            levels.count,
            HoldingVoiceWaveformMetrics.visibleBarCount(for: width)
        )
        return levels.suffix(visibleCount).contains {
            $0 > HoldingVoiceWaveformMetrics.silenceEpsilon
        }
    }

    var hasAnySignal: Bool {
        levels.contains { $0 > HoldingVoiceWaveformMetrics.silenceEpsilon }
    }

    /// Smoothed live voice energy (0...1) sampled from the most recent frames.
    var liveEnergy: CGFloat {
        let tail = levels.suffix(10)
        guard !tail.isEmpty else { return 0 }
        var peak: CGFloat = 0
        var weightedSum: CGFloat = 0
        var weightTotal: CGFloat = 0
        for (index, level) in tail.enumerated() {
            let weight = CGFloat(index + 1)
            peak = max(peak, level)
            weightedSum += level * weight
            weightTotal += weight
        }
        let recentAverage = weightTotal > 0 ? weightedSum / weightTotal : 0
        return min(1, max(0, peak * 0.65 + recentAverage * 0.35))
    }
}

/// Non-published mutable waveform buffer read directly by `HoldingVoiceWaveform`'s
/// `TimelineView` at display refresh rate, avoiding 30 Hz SwiftUI parent view invalidations.
@MainActor
final class HoldingVoiceWaveformBuffer {
    var snapshot = HoldingVoiceWaveformSnapshot.empty()
}

@MainActor
final class HoldingVoiceRecorder: ObservableObject {
    private static let logger = Logger(subsystem: "app.portfolix.mac", category: "HoldingVoiceInput")
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishing = false
    @Published private(set) var isStarting = false
    let waveformBuffer = HoldingVoiceWaveformBuffer()
    var waveform: HoldingVoiceWaveformSnapshot { waveformBuffer.snapshot }
    @Published var errorMessage: String?

    var isTranscribing: Bool {
        isFinishing && !isRecording && !isStarting
    }
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var activeShortcut: VoiceInputShortcut?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var modernSession: (any HoldingSpeechSession)?
    private var timeout: Task<Void, Never>?
    private var session: UUID?
    private var recognitionAttempt: UUID?
    private var held = false
    private var hasTap = false
    private var receivedFinal = false
    private var retryCount = 0
    private var transcript = ""
    private var commit: ((String) -> Void)?
    private var numeric = false
    private var english = false
    private var waveformTick = HoldingVoiceWaveformMetrics.tick(at: Date())
    private var pendingLevel: CGFloat = 0
    private var smoothedLevel: CGFloat = 0
    private var signalSampleCount = 0

    isolated deinit {
        blur()
    }

    func focus(
        numeric: Bool,
        english: Bool,
        shortcut: VoiceInputShortcut = .functionModifier,
        commit: @escaping (String) -> Void
    ) {
        self.numeric = numeric
        self.english = english
        self.commit = commit
        if resignObserver != nil, activeShortcut == shortcut {
            return
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        activeShortcut = shortcut

        switch shortcut {
        case .functionModifier:
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, event.keyCode == 63, NSApp?.isActive == true else { return }
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if flags.contains(.function) { self.press() } else { self.release() }
                }
                return event
            }
        case .f1:
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard event.keyCode == 122 else { return event }
                MainActor.assumeIsolated {
                    guard let self, NSApp?.isActive == true else { return }
                    if event.type == .keyDown { self.press() } else { self.release() }
                }
                return nil
            }
        case .none:
            break
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
    }

    func blur() {
        cancel()
        commit = nil
        activeShortcut = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    func press() {
        guard !held, !isFinishing, commit != nil else { return }
        held = true
        retryCount = 0
        transcript = ""
        receivedFinal = false
        resetWaveform()
        isStarting = true
        isFinishing = true
        let id = UUID()
        session = id
        let locale = Locale(identifier: english ? "en-US" : "zh-CN")
        Task { [weak self] in
            guard let self else { return }
            let audioAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
            guard self.session == id, self.held else { return }
            guard audioAuthorized else {
                self.fail("请在系统设置中允许 Portfolix 使用麦克风。", "Allow Microphone access for Portfolix in System Settings.")
                return
            }
            if #available(macOS 26.0, *) {
                await self.startModern(id: id, locale: locale)
            } else {
                let speechAuthorized = await Self.requestSpeechAuthorization()
                guard self.session == id, self.held else { return }
                guard speechAuthorized else {
                    self.fail("请在系统设置中允许 Portfolix 使用语音识别。", "Allow Speech Recognition for Portfolix in System Settings.")
                    return
                }
                self.startLegacy(id: id, locale: locale)
            }
        }
    }

    func toggle() {
        if held {
            release()
        } else if isRecording || isFinishing {
            cancel()
        } else {
            press()
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    @available(macOS 26.0, *)
    private func startModern(id: UUID, locale: Locale) async {
        isFinishing = true
        do {
            let modernSession = try await HoldingSpeechAnalyzerSession.start(
                locale: locale,
                onLevel: { [weak self] level in self?.record(level: level, id: id) },
                onTranscript: { [weak self] text in
                    guard let self, self.session == id else { return }
                    self.transcript = text
                },
                onComplete: { [weak self] text in
                    guard let self, self.session == id else { return }
                    self.transcript = text
                    self.modernSession = nil
                    self.isRecording = false
                    self.isFinishing = false
                    self.receivedFinal = true
                    self.complete()
                },
                onFailure: { [weak self] error in
                    guard let self, self.session == id else { return }
                    self.handleModernFailure(error)
                }
            )
            guard session == id, held else {
                modernSession.cancel()
                return
            }
            self.modernSession = modernSession
            isStarting = false
            isFinishing = false
            prepareWaveformSampling()
            isRecording = true
            scheduleRecordingTimeout(id: id)
        } catch {
            guard session == id else { return }
            handleModernFailure(error)
        }
    }

    private func startLegacy(id: UUID, locale: Locale) {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            fail("当前语言的本机语音识别不可用，请检查系统语音语言设置。", "On-device speech recognition is unavailable for this language. Check your system speech language settings.")
            return
        }
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = numeric ? .dictation : .search
        self.recognizer = recognizer
        self.engine = engine
        self.request = request
        let attempt = UUID()
        recognitionAttempt = attempt
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("没有可用的麦克风。", "No microphone is available.")
            return
        }
        let sink = VoiceAudioSink(request: request) { [weak self] value in
            Task { @MainActor in
                self?.record(level: value, id: id)
            }
        }
        sink.installTap(on: input, format: format)
        hasTap = true
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failure = error.map(SpeechTaskFailure.init)
            Task { @MainActor in
                guard let self, self.session == id, self.recognitionAttempt == attempt else { return }
                if let text { self.transcript = text }
                if isFinal {
                    self.receivedFinal = true
                    self.stopAudio()
                    self.complete()
                } else if let failure, !self.receivedFinal {
                    self.handleRecognitionFailure(failure, id: id, locale: locale)
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isStarting = false
            isFinishing = false
            prepareWaveformSampling()
            isRecording = true
            scheduleRecordingTimeout(id: id)
        } catch {
            fail("无法启动麦克风，请检查输入设备后重试。", "Cannot start the microphone. Check your input device and retry.")
        }
    }

    func release() {
        guard held else { return }
        held = false
        if receivedFinal { complete(); return }
        if let modernSession {
            isStarting = false
            isRecording = false
            isFinishing = true
            timeout?.cancel()
            modernSession.finish()
            scheduleFinalizationTimeout(id: session)
            return
        }
        guard isRecording else { cancel(); return }
        stopAudio()
        isStarting = false
        isRecording = false
        isFinishing = true
        request?.endAudio()
        timeout?.cancel()
        let id = session
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, self?.session == id else { return }
            if self?.hasTranscript == true {
                self?.complete()
                return
            }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self?.session == id else { return }
            self?.cancel()
        }
    }

    private func scheduleRecordingTimeout(id: UUID) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, self?.session == id else { return }
            self?.release()
        }
    }

    private func scheduleFinalizationTimeout(id: UUID?) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.session == id else { return }
            self?.cancel()
        }
    }

    private func record(level: Float, id: UUID) {
        guard session == id, isRecording else { return }
        pendingLevel = max(pendingLevel, CGFloat(level))

        let tick = HoldingVoiceWaveformMetrics.tick(at: Date())
        guard tick > waveformTick else { return }

        let elapsedTicks = tick - waveformTick
        let stepCount = min(Int(elapsedTicks), HoldingVoiceWaveformMetrics.historyCount)
        var newLevels: [CGFloat] = []
        newLevels.reserveCapacity(stepCount)
        var target = HoldingVoiceWaveformMetrics.visualLevel(from: pendingLevel)

        if target >= HoldingVoiceWaveformMetrics.activationLevel {
            signalSampleCount += 1
        } else {
            signalSampleCount = 0
            target = 0
        }
        if signalSampleCount < HoldingVoiceWaveformMetrics.activationSampleCount {
            target = 0
        }

        if target == 0,
           smoothedLevel <= HoldingVoiceWaveformMetrics.silenceEpsilon,
           !waveform.hasAnySignal {
            smoothedLevel = 0
            waveformTick = tick
            pendingLevel = 0
            return
        }

        for _ in 0 ..< stepCount {
            let response: CGFloat = target > smoothedLevel ? 0.48 : 0.24
            smoothedLevel += (target - smoothedLevel) * response
            if target == 0, smoothedLevel <= HoldingVoiceWaveformMetrics.silenceEpsilon {
                smoothedLevel = 0
            }
            newLevels.append(smoothedLevel)
            target *= 0.82
        }

        let retainedCount = HoldingVoiceWaveformMetrics.historyCount - stepCount
        var levels = Array(waveformBuffer.snapshot.levels.suffix(retainedCount))
        levels.append(contentsOf: newLevels)
        waveformTick = tick
        pendingLevel = 0
        waveformBuffer.snapshot = HoldingVoiceWaveformSnapshot(
            levels: levels,
            anchor: HoldingVoiceWaveformMetrics.anchor(for: tick)
        )
    }

    private func prepareWaveformSampling(at date: Date = Date()) {
        waveformTick = HoldingVoiceWaveformMetrics.tick(at: date)
        pendingLevel = 0
    }

    private func resetWaveform(at date: Date = Date()) {
        prepareWaveformSampling(at: date)
        smoothedLevel = 0
        signalSampleCount = 0
        waveformBuffer.snapshot = .empty(at: date)
    }

    @available(macOS 26.0, *)
    private func handleModernFailure(_ error: any Error) {
        let failure = SpeechTaskFailure(error)
        Self.logger.error("SpeechAnalyzer failed: domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)")
        if hasTranscript {
            modernSession = nil
            isRecording = false
            isFinishing = held
            receivedFinal = true
            complete()
            return
        }
        if let error = error as? HoldingSpeechAnalyzerError {
            switch error {
            case .unsupportedLocale:
                fail("当前语言暂不支持本机语音输入。", "On-device voice input is not supported for this language.")
            case .assetsUnavailable:
                fail("无法准备本机语音模型，请检查网络后重试。", "The on-device speech model could not be prepared. Check your network and retry.")
            case .noMicrophone:
                fail("没有可用的麦克风。", "No microphone is available.")
            case .unsupportedAudioFormat:
                fail("当前麦克风格式无法用于语音识别。", "The current microphone format cannot be used for speech recognition.")
            }
            return
        }
        cancel()
    }

    private var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleRecognitionFailure(_ failure: SpeechTaskFailure, id: UUID, locale: Locale) {
        Self.logger.error("Speech task failed: domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)")

        if hasTranscript {
            receivedFinal = true
            stopAudio()
            isRecording = false
            isFinishing = held
            complete()
            return
        }

        if held, retryCount == 0, failure.isRetryable {
            retryCount += 1
            recognitionAttempt = nil
            stopAudio()
            recognition?.cancel()
            recognition = nil
            request = nil
            recognizer = nil
            isRecording = false
            isFinishing = true
            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.session == id, self.held else { return }
                self.isFinishing = false
                self.startLegacy(id: id, locale: locale)
            }
            return
        }

        if let message = failure.userActionMessage() {
            fail(message.chinese, message.english)
        } else {
            cancel()
        }
    }

    private func complete() {
        // Final results can arrive before release; never replace text while Fn is held.
        guard !held else { return }
        guard let value = HoldingVoiceTranscript.value(from: transcript, numeric: numeric) else {
            cancel()
            return
        }
        let apply = commit
        cancel()
        apply?(value)
    }

    private func stopAudio() {
        if let engine, engine.isRunning { engine.stop() }
        if let engine, hasTap { engine.inputNode.removeTap(onBus: 0) }
        hasTap = false
        engine = nil
    }

    func cancel() {
        session = nil
        recognitionAttempt = nil
        held = false
        retryCount = 0
        timeout?.cancel()
        timeout = nil
        modernSession?.cancel()
        modernSession = nil
        stopAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
        recognizer = nil
        isStarting = false
        isRecording = false
        isFinishing = false
        resetWaveform()
        transcript = ""
    }

    private func fail(_ chinese: String, _ english: String) {
        cancel()
        errorMessage = self.english ? english : chinese
    }
}

enum VoiceInputShortcut {
    case functionModifier
    case f1
    case none
}

enum HoldingVoiceTranscript {
    static func value(from transcript: String, numeric: Bool) -> String? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard numeric else { return text }
        if let normalized = SpokenNumber.normalize(text) { return normalized }

        // Speech recognition can insert grouping spaces inside an otherwise valid number.
        let compactText = text.filter { !$0.isWhitespace }
        if compactText != text, let normalized = SpokenNumber.normalize(compactText) {
            return normalized
        }
        return text
    }
}

private struct SpeechTaskFailure: Sendable {
    let domain: String
    let code: Int

    init(_ error: any Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
    }

    var isRetryable: Bool {
        (domain == "kAFAssistantErrorDomain" && [203, 1100, 1101, 1107, 1110].contains(code))
            || (domain == "kLSRErrorDomain" && code == 300)
    }

    func userActionMessage() -> (chinese: String, english: String)? {
        switch (domain, code) {
        case ("kLSRErrorDomain", 102):
            ("当前语言的听写资源尚未安装，请先在系统设置中启用对应语言的听写。", "Dictation resources for this language are not installed. Enable this dictation language in System Settings first.")
        case ("kLSRErrorDomain", 201):
            ("系统听写已关闭，请先在系统设置中启用听写。", "System Dictation is disabled. Enable Dictation in System Settings first.")
        case ("kAFAssistantErrorDomain", 1700):
            ("请在系统设置中允许 Portfolix 使用语音识别。", "Allow Speech Recognition for Portfolix in System Settings.")
        default:
            nil
        }
    }
}

/// Only the serial audio tap touches this sink; UI updates are throttled off the audio thread.
private final class VoiceAudioSink: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    let update: @Sendable (Float) -> Void
    private var frames = 0
    init(request: SFSpeechAudioBufferRecognitionRequest, update: @escaping @Sendable (Float) -> Void) {
        self.request = request
        self.update = update
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        frames += Int(buffer.frameLength)
        let updateInterval = max(1, Int(buffer.format.sampleRate / 60))
        guard frames >= updateInterval, let channel = buffer.floatChannelData?[0] else { return }
        frames %= updateInterval
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[index])) }
        update(min(1, peak * 8))
    }

    func installTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) {
        inputNode.installTap(onBus: 0, bufferSize: 256, format: format) { [self] buffer, _ in
            append(buffer)
        }
    }
}

enum HoldingVoiceInputAppearance: Equatable {
    case highlightedField
    case waveformOnly
}

private struct HoldingVoiceInputModifier: ViewModifier {
    @StateObject private var recorder = HoldingVoiceRecorder()
    @Binding var text: String
    let isFocused: Bool
    let numeric: Bool
    let language: AppLanguage
    let appearance: HoldingVoiceInputAppearance

    func body(content: Content) -> some View {
        content
            .opacity(isVoiceActive && appearance == .waveformOnly ? 0 : 1)
            .overlay {
                if isVoiceActive {
                    voiceOverlay
                }
            }
            .accessibilityHint(
                language == .english
                    ? "Hold Fn to speak; release to fill this field."
                    : "按住 Fn 说话，松开后填入当前字段。"
            )
            .onChange(of: isFocused, initial: true) { _, focused in
                if focused {
                    recorder.focus(numeric: numeric, english: language == .english) { text = $0 }
                } else { recorder.blur() }
            }
            .onDisappear { recorder.blur() }
            .onChange(of: text) { _, _ in
                recorder.cancel()
            }
            .alert(language == .english ? "Voice Input" : "语音输入", isPresented: Binding(
                get: { recorder.errorMessage != nil },
                set: { if !$0 { recorder.errorMessage = nil } }
            )) {
                Button(language == .english ? "OK" : "好") { recorder.errorMessage = nil }
            } message: { Text(recorder.errorMessage ?? "") }
    }

    private var isVoiceActive: Bool {
        recorder.isRecording || recorder.isFinishing
    }

    @ViewBuilder
    private var voiceOverlay: some View {
        switch appearance {
        case .highlightedField:
            RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                .fill(PortfolixTheme.raised)
                .overlay {
                    RoundedRectangle(cornerRadius: PortfolixRadius.compact, style: .continuous)
                        .strokeBorder(PortfolixTheme.brandFocus.opacity(0.42), lineWidth: 0.75)
                }
                .overlay { waveform }
                .allowsHitTesting(false)
        case .waveformOnly:
            waveform
                .allowsHitTesting(false)
        }
    }

    private var waveform: some View {
        HoldingVoiceWaveform(
            buffer: recorder.waveformBuffer,
            isTranscribing: recorder.isTranscribing
        )
        .padding(.horizontal, PortfolixSpacing.sm)
        .padding(.vertical, 2)
    }
}

struct HoldingVoiceWaveform: View {
    let snapshot: HoldingVoiceWaveformSnapshot?
    let buffer: HoldingVoiceWaveformBuffer?
    var isTranscribing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(snapshot: HoldingVoiceWaveformSnapshot, isTranscribing: Bool = false) {
        self.snapshot = snapshot
        self.buffer = nil
        self.isTranscribing = isTranscribing
    }

    init(buffer: HoldingVoiceWaveformBuffer, isTranscribing: Bool = false) {
        self.snapshot = nil
        self.buffer = buffer
        self.isTranscribing = isTranscribing
    }

    private var currentSnapshot: HoldingVoiceWaveformSnapshot {
        buffer?.snapshot ?? snapshot ?? .empty()
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let activeSnapshot = currentSnapshot
            Canvas { context, size in
                drawFluidWave(
                    in: &context,
                    size: size,
                    snapshot: activeSnapshot,
                    time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func drawFluidWave(
        in context: inout GraphicsContext,
        size: CGSize,
        snapshot: HoldingVoiceWaveformSnapshot,
        time: TimeInterval
    ) {
        guard size.width > 4, size.height > 4 else { return }

        let midY = size.height / 2
        let maxHalfHeight = max(2, size.height * 0.42)
        let energy = isTranscribing ? CGFloat(0.08) : snapshot.liveEnergy
        let breathing = CGFloat(0.5 + 0.5 * sin(time * 2.4))
        let baseAmplitude = maxHalfHeight * (isTranscribing
            ? (0.14 + 0.08 * breathing)
            : (0.14 + 0.06 * breathing + energy * 0.74))
        let stepCount = min(140, max(44, Int(size.width / 4)))
        let recentSamples = snapshot.levels.suffix(48)

        // Subtle center baseline tapered smoothly to transparent at both edges.
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: midY))
        baseline.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(
            baseline,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: PortfolixTheme.brandFocus.opacity(0), location: 0),
                    .init(color: PortfolixTheme.brandFocus.opacity(0.18), location: 0.16),
                    .init(color: PortfolixTheme.brandFocus.opacity(0.18), location: 0.84),
                    .init(color: PortfolixTheme.brandFocus.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: midY),
                endPoint: CGPoint(x: size.width, y: midY)
            ),
            style: StrokeStyle(lineWidth: 0.75, lineCap: .round)
        )

        struct WaveLayer {
            let frequency: Double
            let speed: Double
            let phaseOffset: Double
            let amplitudeScale: CGFloat
            let lineWidth: CGFloat
            let fillOpacity: Double
            let strokeOpacity: Double
        }

        let layers: [WaveLayer] = [
            WaveLayer(
                frequency: 2.1,
                speed: -2.1,
                phaseOffset: 0.4,
                amplitudeScale: 0.78,
                lineWidth: 1.1,
                fillOpacity: 0.13,
                strokeOpacity: 0.30
            ),
            WaveLayer(
                frequency: 3.1,
                speed: 3.0,
                phaseOffset: 2.1,
                amplitudeScale: 0.90,
                lineWidth: 1.35,
                fillOpacity: 0.09,
                strokeOpacity: 0.52
            ),
            WaveLayer(
                frequency: 2.5,
                speed: -3.6,
                phaseOffset: 4.0,
                amplitudeScale: 1.0,
                lineWidth: 1.75,
                fillOpacity: 0.0,
                strokeOpacity: 0.90
            ),
        ]

        let speedBoost = isTranscribing ? 0.65 : (1.0 + Double(energy) * 0.95)

        for layer in layers {
            var upperPath = Path()
            var ribbonPath = Path()
            var lowerPoints: [CGPoint] = []
            if layer.fillOpacity > 0 {
                lowerPoints.reserveCapacity(stepCount + 1)
            }

            for index in 0...stepCount {
                let u = Double(index) / Double(stepCount)
                let x = CGFloat(u) * size.width
                // Smooth bell envelope tapers amplitude cleanly to 0 at both edges.
                let envelope = CGFloat(pow(sin(Double.pi * u), 1.55))

                // Blend spatial voice history subtly into the fluid wave when speaking.
                let sampleModulation: CGFloat
                if !isTranscribing, energy > 0.02, !recentSamples.isEmpty {
                    let sampleIndex = min(recentSamples.count - 1, Int(u * Double(recentSamples.count - 1)))
                    let sampleValue = recentSamples[recentSamples.index(recentSamples.startIndex, offsetBy: sampleIndex)]
                    sampleModulation = 0.72 + sampleValue * 0.48
                } else {
                    sampleModulation = 1.0
                }

                let angle = u * Double.pi * 2.0 * layer.frequency + time * layer.speed * speedBoost + layer.phaseOffset
                let secondaryHarmonic = sin(angle * 1.85 - time * 1.6) * (0.18 + Double(energy) * 0.22)
                let waveValue = CGFloat(sin(angle) + secondaryHarmonic) / 1.32
                let displacement = waveValue * baseAmplitude * layer.amplitudeScale * envelope * sampleModulation

                let topPoint = CGPoint(x: x, y: midY - displacement)
                if index == 0 {
                    upperPath.move(to: topPoint)
                    if layer.fillOpacity > 0 {
                        ribbonPath.move(to: topPoint)
                    }
                } else {
                    upperPath.addLine(to: topPoint)
                    if layer.fillOpacity > 0 {
                        ribbonPath.addLine(to: topPoint)
                    }
                }

                if layer.fillOpacity > 0 {
                    lowerPoints.append(CGPoint(x: x, y: midY + displacement * 0.65))
                }
            }

            if layer.fillOpacity > 0, !lowerPoints.isEmpty {
                for point in lowerPoints.reversed() {
                    ribbonPath.addLine(to: point)
                }
                ribbonPath.closeSubpath()

                let fillGradient = Gradient(stops: [
                    .init(color: PortfolixTheme.brandLogoStart.opacity(0), location: 0),
                    .init(color: PortfolixTheme.brandLogoStart.opacity(layer.fillOpacity), location: 0.22),
                    .init(color: PortfolixTheme.brandFocus.opacity(layer.fillOpacity * 1.15), location: 0.50),
                    .init(color: PortfolixTheme.brandSolid.opacity(layer.fillOpacity), location: 0.78),
                    .init(color: PortfolixTheme.brandSolid.opacity(0), location: 1),
                ])
                context.fill(
                    ribbonPath,
                    with: .linearGradient(
                        fillGradient,
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    )
                )
            }

            let strokeGradient = Gradient(stops: [
                .init(color: PortfolixTheme.brandLogoStart.opacity(0), location: 0),
                .init(color: PortfolixTheme.brandLogoStart.opacity(layer.strokeOpacity * 0.85), location: 0.14),
                .init(color: PortfolixTheme.brandFocus.opacity(layer.strokeOpacity), location: 0.50),
                .init(color: PortfolixTheme.brandSolid.opacity(layer.strokeOpacity * 0.88), location: 0.86),
                .init(color: PortfolixTheme.brandSolid.opacity(0), location: 1),
            ])
            context.stroke(
                upperPath,
                with: .linearGradient(
                    strokeGradient,
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: size.width, y: midY)
                ),
                style: StrokeStyle(lineWidth: layer.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

extension View {
    func holdingVoiceInput(
        text: Binding<String>,
        isFocused: Bool,
        numeric: Bool,
        language: AppLanguage,
        appearance: HoldingVoiceInputAppearance
    ) -> some View {
        modifier(HoldingVoiceInputModifier(
            text: text,
            isFocused: isFocused,
            numeric: numeric,
            language: language,
            appearance: appearance
        ))
    }
}
