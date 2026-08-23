import Foundation

struct LLMWebCitation: Equatable, Sendable {
    let title: String
    let url: String
}

enum LLMWebSearchProgress: Equatable, Sendable {
    case reasoningStarted
    case reasoningActivity(elapsedSeconds: Int)
    case searching(query: String?)
    case completed
    case outputStarted
}

typealias LLMWebSearchProgressHandler = @Sendable (LLMWebSearchProgress) async -> Void

struct LLMCompletionResult: Equatable, Sendable {
    let content: String
    let webSearchCallCount: Int
    let webSearchQueries: [String]
    let citations: [LLMWebCitation]
    let diagnostics: LLMCompletionDiagnostics

    init(
        content: String,
        webSearchCallCount: Int = 0,
        webSearchQueries: [String] = [],
        citations: [LLMWebCitation] = [],
        diagnostics: LLMCompletionDiagnostics = .empty
    ) {
        self.content = content
        self.webSearchCallCount = webSearchCallCount
        self.webSearchQueries = webSearchQueries
        self.citations = citations
        self.diagnostics = diagnostics
    }
}

struct LLMCompletionDiagnostics: Equatable, Sendable {
    let responseHeaderMilliseconds: Int?
    let firstReasoningMilliseconds: Int?
    let firstSearchMilliseconds: Int?
    let firstOutputMilliseconds: Int?
    let totalMilliseconds: Int?
    let reasoningCharacterCount: Int

    static let empty = LLMCompletionDiagnostics(
        responseHeaderMilliseconds: nil,
        firstReasoningMilliseconds: nil,
        firstSearchMilliseconds: nil,
        firstOutputMilliseconds: nil,
        totalMilliseconds: nil,
        reasoningCharacterCount: 0
    )
}

final class DeepSeekResponsesClient: LLMCompleting, LLMConnectionValidating, LLMModelListing, @unchecked Sendable {
    static let shared = DeepSeekResponsesClient()

    private let session: URLSession
    private let maximumResponseBytes = 8 * 1024 * 1024

    init(session: URLSession = .shared) {
        self.session = session
    }

    func completeJSON(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        try await completeJSONResult(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: configuration,
            apiKey: apiKey,
            webSearchEnabled: false,
            webSearchProgress: nil
        ).content
    }

    func completeJSONResult(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIProviderConfiguration,
        apiKey: String,
        webSearchEnabled: Bool,
        webSearchProgress: LLMWebSearchProgressHandler?
    ) async throws -> LLMCompletionResult {
        let request = try makeRequest(
            configuration: configuration,
            apiKey: apiKey,
            instructions: systemPrompt,
            input: userPrompt,
            expectsJSON: true,
            webSearchEnabled: webSearchEnabled,
            stream: true
        )

        let requestStartedAt = Date()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            let responseHeaderAt = Date()
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMClientError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                let body = await responseBodyText(from: bytes)
                throw Self.httpError(statusCode: httpResponse.statusCode, body: body)
            }
            return try await parseStreamingResponse(
                bytes,
                requestStartedAt: requestStartedAt,
                responseHeaderAt: responseHeaderAt,
                progress: webSearchProgress
            )
        } catch let error as LLMClientError {
            throw error
        } catch {
            throw LLMClientError.requestFailed(error.localizedDescription)
        }
    }

    func validateConnection(configuration: AIProviderConfiguration, apiKey: String) async throws {
        let probeConfiguration = configuration.withMaxOutputTokens(LLMOutputTokenPolicy.connectionValidation)
        let request = try makeRequest(
            configuration: probeConfiguration,
            apiKey: apiKey,
            instructions: "Reply with OK.",
            input: "Hi",
            expectsJSON: false,
            webSearchEnabled: false,
            stream: false
        )
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMClientError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw Self.httpError(
                    statusCode: httpResponse.statusCode,
                    body: String(data: data, encoding: .utf8)
                )
            }
            let result = try Self.parseResponseObject(data)
            guard !result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMClientError.invalidResponse
            }
        } catch let error as LLMClientError {
            throw error
        } catch {
            throw LLMClientError.requestFailed(error.localizedDescription)
        }
    }

    func listModels(configuration _: AIProviderConfiguration, apiKey _: String) async throws -> [String] {
        LLMProviderOption.deepSeekModels
    }

    private func makeRequest(
        configuration: AIProviderConfiguration,
        apiKey: String,
        instructions: String,
        input: String,
        expectsJSON: Bool,
        webSearchEnabled: Bool,
        stream: Bool
    ) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMClientError.missingAPIKey }
        guard let url = Self.responsesURL(baseURL: configuration.baseURL) else {
            throw LLMClientError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekResponseRequest(
                model: configuration.model,
                instructions: instructions,
                input: input,
                stream: stream,
                temperature: 0,
                maxOutputTokens: configuration.maxOutputTokens,
                tools: webSearchEnabled ? [DeepSeekResponseTool(type: "web_search")] : nil,
                toolChoice: webSearchEnabled ? "auto" : nil,
                text: expectsJSON ? DeepSeekResponseText(format: DeepSeekResponseTextFormat(type: "json_object")) : nil
            )
        )
        return request
    }

    private func parseStreamingResponse(
        _ bytes: URLSession.AsyncBytes,
        requestStartedAt: Date,
        responseHeaderAt: Date,
        progress: LLMWebSearchProgressHandler?
    ) async throws -> LLMCompletionResult {
        var content = ""
        var citations: [LLMWebCitation] = []
        var seenCitationURLs = Set<String>()
        var searchCallIDs = Set<String>()
        var searchQueries: [String] = []
        var seenSearchQueries = Set<String>()
        var anonymousSearchCallCount = 0
        var currentEvent: String?
        var receivedByteCount = 0
        var completionObject: [String: Any]?
        var reasoningCharacterCount = 0
        var firstReasoningAt: Date?
        var firstSearchAt: Date?
        var firstOutputAt: Date?
        var lastReasoningActivityAt: Date?
        let reasoningActivityInterval: TimeInterval = 4

        for try await line in bytes.lines {
            receivedByteCount += line.utf8.count + 1
            guard receivedByteCount <= maximumResponseBytes else {
                throw LLMClientError.invalidResponse
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("event:") {
                currentEvent = String(trimmed.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any] else { continue }

            let eventType = (dictionary["type"] as? String) ?? currentEvent ?? ""
            switch eventType {
            case "response.output_text.delta":
                if firstOutputAt == nil {
                    firstOutputAt = Date()
                    await progress?(.outputStarted)
                }
                content += dictionary["delta"] as? String ?? ""
            case "response.web_search_call.in_progress", "response.web_search_call.searching":
                if firstSearchAt == nil {
                    firstSearchAt = Date()
                }
                let callID = Self.firstString(in: dictionary, keys: ["id", "call_id", "item_id"])
                if let callID {
                    searchCallIDs.insert(callID)
                } else if eventType.hasSuffix("searching") {
                    anonymousSearchCallCount += 1
                }
                let eventQueries = Self.searchQueries(in: dictionary)
                for query in eventQueries where seenSearchQueries.insert(query).inserted {
                    searchQueries.append(query)
                }
                await progress?(.searching(query: eventQueries.first))
            case "response.web_search_call.completed":
                await progress?(.completed)
            case "response.completed":
                completionObject = dictionary["response"] as? [String: Any]
            case "response.incomplete":
                throw LLMClientError.truncatedFinalContent(
                    finishReason: Self.incompleteReason(in: dictionary)
                )
            case "response.failed", "error":
                throw LLMClientError.requestFailed(
                    Self.firstString(in: dictionary, keys: ["message", "code"]) ?? "DeepSeek Responses API returned an error"
                )
            case let type where Self.isReasoningDeltaEvent(type):
                let now = Date()
                reasoningCharacterCount += (dictionary["delta"] as? String ?? "").count
                if firstReasoningAt == nil {
                    firstReasoningAt = now
                    lastReasoningActivityAt = now
                    await progress?(.reasoningStarted)
                } else if let lastActivityAt = lastReasoningActivityAt,
                          now.timeIntervalSince(lastActivityAt) >= reasoningActivityInterval {
                    let elapsed = max(1, Int(now.timeIntervalSince(firstReasoningAt ?? now)))
                    await progress?(.reasoningActivity(elapsedSeconds: elapsed))
                    lastReasoningActivityAt = now
                }
            default:
                break
            }

            for citation in Self.citations(in: dictionary) where seenCitationURLs.insert(citation.url).inserted {
                citations.append(citation)
            }
        }

        if let completionObject {
            let completedData = try JSONSerialization.data(withJSONObject: completionObject)
            let completed = try Self.parseResponseObject(completedData)
            if content.isEmpty { content = completed.content }
            for citation in completed.citations where seenCitationURLs.insert(citation.url).inserted {
                citations.append(citation)
            }
            for query in completed.webSearchQueries where seenSearchQueries.insert(query).inserted {
                searchQueries.append(query)
            }
            if searchCallIDs.isEmpty, anonymousSearchCallCount == 0 {
                anonymousSearchCallCount = completed.webSearchCallCount
            }
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMClientError.emptyFinalContent(reasoningCharacters: reasoningCharacterCount, finishReason: nil)
        }
        let completedAt = Date()
        return LLMCompletionResult(
            content: content,
            webSearchCallCount: max(searchCallIDs.count, anonymousSearchCallCount),
            webSearchQueries: searchQueries,
            citations: citations,
            diagnostics: LLMCompletionDiagnostics(
                responseHeaderMilliseconds: Self.milliseconds(from: requestStartedAt, to: responseHeaderAt),
                firstReasoningMilliseconds: firstReasoningAt.map { Self.milliseconds(from: requestStartedAt, to: $0) },
                firstSearchMilliseconds: firstSearchAt.map { Self.milliseconds(from: requestStartedAt, to: $0) },
                firstOutputMilliseconds: firstOutputAt.map { Self.milliseconds(from: requestStartedAt, to: $0) },
                totalMilliseconds: Self.milliseconds(from: requestStartedAt, to: completedAt),
                reasoningCharacterCount: reasoningCharacterCount
            )
        )
    }

    static func parseResponseObject(_ data: Data) throws -> LLMCompletionResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMClientError.invalidResponse
        }
        if let error = object["error"] as? [String: Any] {
            throw LLMClientError.requestFailed(error["message"] as? String ?? "DeepSeek Responses API returned an error")
        }
        let texts = allDictionaries(in: object).compactMap { dictionary -> String? in
            guard dictionary["type"] as? String == "output_text" else { return nil }
            return dictionary["text"] as? String
        }
        let searchCalls = allDictionaries(in: object).filter {
            ($0["type"] as? String) == "web_search_call"
        }.count
        var seenCitationURLs = Set<String>()
        let uniqueCitations = citations(in: object).filter {
            seenCitationURLs.insert($0.url).inserted
        }
        var seenQueries = Set<String>()
        let uniqueQueries = allDictionaries(in: object)
            .filter { $0["type"] as? String == "web_search_call" }
            .flatMap(searchQueries)
            .filter { seenQueries.insert($0).inserted }
        return LLMCompletionResult(
            content: texts.joined(),
            webSearchCallCount: searchCalls,
            webSearchQueries: uniqueQueries,
            citations: uniqueCitations
        )
    }

    private static func responsesURL(baseURL: String) -> URL? {
        guard var components = try? LLMBaseURLValidator.validatedComponents(from: baseURL) else {
            return nil
        }
        var segments = components.path.split(separator: "/").map(String.init)
        if segments.last?.lowercased() == "responses" { segments.removeLast() }
        if segments.last?.lowercased() == "v1" { segments.removeLast() }
        segments.append("responses")
        components.path = "/" + segments.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func httpError(statusCode: Int, body: String?) -> LLMClientError {
        switch statusCode {
        case 400, 422:
            .badRequest(OpenAICompatibleClient.providerErrorMessage(from: body) ?? "HTTP \(statusCode)")
        case 401, 403:
            .unauthorized
        case 404:
            .endpointOrModelNotFound
        case 429:
            .rateLimited
        default:
            .serverError(statusCode)
        }
    }

    private func responseBodyText(from bytes: URLSession.AsyncBytes, maximumBytes: Int = 64 * 1024) async -> String? {
        var lines: [String] = []
        var count = 0
        do {
            for try await line in bytes.lines {
                count += line.utf8.count + 1
                guard count <= maximumBytes else { break }
                lines.append(line)
            }
        } catch {
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func citations(in object: Any) -> [LLMWebCitation] {
        allDictionaries(in: object).compactMap { dictionary in
            guard dictionary["type"] as? String == "url_citation",
                  let url = dictionary["url"] as? String,
                  URL(string: url)?.scheme?.lowercased() == "https" else { return nil }
            let title = (dictionary["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return LLMWebCitation(title: title?.isEmpty == false ? title! : url, url: url)
        }
    }

    private static func allDictionaries(in object: Any) -> [[String: Any]] {
        if let dictionary = object as? [String: Any] {
            return [dictionary] + dictionary.values.flatMap(allDictionaries)
        }
        if let array = object as? [Any] {
            return array.flatMap(allDictionaries)
        }
        return []
    }

    private static func firstString(in object: Any, keys: Set<String>) -> String? {
        for dictionary in allDictionaries(in: object) {
            for key in keys {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func searchQueries(in object: Any) -> [String] {
        allDictionaries(in: object).flatMap { dictionary -> [String] in
            var values: [String] = []
            if let query = dictionary["query"] as? String {
                values.append(query)
            }
            if let queries = dictionary["queries"] as? [String] {
                values.append(contentsOf: queries)
            }
            return values.compactMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      !trimmed.lowercased().hasPrefix("ws_call_id=") else { return nil }
                return trimmed
            }
        }
    }

    private static func incompleteReason(in object: Any) -> String? {
        for dictionary in allDictionaries(in: object) {
            if let details = dictionary["incomplete_details"] as? [String: Any],
               let reason = details["reason"] as? String,
               !reason.isEmpty {
                return reason
            }
        }
        return firstString(in: object, keys: ["reason"])
    }

    static func isReasoningDeltaEvent(_ eventType: String) -> Bool {
        eventType.hasSuffix(".delta")
            && (eventType.contains("reasoning") || eventType.contains("reasoning_text"))
    }

    private static func milliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) * 1_000))
    }
}

private struct DeepSeekResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let stream: Bool
    let temperature: Double
    let maxOutputTokens: Int
    let tools: [DeepSeekResponseTool]?
    let toolChoice: String?
    let text: DeepSeekResponseText?

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, stream, temperature, tools, text
        case maxOutputTokens = "max_output_tokens"
        case toolChoice = "tool_choice"
    }
}

private struct DeepSeekResponseTool: Encodable {
    let type: String
}

private struct DeepSeekResponseText: Encodable {
    let format: DeepSeekResponseTextFormat
}

private struct DeepSeekResponseTextFormat: Encodable {
    let type: String
}
