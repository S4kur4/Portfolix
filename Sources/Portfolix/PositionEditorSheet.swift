import SwiftUI

private struct AssetLookupProviderMessage: Sendable {
    let chinese: String
    let english: String
}

private struct AssetLookupProviderResult: Sendable {
    let candidates: [AssetLookupCandidate]
    let providerMessage: AssetLookupProviderMessage?

    init(candidates: [AssetLookupCandidate] = [], error: AssetLookupProviderMessage? = nil) {
        self.candidates = candidates
        self.providerMessage = error
    }

    func message(language: AppLanguage) -> String? {
        guard let providerMessage else { return nil }
        return localizedText(providerMessage.chinese, providerMessage.english, language: language)
    }
}

struct PositionEditorSheet: View {
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    let presentation: PositionEditorPresentation
    @State private var name: String
    @State private var symbol: String
    @State private var category: AssetCategory
    @State private var quantity: String
    @State private var costValue: String
    @State private var costMode: CostEntryMode
    @State private var costCurrency: DisplayCurrency
    @State private var latestPrice: String
    @State private var validationMessage: String?
    @State private var assetCandidates: [AssetLookupCandidate] = []
    @State private var isSearchingAssets = false
    @State private var isResolvingAsset = false
    @State private var assetLookupMessage: String?
    @State private var assetLookupTask: Task<Void, Never>?
    @State private var selectedAssetCandidate: AssetLookupCandidate?
    @State private var assetLookupGeneration = 0
    @State private var isManualAssetEntry: Bool
    @State private var selectedQuoteTime: String?
    @State private var isSaving = false

    init(presentation: PositionEditorPresentation) {
        self.presentation = presentation
        let position = presentation.position
        _name = State(initialValue: position?.name ?? "")
        _symbol = State(initialValue: position?.symbol ?? "")
        _category = State(initialValue: position?.category ?? .cnStock)
        _quantity = State(initialValue: position.map { decimalString($0.quantity) } ?? "")
        _costValue = State(initialValue: position.map { decimalString($0.averageCost) } ?? "")
        _costMode = State(initialValue: .averageCost)
        _costCurrency = State(initialValue: position?.quoteCurrency ?? .cny)
        _latestPrice = State(initialValue: position.map { decimalString($0.latestPrice) } ?? "")
        _validationMessage = State(initialValue: nil)
        _isManualAssetEntry = State(initialValue: position?.source == "手工价格" || position == nil)
        _selectedQuoteTime = State(initialValue: position?.quoteTime)
    }

    private var isEditing: Bool {
        presentation.position != nil
    }

    private var language: AppLanguage {
        store.appLanguage
    }

    private func sheetText(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: isEditing ? sheetText("编辑持仓", "Edit Holding") : sheetText("添加持仓", "Add Holding"),
                symbol: "square.and.pencil"
            )

            Divider().overlay(PortfolixTheme.border)

            Form {
                Section {
                    TextField(sheetText("资产名称", "Asset Name"), text: $name)
                        .onChange(of: name) { _, value in
                            scheduleAssetSearch(for: value)
                        }
                    TextField(sheetText("资产代码", "Asset Code"), text: $symbol)
                        .onChange(of: symbol) { _, value in
                            scheduleAssetSearch(for: value)
                        }

                    if isSearchingAssets || isResolvingAsset {
                        HStack(spacing: PortfolixSpacing.sm) {
                            ProgressView()
                                .controlSize(.small)
                            Text(isResolvingAsset ? sheetText("正在获取最新价格", "Fetching latest price") : sheetText("正在查询数据源", "Searching data sources"))
                                .font(.system(size: 11))
                                .foregroundStyle(PortfolixTheme.secondaryText)
                        }
                    }

                    if !assetCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                            Text(sheetText("数据候选", "Data Candidates"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(PortfolixTheme.tertiaryText)

                            ForEach(assetCandidates) { candidate in
                                AssetCandidateButton(candidate: candidate, language: language) {
                                    selectAssetCandidate(candidate)
                                }
                            }
                        }
                        .padding(.vertical, PortfolixSpacing.xs)
                    }

                    if let assetLookupMessage {
                        Text(assetLookupMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(PortfolixTheme.tertiaryText)
                    }
                }

                Picker(sheetText("资产类别", "Asset Type"), selection: $category) {
                    ForEach(AssetCategory.allCases) { category in
                        Text(category.title(language: language)).tag(category)
                    }
                }
                .disabled(!isManualAssetEntry)

                if !isManualAssetEntry {
                    HStack(spacing: PortfolixSpacing.sm) {
                        Label(sheetText("类型与计价币种由数据源确定", "Type and currency are set by the data source"), systemImage: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(PortfolixTheme.secondaryText)

                        Spacer()

                        Button(sheetText("改为手工录入", "Use Manual Entry")) {
                            switchToManualEntry()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PortfolixTheme.lilac)
                    }
                }

                TextField(sheetText("当前份额", "Current Shares"), text: $quantity)

                Picker(sheetText("成本录入方式", "Cost Input Method"), selection: $costMode) {
                    ForEach(CostEntryMode.allCases) { mode in
                        Text(mode.title(language: language)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField(costMode.title(language: language), text: $costValue)

                Picker(sheetText("计价与成本币种", "Price and Cost Currency"), selection: $costCurrency) {
                    ForEach(DisplayCurrency.allCases) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!isManualAssetEntry)

                TextField(sheetText("当前价格", "Current Price"), text: $latestPrice)

                if let priceMetadataText {
                    LabeledContent(sheetText("价格日期", "Price Date")) {
                        Text(priceMetadataText)
                            .foregroundStyle(PortfolixTheme.secondaryText)
                            .lineLimit(1)
                    }
                }

                LabeledContent(sheetText("持有金额", "Holding Amount")) {
                    Text(holdingAmountText)
                        .foregroundStyle(PortfolixTheme.secondaryText)
                        .monospacedDigit()
                }

                if quantityChanged {
                    Section {
                        EditorNoticeRow(
                            symbol: "exclamationmark.triangle.fill",
                            title: costChangeReminderText,
                            tint: PortfolixTheme.amber,
                            titleColor: PortfolixTheme.amber
                        )
                    }
                    .listRowBackground(PortfolixTheme.panel)
                    .listRowSeparator(.hidden)
                }

                if let validationMessage {
                    Section {
                        EditorNoticeRow(
                            symbol: "exclamationmark.circle.fill",
                            title: validationMessage,
                            tint: PortfolixTheme.danger,
                            titleColor: PortfolixTheme.danger
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 36)
            .onChange(of: costMode) { oldMode, newMode in
                convertCostEntry(from: oldMode, to: newMode)
            }
            .onDisappear {
                assetLookupTask?.cancel()
            }

            Divider().overlay(PortfolixTheme.border)

            HStack(spacing: PortfolixSpacing.sm) {
                Spacer()

                Button(sheetText("取消", "Cancel")) {
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? sheetText("保存修改", "Save Changes") : sheetText("添加持仓", "Add Holding")) {
                    Task {
                        if await saveChanges() {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave || isSaving)
                .keyboardShortcut(.defaultAction)
            }
            .padding(PortfolixSpacing.xl)
        }
        .frame(width: 560, height: 650)
        .background {
            PortfolixSheetBackground()
        }
    }

    private var quantityChanged: Bool {
        guard
            let position = presentation.position,
            let enteredQuantity = decimalValue(quantity)
        else {
            return false
        }
        return enteredQuantity != position.quantity
    }

    private var canSave: Bool {
        guard
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let quantity = decimalValue(quantity),
            quantity > 0,
            let enteredCost = decimalValue(costValue),
            enteredCost >= 0,
            let latestPrice = decimalValue(latestPrice),
            latestPrice > 0
        else {
            return false
        }
        if
            let selectedAssetCandidate,
            !isManualAssetEntry,
            (
                category != selectedAssetCandidate.category
                    || costCurrency != selectedAssetCandidate.quoteCurrency
            )
        {
            return false
        }
        return true
    }

    private var holdingAmountText: String {
        guard
            let quantity = decimalValue(quantity),
            quantity >= 0,
            let latestPrice = decimalValue(latestPrice),
            latestPrice >= 0
        else {
            return "--"
        }
        return formatMoney(quantity * latestPrice, currency: costCurrency)
    }

    private var costChangeReminderText: String {
        let costLabel = costMode.title(language: language)
        return sheetText(
            "份额变化通常会影响成本，请确认上方的\(costLabel)是否仍然准确",
            "Share changes usually affect cost. Please confirm the \(costLabel) above is still accurate"
        )
    }

    private func saveChanges() async -> Bool {
        guard
            canSave,
            let quantity = decimalValue(quantity),
            let enteredCost = decimalValue(costValue),
            let latestPrice = decimalValue(latestPrice)
        else {
            validationMessage = sheetText("请完整填写有效的资产、份额、成本和价格", "Please complete valid asset, shares, cost, and price fields")
            return false
        }

        let averageCost = costMode == .totalCost ? enteredCost / quantity : enteredCost
        isSaving = true
        defer { isSaving = false }

        let refreshedQuote: AssetLookupCandidate?
        do {
            refreshedQuote = try await latestQuoteForSaveIfNeeded(enteredPrice: latestPrice)
        } catch {
            validationMessage = "\(sheetText("最新价格获取失败", "Failed to fetch latest price")): \(error.localizedDescription)"
            return false
        }

        let finalName = refreshedQuote?.name ?? name
        let finalSymbol = refreshedQuote?.symbol ?? symbol
        let finalCategory = refreshedQuote?.category ?? category
        let finalCostCurrency = refreshedQuote?.quoteCurrency ?? costCurrency
        let finalLatestPrice = refreshedQuote?.latestPrice ?? latestPrice
        let quoteMetadata = quoteMetadata(for: finalLatestPrice, refreshedQuote: refreshedQuote)

        if let refreshedQuote, let price = refreshedQuote.latestPrice {
            name = refreshedQuote.name
            symbol = refreshedQuote.symbol
            category = refreshedQuote.category
            costCurrency = refreshedQuote.quoteCurrency
            self.latestPrice = decimalString(price)
            selectedQuoteTime = refreshedQuote.quoteTime
        }

        do {
            if let position = presentation.position {
                try store.updatePosition(
                    id: position.id,
                    name: finalName,
                    symbol: finalSymbol,
                    category: finalCategory,
                    quantity: quantity,
                    averageCost: averageCost,
                    quoteCurrency: finalCostCurrency,
                    latestPrice: finalLatestPrice,
                    source: quoteMetadata.source,
                    quoteTime: quoteMetadata.quoteTime,
                    freshness: quoteMetadata.freshness
                )
            } else {
                try store.addPosition(
                    name: finalName,
                    symbol: finalSymbol,
                    category: finalCategory,
                    quantity: quantity,
                    averageCost: averageCost,
                    quoteCurrency: finalCostCurrency,
                    latestPrice: finalLatestPrice,
                    source: quoteMetadata.source,
                    quoteTime: quoteMetadata.quoteTime,
                    freshness: quoteMetadata.freshness
                )
            }
            return true
        } catch {
            validationMessage = error.localizedDescription
            return false
        }
    }

    private func latestQuoteForSaveIfNeeded(enteredPrice: Decimal) async throws -> AssetLookupCandidate? {
        guard
            let position = presentation.position,
            !isManualAssetEntry,
            selectedAssetCandidate == nil,
            enteredPrice == position.latestPrice
        else {
            return nil
        }

        let candidate = AssetLookupCandidate(
            name: position.name,
            symbol: position.symbol,
            category: position.category,
            quoteCurrency: position.quoteCurrency,
            latestPrice: position.latestPrice,
            upstreamSource: position.source,
            quoteTime: position.quoteTime
        )

        let resolved = try await resolvedLatestQuote(for: candidate)
        store.markDataSourceAvailable(for: resolved)
        return resolved.latestPrice == nil ? nil : resolved
    }

    private func quoteMetadata(
        for enteredPrice: Decimal,
        refreshedQuote: AssetLookupCandidate? = nil
    ) -> (source: String, quoteTime: String, freshness: Freshness) {
        if let refreshedQuote, refreshedQuote.latestPrice == enteredPrice {
            switch refreshedQuote.upstreamSource {
            case "local":
                return ("手工价格", "刚刚", .manual)
            case "OKX":
                return ("OKX", refreshedQuote.quoteTime ?? "刚刚", .updated)
            default:
                return (normalizedQuoteSource(refreshedQuote.upstreamSource, category: refreshedQuote.category), refreshedQuote.quoteTime ?? "刚刚", .updated)
            }
        }

        if isManualAssetEntry {
            return ("手工价格", "刚刚", .manual)
        }

        if
            let candidate = selectedAssetCandidate,
            candidate.latestPrice == enteredPrice
        {
            switch candidate.upstreamSource {
            case "local":
                return ("手工价格", "刚刚", .manual)
            case "OKX":
                return ("OKX", candidate.quoteTime ?? "刚刚", .updated)
            default:
                return (normalizedQuoteSource(candidate.upstreamSource, category: candidate.category), candidate.quoteTime ?? "刚刚", .updated)
            }
        }

        if
            let position = presentation.position,
            position.latestPrice == enteredPrice
        {
            return (position.source, position.quoteTime, position.freshness)
        }

        return ("手工价格", "刚刚", .manual)
    }

    private func convertCostEntry(from oldMode: CostEntryMode, to newMode: CostEntryMode) {
        guard
            oldMode != newMode,
            let quantity = decimalValue(quantity),
            quantity > 0,
            let enteredCost = decimalValue(costValue)
        else {
            return
        }

        switch (oldMode, newMode) {
        case (.averageCost, .totalCost):
            costValue = decimalString(enteredCost * quantity)
        case (.totalCost, .averageCost):
            costValue = decimalString(enteredCost / quantity)
        default:
            break
        }
    }

    private func scheduleAssetSearch(for rawQuery: String) {
        if let selectedAssetCandidate,
           rawQuery == selectedAssetCandidate.name
            || rawQuery.caseInsensitiveCompare(selectedAssetCandidate.symbol) == .orderedSame
        {
            return
        }
        selectedAssetCandidate = nil
        isManualAssetEntry = true
        assetLookupTask?.cancel()
        assetLookupGeneration += 1
        let generation = assetLookupGeneration
        selectedQuoteTime = nil
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            assetCandidates = []
            isSearchingAssets = false
            assetLookupMessage = nil
            return
        }

        isSearchingAssets = true
        assetLookupMessage = nil
        assetLookupTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let cashCandidates = CashAssetLookup.search(keyword: query)
            var candidates = deduplicated(cashCandidates)
            assetCandidates = candidates
            if !candidates.isEmpty {
                isSearchingAssets = false
            }

            var providerMessages: [String] = []
            await withTaskGroup(of: AssetLookupProviderResult.self) { group in
                group.addTask {
                    await Self.searchMarketDataAssets(keyword: query)
                }

                for await providerCandidates in group {
                    guard !Task.isCancelled, generation == assetLookupGeneration else {
                        group.cancelAll()
                        return
                    }
                    if let message = providerCandidates.message(language: language) {
                        providerMessages.append(message)
                    }
                    candidates = deduplicated(cashCandidates + candidates + providerCandidates.candidates)
                    assetCandidates = candidates
                    markAvailableDataSources(from: providerCandidates.candidates)
                    if !candidates.isEmpty {
                        isSearchingAssets = false
                    }
                }
            }
            guard !Task.isCancelled, generation == assetLookupGeneration else { return }
            assetCandidates = candidates
            assetLookupMessage = candidates.isEmpty ? providerMessages.first ?? emptySearchMessage : nil
            isSearchingAssets = false
        }
    }

    private func selectAssetCandidate(_ candidate: AssetLookupCandidate) {
        assetLookupTask?.cancel()
        assetLookupGeneration += 1
        assetCandidates = []
        assetLookupMessage = nil
        selectedAssetCandidate = candidate
        applyAssetCandidate(candidate)
        store.markDataSourceAvailable(for: candidate)

        guard candidate.latestPrice == nil else { return }
        isResolvingAsset = true
        assetLookupTask = Task {
            defer { isResolvingAsset = false }
            do {
                let resolved = try await resolvedLatestQuote(for: candidate)
                guard !Task.isCancelled else { return }
                applyAssetCandidate(resolved)
                store.markDataSourceAvailable(for: resolved)
                if resolved.latestPrice == nil {
                    assetLookupMessage = sheetText("未获取到最新价格，请手工填写", "Latest price unavailable. Please enter it manually")
                }
            } catch {
                guard !Task.isCancelled else { return }
                assetLookupMessage = sheetText("未获取到最新价格，请手工填写", "Latest price unavailable. Please enter it manually")
            }
        }
    }

    private static func searchMarketDataAssets(keyword: String) async -> AssetLookupProviderResult {
        do {
            return AssetLookupProviderResult(candidates: try await MarketDataAdapter.shared.searchAssets(keyword: keyword))
        } catch {
            return AssetLookupProviderResult(error: marketDataSearchFailureMessage(for: error))
        }
    }

    private static func marketDataSearchFailureMessage(for error: Error) -> AssetLookupProviderMessage {
        if let marketDataError = error as? MarketDataAdapterError {
            switch marketDataError {
            case .invalidKeyword:
                return AssetLookupProviderMessage(
                    chinese: "搜索关键字长度无效，请调整后重试。",
                    english: "The search keyword length is invalid. Adjust it and try again."
                )
            case .assetNotFound:
                return AssetLookupProviderMessage(
                    chinese: "未找到候选资产，可继续手工填写。",
                    english: "No matching asset was found. You can continue manually."
                )
            case .unsupportedAsset:
                return AssetLookupProviderMessage(
                    chinese: "该资产暂不支持自动行情，可继续手工填写。",
                    english: "Automatic quotes are not supported for this asset yet. You can continue manually."
                )
            case .responseTooLarge, .invalidResponse:
                return AssetLookupProviderMessage(
                    chinese: "行情数据返回内容暂不可用，可继续手工填写。",
                    english: "The market data response is unavailable. You can continue manually."
                )
            case let .requestFailed(message):
                return AssetLookupProviderMessage(
                    chinese: "行情查询失败：\(message)。可稍后重试或继续手工填写。",
                    english: "Market data lookup failed: \(message). Try again later or continue manually."
                )
            }
        }
        return AssetLookupProviderMessage(
            chinese: "行情数据暂不可用，可稍后重试或继续手工填写。",
            english: "Market data is unavailable. Try again later or continue manually."
        )
    }

    private func resolvedLatestQuote(for candidate: AssetLookupCandidate) async throws -> AssetLookupCandidate {
        try await MarketDataAdapter.shared.resolveAsset(candidate)
    }

    private func switchToManualEntry() {
        assetLookupTask?.cancel()
        assetLookupGeneration += 1
        selectedAssetCandidate = nil
        assetCandidates = []
        assetLookupMessage = nil
        selectedQuoteTime = nil
        isSearchingAssets = false
        isResolvingAsset = false
        isManualAssetEntry = true
    }

}

enum CashAssetLookup {
    static func search(keyword: String) -> [AssetLookupCandidate] {
        let normalizedKeyword = normalizedCashKeyword(keyword)
        return cashAssets.compactMap { entry in
            let searchTerms = entry.aliases + [entry.candidate.name, entry.candidate.symbol]
            let isMatch = searchTerms.contains { searchTerm in
                let normalizedSearchTerm = normalizedCashKeyword(searchTerm)
                return normalizedSearchTerm.contains(normalizedKeyword)
            }
            return isMatch ? entry.candidate : nil
        }
    }

    private static func normalizedCashKeyword(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .uppercased()
    }

    private static let cashAssets: [(candidate: AssetLookupCandidate, aliases: [String])] = [
        (
            AssetLookupCandidate(
                name: "现金人民币",
                symbol: "CNY",
                category: .cash,
                quoteCurrency: .cny,
                latestPrice: 1,
                upstreamSource: "local"
            ),
            ["人民币", "人民币现金", "RMB", "CNY"]
        ),
        (
            AssetLookupCandidate(
                name: "现金港币",
                symbol: "HKD",
                category: .cash,
                quoteCurrency: .hkd,
                latestPrice: 1,
                upstreamSource: "local"
            ),
            ["港币", "港元", "港币现金", "HKD"]
        ),
        (
            AssetLookupCandidate(
                name: "现金美元",
                symbol: "USD",
                category: .cash,
                quoteCurrency: .usd,
                latestPrice: 1,
                upstreamSource: "local"
            ),
            ["美元", "美金", "美元现金", "USD"]
        ),
        (
            AssetLookupCandidate(
                name: "现金 USDT",
                symbol: "USDT",
                category: .cash,
                quoteCurrency: .usdt,
                latestPrice: 1,
                upstreamSource: "local"
            ),
            ["USDT", "泰达币", "现金USDT"]
        ),
    ]
}

private extension PositionEditorSheet {
    func deduplicated(_ candidates: [AssetLookupCandidate]) -> [AssetLookupCandidate] {
        var seen: Set<AssetLookupCandidate.ID> = []
        return candidates.filter { seen.insert($0.id).inserted }
    }

    var emptySearchMessage: String {
        sheetText("未找到候选，可继续手工填写", "No candidates found. You can continue manually")
    }

    func markAvailableDataSources(from candidates: [AssetLookupCandidate]) {
        var markedCategories = Set<AssetCategory>()
        for candidate in candidates where candidate.upstreamSource != "local" && markedCategories.insert(candidate.category).inserted {
            store.markDataSourceAvailable(for: candidate)
        }
    }

    func applyAssetCandidate(_ candidate: AssetLookupCandidate) {
        selectedAssetCandidate = candidate
        isManualAssetEntry = false
        name = candidate.name
        symbol = candidate.symbol
        category = candidate.category
        costCurrency = candidate.quoteCurrency
        if let latestPrice = candidate.latestPrice {
            self.latestPrice = decimalString(latestPrice)
        }
        selectedQuoteTime = candidate.quoteTime
    }

    var priceMetadataText: String? {
        if let position = presentation.position, selectedAssetCandidate == nil {
            return "\(position.priceDateText(language: language)) · \(position.relativeUpdateText(now: store.relativeTimeNow, language: language))"
        }
        guard let selectedAssetCandidate else {
            return isManualAssetEntry ? sheetText("手工价格", "Manual price") : nil
        }
        if selectedAssetCandidate.upstreamSource == "local" {
            return sheetText("手工价格", "Manual price")
        }
        if let quoteTime = selectedQuoteTime ?? selectedAssetCandidate.quoteTime {
            let preview = Position(
                name: selectedAssetCandidate.name,
                symbol: selectedAssetCandidate.symbol,
                category: selectedAssetCandidate.category,
                quoteCurrency: selectedAssetCandidate.quoteCurrency,
                quantity: 1,
                averageCost: 1,
                latestPrice: selectedAssetCandidate.latestPrice ?? 1,
                marketValueCNY: 1,
                profitRate: 0,
                weeklyTrend: [1],
                source: selectedAssetCandidate.upstreamSource,
                quoteTime: quoteTime,
                freshness: .updated
            )
            return preview.priceDateText(language: language)
        }
        return sheetText("价格日期待获取", "Price date pending")
    }
}

private struct EditorNoticeRow: View {
    let symbol: String
    let title: String
    var message: String?
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

                if let message {
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

private struct AssetCandidateButton: View {
    let candidate: AssetLookupCandidate
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PortfolixSpacing.sm) {
                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    Text(candidate.name)
                        .foregroundStyle(PortfolixTheme.primaryText)
                        .lineLimit(1)
                    Text(candidate.symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(PortfolixTheme.tertiaryText)
                        .lineLimit(1)
                }

                Spacer()

                Text(candidate.category.title(language: language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(candidate.category.color)
                    .lineLimit(1)

                Text(sourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(PortfolixTheme.tertiaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, PortfolixSpacing.sm)
            .padding(.vertical, 7)
            .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var sourceLabel: String {
        switch candidate.upstreamSource {
        case "OKX": "OKX"
        case "local": localizedText("本地", "Local", language: language)
        default: localizedQuoteSource(normalizedQuoteSource(candidate.upstreamSource, category: candidate.category), language: language)
        }
    }

}

private func decimalString(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

private func decimalValue(_ value: String) -> Decimal? {
    Decimal(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
}

private enum CostEntryMode: String, CaseIterable, Identifiable {
    case totalCost
    case averageCost

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        if language == .english {
            switch self {
            case .totalCost: "Total Cost"
            case .averageCost: "Cost per Share"
            }
        } else {
            switch self {
            case .totalCost: "持仓总成本"
            case .averageCost: "持仓成本价"
            }
        }
    }
}
