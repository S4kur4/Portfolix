import Foundation

final class ClaudeCompatibleClient: LLMCompleting, LLMConnectionValidating, LLMModelListing, @unchecked Sendable {
    static let shared = ClaudeCompatibleClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMClientError.missingAPIKey }
        guard let url = messagesURL(baseURL: configuration.baseURL) else { throw LLMClientError.invalidBaseURL }
        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(
            ClaudeMessageRequest(
                model: configuration.model,
                maxTokens: 4096,
                temperature: 0,
                system: systemPrompt,
                messages: [
                    ClaudeMessage(role: "user", content: userPrompt),
                ]
            )
        )

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        let decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw LLMClientError.invalidResponse
        }
        return text
    }

    func validateConnection(configuration: AIProviderConfiguration, apiKey: String) async throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMClientError.missingAPIKey }
        guard let url = messagesURL(baseURL: configuration.baseURL) else { throw LLMClientError.invalidBaseURL }
        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(
            ClaudeMessageRequest(
                model: configuration.model,
                maxTokens: min(configuration.maxOutputTokens, LLMOutputTokenPolicy.connectionValidation),
                temperature: 0,
                system: "Respond briefly.",
                messages: [
                    ClaudeMessage(role: "user", content: "Hi"),
                ]
            )
        )

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        let decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw LLMClientError.invalidResponse
        }
    }

    func listModels(configuration: AIProviderConfiguration, apiKey: String) async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMClientError.missingAPIKey }
        guard let url = modelsURL(baseURL: configuration.baseURL) else { throw LLMClientError.invalidBaseURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        let decoded = try JSONDecoder().decode(ClaudeModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted { modelSortKey($0) > modelSortKey($1) }
    }

    private func messagesURL(baseURL: String) -> URL? {
        endpointURL(baseURL: baseURL, suffix: "messages")
    }

    private func modelsURL(baseURL: String) -> URL? {
        endpointURL(baseURL: baseURL, suffix: "models")
    }

    private func endpointURL(baseURL: String, suffix: String) -> URL? {
        LLMBaseURLValidator.endpointURL(baseURL: baseURL, appendingPath: suffix)
    }

    private static func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            return
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
}

private struct ClaudeMessageRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
    }
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

private struct ClaudeMessageResponse: Decodable {
    let content: [ClaudeContentBlock]
}

private struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
}

private struct ClaudeModelsResponse: Decodable {
    let data: [ClaudeModelItem]
}

private struct ClaudeModelItem: Decodable {
    let id: String
}
