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
                    DataSourceCard()
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
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(PortfolixTheme.violet.opacity(0.16))
                .frame(width: 130, height: 130)
                .blur(radius: 35)
                .offset(x: 15, y: 35)
                .allowsHitTesting(false)
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
        .help(localizedText("刷新最新行情", "Refresh latest prices", language: store.appLanguage))
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

                    Picker(localizedText("趋势指标", "Metric", language: store.appLanguage), selection: $store.trendMetric) {
                        ForEach(TrendMetric.allCases) { metric in
                            Text(metric.title(language: store.appLanguage)).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 188, alignment: .trailing)

                    Picker(localizedText("时间范围", "Range", language: store.appLanguage), selection: $store.trendRange) {
                        ForEach(TrendRange.allCases) { range in
                            Text(range.title(language: store.appLanguage)).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 184, alignment: .trailing)
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
        .overlay(alignment: .bottomLeading) {
            Ellipse()
                .fill(PortfolixTheme.violet.opacity(0.14))
                .frame(width: 360, height: 90)
                .blur(radius: 40)
                .offset(x: 150, y: 26)
                .allowsHitTesting(false)
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
    private let maximumPrimaryPositionCount = 10

    private var primaryPositions: [Position] {
        Array(
            store.positions
                .sorted {
                    if $0.marketValueCNY == $1.marketValueCNY {
                        return $0.name.localizedCompare($1.name) == .orderedAscending
                    }
                    return $0.marketValueCNY > $1.marketValueCNY
                }
                .prefix(maximumPrimaryPositionCount)
        )
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("主要持仓", "Top Holdings", language: store.appLanguage), symbol: "list.bullet.rectangle") {
                    Button(localizedText("查看明细", "View Details", language: store.appLanguage)) {
                        store.selection = .positions
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PortfolixTheme.lilac)
                }

                if primaryPositions.isEmpty {
                    DashboardEmptyState(title: localizedText("暂无持仓", "No holdings yet", language: store.appLanguage))
                        .frame(maxWidth: .infinity, minHeight: 82)
                } else {
                    PositionHeaderRow()

                    ForEach(primaryPositions) { position in
                        CompactPositionRow(position: position)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PositionHeaderRow: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        HStack(spacing: 0) {
            Text(localizedText("资产", "Asset", language: store.appLanguage)).positionColumn(alignment: .center)
            Text(localizedText("近 1 周走势", "1W Trend", language: store.appLanguage)).positionColumn(alignment: .center)
            Text(localizedText("类型", "Type", language: store.appLanguage)).positionColumn(alignment: .center)
            Text(localizedText("当前市值", "Market Value", language: store.appLanguage)).positionColumn(alignment: .center)
            Text(localizedText("持仓收益率", "Return Rate", language: store.appLanguage)).positionColumn(alignment: .center)
            Text(localizedText("今日收益", "Today Return", language: store.appLanguage)).positionColumn(alignment: .center)
            Text(localizedText("价格日期", "Price Date", language: store.appLanguage)).positionColumn(alignment: .center)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(PortfolixTheme.tertiaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(PortfolixTheme.panelElevated, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact))
    }
}

private struct CompactPositionRow: View {
    @EnvironmentObject private var store: PortfolioStore
    let position: Position

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: PortfolixSpacing.sm) {
                Circle()
                    .fill(position.category.color.opacity(0.18))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(String(position.name.prefix(1)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(position.category.color)
                    }

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
                InvestmentProfileHeader(language: store.appLanguage)

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
                text: localizedText(
                    "投资画像由AI辅助分析生成",
                    "Investment Profile is AI-assisted",
                    language: language
                )
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
        let cornerRadius: CGFloat = 8
        for index in points.indices {
            let previous = points[(index - 1 + points.count) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let entry = roundedCornerPoint(from: current, toward: previous, distance: cornerRadius)
            let exit = roundedCornerPoint(from: current, toward: next, distance: cornerRadius)

            if index == points.startIndex {
                path.move(to: entry)
            } else {
                path.addLine(to: entry)
            }
            path.addQuadCurve(to: exit, control: current)
        }
        path.closeSubpath()
        return path
    }

    private func roundedCornerPoint(from origin: CGPoint, toward target: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let length = max(hypot(dx, dy), 0.001)
        let boundedDistance = min(distance, length * 0.35)
        return CGPoint(
            x: origin.x + dx / length * boundedDistance,
            y: origin.y + dy / length * boundedDistance
        )
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
        let localDimensions = localInvestmentProfileDimensions
        let aiScores = investmentProfileAIScoresForDisplay
        return localDimensions.map { dimension in
            guard let aiScore = aiScores[dimension.id] else { return dimension }
            let calibratedScore = clampProfileValue(
                min(max(aiScore, dimension.value - 5), dimension.value + 5)
            )
            return InvestmentProfileDimension(
                id: dimension.id,
                title: dimension.title,
                value: calibratedScore,
                color: dimension.color
            )
        }
    }

    var localInvestmentProfileScoresForAI: [AIInvestmentProfileScore] {
        localInvestmentProfileDimensions.map { dimension in
            AIInvestmentProfileScore(
                id: dimension.id,
                score: dimension.value,
                reason: "Local deterministic baseline"
            )
        }
    }

    private var localInvestmentProfileDimensions: [InvestmentProfileDimension] {
        let totalValue = positions.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue }
        let categoryValues = Dictionary(grouping: positions, by: \.category)
            .mapValues { positions in positions.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue } }
        let currencyValues = Dictionary(grouping: positions, by: \.quoteCurrency)
            .mapValues { positions in positions.reduce(0.0) { $0 + $1.marketValueCNY.doubleValue } }
        let positiveValue = max(totalValue, 0)

        func allocation(_ category: AssetCategory) -> Double {
            guard totalValue > 0 else { return 0 }
            return (categoryValues[category] ?? 0) / totalValue * 100
        }

        func currencyAllocation(_ currency: DisplayCurrency) -> Double {
            guard totalValue > 0 else { return 0 }
            return (currencyValues[currency] ?? 0) / totalValue * 100
        }

        func weightedScore(_ scoring: (Position) -> Double) -> Double {
            guard totalValue > 0 else { return 0 }
            return positions.reduce(0.0) { partial, position in
                partial + scoring(position) * position.marketValueCNY.doubleValue / totalValue
            }
        }

        let evaluation = riskConstraintEvaluation
        let positionShares = positions.map { position in
            guard positiveValue > 0 else { return 0.0 }
            return max(position.marketValueCNY.doubleValue / positiveValue, 0.0)
        }
        let hhi = positionShares.reduce(0.0) { $0 + $1 * $1 }
        let effectivePositionCount = hhi > 0 ? min(1 / hhi, 12) : 0
        let effectivePositionScore = effectivePositionCount / 12 * 38
        let positionCountScore = min(Double(positions.count), 10) / 10 * 14
        let categoryCount = Set(positions.map(\.category)).count
        let categoryCountScore = min(Double(categoryCount), 5) / 5 * 22
        let currencyCount = Set(positions.map(\.quoteCurrency)).count
        let currencyCountScore = min(Double(currencyCount), 4) / 4 * 14
        let concentrationPenalty = max(evaluation.largestPositionPercent - 14, 0) * 1.15
        let topThreePercent = positions
            .sorted { $0.marketValueCNY > $1.marketValueCNY }
            .prefix(3)
            .reduce(0.0) { $0 + ($1.marketValueCNY.doubleValue / max(positiveValue, 0.001) * 100) }
        let topThreePenalty = max(topThreePercent - 62, 0) * 0.32
        let profitableAllocation = positions.reduce(0.0) { partial, position in
            guard totalValue > 0, position.profitRate > 0 else { return partial }
            return partial + position.marketValueCNY.doubleValue / totalValue * 100
        }
        let staleAllocation = positions.reduce(0.0) { partial, position in
            guard totalValue > 0, position.freshness == .stale else { return partial }
            return partial + position.marketValueCNY.doubleValue / totalValue * 100
        }

        let diversification = clampProfileValue(
            18 + effectivePositionScore + positionCountScore + categoryCountScore + currencyCountScore
                - concentrationPenalty - topThreePenalty
        )
        let growth = weightedScore { position in
            switch position.category {
            case .crypto: 88
            case .usStock, .hkStock: 72
            case .cnStock, .bStock: 64
            case .fund: 52
            case .cash: 12
            }
        } + profitableAllocation * 0.08 - evaluation.cashAllocationPercent * 0.12
        let defense = weightedScore { position in
            switch position.category {
            case .cash: 96
            case .fund: 76
            case .cnStock, .hkStock, .usStock: 52
            case .bStock: 46
            case .crypto: 20
            }
        } - concentrationPenalty * 0.42 - allocation(.crypto) * 0.22 - staleAllocation * 0.18
        let cashFlow = clampProfileValue(
            8
                + evaluation.cashAllocationPercent * 1.55
                + allocation(.fund) * 0.52
                + profitableAllocation * 0.12
        )
        let activity = weightedScore { position in
            switch position.category {
            case .crypto: 92
            case .cnStock, .hkStock, .usStock: 76
            case .bStock: 58
            case .fund: 44
            case .cash: 24
            }
        } + min(Double(positions.count), 12) / 12 * 8 - evaluation.cashAllocationPercent * 0.08
        let overseasMarketExposure = allocation(.usStock) + allocation(.hkStock) + allocation(.bStock)
        let globalExposure = clampProfileValue(
            evaluation.nonCNYAllocationPercent * 1.05
                + overseasMarketExposure * 0.42
                + currencyAllocation(.usd) * 0.22
                + currencyAllocation(.hkd) * 0.18
                + currencyAllocation(.usdt) * 0.12
        )

        return [
            InvestmentProfileDimension(
                id: "growth",
                title: localizedText("成长", "Growth", language: appLanguage),
                value: clampProfileValue(growth + riskTiltAdjustment(for: .growth)),
                color: PortfolixTheme.lilac
            ),
            InvestmentProfileDimension(
                id: "global",
                title: localizedText("全球化", "Global", language: appLanguage),
                value: clampProfileValue(globalExposure),
                color: PortfolixTheme.lilac
            ),
            InvestmentProfileDimension(
                id: "diversification",
                title: localizedText("分散", "Diversified", language: appLanguage),
                value: diversification,
                color: PortfolixTheme.lilac
            ),
            InvestmentProfileDimension(
                id: "defense",
                title: localizedText("防守", "Defense", language: appLanguage),
                value: clampProfileValue(defense + riskTiltAdjustment(for: .defense)),
                color: PortfolixTheme.lilac
            ),
            InvestmentProfileDimension(
                id: "cashflow",
                title: localizedText("现金流", "Cash Flow", language: appLanguage),
                value: cashFlow,
                color: PortfolixTheme.lilac
            ),
            InvestmentProfileDimension(
                id: "activity",
                title: localizedText("活跃", "Activity", language: appLanguage),
                value: clampProfileValue(activity + riskTiltAdjustment(for: .activity)),
                color: PortfolixTheme.lilac
            ),
        ]
    }

    private enum ProfileRiskTiltTarget {
        case growth
        case defense
        case activity
    }

    private func riskTiltAdjustment(for target: ProfileRiskTiltTarget) -> Double {
        let riskBudget = (positionLimit - 30) * 0.06
            + (cryptoLimit - 15) * 0.08
            + (foreignCurrencyLimit - 50) * 0.04
            - (liquidityMinimum - 10) * 0.08
        switch target {
        case .growth, .activity:
            return riskBudget
        case .defense:
            return -riskBudget
        }
    }

    private func clampProfileValue(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}

private struct DataSourceCard: View {
    @EnvironmentObject private var store: PortfolioStore

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                SectionHeader(title: localizedText("数据源状态", "Data Sources", language: store.appLanguage), symbol: "antenna.radiowaves.left.and.right")

                if store.sourceStatuses.isEmpty {
                    DashboardEmptyState(title: localizedText("尚未同步行情", "Prices not synced yet", language: store.appLanguage))
                        .frame(maxWidth: .infinity, minHeight: 190)
                } else {
                    ForEach(store.sourceStatuses) { source in
                        HStack(spacing: PortfolixSpacing.sm) {
                            DataSourceIcon(source: source)

                            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                                Text(source.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(PortfolixTheme.primaryText)
                                    .lineLimit(1)
                                Text(source.displayDetail(language: store.appLanguage))
                                    .font(.system(size: 10))
                                    .foregroundStyle(PortfolixTheme.tertiaryText)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(source.stateText(language: store.appLanguage))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(source.color)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(height: PortfolixLayout.dashboardTrendContentHeight, alignment: .topLeading)
        }
    }
}

private struct DataSourceIcon: View {
    let source: DataSourceStatus

    var body: some View {
        Group {
            if source.name == "OKX" {
                OKXLogoMark(color: source.color)
            } else {
                Image(systemName: source.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(source.color)
            }
        }
        .frame(width: 24, height: 24)
        .background(source.color.opacity(0.15), in: RoundedRectangle(cornerRadius: PortfolixRadius.compact))
        .accessibilityHidden(true)
    }
}

private struct OKXLogoMark: View {
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 1.2).fill(color).frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1.2).fill(color).frame(width: 5, height: 5)
            }
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 1.2).fill(color).frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1.2).fill(color.opacity(0.32)).frame(width: 5, height: 5)
            }
        }
    }
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
