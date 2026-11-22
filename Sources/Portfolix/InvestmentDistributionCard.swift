import AppKit
import SwiftUI

struct InvestmentCloudCard: View {
    @Environment(PortfolioStore.self) private var store
    var contentHeight: CGFloat = PortfolixLayout.dashboardHeroContentHeight
    private var mode: InvestmentCloudMode { store.investmentCloudMode }

    var body: some View {
        @Bindable var store = store

        Panel {
            VStack(alignment: .leading, spacing: 0) {
                InvestmentCloudHeader(
                    mode: $store.investmentCloudMode, language: store.appLanguage,
                    helpText: store.investmentDistributionHelpText,
                    isUpdating: mode == .distribution && store.isUpdatingInvestmentDistribution
                )
                Group {
                    if mode == .dailyProfit {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            content(asOf: context.date)
                        }
                    } else {
                        content(asOf: .now)
                    }
                }
                .padding(.top, PortfolixSpacing.sm)
            }
            .frame(height: contentHeight, alignment: .topLeading)
        }
        .task(id: mode == .distribution ? store.investmentDistributionRefreshID : "daily_profit") {
            if mode == .distribution { store.refreshInvestmentDistributionIfNeeded() }
        }
    }

    @ViewBuilder private func content(asOf date: Date) -> some View {
        let rawItems: [InvestmentCloudItem] = mode == .dailyProfit
            ? store.investmentCloudDailyProfitItems(asOf: date)
            : store.investmentDistributionItems.map(InvestmentCloudItem.init(distribution:))
        let weight: (InvestmentCloudItem) -> Double = mode == .dailyProfit
            ? { $0.marketValueCNY?.doubleValue ?? 0 }
            : { $0.distributionPercentage ?? $0.areaWeight }
        let prepared = InvestmentCloudEngine.displayItems(
            rawItems,
            minimumShare: 0.02,
            maximumItems: mode == .dailyProfit ? 12 : 8,
            weight: weight
        )
        if prepared.isEmpty {
            Text(mode == .dailyProfit
                 ? localizedText("暂无今日盈亏", "No P&L for today", language: store.appLanguage)
                 : localizedText("暂无投资分布", "No investment distribution yet", language: store.appLanguage))
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(PortfolixTheme.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            InvestmentCloudMapView(
                items: prepared,
                rawItems: rawItems,
                weights: prepared.map(weight),
                mode: mode,
                currency: store.displayCurrency,
                language: store.appLanguage,
                performanceColorScheme: store.performanceColorScheme
            )
            .id(mode)
        }
    }
}

struct InvestmentCloudHeader: View {
    @Binding var mode: InvestmentCloudMode
    let language: AppLanguage
    let helpText: String
    let isUpdating: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PortfolixSpacing.sm) {
                title
                Spacer(minLength: PortfolixSpacing.sm)
                controls
            }
            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                title
                HStack(spacing: PortfolixSpacing.sm) {
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
    }

    private var title: some View {
        SectionHeader(
            title: localizedText("投资云图", "Investment Map", language: language),
            symbol: "square.grid.3x3.fill", helpText: helpText
        ) {}
        .fixedSize(horizontal: true, vertical: false)
    }

    private var controls: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            if isUpdating {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(localizedText("更新投资分布", "Updating investment distribution", language: language))
            }
            PortfolixGlassSegmentedPicker(
                title: localizedText("云图模式", "Map mode", language: language),
                selection: $mode, options: InvestmentCloudMode.allCases,
                optionTitle: { $0.title(language: language) }
            )
        }
    }
}

/// Summary row + treemap + legend. The summary row doubles as the hover/selection
/// readout so tiles never have to carry floating tooltips that cover neighbours.
struct InvestmentCloudMapView: View {
    let items: [InvestmentCloudItem]
    let rawItems: [InvestmentCloudItem]
    let weights: [Double]
    let mode: InvestmentCloudMode
    let currency: DisplayCurrency
    let language: AppLanguage
    let performanceColorScheme: PerformanceColorScheme

    @State private var highlightedID: InvestmentCloudItem.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeItem: InvestmentCloudItem? {
        guard let activeID = highlightedID else { return nil }
        return items.first { $0.id == activeID }
    }

    private var convertedTotal: Decimal {
        rawItems.reduce(Decimal(0)) { $0 + $1.amountCNY } * currency.rateFromCNY
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow
                .frame(height: 18, alignment: .leading)
            InvestmentCloudTreemap(
                items: items, currency: currency, language: language,
                performanceColorScheme: performanceColorScheme,
                weights: weights,
                highlightedID: $highlightedID,
                showsHoverTooltip: false
            )
            .padding(.top, PortfolixSpacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if mode == .distribution {
                legend
                    .padding(.top, PortfolixSpacing.sm)
                    .frame(height: 16, alignment: .leading)
            }
        }
    }

    // MARK: - Summary row

    @ViewBuilder private var summaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.sm) {
            ZStack(alignment: .leading) {
                if let item = activeItem {
                    detailContent(item)
                        .transition(.opacity)
                } else {
                    defaultSummary
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
            Group {
                if activeItem == nil {
                    countText
                }
            }
            .transition(.opacity)
        }
        .lineLimit(1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: summaryAnimationTrigger)
    }

    /// Crossfade the summary when the highlighted tile changes, as in the P&L calendar.
    private var summaryAnimationTrigger: String {
        activeItem?.id ?? "default"
    }

    @ViewBuilder private var defaultSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.sm) {
            Text(mode == .dailyProfit
                 ? localizedText("今日盈亏", "Today's P&L", language: language)
                 : localizedText("总市值", "Total value", language: language))
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(PortfolixTheme.secondary)
            Text(mode == .dailyProfit
                 ? formatSignedMoney(convertedTotal, currency: currency)
                 : formatMoney(convertedTotal, currency: currency))
                .font(PortfolixTypography.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(mode == .dailyProfit
                                 ? PortfolixTheme.performanceStatusText(for: convertedTotal, scheme: performanceColorScheme)
                                 : PortfolixTheme.text)
                .portfolixNumericTransition(convertedTotal)
        }
    }

    @ViewBuilder private var countText: some View {
        if mode == .dailyProfit {
            let up = items.filter { $0.amountCNY > 0 }.count
            let down = items.filter { $0.amountCNY < 0 }.count
            Text(localizedText("涨 \(up) · 跌 \(down)", "\(up) up · \(down) down", language: language))
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.tertiary)
        } else {
            let categories = items.filter { !$0.isAggregated }.count
            Text(localizedText("\(categories) 类", "\(categories) groups", language: language))
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.tertiary)
        }
    }

    @ViewBuilder
    private func detailContent(_ item: InvestmentCloudItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.xs) {
            Text(item.title(language: language))
                .font(PortfolixTypography.captionEmphasis)
                .foregroundStyle(PortfolixTheme.secondary)

            if let marketValue = item.marketValueCNY {
                Text("·")
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                let valueText = formatMoney(marketValue * currency.rateFromCNY, currency: currency)
                Text(valueText)
                    .font(PortfolixTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(PortfolixTheme.text)
                    .portfolixNumericTransition(valueText)
            }

            if mode == .dailyProfit {
                Text("·")
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                let profitText = formatSignedMoney(item.amountCNY * currency.rateFromCNY, currency: currency)
                Text(profitText)
                    .font(PortfolixTypography.captionEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(PortfolixTheme.performanceStatusText(for: item.amountCNY, scheme: performanceColorScheme))
                    .portfolixNumericTransition(profitText)
                if let rate = itemRate(item) {
                    let rateText = formatPercent(rate)
                    Text(rateText)
                        .font(PortfolixTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(PortfolixTheme.performanceStatusText(for: item.amountCNY, scheme: performanceColorScheme))
                        .portfolixNumericTransition(rateText)
                }
            } else if let percentage = item.distributionPercentage {
                Text("·")
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                let percentageText = String(format: "%.1f%%", percentage)
                Text(percentageText)
                    .font(PortfolixTypography.captionEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(PortfolixTheme.text)
                    .portfolixNumericTransition(percentageText)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private func itemRate(_ item: InvestmentCloudItem) -> Decimal? {
        if let rate = item.dailyProfitRate, !item.isAggregated { return rate }
        guard let marketValue = item.marketValueCNY else { return nil }
        let base = marketValue - item.amountCNY
        guard base != 0 else { return nil }
        return item.amountCNY / base * 100
    }

    @ViewBuilder private var legend: some View {
        let categories = items.filter { !$0.isAggregated }
        HStack(spacing: PortfolixSpacing.md) {
            ForEach(Array(categories.prefix(4))) { item in
                HStack(spacing: PortfolixSpacing.xs) {
                    Circle()
                        .fill(item.assetClass.area)
                        .frame(width: 6, height: 6)
                    Text(item.title(language: language))
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondary)
                        .lineLimit(1)
                }
            }
            if categories.count > 4 {
                Text(localizedText("+\(categories.count - 4) 类", "+\(categories.count - 4) groups", language: language))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct InvestmentCloudTreemap: View {
    let items: [InvestmentCloudItem]
    let currency: DisplayCurrency
    let language: AppLanguage
    var performanceColorScheme: PerformanceColorScheme = .greenUpRedDown
    var weights: [Double]?
    var highlightedID: Binding<InvestmentCloudItem.ID?>?
    var showsHoverTooltip: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var internalHighlightedID: InvestmentCloudItem.ID?

    private var activeHighlightedID: InvestmentCloudItem.ID? {
        highlightedID?.wrappedValue ?? internalHighlightedID
    }

    private func setHighlightedID(_ id: InvestmentCloudItem.ID?) {
        if let highlightedID {
            highlightedID.wrappedValue = id
        } else {
            internalHighlightedID = id
        }
    }

    private var resolvedWeights: [Double] {
        if let weights, weights.count == items.count { return weights }
        return items.map(\.areaWeight)
    }

    var body: some View {
        GeometryReader { geometry in
            let rectangles = PortfolioChartLayout.treemap(
                weights: resolvedWeights, in: CGRect(origin: .zero, size: geometry.size),
                spacing: PortfolixLayout.dataTileSpacing
            )
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index < rectangles.count {
                        let rect = rectangles[index]
                        if rect.width > 0, rect.height > 0 {
                            tile(item: item, rect: rect)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    let hit = rectangles.enumerated().first { $0.element.contains(location) }
                        .flatMap { items.indices.contains($0.offset) ? items[$0.offset].id : nil }
                    setHighlightedID(hit)
                case .ended:
                    setHighlightedID(nil)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsHoverTooltip,
                   let index = items.firstIndex(where: { $0.id == activeHighlightedID }), index < rectangles.count,
                   shouldShowHover(item: items[index], rect: rectangles[index]) {
                    let frame = hoverFrame(item: items[index], tile: rectangles[index], bounds: geometry.size)
                    hoverDetails(items[index])
                        .frame(width: frame.width, alignment: .leading)
                        .offset(x: frame.minX, y: frame.minY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if let activeHighlightedID, !ids.contains(activeHighlightedID) {
                setHighlightedID(nil)
            }
        }
    }

    private func tile(item: InvestmentCloudItem, rect: CGRect) -> some View {
        let dimmed: Bool = {
            guard let activeHighlightedID else { return false }
            return activeHighlightedID != item.id
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                .fill(fillColor(for: item))
                .opacity(dimmed ? 0.62 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: dimmed)
            if canShowLabels(item: item, rect: rect) {
                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    Text(item.title(language: language))
                        .font(PortfolixTypography.captionEmphasis)
                        .lineLimit(2)
                    if item.mode == .dailyProfit {
                        let amount = amountLabelText(item, rect: rect)
                        Text(amount)
                            .font(PortfolixTypography.captionEmphasis)
                            .monospacedDigit()
                            .portfolixNumericTransition(amount)
                            .lineLimit(1)
                            .foregroundStyle(tileTextColor(for: item))
                    } else if let percentage = item.distributionPercentage {
                        Text(String(format: "%.1f%%", percentage))
                            .font(PortfolixTypography.captionEmphasis)
                            .monospacedDigit()
                            .portfolixNumericTransition(percentage)
                            .foregroundStyle(tileTitleColor(for: item))
                    }
                }
                .foregroundStyle(tileTitleColor(for: item))
                .padding(PortfolixSpacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityHint(localizedText("悬停查看详情", "Hover for details", language: language))
    }

    private func fillColor(for item: InvestmentCloudItem) -> Color {
        if item.mode == .dailyProfit {
            return PortfolixTheme.neutralWash
        }
        if item.isAggregated {
            return PortfolixTheme.neutralWash
        }
        return item.assetClass.pale
    }

    /// Use the matching ink on pale distribution tiles and standard text on neutral tiles.
    private func tileTitleColor(for item: InvestmentCloudItem) -> Color {
        guard item.mode == .distribution, !item.isAggregated else { return PortfolixTheme.text }
        return PortfolixTheme.classOnPale
    }

    private func tileTextColor(for item: InvestmentCloudItem) -> Color {
        guard item.mode == .dailyProfit else { return tileTitleColor(for: item) }
        guard item.amountCNY != 0 else { return PortfolixTheme.text }
        return PortfolixTheme.performanceStatusText(for: item.amountCNY, scheme: performanceColorScheme)
    }

    private func accessibilityLabel(for item: InvestmentCloudItem) -> String {
        var parts: [String] = [item.title(language: language)]
        if let marketValue = item.marketValueCNY {
            parts.append(formatMoney(marketValue * currency.rateFromCNY, currency: currency))
        }
        if item.mode == .dailyProfit {
            parts.append(formatSignedMoney(item.amountCNY * currency.rateFromCNY, currency: currency))
            if let rate = item.dailyProfitRate, !item.isAggregated {
                parts.append(formatPercent(rate))
            }
        } else if let percentage = item.distributionPercentage {
            parts.append(String(format: "%.1f%%", percentage))
        }
        return parts.joined(separator: ", ")
    }

    private func hoverDetails(_ item: InvestmentCloudItem) -> some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Text(item.title(language: language))
                .fixedSize(horizontal: false, vertical: true)
            if let percentage = item.distributionPercentage {
                Text(String(format: "%.1f%%", percentage))
                    .portfolixNumericTransition(percentage)
            }
            let amount = amountText(item)
            Text(amount)
                .monospacedDigit()
                .portfolixNumericTransition(amount)
                .foregroundStyle(item.mode == .dailyProfit
                                 ? PortfolixTheme.performanceStatusText(for: item.amountCNY, scheme: performanceColorScheme)
                                 : PortfolixTheme.text)
        }
        .foregroundStyle(PortfolixTheme.text)
        .portfolixChartTooltip()
    }

    private func amountText(_ item: InvestmentCloudItem) -> String {
        let amount = item.amountCNY * currency.rateFromCNY
        return item.mode == .dailyProfit ? formatSignedMoney(amount, currency: currency) : formatMoney(amount, currency: currency)
    }

    func amountLabelText(_ item: InvestmentCloudItem, rect: CGRect) -> String {
        let full = amountText(item)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        if (full as NSString).size(withAttributes: [.font: font]).width <= rect.width - 16 { return full }
        let converted = (item.amountCNY * currency.rateFromCNY).doubleValue
        let number = abs(converted).formatted(
            .number.notation(.compactName).precision(.fractionLength(0...2))
                .locale(Locale(identifier: language == .chinese ? "zh_CN" : "en_US"))
        )
        let sign: String
        if converted < 0 {
            sign = "-"
        } else if item.mode == .dailyProfit && item.amountCNY > 0 {
            sign = "+"
        } else {
            sign = ""
        }
        return "\(sign)\(currency.symbol)\(number)"
    }

    func shouldShowHover(item: InvestmentCloudItem, rect: CGRect) -> Bool {
        !canShowLabels(item: item, rect: rect)
    }

    func hoverFrame(item: InvestmentCloudItem, tile: CGRect, bounds: CGSize) -> CGRect {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let moneyFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let title = item.title(language: language) as NSString
        let percentage = item.distributionPercentage.map { String(format: "%.1f%%", $0) } ?? ""
        let amount = amountText(item) as NSString
        let textWidth = max(
            title.size(withAttributes: [.font: font]).width,
            (percentage as NSString).size(withAttributes: [.font: font]).width,
            amount.size(withAttributes: [.font: moneyFont]).width
        )
        let width = min(ceil(textWidth) + 16, max(bounds.width, 0))
        let contentWidth = max(width - 16, 1)
        let titleHeight = title.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]
        ).height
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let extraLines: CGFloat = item.distributionPercentage == nil ? 1 : 2
        let height = ceil(titleHeight) + (lineHeight + PortfolixSpacing.xs) * extraLines + 10
        let x = min(max(tile.midX - width / 2, 0), max(bounds.width - width, 0))
        let y = min(max(tile.midY - height / 2, 0), max(bounds.height - height, 0))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func canShowLabels(item: InvestmentCloudItem, rect: CGRect) -> Bool {
        let width = rect.width - PortfolixSpacing.sm * 2
        guard width >= 48 else { return false }
        let title = (item.title(language: language) as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]
        )
        guard title.height <= 28 else { return false }
        switch item.mode {
        case .dailyProfit:
            let amountWidth = (amountLabelText(item, rect: rect) as NSString)
                .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)]).width
            return rect.height >= ceil(title.height) + 33 && amountWidth <= width
        case .distribution:
            return rect.height >= ceil(title.height) + 34
        }
    }
}
