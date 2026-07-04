import Foundation

enum LLMClientError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidBaseURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case endpointOrModelNotFound
    case badRequest(String)
    case serverError(Int)
    case unsupportedJSONMode(String?)
    case emptyFinalContent(reasoningCharacters: Int, finishReason: String?)
    case truncatedFinalContent(finishReason: String?)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "尚未配置 LLM API Key"
        case .invalidBaseURL:
            return "LLM API Base URL 无效"
        case .invalidResponse:
            return "LLM 返回数据无法解析"
        case .unauthorized:
            return "LLM API Key 无效或已失效"
        case .rateLimited:
            return "LLM 请求已达到频率或额度限制"
        case .endpointOrModelNotFound:
            return "LLM Endpoint 或模型不存在（404），请检查 Base URL 和模型名称"
        case let .badRequest(message):
            return "LLM 请求参数被服务拒绝：\(message)"
        case let .serverError(status):
            return "LLM 服务暂时不可用（\(status)）"
        case let .unsupportedJSONMode(message):
            if let message, !message.isEmpty {
                return "LLM 模型不支持 JSON mode：\(message)"
            }
            return "LLM 模型不支持 JSON mode"
        case let .emptyFinalContent(reasoningCharacters, finishReason):
            let reason = finishReason.map { "，结束原因：\($0)" } ?? ""
            if reasoningCharacters > 0 {
                return "LLM 仅返回了推理过程，未返回最终内容\(reason)"
            }
            return "LLM 未返回最终内容\(reason)"
        case let .truncatedFinalContent(finishReason):
            let reason = finishReason.map { "，结束原因：\($0)" } ?? ""
            return "LLM 返回内容被截断\(reason)"
        case let .requestFailed(message):
            return "LLM 请求失败：\(message)"
        }
    }
}

protocol LLMCompleting: Sendable {
    func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String
}

protocol LLMConnectionValidating: Sendable {
    func validateConnection(configuration: AIProviderConfiguration, apiKey: String) async throws
}

protocol LLMModelListing: Sendable {
    func listModels(configuration: AIProviderConfiguration, apiKey: String) async throws -> [String]
}

final class LLMProviderClient: LLMCompleting, LLMConnectionValidating, LLMModelListing, @unchecked Sendable {
    static let shared = LLMProviderClient()

    func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String {
        let provider = configuration.providerOption
        if provider.usesClaudeMessagesAPI {
            return try await ClaudeCompatibleClient.shared.completeJSON(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                configuration: configuration,
                apiKey: apiKey
            )
        }
        if provider.usesGeminiAPI {
            return try await GeminiClient.shared.completeJSON(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                configuration: configuration,
                apiKey: apiKey
            )
        }
        return try await OpenAICompatibleClient.shared.completeJSON(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: configuration,
            apiKey: apiKey
        )
    }

    func validateConnection(configuration: AIProviderConfiguration, apiKey: String) async throws {
        let provider = configuration.providerOption
        if provider.usesClaudeMessagesAPI {
            try await ClaudeCompatibleClient.shared.validateConnection(configuration: configuration, apiKey: apiKey)
            return
        }
        if provider.usesGeminiAPI {
            try await GeminiClient.shared.validateConnection(configuration: configuration, apiKey: apiKey)
            return
        }
        try await OpenAICompatibleClient.shared.validateConnection(configuration: configuration, apiKey: apiKey)
    }

    func listModels(configuration: AIProviderConfiguration, apiKey: String) async throws -> [String] {
        let provider = configuration.providerOption
        if provider.usesClaudeMessagesAPI {
            return try await ClaudeCompatibleClient.shared.listModels(configuration: configuration, apiKey: apiKey)
        }
        if provider.usesGeminiAPI {
            return try await GeminiClient.shared.listModels(configuration: configuration, apiKey: apiKey)
        }
        return try await OpenAICompatibleClient.shared.listModels(configuration: configuration, apiKey: apiKey)
    }
}

final class OpenAICompatibleClient: LLMCompleting, LLMConnectionValidating, @unchecked Sendable {
    static let shared = OpenAICompatibleClient()

    private let session: URLSession
    private let maximumResponseBytes = 8 * 1024 * 1024

    init(session: URLSession = .shared) {
        self.session = session
    }

    func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String {
        do {
            return try await completeJSON(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                configuration: configuration,
                apiKey: apiKey,
                usesJSONMode: true
            )
        } catch LLMClientError.unsupportedJSONMode {
            return try await completeJSON(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                configuration: configuration,
                apiKey: apiKey,
                usesJSONMode: false
            )
        }
    }

    private func completeJSON(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIProviderConfiguration,
        apiKey: String,
        usesJSONMode: Bool
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }
        guard let url = Self.chatCompletionsURL(baseURL: configuration.baseURL) else {
            throw LLMClientError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatRequest(
                model: configuration.model,
                messages: [
                    OpenAIChatMessage(role: "system", content: systemPrompt),
                    OpenAIChatMessage(role: "user", content: userPrompt),
                ],
                temperature: 0,
                maxTokens: configuration.maxOutputTokens,
                responseFormat: usesJSONMode ? OpenAIResponseFormat(type: "json_object") : nil,
                stream: true
            )
        )

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMClientError.invalidResponse
            }
            switch httpResponse.statusCode {
            case 200:
                var lines: [String] = []
                var receivedByteCount = 0
                for try await line in bytes.lines {
                    receivedByteCount += line.utf8.count + 1
                    guard receivedByteCount <= maximumResponseBytes else {
                        throw LLMClientError.invalidResponse
                    }
                    lines.append(line)
                }
                return try Self.content(fromResponseLines: lines)
            case 400:
                let body = await Self.responseBodyText(from: bytes)
                let message = Self.providerErrorMessage(from: body)
                if usesJSONMode, Self.isJSONModeUnsupported(message: message, body: body) {
                    throw LLMClientError.unsupportedJSONMode(message)
                }
                throw LLMClientError.badRequest(message ?? "HTTP 400")
            case 401, 403:
                throw LLMClientError.unauthorized
            case 429:
                throw LLMClientError.rateLimited
            case 404:
                throw LLMClientError.endpointOrModelNotFound
            case 500...599:
                throw LLMClientError.serverError(httpResponse.statusCode)
            default:
                throw LLMClientError.serverError(httpResponse.statusCode)
            }
        } catch let error as LLMClientError {
            throw error
        } catch {
            throw LLMClientError.requestFailed(error.localizedDescription)
        }
    }

    func validateConnection(configuration: AIProviderConfiguration, apiKey: String) async throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }
        guard let url = Self.chatCompletionsURL(baseURL: configuration.baseURL) else {
            throw LLMClientError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatValidationRequest(
                model: configuration.model,
                messages: [
                    OpenAIChatMessage(role: "user", content: "Hi"),
                ],
                temperature: 0,
                maxTokens: min(configuration.maxOutputTokens, LLMOutputTokenPolicy.connectionValidation),
                stream: false
            )
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMClientError.invalidResponse
            }
            switch httpResponse.statusCode {
            case 200:
                try Self.validateSuccessfulProbeResponse(data)
            case 400:
                let body = String(data: data, encoding: .utf8)
                throw LLMClientError.badRequest(Self.providerErrorMessage(from: body) ?? "HTTP 400")
            case 401, 403:
                throw LLMClientError.unauthorized
            case 429:
                throw LLMClientError.rateLimited
            case 404:
                throw LLMClientError.endpointOrModelNotFound
            case 500...599:
                throw LLMClientError.serverError(httpResponse.statusCode)
            default:
                throw LLMClientError.serverError(httpResponse.statusCode)
            }
        } catch let error as LLMClientError {
            throw error
        } catch {
            throw LLMClientError.requestFailed(error.localizedDescription)
        }
    }

    static func validateSuccessfulProbeResponse(_ data: Data) throws {
        if let text = String(data: data, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("data:") {
            try validateSuccessfulProbeSSE(text)
            return
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            !containsProviderError(object)
        else {
            throw LLMClientError.invalidResponse
        }
    }

    private static func validateSuccessfulProbeSSE(_ text: String) throws {
        var sawValidPayload = false
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let data = payload.data(using: .utf8) else { continue }
            guard
                let object = try? JSONSerialization.jsonObject(with: data),
                !containsProviderError(object)
            else {
                throw LLMClientError.invalidResponse
            }
            sawValidPayload = true
        }
        guard sawValidPayload else {
            throw LLMClientError.invalidResponse
        }
    }

    private static func containsProviderError(_ object: Any) -> Bool {
        if let dictionary = object as? [String: Any] {
            return dictionary["error"] != nil
        }
        return false
    }

    private static func responseBodyText(from bytes: URLSession.AsyncBytes, maximumBytes: Int = 64 * 1024) async -> String? {
        var lines: [String] = []
        var receivedByteCount = 0
        do {
            for try await line in bytes.lines {
                receivedByteCount += line.utf8.count + 1
                guard receivedByteCount <= maximumBytes else { break }
                lines.append(line)
            }
        } catch {
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func providerErrorMessage(from body: String?) -> String? {
        guard
            let body,
            let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        if let dictionary = object as? [String: Any] {
            if let message = dictionary["message"] as? String {
                return message
            }
            if let error = dictionary["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let error = dictionary["error"] as? String {
                return error
            }
        }
        return nil
    }

    static func isJSONModeUnsupported(message: String?, body: String?) -> Bool {
        let haystack = [message, body]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        guard !haystack.isEmpty else { return false }
        return haystack.contains("json mode")
            || haystack.contains("response_format")
            || haystack.contains("json_object")
    }

    static func chatCompletionsURL(baseURL: String) -> URL? {
        openAIEndpointURL(baseURL: baseURL, endpointPath: "chat/completions")
    }

    static func content(fromResponseLines lines: [String]) throws -> String {
        var streamedContent = ""
        var sawStreamingData = false
        var reasoningCharacterCount = 0
        var finishReason: String?
        var regularResponseLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.hasPrefix("data:") else {
                if !trimmed.hasPrefix("event:") && !trimmed.hasPrefix(":") {
                    regularResponseLines.append(line)
                }
                continue
            }

            sawStreamingData = true
            let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                break
            }
            guard
                let data = payload.data(using: .utf8),
                let chunk = try? JSONDecoder().decode(OpenAIStreamResponse.self, from: data)
            else {
                continue
            }
            for choice in chunk.choices {
                if let content = choice.delta.content {
                    streamedContent += content
                }
                if let reasoningContent = choice.delta.reasoningContent {
                    reasoningCharacterCount += reasoningContent.count
                }
                if let choiceFinishReason = choice.finishReason {
                    finishReason = choiceFinishReason
                }
            }
        }

        if sawStreamingData {
            if Self.isTruncatedFinishReason(finishReason) {
                throw LLMClientError.truncatedFinalContent(finishReason: finishReason)
            }
            guard !streamedContent.isEmpty else {
                throw LLMClientError.emptyFinalContent(
                    reasoningCharacters: reasoningCharacterCount,
                    finishReason: finishReason
                )
            }
            return streamedContent
        }

        let data = regularResponseLines.joined(separator: "\n").data(using: .utf8)
        guard let data, let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data) else {
            throw LLMClientError.invalidResponse
        }
        if Self.isTruncatedFinishReason(decoded.choices.first?.finishReason) {
            throw LLMClientError.truncatedFinalContent(finishReason: decoded.choices.first?.finishReason)
        }
        guard let message = decoded.choices.first?.message,
              let content = message.content,
              !content.isEmpty else {
            throw LLMClientError.emptyFinalContent(
                reasoningCharacters: decoded.choices.first?.message.reasoningContent?.count ?? 0,
                finishReason: decoded.choices.first?.finishReason
            )
        }
        return content
    }

    private static func isTruncatedFinishReason(_ finishReason: String?) -> Bool {
        guard let finishReason else { return false }
        let normalized = finishReason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "length" || normalized == "max_tokens"
    }
}

extension OpenAICompatibleClient: LLMModelListing {
    func listModels(configuration: AIProviderConfiguration, apiKey: String) async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }
        guard let url = Self.modelsURL(baseURL: configuration.baseURL) else {
            throw LLMClientError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            return decoded.data.map(\.id).sorted { lhs, rhs in
                modelSortKey(lhs) > modelSortKey(rhs)
            }
        case 401, 403:
            throw LLMClientError.unauthorized
        case 429:
            throw LLMClientError.rateLimited
        case 404:
            throw LLMClientError.endpointOrModelNotFound
        case 500...599:
            throw LLMClientError.serverError(httpResponse.statusCode)
        default:
            throw LLMClientError.serverError(httpResponse.statusCode)
        }
    }

    static func modelsURL(baseURL: String) -> URL? {
        openAIEndpointURL(baseURL: baseURL, endpointPath: "models")
    }

    private static func openAIEndpointURL(baseURL: String, endpointPath: String) -> URL? {
        guard var components = try? LLMBaseURLValidator.validatedComponents(from: baseURL) else {
            return nil
        }
        var segments = components.path.split(separator: "/").map(String.init)
        if segments.last?.lowercased() == "models" {
            segments.removeLast()
        } else if segments.count >= 2,
                  segments[segments.count - 2].lowercased() == "chat",
                  segments.last?.lowercased() == "completions" {
            segments.removeLast(2)
        }
        segments.append(contentsOf: endpointPath.split(separator: "/").map(String.init))
        components.path = "/" + segments.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double
    let maxTokens: Int
    let responseFormat: OpenAIResponseFormat?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
        case stream
    }
}

private struct OpenAIChatValidationRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct OpenAIChatMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAIResponseFormat: Encodable {
    let type: String
}

private struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIResponseMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct OpenAIResponseMessage: Decodable {
    let content: String?
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
    }
}

private struct OpenAIStreamResponse: Decodable {
    let choices: [OpenAIStreamChoice]
}

private struct OpenAIStreamChoice: Decodable {
    let delta: OpenAIStreamDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

private struct OpenAIStreamDelta: Decodable {
    let content: String?
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
    }
}

private struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModelItem]
}

private struct OpenAIModelItem: Decodable {
    let id: String
}

func modelSortKey(_ model: String) -> String {
    model
        .replacingOccurrences(of: "latest", with: "zzzz")
        .replacingOccurrences(of: "-", with: "")
        .lowercased()
}
