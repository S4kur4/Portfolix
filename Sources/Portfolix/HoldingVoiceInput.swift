import SwiftUI
import AppKit
@preconcurrency import AVFoundation
@preconcurrency import Speech
import PortfolixCore

@MainActor
private final class HoldingVoiceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishing = false
    @Published private(set) var level: CGFloat = 0
    @Published var errorMessage: String?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var timeout: Task<Void, Never>?
    private var session: UUID?
    private var held = false
    private var hasTap = false
    private var receivedFinal = false
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
            let consumed = MainActor.assumeIsolated {
                guard let self, event.keyCode == 63, NSApp.isActive else { return false }
                if event.modifierFlags.contains(.function) { self.press() } else { self.release() }
                return true
            }
            return consumed ? nil : event
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
        let id = UUID()
        session = id
        let locale = Locale(identifier: english ? "en-US" : "zh-CN")
        Task { [weak self] in
            guard let self else { return }
            let speechAuthorized = await Self.requestSpeechAuthorization()
            guard self.session == id, self.held else { return }
            guard speechAuthorized else {
                self.fail("请在系统设置中允许 Portfolix 使用语音识别。", "Allow Speech Recognition for Portfolix in System Settings.")
                return
            }
            let audioAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
            guard self.session == id, self.held else { return }
            guard audioAuthorized else {
                self.fail("请在系统设置中允许 Portfolix 使用麦克风。", "Allow Microphone access for Portfolix in System Settings.")
                return
            }
            self.start(id: id, locale: locale)
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func start(id: UUID, locale: Locale) {
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
        transcript = ""
        receivedFinal = false
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("没有可用的麦克风。", "No microphone is available.")
            return
        }
        let sink = VoiceAudioSink(request: request) { [weak self] value in
            Task { @MainActor in
                guard let self, self.session == id, self.isRecording else { return }
                self.level = CGFloat(value)
            }
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in sink.append(buffer) }
        hasTap = true
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.session == id else { return }
                if let text { self.transcript = text }
                if isFinal { self.receivedFinal = true; self.stopAudio(); self.complete() }
                else if failed, !self.receivedFinal { self.fail("语音识别未完成，请重试。原内容已保留。", "Speech recognition failed. Your original value is unchanged.") }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, self?.session == id else { return }
                self?.release()
            }
        } catch {
            fail("无法启动麦克风，请检查输入设备后重试。", "Cannot start the microphone. Check your input device and retry.")
        }
    }

    func release() {
        guard held else { return }
        held = false
        guard isRecording else { cancel(); return }
        if receivedFinal { complete(); return }
        stopAudio()
        isRecording = false
        isFinishing = true
        request?.endAudio()
        timeout?.cancel()
        let id = session
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.session == id else { return }
            self?.fail("语音识别超时，请重试。原内容已保留。", "Speech recognition timed out. Your original value is unchanged.")
        }
    }

    private func complete() {
        // Final results can arrive before release; never replace text while Fn is held.
        guard !held else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            fail("没有识别到内容，请重试。", "No speech was recognized. Please retry.")
            return
        }
        let value = numeric ? SpokenNumber.normalize(text) : text
        guard let value else {
            fail("未识别到明确的数字，请逐位读出数字和小数点。原内容已保留。", "No unambiguous number was recognized. Say the digits and decimal point. Your original value is unchanged.")
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
        held = false
        timeout?.cancel()
        timeout = nil
        stopAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
        recognizer = nil
        isRecording = false
        isFinishing = false
        level = 0
    }

    private func fail(_ chinese: String, _ english: String) {
        cancel()
        errorMessage = self.english ? english : chinese
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
        guard frames >= Int(buffer.format.sampleRate / 15), let channel = buffer.floatChannelData?[0] else { return }
        frames = 0
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[index])) }
        update(min(1, peak * 8))
    }
}

private struct HoldingVoiceInputModifier: ViewModifier {
    @StateObject private var recorder = HoldingVoiceRecorder()
    @Binding var text: String
    let isFocused: Bool
    let numeric: Bool
    let language: AppLanguage

    func body(content: Content) -> some View {
        content
            .overlay {
                if recorder.isRecording || recorder.isFinishing {
                    RoundedRectangle(cornerRadius: PortfolixRadius.compact)
                        .fill(PortfolixTheme.violet.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: PortfolixRadius.compact)
                                .stroke(PortfolixTheme.violet, lineWidth: 1)
                        }
                        .overlay(alignment: .leading) {
                            HStack(spacing: 2) {
                                ForEach(0..<5) { index in
                                    Capsule().fill(PortfolixTheme.violet)
                                        .frame(width: 2, height: 3 + recorder.level * CGFloat([8, 16, 22, 14, 7][index]))
                                }
                            }
                            .frame(width: 26, height: 26)
                            .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: 4))
                            .padding(.leading, 4)
                            .animation(.linear(duration: 0.08), value: recorder.level)
                        }
                        .allowsHitTesting(false)
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
}

extension View {
    func holdingVoiceInput(text: Binding<String>, isFocused: Bool, numeric: Bool, language: AppLanguage) -> some View {
        modifier(HoldingVoiceInputModifier(text: text, isFocused: isFocused, numeric: numeric, language: language))
    }
}
