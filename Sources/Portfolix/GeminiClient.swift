import Foundation

final class GeminiClient: LLMCompleting, LLMModelListing, @unchecked Sendable {
    static let shared = GeminiClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func completeJSON(systemPrompt: String, userPrompt: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMClientError.missingAPIKey }
        guard let url = generateURL(baseURL: configuration.baseURL, model: configuration.model, apiKey: trimmedKey) else {
            throw LLMClientError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GeminiGenerateRequest(
                systemInstruction: GeminiContent(parts: [GeminiPart(text: systemPrompt)]),
                contents: [
                    GeminiContent(parts: [GeminiPart(text: userPrompt)]),
                ],
                generationConfig: GeminiGenerationConfig(
                    temperature: 0,
                    responseMimeType: "application/json"
                )
            )
        )

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text, !text.isEmpty else {
            throw LLMClientError.invalidResponse
        }
        return text
    }

    func listModels(configuration: AIProviderConfiguration, apiKey: String) async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMClientError.missingAPIKey }
        guard let url = modelsURL(baseURL: configuration.baseURL, apiKey: trimmedKey) else {
            throw LLMClientError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        return decoded.models
            .filter { ($0.supportedGenerationMethods ?? []).contains("generateContent") }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .sorted { modelSortKey($0) > modelSortKey($1) }
    }

    private func generateURL(baseURL: String, model: String, apiKey: String) -> URL? {
        let modelPath = model.hasPrefix("models/") ? model : "models/\(model)"
        return endpointURL(baseURL: baseURL, path: "\(modelPath):generateContent", apiKey: apiKey)
    }

    private func modelsURL(baseURL: String, apiKey: String) -> URL? {
        endpointURL(baseURL: baseURL, path: "models", apiKey: apiKey)
    }

    private func endpointURL(baseURL: String, path: String, apiKey: String) -> URL? {
        LLMBaseURLValidator.endpointURL(
            baseURL: baseURL,
            appendingPath: path,
            queryItems: [URLQueryItem(name: "key", value: apiKey)]
        )
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
        case 500...599:
            throw LLMClientError.serverError(httpResponse.statusCode)
        default:
            throw LLMClientError.serverError(httpResponse.statusCode)
        }
    }
}

private struct GeminiGenerateRequest: Encodable {
    let systemInstruction: GeminiContent
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double
    let responseMimeType: String
}

private struct GeminiGenerateResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent
}

private struct GeminiModelsResponse: Decodable {
    let models: [GeminiModelItem]
}

private struct GeminiModelItem: Decodable {
    let name: String
    let supportedGenerationMethods: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case supportedGenerationMethods = "supportedGenerationMethods"
    }
}
