import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

@MainActor
protocol HoldingSpeechSession: AnyObject {
    func finish()
    func cancel()
}

@available(macOS 26.0, *)
@MainActor
final class HoldingSpeechAnalyzerSession: HoldingSpeechSession {
    private let engine: AVAudioEngine
    private let analyzer: SpeechAnalyzer
    private let transcriber: DictationTranscriber
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var hasTap = false
    private var finalizedTranscript = ""
    private var volatileTranscript = ""
    private var didStop = false
    private let onLevel: @MainActor @Sendable (Float) -> Void
    private let onTranscript: @MainActor @Sendable (String) -> Void
    private let onComplete: @MainActor @Sendable (String) -> Void
    private let onFailure: @MainActor @Sendable (any Error) -> Void

    private init(
        engine: AVAudioEngine,
        analyzer: SpeechAnalyzer,
        transcriber: DictationTranscriber,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        onLevel: @escaping @MainActor @Sendable (Float) -> Void,
        onTranscript: @escaping @MainActor @Sendable (String) -> Void,
        onComplete: @escaping @MainActor @Sendable (String) -> Void,
        onFailure: @escaping @MainActor @Sendable (any Error) -> Void
    ) {
        self.engine = engine
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.inputContinuation = inputContinuation
        self.onLevel = onLevel
        self.onTranscript = onTranscript
        self.onComplete = onComplete
        self.onFailure = onFailure
    }

    static func start(
        locale: Locale,
        onLevel: @escaping @MainActor @Sendable (Float) -> Void,
        onTranscript: @escaping @MainActor @Sendable (String) -> Void,
        onComplete: @escaping @MainActor @Sendable (String) -> Void,
        onFailure: @escaping @MainActor @Sendable (any Error) -> Void
    ) async throws -> HoldingSpeechAnalyzerSession {
        let selectedLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let transcriber = DictationTranscriber(locale: selectedLocale, preset: .progressiveShortDictation)
        try await ensureAssets(for: transcriber)

        let engine = AVAudioEngine()
        let naturalFormat = engine.inputNode.outputFormat(forBus: 0)
        guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
            throw HoldingSpeechAnalyzerError.noMicrophone
        }
        let modules: [any SpeechModule] = [transcriber]
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: naturalFormat
        ) else {
            throw HoldingSpeechAnalyzerError.unsupportedAudioFormat
        }

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let session = HoldingSpeechAnalyzerSession(
            engine: engine,
            analyzer: analyzer,
            transcriber: transcriber,
            inputContinuation: continuation,
            onLevel: onLevel,
            onTranscript: onTranscript,
            onComplete: onComplete,
            onFailure: onFailure
        )
        session.startResultTask()
        do {
            try await analyzer.start(inputSequence: inputSequence)
            try session.startAudio(naturalFormat: naturalFormat, analyzerFormat: analyzerFormat)
            return session
        } catch {
            session.cancel()
            throw error
        }
    }

    private static func ensureAssets(for transcriber: DictationTranscriber) async throws {
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)
        guard status != .unsupported else { throw HoldingSpeechAnalyzerError.unsupportedLocale }
        guard status != .installed else { return }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
            throw HoldingSpeechAnalyzerError.assetsUnavailable
        }
        try await request.downloadAndInstall()
        guard await AssetInventory.status(forModules: modules) == .installed else {
            throw HoldingSpeechAnalyzerError.assetsUnavailable
        }
    }

    private func startResultTask() {
        resultTask = Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    guard let self, !self.didStop else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalizedTranscript += text
                        self.volatileTranscript = ""
                    } else {
                        self.volatileTranscript = text
                    }
                    self.onTranscript(self.currentTranscript)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, !self.didStop else { return }
                self.fail(error)
            }
        }
    }

    private func startAudio(naturalFormat: AVAudioFormat, analyzerFormat: AVAudioFormat) throws {
        let sink = try AnalyzerAudioSink(
            inputFormat: naturalFormat,
            outputFormat: analyzerFormat,
            continuation: inputContinuation,
            onLevel: onLevel
        )
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: naturalFormat) { buffer, _ in
            sink.append(buffer)
        }
        hasTap = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopAudio()
            throw error
        }
    }

    func finish() {
        guard !didStop, finishTask == nil else { return }
        stopAudio()
        inputContinuation?.finish()
        inputContinuation = nil
        finishTask = Task { [weak self, analyzer] in
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                guard let self, !self.didStop else { return }
                if let resultTask = self.resultTask { await resultTask.value }
                guard !self.didStop else { return }
                self.didStop = true
                self.onComplete(self.currentTranscript)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !self.didStop else { return }
                self.fail(error)
            }
        }
    }

    func cancel() {
        guard !didStop else { return }
        didStop = true
        stopAudio()
        inputContinuation?.finish()
        inputContinuation = nil
        resultTask?.cancel()
        resultTask = nil
        finishTask?.cancel()
        finishTask = nil
        Task { [analyzer] in await analyzer.cancelAndFinishNow() }
    }

    private var currentTranscript: String {
        finalizedTranscript + volatileTranscript
    }

    private func fail(_ error: any Error) {
        didStop = true
        stopAudio()
        inputContinuation?.finish()
        inputContinuation = nil
        resultTask?.cancel()
        resultTask = nil
        finishTask?.cancel()
        finishTask = nil
        Task { [analyzer] in await analyzer.cancelAndFinishNow() }
        onFailure(error)
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        if hasTap { engine.inputNode.removeTap(onBus: 0) }
        hasTap = false
    }
}

@available(macOS 26.0, *)
enum HoldingSpeechAnalyzerError: Error {
    case unsupportedLocale
    case assetsUnavailable
    case noMicrophone
    case unsupportedAudioFormat
}

@available(macOS 26.0, *)
private final class AnalyzerAudioSink: @unchecked Sendable {
    private final class InputSupplyState: @unchecked Sendable {
        var supplied = false
    }

    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let continuation: AsyncStream<AnalyzerInput>.Continuation?
    private let onLevel: @MainActor @Sendable (Float) -> Void
    private var framesSinceLevelUpdate = 0

    init(
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation?,
        onLevel: @escaping @MainActor @Sendable (Float) -> Void
    ) throws {
        self.outputFormat = outputFormat
        self.continuation = continuation
        self.onLevel = onLevel
        if inputFormat == outputFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw HoldingSpeechAnalyzerError.unsupportedAudioFormat
            }
            self.converter = converter
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        updateLevel(from: buffer)
        guard let converter else {
            continuation?.yield(AnalyzerInput(buffer: buffer))
            return
        }

        let ratio = outputFormat.sampleRate / max(buffer.format.sampleRate, 1)
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        let supplyState = InputSupplyState()
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            guard !supplyState.supplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplyState.supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, status != .error, converted.frameLength > 0 else { return }
        continuation?.yield(AnalyzerInput(buffer: converted))
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        framesSinceLevelUpdate += Int(buffer.frameLength)
        guard framesSinceLevelUpdate >= Int(buffer.format.sampleRate / 20),
              let channel = buffer.floatChannelData?[0] else { return }
        framesSinceLevelUpdate = 0
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[index])) }
        let level = min(1, peak * 8)
        Task { @MainActor [onLevel] in onLevel(level) }
    }
}
