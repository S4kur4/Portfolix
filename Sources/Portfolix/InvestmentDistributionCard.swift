import AppKit
import SwiftUI

struct InvestmentCloudCard: View {
    @Environment(PortfolioStore.self) private var store
    var contentHeight: CGFloat = PortfolixLayout.dashboardHeroContentHeight
    private var mode: InvestmentCloudMode { store.investmentCloudMode }

    var body: some View {
        @Bindable var store = store

        TimelineView(.periodic(from: .now, by: 60)) { context in
            Panel {
                VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                    InvestmentCloudHeader(
                        mode: $store.investmentCloudMode, language: store.appLanguage,
                        helpText: store.investmentDistributionHelpText,
                        isUpdating: mode == .distribution && store.isUpdatingInvestmentDistribution
                    )

                    if mode == .dailyProfit {
                        cloud(items: InvestmentCloudEngine.dailyProfitItems(positions: store.positions) {
                            store.todayProfitCNY(for: $0, asOf: context.date)
                        })
                    } else {
                        cloud(items: store.investmentDistributionItems.map(InvestmentCloudItem.init(distribution:)))
                    }
                }
                .frame(height: contentHeight, alignment: .topLeading)
            }
        }
        .task(id: mode == .distribution ? store.investmentDistributionRefreshID : "daily_profit") {
            if mode == .distribution { store.refreshInvestmentDistributionIfNeeded() }
        }
    }

    @ViewBuilder private func cloud(items: [InvestmentCloudItem]) -> some View {
        if items.isEmpty {
            Text(mode == .dailyProfit
                 ? localizedText("暂无今日盈亏", "No P&L for today", language: store.appLanguage)
                 : localizedText("暂无投资分布", "No investment distribution yet", language: store.appLanguage))
                .font(PortfolixTypography.body)
                .foregroundStyle(PortfolixTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            InvestmentCloudTreemap(items: items, currency: store.displayCurrency, language: store.appLanguage)
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

struct InvestmentCloudTreemap: View {
    let items: [InvestmentCloudItem]
    let currency: DisplayCurrency
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme
    @State private var highlightedID: InvestmentCloudItem.ID?

    var body: some View {
        GeometryReader { geometry in
            let rectangles = PortfolioChartLayout.treemap(
                weights: items.map(\.areaWeight), in: CGRect(origin: .zero, size: geometry.size),
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
                    highlightedID = rectangles.enumerated().first { $0.element.contains(location) }
                        .flatMap { items.indices.contains($0.offset) ? items[$0.offset].id : nil }
                case .ended:
                    highlightedID = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let index = items.firstIndex(where: { $0.id == highlightedID }), index < rectangles.count,
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
            if let highlightedID, !ids.contains(highlightedID) { self.highlightedID = nil }
        }
    }

    private func tile(item: InvestmentCloudItem, rect: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous)
                .fill(item.mode == .dailyProfit
                      ? PortfolixTheme.dailyProfitTileFill(for: item.amountCNY)
                      : PortfolixTheme.lilac.opacity(colorScheme == .dark ? 0.30 : 0.16))
                .opacity(highlightedID == nil || highlightedID == item.id ? 1 : 0.62)
            if canShowLabels(item: item, rect: rect) {
                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    Text(item.title(language: language))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(2)
                    if let percentage = item.distributionPercentage {
                        Text(String(format: "%.1f%%", percentage))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                    }
                    Text(amountLabelText(item, rect: rect))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(item.mode == .dailyProfit
                                         ? PortfolixTheme.performanceStatusText(for: item.amountCNY)
                                         : PortfolixTheme.primaryText)
                }
                .foregroundStyle(PortfolixTheme.primaryText)
                .padding(PortfolixSpacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PortfolixRadius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.title(language: language), item.distributionPercentage.map { String(format: "%.1f%%", $0) }, amountText(item)].compactMap { $0 }.joined(separator: ", "))
    }

    private func hoverDetails(_ item: InvestmentCloudItem) -> some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Text(item.title(language: language))
                .fixedSize(horizontal: false, vertical: true)
            if let percentage = item.distributionPercentage { Text(String(format: "%.1f%%", percentage)) }
            Text(amountText(item))
                .monospacedDigit()
                .foregroundStyle(item.mode == .dailyProfit
                                 ? PortfolixTheme.performanceStatusText(for: item.amountCNY)
                                 : PortfolixTheme.primaryText)
        }
        .foregroundStyle(PortfolixTheme.primaryText)
        .portfolixChartTooltip()
    }

    private func amountText(_ item: InvestmentCloudItem) -> String {
        let amount = item.amountCNY * currency.rateFromCNY
        return item.mode == .dailyProfit ? formatSignedMoney(amount, currency: currency) : formatMoney(amount, currency: currency)
    }

    func amountLabelText(_ item: InvestmentCloudItem, rect: CGRect) -> String {
        let full = amountText(item)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        if (full as NSString).size(withAttributes: [.font: font]).width <= rect.width - 16 { return full }
        let number = (item.amountCNY * currency.rateFromCNY).doubleValue.formatted(
            .number.notation(.compactName).precision(.fractionLength(0...2))
                .locale(Locale(identifier: language == .chinese ? "zh_CN" : "en_US"))
        )
        let sign = item.mode == .dailyProfit && item.amountCNY > 0 ? "+" : ""
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
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]
        )
        let amountWidth = (amountLabelText(item, rect: rect) as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)]).width
        let detailsHeight: CGFloat = item.distributionPercentage == nil ? 33 : 50
        return title.height <= 28 && rect.height >= ceil(title.height) + detailsHeight && amountWidth <= width
    }
}
