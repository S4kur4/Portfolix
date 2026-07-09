import Foundation

enum ProviderCredentialKind: String, CaseIterable {
    case llm = "llm"
    case tavily = "tavily"
    case bocha = "bocha"

    var databaseKey: String {
        switch self {
        case .llm: "provider_credential_llm_api_key"
        case .tavily: "provider_credential_tavily_api_key"
        case .bocha: "provider_credential_bocha_api_key"
        }
    }

    var validationStateDatabaseKey: String {
        switch self {
        case .llm: "provider_credential_llm_validation_state"
        case .tavily: "provider_credential_tavily_validation_state"
        case .bocha: "provider_credential_bocha_validation_state"
        }
    }
}

enum ProviderCredentialValidationState: String, Equatable {
    case unknown
    case valid
    case invalid
}

enum ProviderCredentialError: LocalizedError, Equatable {
    case invalidValue
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidValue:
            "API Key 内容无效"
        case .unavailable:
            "本地数据库不可用，无法保存 API Key"
        }
    }
}

protocol ProviderCredentialStoring: Sendable {
    func read(kind: ProviderCredentialKind) throws -> String?
    func save(_ value: String, kind: ProviderCredentialKind) throws
    func delete(kind: ProviderCredentialKind) throws
    func readValidationState(kind: ProviderCredentialKind) throws -> ProviderCredentialValidationState
    func saveValidationState(_ state: ProviderCredentialValidationState, kind: ProviderCredentialKind) throws
}

final class ProviderCredentialStore: ProviderCredentialStoring, @unchecked Sendable {
    static let shared = ProviderCredentialStore()

    private var values: [ProviderCredentialKind: String] = [:]
    private var validationStates: [ProviderCredentialKind: ProviderCredentialValidationState] = [:]
    private let lock = NSLock()

    func read(kind: ProviderCredentialKind) throws -> String? {
        lock.withLock {
            values[kind]
        }
    }

    func save(_ value: String, kind: ProviderCredentialKind) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderCredentialError.invalidValue
        }
        lock.withLock {
            values[kind] = trimmed
        }
    }

    func delete(kind: ProviderCredentialKind) throws {
        lock.withLock {
            values.removeValue(forKey: kind)
            validationStates.removeValue(forKey: kind)
        }
    }

    func readValidationState(kind: ProviderCredentialKind) throws -> ProviderCredentialValidationState {
        lock.withLock {
            validationStates[kind] ?? .unknown
        }
    }

    func saveValidationState(_ state: ProviderCredentialValidationState, kind: ProviderCredentialKind) throws {
        lock.withLock {
            validationStates[kind] = state
        }
    }
}

final class DatabaseProviderCredentialStore: ProviderCredentialStoring, @unchecked Sendable {
    private let repository: PositionRepository

    init(repository: PositionRepository) {
        self.repository = repository
    }

    func read(kind: ProviderCredentialKind) throws -> String? {
        try repository.appSetting(for: kind.databaseKey)
    }

    func save(_ value: String, kind: ProviderCredentialKind) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderCredentialError.invalidValue
        }
        try repository.setAppSetting(key: kind.databaseKey, value: trimmed)
    }

    func delete(kind: ProviderCredentialKind) throws {
        try repository.deleteAppSetting(key: kind.databaseKey)
        try repository.deleteAppSetting(key: kind.validationStateDatabaseKey)
    }

    func readValidationState(kind: ProviderCredentialKind) throws -> ProviderCredentialValidationState {
        guard let rawValue = try repository.appSetting(for: kind.validationStateDatabaseKey) else {
            return .unknown
        }
        return ProviderCredentialValidationState(rawValue: rawValue) ?? .unknown
    }

    func saveValidationState(_ state: ProviderCredentialValidationState, kind: ProviderCredentialKind) throws {
        try repository.setAppSetting(key: kind.validationStateDatabaseKey, value: state.rawValue)
    }
}

enum LLMProviderOption: String, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case deepSeek = "DeepSeek"
    case anthropic = "Anthropic"
    case googleGemini = "Google Gemini"
    case moonshot = "Moonshot"
    case openAICompatible = "OpenAI compatible"
    case claudeCompatible = "Claude compatible"

    var id: String { rawValue }

    var defaultBaseURL: String {
        switch self {
        case .openAI:
            "https://api.openai.com/v1"
        case .deepSeek:
            "https://api.deepseek.com/v1"
        case .anthropic:
            "https://api.anthropic.com/v1"
        case .googleGemini:
            "https://generativelanguage.googleapis.com/v1beta"
        case .moonshot:
            "https://api.moonshot.cn/v1"
        case .openAICompatible, .claudeCompatible:
            ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:
            "gpt-4.1-mini"
        case .deepSeek:
            "deepseek-chat"
        case .anthropic, .claudeCompatible:
            "claude-3-5-sonnet-latest"
        case .googleGemini:
            "gemini-2.5-flash"
        case .moonshot:
            "moonshot-v1-8k"
        case .openAICompatible:
            ""
        }
    }

    var canAutoFillBaseURL: Bool {
        self != .openAICompatible && self != .claudeCompatible
    }

    var requiresCustomModelEntry: Bool {
        self == .openAICompatible || self == .claudeCompatible
    }

    var usesClaudeMessagesAPI: Bool {
        self == .anthropic || self == .claudeCompatible
    }

    var usesGeminiAPI: Bool {
        self == .googleGemini
    }

    static func from(_ value: String) -> LLMProviderOption {
        if value == "OpenAI-compatible" {
            return .openAICompatible
        }
        return LLMProviderOption(rawValue: value) ?? .openAICompatible
    }
}

struct AIProviderConfiguration: Equatable {
    var provider: String
    var baseURL: String
    var model: String
    var isEnabled: Bool
    var requestTimeout: TimeInterval = LLMRequestTimeoutPolicy.standard
    var maxOutputTokens: Int = LLMOutputTokenPolicy.standard

    var providerOption: LLMProviderOption {
        LLMProviderOption.from(provider)
    }

    func withRequestTimeout(_ timeout: TimeInterval) -> AIProviderConfiguration {
        var copy = self
        copy.requestTimeout = max(1, timeout)
        return copy
    }

    func withMaxOutputTokens(_ limit: Int) -> AIProviderConfiguration {
        var copy = self
        copy.maxOutputTokens = max(1, limit)
        return copy
    }

    static let `default` = AIProviderConfiguration(
        provider: LLMProviderOption.openAI.rawValue,
        baseURL: LLMProviderOption.openAI.defaultBaseURL,
        model: LLMProviderOption.openAI.defaultModel,
        isEnabled: true
    )
}

enum LLMRequestTimeoutPolicy {
    static let standard: TimeInterval = 90
    static let validationProbe: TimeInterval = 30
    static let reportGeneration: TimeInterval = 300
}

enum LLMOutputTokenPolicy {
    static let connectionValidation = 16
    static let validationProbe = 64
    static let standard = 2_400
    static let followUp = 6_400
    static let reportGeneration = 10_000
}

enum SearchProviderOption: String, CaseIterable, Identifiable, Codable {
    case tavily = "Tavily"
    case bocha = "BochaAI"

    var id: String { rawValue }

    var credentialKind: ProviderCredentialKind {
        switch self {
        case .tavily: .tavily
        case .bocha: .bocha
        }
    }
}

enum SearchQuality: String, CaseIterable, Identifiable, Codable {
    case basic
    case advanced

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.basic, .chinese): "标准"
        case (.advanced, .chinese): "深度"
        case (.basic, .english): "Standard"
        case (.advanced, .english): "Deep"
        }
    }
}

enum SearchExecutionPolicy {
    // Result volume is an Agent execution detail, not a user preference.
    static let requestedResultCount = 8
    static let acceptedSourceCount = 6
}

struct SearchConfiguration: Equatable {
    var isEnabled: Bool
    var provider: SearchProviderOption
    var quality: SearchQuality

    static let `default` = SearchConfiguration(
        isEnabled: false,
        provider: .tavily,
        quality: .basic
    )

    init(isEnabled: Bool, provider: SearchProviderOption, quality: SearchQuality) {
        self.isEnabled = isEnabled
        self.provider = provider
        self.quality = quality
    }

    // Compatibility for persisted diagnostics and older tests. Result count is now policy-owned.
    init(isEnabled: Bool, searchDepth: SearchQuality, maxResults _: Int) {
        self.init(isEnabled: isEnabled, provider: .tavily, quality: searchDepth)
    }

    var searchDepth: SearchQuality {
        get { quality }
        set { quality = newValue }
    }

    var maxResults: Int { SearchExecutionPolicy.requestedResultCount }
}

typealias TavilyConfiguration = SearchConfiguration
typealias TavilySearchDepth = SearchQuality

enum SmartAnalysisMode: String, CaseIterable, Identifiable {
    case basic
    case connected

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.basic, .chinese): "基础模式"
        case (.connected, .chinese): "联网增强"
        case (.basic, .english): "Basic"
        case (.connected, .english): "Connected"
        }
    }
}

enum AIProviderConfigurationStore {
    private static let llmProviderKey = "portfolix.ai.llm.provider"
    private static let llmBaseURLKey = "portfolix.ai.llm.baseURL"
    private static let llmModelKey = "portfolix.ai.llm.model"
    private static let llmCachedModelsPrefix = "portfolix.ai.llm.cachedModels"
    private static let llmEnabledKey = "portfolix.ai.enabled"
    private static let tavilyEnabledKey = "portfolix.ai.tavily.enabled"
    private static let tavilyDepthKey = "portfolix.ai.tavily.searchDepth"
    private static let searchEnabledKey = "portfolix.ai.search.enabled"
    private static let searchProviderKey = "portfolix.ai.search.provider"
    private static let searchQualityKey = "portfolix.ai.search.quality"

    static func loadLLM() -> AIProviderConfiguration {
        let defaults = UserDefaults.standard
        let fallback = AIProviderConfiguration.default
        let rawProvider = defaults.string(forKey: llmProviderKey) ?? fallback.provider
        let provider = LLMProviderOption.from(rawProvider)
        return AIProviderConfiguration(
            provider: provider.rawValue,
            baseURL: defaults.string(forKey: llmBaseURLKey) ?? fallback.baseURL,
            model: defaults.string(forKey: llmModelKey) ?? fallback.model,
            isEnabled: defaults.object(forKey: llmEnabledKey) == nil ? fallback.isEnabled : defaults.bool(forKey: llmEnabledKey)
        )
    }

    static func saveLLM(_ configuration: AIProviderConfiguration) {
        let defaults = UserDefaults.standard
        defaults.set(configuration.providerOption.rawValue, forKey: llmProviderKey)
        defaults.set(configuration.baseURL, forKey: llmBaseURLKey)
        defaults.set(configuration.model, forKey: llmModelKey)
        defaults.set(configuration.isEnabled, forKey: llmEnabledKey)
    }

    static func loadCachedModels(provider: LLMProviderOption) -> [String] {
        UserDefaults.standard.stringArray(forKey: cachedModelsKey(provider: provider)) ?? []
    }

    static func saveCachedModels(_ models: [String], provider: LLMProviderOption) {
        let cleaned = models.reduce(into: [String]()) { result, model in
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }
        UserDefaults.standard.set(cleaned, forKey: cachedModelsKey(provider: provider))
    }

    private static func cachedModelsKey(provider: LLMProviderOption) -> String {
        "\(llmCachedModelsPrefix).\(provider.rawValue)"
    }

    static func loadSearch(defaults: UserDefaults = .standard) -> SearchConfiguration {
        let fallback = SearchConfiguration.default
        let isEnabled = defaults.object(forKey: searchEnabledKey) == nil
            ? (defaults.object(forKey: tavilyEnabledKey) == nil ? fallback.isEnabled : defaults.bool(forKey: tavilyEnabledKey))
            : defaults.bool(forKey: searchEnabledKey)
        let provider = defaults.string(forKey: searchProviderKey)
            .flatMap(SearchProviderOption.init(rawValue:)) ?? fallback.provider
        let quality = defaults.string(forKey: searchQualityKey)
            .flatMap(SearchQuality.init(rawValue:))
            ?? defaults.string(forKey: tavilyDepthKey).flatMap(SearchQuality.init(rawValue:))
            ?? fallback.quality
        return SearchConfiguration(
            isEnabled: isEnabled,
            provider: provider,
            quality: quality
        )
    }

    static func saveSearch(_ configuration: SearchConfiguration, defaults: UserDefaults = .standard) {
        defaults.set(configuration.isEnabled, forKey: searchEnabledKey)
        defaults.set(configuration.provider.rawValue, forKey: searchProviderKey)
        defaults.set(configuration.quality.rawValue, forKey: searchQualityKey)
    }

    static func loadTavily() -> TavilyConfiguration { loadSearch() }
    static func saveTavily(_ configuration: TavilyConfiguration) { saveSearch(configuration) }
}
