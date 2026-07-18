import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                DashboardHeader()

                GoldenRatioDashboardRow(spacing: PortfolixSpacing.md) {
                    PortfolioHeroCard()
                } trailing: {
                    InvestmentProfileCard()
                }
                .frame(maxWidth: .infinity)

                GoldenRatioDashboardRow(spacing: PortfolixSpacing.md) {
                    PerformanceTrendCard()
                } trailing: {
                    DailyProfitCard()
                }
                .frame(maxWidth: .infinity)

                AssetMixBarCard()

                HStack(alignment: .top, spacing: PortfolixSpacing.md) {
                    AssetAllocationCard(items: store.categoryAllocation)
                    CurrencyDistributionCard(items: store.currencyAllocation)
                }

                RecentPositionsCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

private struct GoldenRatioDashboardRow<Leading: View, Trailing: View>: View {
    let spacing: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(
        spacing: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.spacing = spacing
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GoldenRatioRowLayout(spacing: spacing) {
            leading
            trailing
        }
    }
}

private struct GoldenRatioRowLayout: Layout {
    let spacing: CGFloat
    private let trailingRatio: CGFloat = 0.618

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else {
            return .zero
        }

        let fallbackSizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let proposedWidth = proposal.width ?? fallbackSizes.reduce(spacing) { $0 + $1.width }
        let widths = columnWidths(totalWidth: proposedWidth)
        let leadingSize = subviews[0].sizeThatFits(ProposedViewSize(width: widths.leading, height: proposal.height))
        let trailingSize = subviews[1].sizeThatFits(ProposedViewSize(width: widths.trailing, height: proposal.height))

        return CGSize(width: proposedWidth, height: max(leadingSize.height, trailingSize.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else {
            return
        }

        let widths = columnWidths(totalWidth: bounds.width)
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: widths.leading, height: bounds.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + widths.leading + spacing, y: bounds.minY),
            proposal: ProposedViewSize(width: widths.trailing, height: bounds.height)
        )
    }

    private func columnWidths(totalWidth: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let contentWidth = max(totalWidth - spacing, 0)
        let leading = contentWidth / (1 + trailingRatio)
        return (leading, contentWidth - leading)
    }
}

private struct DashboardHeader: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        PageHeader(title: localizedText("资产总览", "Overview", language: store.appLanguage)) {
            Button {
                store.presentNewPositionEditor()
            } label: {
                Label(localizedText("添加持仓", "Add Holding", language: store.appLanguage), systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

private struct PortfolioHeroCard: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        Panel(padding: PortfolixSpacing.xl) {
            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                HStack(alignment: .center, spacing: PortfolixSpacing.md) {
                    SectionHeader(title: localizedText("组合价值", "Portfolio Value", language: store.appLanguage), symbol: "briefcase.fill")

                    Picker(localizedText("展示币种", "Display Currency", language: store.appLanguage), selection: $store.displayCurrency) {
                        ForEach(DisplayCurrency.allCases) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 270, alignment: .trailing)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                    Text(formatHeroMoney(store.converted(store.totalValueCNY), currency: store.displayCurrency))
                        .font(PortfolixTypography.portfolioHeroValue)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(PortfolixTheme.primaryText)

                    HStack(spacing: PortfolixSpacing.md) {
                        Text("\(localizedText("今日收益", "Today Return", language: store.appLanguage)) \(todayProfitText)")
                            .foregroundStyle(todayProfitColor)
                            .lineLimit(1)
                        Text("\(localizedText("今日收益率", "Today Return Rate", language: store.appLanguage)) \(todayProfitRateText)")
                            .foregroundStyle(todayProfitRateColor)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                }

                Spacer(minLength: 0)

                HStack(spacing: PortfolixSpacing.sm) {
                    Text(store.isRefreshing ? localizedText("正在同步行情...", "Syncing prices...", language: store.appLanguage) : updateSummary)
                        .lineLimit(1)
                    PriceRefreshButton()
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11))
                .foregroundStyle(store.isRefreshing ? PortfolixTheme.lilac : PortfolixTheme.tertiaryText)
            }
            .frame(height: PortfolixLayout.dashboardHeroContentHeight, alignment: .topLeading)
        }
    }

    private var updateSummary: String {
        guard let latestPosition = store.positions.max(by: { fetchedDate(for: $0) < fetchedDate(for: $1) }) else {
            return localizedText("尚未添加持仓", "No holdings yet", language: store.appLanguage)
        }
        return latestPosition.relativeUpdateText(now: store.relativeTimeNow, language: store.appLanguage)
    }

    private var todayProfitText: String {
        let convertedProfit = store.converted(store.todayProfitCNY)
        return store.todayProfitCNY == 0
            ? formatMoney(convertedProfit, currency: store.displayCurrency)
            : formatSignedMoney(convertedProfit, currency: store.displayCurrency)
    }

    private var todayProfitRateText: String {
        store.todayProfitRate == 0 ? "0.00%" : formatPercent(store.todayProfitRate)
    }

    private var todayProfitColor: Color {
        valueColor(for: store.todayProfitCNY)
    }

    private var todayProfitRateColor: Color {
        valueColor(for: store.todayProfitRate)
    }

    private func valueColor(for value: Decimal) -> Color {
        if value > 0 { return PortfolixTheme.mint }
        if value < 0 { return PortfolixTheme.danger }
        return PortfolixTheme.secondaryText
    }

    private func fetchedDate(for position: Position) -> Date {
        Self.isoFormatter.date(from: position.fetchedAt) ?? .distantPast
    }

    private static let isoFormatter = ISO8601DateFormatter()
}

private struct PriceRefreshButton: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var isHovering = false

    var body: some View {
        Button {
            store.refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .symbolEffect(.rotate, isActive: store.isRefreshing)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundStyle)
        .portfolixGlass(
            in: Circle(),
            fallbackTint: PortfolixTheme.panelSoft,
            fallbackOpacity: isHovering && !store.isRefreshing ? 0.64 : 0.42,
            interactive: true
        )
        .opacity(store.isRefreshing ? 0.58 : 1)
        .onHover { isHovering = $0 }
        .accessibilityLabel(localizedText("刷新最新行情", "Refresh latest prices", language: store.appLanguage))
        .disabled(store.isRefreshing)
    }

    private var foregroundStyle: AnyShapeStyle {
        AnyShapeStyle(isHovering && !store.isRefreshing ? PortfolixTheme.primaryText : PortfolixTheme.secondaryText)
    }
}

private struct PerformanceTrendCard: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var highlightedSnapshotID: PortfolioSnapshot.ID?

    private var snapshots: [PortfolioSnapshot] {
        store.visibleSnapshots
    }

    private var values: [Double] {
        snapshots.map(chartValue)
    }

    private var lowerBound: Double {
        guard let minimum = values.min() else { return 0 }
        return minimum - scalePadding
    }

    private var upperBound: Double {
        guard let maximum = values.max() else { return 1 }
        return maximum + scalePadding
    }

    private var scalePadding: Double {
        guard let minimum = values.min(), let maximum = values.max() else { return 1 }
        let span = max(maximum - minimum, 1)
        switch store.trendMetric {
        case .profitValue:
            return max(span * 0.18, 2_000)
        case .profitRate:
            return max(span * 0.18, 0.3)
        }
    }

    private var highlightedSnapshot: PortfolioSnapshot? {
        snapshots.first { $0.id == highlightedSnapshotID }
    }

    private var chartDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -store.trendRange.days, to: today) ?? today
        return start ... today
    }

    private var chartScaleDomain: ClosedRange<Date> {
        let padding = max(TimeInterval(store.trendRange.days) * 0.055 * 86_400, 18_000)
        return chartDomain.lowerBound.addingTimeInterval(-padding) ... chartDomain.upperBound.addingTimeInterval(padding)
    }

    private var xAxisDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = chartDomain.lowerBound

        switch store.trendRange {
        case .day:
            return [start, today]
        case .week:
            return [0, 2, 4, 6].compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        case .month:
            var dates = stride(from: 0, through: store.trendRange.days, by: 10).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
            if dates.last != today {
                dates.append(today)
            }
            return dates
        case .year:
            var dates: [Date] = []
            var cursor = start
            while cursor <= today {
                dates.append(cursor)
                guard let next = calendar.date(byAdding: .month, value: 2, to: cursor) else { break }
                cursor = next
            }
            if dates.last != today {
                dates.append(today)
            }
            return dates
        }
    }

    var body: some View {
        Panel(padding: PortfolixSpacing.lg) {
            VStack(alignment: .leading, spacing: PortfolixSpacing.lg) {
                HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
                    SectionHeader(title: localizedText("收益趋势", "Return Trend", language: store.appLanguage), symbol: "chart.xyaxis.line")

                    HStack(spacing: PortfolixSpacing.md) {
                        Picker(localizedText("趋势指标", "Metric", language: store.appLanguage), selection: $store.trendMetric) {
                            ForEach(TrendMetric.allCases) { metric in
                                Text(metric.title(language: store.appLanguage)).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: PortfolixLayout.dashboardCompactControlHeight)

                        Picker(localizedText("时间范围", "Range", language: store.appLanguage), selection: $store.trendRange) {
                            ForEach(TrendRange.allCases) { range in
                                Text(range.title(language: store.appLanguage)).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: PortfolixLayout.dashboardCompactControlHeight)
                    }
                }
                .padding(.trailing, PortfolixSpacing.xs)

                HStack(alignment: .lastTextBaseline, spacing: PortfolixSpacing.sm) {
                    Text(latestValueText)
                        .font(PortfolixTypography.secondaryValue)
                        .foregroundStyle(PortfolixTheme.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Label(changeSummary, systemImage: changeSymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(changeColor)
                        .lineLimit(1)
                }

                if snapshots.isEmpty {
                    DashboardEmptyState(title: localizedText("暂无历史快照", "No snapshots yet", language: store.appLanguage))
                        .frame(maxWidth: .infinity, minHeight: 172)
                } else {
                    Chart(snapshots) { snapshot in
                        AreaMark(
                            x: .value("日期", snapshot.date),
                            yStart: .value("基线", lowerBound),
                            yEnd: .value("数值", chartValue(snapshot))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [PortfolixTheme.lilac.opacity(0.3), PortfolixTheme.violet.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("日期", snapshot.date),
                            y: .value("数值", chartValue(snapshot))
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(PortfolixTheme.lilac)

                        if snapshot.id == highlightedSnapshot?.id {
                            RuleMark(x: .value("日期", snapshot.date))
                                .foregroundStyle(PortfolixTheme.lilac.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }

                        if snapshot.id == (highlightedSnapshot?.id ?? snapshots.last?.id) {
                            PointMark(
                                x: .value("日期", snapshot.date),
                                y: .value("数值", chartValue(snapshot))
                            )
                            .symbolSize(42)
                            .foregroundStyle(PortfolixTheme.primaryText)
                            .annotation(position: shouldPlaceAnnotationLeading(for: snapshot) ? .topLeading : .topTrailing, spacing: PortfolixSpacing.sm) {
                                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                                    if highlightedSnapshot != nil {
                                        Text(snapshot.date.formatted(.dateTime.month().day()))
                                            .foregroundStyle(PortfolixTheme.tertiaryText)
                                    }
                                    Text(valueText(for: snapshot))
                                        .foregroundStyle(PortfolixTheme.primaryText)
                                }
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(PortfolixTheme.panelSoft, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: PortfolixRadius.compact)
                                            .stroke(PortfolixTheme.borderStrong, lineWidth: 1)
                                    }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    updateHighlightedSnapshot(for: phase, proxy: proxy, geometry: geometry)
                                }
                        }
                    }
                    .chartXScale(domain: chartScaleDomain)
                    .chartYScale(domain: lowerBound ... upperBound)
                    .chartXAxis {
                        AxisMarks(values: xAxisDates) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                                .foregroundStyle(PortfolixTheme.border)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(axisDateLabel(date))
                                        .foregroundStyle(PortfolixTheme.tertiaryText)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                                .foregroundStyle(PortfolixTheme.border)
                            AxisValueLabel {
                                if let numeric = value.as(Double.self) {
                                    Text(axisLabel(numeric))
                                        .foregroundStyle(PortfolixTheme.tertiaryText)
                                }
                            }
                        }
                    }
                    .frame(height: 172)
                }
            }
            .frame(height: PortfolixLayout.dashboardTrendContentHeight, alignment: .topLeading)
        }
    }

    private func chartValue(_ snapshot: PortfolioSnapshot) -> Double {
        switch store.trendMetric {
        case .profitValue:
            snapshot.profitCNY * store.displayCurrency.rateFromCNY.doubleValue
        case .profitRate:
            snapshot.profitRate
        }
    }

    private var latestValueText: String {
        guard let latest = snapshots.last else { return "--" }
        return valueText(for: latest)
    }

    private func valueText(for snapshot: PortfolioSnapshot) -> String {
        switch store.trendMetric {
        case .profitValue:
            return formatSignedMoney(
                Decimal(snapshot.profitCNY) * store.displayCurrency.rateFromCNY,
                currency: store.displayCurrency,
                maximumFractionDigits: 0
            )
        case .profitRate:
            return String(format: "%+.2f%%", snapshot.profitRate)
        }
    }

    private func updateHighlightedSnapshot(for phase: HoverPhase, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            highlightedSnapshotID = nil
            return
        }

        switch phase {
        case let .active(location):
            let frame = geometry[plotFrame]
            let x = location.x - frame.origin.x
            guard frame.contains(location), let date: Date = proxy.value(atX: x) else {
                highlightedSnapshotID = nil
                return
            }
            highlightedSnapshotID = snapshots.min {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }?.id
        case .ended:
            highlightedSnapshotID = nil
        }
    }

    private var changeSummary: String {
        guard let first = values.first, let last = values.last else {
            return localizedText("暂无变化", "No change", language: store.appLanguage)
        }
        switch store.trendMetric {
        case .profitValue:
            return "\(localizedText("区间变化", "Range change", language: store.appLanguage)) \(formatSignedMoney(Decimal(last - first), currency: store.displayCurrency, maximumFractionDigits: 0))"
        case .profitRate:
            return String(format: "\(localizedText("区间变化", "Range change", language: store.appLanguage)) %+.2f%%", last - first)
        }
    }

    private func axisLabel(_ value: Double) -> String {
        switch store.trendMetric {
        case .profitValue:
            let sign = value >= 0 ? "+" : "-"
            return String(format: "%@%@%.0fK", sign, store.displayCurrency.symbol, abs(value) / 1_000)
        case .profitRate:
            return String(format: "%+.1f%%", value)
        }
    }

    private func axisDateLabel(_ date: Date) -> String {
        if store.appLanguage == .english {
            switch store.trendRange {
            case .year:
                return Self.englishMonthFormatter.string(from: date)
            default:
                return Self.englishMonthDayFormatter.string(from: date)
            }
        }
        switch store.trendRange {
        case .year:
            return date.formatted(.dateTime.month())
        default:
            return date.formatted(.dateTime.month().day())
        }
    }

    private static let englishMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let englishMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private func shouldPlaceAnnotationLeading(for snapshot: PortfolioSnapshot) -> Bool {
        let span = max(chartDomain.upperBound.timeIntervalSince(chartDomain.lowerBound), 1)
        let progress = snapshot.date.timeIntervalSince(chartDomain.lowerBound) / span
        return progress > 0.72
    }

    private var changeSymbol: String {
        intervalChange >= 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private var changeColor: Color {
        intervalChange >= 0 ? PortfolixTheme.mint : PortfolixTheme.danger
    }

    private var intervalChange: Double {
        guard let first = values.first, let last = values.last else { return 0 }
        return last - first
    }
}

private struct AssetAllocationCard: View {
    @EnvironmentObject private var store: PortfolioStore
    let items: [AllocationItem]
    @State private var highlightedItemID: AllocationItem.ID?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("资产配置", "Asset Allocation", language: store.appLanguage), symbol: "chart.pie.fill")

                if items.isEmpty {
                    DashboardEmptyState(title: localizedText("暂无资产配置", "No allocation yet", language: store.appLanguage))
                        .frame(maxWidth: .infinity, minHeight: 142)
                } else {
                    HStack(spacing: PortfolixSpacing.xxl) {
                        InteractiveDistributionChart(items: items, highlightedItemID: $highlightedItemID)
                            .frame(width: 142, height: 142)
                            .accessibilityLabel(localizedText("资产配置", "Asset Allocation", language: store.appLanguage))

                        VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                            ForEach(items) { item in
                                DistributionLegendRow(item: item, highlightedItemID: highlightedItemID)
                            }
                        }
                        .frame(width: 152, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(height: PortfolixLayout.distributionContentHeight, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CurrencyDistributionCard: View {
    @EnvironmentObject private var store: PortfolioStore
    let items: [AllocationItem]
    @State private var highlightedItemID: AllocationItem.ID?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("计价币种分布", "Currency Exposure", language: store.appLanguage), symbol: "banknote.fill")

                if items.isEmpty {
                    DashboardEmptyState(title: localizedText("暂无币种分布", "No currency exposure yet", language: store.appLanguage))
                        .frame(maxWidth: .infinity, minHeight: 142)
                } else {
                    HStack(spacing: PortfolixSpacing.xxl) {
                        InteractiveDistributionChart(items: items, highlightedItemID: $highlightedItemID)
                            .frame(width: 142, height: 142)
                            .accessibilityLabel(localizedText("计价币种分布", "Currency Exposure", language: store.appLanguage))

                        VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                            ForEach(items) { item in
                                DistributionLegendRow(item: item, highlightedItemID: highlightedItemID)
                            }
                        }
                        .frame(width: 152, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(height: PortfolixLayout.distributionContentHeight, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AssetMixBarCard: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var highlightedItemID: PositionShareItem.ID?

    private var items: [PositionShareItem] {
        store.positionShareItems
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                HStack(alignment: .center, spacing: PortfolixSpacing.md) {
                    SectionHeader(title: localizedText("持仓占比", "Holding Mix", language: store.appLanguage), symbol: "rectangle.split.3x1.fill")

                    Spacer(minLength: PortfolixSpacing.sm)

                    Text(formatMoney(store.converted(store.totalValueCNY), currency: store.displayCurrency))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(PortfolixTheme.secondaryText)
                        .lineLimit(1)
                }

                if items.isEmpty {
                    DashboardEmptyState(title: localizedText("暂无持仓占比", "No holding mix yet", language: store.appLanguage))
                        .frame(maxWidth: .infinity, minHeight: 64)
                } else {
                    AssetMixSegmentBar(items: items, highlightedItemID: $highlightedItemID)
                        .frame(height: 18)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220), spacing: PortfolixSpacing.lg, alignment: .leading)],
                        alignment: .leading,
                        spacing: PortfolixSpacing.sm
                    ) {
                        ForEach(items) { item in
                            AssetMixLegendItem(item: item, highlightedItemID: highlightedItemID)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AssetMixSegmentBar: View {
    let items: [PositionShareItem]
    @Binding var highlightedItemID: PositionShareItem.ID?

    var body: some View {
        GeometryReader { proxy in
            let spacing = CGFloat(max(items.count - 1, 0)) * 2
            let availableWidth = max(proxy.size.width - spacing, 0)

            HStack(spacing: 2) {
                ForEach(items) { item in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(item.color.gradient)
                        .opacity(highlightedItemID == nil || highlightedItemID == item.id ? 1 : 0.32)
                        .frame(width: max(availableWidth * item.value / 100, item.value > 0 ? 4 : 0))
                }
            }
            .background(PortfolixTheme.panelSoft, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(PortfolixTheme.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                updateHighlightedItem(for: phase, totalWidth: proxy.size.width)
            }
        }
        .animation(.easeOut(duration: 0.16), value: highlightedItemID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Asset mix")
    }

    private func updateHighlightedItem(for phase: HoverPhase, totalWidth: CGFloat) {
        switch phase {
        case let .active(location):
            guard totalWidth > 0, location.x >= 0, location.x <= totalWidth else {
                highlightedItemID = nil
                return
            }
            let total = items.reduce(0) { $0 + $1.value }
            guard total > 0 else {
                highlightedItemID = nil
                return
            }

            let selectedValue = Double(location.x / totalWidth) * total
            var upperBound = 0.0
            highlightedItemID = items.first { item in
                upperBound += item.value
                return selectedValue <= upperBound
            }?.id
        case .ended:
            highlightedItemID = nil
        }
    }
}

private struct AssetMixLegendItem: View {
    let item: PositionShareItem
    let highlightedItemID: PositionShareItem.ID?

    var body: some View {
        HStack(spacing: PortfolixSpacing.xs) {
            Circle()
                .fill(item.color)
                .frame(width: 8, height: 8)
            Text(item.name)
                .foregroundStyle(PortfolixTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(String(format: "%.1f%%", item.value))
                .foregroundStyle(PortfolixTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(PortfolixTypography.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(highlightedItemID == nil || highlightedItemID == item.id ? 1 : 0.42)
        .animation(.easeOut(duration: 0.16), value: highlightedItemID)
        .help("\(item.name) \(String(format: "%.1f%%", item.value))")
    }
}

private struct PositionShareItem: Identifiable {
    let id: Position.ID
    let name: String
    let value: Double
    let color: Color
}

private struct InteractiveDistributionChart: View {
    let items: [AllocationItem]
    @Binding var highlightedItemID: AllocationItem.ID?

    private var highlightedItem: AllocationItem? {
        items.first { $0.id == highlightedItemID }
    }

    var body: some View {
        ZStack {
            Chart(items) { item in
                SectorMark(
                    angle: .value("占比", item.value),
                    innerRadius: .ratio(0.62),
                    outerRadius: .ratio(item.id == highlightedItemID ? 1 : 0.94),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(item.color.gradient)
                .opacity(highlightedItemID == nil || item.id == highlightedItemID ? 1 : 0.38)
            }
            .chartLegend(.hidden)
            .chartOverlay { _ in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            updateHighlightedItem(for: phase, size: geometry.size)
                        }
                }
            }

            if let highlightedItem {
                VStack(spacing: PortfolixSpacing.xs) {
                    Text(highlightedItem.name)
                        .foregroundStyle(PortfolixTheme.secondaryText)
                    Text(String(format: "%.1f%%", highlightedItem.value))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PortfolixTheme.primaryText)
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.16), value: highlightedItemID)
    }

    private func updateHighlightedItem(for phase: HoverPhase, size: CGSize) {
        switch phase {
        case let .active(location):
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let offset = CGPoint(x: location.x - center.x, y: location.y - center.y)
            let radius = min(size.width, size.height) / 2
            let distance = hypot(offset.x, offset.y)

            guard distance >= radius * 0.56, distance <= radius else {
                highlightedItemID = nil
                return
            }

            var angle = atan2(offset.x, -offset.y)
            if angle < 0 {
                angle += 2 * .pi
            }

            let total = items.reduce(0) { $0 + $1.value }
            let selectedValue = angle / (2 * .pi) * total
            var upperBound = 0.0
            highlightedItemID = items.first { item in
                upperBound += item.value
                return selectedValue <= upperBound
            }?.id
        case .ended:
            highlightedItemID = nil
        }
    }
}

private struct DistributionLegendRow: View {
    let item: AllocationItem
    let highlightedItemID: AllocationItem.ID?

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Circle()
                .fill(item.color)
                .frame(width: 8, height: 8)
            Text(item.name)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondaryText)
                .lineLimit(1)
            Spacer()
            Text(String(format: "%.1f%%", item.value))
                .font(PortfolixTypography.captionEmphasis)
                .monospacedDigit()
                .foregroundStyle(PortfolixTheme.primaryText)
        }
        .opacity(highlightedItemID == nil || highlightedItemID == item.id ? 1 : 0.42)
        .animation(.easeOut(duration: 0.16), value: highlightedItemID)
        .accessibilityElement(children: .combine)
    }
}

private struct RecentPositionsCard: View {
    @EnvironmentObject private var store: PortfolioStore
    @AppStorage("dashboard_primary_positions_limit")
    private var displayLimitRawValue = PrimaryPositionDisplayLimit.top10Percent.rawValue
    @State private var sortField: PrimaryPositionSortField = .marketValue
    @State private var sortDirection: PrimaryPositionSortDirection = .descending

    private var displayLimit: PrimaryPositionDisplayLimit {
        PrimaryPositionDisplayLimit(rawValue: displayLimitRawValue) ?? .top10Percent
    }

    private var primaryPositions: [Position] {
        PrimaryPositionOrdering.visiblePositions(
            from: store.positions,
            limit: displayLimit,
            sortField: sortField,
            direction: sortDirection,
            todayProfit: { store.todayProfitCNY(for: $0) }
        )
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("主要持仓", "Top Holdings", language: store.appLanguage), symbol: "list.bullet.rectangle") {
                    PortfolixGlassGroup(spacing: PortfolixSpacing.md) {
                        HStack(spacing: PortfolixSpacing.md) {
                            PrimaryPositionLimitMenu(
                                selection: Binding(
                                    get: { displayLimit },
                                    set: { displayLimitRawValue = $0.rawValue }
                                ),
                                language: store.appLanguage
                            )

                            DashboardGlassCapsuleButton(
                                title: localizedText("查看明细", "View Details", language: store.appLanguage),
                                symbol: "list.bullet"
                            ) {
                                store.selection = .positions
                            }
                        }
                    }
                }

                if primaryPositions.isEmpty {
                    DashboardEmptyState(title: localizedText("暂无持仓", "No holdings yet", language: store.appLanguage))
                        .frame(maxWidth: .infinity, minHeight: 82)
                } else {
                    PositionHeaderRow(
                        sortField: $sortField,
                        sortDirection: $sortDirection
                    )

                    ForEach(primaryPositions) { position in
                        CompactPositionRow(position: position)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

enum PrimaryPositionDisplayLimit: String, CaseIterable, Identifiable {
    case top10Percent
    case top30Percent
    case top50Percent
    case all

    var id: String { rawValue }

    func maximumCount(totalCount: Int) -> Int? {
        switch self {
        case .top10Percent:
            percentageCount(0.10, totalCount: totalCount)
        case .top30Percent:
            percentageCount(0.30, totalCount: totalCount)
        case .top50Percent:
            percentageCount(0.50, totalCount: totalCount)
        case .all: nil
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .top10Percent:
            localizedText("市值前 10%", "Top 10% by Market Value", language: language)
        case .top30Percent:
            localizedText("市值前 30%", "Top 30% by Market Value", language: language)
        case .top50Percent:
            localizedText("市值前 50%", "Top 50% by Market Value", language: language)
        case .all:
            localizedText("全部持仓", "All Holdings", language: language)
        }
    }

    private func percentageCount(_ percentage: Double, totalCount: Int) -> Int {
        guard totalCount > 0 else { return 0 }
        return max(1, Int(ceil(Double(totalCount) * percentage)))
    }
}

enum PrimaryPositionSortField: Hashable {
    case marketValue
    case profitRate
    case todayProfit
}

enum PrimaryPositionSortDirection: Hashable {
    case ascending
    case descending

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

enum PrimaryPositionOrdering {
    static func visiblePositions(
        from positions: [Position],
        limit: PrimaryPositionDisplayLimit,
        sortField: PrimaryPositionSortField,
        direction: PrimaryPositionSortDirection,
        todayProfit: (Position) -> Decimal
    ) -> [Position] {
        let rankedByMarketValue = positions.sorted(by: marketValueRank)
        let limited: [Position]
        if let maximumCount = limit.maximumCount(totalCount: rankedByMarketValue.count) {
            limited = Array(rankedByMarketValue.prefix(maximumCount))
        } else {
            limited = rankedByMarketValue
        }

        return limited.sorted { lhs, rhs in
            let lhsValue = sortValue(for: lhs, field: sortField, todayProfit: todayProfit)
            let rhsValue = sortValue(for: rhs, field: sortField, todayProfit: todayProfit)
            if lhsValue == rhsValue {
                return marketValueRank(lhs, rhs)
            }
            return direction == .ascending ? lhsValue < rhsValue : lhsValue > rhsValue
        }
    }

    private static func sortValue(
        for position: Position,
        field: PrimaryPositionSortField,
        todayProfit: (Position) -> Decimal
    ) -> Decimal {
        switch field {
        case .marketValue:
            position.marketValueCNY
        case .profitRate:
            position.profitRate
        case .todayProfit:
            todayProfit(position)
        }
    }

    private static func marketValueRank(_ lhs: Position, _ rhs: Position) -> Bool {
        if lhs.marketValueCNY == rhs.marketValueCNY {
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        return lhs.marketValueCNY > rhs.marketValueCNY
    }
}

private struct PrimaryPositionLimitMenu: View {
    @Binding var selection: PrimaryPositionDisplayLimit
    let language: AppLanguage

    var body: some View {
        Menu {
            ForEach(PrimaryPositionDisplayLimit.allCases) { option in
                Button(option.title(language: language)) {
                    selection = option
                }
            }
        } label: {
            DashboardGlassCapsuleLabel(
                title: selection.title(language: language),
                symbol: "line.3.horizontal.decrease",
                showsChevron: true
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

private struct DashboardGlassCapsuleButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DashboardGlassCapsuleLabel(title: title, symbol: symbol)
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardGlassCapsuleLabel: View {
    let title: String
    let symbol: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Image(systemName: symbol)
            Text(title)
                .fixedSize(horizontal: true, vertical: false)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.tertiaryText)
            }
        }
        .font(PortfolixTypography.captionEmphasis)
        .lineLimit(1)
        .foregroundStyle(PortfolixTheme.secondaryText)
        .padding(.horizontal, PortfolixSpacing.sm)
        .padding(.vertical, PortfolixSpacing.xs)
        .frame(height: PortfolixLayout.dashboardCompactControlHeight)
        .portfolixGlass(
            in: Capsule(),
            fallbackTint: PortfolixTheme.panelSoft,
            fallbackOpacity: 0.48,
            interactive: true
        )
        .contentShape(Capsule())
    }
}

private struct PositionHeaderRow: View {
    @EnvironmentObject private var store: PortfolioStore
    @Binding var sortField: PrimaryPositionSortField
    @Binding var sortDirection: PrimaryPositionSortDirection

    var body: some View {
        HStack(spacing: 0) {
            Text(localizedText("资产", "Asset", language: store.appLanguage)).positionColumn(alignment: .center)
            Text(localizedText("近 1 周走势", "1W Trend", language: store.appLanguage)).positionColumn(alignment: .center)
            Text(localizedText("类型", "Type", language: store.appLanguage)).positionColumn(alignment: .center)
            SortablePositionHeader(
                title: localizedText("当前市值", "Market Value", language: store.appLanguage),
                field: .marketValue,
                selectedField: $sortField,
                direction: $sortDirection
            )
            .positionColumn(alignment: .center)
            SortablePositionHeader(
                title: localizedText("持仓收益率", "Return Rate", language: store.appLanguage),
                field: .profitRate,
                selectedField: $sortField,
                direction: $sortDirection
            )
            .positionColumn(alignment: .center)
            SortablePositionHeader(
                title: localizedText("今日收益", "Today Return", language: store.appLanguage),
                field: .todayProfit,
                selectedField: $sortField,
                direction: $sortDirection
            )
            .positionColumn(alignment: .center)
            Text(localizedText("价格日期", "Price Date", language: store.appLanguage)).positionColumn(alignment: .center)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(PortfolixTheme.tertiaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact))
    }
}

private struct SortablePositionHeader: View {
    let title: String
    let field: PrimaryPositionSortField
    @Binding var selectedField: PrimaryPositionSortField
    @Binding var direction: PrimaryPositionSortDirection

    private var isSelected: Bool {
        selectedField == field
    }

    var body: some View {
        Button {
            if isSelected {
                direction.toggle()
            } else {
                selectedField = field
                direction = .descending
            }
        } label: {
            HStack(spacing: PortfolixSpacing.xs) {
                Text(title)
                Image(systemName: direction == .ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(isSelected ? PortfolixTheme.lilac : PortfolixTheme.tertiaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? accessibilitySortValue : "")
    }

    private var accessibilitySortValue: String {
        switch direction {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }
}

private struct CompactPositionRow: View {
    @EnvironmentObject private var store: PortfolioStore
    let position: Position

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: PortfolixSpacing.sm) {
                Button {
                    store.presentPositionEditor(for: position.id)
                } label: {
                    Circle()
                        .fill(position.category.color.opacity(0.18))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Text(String(position.name.prefix(1)))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(position.category.color)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .help(localizedText("编辑持仓", "Edit Holding", language: store.appLanguage))
                .accessibilityLabel(localizedText("编辑 \(position.name)", "Edit \(position.name)", language: store.appLanguage))

                VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                    Text(position.name)
                        .foregroundStyle(PortfolixTheme.primaryText)
                    Text(position.symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(PortfolixTheme.tertiaryText)
                }
            }
            .positionColumn()

            PositionSparkline(values: position.weeklyTrend)
                .frame(width: 112)
                .positionColumn(alignment: .center)

            Text(position.category.title(language: store.appLanguage))
                .positionColumn(alignment: .center)
                .foregroundStyle(PortfolixTheme.secondaryText)

            Text(formatMoney(store.converted(position.marketValueCNY), currency: store.displayCurrency))
                .positionMetricColumn(width: 118)
                .foregroundStyle(PortfolixTheme.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(formatPercent(position.profitRate))
                .positionMetricColumn(width: 72)
                .foregroundStyle(position.profitRate >= 0 ? PortfolixTheme.mint : PortfolixTheme.danger)
                .monospacedDigit()

            let todayProfit = store.todayProfitCNY(for: position)
            let isTodayProfitZero = todayProfit == 0
            Text(
                isTodayProfitZero
                    ? formatMoney(store.converted(todayProfit), currency: store.displayCurrency)
                    : formatSignedMoney(store.converted(todayProfit), currency: store.displayCurrency)
            )
                .positionMetricColumn(width: 96)
                .foregroundStyle(
                    isTodayProfitZero
                        ? PortfolixTheme.secondaryText
                        : (todayProfit > 0 ? PortfolixTheme.mint : PortfolixTheme.danger)
                )
                .monospacedDigit()
                .contentTransition(.numericText())

            VStack(alignment: .trailing, spacing: 2) {
                Text(position.priceDateText(language: store.appLanguage))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PortfolixTheme.primaryText)
                    .lineLimit(1)
                Text(position.relativeUpdateText(now: store.relativeTimeNow, language: store.appLanguage))
                    .font(.system(size: 9))
                    .foregroundStyle(PortfolixTheme.tertiaryText)
                    .lineLimit(1)
            }
            .positionMetricColumn(width: 112)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(PortfolixTheme.panelElevated.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func positionColumn(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
    }

    func positionMetricColumn(width: CGFloat) -> some View {
        frame(maxWidth: width, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct PositionSparkline: View {
    @EnvironmentObject private var store: PortfolioStore
    let values: [Double]

    private var points: [(offset: Int, value: Double)] {
        values.enumerated().map { (offset: $0.offset, value: $0.element) }
    }

    private var color: Color {
        isRising ? PortfolixTheme.mint : PortfolixTheme.danger
    }

    private var isRising: Bool {
        guard let first = values.first, let last = values.last else { return true }
        return last >= first
    }

    private var domain: ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else { return 0 ... 1 }
        let padding = max((maximum - minimum) * 0.18, max(abs(maximum) * 0.002, 0.01))
        return (minimum - padding) ... (maximum + padding)
    }

    var body: some View {
        Group {
            if points.count < 2 {
                ZStack {
                    Capsule()
                        .fill(PortfolixTheme.tertiaryText.opacity(0.22))
                        .frame(width: 36, height: 2)
                    Circle()
                        .fill(PortfolixTheme.tertiaryText.opacity(0.72))
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 28)
            } else {
                Chart(points, id: \.offset) { point in
                    AreaMark(
                        x: .value("日", point.offset),
                        yStart: .value("基线", domain.lowerBound),
                        yEnd: .value("价格", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日", point.offset),
                        y: .value("价格", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(color)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: domain)
                .frame(height: 28)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedText("近 1 周走势", "1-week trend", language: store.appLanguage))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if values.count < 2 {
            return localizedText("历史数据不足", "Not enough history", language: store.appLanguage)
        }
        return isRising
            ? localizedText("上涨", "Rising", language: store.appLanguage)
            : localizedText("下跌", "Falling", language: store.appLanguage)
    }
}

private struct InvestmentProfileCard: View {
    @EnvironmentObject private var store: PortfolioStore

    private var dimensions: [InvestmentProfileDimension] {
        store.investmentProfileDimensions
    }

    var body: some View {
        Panel(padding: PortfolixSpacing.xl) {
            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                InvestmentProfileHeader(
                    language: store.appLanguage,
                    helpText: store.investmentProfileHelpText
                )

                if store.positions.isEmpty {
                    DashboardEmptyState(title: localizedText("添加持仓后生成画像", "Add holdings to generate a profile", language: store.appLanguage))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    InvestmentRadarChart(dimensions: dimensions, language: store.appLanguage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .onAppear {
                            store.refreshInvestmentProfileIfNeeded()
                        }
                }
            }
            .frame(height: PortfolixLayout.dashboardHeroContentHeight, alignment: .topLeading)
        }
    }
}

struct InvestmentProfileDimension: Identifiable {
    let id: String
    let title: String
    let value: Double
    let color: Color
}

private struct InvestmentProfileHeader: View {
    let language: AppLanguage
    let helpText: String

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PortfolixTheme.lilac)
                .frame(width: 16)

            Text(localizedText("投资画像", "Investment Profile", language: language))
                .font(PortfolixTypography.sectionTitle)
                .foregroundStyle(PortfolixTheme.primaryText)
                .lineLimit(1)

            HelpIcon(
                text: helpText
            )

            Spacer(minLength: PortfolixSpacing.sm)
        }
    }
}

private struct InvestmentRadarChart: View {
    let dimensions: [InvestmentProfileDimension]
    let language: AppLanguage
    @State private var highlightedDimensionID: InvestmentProfileDimension.ID?

    private struct RadarGeometry {
        let center: CGPoint
        let radius: CGFloat
        let labelRadius: CGFloat
    }

    private var highlightedDimension: InvestmentProfileDimension? {
        dimensions.first { $0.id == highlightedDimensionID }
    }

    private let gridStroke = StrokeStyle(lineWidth: 0.5, dash: [3, 4])

    var body: some View {
        GeometryReader { proxy in
            let geometry = radarGeometry(size: proxy.size)

            ZStack {
                Canvas { context, _ in
                    guard dimensions.count >= 3 else { return }

                    for level in [0.25, 0.5, 0.75, 1.0] {
                        let rect = CGRect(
                            x: geometry.center.x - geometry.radius * level,
                            y: geometry.center.y - geometry.radius * level,
                            width: geometry.radius * 2 * level,
                            height: geometry.radius * 2 * level
                        )
                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(PortfolixTheme.border),
                            style: gridStroke
                        )
                    }

                    for index in dimensions.indices {
                        var axis = Path()
                        axis.move(to: geometry.center)
                        axis.addLine(to: radarPoint(
                            center: geometry.center,
                            radius: geometry.radius,
                            index: index,
                            count: dimensions.count,
                            scale: 1
                        ))
                        context.stroke(
                            axis,
                            with: .color(PortfolixTheme.border),
                            style: gridStroke
                        )
                    }

                    let valuePath = radarValuePath(
                        dimensions: dimensions,
                        center: geometry.center,
                        radius: geometry.radius,
                        value: \.value
                    )
                    context.fill(valuePath, with: .color(PortfolixTheme.lilac.opacity(0.24)))
                    context.stroke(valuePath, with: .color(PortfolixTheme.lilac), lineWidth: 2)

                    for (index, dimension) in dimensions.enumerated() {
                        let scale = max(0, min(dimension.value / 100, 1))
                        let point = radarPoint(
                            center: geometry.center,
                            radius: geometry.radius,
                            index: index,
                            count: dimensions.count,
                            scale: scale
                        )
                        let isHighlighted = dimension.id == highlightedDimensionID
                        let size: CGFloat = isHighlighted ? 8 : 6
                        let rect = CGRect(
                            x: point.x - size / 2,
                            y: point.y - size / 2,
                            width: size,
                            height: size
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(isHighlighted ? PortfolixTheme.primaryText : PortfolixTheme.lilac))
                    }
                }

                ForEach(Array(dimensions.enumerated()), id: \.element.id) { index, dimension in
                    let point = radarPoint(
                        center: geometry.center,
                        radius: geometry.labelRadius,
                        index: index,
                        count: dimensions.count,
                        scale: 1
                    )
                    RadarAxisLabel(dimension: dimension)
                        .position(point)
                }

                if
                    let highlightedDimension,
                    let highlightedIndex = dimensions.firstIndex(where: { $0.id == highlightedDimension.id })
                {
                    let point = radarPoint(
                        center: geometry.center,
                        radius: geometry.radius,
                        index: highlightedIndex,
                        count: dimensions.count,
                        scale: max(0, min(highlightedDimension.value / 100, 1))
                    )
                    RadarValueBadge(dimension: highlightedDimension)
                        .position(x: point.x, y: point.y - 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        updateHighlightedDimension(for: phase, geometry: geometry)
                    }
            }
        }
        .animation(.easeOut(duration: 0.16), value: highlightedDimensionID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Investment profile radar")
    }

    private func radarGeometry(size: CGSize) -> RadarGeometry {
        let labelInset: CGFloat = 8
        let horizontalLabelReserve = max(24, min(size.width * 0.09, 40))
        let availableHorizontalRadius = max((size.width - horizontalLabelReserve * 2) / 2, 48)
        let availableVerticalRadius = max(size.height / 2 - labelInset, 48)
        let radius = min(availableHorizontalRadius, availableVerticalRadius) * 0.94
        let labelRadius = radius + PortfolixSpacing.xs
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return RadarGeometry(center: center, radius: radius, labelRadius: labelRadius)
    }

    private func updateHighlightedDimension(for phase: HoverPhase, geometry: RadarGeometry) {
        switch phase {
        case let .active(location):
            guard dimensions.count >= 3 else {
                highlightedDimensionID = nil
                return
            }
            let offset = CGPoint(x: location.x - geometry.center.x, y: location.y - geometry.center.y)
            let distance = hypot(offset.x, offset.y)
            guard distance <= geometry.labelRadius + 18 else {
                highlightedDimensionID = nil
                return
            }

            let locationAngle = normalizedAngle(atan2(offset.y, offset.x))
            highlightedDimensionID = dimensions.enumerated().min { lhs, rhs in
                let lhsAngle = normalizedAngle(-Double.pi / 2 + Double(lhs.offset) / Double(dimensions.count) * 2 * Double.pi)
                let rhsAngle = normalizedAngle(-Double.pi / 2 + Double(rhs.offset) / Double(dimensions.count) * 2 * Double.pi)
                return angularDistance(lhsAngle, locationAngle) < angularDistance(rhsAngle, locationAngle)
            }?.element.id
        case .ended:
            highlightedDimensionID = nil
        }
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 2 * Double.pi)
        if value < 0 {
            value += 2 * Double.pi
        }
        return value
    }

    private func angularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs)
        return min(difference, 2 * Double.pi - difference)
    }

    private func radarValuePath(
        dimensions: [InvestmentProfileDimension],
        center: CGPoint,
        radius: CGFloat,
        value: KeyPath<InvestmentProfileDimension, Double>
    ) -> Path {
        let points = dimensions.enumerated().map { index, dimension in
            let scale = max(0, min(dimension[keyPath: value] / 100, 1))
            return radarPoint(center: center, radius: radius, index: index, count: dimensions.count, scale: scale)
        }
        guard points.count >= 3 else { return Path() }

        var path = Path()
        for (index, point) in points.enumerated() {
            if index == points.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func radarPoint(
        center: CGPoint,
        radius: CGFloat,
        index: Int,
        count: Int,
        scale: Double
    ) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) / Double(count) * 2 * Double.pi
        return CGPoint(
            x: center.x + cos(angle) * radius * scale,
            y: center.y + sin(angle) * radius * scale
        )
    }
}

private struct RadarAxisLabel: View {
    let dimension: InvestmentProfileDimension

    var body: some View {
        Text(dimension.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(PortfolixTheme.secondaryText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityHidden(true)
    }
}

private struct RadarValueBadge: View {
    let dimension: InvestmentProfileDimension

    var body: some View {
        Text("\(Int(round(dimension.value)))")
        .font(PortfolixTypography.captionEmphasis)
        .monospacedDigit()
        .foregroundStyle(dimension.color)
        .padding(.horizontal, PortfolixSpacing.sm)
        .padding(.vertical, PortfolixSpacing.xs)
        .background(PortfolixTheme.panelSoft.opacity(0.86), in: Capsule())
    }
}

extension PortfolioStore {
    private var otherPositionShareID: Position.ID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    }

    fileprivate var positionShareItems: [PositionShareItem] {
        let totalValue = positions.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue }
        guard totalValue > 0 else { return [] }
        let maximumVisibleHoldingCount = 10

        let palette = [
            PortfolixTheme.lilac,
            PortfolixTheme.mint,
            PortfolixTheme.rose,
            PortfolixTheme.blue,
            PortfolixTheme.amber,
            PortfolixTheme.violet,
        ]

        let sortedPositions = positions
            .sorted {
                if $0.marketValueCNY == $1.marketValueCNY {
                    return $0.name.localizedCompare($1.name) == .orderedAscending
                }
                return $0.marketValueCNY > $1.marketValueCNY
            }

        var items = sortedPositions
            .prefix(maximumVisibleHoldingCount)
            .enumerated()
            .map { index, position in
                PositionShareItem(
                    id: position.id,
                    name: position.name,
                    value: position.marketValueCNY.doubleValue / totalValue * 100,
                    color: palette[index % palette.count]
                )
            }

        let otherValue = sortedPositions
            .dropFirst(maximumVisibleHoldingCount)
            .reduce(0.0) { $0 + $1.marketValueCNY.doubleValue }
        if otherValue > 0 {
            items.append(
                PositionShareItem(
                    id: otherPositionShareID,
                    name: localizedText("其他", "Other", language: appLanguage),
                    value: otherValue / totalValue * 100,
                    color: PortfolixTheme.tertiaryText
                )
            )
        }

        return items
    }

    var investmentProfileDimensions: [InvestmentProfileDimension] {
        let aiScores = investmentProfileAIScoresForDisplay
        return localInvestmentProfileScoresForAI.map { score in
            return InvestmentProfileDimension(
                id: score.id,
                title: investmentProfileTitle(for: score.id),
                value: min(max(aiScores[score.id] ?? score.score, 0), 100),
                color: PortfolixTheme.lilac
            )
        }
    }

    var localInvestmentProfileScoresForAI: [AIInvestmentProfileScore] {
        let context = AIAnalysisStoreContext(
            displayCurrency: displayCurrency,
            convertedTotalValue: totalValueCNY,
            convertedTotalProfit: totalProfitCNY,
            totalProfitRate: totalProfitRate,
            riskProfileConfigured: riskProfileConfigured,
            riskProfileVersion: riskProfileVersion,
            riskLevel: riskLevel,
            positionLimit: positionLimit,
            cryptoLimit: cryptoLimit,
            foreignCurrencyLimit: foreignCurrencyLimit,
            liquidityMinimum: liquidityMinimum,
            riskConstraintEvaluation: riskConstraintEvaluation
        )
        let exposures = InvestmentProfileEngine.merge(
            positions: positions,
            cached: investmentProfileExposureCache
        )
        return InvestmentProfileEngine.score(positions: positions, exposures: exposures, context: context).scores
    }

    private func investmentProfileTitle(for id: String) -> String {
        switch id {
        case "growth": localizedText("成长", "Growth", language: appLanguage)
        case "global": localizedText("全球化", "Global", language: appLanguage)
        case "diversification": localizedText("分散", "Diversified", language: appLanguage)
        case "defense": localizedText("防守", "Defense", language: appLanguage)
        case "cashflow": localizedText("现金流", "Cash Flow", language: appLanguage)
        default: localizedText("活跃", "Activity", language: appLanguage)
        }
    }
}

private enum DailyProfitDisplayMode: String, CaseIterable, Identifiable {
    case calendar
    case chart

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .chart: "chart.bar.xaxis"
        }
    }
}

private struct DailyProfitCard: View {
    @EnvironmentObject private var store: PortfolioStore
    @State private var displayMode: DailyProfitDisplayMode = .calendar
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var highlightedDate: Date?

    private let calendar = Calendar.current

    private var monthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: selectedMonth)
            ?? DateInterval(start: selectedMonth, duration: 31 * 86_400)
    }

    private var points: [DailyProfitPoint] {
        store.dailyProfitHistory.filter { monthInterval.contains($0.date) }
    }

    private var pointsByDay: [Date: DailyProfitPoint] {
        Dictionary(uniqueKeysWithValues: points.map { (calendar.startOfDay(for: $0.date), $0) })
    }

    private var highlightedPoint: DailyProfitPoint? {
        guard let highlightedDate else { return nil }
        return pointsByDay[calendar.startOfDay(for: highlightedDate)]
    }

    private var monthlyProfitCNY: Decimal {
        points.reduce(0) { $0 + $1.amountCNY }
    }

    private var profitableDayCount: Int {
        points.filter { $0.amountCNY > 0 }.count
    }

    private var lossDayCount: Int {
        points.filter { $0.amountCNY < 0 }.count
    }

    private var earliestMonth: Date {
        guard let earliestDate = store.dailyProfitHistory.first?.date else {
            return currentMonth
        }
        return calendar.dateInterval(of: .month, for: earliestDate)?.start ?? currentMonth
    }

    private var currentMonth: Date {
        calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    }

    private var canMoveBackward: Bool {
        selectedMonth > earliestMonth
    }

    private var canMoveForward: Bool {
        selectedMonth < currentMonth
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                header
                summary

                Group {
                    if points.isEmpty {
                        DashboardEmptyState(title: localizedText("本月暂无盈亏记录", "No daily P&L for this month", language: store.appLanguage))
                    } else if displayMode == .calendar {
                        calendarView
                    } else {
                        chartView
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 192, maxHeight: 192)
                .offset(y: PortfolixSpacing.sm)
            }
            .frame(height: PortfolixLayout.dashboardTrendContentHeight, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            HStack(spacing: PortfolixSpacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.lilac)
                    .frame(width: 16)

                Text(localizedText("每日盈亏", "Daily P&L", language: store.appLanguage))
                    .font(PortfolixTypography.sectionTitle)
                    .foregroundStyle(PortfolixTheme.primaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)

            Spacer(minLength: PortfolixSpacing.xs)

            HStack(spacing: PortfolixSpacing.md) {
                HStack(spacing: 0) {
                    Button {
                        moveMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canMoveBackward ? PortfolixTheme.secondaryText : PortfolixTheme.tertiaryText)
                    .disabled(!canMoveBackward)
                    .accessibilityLabel(localizedText("上个月", "Previous month", language: store.appLanguage))

                    Text(monthTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PortfolixTheme.secondaryText)
                        .monospacedDigit()
                        .frame(width: 56)

                    Button {
                        moveMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canMoveForward ? PortfolixTheme.secondaryText : PortfolixTheme.tertiaryText)
                    .disabled(!canMoveForward)
                    .accessibilityLabel(localizedText("下个月", "Next month", language: store.appLanguage))
                }
                .padding(.horizontal, PortfolixSpacing.sm)
                .padding(.vertical, PortfolixSpacing.xs)
                .frame(height: PortfolixLayout.dashboardCompactControlHeight)
                .portfolixGlass(
                    in: Capsule(),
                    fallbackTint: PortfolixTheme.panelSoft,
                    fallbackOpacity: 0.48,
                    interactive: true
                )
                .contentShape(Capsule())

                Picker(
                    localizedText("显示方式", "Display mode", language: store.appLanguage),
                    selection: $displayMode
                ) {
                    ForEach(DailyProfitDisplayMode.allCases) { mode in
                        Image(systemName: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: PortfolixLayout.dashboardCompactControlHeight)
                .onChange(of: displayMode) { _, _ in
                    highlightedDate = nil
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, PortfolixSpacing.xs)
    }

    private var summary: some View {
        HStack(alignment: .lastTextBaseline, spacing: PortfolixSpacing.sm) {
            Text(highlightedPoint.map { dayTitle($0.date) }
                ?? localizedText("本月累计", "Month total", language: store.appLanguage))
                .foregroundStyle(PortfolixTheme.tertiaryText)
                .lineLimit(1)

            Text(moneyText(highlightedPoint?.amountCNY ?? monthlyProfitCNY))
                .monospacedDigit()
                .foregroundStyle(profitColor(highlightedPoint?.amountCNY ?? monthlyProfitCNY))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: PortfolixSpacing.xs)

            Text(
                localizedText(
                    "盈利 \(profitableDayCount) · 亏损 \(lossDayCount)",
                    "\(profitableDayCount) up · \(lossDayCount) down",
                    language: store.appLanguage
                )
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(PortfolixTheme.tertiaryText)
            .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .frame(height: 16)
        .padding(.trailing, PortfolixSpacing.xs)
    }

    private var calendarView: some View {
        VStack(spacing: PortfolixSpacing.xs) {
            LazyVGrid(columns: calendarColumns, spacing: 0) {
                ForEach(Array(weekdayTitles.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(PortfolixTheme.tertiaryText)
                        .frame(maxWidth: .infinity, minHeight: 12)
                }
            }

            LazyVGrid(columns: calendarColumns, spacing: PortfolixSpacing.xs) {
                ForEach(calendarSlots) { slot in
                    if let date = slot.date {
                        calendarCell(for: date)
                    } else {
                        Color.clear
                            .frame(height: calendarCellHeight)
                    }
                }
            }
        }
    }

    private var chartView: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(PortfolixTheme.borderStrong)
                .lineStyle(StrokeStyle(lineWidth: 1))

            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date),
                    y: .value("Daily P&L", convertedAmount(point.amountCNY))
                )
                .foregroundStyle(profitColor(point.amountCNY))
                .cornerRadius(2)
            }

            if let highlightedPoint {
                RuleMark(x: .value("Selected date", highlightedPoint.date))
                    .foregroundStyle(PortfolixTheme.lilac.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: chartYDomain)
        .chartXAxis {
            AxisMarks(values: chartAxisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(PortfolixTheme.border)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(String(calendar.component(.day, from: date)))
                            .foregroundStyle(PortfolixTheme.tertiaryText)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(PortfolixTheme.border)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(compactNumber(amount))
                            .foregroundStyle(PortfolixTheme.tertiaryText)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        updateHighlightedDate(for: phase, proxy: proxy, geometry: geometry)
                    }
            }
        }
    }

    @ViewBuilder
    private func calendarCell(for date: Date) -> some View {
        let point = pointsByDay[calendar.startOfDay(for: date)]
        let amount = point?.amountCNY
        let isToday = calendar.isDateInToday(date)
        let isHighlighted = highlightedDate.map { calendar.isDate($0, inSameDayAs: date) } == true

        VStack(spacing: 0) {
            Text(String(calendar.component(.day, from: date)))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(date > Date() ? PortfolixTheme.tertiaryText : PortfolixTheme.primaryText)

            if let amount {
                Text(compactCellAmount(amount))
                    .font(.system(size: 7, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(profitColor(amount))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: calendarCellHeight, maxHeight: calendarCellHeight)
        .background(cellBackground(amount), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if isToday || isHighlighted {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PortfolixTheme.lilac, lineWidth: isHighlighted ? 1.5 : 1)
            }
        }
        .onHover { hovering in
            highlightedDate = hovering ? date : nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calendarAccessibilityLabel(date: date, amount: amount))
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: PortfolixSpacing.xs), count: 7)
    }

    private var weekdayTitles: [String] {
        store.appLanguage == .english
            ? ["M", "T", "W", "T", "F", "S", "S"]
            : ["一", "二", "三", "四", "五", "六", "日"]
    }

    private var calendarSlots: [DailyProfitCalendarSlot] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: selectedMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: selectedMonth)
        let leadingEmptyCount = (weekday + 5) % 7
        var slots = (0..<leadingEmptyCount).map { DailyProfitCalendarSlot(id: "leading-\($0)", date: nil) }
        slots += dayRange.compactMap { day in
            let date = calendar.date(byAdding: .day, value: day - 1, to: selectedMonth)
            return DailyProfitCalendarSlot(id: "day-\(day)", date: date)
        }
        let minimumSlotCount = 35
        let requiredSlotCount = max(minimumSlotCount, Int(ceil(Double(slots.count) / 7.0)) * 7)
        while slots.count < requiredSlotCount {
            slots.append(DailyProfitCalendarSlot(id: "trailing-\(slots.count)", date: nil))
        }
        return slots
    }

    private var calendarRowCount: Int {
        max(calendarSlots.count / 7, 5)
    }

    private var calendarCellHeight: CGFloat {
        calendarRowCount == 6 ? 26 : 32
    }

    private var monthTitle: String {
        let components = calendar.dateComponents([.year, .month], from: selectedMonth)
        let year = components.year ?? 0
        let month = components.month ?? 0
        if store.appLanguage == .chinese {
            return "\(year)年\(month)月"
        }
        return Self.englishMonthFormatter.string(from: selectedMonth)
    }

    private var chartAxisDates: [Date] {
        let lastDay = calendar.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
        return [1, 8, 15, 22, lastDay].compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: selectedMonth)
        }
    }

    private var chartYDomain: ClosedRange<Double> {
        let magnitude = max(points.map { abs(convertedAmount($0.amountCNY)) }.max() ?? 0, 1) * 1.12
        return -magnitude ... magnitude
    }

    private func moveMonth(by offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: selectedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedMonth = newMonth
            highlightedDate = nil
        }
    }

    private func updateHighlightedDate(for phase: HoverPhase, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            highlightedDate = nil
            return
        }
        switch phase {
        case let .active(location):
            let frame = geometry[plotFrame]
            let x = location.x - frame.origin.x
            guard frame.contains(location), let date: Date = proxy.value(atX: x) else {
                highlightedDate = nil
                return
            }
            highlightedDate = points.min {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }?.date
        case .ended:
            highlightedDate = nil
        }
    }

    private func convertedAmount(_ amountCNY: Decimal) -> Double {
        (amountCNY * store.displayCurrency.rateFromCNY).doubleValue
    }

    private func moneyText(_ amountCNY: Decimal) -> String {
        let converted = amountCNY * store.displayCurrency.rateFromCNY
        return amountCNY == 0
            ? formatMoney(converted, currency: store.displayCurrency)
            : formatSignedMoney(converted, currency: store.displayCurrency)
    }

    private func compactCellAmount(_ amountCNY: Decimal) -> String {
        compactNumber(convertedAmount(amountCNY), includesPlus: true)
    }

    private func compactNumber(_ value: Double, includesPlus: Bool = false) -> String {
        let sign = value < 0 ? "−" : (includesPlus && value > 0 ? "+" : "")
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return String(format: "%@%.1fM", sign, magnitude / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%@%.1fK", sign, magnitude / 1_000)
        }
        return String(format: "%@%.0f", sign, magnitude)
    }

    private func profitColor(_ amount: Decimal) -> Color {
        if amount > 0 { return PortfolixTheme.mint }
        if amount < 0 { return PortfolixTheme.danger }
        return PortfolixTheme.secondaryText
    }

    private func cellBackground(_ amount: Decimal?) -> Color {
        guard let amount else { return .clear }
        if amount > 0 { return PortfolixTheme.mint.opacity(0.13) }
        if amount < 0 { return PortfolixTheme.danger.opacity(0.13) }
        return PortfolixTheme.panelSoft.opacity(0.55)
    }

    private func dayTitle(_ date: Date) -> String {
        if store.appLanguage == .chinese {
            return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
        }
        return Self.englishDayFormatter.string(from: date)
    }

    private func calendarAccessibilityLabel(date: Date, amount: Decimal?) -> String {
        let dateText = dayTitle(date)
        guard let amount else {
            return localizedText("\(dateText)，无盈亏记录", "\(dateText), no P&L record", language: store.appLanguage)
        }
        return localizedText("\(dateText)，\(moneyText(amount))", "\(dateText), \(moneyText(amount))", language: store.appLanguage)
    }

    private static let englishMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    private static let englishDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private struct DailyProfitCalendarSlot: Identifiable {
    let id: String
    let date: Date?
}

private struct DashboardEmptyState: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(PortfolixTheme.tertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
