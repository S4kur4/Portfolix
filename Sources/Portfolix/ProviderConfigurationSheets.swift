import AppKit
import SwiftUI

private enum ProviderConfigurationLayout {
    static let valueFieldWidth: CGFloat = 380
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
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    @State private var provider: LLMProviderOption = .openAI
    @State private var model = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var availableModels: [String] = []
    @State private var connectionStatus: ProviderConnectionStatus?
    @State private var isFetchingModels = false
    @State private var isValidatingAPIKey = false
    @State private var isAPIKeyVisible = false
    @State private var apiKeyValidationTask: Task<Void, Never>?
    @State private var connectionStatusFingerprint: String?
    private let valueFieldWidth = ProviderConfigurationLayout.valueFieldWidth

    var body: some View {
        ProviderSheetScaffold(
            title: "LLM API",
            symbol: "sparkles.rectangle.stack",
            height: 500,
            cancelTitle: text("取消", "Cancel"),
            primaryTitle: text("保存", "Save"),
            isPrimaryDisabled: !canSave,
            cancel: { dismiss() },
            primary: save
        ) {
            Form {
                Section {
                    ProviderFormRow(label: text("供应商", "Provider")) {
                        Picker("", selection: $provider) {
                            ForEach(LLMProviderOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: valueFieldWidth, alignment: .trailing)
                    }
                    .onChange(of: provider) { _, newProvider in
                        applyProviderDefaults(newProvider)
                    }

                    ProviderFormRow(label: "API Base URL") {
                        TextField("", text: $baseURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .regular))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(PortfolixTheme.primaryText)
                            .lineLimit(1)
                            .frame(width: valueFieldWidth, height: 22, alignment: .trailing)
                            .onChange(of: baseURL) { _, _ in
                                scheduleAPIKeyValidation()
                            }
                    }

                    if !availableModels.isEmpty {
                        ProviderFormRow(label: text("模型", "Model")) {
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
                        ProviderFormRow(label: text("模型", "Model")) {
                            TextField("", text: $model)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .frame(width: valueFieldWidth, height: 22, alignment: .trailing)
                                .onChange(of: model) { _, _ in
                                    scheduleAPIKeyValidation()
                                }
                        }
                    }

                    ProviderFormRow(label: "API Key") {
                        HStack(spacing: PortfolixSpacing.sm) {
                            Group {
                                if isAPIKeyVisible {
                                    TextField("", text: $apiKey)
                                } else {
                                    SecureField("", text: $apiKey)
                                }
                            }
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(PortfolixTheme.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                            Button {
                                isAPIKeyVisible.toggle()
                            } label: {
                                Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(PortfolixTheme.tertiaryText)
                            .help(isAPIKeyVisible ? text("隐藏 API Key", "Hide API Key") : text("显示 API Key", "Show API Key"))
                        }
                        .frame(width: valueFieldWidth, height: 22, alignment: .trailing)
                        .clipped()
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
        } secondary: {
            Button {
                Task { await fetchModelsAndValidate() }
            } label: {
                ProviderActionLabel(title: text("获取模型", "Fetch Models"), isLoading: isFetchingModels)
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(isFetchingModels || !hasValidBaseURL || activeAPIKey.isEmpty)
        }
        .onAppear {
            let configuration = store.aiConfiguration
            provider = configuration.providerOption
            baseURL = configuration.baseURL.isEmpty ? provider.defaultBaseURL : configuration.baseURL
            model = configuration.model.isEmpty ? provider.defaultModel : configuration.model
            availableModels = AIProviderConfigurationStore.loadCachedModels(provider: provider)
            if !availableModels.isEmpty, !availableModels.contains(model) {
                model = availableModels.first ?? model
            }
            store.refreshProviderCredentialState()
            apiKey = (try? store.readProviderAPIKey(kind: .llm)) ?? ""
            isAPIKeyVisible = false
        }
        .onDisappear {
            apiKeyValidationTask?.cancel()
        }
    }

    private var canSave: Bool {
        hasValidBaseURL
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasVisibleOrSavedAPIKey
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

    private var hasVisibleOrSavedAPIKey: Bool {
        store.hasLLMAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeAPIKey: String {
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiKey
        }
        return (try? store.readProviderAPIKey(kind: .llm)) ?? ""
    }

    private func applyProviderDefaults(_ option: LLMProviderOption) {
        availableModels = AIProviderConfigurationStore.loadCachedModels(provider: option)
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
        do {
            _ = try LLMBaseURLValidator.validatedComponents(from: baseURL)
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveAPIKey = trimmedAPIKey.isEmpty ? savedAPIKey : trimmedAPIKey
            let isValidationContextChanged = validationFingerprint(apiKey: effectiveAPIKey) != savedValidationFingerprint
            if !trimmedAPIKey.isEmpty {
                try store.saveProviderAPIKey(trimmedAPIKey, kind: .llm)
            }
            if !effectiveAPIKey.isEmpty,
               let validationState = validationStateForSave(isValidationContextChanged: isValidationContextChanged) {
                try store.saveProviderAPIKeyValidationState(validationState, kind: .llm)
            }
            store.aiConfiguration.provider = provider.rawValue
            store.aiConfiguration.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
            store.aiConfiguration.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
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
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isValidatingAPIKey = false
                    connectionStatus = .success(text("API 配置有效", "API configuration valid"))
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

    private func fetchModelsAndValidate() async {
        guard hasValidBaseURL else {
            connectionStatus = .failure(baseURLValidationError ?? text("API Base URL 无效", "Invalid API Base URL"))
            return
        }
        isFetchingModels = true
        defer { isFetchingModels = false }
        let configuration = AIProviderConfiguration(
            provider: provider.rawValue,
            baseURL: baseURL,
            model: model.isEmpty ? provider.defaultModel : model,
            isEnabled: store.aiConfiguration.isEnabled
        )

        do {
            let models = try await LLMProviderClient.shared.listModels(configuration: configuration, apiKey: activeAPIKey)
            availableModels = models
            AIProviderConfigurationStore.saveCachedModels(models, provider: provider)
            if !models.isEmpty {
                model = models.first ?? model
            }
            let validationConfiguration = AIProviderConfiguration(
                provider: provider.rawValue,
                baseURL: baseURL,
                model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                isEnabled: store.aiConfiguration.isEnabled
            )
            try await LLMAPIKeyValidationProbe.validate(configuration: validationConfiguration, apiKey: activeAPIKey)
            connectionStatusFingerprint = validationFingerprint(apiKey: activeAPIKey)
            connectionStatus = .success(text("API 配置有效", "API configuration valid"))
        } catch {
            connectionStatus = .failure(error.localizedDescription)
            connectionStatusFingerprint = validationFingerprint(apiKey: activeAPIKey)
        }
    }

    private var noticeSymbol: String {
        if case .failure = connectionStatus {
            return "exclamationmark.circle.fill"
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
        if !hasBaseURL && !hasVisibleOrSavedAPIKey {
            return text("请填写 API Base URL 和 API Key", "Enter API Base URL and API Key")
        }
        if !hasBaseURL {
            return text("请填写 API Base URL", "Enter API Base URL")
        }
        if let baseURLValidationError {
            return baseURLValidationError
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
        if !hasValidBaseURL || !hasVisibleOrSavedAPIKey {
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

struct SearchConfigurationSheet: View {
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var provider: SearchProviderOption = .tavily
    @State private var quality: SearchQuality = .basic
    @State private var connectionStatus: ProviderConnectionStatus?
    @State private var isValidatingAPIKey = false
    @State private var isAPIKeyVisible = false
    @State private var apiKeyValidationTask: Task<Void, Never>?
    private let valueFieldWidth = ProviderConfigurationLayout.valueFieldWidth

    var body: some View {
        ProviderSheetScaffold(
            title: "Search API",
            symbol: "network",
            height: 500,
            cancelTitle: text("取消", "Cancel"),
            primaryTitle: text("保存", "Save"),
            isPrimaryDisabled: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingAPIKey,
            cancel: { dismiss() },
            primary: save
        ) {
            Form {
                Section {
                    ProviderFormRow(label: text("供应商", "Provider")) {
                        Picker("", selection: $provider) {
                            ForEach(SearchProviderOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: valueFieldWidth, alignment: .trailing)
                        .onChange(of: provider) { _, _ in
                            loadSelectedProviderCredential()
                        }
                    }

                    ProviderFormRow(label: "API Key") {
                        HStack(spacing: PortfolixSpacing.sm) {
                            Group {
                                if isAPIKeyVisible {
                                    TextField("", text: $apiKey)
                                } else {
                                    SecureField("", text: $apiKey)
                                }
                            }
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(PortfolixTheme.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                            Button {
                                isAPIKeyVisible.toggle()
                            } label: {
                                Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(PortfolixTheme.tertiaryText)
                            .help(isAPIKeyVisible ? text("隐藏 API Key", "Hide API Key") : text("显示 API Key", "Show API Key"))
                        }
                        .frame(width: valueFieldWidth, height: 22, alignment: .trailing)
                        .clipped()
                        .onChange(of: apiKey) { _, _ in
                            scheduleAPIKeyValidation()
                        }
                    }

                    if provider == .tavily {
                        ProviderFormRow(label: text("搜索质量", "Search Quality")) {
                            Picker("", selection: $quality) {
                                ForEach(SearchQuality.allCases) { option in
                                    Text(option.title(language: store.appLanguage)).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: valueFieldWidth, alignment: .trailing)
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
        } secondary: {
            EmptyView()
        }
        .onAppear {
            let configuration = store.searchConfiguration
            provider = configuration.provider
            quality = configuration.quality
            store.refreshProviderCredentialState()
            loadSelectedProviderCredential()
            isAPIKeyVisible = false
        }
        .onDisappear {
            apiKeyValidationTask?.cancel()
        }
    }

    private func save() {
        do {
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let isKeyChanged = !trimmedAPIKey.isEmpty && trimmedAPIKey != savedAPIKey
            if !trimmedAPIKey.isEmpty {
                try store.saveProviderAPIKey(trimmedAPIKey, kind: provider.credentialKind)
                if let validationState = validationStateForSave(isKeyChanged: isKeyChanged) {
                    try store.saveProviderAPIKeyValidationState(validationState, kind: provider.credentialKind)
                }
            }
            store.searchConfiguration.provider = provider
            store.searchConfiguration.quality = quality
            dismiss()
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: store.appLanguage)
    }

    private func validationStateForSave(isKeyChanged: Bool) -> ProviderCredentialValidationState? {
        if case .success = connectionStatus {
            return .valid
        }
        if case .failure = connectionStatus {
            return .invalid
        }
        return isKeyChanged ? .unknown : nil
    }

    private func scheduleAPIKeyValidation() {
        apiKeyValidationTask?.cancel()
        connectionStatus = nil
        isValidatingAPIKey = false

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        isValidatingAPIKey = true
        apiKeyValidationTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            do {
                _ = try await SearchProviderClient.shared.search(
                    query: TavilyClient.query(for: validationProbePosition),
                    positions: [validationProbePosition],
                    configuration: SearchConfiguration(isEnabled: true, provider: provider, quality: quality),
                    apiKey: key
                )
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isValidatingAPIKey = false
                    connectionStatus = .success(text("API Key 有效", "API Key valid"))
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isValidatingAPIKey = false
                    connectionStatus = .failure(error.localizedDescription)
                }
            }
        }
    }

    private var shouldShowNotice: Bool {
        if connectionStatus != nil || isValidatingAPIKey {
            return true
        }
        return false
    }

    private var noticeSymbol: String {
        if case .failure = connectionStatus {
            return "exclamationmark.circle.fill"
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
            return text("正在验证 API Key", "Validating API Key")
        }
        return ""
    }

    private var noticeMessage: String? {
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

    private var savedAPIKey: String {
        ((try? store.readProviderAPIKey(kind: provider.credentialKind)) ?? "")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func loadSelectedProviderCredential() {
        apiKeyValidationTask?.cancel()
        connectionStatus = nil
        isValidatingAPIKey = false
        apiKey = (try? store.readProviderAPIKey(kind: provider.credentialKind)) ?? ""
        scheduleAPIKeyValidation()
    }

    private var validationProbePosition: Position {
        Position(
            name: "Apple",
            symbol: "AAPL",
            category: .usStock,
            quoteCurrency: .usd,
            quantity: 1,
            averageCost: 1,
            latestPrice: 1,
            marketValueCNY: 1,
            profitRate: 0,
            weeklyTrend: [1],
            source: "东方财富",
            quoteTime: "刚刚",
            freshness: .updated
        )
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

            VStack(alignment: .leading, spacing: 0) {
                content
            }
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
    let value: Value

    init(label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.md) {
            Text(label)
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
