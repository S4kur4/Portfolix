import AppKit
import Charts
import Observation
import SwiftUI

struct DashboardView: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                DashboardHeader()

                GoldenRatioDashboardRow(spacing: PortfolixSpacing.md) {
                    PortfolioHeroCard()
                } trailing: {
                    DailyProfitCard(contentHeight: PortfolixLayout.dashboardHeroContentHeight)
                }
                .frame(maxWidth: .infinity)

                GoldenRatioDashboardRow(spacing: PortfolixSpacing.md) {
                    PerformanceRiskCard()
                } trailing: {
                    InvestmentCloudCard(contentHeight: PortfolixLayout.dashboardTrendContentHeight)
                }
                .frame(maxWidth: .infinity)

                AssetMixBarCard()

                RecentPositionsCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
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

        let proposedWidth = proposal.width ?? subviews.reduce(spacing) {
            $0 + $1.sizeThatFits(.unspecified).width
        }
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
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        PageHeader(title: localizedText("资产总览", "Overview", language: store.appLanguage)) {
            Button {
                store.presentNewPositionEditor()
            } label: {
                Label(localizedText("添加资产", "Add Asset", language: store.appLanguage), systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

private enum PortfolioHeroCardLayout {
    /// The currency picker and mini chart share a width to align their leading edges.
    static let trailingControlWidth: CGFloat = 230
    static let trendChartHeight: CGFloat = 96
}

private struct PortfolioHeroCard: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Panel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(
                    title: localizedText("组合价值", "Portfolio Value", language: store.appLanguage),
                    symbol: "briefcase.fill"
                ) {
                    HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
                        if store.isRefreshing {
                            Text(localizedText("同步行情中…", "Updating quotes…", language: store.appLanguage))
                                .font(PortfolixTypography.caption)
                                .foregroundStyle(PortfolixTheme.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        } else {
                            RelativeTimeText { now in
                                updateSummary(now: now)
                            }
                            .font(PortfolixTypography.caption)
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        }

                        PriceRefreshButton()

                        PortfolixGlassSegmentedPicker(
                            title: localizedText("展示币种", "Display Currency", language: store.appLanguage),
                            selection: $store.displayCurrency,
                            options: DisplayCurrency.allCases,
                            optionTitle: { $0.rawValue },
                            width: PortfolioHeroCardLayout.trailingControlWidth
                        )
                    }
                }

                Text(heroValueText)
                    .font(PortfolixTypography.portfolioHeroValue)
                    .monospacedDigit()
                    .portfolixNumericTransition(heroValueText)
                    .foregroundStyle(PortfolixTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.top, PortfolixSpacing.lg)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(localizedText("组合总价值", "Total portfolio value", language: store.appLanguage))
                    .accessibilityValue(heroValueText)

                HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.xs) {
                    Text(localizedText("今日盈亏", "Today's P&L", language: store.appLanguage))
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondary)
                        .lineLimit(1)

                    Text(todayProfitText)
                        .font(PortfolixTypography.headlineValue)
                        .monospacedDigit()
                        .portfolixNumericTransition(todayProfitText)
                        .foregroundStyle(todayProfitColor)
                        .lineLimit(1)

                    Text(todayProfitRateText)
                        .font(PortfolixTypography.headlineValue)
                        .monospacedDigit()
                        .portfolixNumericTransition(todayProfitRateText)
                        .foregroundStyle(todayProfitRateColor)
                        .lineLimit(1)
                        .padding(.leading, PortfolixSpacing.xs)
                }
                .padding(.top, PortfolixSpacing.sm)
                .accessibilityElement(children: .combine)

                Spacer(minLength: PortfolixSpacing.md)

                HStack(alignment: .top, spacing: PortfolixSpacing.lg) {
                    HeroMetricsGrid()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    HeroValueTrendChart()
                        .frame(
                            width: PortfolioHeroCardLayout.trailingControlWidth,
                            height: PortfolioHeroCardLayout.trendChartHeight
                        )
                }
                .frame(height: PortfolioHeroCardLayout.trendChartHeight, alignment: .top)
            }
            .frame(height: PortfolixLayout.dashboardHeroContentHeight, alignment: .topLeading)
            .padding(PortfolixLayout.cardPadding)
        }
    }

    private var heroValueText: String {
        formatHeroMoney(store.converted(store.totalValueCNY), currency: store.displayCurrency)
    }

    private func updateSummary(now: Date) -> String {
        let latestPosition = store.positions.lazy
            .map { (position: $0, date: $0.fetchedDate ?? .distantPast) }
            .max { $0.date < $1.date }?.position
        guard let latestPosition else {
            return localizedText("尚未添加持仓", "No holdings yet", language: store.appLanguage)
        }
        return latestPosition.shortRelativeUpdateText(now: now, language: store.appLanguage)
    }

    private var todayProfitText: String {
        guard store.todayProfitIsAvailable() else { return "—" }
        let convertedProfit = store.converted(store.todayProfitCNY)
        return store.todayProfitCNY == 0
            ? formatMoney(convertedProfit, currency: store.displayCurrency)
            : formatSignedMoney(convertedProfit, currency: store.displayCurrency)
    }

    private var todayProfitRateText: String {
        store.todayProfitIsAvailable() ? (store.todayProfitRate == 0 ? "0.00%" : formatPercent(store.todayProfitRate)) : "—"
    }

    private var todayProfitColor: Color {
        valueColor(for: store.todayProfitCNY)
    }

    private var todayProfitRateColor: Color {
        valueColor(for: store.todayProfitRate)
    }

    private func valueColor(for value: Decimal) -> Color {
        PortfolixTheme.performanceColor(for: value, scheme: store.performanceColorScheme)
    }
}

private struct HeroMetricsGrid: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        let thirtyDayChange = thirtyDayChange
        let changeColor = PortfolixTheme.performanceColor(
            for: thirtyDayChange?.amountCNY ?? 0, scheme: store.performanceColorScheme
        )
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: PortfolixSpacing.lg) {
                HeroMetricCell(
                    label: localizedText("已实现收益", "Realized Profit", language: store.appLanguage),
                    value: realizedReturnText,
                    rate: realizedReturnRateText,
                    valueColor: realizedReturnColor,
                    rateColor: realizedReturnColor
                )
                HeroMetricCell(
                    label: localizedText("近 30 天", "Last 30 Days", language: store.appLanguage),
                    value: thirtyDayChange.map { moneyText($0.amountCNY) } ?? "—",
                    rate: thirtyDayChange.map { formatPercent($0.rate) },
                    valueColor: changeColor,
                    rateColor: changeColor
                )
            }

            Spacer(minLength: PortfolixSpacing.sm)

            HStack(alignment: .top, spacing: PortfolixSpacing.lg) {
                HeroMetricCell(
                    label: localizedText("持仓成本", "Cost Basis", language: store.appLanguage),
                    value: costBasisText,
                    rate: nil,
                    valueColor: PortfolixTheme.text,
                    rateColor: nil
                )
                HeroMetricCell(
                    label: localizedText("现金", "Cash", language: store.appLanguage),
                    value: cashAmountText,
                    rate: nil,
                    valueColor: PortfolixTheme.text,
                    rateColor: nil
                )
            }
        }
    }

    /// Show realized P&L in the display currency when the cost basis is known.
    private var realizedReturnText: String {
        guard store.realizedProfitIsAvailable else { return "—" }

        let converted = store.converted(store.realizedProfitCNY)
        return store.realizedProfitCNY == 0
            ? formatMoney(converted, currency: store.displayCurrency)
            : formatSignedMoney(converted, currency: store.displayCurrency)
    }

    private var realizedReturnRateText: String? {
        guard store.realizedProfitIsAvailable, store.realizedCostCNY != 0 else { return nil }
        return store.realizedProfitRate == 0 ? "0.00%" : formatPercent(store.realizedProfitRate)
    }

    private var realizedReturnColor: Color {
        PortfolixTheme.performanceColor(for: store.realizedProfitCNY, scheme: store.performanceColorScheme)
    }

    private var thirtyDayChange: (amountCNY: Decimal, rate: Decimal)? {
        let history = store.snapshotHistory
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: .now)),
              let latest = history.max(by: { $0.date < $1.date }),
              let baseline = history.lazy.filter({ $0.date <= cutoff }).max(by: { $0.date < $1.date }),
              baseline.date < latest.date,
              latest.totalValueCNY.isFinite, baseline.totalValueCNY.isFinite
        else {
            return nil
        }

        let baselineValue = Decimal(baseline.totalValueCNY)
        let latestValue = Decimal(latest.totalValueCNY)
        let amount = latestValue - baselineValue
        let rate = baselineValue > 0 ? amount / baselineValue * 100 : 0
        return (amount, rate)
    }

    private func moneyText(_ amountCNY: Decimal) -> String {
        let converted = store.converted(amountCNY)
        return amountCNY == 0
            ? formatMoney(converted, currency: store.displayCurrency)
            : formatSignedMoney(converted, currency: store.displayCurrency)
    }

    private var costBasisText: String {
        formatMoney(store.converted(store.totalCostCNY), currency: store.displayCurrency)
    }

    private var cashAmountText: String {
        let cash = store.positions
            .filter { $0.category == .cash }
            .reduce(Decimal(0)) { $0 + $1.marketValueCNY }
        return formatMoney(store.converted(cash), currency: store.displayCurrency)
    }
}

private struct HeroMetricCell: View {
    let label: String
    let value: String
    let rate: String?
    let valueColor: Color
    let rateColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Text(label)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.xs) {
                Text(value)
                    .font(PortfolixTypography.headlineValue)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .portfolixNumericTransition(value)

                if let rate {
                    Text(rate)
                        .font(PortfolixTypography.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(rateColor ?? valueColor)
                        .lineLimit(1)
                        .portfolixNumericTransition(rate)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct HeroValueTrendPoint: Identifiable {
    let snapshot: PortfolioSnapshot
    let value: Double

    var id: UUID { snapshot.id }
}

private struct HeroValueTrendChart: View {
    @Environment(PortfolioStore.self) private var store
    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let cutoff = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let rate = store.displayCurrency.rateFromCNY.doubleValue
        let points = store.snapshotHistory
            .filter { $0.date >= cutoff && $0.totalValueCNY.isFinite }
            .sorted { $0.date < $1.date }
            .map { HeroValueTrendPoint(snapshot: $0, value: $0.totalValueCNY * rate) }

        HeroValueTrendPlot(points: points, calendar: calendar)
    }
}

private struct HeroValueTrendPlot: View {
    @Environment(PortfolioStore.self) private var store
    @State private var highlightedSnapshotID: UUID?
    let points: [HeroValueTrendPoint]
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Text(localizedText("近 30 天走势", "30-day trend", language: store.appLanguage))
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.tertiary)
                .lineLimit(1)

            if points.count >= 2 {
                chart
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedText("组合价值近 30 天走势", "Portfolio value over the last 30 days", language: store.appLanguage))
        .accessibilityValue(accessibilitySummary)
    }

    private var chart: some View {
        let yDomain = yDomain
        let xDomain = xDomain
        let axisDates = xAxisDates
        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.snapshot.date),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Value", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            PortfolixTheme.brandChart.opacity(0.32),
                            PortfolixTheme.brandChart.opacity(0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.snapshot.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .butt, lineJoin: .round))
                .foregroundStyle(PortfolixTheme.brandChart)
            }

            if let highlightedSnapshotID,
               let point = points.first(where: { $0.snapshot.id == highlightedSnapshotID }) {
                RuleMark(x: .value("Date", point.snapshot.date))
                    .foregroundStyle(PortfolixTheme.brandFocus)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("Date", point.snapshot.date),
                    y: .value("Value", point.value)
                )
                .symbolSize(30)
                .foregroundStyle(PortfolixTheme.text)
                .annotation(
                    position: shouldPlaceAnnotationLeading(for: point, in: xDomain) ? .topLeading : .topTrailing,
                    spacing: PortfolixSpacing.xs,
                    overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(point.snapshot.date.formatted(
                            Date.FormatStyle(locale: Locale(identifier: store.appLanguage == .english ? "en_US" : "zh_CN"))
                                .month().day()
                        ))
                            .foregroundStyle(PortfolixTheme.tertiary)
                        Text(formatMoney(Decimal(point.value), currency: store.displayCurrency))
                            .foregroundStyle(PortfolixTheme.text)
                    }
                    .portfolixChartTooltip()
                }
            } else if let last = points.last {
                PointMark(
                    x: .value("Date", last.snapshot.date),
                    y: .value("Value", last.value)
                )
                .symbolSize(22)
                .foregroundStyle(PortfolixTheme.text)
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
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(PortfolixTheme.border.opacity(0.8))
                AxisValueLabel(anchor: xAxisLabelAnchor(for: value.as(Date.self), dates: axisDates)) {
                    if let date = value.as(Date.self) {
                        Text(dayLabel(date))
                            .font(PortfolixTypography.chartAxis)
                            .monospacedDigit()
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(PortfolixTheme.border.opacity(0.8))
                AxisValueLabel {
                    if let numeric = value.as(Double.self) {
                        Text(axisValueLabel(numeric, span: yDomain.upperBound - yDomain.lowerBound))
                            .font(PortfolixTypography.chartAxis)
                            .monospacedDigit()
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: PortfolixSpacing.xs) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 13))
                .foregroundStyle(PortfolixTheme.tertiary)
            Text(localizedText("暂无走势数据", "No trend data yet", language: store.appLanguage))
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = points.first?.snapshot.date, let last = points.last?.snapshot.date else {
            let now = Date()
            return now.addingTimeInterval(-86_400)...now
        }

        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        if start < end {
            return start...end
        }
        return start...start.addingTimeInterval(86_400)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let lowest = values.min(), let highest = values.max() else {
            return 0...1
        }

        let padding = max((highest - lowest) * 0.2, max(abs(highest), 1) * 0.002)
        let lower = lowest >= 0 ? max(0, lowest - padding) : lowest - padding
        return lower...(highest + padding)
    }

    private var xAxisDates: [Date] {
        guard let first = points.first?.snapshot.date, let last = points.last?.snapshot.date, first < last else {
            return []
        }

        let middle = first.addingTimeInterval(last.timeIntervalSince(first) / 2)
        return [calendar.startOfDay(for: first), middle, calendar.startOfDay(for: last)]
    }

    private func xAxisLabelAnchor(for date: Date?, dates: [Date]) -> UnitPoint {
        guard let date, let first = dates.first, let last = dates.last else {
            return .top
        }
        if date == first { return .topLeading }
        if date == last { return .topTrailing }
        return .top
    }

    private func dayLabel(_ date: Date) -> String {
        Self.monthDayFormatter.string(from: date)
    }

    private func axisValueLabel(_ value: Double, span: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return String(format: span < 200_000 ? "%.2fM" : "%.1fM", value / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    private func shouldPlaceAnnotationLeading(for point: HeroValueTrendPoint, in xDomain: ClosedRange<Date>) -> Bool {
        let span = max(xDomain.upperBound.timeIntervalSince(xDomain.lowerBound), 1)
        let progress = point.snapshot.date.timeIntervalSince(xDomain.lowerBound) / span
        return progress > 0.7
    }

    private var accessibilitySummary: String {
        guard points.count >= 2, let first = points.first, let last = points.last else {
            return localizedText("暂无走势数据", "No trend data yet", language: store.appLanguage)
        }

        let start = formatMoney(Decimal(first.value), currency: store.displayCurrency)
        let end = formatMoney(Decimal(last.value), currency: store.displayCurrency)
        return localizedText("从 \(start) 到 \(end)", "From \(start) to \(end)", language: store.appLanguage)
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
                if highlightedSnapshotID != nil { highlightedSnapshotID = nil }
                return
            }
            let nearest = points.min {
                abs($0.snapshot.date.timeIntervalSince(date)) < abs($1.snapshot.date.timeIntervalSince(date))
            }?.snapshot.id
            if highlightedSnapshotID != nearest {
                highlightedSnapshotID = nearest
            }
        case .ended:
            highlightedSnapshotID = nil
        }
    }

    private static let monthDayFormatter = DashboardDateFormatters.monthDay
}

private struct PriceRefreshButton: View {
    @Environment(PortfolioStore.self) private var store
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
        .portfolixSecondaryGlass(in: Circle(), interactive: true)
        .opacity(store.isRefreshing ? 0.58 : isHovering ? 0.88 : 1)
        .onHover { isHovering = $0 }
        .accessibilityLabel(localizedText("刷新最新行情", "Refresh latest prices", language: store.appLanguage))
        .disabled(store.isRefreshing)
    }

    private var foregroundStyle: AnyShapeStyle {
        AnyShapeStyle(PortfolixTheme.text)
    }
}

enum PerformanceRiskRange: String, CaseIterable, Identifiable {
    case month
    case quarter
    case year
    case all

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .month: 29
        case .quarter: 89
        case .year: 364
        case .all: nil
        }
    }

    func title(language: AppLanguage) -> String {
        if language == .english {
            switch self {
            case .month: "1M"
            case .quarter: "3M"
            case .year: "1Y"
            case .all: "All"
            }
        } else {
            switch self {
            case .month: "1月"
            case .quarter: "3月"
            case .year: "1年"
            case .all: "全部"
            }
        }
    }
}

/// Shared hover date for the profit and drawdown charts. An observable reference keeps pointer
/// tracking isolated from the Charts, so hovering only re-renders the small overlay layers.
@Observable
private final class RiskChartHoverTracker {
    var highlightedDate: Date?
}

private struct RiskChartHoverLayer: View {
    let tracker: RiskChartHoverTracker
    let proxy: ChartProxy
    let geometry: GeometryProxy
    let points: [PerformanceRiskPoint]
    let displayRate: Double
    let showsProfitTooltip: Bool
    let displayCurrency: DisplayCurrency
    let language: AppLanguage
    let scheme: PerformanceColorScheme
    let value: (PerformanceRiskPoint) -> Double
    let lineColor: (PerformanceRiskPoint) -> Color

    private static let dateFormatter = DashboardDateFormatters.monthDay

    private var markerPoint: PerformanceRiskPoint? {
        guard let highlightedDate = tracker.highlightedDate else { return points.last }
        return points.first { $0.date == highlightedDate } ?? points.last
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    updateHighlightedDate(for: phase)
                }

            if let plotFrame = proxy.plotFrame.map({ geometry[$0] }), let point = markerPoint {
                let xPosition = plotFrame.minX + (proxy.position(forX: point.date) ?? plotFrame.width / 2)

                Rectangle()
                    .fill(lineColor(point).opacity(0.55))
                    .frame(width: 1, height: plotFrame.height)
                    .position(x: xPosition, y: plotFrame.midY)
                    .allowsHitTesting(false)

                if let yOffset = proxy.position(forY: value(point)) {
                    Circle()
                        .fill(PortfolixTheme.text)
                        .frame(width: 7, height: 7)
                        .position(x: xPosition, y: plotFrame.minY + yOffset)
                        .allowsHitTesting(false)

                    if showsProfitTooltip {
                        tooltip(for: point)
                            .fixedSize()
                            .position(
                                x: min(max(xPosition, plotFrame.minX + 72), plotFrame.maxX - 72),
                                y: max(plotFrame.minY + 42, plotFrame.minY + yOffset - 48)
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func updateHighlightedDate(for phase: HoverPhase) {
        guard let plotFrame = proxy.plotFrame else {
            if tracker.highlightedDate != nil { tracker.highlightedDate = nil }
            return
        }

        switch phase {
        case let .active(location):
            let frame = geometry[plotFrame]
            let x = location.x - frame.origin.x
            guard frame.contains(location), let date: Date = proxy.value(atX: x),
                  let first = points.first, let last = points.last,
                  date >= first.date, date <= last.date
            else {
                if tracker.highlightedDate != nil { tracker.highlightedDate = nil }
                return
            }
            let nearest = points.min {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }?.date
            if tracker.highlightedDate != nearest {
                tracker.highlightedDate = nearest
            }
        case .ended:
            if tracker.highlightedDate != nil { tracker.highlightedDate = nil }
        }
    }

    private func moneyText(_ valueCNY: Double) -> String {
        valueCNY == 0
            ? formatMoney(0, currency: displayCurrency, maximumFractionDigits: 0)
            : formatSignedMoney(Decimal(valueCNY * displayRate), currency: displayCurrency, maximumFractionDigits: 0)
    }

    private func tooltip(for point: PerformanceRiskPoint) -> some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Text(Self.dateFormatter.string(from: point.date))
                .foregroundStyle(PortfolixTheme.tertiary)
            HStack(spacing: PortfolixSpacing.xs) {
                Text(localizedText("浮盈", "P&L", language: language))
                    .foregroundStyle(PortfolixTheme.tertiary)
                Text(moneyText(point.profitCNY))
                    .foregroundStyle(PortfolixTheme.performanceStatusText(
                        for: Decimal(point.profitCNY),
                        scheme: scheme
                    ))
            }
            HStack(spacing: PortfolixSpacing.xs) {
                Text(localizedText("回撤", "Drawdown", language: language))
                    .foregroundStyle(PortfolixTheme.tertiary)
                Text(moneyText(point.drawdownCNY))
                    .foregroundStyle(PortfolixTheme.performanceStatusText(
                        for: Decimal(point.drawdownCNY),
                        scheme: scheme
                    ))
            }
        }
        .portfolixChartTooltip()
    }
}

private struct PerformanceRiskCard: View {
    @Environment(PortfolioStore.self) private var store
    @State private var hoverTracker = RiskChartHoverTracker()

    private var calendar: Calendar { .current }

    private var displayRate: Double { store.displayCurrency.rateFromCNY.doubleValue }

    // The drawdown chart always encodes a negative performance value; map it through the
    // shared performance palette so both color schemes stay consistent with the rest of the app.
    private var drawdownColor: Color {
        PortfolixTheme.performanceColor(for: Decimal(-1), scheme: store.performanceColorScheme)
    }

    var body: some View {
        @Bindable var store = store
        let data = PerformanceRiskChartData(
            snapshots: store.snapshotHistory,
            dailyProfit: store.dailyProfitHistory,
            range: store.performanceRiskRange,
            calendar: calendar,
            now: .now
        )
        let summary = data.summary

        Panel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
                    SectionHeader(
                        title: localizedText("收益波动", "Returns & Drawdown", language: store.appLanguage),
                        symbol: "chart.line.uptrend.xyaxis"
                    )

                    Spacer(minLength: PortfolixSpacing.sm)

                    PortfolixGlassSegmentedPicker(
                        title: localizedText("时间范围", "Range", language: store.appLanguage),
                        selection: $store.performanceRiskRange,
                        options: PerformanceRiskRange.allCases,
                        optionTitle: { $0.title(language: store.appLanguage) },
                        width: 208
                    )
                }
                .frame(minHeight: PortfolixLayout.cardHeaderHeight, alignment: .top)

                HStack(alignment: .firstTextBaseline, spacing: PortfolixSpacing.sm) {
                    Text(headlineTitle(summary))
                        .font(PortfolixTypography.caption)
                        .foregroundStyle(PortfolixTheme.secondary)

                    Text(headlineValueText(summary))
                        .font(PortfolixTypography.secondaryValue)
                        .foregroundStyle(headlineColor(headlineValueCNY(summary)))
                        .monospacedDigit()
                        .portfolixNumericTransition(headlineValueText(summary))
                        .lineLimit(1)

                    if let rateText = headlineRateText(summary) {
                        Text(rateText)
                            .font(PortfolixTypography.bodyEmphasis)
                            .foregroundStyle(PortfolixTheme.performanceStatusText(
                                for: Decimal(headlineValueCNY(summary)),
                                scheme: store.performanceColorScheme
                            ))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .padding(.top, PortfolixSpacing.md)
                .accessibilityElement(children: .combine)

                chartSection(data)
                    .padding(.top, PortfolixSpacing.sm)
                    .frame(maxHeight: .infinity)

                HStack(alignment: .top, spacing: PortfolixSpacing.lg) {
                    riskStatCell(
                        title: localizedText("最大回撤", "Max Drawdown", language: store.appLanguage),
                        value: summary.maxDrawdownDate == nil ? "—" : moneyText(summary.maxDrawdownCNY),
                        detail: maxDrawdownDetail(summary),
                        color: summary.maxDrawdownDate == nil
                            ? PortfolixTheme.tertiary
                            : PortfolixTheme.performanceStatusText(for: Decimal(summary.maxDrawdownCNY), scheme: store.performanceColorScheme)
                    )
                    riskStatCell(
                        title: localizedText("年化波动率", "Annualized Volatility", language: store.appLanguage),
                        value: summary.annualizedVolatility.map { String(format: "%.1f%%", $0) } ?? "—",
                        detail: nil,
                        color: PortfolixTheme.text
                    )
                    riskStatCell(
                        title: localizedText("上涨日占比", "Up Days", language: store.appLanguage),
                        value: summary.upDayRatio.map { String(format: "%.1f%%", $0) } ?? "—",
                        detail: summary.trackedDayCount > 0
                            ? String(format: "%d/%d", summary.upDayCount, summary.trackedDayCount)
                            : nil,
                        color: PortfolixTheme.text
                    )
                    riskStatCell(
                        title: localizedText("最差单日", "Worst Day", language: store.appLanguage),
                        value: summary.worstDayCNY.map(moneyText) ?? "—",
                        detail: summary.worstDayDate.map(dateLabel),
                        color: summary.worstDayCNY == nil
                            ? PortfolixTheme.tertiary
                            : PortfolixTheme.performanceStatusText(for: Decimal(summary.worstDayCNY ?? 0), scheme: store.performanceColorScheme)
                    )
                }
                .padding(.top, PortfolixSpacing.md)
            }
            .frame(height: PortfolixLayout.dashboardTrendContentHeight, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func chartSection(_ data: PerformanceRiskChartData) -> some View {
        let points = data.points
        if points.count < 2 {
            DashboardEmptyState(title: localizedText("暂无收益与回撤数据", "No return or drawdown data yet", language: store.appLanguage))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let samples = data.chartPoints
            let domain = xDomain(points: points)
            let accessibilityValue = accessibilitySummary(data.summary)
            VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                profitChart(points: points, samples: samples, xDomain: domain, accessibilityValue: accessibilityValue)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
                    .zIndex(1)

                drawdownChart(points: points, samples: samples, xDomain: domain, accessibilityValue: accessibilityValue)
                    .frame(height: 46)
                    .zIndex(0)
            }
        }
    }

    private func profitChart(
        points: [PerformanceRiskPoint],
        samples: [PerformanceRiskPoint],
        xDomain: ClosedRange<Date>,
        accessibilityValue: String
    ) -> some View {
        let series = ProfitAreaSeries.make(from: samples.map { ($0.date, $0.profitCNY * displayRate) })
        let styleDomain = series.map { "area-\($0.id)" } + series.map { "line-\($0.id)" }
        let styleRange: [Color] = series.map {
            ($0.isPositive ? profitPositiveAreaColor : profitNegativeAreaColor).opacity(0.70)
        } + series.map {
            $0.isPositive ? profitPositiveColor : profitNegativeColor
        }
        return Chart {
            RuleMark(y: .value("零线", 0))
                .foregroundStyle(PortfolixTheme.border)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

            ForEach(series) { segment in
                ForEach(segment.points) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        yStart: .value("基线", 0),
                        yEnd: .value("浮盈", point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("段", "area-\(segment.id)"))

                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("浮盈", point.value)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .butt, lineJoin: .round))
                    .foregroundStyle(by: .value("段", "line-\(segment.id)"))
                }
            }
        }
        .chartForegroundStyleScale(domain: styleDomain, range: styleRange)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.clipped()
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                RiskChartHoverLayer(
                    tracker: hoverTracker,
                    proxy: proxy,
                    geometry: geometry,
                    points: points,
                    displayRate: displayRate,
                    showsProfitTooltip: true,
                    displayCurrency: store.displayCurrency,
                    language: store.appLanguage,
                    scheme: store.performanceColorScheme,
                    value: { $0.profitCNY * displayRate },
                    lineColor: { profitColor(for: $0.profitCNY) }
                )
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: profitYDomain(points: points))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(PortfolixTheme.border)
                AxisValueLabel {
                    if let numeric = value.as(Double.self) {
                        Text(axisMoneyLabel(numeric))
                            .font(PortfolixTypography.chartAxis)
                            .monospacedDigit()
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .frame(width: Self.chartYAxisLabelWidth, alignment: .trailing)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedText("浮盈走势", "Unrealized P&L trend", language: store.appLanguage))
        .accessibilityValue(accessibilityValue)
    }

    private func drawdownChart(
        points: [PerformanceRiskPoint],
        samples: [PerformanceRiskPoint],
        xDomain: ClosedRange<Date>,
        accessibilityValue: String
    ) -> some View {
        let yDomain = drawdownYDomain(points: points)
        let axisDates = xAxisDates(in: xDomain)
        return Chart {
            RuleMark(y: .value("零线", 0))
                .foregroundStyle(PortfolixTheme.border)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

            ForEach(samples) { point in
                AreaMark(
                    x: .value("日期", point.date),
                    yStart: .value("基线", 0),
                    yEnd: .value("回撤", point.drawdownCNY * displayRate)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(drawdownAreaColor.opacity(0.58))

                LineMark(
                    x: .value("日期", point.date),
                    y: .value("回撤", point.drawdownCNY * displayRate)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.25, lineCap: .butt, lineJoin: .round))
                .foregroundStyle(drawdownColor.opacity(0.85))
            }

        }
        .chartPlotStyle { plot in
            plot.clipped()
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                RiskChartHoverLayer(
                    tracker: hoverTracker,
                    proxy: proxy,
                    geometry: geometry,
                    points: points,
                    displayRate: displayRate,
                    showsProfitTooltip: false,
                    displayCurrency: store.displayCurrency,
                    language: store.appLanguage,
                    scheme: store.performanceColorScheme,
                    value: { $0.drawdownCNY * displayRate },
                    lineColor: { _ in drawdownColor }
                )
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(PortfolixTheme.border)
                AxisValueLabel(anchor: value.as(Date.self) == axisDates.last ? .topTrailing : .top) {
                    if let date = value.as(Date.self) {
                        Text(axisDateLabel(date, domain: xDomain))
                            .font(PortfolixTypography.chartAxis)
                            .monospacedDigit()
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [yDomain.lowerBound, 0]) { value in
                AxisValueLabel {
                    if let numeric = value.as(Double.self) {
                        Text(axisMoneyLabel(numeric))
                            .font(PortfolixTypography.chartAxis)
                            .monospacedDigit()
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .frame(width: Self.chartYAxisLabelWidth, alignment: .trailing)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedText("回撤走势", "Drawdown trend", language: store.appLanguage))
        .accessibilityValue(accessibilityValue)
    }

    static let chartYAxisLabelWidth: CGFloat = 52

    private var profitPositiveColor: Color {
        PortfolixTheme.performanceColor(for: Decimal(1), scheme: store.performanceColorScheme)
    }

    private var profitNegativeColor: Color {
        PortfolixTheme.performanceColor(for: Decimal(-1), scheme: store.performanceColorScheme)
    }

    private func profitColor(for valueCNY: Double) -> Color {
        valueCNY >= 0 ? profitPositiveColor : profitNegativeColor
    }

    /// Fill each side of the zero axis with the corresponding color in the active scheme.
    private var profitPositiveAreaColor: Color {
        switch store.performanceColorScheme {
        case .redUpGreenDown: return PortfolixTheme.lossAreaWash
        case .greenUpRedDown: return PortfolixTheme.gainAreaWash
        }
    }

    private var profitNegativeAreaColor: Color {
        switch store.performanceColorScheme {
        case .redUpGreenDown: return PortfolixTheme.gainAreaWash
        case .greenUpRedDown: return PortfolixTheme.lossAreaWash
        }
    }

    private var drawdownAreaColor: Color {
        switch store.performanceColorScheme {
        case .redUpGreenDown: return PortfolixTheme.gainAreaWash
        case .greenUpRedDown: return PortfolixTheme.lossAreaWash
        }
    }

    private func profitYDomain(points: [PerformanceRiskPoint]) -> ClosedRange<Double> {
        let values = points.map { $0.profitCNY * displayRate }
        let minimum = min(values.min() ?? 0, 0)
        let maximum = max(values.max() ?? 0, 0)
        let span = max(maximum - minimum, 1)
        let padding = max(span * 0.12, 120)
        return (minimum - padding) ... (maximum + padding)
    }

    private func drawdownYDomain(points: [PerformanceRiskPoint]) -> ClosedRange<Double> {
        let values = points.map { $0.drawdownCNY * displayRate }
        let minimum = min(values.min() ?? 0, 0)
        let padding = max(abs(minimum) * 0.14, 120)
        return (minimum - padding) ... (padding * 0.55)
    }

    private func xDomain(points: [PerformanceRiskPoint]) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: .now)
        guard let first = points.first, let last = points.last else {
            return today.addingTimeInterval(-86_400) ... today
        }
        let end = max(last.date, today)
        let start = min(first.date, end)
        return start ... max(start.addingTimeInterval(86_400), end)
    }

    private func xAxisDates(in domain: ClosedRange<Date>) -> [Date] {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let count: Int
        if store.performanceRiskRange == .all {
            count = span > 240 * 86_400 ? 6 : 4
        } else {
            count = store.performanceRiskRange == .year ? 5 : 4
        }
        var dates: [Date] = []
        for index in 0..<count {
            let fraction = Double(index) / Double(max(count - 1, 1))
            let date = calendar.startOfDay(for: domain.lowerBound.addingTimeInterval(span * fraction))
            if !dates.contains(date) {
                dates.append(date)
            }
        }
        return dates
    }

    private func headlineTitle(_ summary: PerformanceRiskSummary) -> String {
        summary.currentProfitCNY >= 0
            ? localizedText("当前浮盈", "Unrealized P&L", language: store.appLanguage)
            : localizedText("当前回撤", "Current Drawdown", language: store.appLanguage)
    }

    private func headlineValueCNY(_ summary: PerformanceRiskSummary) -> Double {
        summary.currentProfitCNY >= 0
            ? summary.currentProfitCNY
            : summary.currentDrawdownCNY
    }

    private func headlineValueText(_ summary: PerformanceRiskSummary) -> String {
        moneyText(headlineValueCNY(summary))
    }

    private func headlineRateText(_ summary: PerformanceRiskSummary) -> String? {
        let rate = summary.currentProfitCNY >= 0
            ? summary.currentProfitRate
            : summary.currentDrawdownRate
        return percentageText(rate)
    }

    private func moneyText(_ valueCNY: Double) -> String {
        valueCNY == 0
            ? formatMoney(0, currency: store.displayCurrency, maximumFractionDigits: 0)
            : formatSignedMoney(Decimal(valueCNY * displayRate), currency: store.displayCurrency, maximumFractionDigits: 0)
    }

    private func headlineColor(_ valueCNY: Double) -> Color {
        PortfolixTheme.performanceStatusText(for: Decimal(valueCNY), scheme: store.performanceColorScheme)
    }

    private func percentageText(_ value: Double) -> String? {
        value.isFinite ? String(format: "%+.2f%%", value) : nil
    }

    private func maxDrawdownDetail(_ summary: PerformanceRiskSummary) -> String? {
        var parts: [String] = []
        if let date = summary.maxDrawdownDate {
            parts.append(dateLabel(date))
        }
        if let rateText = summary.maxDrawdownRate.flatMap(percentageText) {
            parts.append(rateText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func dateLabel(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }

    private func axisDateLabel(_ date: Date, domain: ClosedRange<Date>) -> String {
        let usesMonthLabels: Bool
        if store.performanceRiskRange == .year {
            usesMonthLabels = true
        } else if store.performanceRiskRange == .all {
            usesMonthLabels = domain.upperBound.timeIntervalSince(domain.lowerBound) > 200 * 86_400
        } else {
            usesMonthLabels = false
        }
        if usesMonthLabels {
            return store.appLanguage == .english
                ? Self.englishMonthFormatter.string(from: date)
                : date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN")).month())
        }
        return Self.shortDateFormatter.string(from: date)
    }

    private func axisMoneyLabel(_ value: Double) -> String {
        let symbol = store.displayCurrency.symbol
        let sign = value < 0 ? "-" : (value > 0 ? "+" : "")
        let magnitude = abs(value)
        if magnitude < 1_000 {
            return String(format: "%@%@%.0f", sign, symbol, magnitude)
        }
        if magnitude >= 1_000_000 {
            return String(format: "%@%@%.1fM", sign, symbol, magnitude / 1_000_000)
        }
        let thousands = magnitude / 1_000
        let format = thousands < 10 && thousands.rounded() != thousands ? "%@%@%.1fK" : "%@%@%.0fK"
        return String(format: format, sign, symbol, thousands)
    }

    private func accessibilitySummary(_ summary: PerformanceRiskSummary) -> String {
        var parts = [String(format: "%@ %@", localizedText("当前回撤", "Current drawdown", language: store.appLanguage), moneyText(summary.currentDrawdownCNY))]
        if summary.maxDrawdownDate != nil {
            parts.append(String(format: "%@ %@", localizedText("最大回撤", "Max drawdown", language: store.appLanguage), moneyText(summary.maxDrawdownCNY)))
        }
        if let volatility = summary.annualizedVolatility {
            parts.append(String(format: "%@ %.1f%%", localizedText("年化波动率", "Annualized volatility", language: store.appLanguage), volatility))
        }
        return parts.joined(separator: "，")
    }

    private func riskStatCell(title: String, value: String, detail: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
            Text(title)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondary)
                .lineLimit(1)

            Text(value)
                .font(PortfolixTypography.headlineValue)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .portfolixNumericTransition(value)

            if let detail {
                Text(detail)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let shortDateFormatter = DashboardDateFormatters.monthDay

    private static let englishMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM"
        return formatter
    }()
}

private enum DashboardDateFormatters {
    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d"
        return formatter
    }()
}

private struct AssetMixBarCard: View {
    @Environment(PortfolioStore.self) private var store
    @State private var highlightedItemID: PositionShareItem.ID?

    var body: some View {
        let items = store.positionShareItems
        let displayedAmountCNY = items.first { $0.id == highlightedItemID }?.amountCNY ?? store.totalValueCNY
        let formattedAmount = formatMoney(store.converted(displayedAmountCNY), currency: store.displayCurrency)

        Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.md) {
                HStack(alignment: .center, spacing: PortfolixSpacing.md) {
                    SectionHeader(title: localizedText("持仓占比", "Allocation", language: store.appLanguage), symbol: "rectangle.split.3x1.fill")

                    Spacer(minLength: PortfolixSpacing.sm)

                    Text(formattedAmount)
                        .font(PortfolixTypography.bodyEmphasis)
                        .monospacedDigit()
                        .portfolixNumericTransition(formattedAmount)
                        .foregroundStyle(PortfolixTheme.text)
                        .lineLimit(1)
                }
                .frame(minHeight: PortfolixLayout.cardHeaderHeight, alignment: .top)

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
        .onChange(of: items.map(\.id)) { _, ids in
            if let highlightedItemID, !ids.contains(highlightedItemID) { self.highlightedItemID = nil }
        }
    }
}

private struct AssetMixSegmentBar: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [PositionShareItem]
    @Binding var highlightedItemID: PositionShareItem.ID?

    /// Keep 2 pt between segments and use the same pale colors in the bar and legend.
    var body: some View {
        GeometryReader { proxy in
            let rectangles = PortfolioChartLayout.barSegments(weights: items.map(\.value), size: proxy.size)

            ZStack(alignment: .leading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index < rectangles.count {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(item.color)
                            .opacity(highlightedItemID == nil || highlightedItemID == item.id ? 1 : 0.32)
                            .frame(width: max(rectangles[index].width - 2, 0.5), height: rectangles[index].height)
                            .offset(x: rectangles[index].minX)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                updateHighlightedItem(for: phase, rectangles: rectangles)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: highlightedItemID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedText("持仓占比", "Asset mix", language: store.appLanguage))
    }

    private func updateHighlightedItem(for phase: HoverPhase, rectangles: [CGRect]) {
        let nextID: PositionShareItem.ID?
        switch phase {
        case let .active(location):
            nextID = rectangles.enumerated().first { $0.element.contains(location) }
                .flatMap { items.indices.contains($0.offset) ? items[$0.offset].id : nil }
        case .ended:
            nextID = nil
        }
        if highlightedItemID != nextID {
            highlightedItemID = nextID
        }
    }
}

private struct AssetMixLegendItem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: PositionShareItem
    let highlightedItemID: PositionShareItem.ID?

    var body: some View {
        HStack(spacing: PortfolixSpacing.xs) {
            Circle()
                .fill(item.color)
                .frame(width: 8, height: 8)
            Text(item.name)
                .foregroundStyle(PortfolixTheme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(String(format: "%.1f%%", item.value))
                .foregroundStyle(PortfolixTheme.text)
                .monospacedDigit()
                .portfolixNumericTransition(item.value)
                .lineLimit(1)
        }
        .font(PortfolixTypography.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(highlightedItemID == nil || highlightedItemID == item.id ? 1 : 0.42)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: highlightedItemID)
    }
}

private struct PositionShareItem: Identifiable {
    let id: String
    let name: String
    let amountCNY: Decimal
    let value: Double
    let color: Color
}

private struct RecentPositionsCard: View {
    @Environment(PortfolioStore.self) private var store
    @AppStorage("dashboard_primary_positions_limit")
    private var displayLimitRawValue = PrimaryPositionDisplayLimit.top10.rawValue
    private var sortField: PrimaryPositionSortField { store.primaryPositionSortField }
    private var sortDirection: PrimaryPositionSortDirection { store.primaryPositionSortDirection }

    private var displayLimit: PrimaryPositionDisplayLimit {
        PrimaryPositionDisplayLimit(rawValue: displayLimitRawValue) ?? .top10
    }

    private var primaryPositions: [Position] {
        let now = Date.now
        return PrimaryPositionOrdering.visiblePositions(
            from: store.positions,
            limit: displayLimit,
            sortField: sortField,
            direction: sortDirection,
            todayProfit: { store.todayProfitCNY(for: $0, asOf: now) }
        )
    }

    var body: some View {
        let positions = primaryPositions
        let assetColumnWidth = PrimaryPositionColumnWidths.assetWidth(for: positions, language: store.appLanguage)
        return Panel {
            VStack(alignment: .leading, spacing: PortfolixSpacing.sm) {
                SectionHeader(title: localizedText("主要持仓", "Top Holdings", language: store.appLanguage), symbol: "list.bullet.rectangle") {
                    PortfolixGlassGroup(spacing: PortfolixLayout.controlSpacing) {
                        HStack(spacing: PortfolixLayout.controlSpacing) {
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
                .frame(minHeight: PortfolixLayout.cardHeaderHeight, alignment: .top)

                if positions.isEmpty {
                    DashboardEmptyState(title: localizedText("暂无持仓", "No holdings yet", language: store.appLanguage))
                        .frame(maxWidth: .infinity, minHeight: 82)
                } else {
                    PositionHeaderRow(
                        assetWidth: assetColumnWidth,
                        sortField: Binding(get: { sortField }, set: { store.primaryPositionSortField = $0 }),
                        sortDirection: Binding(get: { sortDirection }, set: { store.primaryPositionSortDirection = $0 })
                    )
                    .padding(.top, PortfolixSpacing.xs)

                    VStack(alignment: .leading, spacing: PortfolixSpacing.xs) {
                        ForEach(positions) { position in
                            CompactPositionRow(assetWidth: assetColumnWidth, position: position) {
                                openPosition(position)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func openPosition(_ position: Position) {
        store.selectedPositionID = position.id
        store.selection = .positions
    }
}

enum PrimaryPositionDisplayLimit: String, CaseIterable, Identifiable {
    case top5
    case top10
    case all

    var id: String { rawValue }

    func maximumCount(totalCount: Int) -> Int? {
        guard totalCount > 0 else { return 0 }
        switch self {
        case .top5: return min(5, totalCount)
        case .top10: return min(10, totalCount)
        case .all: return nil
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .top5:
            localizedText("前 5 大持仓", "Top 5", language: language)
        case .top10:
            localizedText("前 10 大持仓", "Top 10", language: language)
        case .all:
            localizedText("全部持仓", "All Holdings", language: language)
        }
    }
}

enum PrimaryPositionSortField: String, Hashable {
    case marketValue
    case profitRate
    case todayProfit
}

enum PrimaryPositionSortDirection: String, Hashable {
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

        if sortField == .marketValue, direction == .descending {
            return limited
        }
        let keyedPositions = limited.map {
            (position: $0, value: sortValue(for: $0, field: sortField, todayProfit: todayProfit))
        }
        // Swift's stable sort preserves the existing market-value rank for equal metrics.
        return keyedPositions.sorted {
            direction == .ascending ? $0.value < $1.value : $0.value > $1.value
        }.map(\.position)
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
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: PortfolixLayout.glassControlHeight)
                .portfolixGlassControl()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct DashboardGlassCapsuleLabel: View {
    let title: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: PortfolixSpacing.sm) {
            Text(title)
                .fixedSize(horizontal: true, vertical: false)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .font(PortfolixTypography.captionEmphasis)
        .lineLimit(1)
        .foregroundStyle(PortfolixTheme.text)
        .padding(.horizontal, PortfolixSpacing.sm)
        .portfolixGlassControl()
    }
}

private enum PrimaryPositionColumnWidths {
    static let columnSpacing: CGFloat = PortfolixSpacing.md
    static let rowHeight: CGFloat = 44
    static let trendWidth: CGFloat = 96
    static let minimumAssetWidth: CGFloat = 220
    static let maximumAssetWidth: CGFloat = 420
    static let marketColumnWidth: CGFloat = 132
    static let rateColumnWidth: CGFloat = 84
    static let todayColumnWidth: CGFloat = 108

    /// Fits the asset column to the longest visible holding title. The width is
    /// purely content driven and never reads the table width, so resizing the
    /// window cannot feed back into the layout.
    static func assetWidth(for positions: [Position], language: AppLanguage) -> CGFloat {
        let nameFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let metaFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        var widest: CGFloat = 0
        for position in positions {
            let nameWidth = (position.name as NSString).size(withAttributes: [.font: nameFont]).width
            let meta = "\(position.symbol) · \(position.category.title(language: language))"
            let metaWidth = (meta as NSString).size(withAttributes: [.font: metaFont]).width
            widest = max(widest, nameWidth, metaWidth)
        }
        let padded = widest + 28 + PortfolixSpacing.sm + 10
        return min(max(padded, minimumAssetWidth), maximumAssetWidth)
    }
}

private struct PositionHeaderRow: View {
    @Environment(PortfolioStore.self) private var store
    let assetWidth: CGFloat
    @Binding var sortField: PrimaryPositionSortField
    @Binding var sortDirection: PrimaryPositionSortDirection

    var body: some View {
        HStack(spacing: PrimaryPositionColumnWidths.columnSpacing) {
            Text(localizedText("资产", "Asset", language: store.appLanguage))
                .frame(width: assetWidth, alignment: .leading)
            Text(localizedText("近 1 周走势", "1W Trend", language: store.appLanguage))
                .frame(width: PrimaryPositionColumnWidths.trendWidth, alignment: .center)
            SortablePositionHeader(
                title: localizedText("市值 / 权重", "Value / Weight", language: store.appLanguage),
                field: .marketValue,
                selectedField: $sortField,
                direction: $sortDirection
            )
            .frame(minWidth: PrimaryPositionColumnWidths.marketColumnWidth, maxWidth: .infinity, alignment: .trailing)
            SortablePositionHeader(
                title: localizedText("收益率", "Return", language: store.appLanguage),
                field: .profitRate,
                selectedField: $sortField,
                direction: $sortDirection
            )
            .frame(minWidth: PrimaryPositionColumnWidths.rateColumnWidth, maxWidth: .infinity, alignment: .trailing)
            SortablePositionHeader(
                title: localizedText("今日盈亏", "Today's P&L", language: store.appLanguage),
                field: .todayProfit,
                selectedField: $sortField,
                direction: $sortDirection
            )
            .frame(minWidth: PrimaryPositionColumnWidths.todayColumnWidth, maxWidth: .infinity, alignment: .trailing)
        }
        .font(PortfolixTypography.captionEmphasis)
        .foregroundStyle(PortfolixTheme.tertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PortfolixTheme.raised, in: RoundedRectangle(cornerRadius: PortfolixRadius.compact))
    }
}

private struct SortablePositionHeader: View {
    @Environment(PortfolioStore.self) private var store
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
            .foregroundStyle(isSelected ? PortfolixTheme.brandText : PortfolixTheme.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? accessibilitySortValue : "")
    }

    private var accessibilitySortValue: String {
        switch direction {
        case .ascending: localizedText("升序", "Ascending", language: store.appLanguage)
        case .descending: localizedText("降序", "Descending", language: store.appLanguage)
        }
    }
}

private struct CompactPositionRow: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let assetWidth: CGFloat
    let position: Position
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let convertedMarketValue = store.converted(position.marketValueCNY)
        let marketValueText = formatMoney(convertedMarketValue, currency: store.displayCurrency)
        let weightText = formattedWeightText
        let todayProfit = store.todayProfitCNY(for: position)
        let convertedTodayProfit = store.converted(todayProfit)
        let todayProfitText = formattedTodayProfitText(todayProfit: todayProfit, converted: convertedTodayProfit)

        HStack(spacing: PrimaryPositionColumnWidths.columnSpacing) {
            HStack(spacing: PortfolixSpacing.sm) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(position.category.assetClass.pale)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(String(position.name.prefix(1)))
                            .font(PortfolixTypography.captionEmphasis)
                            .foregroundStyle(PortfolixTheme.classOnPale)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(position.name)
                        .font(PortfolixTypography.bodyEmphasis)
                        .foregroundStyle(PortfolixTheme.text)
                        .lineLimit(1)
                    HStack(spacing: PortfolixSpacing.xs) {
                        Text(position.symbol)
                        Text("·")
                        Text(position.category.title(language: store.appLanguage))
                    }
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                    .lineLimit(1)
                }
            }
            .frame(width: assetWidth, alignment: .leading)

            PositionSparkline(values: position.weeklyTrend)
                .frame(width: PrimaryPositionColumnWidths.trendWidth, height: 28)

            VStack(alignment: .trailing, spacing: 2) {
                Text(marketValueText)
                    .font(PortfolixTypography.label)
                    .foregroundStyle(PortfolixTheme.text)
                    .monospacedDigit()
                    .portfolixNumericTransition(convertedMarketValue)
                    .lineLimit(1)
                Text(weightText)
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(minWidth: PrimaryPositionColumnWidths.marketColumnWidth, maxWidth: .infinity, alignment: .trailing)

            Text(position.costIsKnown ? formatPercent(position.profitRate) : "—")
                .font(PortfolixTypography.label)
                .foregroundStyle(PortfolixTheme.performanceColor(for: position.profitRate, scheme: store.performanceColorScheme))
                .monospacedDigit()
                .portfolixNumericTransition(position.profitRate)
                .lineLimit(1)
                .frame(minWidth: PrimaryPositionColumnWidths.rateColumnWidth, maxWidth: .infinity, alignment: .trailing)

            Text(todayProfitText)
                .font(PortfolixTypography.label)
                .foregroundStyle(PortfolixTheme.performanceColor(for: todayProfit, scheme: store.performanceColorScheme))
                .monospacedDigit()
                .portfolixNumericTransition(convertedTodayProfit)
                .lineLimit(1)
                .frame(minWidth: PrimaryPositionColumnWidths.todayColumnWidth, maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: PrimaryPositionColumnWidths.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? PortfolixTheme.text.opacity(0.055) : PortfolixTheme.raised.opacity(0.42))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }
        .onTapGesture(perform: action)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(
            marketValueText: marketValueText,
            weightText: weightText,
            todayProfitText: todayProfitText
        ))
        .accessibilityAddTraits(.isButton)
    }

    private var formattedWeightText: String {
        guard store.totalValueCNY > 0 else { return "—" }
        let share = (position.marketValueCNY / store.totalValueCNY * 100).doubleValue
        return String(format: "%.1f%%", share)
    }

    private func formattedTodayProfitText(todayProfit: Decimal, converted: Decimal) -> String {
        guard store.todayProfitIsAvailable(for: position) else { return "—" }
        if todayProfit == 0 {
            return formatMoney(converted, currency: store.displayCurrency)
        }
        return formatSignedMoney(converted, currency: store.displayCurrency)
    }

    private var helpText: String {
        "\(position.priceDateText(language: store.appLanguage)) · \(position.relativeUpdateText(now: Date(), language: store.appLanguage))"
    }

    private func accessibilityText(marketValueText: String, weightText: String, todayProfitText: String) -> String {
        let name = position.name
        let category = position.category.title(language: store.appLanguage)
        let rate = position.costIsKnown ? formatPercent(position.profitRate) : "—"
        return localizedText(
            "\(name) \(category)，市值 \(marketValueText)，占比 \(weightText)，收益率 \(rate)，今日收益 \(todayProfitText)",
            "\(name) \(category), market value \(marketValueText), weight \(weightText), return \(rate), today \(todayProfitText)",
            language: store.appLanguage
        )
    }
}

private struct PositionSparkline: View {
    @Environment(PortfolioStore.self) private var store
    let values: [Double]

    private var points: [(offset: Int, value: Double)] {
        values.enumerated().map { (offset: $0.offset, value: $0.element) }
    }

    private var lineColor: Color {
        if trendDelta == 0 { return PortfolixTheme.tertiary }
        return PortfolixTheme.performanceColor(for: trendDelta, scheme: store.performanceColorScheme)
    }

    private var areaGradient: LinearGradient {
        if trendDelta == 0 {
            return LinearGradient(
                colors: [PortfolixTheme.neutralWash, PortfolixTheme.neutralWash.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [lineColor.opacity(0.24), lineColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var trendDelta: Double {
        guard let first = values.first, let last = values.last else { return 0 }
        return last - first
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
                        .fill(PortfolixTheme.tertiary.opacity(0.22))
                        .frame(width: 36, height: 2)
                    Circle()
                        .fill(PortfolixTheme.tertiary.opacity(0.72))
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
                    .foregroundStyle(areaGradient)

                    LineMark(
                        x: .value("日", point.offset),
                        y: .value("价格", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, lineCap: .butt, lineJoin: .round))
                    .foregroundStyle(lineColor)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: domain)
                .chartPlotStyle { plot in
                    plot.clipped()
                }
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
        if trendDelta > 0 {
            return localizedText("上涨", "Rising", language: store.appLanguage)
        }
        if trendDelta < 0 {
            return localizedText("下跌", "Falling", language: store.appLanguage)
        }
        return localizedText("持平", "Unchanged", language: store.appLanguage)
    }
}

extension PortfolioStore {
    fileprivate var positionShareItems: [PositionShareItem] {
        let positionsByID = Dictionary(uniqueKeysWithValues: positions.map { ($0.id, $0) })
        return HoldingShareEngine.groups(positions: positions, language: appLanguage).map { group in
            let color: Color
            if group.id == "other_holdings" {
                // Match the investment map’s Other tile.
                color = PortfolixTheme.neutralWash
            } else if let uuid = UUID(uuidString: group.id.replacingOccurrences(of: "holding_", with: "")),
                      let position = positionsByID[uuid] {
                color = PortfolixTheme.classPale(position.category.assetClass)
            } else {
                color = PortfolixTheme.classOtherPale
            }
            return PositionShareItem(
                id: group.id, name: group.name, amountCNY: group.amountCNY,
                value: group.percentage, color: color
            )
        }
    }

}

/// Filters daily P&L points to a half-open month interval.
///
/// `DateInterval.contains(_:)` treats its end date as included, which pulls the
/// next month's first day (recorded at the interval's end instant) into the
/// current month. Use an explicit `[start, end)` range instead.
func dailyProfitPointsInMonth(
    _ points: [DailyProfitPoint],
    in monthInterval: DateInterval
) -> [DailyProfitPoint] {
    points.filter { $0.date >= monthInterval.start && $0.date < monthInterval.end }
}

enum DailyProfitDisplayMode: String, CaseIterable, Identifiable {
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
    @Environment(PortfolioStore.self) private var store
    var contentHeight: CGFloat = PortfolixLayout.dashboardTrendContentHeight
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    var body: some View {
        let calendar = Calendar.current
        let history = store.dailyProfitHistory
        let interval = calendar.dateInterval(of: .month, for: selectedMonth)
            ?? DateInterval(start: selectedMonth, duration: 31 * 86_400)
        let points = dailyProfitPointsInMonth(history, in: interval).sorted { $0.date < $1.date }
        let earliestDate = history.lazy.map(\.date).min()
        let earliestMonth = earliestDate.flatMap { calendar.dateInterval(of: .month, for: $0)?.start }

        DailyProfitMonthCard(
            selectedMonth: $selectedMonth,
            contentHeight: contentHeight,
            calendar: calendar,
            monthInterval: interval,
            points: points,
            pointsByDay: Dictionary(
                points.map { (calendar.startOfDay(for: $0.date), $0) },
                uniquingKeysWith: { _, latest in latest }
            ),
            earliestRecordedMonth: earliestMonth
        )
    }
}

private struct DailyProfitMonthCard: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedMonth: Date
    let contentHeight: CGFloat
    let calendar: Calendar
    let monthInterval: DateInterval
    let points: [DailyProfitPoint]
    let pointsByDay: [Date: DailyProfitPoint]
    let earliestRecordedMonth: Date?
    @State private var hoveredDate: Date?

    private var displayMode: DailyProfitDisplayMode { store.dailyProfitDisplayMode }
    private var highlightedDate: Date? { hoveredDate }

    private var highlightedPoint: DailyProfitPoint? {
        hoveredDate.flatMap { pointsByDay[calendar.startOfDay(for: $0)] }
    }

    private var monthlyProfitCNY: Decimal {
        points.reduce(0) { $0 + $1.amountCNY }
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
    }

    private var currentMonth: Date {
        calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(selectedMonth, equalTo: currentMonth, toGranularity: .month)
    }

    private var canMoveBackward: Bool {
        selectedMonth > (earliestRecordedMonth ?? currentMonth)
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
                    if displayMode == .calendar {
                        calendarView
                    } else {
                        chartView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: contentHeight, alignment: .topLeading)
        }
        .onExitCommand {
            hoveredDate = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: PortfolixSpacing.sm) {
            HStack(spacing: PortfolixSpacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PortfolixTheme.secondary)
                    .frame(width: 16, height: PortfolixLayout.cardHeaderHeight)

                Text(localizedText("盈亏日历", "P&L Calendar", language: store.appLanguage))
                    .font(PortfolixTypography.sectionTitle)
                    .foregroundStyle(PortfolixTheme.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: PortfolixLayout.cardHeaderHeight)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            HStack(spacing: PortfolixLayout.controlSpacing) {
                monthNavigation

                PortfolixGlassSegmentedPicker(
                    title: localizedText("显示方式", "Display mode", language: store.appLanguage),
                    selection: Binding(get: { displayMode }, set: { store.dailyProfitDisplayMode = $0 }),
                    options: DailyProfitDisplayMode.allCases,
                    optionTitle: { mode in
                        mode == .calendar
                            ? localizedText("日历", "Calendar", language: store.appLanguage)
                            : localizedText("柱状图", "Bar chart", language: store.appLanguage)
                    },
                    optionSymbol: { $0.symbol }
                )
                .onChange(of: displayMode) { _, _ in
                    hoveredDate = nil
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: PortfolixLayout.cardHeaderHeight, alignment: .top)
    }

    private var monthNavigation: some View {
        HStack(spacing: 0) {
            monthStepButton(
                systemName: "chevron.left",
                label: localizedText("上个月", "Previous month", language: store.appLanguage),
                enabled: canMoveBackward
            ) {
                moveMonth(by: -1)
            }

            Button {
                guard !isCurrentMonth else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    selectedMonth = currentMonth
                    hoveredDate = nil
                }
            } label: {
                Text(monthTitle)
                    .font(PortfolixTypography.captionEmphasis)
                    .foregroundStyle(PortfolixTheme.text)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, PortfolixSpacing.xs)
                    .frame(height: PortfolixLayout.glassControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
            .help(localizedText("回到本月", "Back to this month", language: store.appLanguage))
            .accessibilityLabel(localizedText("回到本月", "Back to this month", language: store.appLanguage))

            monthStepButton(
                systemName: "chevron.right",
                label: localizedText("下个月", "Next month", language: store.appLanguage),
                enabled: canMoveForward
            ) {
                moveMonth(by: 1)
            }
        }
        .padding(.horizontal, PortfolixSpacing.xs)
        .portfolixGlassControl()
    }

    private func monthStepButton(
        systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: PortfolixLayout.glassControlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? PortfolixTheme.text : PortfolixTheme.disabled)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var summary: some View {
        HStack(alignment: .lastTextBaseline, spacing: PortfolixSpacing.sm) {
            Text(monthSummaryTitle)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.secondary)
                .lineLimit(1)

            Text(points.isEmpty ? "—" : moneyText(monthlyProfitCNY))
                .font(PortfolixTypography.headlineValue)
                .monospacedDigit()
                .foregroundStyle(points.isEmpty ? PortfolixTheme.tertiary : profitColor(monthlyProfitCNY))
                .portfolixNumericTransition(points.isEmpty ? "—" : moneyText(monthlyProfitCNY))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: PortfolixSpacing.xs)

            summaryTrailing
        }
        .frame(height: 20)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: highlightedDate)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var summaryTrailing: some View {
        if let highlighted = highlightedDate {
            highlightedDayDetail(highlighted)
                .transition(.opacity)
        } else if !points.isEmpty {
            Text(countsText)
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .transition(.opacity)
        }
    }

    private var monthSummaryTitle: String {
        if isCurrentMonth {
            return localizedText("本月累计", "Month to date", language: store.appLanguage)
        }
        return localizedText("当月累计", "Month total", language: store.appLanguage)
    }

    private var countsText: String {
        let profitableDayCount = points.count { $0.amountCNY > 0 }
        let lossDayCount = points.count { $0.amountCNY < 0 }
        let zeroDayCount = points.count - profitableDayCount - lossDayCount
        var chinese = "盈利 \(profitableDayCount) · 亏损 \(lossDayCount)"
        var english = "\(profitableDayCount) up · \(lossDayCount) down"
        if zeroDayCount > 0 {
            chinese += " · 持平 \(zeroDayCount)"
            english += " · \(zeroDayCount) flat"
        }
        chinese += " · 记录 \(points.count)/\(daysInMonth) 天"
        english += " · \(points.count)/\(daysInMonth) recorded"
        return localizedText(chinese, english, language: store.appLanguage)
    }

    private func highlightedDayDetail(_ date: Date) -> some View {
        HStack(spacing: PortfolixSpacing.xs) {
            Text(dayTitle(date))
                .font(PortfolixTypography.caption)
                .foregroundStyle(PortfolixTheme.tertiary)
            if let point = pointsByDay[calendar.startOfDay(for: date)] {
                Text(moneyText(point.amountCNY))
                    .font(PortfolixTypography.captionEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(profitColor(point.amountCNY))
                    .portfolixNumericTransition(moneyText(point.amountCNY))
            } else {
                Text(localizedText("无记录", "No record", language: store.appLanguage))
                    .font(PortfolixTypography.caption)
                    .foregroundStyle(PortfolixTheme.tertiary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private var calendarView: some View {
        GeometryReader { geometry in
            let slots = calendarSlots
            let rows = max((slots.count + 6) / 7, 1)
            let cellHeight = DailyProfitCalendarLayout.cellHeight(in: geometry.size.height, rows: rows)

            if points.isEmpty {
                DashboardEmptyState(title: emptyStateTitle)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                VStack(spacing: PortfolixLayout.dataTileSpacing) {
                    LazyVGrid(columns: calendarColumns, spacing: 0) {
                        ForEach(Array(weekdayTitles.enumerated()), id: \.offset) { _, weekday in
                            Text(weekday)
                                .font(PortfolixTypography.chartAxis)
                                .foregroundStyle(PortfolixTheme.tertiary)
                                .frame(maxWidth: .infinity)
                                .frame(height: DailyProfitCalendarLayout.weekdayHeight)
                        }
                    }

                    let todayStart = calendar.startOfDay(for: .now)
                    LazyVGrid(columns: calendarColumns, spacing: PortfolixLayout.dataTileSpacing) {
                        ForEach(slots) { slot in
                            if let date = slot.date {
                                calendarCell(for: date, height: cellHeight, todayStart: todayStart)
                            } else {
                                Color.clear
                                    .frame(height: cellHeight)
                            }
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        updateHoveredDate(to: date(at: location, cellHeight: cellHeight, in: geometry.size, slots: slots))
                    case .ended:
                        hoveredDate = nil
                    }
                }
            }
        }
    }

    private var chartView: some View {
        Group {
            if points.isEmpty {
                DashboardEmptyState(title: emptyStateTitle)
            } else {
                chartContent
            }
        }
    }

    private var chartContent: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(PortfolixTheme.borderStrong)
                .lineStyle(StrokeStyle(lineWidth: 1))

            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date),
                    y: .value("Daily P&L", convertedAmount(point.amountCNY))
                )
                .foregroundStyle(profitBarColor(point.amountCNY))
                .cornerRadius(2)
            }

            if let highlightedPoint {
                RuleMark(x: .value("Selected date", highlightedPoint.date))
                    .foregroundStyle(PortfolixTheme.brandFocus)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: chartYDomain)
        .chartXScale(
            domain: chartXDomain,
            range: .plotDimension(
                startPadding: PortfolixSpacing.md,
                endPadding: PortfolixSpacing.md
            )
        )
        .chartXAxis {
            AxisMarks(values: chartAxisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(PortfolixTheme.border)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(String(calendar.component(.day, from: date)))
                            .foregroundStyle(PortfolixTheme.tertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
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
                            .foregroundStyle(PortfolixTheme.tertiary)
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
                        updateHoveredDate(for: phase, proxy: proxy, geometry: geometry)
                    }
            }
        }
        .accessibilityLabel(chartAccessibilityLabel)
    }

    @ViewBuilder
    private func calendarCell(for date: Date, height: CGFloat, todayStart: Date) -> some View {
        let point = pointsByDay[date]
        let amount = point?.amountCNY
        let dayStart = calendar.startOfDay(for: date)
        let isToday = dayStart == todayStart
        let isHovered = hoveredDate.map { calendar.isDate($0, inSameDayAs: date) } == true
        let isFuture = dayStart > todayStart
        let todayForeground = isToday ? todayCellForeground : nil

        VStack(spacing: 0) {
            Text(String(calendar.component(.day, from: date)))
                .font(PortfolixTypography.chartAxis)
                .foregroundStyle(todayForeground ?? dayNumberColor(isToday: false, isFuture: isFuture))

            if let amount {
                Text(compactCellAmount(amount))
                    .font(PortfolixTypography.chartAxis)
                    .monospacedDigit()
                    .foregroundStyle(
                        PortfolixTheme.performanceStatusText(for: amount, scheme: store.performanceColorScheme)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? PortfolixTheme.brandWash
                            : PortfolixTheme.brandWashStrong
                    )
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PortfolixTheme.subtleFill)

                if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayTitle(date))
        .accessibilityValue(accessibilityValue(amount: amount))
    }

    /// Foreground used inside the light brand wash "today" tile.
    private var todayCellForeground: Color {
        PortfolixTheme.brandWashText
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: PortfolixLayout.dataTileSpacing), count: 7)
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
        let rowCount = (slots.count + 6) / 7
        while slots.count < rowCount * 7 {
            slots.append(DailyProfitCalendarSlot(id: "trailing-\(slots.count)", date: nil))
        }
        return slots
    }

    private var monthTitle: String {
        let components = calendar.dateComponents([.year, .month], from: selectedMonth)
        let year = components.year ?? 0
        let month = components.month ?? 1
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

    private var chartXDomain: ClosedRange<Date> {
        let firstDay = monthInterval.start
        let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end)
            ?? firstDay
        let paddedStart = calendar.date(byAdding: .hour, value: -12, to: firstDay)
            ?? firstDay
        let paddedEnd = calendar.date(byAdding: .hour, value: 12, to: lastDay)
            ?? monthInterval.end
        return paddedStart ... paddedEnd
    }

    private var chartYDomain: ClosedRange<Double> {
        let magnitude = max(points.map { abs(convertedAmount($0.amountCNY)) }.max() ?? 0, 1) * 1.12
        return -magnitude ... magnitude
    }

    private var emptyStateTitle: String {
        if store.dailyProfitHistory.isEmpty {
            return localizedText(
                "首次同步行情后，将按日记录盈亏",
                "Daily P&L begins after your first quote sync",
                language: store.appLanguage
            )
        }
        return localizedText("该月暂无盈亏记录", "No P&L records this month", language: store.appLanguage)
    }

    private var chartAccessibilityLabel: String {
        localizedText(
            "\(monthTitle)盈亏柱状图，累计 \(moneyText(monthlyProfitCNY))",
            "\(monthTitle) daily P&L bar chart, month total \(moneyText(monthlyProfitCNY))",
            language: store.appLanguage
        )
    }

    private func moveMonth(by offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: selectedMonth) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            selectedMonth = newMonth
            hoveredDate = nil
        }
    }

    private func updateHoveredDate(for phase: HoverPhase, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            hoveredDate = nil
            return
        }
        switch phase {
        case let .active(location):
            let frame = geometry[plotFrame]
            let x = location.x - frame.origin.x
            guard frame.contains(location), let date: Date = proxy.value(atX: x) else {
                hoveredDate = nil
                return
            }
            updateHoveredDate(to: points.min {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }?.date)
        case .ended:
            hoveredDate = nil
        }
    }

    private func updateHoveredDate(to date: Date?) {
        if hoveredDate != date { hoveredDate = date }
    }

    private func date(
        at location: CGPoint, cellHeight: CGFloat, in size: CGSize, slots: [DailyProfitCalendarSlot]
    ) -> Date? {
        let spacing = PortfolixLayout.dataTileSpacing
        let cellWidth = (size.width - spacing * 6) / 7
        guard cellWidth > 0, cellHeight > 0 else { return nil }
        let y = location.y - DailyProfitCalendarLayout.weekdayHeight - spacing
        guard y >= 0 else { return nil }
        let column = Int(location.x / (cellWidth + spacing))
        let row = Int(y / (cellHeight + spacing))
        guard (0..<7).contains(column), row >= 0 else { return nil }
        let index = row * 7 + column
        guard slots.indices.contains(index) else { return nil }
        return slots[index].date
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
        let sign = value < 0 ? "-" : (includesPlus && value > 0 ? "+" : "")
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
        PortfolixTheme.performanceColor(for: amount, scheme: store.performanceColorScheme)
    }

    /// Reuse the pale gain and loss fills from Returns & Drawdown.
    private func profitBarColor(_ amount: Decimal) -> Color {
        if amount == 0 { return PortfolixTheme.neutralWash }
        let isPositive = amount > 0
        switch (isPositive, store.performanceColorScheme) {
        case (true, .redUpGreenDown), (false, .greenUpRedDown):
            return PortfolixTheme.lossAreaWash
        default:
            return PortfolixTheme.gainAreaWash
        }
    }

    private func dayNumberColor(isToday: Bool, isFuture: Bool) -> Color {
        if isToday { return PortfolixTheme.brandWashText }
        return isFuture ? PortfolixTheme.tertiary : PortfolixTheme.text
    }

    private func accessibilityValue(amount: Decimal?) -> String {
        guard let amount else {
            return localizedText("无盈亏记录", "no P&L record", language: store.appLanguage)
        }
        return moneyText(amount)
    }

    private func dayTitle(_ date: Date) -> String {
        if store.appLanguage == .chinese {
            return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
        }
        return Self.englishDayFormatter.string(from: date)
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

enum DailyProfitCalendarLayout {
    static let weekdayHeight: CGFloat = 14

    static func cellHeight(in availableHeight: CGFloat, rows: Int) -> CGFloat {
        guard availableHeight.isFinite, rows > 0 else { return 0 }
        let spacing = PortfolixLayout.dataTileSpacing
        let reservedHeight = weekdayHeight + spacing * CGFloat(rows)
        return max(availableHeight - reservedHeight, 0) / CGFloat(rows)
    }
}

private struct DailyProfitCalendarSlot: Identifiable {
    let id: String
    let date: Date?
}

private struct DashboardEmptyState: View {
    let title: String

    var body: some View {
        Text(title)
            .font(PortfolixTypography.captionEmphasis)
            .foregroundStyle(PortfolixTheme.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
