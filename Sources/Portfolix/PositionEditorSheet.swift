import AppKit
import SwiftUI

private enum PositionEditorField: Hashable {
    case name
    case symbol
    case quantity
    case cost
    case fees
}

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
    @Environment(PortfolioStore.self) private var store
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
    @State private var didAttemptSave = false
    @State private var purchaseFees = ""
    @State private var purchaseCashID = ""
    @State private var purchaseAssetID = ""
    @State private var tradeID = UUID()
    @FocusState private var focusedField: PositionEditorField?

    init(presentation: PositionEditorPresentation) {
        self.presentation = presentation
        let position = presentation.position
        _name = State(initialValue: position?.name ?? "")
        _symbol = State(initialValue: position?.symbol ?? "")
        _category = State(initialValue: position?.category ?? .cnStock)
        _quantity = State(initialValue: "")
        _costValue = State(initialValue: position.map { decimalString($0.latestPrice) } ?? "")
        _costMode = State(initialValue: .averageCost)
        _costCurrency = State(initialValue: position?.quoteCurrency ?? .cny)
        _latestPrice = State(initialValue: position.map { decimalString($0.latestPrice) } ?? "")
        _validationMessage = State(initialValue: nil)
        _isManualAssetEntry = State(initialValue: position?.source == "手工价格" || position == nil)
        _selectedQuoteTime = State(initialValue: position?.quoteTime)
        _purchaseAssetID = State(initialValue: position?.id.uuidString ?? "")
    }

    private var selectedPosition: Position? { store.positions.first { $0.id.uuidString == purchaseAssetID } }
    private var locksAssetIdentity: Bool { !purchaseAssetID.isEmpty }
    private var purchaseCashOptions: [Position] { store.positions.filter { $0.category == .cash && $0.quoteCurrency == costCurrency } }

    private var language: AppLanguage {
        store.appLanguage
    }

    private func sheetText(_ chinese: String, _ english: String) -> String {
        localizedText(chinese, english, language: language)
    }

    private var usesFixedCashPricing: Bool {
        category == .cash
    }

    private var additionCopy: AssetAdditionCopy {
        AssetAdditionCopy(isExistingAsset: locksAssetIdentity, isCash: usesFixedCashPricing, language: language)
    }

    private var footerNotices: [SheetNotice] {
        if isSaving { return [.init(message: sheetText("正在添加资产", "Adding asset"), kind: .progress)] }
        guard !locksAssetIdentity else { return [] }
        if isSearchingAssets || isResolvingAsset {
            return [.init(message: isResolvingAsset ? sheetText("正在获取最新价格", "Fetching latest price") : sheetText("正在查询数据源", "Searching data sources"), kind: .progress)]
        }
        return assetLookupMessage.map { [.init(message: $0, kind: .information)] } ?? []
    }

    private func editorTextField(
        title: String,
        text: Binding<String>,
        field: PositionEditorField,
        placeholder: String,
        isLocked: Bool = false
    ) -> some View {
        LabeledContent {
            Group {
                if isLocked {
                    Text(text.wrappedValue)
                        .font(PortfolixTypography.body)
                        .monospacedDigit()
                        .foregroundStyle(PortfolixTheme.secondaryText)
                        .lineLimit(1)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: AssetEntryLayout.valueFieldHeight,
                            alignment: .trailing
                        )
                } else {
                    AssetEntryTextField(title: title, text: text, field: field, focus: $focusedField,
                        placeholder: placeholder, language: language,
                        numeric: field == .quantity || field == .cost || field == .fees,
                        isInvalid: shouldHighlight(field))
                }
            }
            .frame(
                width: AssetEntryLayout.valueFieldWidth,
                height: AssetEntryLayout.valueFieldHeight,
                alignment: .trailing
            )
        } label: {
            AssetEntryFieldLabel(
                title: title,
                isInvalid: shouldHighlight(field),
                showsRequiredIndicator: !isLocked && field != .fees
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: sheetText("添加资产", "Add Asset"),
                symbol: "square.and.pencil"
            )

            Divider().overlay(PortfolixTheme.border)

            Form {
                LabeledContent(sheetText("资产", "Asset")) {
                    PortfolixGlassMenuPicker(title: sheetText("资产", "Asset"), selection: $purchaseAssetID,
                        options: [""] + store.positions.map { $0.id.uuidString },
                        optionTitle: { id in
                            store.positions.first { $0.id.uuidString == id }?.name
                                ?? sheetText("新资产", "New Asset")
                        })
                }
                .onChange(of: purchaseAssetID) { _, value in
                    assetLookupTask?.cancel()
                    assetLookupGeneration += 1
                    assetCandidates = []
                    selectedAssetCandidate = nil
                    let position = store.positions.first { $0.id.uuidString == value }
                    name = position?.name ?? ""; symbol = position?.symbol ?? ""
                    category = position?.category ?? .cnStock; costCurrency = position?.quoteCurrency ?? .cny
                    costValue = position.map { decimalString($0.latestPrice) } ?? ""
                    latestPrice = costValue; quantity = ""; costMode = .averageCost
                    selectedQuoteTime = position?.quoteTime
                    isManualAssetEntry = position?.source == "手工价格" || position == nil
                    purchaseCashID = ""
                    purchaseFees = ""
                    validationMessage = nil
                    didAttemptSave = false
                }
                Section {
                    LabeledContent(sheetText("资产类别", "Asset Type")) {
                        PortfolixGlassMenuPicker(
                            title: sheetText("资产类别", "Asset Type"),
                            selection: $category,
                            options: AssetCategory.allCases,
                            optionTitle: { $0.title(language: language) }
                        )
                    }
                    .disabled(locksAssetIdentity || !isManualAssetEntry)
                    .onChange(of: category) { _, _ in
                        handleCategoryChange()
                    }

                    if !locksAssetIdentity, !isManualAssetEntry {
                        HStack(spacing: PortfolixSpacing.sm) {
                            Label(sheetText("类型与计价币种由数据源确定", "Type and currency are set by the data source"), systemImage: "lock.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(PortfolixTheme.secondaryText)

                            Spacer()

                            Button(sheetText("改为手工录入", "Use Manual Entry")) {
                                switchToManualEntry()
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                    }

                    editorTextField(
                        title: sheetText("资产名称", "Asset Name"),
                        text: $name,
                        field: .name,
                        placeholder: sheetText("输入名称搜索", "Search by name"),
                        isLocked: locksAssetIdentity
                    )
                        .onChange(of: name) { _, value in
                            if !locksAssetIdentity {
                                scheduleAssetSearch(for: value)
                            }
                        }

                    editorTextField(
                        title: sheetText("资产代码", "Asset Code"),
                        text: $symbol,
                        field: .symbol,
                        placeholder: sheetText("输入代码搜索", "Search by code"),
                        isLocked: locksAssetIdentity
                    )
                        .onChange(of: symbol) { _, value in
                            if !locksAssetIdentity {
                                scheduleAssetSearch(for: value)
                            }
                        }

                    if !locksAssetIdentity, !assetCandidates.isEmpty {
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

                }
                .accessibilityElement(children: .contain)

                editorTextField(
                    title: additionCopy.quantityTitle,
                    text: $quantity,
                    field: .quantity,
                    placeholder: additionCopy.quantityPlaceholder
                )
                .onChange(of: quantity) { _, _ in
                    validationMessage = nil
                    synchronizePurchaseReference()
                }

                if !usesFixedCashPricing {
                    LabeledContent(sheetText("成本录入方式", "Cost Input Method")) {
                        PortfolixGlassSegmentedPicker(
                            title: sheetText("成本录入方式", "Cost Input Method"),
                            selection: $costMode,
                            options: CostEntryMode.allCases,
                            optionTitle: { $0 == .totalCost ? sheetText("总成本", "Total Cost") : sheetText("成本价", "Unit Cost") },
                            width: AssetEntryLayout.valueFieldWidth
                        )
                    }

                    editorTextField(
                    title: additionCopy.costTitle(mode: costMode),
                    text: $costValue,
                    field: .cost,
                    placeholder: additionCopy.costPlaceholder(mode: costMode),
                    isLocked: usesFixedCashPricing
                    )
                    .onChange(of: costValue) { _, _ in
                        validationMessage = nil
                        synchronizePurchaseReference()
                    }
                }

                LabeledContent(sheetText("计价与成本币种", "Price and Cost Currency")) {
                    PortfolixGlassSegmentedPicker(
                        title: sheetText("计价与成本币种", "Price and Cost Currency"),
                        selection: $costCurrency,
                        options: DisplayCurrency.allCases,
                        optionTitle: { $0.rawValue },
                        width: AssetEntryLayout.valueFieldWidth
                    )
                }
                .disabled(locksAssetIdentity || !isManualAssetEntry)

                    Section {
                        if !usesFixedCashPricing {
                            editorTextField(title: sheetText("手续费", "Fees"), text: $purchaseFees, field: .fees,
                                placeholder: sheetText("选填，默认为 0", "Optional, defaults to 0"))
                            LabeledContent(sheetText("资金来源", "Funding Source")) {
                                PortfolixGlassMenuPicker(title: sheetText("资金来源", "Funding Source"), selection: $purchaseCashID,
                                    options: [""] + purchaseCashOptions.map { $0.id.uuidString },
                                    optionTitle: { id in purchaseCashOptions.first { $0.id.uuidString == id }?.name ?? additionCopy.externalFundsTitle })
                            }
                        }
                        LabeledContent(additionCopy.resultingQuantityTitle) {
                            let total = (selectedPosition?.quantity ?? 0) + (decimalValue(quantity) ?? 0)
                            Text(usesFixedCashPricing ? formatMoney(total, currency: costCurrency) : decimalString(total)).monospacedDigit()
                        }
                        if !usesFixedCashPricing {
                            LabeledContent(additionCopy.totalCostTitle) {
                                let gross = costMode == .totalCost ? (decimalValue(costValue) ?? 0) : (decimalValue(quantity) ?? 0) * (decimalValue(costValue) ?? 0)
                                Text(formatMoney(PositionClosureMath.rounded(gross, currency: costCurrency) + (PositionClosureMath.decimal(purchaseFees) ?? 0), currency: costCurrency)).monospacedDigit()
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)

            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .environment(\.defaultMinListRowHeight, AssetEntryLayout.minimumRowHeight)
            .disabled(isSaving)
            .onChange(of: costMode) { oldMode, newMode in
                convertCostEntry(from: oldMode, to: newMode)
            }
            .onDisappear {
                assetLookupTask?.cancel()
            }
            .onAppear { if usesFixedCashPricing { applyFixedCashPricing() } }
            .onChange(of: costCurrency) { _, _ in purchaseCashID = "" }
            .onChange(of: purchaseCashID) { _, _ in validationMessage = nil }
            .onChange(of: purchaseFees) { _, _ in validationMessage = nil }

            Divider().overlay(PortfolixTheme.border)

            SheetActionFooter(errorMessage: validationMessage, notices: footerNotices) {
                Button(sheetText("取消", "Cancel")) {
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)

                Button(sheetText("确认添加", "Add Asset")) {
                    let window = NSApp.keyWindow
                    Task {
                        if await saveChanges(committing: window) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 620, height: usesFixedCashPricing ? 560 : 720)
        .background {
            PortfolixSheetBackground()
        }
    }

    private var invalidRequiredFields: Set<PositionEditorField> {
        var fields: Set<PositionEditorField> = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.insert(.name)
        }
        if symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.insert(.symbol)
        }
        if decimalValue(quantity).map({ $0 > 0 }) != true {
            fields.insert(.quantity)
        }
        if !usesFixedCashPricing, decimalValue(costValue).map({ $0 >= 0 }) != true {
            fields.insert(.cost)
        }
        if !usesFixedCashPricing, PositionTradeInput.fees(purchaseFees).map({ $0 >= 0 }) != true {
            fields.insert(.fees)
        }
        return fields
    }

    private func synchronizePurchaseReference() {
        guard isManualAssetEntry, !locksAssetIdentity,
              let entered = PositionClosureMath.decimal(costValue), entered > 0 else { return }
        if costMode == .averageCost { latestPrice = decimalString(entered) }
        else if let units = PositionClosureMath.decimal(quantity), units > 0 { latestPrice = decimalString(entered / units) }
    }

    private var firstInvalidField: PositionEditorField? {
        [.name, .symbol, .quantity, .cost, .fees].first { invalidRequiredFields.contains($0) }
    }

    private func shouldHighlight(_ field: PositionEditorField) -> Bool {
        didAttemptSave && invalidRequiredFields.contains(field)
    }

    private var canSave: Bool {
        guard invalidRequiredFields.isEmpty else {
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

    private var currentPriceText: String {
        guard
            let latestPrice = decimalValue(latestPrice),
            latestPrice > 0
        else {
            return "--"
        }
        return decimalString(latestPrice)
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

    private func saveChanges(committing window: NSWindow?) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        focusedField = nil
        guard await SheetEditingCommit.commit(in: window) else {
            validationMessage = sheetText("无法结束当前输入，请检查后重试。", "Unable to finish editing. Check the current field and try again.")
            return false
        }
        if usesFixedCashPricing {
            applyFixedCashPricing()
        }
        guard
            canSave,
            let quantity = decimalValue(quantity),
            let enteredCost = decimalValue(costValue)
        else {
            didAttemptSave = true
            switch firstInvalidField {
            case .name: validationMessage = sheetText("请填写资产名称。", "Enter an asset name.")
            case .symbol: validationMessage = sheetText("请填写资产代码。", "Enter an asset code.")
            case .quantity: validationMessage = sheetText("\(additionCopy.quantityTitle)必须大于 0。", "Enter a quantity or amount greater than 0.")
            case .cost: validationMessage = sheetText("成本须为 0 或正数。", "Cost must be zero or positive.")
            case .fees: validationMessage = sheetText("手续费须为 0 或正数。", "Fees must be zero or positive.")
            case nil: validationMessage = sheetText("资产类别或币种与数据源不一致，请重新选择资产。", "The asset type or currency does not match its data source. Select the asset again.")
            }
            focusedField = firstInvalidField
            return false
        }

        guard
            let latestPrice = decimalValue(latestPrice),
            latestPrice > 0
        else {
            didAttemptSave = true
            validationMessage = sheetText(
                "当前价格尚未获取，请先从数据候选中选择资产。",
                "Current price is not available yet. Select an asset from data candidates first."
            )
            focusedField = nil
            return false
        }

        didAttemptSave = false
        let submittedPosition = selectedPosition
        let submittedAssetID = purchaseAssetID
        let averageCost = costMode == .totalCost ? enteredCost / quantity : enteredCost
        let refreshedQuote: AssetLookupCandidate?
        do {
            refreshedQuote = try await latestQuoteForSaveIfNeeded(enteredPrice: latestPrice)
        } catch {
            validationMessage = "\(sheetText("最新价格获取失败", "Failed to fetch latest price")): \(error.localizedDescription)"
            return false
        }

        let finalName = submittedPosition?.name ?? refreshedQuote?.name ?? name
        let finalSymbol = submittedPosition?.symbol ?? refreshedQuote?.symbol ?? symbol
        let finalCategory = submittedPosition?.category ?? refreshedQuote?.category ?? category
        let finalCostCurrency = submittedPosition?.quoteCurrency ?? refreshedQuote?.quoteCurrency ?? costCurrency
        let finalLatestPrice = refreshedQuote?.latestPrice ?? latestPrice
        let quoteMetadata = quoteMetadata(for: finalLatestPrice, refreshedQuote: refreshedQuote)

        if let refreshedQuote, let price = refreshedQuote.latestPrice {
            if !locksAssetIdentity {
                name = refreshedQuote.name
                symbol = refreshedQuote.symbol
                category = refreshedQuote.category
                costCurrency = refreshedQuote.quoteCurrency
            }
            self.latestPrice = decimalString(price)
            selectedQuoteTime = refreshedQuote.quoteTime
        }

        do {
            guard submittedAssetID == purchaseAssetID else { throw PositionTradeError.changed }
            guard let fees = PositionTradeInput.fees(purchaseFees), fees >= 0 else { throw PositionTradeError.invalidInput }
            if locksAssetIdentity, submittedPosition == nil { throw PositionTradeError.changed }
            if !locksAssetIdentity, store.positions.contains(where: {
                $0.symbol.caseInsensitiveCompare(finalSymbol) == .orderedSame && $0.category == finalCategory
            }) {
                throw PositionValidationError.duplicateAsset
            }
            let cashID = usesFixedCashPricing ? nil : UUID(uuidString: purchaseCashID)
            if !usesFixedCashPricing, !purchaseCashID.isEmpty, cashID == nil { throw PositionTradeError.invalidInput }
            try PositionInputValidator.validateProviderIdentity(category: finalCategory, quoteCurrency: finalCostCurrency, source: quoteMetadata.source)
            let asset = submittedPosition ?? Position(name: finalName.trimmingCharacters(in: .whitespacesAndNewlines),
                symbol: finalSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), category: finalCategory,
                quoteCurrency: finalCostCurrency, quantity: quantity, averageCost: averageCost,
                latestPrice: finalLatestPrice, marketValueCNY: quantity * finalLatestPrice / finalCostCurrency.rateFromCNY,
                profitRate: 0, weeklyTrend: Array(repeating: finalLatestPrice.doubleValue, count: 7),
                source: quoteMetadata.source, quoteTime: quoteMetadata.quoteTime, freshness: quoteMetadata.freshness)
            try store.recordTrade(id: tradeID, side: cashID == nil ? .add : .buy, position: asset, quantity: quantity,
                price: usesFixedCashPricing ? 1 : averageCost, fees: usesFixedCashPricing ? 0 : fees,
                tradeDate: .now, cashPositionID: cashID)
            return true
        } catch {
            validationMessage = (error as? PositionTradeError)?.message(language: language) ?? error.localizedDescription
            return false
        }
    }

    private func latestQuoteForSaveIfNeeded(enteredPrice: Decimal) async throws -> AssetLookupCandidate? {
        guard
            let position = selectedPosition,
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
            let position = selectedPosition,
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

    private func handleCategoryChange() {
        guard isManualAssetEntry, !locksAssetIdentity else { return }
        validationMessage = nil
        selectedAssetCandidate = nil
        selectedQuoteTime = nil
        assetCandidates = []
        assetLookupMessage = nil
        costCurrency = defaultCurrency(for: category)
        if usesFixedCashPricing {
            applyFixedCashPricing()
        }
        scheduleAssetSearch(for: preferredAssetLookupQuery)
    }

    private func applyFixedCashPricing() {
        costMode = .averageCost
        costValue = "1"
        latestPrice = "1"
    }

    private var preferredAssetLookupQuery: String {
        let symbolQuery = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if !symbolQuery.isEmpty {
            return symbolQuery
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
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
        validationMessage = nil
        assetLookupTask?.cancel()
        assetLookupGeneration += 1
        let generation = assetLookupGeneration
        selectedQuoteTime = nil
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchCategory = category
        let lookupLanguage = language
        let emptyMessage = emptySearchMessage
        guard !query.isEmpty else {
            assetCandidates = []
            isSearchingAssets = false
            assetLookupMessage = nil
            return
        }

        isSearchingAssets = true
        assetLookupMessage = nil
        assetLookupTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }

            let localCandidates = searchCategory == .cash ? CashAssetLookup.search(keyword: query)
                : searchCategory == .crypto ? CashAssetLookup.stablecoins(keyword: query) : []
            var candidates = Self.filteredLookupCandidates(localCandidates, category: searchCategory)
            assetCandidates = candidates
            if !candidates.isEmpty || searchCategory == .cash {
                isSearchingAssets = false
            }
            if searchCategory == .cash || !candidates.isEmpty {
                assetLookupMessage = candidates.isEmpty ? emptyMessage : nil
                return
            }

            var providerMessages: [String] = []
            await withTaskGroup(of: AssetLookupProviderResult.self) { group in
                group.addTask {
                    await Self.searchMarketDataAssets(keyword: query, category: searchCategory)
                }

                for await providerCandidates in group {
                    guard !Task.isCancelled, generation == assetLookupGeneration else {
                        group.cancelAll()
                        return
                    }
                    if let message = providerCandidates.message(language: lookupLanguage) {
                        providerMessages.append(message)
                    }
                    candidates = Self.filteredLookupCandidates(candidates + providerCandidates.candidates, category: searchCategory)
                    assetCandidates = candidates
                    if !candidates.isEmpty {
                        isSearchingAssets = false
                    }
                }
            }
            guard !Task.isCancelled, generation == assetLookupGeneration else { return }
            assetCandidates = candidates
            assetLookupMessage = candidates.isEmpty ? providerMessages.first ?? emptyMessage : nil
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

        guard candidate.latestPrice == nil else { return }
        isResolvingAsset = true
        assetLookupTask = Task {
            defer { isResolvingAsset = false }
            do {
                let resolved = try await resolvedLatestQuote(for: candidate)
                guard !Task.isCancelled else { return }
                applyAssetCandidate(resolved)
                if resolved.latestPrice == nil {
                    assetLookupMessage = sheetText(
                        "未获取到最新价格，请稍后重试或继续选择其他候选",
                        "Latest price unavailable. Try again later or choose another candidate."
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                assetLookupMessage = sheetText(
                    "未获取到最新价格，请稍后重试或继续选择其他候选",
                    "Latest price unavailable. Try again later or choose another candidate."
                )
            }
        }
    }

    private static func searchMarketDataAssets(keyword: String, category: AssetCategory) async -> AssetLookupProviderResult {
        do {
            return AssetLookupProviderResult(candidates: try await MarketDataAdapter.shared.searchAssets(keyword: keyword, category: category))
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
        if usesFixedCashPricing {
            applyFixedCashPricing()
        }
    }

}

enum CashAssetLookup {
    static func stablecoins(keyword: String) -> [AssetLookupCandidate] {
        let keyword = normalizedCashKeyword(keyword)
        return cashAssets.filter { entry in
            entry.candidate.symbol == "USDT"
                && (entry.aliases + [entry.candidate.name, entry.candidate.symbol]).contains { normalizedCashKeyword($0) == keyword }
        }.map(\.candidate)
    }

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
    static func deduplicated(_ candidates: [AssetLookupCandidate]) -> [AssetLookupCandidate] {
        var seen: Set<AssetLookupCandidate.ID> = []
        return candidates.filter { seen.insert($0.id).inserted }
    }

    static func filteredLookupCandidates(_ candidates: [AssetLookupCandidate], category: AssetCategory) -> [AssetLookupCandidate] {
        Array(deduplicated(candidates.filter {
            $0.category == category || (category == .crypto && $0.category == .cash && $0.symbol == "USDT")
        }).prefix(10))
    }

    var emptySearchMessage: String {
        sheetText(
            "未找到\(category.title(language: language))候选，可继续手工填写",
            "No \(category.title(language: language)) candidates found. You can continue manually"
        )
    }

    func defaultCurrency(for category: AssetCategory) -> DisplayCurrency {
        switch category {
        case .cnStock, .bStock, .fund, .cash:
            .cny
        case .hkStock:
            .hkd
        case .usStock:
            .usd
        case .crypto:
            .usdt
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
        if candidate.category == .cash {
            applyFixedCashPricing()
        }
        selectedQuoteTime = candidate.quoteTime
    }

    var hasPriceMetadata: Bool {
        priceMetadataText(now: .now) != nil
    }

    func priceMetadataText(now: Date) -> String? {
        if let position = selectedPosition, selectedAssetCandidate == nil {
            return "\(position.priceDateText(language: language)) · \(position.relativeUpdateText(now: now, language: language))"
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
        }
        .buttonStyle(QuietButtonStyle(preservesLabelSize: true))
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
    PositionClosureMath.decimal(value)
}

enum CostEntryMode: String, CaseIterable, Identifiable {
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
