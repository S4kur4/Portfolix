import Foundation
import OSLog

enum AIAgentRuntimeDiagnostics {
    private static let debugLogURL = URL(fileURLWithPath: "/private/tmp/portfolix-agent-runtime.log")
    private static let debugLogLock = NSLock()
    private static let logger = Logger(
        subsystem: "app.portfolix.mac",
        category: "AgentRuntime"
    )

    static func event(
        _ name: String,
        runID: UUID,
        metadata: [String: String] = [:]
    ) {
#if DEBUG
        let fields = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let thread = Thread.isMainThread ? "main" : "background"
        let message = "run=\(runID.uuidString) event=\(name) thread=\(thread) \(fields)"
        logger.notice(
            "run=\(runID.uuidString, privacy: .public) event=\(name, privacy: .public) thread=\(thread, privacy: .public) \(fields, privacy: .public)"
        )
        appendDebugLog(message)
#endif
    }

#if DEBUG
    private static func appendDebugLog(_ message: String) {
        debugLogLock.lock()
        defer { debugLogLock.unlock() }

        let timestamp = ISO8601DateFormatter().string(from: .now)
        guard let data = "\(timestamp) \(message)\n".data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: debugLogURL.path) {
            FileManager.default.createFile(atPath: debugLogURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: debugLogURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.synchronize()
    }
#endif

    static func startMainThreadWatchdog(runID: UUID) -> Task<Void, Never>? {
#if DEBUG
        Task.detached(priority: .background) {
            var heartbeat = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                heartbeat += 1
                let scheduledAt = Date()
                let heartbeatSnapshot = heartbeat
                if heartbeat.isMultiple(of: 2) {
                    event(
                        "watchdog_background_alive",
                        runID: runID,
                        metadata: ["heartbeat": String(heartbeatSnapshot)]
                    )
                }
                DispatchQueue.main.async {
                    let latencyMilliseconds = Int(Date().timeIntervalSince(scheduledAt) * 1_000)
                    if latencyMilliseconds >= 150 {
                        event(
                            "main_thread_delay",
                            runID: runID,
                            metadata: ["latency_ms": String(latencyMilliseconds)]
                        )
                    } else if heartbeatSnapshot.isMultiple(of: 2) {
                        event(
                            "watchdog_main_responsive",
                            runID: runID,
                            metadata: ["latency_ms": String(latencyMilliseconds)]
                        )
                    }
                }
            }
        }
#else
        nil
#endif
    }

    static func stageID(for progress: AIFollowUpProgress) -> String {
        switch progress {
        case .analyzing: "analyzing"
        case let .replanning(turn, total): "replanning_\(turn)_of_\(total)"
        case let .searching(_, ordinal, total): "searching_\(ordinal)_of_\(total)"
        case let .evaluatingEvidence(turn, total): "evaluating_evidence_\(turn)_of_\(total)"
        case .composing: "composing"
        }
    }
}
