import AppKit
import SwiftUI

private enum ProviderConfigurationLayout {
    static let valueFieldWidth: CGFloat = 340
    static let valueFieldMinHeight: CGFloat = 28
    static let apiKeyOpticalYOffset: CGFloat = 2
}

private enum ProviderConfigurationField: Hashable {
    case llmBaseURL
    case llmModel
    case llmAPIKey
    case tavilyAPIKey
    case bochaAPIKey
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
                            Picker("", selection: $model) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
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

                if shouldShowNotice {
                    ProviderNoticeSection(
                        symbol: noticeSymbol,
                        title: noticeTitle,
                        message: noticeMessage,
                        tint: noticeTint,
                        titleColor: noticeTitleColor
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 36)
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
        didAttemptSave = true
        guard canSave else {
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
            connectionStatus = .failure(error.localizedDescription)
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
                    connectionStatus = .success(text("API 已验证", "API validated"))
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

    private var noticeSymbol: String {
        if case .failure = connectionStatus {
            return "xmark.circle.fill"
        }
        if case .success = connectionStatus {
            return "checkmark.circle.fill"
        }
        return isValidatingAPIKey ? "clock.arrow.circlepath" : "exclamationmark.circle.fill"
    }

    private var noticeTitle: String {
        if let connectionStatus {
            return connectionStatus.message
        }
        if isValidatingAPIKey {
            return text("正在验证 API 配置", "Validating API configuration")
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

    private var noticeMessage: String? {
        if case .failure = connectionStatus {
            return nil
        }
        return nil
    }

    private var noticeTint: Color {
        if let connectionStatus {
            return connectionStatus.color
        }
        if isValidatingAPIKey {
            return PortfolixTheme.lilac
        }
        return PortfolixTheme.amber
    }

    private var noticeTitleColor: Color {
        if let connectionStatus {
            return connectionStatus.color
        }
        if isValidatingAPIKey {
            return PortfolixTheme.lilac
        }
        return PortfolixTheme.amber
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
    @State private var tavilyEnabled = false
    @State private var bochaEnabled = false
    @State private var tavilyAPIKey = ""
    @State private var bochaAPIKey = ""
    @State private var initialTavilyAPIKey = ""
    @State private var initialBochaAPIKey = ""
    @State private var tavilyStatus: ProviderConnectionStatus?
    @State private var bochaStatus: ProviderConnectionStatus?
    @State private var isTavilyAPIKeyVisible = false
    @State private var isBochaAPIKeyVisible = false
    @State private var isValidating = false
    @State private var didAttemptSave = false
    @FocusState private var focusedField: ProviderConfigurationField?

    var body: some View {
        ProviderSheetScaffold(
            title: text("搜索 API", "Search APIs"),
            symbol: "globe",
            height: 620,
            cancelTitle: text("取消", "Cancel"),
            primaryTitle: text("保存", "Save"),
            isPrimaryDisabled: isValidating,
            cancel: { dismiss() },
            primary: validateAndSave
        ) {
            Form {
                freeProviderSection

                providerSection(
                    provider: .tavily,
                    isEnabled: $tavilyEnabled,
                    apiKey: $tavilyAPIKey,
                    isVisible: $isTavilyAPIKeyVisible,
                    field: .tavilyAPIKey,
                    status: tavilyStatus
                )

                providerSection(
                    provider: .bocha,
                    isEnabled: $bochaEnabled,
                    apiKey: $bochaAPIKey,
                    isVisible: $isBochaAPIKeyVisible,
                    field: .bochaAPIKey,
                    status: bochaStatus
                )
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 36)
        } secondary: { EmptyView() }
        .onAppear {
            store.refreshProviderCredentialState()
            let configuration = store.searchConfiguration
            parallelEnabled = configuration.isProviderEnabled(.parallel)
            tavilyEnabled = configuration.isProviderEnabled(.tavily)
            bochaEnabled = configuration.isProviderEnabled(.bocha)
            let storedTavilyAPIKey = (try? store.readProviderAPIKey(kind: .tavily)) ?? ""
            let storedBochaAPIKey = (try? store.readProviderAPIKey(kind: .bocha)) ?? ""
            tavilyAPIKey = storedTavilyAPIKey
            bochaAPIKey = storedBochaAPIKey
            initialTavilyAPIKey = storedTavilyAPIKey
            initialBochaAPIKey = storedBochaAPIKey
            isTavilyAPIKeyVisible = false
            isBochaAPIKeyVisible = false
            tavilyStatus = persistedStatus(for: .tavily)
            bochaStatus = persistedStatus(for: .bocha)
        }
    }

    private var freeProviderSection: some View {
        Section {
            ProviderFormRow(label: SearchProviderOption.parallel.title(language: store.appLanguage)) {
                Toggle("", isOn: $parallelEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(text("启用 Parallel Search", "Enable Parallel Search"))
            }

            Text(parallelDescription)
            .font(PortfolixTypography.caption)
            .foregroundStyle(PortfolixTheme.tertiaryText)
        }
    }

    @ViewBuilder
    private func providerSection(
        provider: SearchProviderOption,
        isEnabled: Binding<Bool>,
        apiKey: Binding<String>,
        isVisible: Binding<Bool>,
        field: ProviderConfigurationField,
        status: ProviderConnectionStatus?
    ) -> some View {
        Section {
            ProviderFormRow(label: provider.title(language: store.appLanguage)) {
                Toggle("", isOn: isEnabled)
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
                    setStatus(nil, for: provider)
                }
            }

            if let status {
                Label(status.message, systemImage: statusSymbol(status))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(status.color)
            } else {
                Text(providerDescription(provider))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiaryText)
            }
        }
    }

    private func validateAndSave() {
        didAttemptSave = true
        guard hasRequiredKeys else { return }
        isValidating = true
        tavilyStatus = tavilyEnabled ? nil : tavilyStatus
        bochaStatus = bochaEnabled ? nil : bochaStatus

        Task {
            let results = await validateEnabledProviders()
            await MainActor.run {
                isValidating = false
                for (provider, result) in results {
                    switch result {
                    case .success:
                        setStatus(.success(text("API 已验证", "API validated")), for: provider)
                    case let .failure(error):
                        setStatus(.failure(error.localizedDescription), for: provider)
                    }
                }
                guard results.values.allSatisfy({ if case .success = $0 { true } else { false } }) else {
                    return
                }
                guard persistConfiguration() else { return }
                dismiss()
            }
        }
    }

    private func validateEnabledProviders() async -> [SearchProviderOption: Result<Void, Error>] {
        let enabled = enabledProviders
        return await withTaskGroup(of: (SearchProviderOption, Result<Void, Error>).self) { group in
            for provider in enabled {
                guard provider.requiresAPIKey else { continue }
                let key = activeKey(for: provider)
                guard !key.isEmpty else { continue }
                group.addTask {
                    do {
                        try await SearchAPIKeyValidationProbe.validate(provider: provider, apiKey: key)
                        return (provider, .success(()))
                    } catch {
                        return (provider, .failure(error))
                    }
                }
            }
            var results: [SearchProviderOption: Result<Void, Error>] = [:]
            for await (provider, result) in group {
                results[provider] = result
            }
            return results
        }
    }

    private func persistConfiguration() -> Bool {
        let persistedProviders = enabledProviders.filter {
            !$0.requiresAPIKey || !activeKey(for: $0).isEmpty
        }
        for provider in SearchProviderOption.allCases {
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
                setStatus(.failure(error.localizedDescription), for: provider)
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
        if tavilyEnabled { providers.insert(.tavily) }
        if bochaEnabled { providers.insert(.bocha) }
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
        case .parallel: ""
        case .tavily: initialTavilyAPIKey
        case .bocha: initialBochaAPIKey
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
        case .tavily: tavilyAPIKey
        case .bocha: bochaAPIKey
        }
    }

    private func shouldHighlight(_ provider: SearchProviderOption) -> Bool {
        didAttemptSave && provider.requiresAPIKey && enabledProviders.contains(provider) && activeKey(for: provider).isEmpty
    }

    private func persistedStatus(for provider: SearchProviderOption) -> ProviderConnectionStatus? {
        guard let credentialKind = provider.credentialKind else {
            return nil
        }
        guard !activeKey(for: provider).isEmpty else { return nil }
        let state = (try? store.credentialValidationState(for: credentialKind)) ?? .unknown
        return switch state {
        case .valid: ProviderConnectionStatus.success(text("API 已验证", "API validated"))
        case .invalid: ProviderConnectionStatus.failure(text("API 验证失败", "API validation failed"))
        case .unknown: nil
        }
    }

    private func setStatus(_ status: ProviderConnectionStatus?, for provider: SearchProviderOption) {
        switch provider {
        case .parallel:
            break
        case .tavily:
            tavilyStatus = status
        case .bocha:
            bochaStatus = status
        }
    }

    private func statusSymbol(_ status: ProviderConnectionStatus) -> String {
        if case .success = status { return "checkmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private func providerDescription(_ provider: SearchProviderOption) -> String {
        switch (provider, store.appLanguage) {
        case (.parallel, _): parallelDescription
        case (.tavily, .chinese): "更适合国际市场、英文资料与跨市场检索。"
        case (.tavily, .english): "Best suited to global markets, English sources, and cross-market research."
        case (.bocha, .chinese): "更适合中文资料、A 股、基金与境内政策信息。"
        case (.bocha, .english): "Best suited to Chinese sources, A-shares, funds, and domestic policy research."
        }
    }

    private var parallelDescription: String {
        text(
            "免费的通用网页搜索服务，适合补充市场新闻、公开资料与跨市场信息，仅在联网增强模式下使用。",
            "A free general web search service for market news, public sources, and cross-market information; used only in Connected mode."
        )
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }
}

enum ProviderConnectionStatus: Equatable {
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case let .success(message), let .failure(message): message
        }
    }

    var color: Color {
        switch self {
        case .success: PortfolixTheme.mint
        case .failure: PortfolixTheme.danger
        }
    }
}

private struct ProviderSheetScaffold<Content: View, Secondary: View>: View {
    let title: String
    let symbol: String
    let height: CGFloat
    let cancelTitle: String
    let primaryTitle: String
    let isPrimaryDisabled: Bool
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

            HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
                HStack(spacing: PortfolixSpacing.sm) {
                    secondary
                }
                Spacer()
                HStack(spacing: PortfolixSpacing.sm) {
                    Button(cancelTitle, action: cancel)
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(primaryTitle, action: primary)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isPrimaryDisabled)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(PortfolixSpacing.xl)
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
        HStack(alignment: .center, spacing: PortfolixSpacing.md) {
            HStack(spacing: PortfolixSpacing.xs) {
                Text(label)

                if isRequired {
                    Text("·")
                        .font(.system(size: 18, weight: .heavy))
                        .baselineOffset(1)
                        .foregroundStyle(isInvalid ? PortfolixTheme.danger : PortfolixTheme.lilac)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PortfolixTheme.primaryText)
            .lineLimit(1)

            Spacer(minLength: PortfolixSpacing.md)

            value
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PortfolixTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 36, alignment: .center)
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
            isVisible: isVisible,
            field: field,
            focusedField: focusedField,
            isInvalid: isInvalid,
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

private struct ProviderNoticeRow: View {
    let symbol: String
    let title: String
    let message: String?
    let tint: Color
    let titleColor: Color

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
