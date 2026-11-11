import AppKit
import SwiftUI

private enum ProviderConfigurationLayout {
    static let valueFieldWidth: CGFloat = 340
    static let valueFieldMinHeight = SheetFormLayout.rowContentHeight
    static let apiKeyOpticalYOffset: CGFloat = 2
}

enum ProviderAPIKeyPresentation {
    static func displaysEditableText(isVisible: Bool, text: String) -> Bool {
        isVisible || text.isEmpty
    }

    static func shouldRevealWhenEditing(isVisible: Bool, text: String) -> Bool {
        !isVisible && text.isEmpty
    }
}

private enum ProviderConfigurationField: Hashable {
    case llmBaseURL
    case llmModel
    case llmAPIKey
    case tavilyAPIKey
    case bochaAPIKey
    case exaAPIKey
    case anysearchAPIKey
}

enum LLMAPIKeyValidationProbe {
    static func validate(
        configuration: AIProviderConfiguration,
        apiKey: String,
        client: LLMConnectionValidating = LLMProviderClient.shared
    ) async throws {
        let probeConfiguration = configuration
            .withRequestTimeout(LLMRequestTimeoutPolicy.validationProbe)
            .withMaxOutputTokens(LLMOutputTokenPolicy.connectionValidation)
        try await client.validateConnection(
            configuration: probeConfiguration,
            apiKey: apiKey
        )
    }
}

struct LLMConfigurationSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var provider: LLMProviderOption = .deepSeek
    @State private var model = ""
    @State private var baseURL = LLMProviderOption.deepSeek.defaultBaseURL
    @State private var apiKey = ""
    @State private var initialAPIKey = ""
    @State private var availableModels = AIProviderConfigurationStore.availableDeepSeekModels()
    @State private var connectionStatus: ProviderConnectionStatus?
    @State private var saveErrorMessage: String?
    @State private var isValidatingAPIKey = false
    @State private var isAPIKeyVisible = false
    @State private var apiKeyValidationTask: Task<Void, Never>?
    @State private var connectionStatusFingerprint: String?
    @State private var didAttemptSave = false
    @FocusState private var focusedField: ProviderConfigurationField?
    private let valueFieldWidth = ProviderConfigurationLayout.valueFieldWidth

    var body: some View {
        ProviderSheetScaffold(
            title: "DeepSeek API",
            symbol: "sparkles.rectangle.stack",
            height: 420,
            cancelTitle: text("取消", "Cancel"),
            primaryTitle: text("保存", "Save"),
            isPrimaryDisabled: isValidatingAPIKey,
            errorMessage: saveErrorMessage,
            notices: footerNotices,
            cancel: { dismiss() },
            primary: save
        ) {
            Form {
                Section {
                    ProviderFormRow(label: text("供应商", "Provider")) {
                        Text("DeepSeek")
                            .font(PortfolixTypography.body)
                            .foregroundStyle(PortfolixTheme.primaryText)
                        .frame(width: valueFieldWidth, alignment: .trailing)
                    }

                    if !availableModels.isEmpty {
                        ProviderFormRow(label: text("模型", "Model"), isRequired: true, isInvalid: shouldHighlight(.llmModel)) {
                            PortfolixGlassMenuPicker(
                                title: text("模型", "Model"),
                                selection: $model,
                                options: availableModels,
                                optionTitle: { $0 }
                            )
                            .frame(width: valueFieldWidth, alignment: .trailing)
                            .onChange(of: model) { _, _ in
                                scheduleAPIKeyValidation()
                            }
                        }
                    } else {
                        ProviderFormRow(label: text("模型", "Model"), isRequired: true, isInvalid: shouldHighlight(.llmModel)) {
                            ProviderInputField(
                                text: $model,
                                placeholder: text("填写模型名称", "Enter model name"),
                                field: .llmModel,
                                focusedField: $focusedField,
                                isInvalid: shouldHighlight(.llmModel)
                            )
                                .onChange(of: model) { _, _ in
                                    scheduleAPIKeyValidation()
                                }
                        }
                    }

                    ProviderFormRow(label: "API Key", isRequired: true, isInvalid: shouldHighlight(.llmAPIKey)) {
                        ProviderAPIKeyInputField(
                            text: $apiKey,
                            isVisible: $isAPIKeyVisible,
                            placeholder: text("填写 API Key", "Enter API Key"),
                            field: .llmAPIKey,
                            focusedField: $focusedField,
                            isInvalid: shouldHighlight(.llmAPIKey),
                            visibleHelp: text("隐藏 API Key", "Hide API Key"),
                            hiddenHelp: text("显示 API Key", "Show API Key")
                        )
                        .onChange(of: apiKey) { _, _ in
                            scheduleAPIKeyValidation()
                        }
                    }
                }

            }
            .portfolixSheetForm()
        } secondary: { EmptyView() }
        .onAppear {
            let configuration = store.aiConfiguration
            provider = .deepSeek
            baseURL = LLMProviderOption.deepSeek.defaultBaseURL
            availableModels = AIProviderConfigurationStore.availableDeepSeekModels()
            model = availableModels.contains(configuration.model)
                ? configuration.model
                : AIProviderConfigurationStore.preferredDeepSeekModel(in: availableModels)
            store.refreshProviderCredentialState()
            let storedAPIKey = (try? store.readProviderAPIKey(kind: .llm)) ?? ""
            apiKey = storedAPIKey
            initialAPIKey = storedAPIKey
            isAPIKeyVisible = false
        }
        .task {
            await refreshModelsFromAPI()
        }
        .onDisappear {
            apiKeyValidationTask?.cancel()
        }
    }

    private var canSave: Bool {
        hasValidBaseURL
            && hasModel
            && hasAPIKeyForSave
            && !isValidatingAPIKey
    }

    private var hasBaseURL: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var baseURLValidationError: String? {
        do {
            _ = try LLMBaseURLValidator.validatedComponents(from: baseURL)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var hasValidBaseURL: Bool {
        hasBaseURL && baseURLValidationError == nil
    }

    private var hasModel: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasAPIKeyForSave: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDeletingSavedAPIKey
    }

    private var isDeletingSavedAPIKey: Bool {
        !initialAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var invalidFields: Set<ProviderConfigurationField> {
        var fields: Set<ProviderConfigurationField> = []
        if !hasValidBaseURL {
            fields.insert(.llmBaseURL)
        }
        if !hasModel {
            fields.insert(.llmModel)
        }
        if !hasAPIKeyForSave {
            fields.insert(.llmAPIKey)
        }
        return fields
    }

    private func shouldHighlight(_ field: ProviderConfigurationField) -> Bool {
        didAttemptSave && invalidFields.contains(field)
    }

    private var activeAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyProviderDefaults(_ option: LLMProviderOption) {
        availableModels = option == .deepSeek
            ? AIProviderConfigurationStore.availableDeepSeekModels()
            : AIProviderConfigurationStore.loadCachedModels(provider: option)
        connectionStatus = nil
        let savedConfiguration = store.aiConfiguration
        let savedBaseURL = savedConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if savedConfiguration.providerOption == option, !savedBaseURL.isEmpty {
            baseURL = savedBaseURL
        } else if option.canAutoFillBaseURL {
            baseURL = option.defaultBaseURL
        } else {
            baseURL = ""
        }
        model = availableModels.first ?? option.defaultModel
        if store.aiConfiguration.providerOption == option, !store.aiConfiguration.model.isEmpty {
            model = store.aiConfiguration.model
        }
        scheduleAPIKeyValidation()
    }

    private func save() {
        saveErrorMessage = nil
        didAttemptSave = true
        guard canSave else {
            saveErrorMessage = noticeTitle
            return
        }
        do {
            _ = try LLMBaseURLValidator.validatedComponents(from: baseURL)
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let isValidationContextChanged = validationFingerprint(apiKey: trimmedAPIKey) != savedValidationFingerprint
            let persistenceResult = try store.persistProviderAPIKeyEdit(
                trimmedAPIKey,
                initialValue: initialAPIKey,
                kind: .llm
            )
            if persistenceResult != .deleted,
               !trimmedAPIKey.isEmpty,
               let validationState = validationStateForSave(isValidationContextChanged: isValidationContextChanged) {
                try store.saveProviderAPIKeyValidationState(validationState, kind: .llm)
            }
            store.selectAIModel(model)
            didAttemptSave = false
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func validationStateForSave(isValidationContextChanged: Bool) -> ProviderCredentialValidationState? {
        let currentFingerprint = validationFingerprint(apiKey: activeAPIKey)
        guard connectionStatusFingerprint == currentFingerprint else {
            return isValidationContextChanged ? .unknown : nil
        }
        if case .success = connectionStatus {
            return .valid
        }
        if case .failure = connectionStatus {
            return .invalid
        }
        return isValidationContextChanged ? .unknown : nil
    }

    private func scheduleAPIKeyValidation() {
        saveErrorMessage = nil
        apiKeyValidationTask?.cancel()
        connectionStatus = nil
        connectionStatusFingerprint = nil
        isValidatingAPIKey = false

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard hasValidBaseURL else { return }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return }
        let fingerprint = validationFingerprint(apiKey: key)

        isValidatingAPIKey = true
        apiKeyValidationTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            let configuration = AIProviderConfiguration(
                provider: provider.rawValue,
                baseURL: baseURL,
                model: trimmedModel,
                isEnabled: store.aiConfiguration.isEnabled
            )

            do {
                try await LLMAPIKeyValidationProbe.validate(configuration: configuration, apiKey: key)
                await refreshModelsFromAPI(apiKey: key)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isValidatingAPIKey = false
                    connectionStatus = .validatedAPI(language: store.appLanguage)
                    connectionStatusFingerprint = fingerprint
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isValidatingAPIKey = false
                    connectionStatus = .failure(error.localizedDescription)
                    connectionStatusFingerprint = fingerprint
                }
            }
        }
    }

    private func refreshModelsFromAPI(apiKey explicitAPIKey: String? = nil) async {
        guard hasValidBaseURL else { return }
        let key = (explicitAPIKey ?? activeAPIKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        let configuration = AIProviderConfiguration(
            provider: provider.rawValue,
            baseURL: baseURL,
            model: model.isEmpty ? provider.defaultModel : model,
            isEnabled: store.aiConfiguration.isEnabled
        )

        do {
            let fetchedModels = try await LLMProviderClient.shared.listModels(
                configuration: configuration,
                apiKey: key
            )
            let models = LLMProviderOption.sanitizedDeepSeekModels(fetchedModels)
            guard !models.isEmpty else { return }
            let previousModel = model
            availableModels = models
            AIProviderConfigurationStore.saveCachedModels(models, provider: provider)
            store.updateAvailableDeepSeekModels(models)
            model = AIProviderConfigurationStore.preferredDeepSeekModel(
                current: previousModel,
                in: models
            )
        } catch {
            // Keep the embedded or cached catalog available when refresh fails.
        }
    }

    private var footerNotices: [SheetNotice] {
        guard shouldShowNotice else { return [] }
        if let connectionStatus { return [connectionStatus.footerNotice()] }
        if isValidatingAPIKey { return [ProviderConnectionStatus.validatingAPI(language: store.appLanguage).footerNotice()] }
        return [.init(message: noticeTitle, kind: .warning)]
    }

    private var noticeTitle: String {
        if let connectionStatus {
            return connectionStatus.message
        }
        if isValidatingAPIKey {
            return ProviderConnectionStatus.validatingAPI(language: store.appLanguage).message
        }
        if !hasBaseURL && !hasAPIKeyForSave {
            return text("请填写 API Base URL 和 API Key", "Enter API Base URL and API Key")
        }
        if !hasBaseURL {
            return text("请填写 API Base URL", "Enter API Base URL")
        }
        if let baseURLValidationError {
            return baseURLValidationError
        }
        if !hasModel {
            return text("请填写模型名称", "Enter model name")
        }
        return text("请填写 API Key", "Enter API Key")
    }

    private var shouldShowNotice: Bool {
        if connectionStatus != nil || isValidatingAPIKey {
            return true
        }
        if !hasValidBaseURL || !hasModel || !hasAPIKeyForSave {
            return true
        }
        return false
    }

    private var savedAPIKey: String {
        ((try? store.readProviderAPIKey(kind: .llm)) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var savedValidationFingerprint: String {
        let configuration = store.aiConfiguration
        return [
            configuration.providerOption.rawValue,
            configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
            "\(savedAPIKey.hashValue)",
        ].joined(separator: "|")
    }

    private func validationFingerprint(apiKey: String) -> String {
        [
            provider.rawValue,
            baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model.trimmingCharacters(in: .whitespacesAndNewlines),
            "\(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hashValue)",
        ].joined(separator: "|")
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}

enum SearchAPIKeyValidationProbe {
    static func validate(
        provider: SearchProviderOption,
        apiKey: String,
        client: WebSearching = SearchProviderClient.shared
    ) async throws {
        let query = provider == .bocha
            ? "上海证券交易所 最新公告"
            : "Apple investor relations latest filing"
        _ = try await client.search(
            query: query,
            positions: [],
            configuration: SearchConfiguration(isEnabled: true, provider: provider, quality: .basic),
            apiKey: apiKey
        )
    }
}

struct SearchConfigurationSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var parallelEnabled = false
    @State private var deepseekEnabled = false
    @State private var tavilyEnabled = false
    @State private var bochaEnabled = false
    @State private var exaEnabled = false
    @State private var anysearchEnabled = false
    @State private var tavilyAPIKey = ""
    @State private var bochaAPIKey = ""
    @State private var exaAPIKey = ""
    @State private var anysearchAPIKey = ""
    @State private var initialTavilyAPIKey = ""
    @State private var initialBochaAPIKey = ""
    @State private var initialExaAPIKey = ""
    @State private var initialAnySearchAPIKey = ""
    @State private var providerNotices = SearchProviderNoticeState()
    @State private var isTavilyAPIKeyVisible = false
    @State private var isBochaAPIKeyVisible = false
    @State private var isExaAPIKeyVisible = false
    @State private var isAnySearchAPIKeyVisible = false
    @State private var validatingProviders: Set<SearchProviderOption> = []
    @State private var validationRequestIDs: [SearchProviderOption: UUID] = [:]
    @State private var activationPromptProviders: Set<SearchProviderOption> = []
    @State private var didLoadConfiguration = false
    @State private var didAttemptSave = false
    @State private var saveErrorMessage: String?
    @FocusState private var focusedField: ProviderConfigurationField?

    var body: some View {
        ProviderSheetScaffold(
            title: text("搜索 API", "Search APIs"),
            symbol: "globe",
            height: 620,
            cancelTitle: text("取消", "Cancel"),
            primaryTitle: text("保存", "Save"),
            isPrimaryDisabled: isValidating,
            errorMessage: saveErrorMessage,
            notices: footerNotices,
            cancel: { dismiss() },
            primary: validateAndSave
        ) {
            Form {
                sharedProviderSection

                providerSection(
                    provider: .tavily,
                    isEnabled: $tavilyEnabled,
                    apiKey: $tavilyAPIKey,
                    isVisible: $isTavilyAPIKeyVisible,
                    field: .tavilyAPIKey
                )

                providerSection(
                    provider: .bocha,
                    isEnabled: $bochaEnabled,
                    apiKey: $bochaAPIKey,
                    isVisible: $isBochaAPIKeyVisible,
                    field: .bochaAPIKey
                )

                providerSection(
                    provider: .exa,
                    isEnabled: $exaEnabled,
                    apiKey: $exaAPIKey,
                    isVisible: $isExaAPIKeyVisible,
                    field: .exaAPIKey
                )

                providerSection(
                    provider: .anysearch,
                    isEnabled: $anysearchEnabled,
                    apiKey: $anysearchAPIKey,
                    isVisible: $isAnySearchAPIKeyVisible,
                    field: .anysearchAPIKey
                )
            }
            .portfolixSheetForm()
        } secondary: { EmptyView() }
        .onAppear {
            store.refreshProviderCredentialState()
            let configuration = store.searchConfiguration
            parallelEnabled = configuration.isProviderEnabled(.parallel)
            deepseekEnabled = configuration.isProviderEnabled(.deepseek)
            tavilyEnabled = configuration.isProviderEnabled(.tavily)
            bochaEnabled = configuration.isProviderEnabled(.bocha)
            exaEnabled = configuration.isProviderEnabled(.exa)
            anysearchEnabled = configuration.isProviderEnabled(.anysearch)
            let storedTavilyAPIKey = (try? store.readProviderAPIKey(kind: .tavily)) ?? ""
            let storedBochaAPIKey = (try? store.readProviderAPIKey(kind: .bocha)) ?? ""
            let storedExaAPIKey = (try? store.readProviderAPIKey(kind: .exa)) ?? ""
            let storedAnySearchAPIKey = (try? store.readProviderAPIKey(kind: .anysearch)) ?? ""
            tavilyAPIKey = storedTavilyAPIKey
            bochaAPIKey = storedBochaAPIKey
            exaAPIKey = storedExaAPIKey
            anysearchAPIKey = storedAnySearchAPIKey
            initialTavilyAPIKey = storedTavilyAPIKey
            initialBochaAPIKey = storedBochaAPIKey
            initialExaAPIKey = storedExaAPIKey
            initialAnySearchAPIKey = storedAnySearchAPIKey
            isTavilyAPIKeyVisible = false
            isBochaAPIKeyVisible = false
            isExaAPIKeyVisible = false
            isAnySearchAPIKeyVisible = false
            providerNotices.update(persistedStatus(for: .tavily), for: .tavily)
            providerNotices.update(persistedStatus(for: .bocha), for: .bocha)
            providerNotices.update(persistedStatus(for: .exa), for: .exa)
            providerNotices.update(persistedStatus(for: .anysearch), for: .anysearch)
            Task { @MainActor in
                await Task.yield()
                didLoadConfiguration = true
            }
        }
    }

    private var sharedProviderSection: some View {
        Section {
            ProviderFormRow(label: SearchProviderOption.parallel.title(language: store.appLanguage)) {
                Toggle("", isOn: $parallelEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(text("启用 Parallel Search", "Enable Parallel Search"))
                .onChange(of: parallelEnabled) { _, _ in
                    guard didLoadConfiguration else { return }
                    saveErrorMessage = nil
                    providerNotices.begin(.parallel)
                }
            }

            ProviderFormRow(label: SearchProviderOption.deepseek.title(language: store.appLanguage)) {
                Toggle("", isOn: Binding(
                    get: { deepseekEnabled },
                    set: { enabled in
                        if enabled {
                            enable(.deepseek, isEnabled: $deepseekEnabled, field: .llmAPIKey)
                        } else {
                            saveErrorMessage = nil
                            providerNotices.begin(.deepseek)
                            deepseekEnabled = false
                            validatingProviders.remove(.deepseek)
                            validationRequestIDs[.deepseek] = nil
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(text("启用 DeepSeek Search", "Enable DeepSeek Search"))
            }
        }
    }

    @ViewBuilder
    private func providerSection(
        provider: SearchProviderOption,
        isEnabled: Binding<Bool>,
        apiKey: Binding<String>,
        isVisible: Binding<Bool>,
        field: ProviderConfigurationField
    ) -> some View {
        Section {
            ProviderFormRow(label: provider.title(language: store.appLanguage)) {
                Toggle("", isOn: activationBinding(for: provider, isEnabled: isEnabled, field: field))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(
                        text("启用 \(provider.title(language: .chinese))", "Enable \(provider.title(language: .english))")
                    )
            }

            ProviderFormRow(
                label: "API Key",
                isRequired: isEnabled.wrappedValue,
                isInvalid: shouldHighlight(provider)
            ) {
                ProviderAPIKeyInputField(
                    text: apiKey,
                    isVisible: isVisible,
                    placeholder: text("填写 API Key", "Enter API Key"),
                    field: field,
                    focusedField: $focusedField,
                    isInvalid: shouldHighlight(provider),
                    visibleHelp: text("隐藏 API Key", "Hide API Key"),
                    hiddenHelp: text("显示 API Key", "Show API Key")
                )
                .onChange(of: apiKey.wrappedValue) { _, _ in
                    guard didLoadConfiguration else { return }
                    saveErrorMessage = nil
                    providerNotices.begin(provider)
                    activationPromptProviders.remove(provider)
                    validatingProviders.remove(provider)
                    validationRequestIDs[provider] = nil
                    if isEnabled.wrappedValue {
                        isEnabled.wrappedValue = false
                    }
                    setStatus(nil, for: provider)
                }
            }

        }
    }

    private var footerNotices: [SheetNotice] {
        providerNotices.currentNotice(language: store.appLanguage).map { [$0] } ?? []
    }

    private func validateAndSave() {
        saveErrorMessage = nil
        didAttemptSave = true
        guard hasRequiredKeys else {
            saveErrorMessage = text("请填写已启用搜索服务的 API Key。", "Enter an API Key for each enabled search service.")
            return
        }
        guard persistConfiguration() else { return }
        dismiss()
    }

    private var isValidating: Bool {
        !validatingProviders.isEmpty
    }

    private func activationBinding(
        for provider: SearchProviderOption,
        isEnabled: Binding<Bool>,
        field: ProviderConfigurationField
    ) -> Binding<Bool> {
        Binding(
            get: { isEnabled.wrappedValue },
            set: { requestedValue in
                saveErrorMessage = nil
                providerNotices.begin(provider)
                if !requestedValue {
                    validatingProviders.remove(provider)
                    validationRequestIDs[provider] = nil
                    activationPromptProviders.remove(provider)
                    isEnabled.wrappedValue = false
                    return
                }
                enable(provider, isEnabled: isEnabled, field: field)
            }
        )
    }

    private func enable(
        _ provider: SearchProviderOption,
        isEnabled: Binding<Bool>,
        field: ProviderConfigurationField
    ) {
        saveErrorMessage = nil
        providerNotices.begin(provider)
        let key = activeKey(for: provider)
        guard !key.isEmpty else {
            activationPromptProviders.insert(provider)
            setStatus(
                .failure(provider == .deepseek
                         ? text("请先在 DeepSeek API 中配置密钥", "Configure your key in DeepSeek API first")
                         : text("请先填写 API Key", "Enter an API Key first")),
                for: provider
            )
            revealAndFocusAPIKey(for: provider, field: field)
            return
        }

        activationPromptProviders.remove(provider)
        isEnabled.wrappedValue = true
        validatingProviders.insert(provider)
        let requestID = UUID()
        validationRequestIDs[provider] = requestID
        setStatus(.validatingAPI(language: store.appLanguage), for: provider)

        Task {
            let result: Result<Void, Error>
            do {
                try await SearchAPIKeyValidationProbe.validate(provider: provider, apiKey: key)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            guard validationRequestIDs[provider] == requestID else { return }
            validationRequestIDs[provider] = nil
            validatingProviders.remove(provider)
            guard isEnabled.wrappedValue, activeKey(for: provider) == key else { return }
            switch result {
            case .success:
                setStatus(.validatedAPI(language: store.appLanguage), for: provider)
            case let .failure(error):
                isEnabled.wrappedValue = false
                setStatus(.failure(error.localizedDescription), for: provider)
            }
        }
    }

    private func revealAndFocusAPIKey(
        for provider: SearchProviderOption,
        field: ProviderConfigurationField
    ) {
        switch provider {
        case .parallel, .deepseek:
            return
        case .tavily:
            isTavilyAPIKeyVisible = true
        case .bocha:
            isBochaAPIKeyVisible = true
        case .exa:
            isExaAPIKeyVisible = true
        case .anysearch:
            isAnySearchAPIKeyVisible = true
        }
        Task { @MainActor in
            await Task.yield()
            focusedField = field
        }
    }

    private func persistConfiguration() -> Bool {
        let persistedProviders = enabledProviders.filter {
            !$0.requiresAPIKey || !activeKey(for: $0).isEmpty
        }
        for provider in SearchProviderOption.independentlyConfiguredProviders {
            guard let credentialKind = provider.credentialKind else { continue }
            let key = visibleKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let result = try store.persistProviderAPIKeyEdit(
                    key,
                    initialValue: initialKey(for: provider),
                    kind: credentialKind
                )
                if result == .deleted {
                    setStatus(nil, for: provider)
                } else if persistedProviders.contains(provider), !key.isEmpty {
                    try store.saveProviderAPIKeyValidationState(.valid, kind: credentialKind)
                }
            } catch {
                saveErrorMessage = error.localizedDescription
                return false
            }
        }
        let wasConnected = store.searchConfiguration.isEnabled
        store.searchConfiguration = SearchConfiguration(
            isEnabled: wasConnected && !persistedProviders.isEmpty,
            enabledProviders: persistedProviders,
            preferredProvider: store.searchConfiguration.preferredProvider,
            quality: store.searchConfiguration.quality
        )
        return true
    }

    private var enabledProviders: Set<SearchProviderOption> {
        var providers = Set<SearchProviderOption>()
        if parallelEnabled { providers.insert(.parallel) }
        if deepseekEnabled { providers.insert(.deepseek) }
        if tavilyEnabled { providers.insert(.tavily) }
        if bochaEnabled { providers.insert(.bocha) }
        if exaEnabled { providers.insert(.exa) }
        if anysearchEnabled { providers.insert(.anysearch) }
        return providers
    }

    private var hasRequiredKeys: Bool {
        enabledProviders.allSatisfy {
            !$0.requiresAPIKey || !activeKey(for: $0).isEmpty || isDeletingSavedKey(for: $0)
        }
    }

    private func activeKey(for provider: SearchProviderOption) -> String {
        visibleKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func initialKey(for provider: SearchProviderOption) -> String {
        switch provider {
        case .parallel, .deepseek: ""
        case .tavily: initialTavilyAPIKey
        case .bocha: initialBochaAPIKey
        case .exa: initialExaAPIKey
        case .anysearch: initialAnySearchAPIKey
        }
    }

    private func isDeletingSavedKey(for provider: SearchProviderOption) -> Bool {
        provider.requiresAPIKey
            && !initialKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && activeKey(for: provider).isEmpty
    }

    private func visibleKey(for provider: SearchProviderOption) -> String {
        switch provider {
        case .parallel: ""
        case .deepseek: (try? store.readProviderAPIKey(kind: .llm)) ?? ""
        case .tavily: tavilyAPIKey
        case .bocha: bochaAPIKey
        case .exa: exaAPIKey
        case .anysearch: anysearchAPIKey
        }
    }

    private func shouldHighlight(_ provider: SearchProviderOption) -> Bool {
        activationPromptProviders.contains(provider)
            || (didAttemptSave && provider.requiresAPIKey && enabledProviders.contains(provider) && activeKey(for: provider).isEmpty)
    }

    private func persistedStatus(for provider: SearchProviderOption) -> ProviderConnectionStatus? {
        guard let credentialKind = provider.credentialKind else {
            return nil
        }
        guard !activeKey(for: provider).isEmpty else { return nil }
        let state = (try? store.credentialValidationState(for: credentialKind)) ?? .unknown
        return switch state {
        case .valid: ProviderConnectionStatus.validatedAPI(language: store.appLanguage)
        case .invalid: ProviderConnectionStatus.failure(text("API 验证失败", "API validation failed"))
        case .unknown: nil
        }
    }

    private func setStatus(_ status: ProviderConnectionStatus?, for provider: SearchProviderOption) {
        providerNotices.update(status, for: provider)
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}

struct SearchProviderNoticeState {
    private(set) var activeProvider: SearchProviderOption?
    private var statuses: [SearchProviderOption: ProviderConnectionStatus] = [:]

    mutating func begin(_ provider: SearchProviderOption) {
        activeProvider = provider
        statuses[provider] = nil
    }

    mutating func update(_ status: ProviderConnectionStatus?, for provider: SearchProviderOption) {
        statuses[provider] = status
    }

    func currentNotice(language: AppLanguage) -> SheetNotice? {
        guard let activeProvider, let status = statuses[activeProvider] else { return nil }
        return status.footerNotice(prefix: activeProvider.title(language: language))
    }
}

enum ProviderConnectionStatus: Equatable {
    case success(String)
    case failure(String)
    case validating(String)

    static func validatingAPI(language: AppLanguage) -> Self {
        .validating(localizedText("正在验证 API 配置", "Validating API configuration", language: language))
    }

    static func validatedAPI(language: AppLanguage) -> Self {
        .success(localizedText("API 已验证", "API validated", language: language))
    }

    var message: String {
        switch self {
        case let .success(message), let .failure(message), let .validating(message): message
        }
    }

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .validating: "clock.arrow.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .success: PortfolixTheme.mint
        case .failure: PortfolixTheme.danger
        case .validating: PortfolixTheme.lilac
        }
    }

    func footerNotice(prefix: String? = nil) -> SheetNotice {
        let kind: SheetNotice.Kind = switch self {
        case .success: .success
        case .failure: .error
        case .validating: .progress
        }
        return SheetNotice(message: prefix.map { "\($0) · \(message)" } ?? message, kind: kind)
    }
}

private struct ProviderSheetScaffold<Content: View, Secondary: View>: View {
    let title: String
    let symbol: String
    let height: CGFloat
    let cancelTitle: String
    let primaryTitle: String
    let isPrimaryDisabled: Bool
    let errorMessage: String?
    let notices: [SheetNotice]
    let cancel: () -> Void
    let primary: () -> Void
    let content: Content
    let secondary: Secondary

    init(
        title: String,
        symbol: String,
        height: CGFloat = 500,
        cancelTitle: String,
        primaryTitle: String,
        isPrimaryDisabled: Bool,
        errorMessage: String? = nil,
        notices: [SheetNotice] = [],
        cancel: @escaping () -> Void,
        primary: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.title = title
        self.symbol = symbol
        self.height = height
        self.cancelTitle = cancelTitle
        self.primaryTitle = primaryTitle
        self.isPrimaryDisabled = isPrimaryDisabled
        self.errorMessage = errorMessage
        self.notices = notices
        self.cancel = cancel
        self.primary = primary
        self.content = content()
        self.secondary = secondary()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: title, symbol: symbol)

            Divider().overlay(PortfolixTheme.border)

            content
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(PortfolixTheme.border)

            SheetActionFooter(errorMessage: errorMessage, notices: notices, leading: { secondary }) {
                Button(cancelTitle, action: cancel)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: primary)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isPrimaryDisabled)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 560, height: height)
        .background {
            PortfolixSheetBackground()
        }
        .onAppear(perform: clearInitialTextSelection)
    }

    private func clearInitialTextSelection() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

private struct ProviderFormRow<Value: View>: View {
    let label: String
    let isRequired: Bool
    let isInvalid: Bool
    let value: Value

    init(
        label: String,
        isRequired: Bool = false,
        isInvalid: Bool = false,
        @ViewBuilder value: () -> Value
    ) {
        self.label = label
        self.isRequired = isRequired
        self.isInvalid = isInvalid
        self.value = value()
    }

    var body: some View {
        LabeledContent {
            value
                .foregroundStyle(PortfolixTheme.primaryText)
        } label: {
            AssetEntryFieldLabel(title: label, isInvalid: isInvalid, showsRequiredIndicator: isRequired)
        }
    }
}

private struct ProviderInputField: View {
    @Binding var text: String
    let placeholder: String
    let field: ProviderConfigurationField
    let focusedField: FocusState<ProviderConfigurationField?>.Binding
    let isInvalid: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            if shouldShowPlaceholder {
                Text(placeholder)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(placeholderColor)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(inputColor)
                .lineLimit(1)
                .focused(focusedField, equals: field)
        }
        .frame(width: ProviderConfigurationLayout.valueFieldWidth, alignment: .trailing)
        .frame(minHeight: ProviderConfigurationLayout.valueFieldMinHeight, alignment: .center)
        .clipped()
    }

    private var shouldShowPlaceholder: Bool {
        focusedField.wrappedValue != field && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var placeholderColor: Color {
        isInvalid ? PortfolixTheme.danger : PortfolixTheme.tertiaryText
    }

    private var inputColor: Color {
        isInvalid ? PortfolixTheme.danger : PortfolixTheme.primaryText
    }
}

private struct ProviderAPIKeyInputField: View {
    @Binding var text: String
    @Binding var isVisible: Bool
    let placeholder: String
    let field: ProviderConfigurationField
    let focusedField: FocusState<ProviderConfigurationField?>.Binding
    let isInvalid: Bool
    let visibleHelp: String
    let hiddenHelp: String

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            ZStack(alignment: .trailing) {
                if shouldShowPlaceholder {
                    Text(placeholder)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(placeholderColor)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                inputContent
            }
            .frame(
                maxWidth: .infinity,
                minHeight: ProviderConfigurationLayout.valueFieldMinHeight,
                alignment: .trailing
            )
            .clipped()

            Button {
                if isVisible {
                    focusedField.wrappedValue = nil
                    isVisible = false
                } else {
                    revealAndFocus()
                }
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PortfolixTheme.tertiaryText)
            .accessibilityLabel(isVisible ? visibleHelp : hiddenHelp)
        }
        .frame(width: ProviderConfigurationLayout.valueFieldWidth, alignment: .trailing)
        .frame(minHeight: ProviderConfigurationLayout.valueFieldMinHeight, alignment: .center)
        .clipped()
    }

    @ViewBuilder
    private var inputContent: some View {
        ProviderAPIKeyTextInput(
            text: $text,
            isVisible: displaysEditableText,
            field: field,
            focusedField: focusedField,
            isInvalid: isInvalid,
            shouldRevealWhenEditing: ProviderAPIKeyPresentation.shouldRevealWhenEditing(
                isVisible: isVisible,
                text: text
            ),
            onReveal: revealAndFocus
        )
            .frame(
                maxWidth: .infinity,
                minHeight: ProviderConfigurationLayout.valueFieldMinHeight,
                alignment: .trailing
            )
            .clipped()
    }

    private func revealAndFocus() {
        guard !isVisible else { return }
        isVisible = true
        DispatchQueue.main.async {
            guard isVisible else { return }
            focusedField.wrappedValue = field
        }
    }

    private var displaysEditableText: Bool {
        ProviderAPIKeyPresentation.displaysEditableText(isVisible: isVisible, text: text)
    }

    private var shouldShowPlaceholder: Bool {
        focusedField.wrappedValue != field && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var placeholderColor: Color {
        isInvalid ? PortfolixTheme.danger : PortfolixTheme.tertiaryText
    }

    private var inputColor: Color {
        isInvalid ? PortfolixTheme.danger : PortfolixTheme.primaryText
    }
}

private struct ProviderAPIKeyTextInput: NSViewRepresentable {
    @Binding var text: String
    let isVisible: Bool
    let field: ProviderConfigurationField
    let focusedField: FocusState<ProviderConfigurationField?>.Binding
    let isInvalid: Bool
    let shouldRevealWhenEditing: Bool
    let onReveal: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ProviderAPIKeyTextInputView {
        let view = ProviderAPIKeyTextInputView()
        view.plainField.delegate = context.coordinator
        view.onReveal = onReveal
        return view
    }

    func updateNSView(_ nsView: ProviderAPIKeyTextInputView, context: Context) {
        context.coordinator.parent = self
        nsView.onReveal = onReveal
        nsView.update(text: text, isVisible: isVisible, textColor: textColor)
        if focusedField.wrappedValue == field {
            nsView.focusActiveField()
        }
    }

    private var textColor: NSColor {
        isInvalid ? .portfolixDanger : .labelColor
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ProviderAPIKeyTextInput

        init(parent: ProviderAPIKeyTextInput) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            if parent.shouldRevealWhenEditing {
                parent.onReveal()
            }
            parent.focusedField.wrappedValue = parent.field
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if parent.focusedField.wrappedValue == parent.field {
                parent.focusedField.wrappedValue = nil
            }
        }
    }
}

final class ProviderAPIKeyTextInputView: NSView {
    private static let maskedValue = "xxxxxxxxxxxx"

    let plainField = NSTextField()
    private let maskedDisplayField = NSSecureTextField()
    private var isVisible = false
    var onReveal: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setup(field: plainField)
        setupMaskedDisplayField()
        addSubview(maskedDisplayField)
        addSubview(plainField)
        NSLayoutConstraint.activate([
            plainField.leadingAnchor.constraint(equalTo: leadingAnchor),
            plainField.trailingAnchor.constraint(equalTo: trailingAnchor),
            plainField.centerYAnchor.constraint(
                equalTo: centerYAnchor,
                constant: ProviderConfigurationLayout.apiKeyOpticalYOffset
            ),
            plainField.heightAnchor.constraint(equalToConstant: 24),
            maskedDisplayField.leadingAnchor.constraint(equalTo: leadingAnchor),
            maskedDisplayField.trailingAnchor.constraint(equalTo: trailingAnchor),
            maskedDisplayField.centerYAnchor.constraint(
                equalTo: centerYAnchor,
                constant: ProviderConfigurationLayout.apiKeyOpticalYOffset
            ),
            maskedDisplayField.heightAnchor.constraint(equalToConstant: 24),
        ])
        plainField.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, isVisible: Bool, textColor: NSColor) {
        let wasEditing = plainField.currentEditor() != nil
        self.isVisible = isVisible
        plainField.isHidden = !isVisible
        maskedDisplayField.isHidden = isVisible
        if plainField.stringValue != text {
            plainField.stringValue = text
        }
        maskedDisplayField.stringValue = text.isEmpty ? "" : Self.maskedValue
        plainField.textColor = textColor
        maskedDisplayField.textColor = textColor
        if wasEditing {
            focusActiveField()
        }
    }

    func focusActiveField() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, let window else { return }
            if self.plainField.currentEditor() == nil {
                window.makeFirstResponder(self.plainField)
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !isVisible, bounds.contains(point) {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isVisible else {
            super.mouseDown(with: event)
            return
        }
        onReveal?()
    }

    private func setup(field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .right
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.textColor = .labelColor
        field.usesSingleLineMode = true
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.lineBreakMode = .byTruncatingMiddle
    }

    private func setupMaskedDisplayField() {
        setup(field: maskedDisplayField)
        maskedDisplayField.isEditable = false
        maskedDisplayField.isSelectable = false
        maskedDisplayField.cell?.lineBreakMode = .byClipping
    }
}

private extension NSColor {
    static let portfolixDanger = NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return NSColor(hex: match == .darkAqua ? 0xDD7D88 : 0xB44755)
    }
}

struct SheetHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PortfolixTheme.primaryText)
                .lineLimit(1)
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(PortfolixTheme.lilac)
        }
        .padding(PortfolixSpacing.xl)
    }
}

private struct ProviderActionLabel: View {
    let title: String
    let isLoading: Bool

    var body: some View {
        ZStack {
            Text(title)
                .opacity(isLoading ? 0 : 1)

            ProgressView()
                .controlSize(.small)
                .labelsHidden()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
                .opacity(isLoading ? 1 : 0)
        }
        .frame(width: 84, height: 14)
        .fixedSize()
        .animation(nil, value: isLoading)
    }
}

private struct ProviderNoticeSection: View {
    let symbol: String
    let title: String
    let message: String?
    let tint: Color
    let titleColor: Color

    var body: some View {
        Section {
            ProviderNoticeRow(
                symbol: symbol,
                title: title,
                message: message,
                tint: tint,
                titleColor: titleColor
            )
        }
        .listRowBackground(PortfolixTheme.panel)
        .listRowSeparator(.hidden)
    }
}

struct ProviderNoticeRow: View {
    let symbol: String
    let title: String
    let message: String?
    let tint: Color
    let titleColor: Color

    init(status: ProviderConnectionStatus) {
        self.init(symbol: status.symbol, title: status.message, message: nil, tint: status.color, titleColor: status.color)
    }

    init(symbol: String, title: String, message: String?, tint: Color, titleColor: Color) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.tint = tint
        self.titleColor = titleColor
    }

    var body: some View {
        HStack(alignment: .top, spacing: PortfolixSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(PortfolixTheme.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, PortfolixSpacing.xs)
    }
}
