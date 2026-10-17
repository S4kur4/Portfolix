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

enum ProviderCredentialFormPersistence {
    enum Result: Equatable {
        case unchanged
        case saved
        case deleted
    }

    static func apply(
        value: String,
        initialValue: String,
        kind: ProviderCredentialKind,
        store: ProviderCredentialStoring
    ) throws -> Result {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInitialValue = initialValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            guard !trimmedInitialValue.isEmpty else { return .unchanged }
            try store.delete(kind: kind)
            return .deleted
        }
        guard trimmedValue != trimmedInitialValue else { return .unchanged }
        try store.save(trimmedValue, kind: kind)
        return .saved
    }
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
            "https://api.deepseek.com"
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
            "deepseek-flash"
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

    static let deepSeekModels = [
        "deepseek-flash",
        "deepseek-v4-pro",
    ]

    private static let deepSeekModelAliases = [
        "deepseek-v4-flash": "deepseek-flash",
        "deepseek-v4-flash-vision-exp": "deepseek-flash",
    ]

    static func canonicalDeepSeekModel(_ model: String) -> String {
        deepSeekModelAliases[model] ?? model
    }

    static func supportsBuiltInWebSearch(model: String) -> Bool {
        _ = model
        return false
    }

    static func preferredConnectedModel(in models: [String]) -> String? {
        sanitizedDeepSeekModels(models).first(where: supportsBuiltInWebSearch)
    }

    static func sanitizedDeepSeekModels(_ models: [String]) -> [String] {
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        return models.reduce(into: [String]()) { result, model in
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonical = canonicalDeepSeekModel(trimmed)
            guard canonical.hasPrefix("deepseek-"),
                  canonical.utf8.count <= 128,
                  canonical.unicodeScalars.allSatisfy(allowedCharacters.contains),
                  !result.contains(canonical) else {
                return
            }
            result.append(canonical)
        }
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
        provider: LLMProviderOption.deepSeek.rawValue,
        baseURL: LLMProviderOption.deepSeek.defaultBaseURL,
        model: LLMProviderOption.deepSeek.defaultModel,
        isEnabled: true
    )
}

enum LLMRequestTimeoutPolicy {
    static let standard = AIAgentExecutionBudget.production.planningSeconds
    static let validationProbe: TimeInterval = 30
    static let reportGeneration = AIAgentExecutionBudget.production.reportSeconds
    static let reportRepair = AIAgentExecutionBudget.production.repairSeconds
    static let followUp = AIAgentExecutionBudget.production.followUpSeconds
}

enum LLMOutputTokenPolicy {
    // DeepSeek V4 Pro emits reasoning tokens before the final probe text, even
    // for a minimal request. Keep enough room for both so a valid key is not rejected.
    static let connectionValidation = 512
    static let validationProbe = 64
    static let standard = 4_000
    static let followUp = 10_000
    static let reportGeneration = 16_000
}

enum SearchProviderOption: String, CaseIterable, Identifiable, Codable {
    case parallel = "Parallel"
    case deepseek = "DeepSeek"
    case tavily = "Tavily"
    case bocha = "BochaAI"

    var id: String { rawValue }

    var credentialKind: ProviderCredentialKind? {
        switch self {
        case .parallel: nil
        case .deepseek: .llm
        case .tavily: .tavily
        case .bocha: .bocha
        }
    }

    var requiresAPIKey: Bool { credentialKind != nil }
    static let independentlyConfiguredProviders: [SearchProviderOption] = [.tavily, .bocha]

    func usableAPIKey(from store: ProviderCredentialStoring) throws -> String? {
        guard let credentialKind else { return "" }
        guard let key = try store.read(kind: credentialKind), !key.isEmpty else { return nil }
        let state = try store.readValidationState(kind: credentialKind)
        return state == .invalid ? nil : key
    }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.parallel, _): "Parallel Search"
        case (.deepseek, _): "DeepSeek Search"
        case (.tavily, _): "Tavily"
        case (.bocha, .chinese): "博查"
        case (.bocha, .english): "Bocha"
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
    var enabledProviders: Set<SearchProviderOption>
    var preferredProvider: SearchProviderOption
    var quality: SearchQuality

    static let `default` = SearchConfiguration(
        isEnabled: false,
        enabledProviders: [.parallel],
        preferredProvider: .parallel,
        quality: .basic
    )

    init(isEnabled: Bool, provider: SearchProviderOption, quality: SearchQuality) {
        self.isEnabled = isEnabled
        enabledProviders = isEnabled ? [provider] : []
        preferredProvider = provider
        self.quality = quality
    }

    init(
        isEnabled: Bool,
        enabledProviders: Set<SearchProviderOption>,
        preferredProvider: SearchProviderOption = .tavily,
        quality: SearchQuality
    ) {
        self.isEnabled = isEnabled
        self.enabledProviders = enabledProviders
        self.preferredProvider = enabledProviders.contains(preferredProvider)
            ? preferredProvider
            : enabledProviders.sorted(by: Self.providerOrder).first ?? preferredProvider
        self.quality = quality
    }

    var provider: SearchProviderOption {
        get { preferredProvider }
        set {
            preferredProvider = newValue
            enabledProviders.insert(newValue)
        }
    }

    var orderedEnabledProviders: [SearchProviderOption] {
        enabledProviders.sorted(by: Self.providerOrder)
    }

    func isProviderEnabled(_ provider: SearchProviderOption) -> Bool {
        enabledProviders.contains(provider)
    }

    mutating func setProvider(_ provider: SearchProviderOption, enabled: Bool) {
        if enabled {
            enabledProviders.insert(provider)
            if enabledProviders.count == 1 {
                preferredProvider = provider
            }
        } else {
            enabledProviders.remove(provider)
            if preferredProvider == provider,
               let next = orderedEnabledProviders.first {
                preferredProvider = next
            }
            if enabledProviders.isEmpty {
                isEnabled = false
            }
        }
    }

    func selecting(_ provider: SearchProviderOption) -> SearchConfiguration {
        var copy = self
        copy.preferredProvider = provider
        return copy
    }

    private static func providerOrder(_ lhs: SearchProviderOption, _ rhs: SearchProviderOption) -> Bool {
        SearchProviderOption.allCases.firstIndex(of: lhs) ?? 0
            < SearchProviderOption.allCases.firstIndex(of: rhs) ?? 0
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

    static var availableCases: [SmartAnalysisMode] { allCases }

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
    private static let bochaEnabledKey = "portfolix.ai.bocha.enabled"
    private static let parallelEnabledKey = "portfolix.ai.parallel.enabled"
    private static let deepseekSearchEnabledKey = "portfolix.ai.deepseekSearch.enabled"

    static func loadLLM(defaults: UserDefaults = .standard) -> AIProviderConfiguration {
        let fallback = AIProviderConfiguration.default
        let savedModel = defaults.string(forKey: llmModelKey)
        let availableModels = availableDeepSeekModels(defaults: defaults)
        let model = availableModels.contains(savedModel ?? "")
            ? (savedModel ?? fallback.model)
            : preferredDeepSeekModel(in: availableModels)
        return AIProviderConfiguration(
            provider: LLMProviderOption.deepSeek.rawValue,
            baseURL: LLMProviderOption.deepSeek.defaultBaseURL,
            model: model,
            isEnabled: defaults.object(forKey: llmEnabledKey) == nil ? fallback.isEnabled : defaults.bool(forKey: llmEnabledKey)
        )
    }

    static func saveLLM(_ configuration: AIProviderConfiguration, defaults: UserDefaults = .standard) {
        let availableModels = availableDeepSeekModels(defaults: defaults)
        let model = availableModels.contains(configuration.model)
            ? configuration.model
            : preferredDeepSeekModel(in: availableModels)
        defaults.set(LLMProviderOption.deepSeek.rawValue, forKey: llmProviderKey)
        defaults.set(LLMProviderOption.deepSeek.defaultBaseURL, forKey: llmBaseURLKey)
        defaults.set(model, forKey: llmModelKey)
        defaults.set(configuration.isEnabled, forKey: llmEnabledKey)
    }

    static func loadCachedModels(
        provider: LLMProviderOption,
        defaults: UserDefaults = .standard
    ) -> [String] {
        let models = defaults.stringArray(forKey: cachedModelsKey(provider: provider)) ?? []
        return provider == .deepSeek
            ? LLMProviderOption.sanitizedDeepSeekModels(models)
            : models
    }

    static func saveCachedModels(
        _ models: [String],
        provider: LLMProviderOption,
        defaults: UserDefaults = .standard
    ) {
        let cleaned = provider == .deepSeek
            ? LLMProviderOption.sanitizedDeepSeekModels(models)
            : models.reduce(into: [String]()) { result, model in
                let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
                result.append(trimmed)
            }
        defaults.set(cleaned, forKey: cachedModelsKey(provider: provider))
    }

    static func availableDeepSeekModels(defaults: UserDefaults = .standard) -> [String] {
        let cachedModels = loadCachedModels(provider: .deepSeek, defaults: defaults)
        return cachedModels.isEmpty ? LLMProviderOption.deepSeekModels : cachedModels
    }

    static func preferredDeepSeekModel(
        current: String? = nil,
        in models: [String]
    ) -> String {
        let availableModels = LLMProviderOption.sanitizedDeepSeekModels(models)
        if let current, availableModels.contains(current) {
            return current
        }
        if availableModels.contains(LLMProviderOption.deepSeek.defaultModel) {
            return LLMProviderOption.deepSeek.defaultModel
        }
        return availableModels.first ?? LLMProviderOption.deepSeek.defaultModel
    }

    private static func cachedModelsKey(provider: LLMProviderOption) -> String {
        "\(llmCachedModelsPrefix).\(provider.rawValue)"
    }

    static func loadSearch(defaults: UserDefaults = .standard) -> SearchConfiguration {
        let fallback = SearchConfiguration.default
        let legacySearchEnabled = defaults.object(forKey: searchEnabledKey) == nil
            ? nil
            : defaults.bool(forKey: searchEnabledKey)
        let provider = defaults.string(forKey: searchProviderKey)
            .flatMap(SearchProviderOption.init(rawValue:)) ?? fallback.provider
        var enabledProviders = Set<SearchProviderOption>()
        let hasPersistedProviderSelection = defaults.object(forKey: parallelEnabledKey) != nil
            || defaults.object(forKey: deepseekSearchEnabledKey) != nil
            || defaults.object(forKey: tavilyEnabledKey) != nil
            || defaults.object(forKey: bochaEnabledKey) != nil
        if defaults.object(forKey: parallelEnabledKey) != nil,
           defaults.bool(forKey: parallelEnabledKey) {
            enabledProviders.insert(.parallel)
        }
        if defaults.bool(forKey: deepseekSearchEnabledKey) {
            enabledProviders.insert(.deepseek)
        }
        if defaults.object(forKey: tavilyEnabledKey) != nil,
           defaults.bool(forKey: tavilyEnabledKey) {
            enabledProviders.insert(.tavily)
        }
        if defaults.object(forKey: bochaEnabledKey) != nil,
           defaults.bool(forKey: bochaEnabledKey) {
            enabledProviders.insert(.bocha)
        }
        if enabledProviders.isEmpty, legacySearchEnabled == true {
            enabledProviders.insert(provider)
        }
        if !hasPersistedProviderSelection, legacySearchEnabled == nil {
            enabledProviders = fallback.enabledProviders
        }
        let quality = defaults.string(forKey: searchQualityKey)
            .flatMap(SearchQuality.init(rawValue:))
            ?? defaults.string(forKey: tavilyDepthKey).flatMap(SearchQuality.init(rawValue:))
            ?? fallback.quality
        let isEnabled = legacySearchEnabled
            ?? (hasPersistedProviderSelection ? !enabledProviders.isEmpty : fallback.isEnabled)
        return SearchConfiguration(
            isEnabled: isEnabled,
            enabledProviders: enabledProviders,
            preferredProvider: provider,
            quality: quality
        )
    }

    static func saveSearch(_ configuration: SearchConfiguration, defaults: UserDefaults = .standard) {
        defaults.set(configuration.isEnabled, forKey: searchEnabledKey)
        defaults.set(configuration.provider.rawValue, forKey: searchProviderKey)
        defaults.set(configuration.quality.rawValue, forKey: searchQualityKey)
        defaults.set(configuration.isProviderEnabled(.parallel), forKey: parallelEnabledKey)
        defaults.set(configuration.isProviderEnabled(.deepseek), forKey: deepseekSearchEnabledKey)
        defaults.set(configuration.isProviderEnabled(.tavily), forKey: tavilyEnabledKey)
        defaults.set(configuration.isProviderEnabled(.bocha), forKey: bochaEnabledKey)
    }

    static func loadTavily() -> TavilyConfiguration { loadSearch() }
    static func saveTavily(_ configuration: TavilyConfiguration) { saveSearch(configuration) }
}
