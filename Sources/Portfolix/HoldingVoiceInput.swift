import SwiftUI
import AppKit
@preconcurrency import AVFoundation
@preconcurrency import Speech
import OSLog
import PortfolixCore

@MainActor
private final class HoldingVoiceRecorder: ObservableObject {
    private static let logger = Logger(subsystem: "app.portfolix.mac", category: "HoldingVoiceInput")
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishing = false
    @Published private(set) var levels = Array(repeating: CGFloat.zero, count: 36)
    @Published var errorMessage: String?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
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

    func focus(numeric: Bool, english: Bool, commit: @escaping (String) -> Void) {
        self.numeric = numeric
        self.english = english
        self.commit = commit
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.keyCode == 63, NSApp.isActive else { return }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.function) { self.press() } else { self.release() }
            }
            return event
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
        levels = Array(repeating: 0, count: levels.count)
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
            isFinishing = false
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
            isRecording = false
            isFinishing = true
            timeout?.cancel()
            modernSession.finish()
            scheduleFinalizationTimeout(id: session)
            return
        }
        guard isRecording else { cancel(); return }
        stopAudio()
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
        let previous = levels.last ?? 0
        let target = CGFloat(level)
        let response: CGFloat = target > previous ? 0.72 : 0.38
        let value = previous + (target - previous) * response
        levels.removeFirst()
        levels.append(value)
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
        isRecording = false
        isFinishing = false
        levels = Array(repeating: 0, count: levels.count)
        transcript = ""
    }

    private func fail(_ chinese: String, _ english: String) {
        cancel()
        errorMessage = self.english ? english : chinese
    }
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
            .help(language == .english ? "Hold Fn to speak; release to fill this field." : "按住 Fn 说话，松开后填入当前字段。")
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
            RoundedRectangle(cornerRadius: PortfolixRadius.compact)
                .fill(PortfolixTheme.panelElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: PortfolixRadius.compact)
                        .fill(PortfolixTheme.violet.opacity(0.14))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: PortfolixRadius.compact)
                        .stroke(PortfolixTheme.violet, lineWidth: 1)
                }
                .overlay { waveform }
                .allowsHitTesting(false)
        case .waveformOnly:
            waveform
                .allowsHitTesting(false)
        }
    }

    private var waveform: some View {
        HoldingVoiceWaveform(levels: recorder.levels, isFinishing: recorder.isFinishing)
            .padding(.horizontal, PortfolixSpacing.sm)
            .padding(.vertical, PortfolixSpacing.xs)
    }
}

private struct HoldingVoiceWaveform: View {
    let levels: [CGFloat]
    let isFinishing: Bool

    var body: some View {
        Canvas { context, size in
            guard !levels.isEmpty, size.width > 0, size.height > 0 else { return }
            let step = size.width / CGFloat(levels.count)
            let width = max(1, min(3, step * 0.52))
            for (index, level) in levels.enumerated() {
                let normalized = max(0.08, min(1, level))
                let height = max(2, normalized * size.height * 0.82)
                let rect = CGRect(
                    x: CGFloat(index) * step + (step - width) / 2,
                    y: (size.height - height) / 2,
                    width: width,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: width / 2),
                    with: .color(PortfolixTheme.violet.opacity(isFinishing ? 0.45 : 0.9))
                )
            }
        }
        .animation(.linear(duration: 1 / 60), value: levels)
        .accessibilityHidden(true)
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
