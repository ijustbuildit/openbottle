import Charts
import SwiftUI

/// History: configurable Swift Charts chart (range 7 D / 30 D / 90 D / 1 Y,
/// bars / line / area, auto / fixed y axis, scrolling x axis, tap selection),
/// a summary row, then every drink grouped by day. Bucketing and the summary
/// are `HistoryAggregation` (pure, tested); this view only draws.
struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var events: [DrinkEvent] = []
    @State private var snapshotNow = Date()
    @State private var loadID = UUID()
    @State private var loaded = false
    @State private var selectedBucketStart: Date?
    @State private var scrollPosition: Date = .now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var range: HistoryAggregation.Range { model.historyRange }
    private var chartType: String { model.settings.historyChartType }
    private var fixedYAxis: Bool { range != .day && model.settings.historyYAxis == "fixed" }
    private var targetMl: Double { model.dailyTargetMl }
    private var calendar: Calendar { Calendar.current }

    private var buckets: [HistoryAggregation.Bucket] {
        HistoryAggregation.buckets(events: events, range: range, now: snapshotNow, calendar: calendar)
    }

    private var summary: HistoryAggregation.Summary {
        HistoryAggregation.summary(events: events, range: range, now: snapshotNow, calendar: calendar, targetMl: targetMl)
    }

    private var days: [DrinkDay] {
        DrinkDay.group(HistoryAggregation.eventsInRange(events: events, range: range, now: snapshotNow, calendar: calendar))
            .filter { $0.totalMl > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HydroCapTheme.sectionSpacing) {
                controls
                summaryRow
                chartCard
                if loaded, days.isEmpty {
                    ContentUnavailableView {
                        Label("No drinks in this range", systemImage: "drop")
                    } description: {
                        Text("Drinks appear here after a sync.")
                    }
                    .card()
                }
                LazyVStack(alignment: .leading, spacing: HydroCapTheme.sectionSpacing) {
                    ForEach(days) { day in
                        dayCard(day)
                    }
                }
            }
            .padding(HydroCapTheme.screenPadding)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("History")
        .toolbarTitleDisplayMode(.inlineLarge)
        .task(id: range) { await load() }
        .refreshable { await load() }
        .onChange(of: model.settings.historyRange) { _, _ in
            selectedBucketStart = nil
        }
    }

    // MARK: Controls

    /// Range as a glass segmented picker; chart type and y axis as a compact
    /// menu (a second segmented row would crowd the card).
    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Range", selection: Binding(
                get: { range },
                set: {
                    guard $0 != range else { return }
                    // Invalidate before changing the range, including A → B → A
                    // while a non-cancellable store read is still in flight.
                    loadID = UUID()
                    model.setHistoryControls(range: $0)
                }
            )) {
                ForEach(HistoryAggregation.Range.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Menu {
                Picker("Chart", selection: Binding(
                    get: { chartType },
                    set: { model.setHistoryControls(chartType: $0) }
                )) {
                    Label("Bars", systemImage: "chart.bar.fill").tag("bars")
                    Label("Line", systemImage: "chart.xyaxis.line").tag("line")
                    Label("Area", systemImage: "chart.line.uptrend.xyaxis").tag("area")
                }
                if range == .day {
                    Text("Y axis: Auto")
                } else {
                    Picker("Y axis", selection: Binding(
                        get: { model.settings.historyYAxis },
                        set: { model.setHistoryControls(yAxis: $0) }
                    )) {
                        Text("Auto").tag("auto")
                        Text("Fixed to target").tag("fixed")
                    }
                }
            } label: {
                Image(systemName: chartTypeSymbol)
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 32)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Chart type and y axis")
        }
    }

    private var chartTypeSymbol: String {
        switch chartType {
        case "line": "chart.xyaxis.line"
        case "area": "chart.line.uptrend.xyaxis"
        default: "chart.bar.fill"
        }
    }

    // MARK: Summary

    private var summaryRow: some View {
        let summary = summary
        return HStack(spacing: HydroCapTheme.sectionSpacing) {
            summaryTile(title: range == .day ? "Today" : "Average", value: summary.averagePerDayMl.map { HydroCapFormat.ml($0) } ?? "—", unit: range == .day ? "ml" : "ml / day")
            summaryTile(
                title: "Best day",
                value: summary.bestDay.map { HydroCapFormat.ml($0.ml) } ?? "—",
                unit: summary.bestDay.map { $0.day.formatted(.dateTime.day().month(.abbreviated)) } ?? "no data",
            )
            summaryTile(title: "On target", value: "\(summary.daysOnTarget)", unit: summary.daysOnTarget == 1 ? "day" : "days")
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : .snappy, value: summary)
    }

    private func summaryTile(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Chart

    private var chartCard: some View {
        let buckets = buckets
        let upper = HistoryAggregation.yUpperBound(buckets: buckets, targetMl: targetMl, fixedToTarget: fixedYAxis, hourly: range == .day)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: chartTitle, systemImage: "chart.bar.fill")
                Spacer()
                selectionLabel(buckets)
            }
            chart(buckets, upper: upper)
                .frame(height: 220)
                .animation(reduceMotion ? nil : .snappy, value: buckets)
                .animation(reduceMotion ? nil : .snappy, value: chartType)
                .animation(reduceMotion ? nil : .snappy, value: fixedYAxis)
            Text(chartFootnote(upper: upper))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .card()
    }

    private var chartTitle: String {
        switch range {
        case .day: "Today"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .quarter: "Last 90 days"
        case .year: "Last year"
        }
    }

    private func chartFootnote(upper: Double) -> String {
        if range == .day {
            return "Today's recorded water by hour, in local time. Tap for the amount and time. Empty hours have no recorded drinks; the daily goal is not an hourly requirement."
        }
        let unit = switch range {
        case .day: "hour"
        case .week, .month: "day"
        case .quarter: "calendar week"
        case .year: "month"
        }
        let start = HistoryAggregation.rangeStart(range: range, now: snapshotNow, calendar: calendar)
        let dates = "\(start.formatted(date: .abbreviated, time: .omitted)) – \(snapshotNow.formatted(date: .abbreviated, time: .omitted))"
        let scroll = range.scrolls ? " · swipe to scroll" : ""
        let goal: String
        if HistoryAggregation.showsGoalRule(targetMl: targetMl, upperBound: upper) {
            goal = "Dashed line = daily goal (\(HydroCapFormat.ml(targetMl)) ml/day)."
        } else if targetMl.isFinite, targetMl > 0 {
            goal = "Daily goal: \(HydroCapFormat.ml(targetMl)) ml/day (above chart scale)."
        } else {
            goal = "Daily goal is unavailable."
        }
        return "\(dates). Average ml/day, grouped by \(unit). Days with 0 ml are excluded (\(summary.recordedDayCount) days used). \(goal)\(scroll) · tap for values"
    }

    /// Selection names the actual covered dates, not an unobserved full period.
    @ViewBuilder
    private func selectionLabel(_ buckets: [HistoryAggregation.Bucket]) -> some View {
        if let selected = selectedBucketStart,
           let bucket = buckets.first(where: { $0.contains(selected) }) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(bucketLabel(bucket))
                    .foregroundStyle(.secondary)
                if let average = bucket.averagePerDayMl {
                    Text(verbatim: range == .day ? "\(HydroCapFormat.ml(bucket.ml)) ml" : "\(HydroCapFormat.ml(average)) ml / day")
                        .fontWeight(.semibold)
                        .fontDesign(.rounded)
                    if range != .day {
                        Text("Based on \(bucket.recordedDayCount) day\(bucket.recordedDayCount == 1 ? "" : "s") with drinks")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No recorded drinks")
                        .foregroundStyle(.secondary)
                }
                if range != .day {
                    Text("Goal \(HydroCapFormat.ml(targetMl)) ml / day")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .transition(.opacity)
        }
    }

    private func bucketLabel(_ bucket: HistoryAggregation.Bucket) -> String {
        if range == .day {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "HH:mm z"
            return "\(formatter.string(from: bucket.start)) – \(formatter.string(from: bucket.end))"
        }
        if bucket.dayCount == 1 {
            if calendar.isDateInToday(bucket.start) { return "Today" }
            if calendar.isDateInYesterday(bucket.start) { return "Yesterday" }
            return bucket.start.formatted(.dateTime.day().month(.abbreviated).year())
        }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: bucket.end) ?? bucket.start
        return "\(bucket.start.formatted(.dateTime.day().month(.abbreviated).year())) – \(lastDay.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func chart(_ buckets: [HistoryAggregation.Bucket], upper: Double) -> some View {
        Chart {
            ForEach(HistoryAggregation.plotPoints(buckets: buckets)) { point in
                let bucket = point.bucket
                switch chartType {
                case "line":
                    LineMark(
                        x: .value("Date", bucket.midpoint),
                        y: .value(range == .day ? "Hourly intake" : "Average ml/day", point.averagePerDayMl),
                        series: .value("Recorded period", point.series),
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(HydroCapTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                case "area":
                    AreaMark(
                        x: .value("Date", bucket.midpoint),
                        y: .value(range == .day ? "Hourly intake" : "Average ml/day", point.averagePerDayMl),
                        series: .value("Recorded period", point.series),
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(HydroCapTheme.waterGradient.opacity(0.55))
                    LineMark(
                        x: .value("Date", bucket.midpoint),
                        y: .value(range == .day ? "Hourly intake" : "Average ml/day", point.averagePerDayMl),
                        series: .value("Recorded period", point.series),
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(HydroCapTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                default:
                    BarMark(
                        x: .value("Date", bucket.midpoint),
                        y: .value(range == .day ? "Hourly intake" : "Average ml/day", point.averagePerDayMl),
                    )
                    .foregroundStyle(HydroCapTheme.waterGradient)
                    .opacity(selectedBucketStart == nil || isSelected(bucket) ? 1 : 0.45)
                    .cornerRadius(range == .month ? 3 : 6)
                }
                if chartType != "bars" {
                    // An isolated used period remains visible between gaps.
                    PointMark(x: .value("Date", bucket.midpoint), y: .value(range == .day ? "Hourly intake" : "Average ml/day", point.averagePerDayMl))
                        .foregroundStyle(HydroCapTheme.accent)
                        .symbolSize(isSelected(bucket) ? 90 : 30)
                }
            }
            if HistoryAggregation.showsGoalRule(targetMl: targetMl, upperBound: upper, hourly: range == .day) {
                RuleMark(y: .value("Daily goal", targetMl))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let selected = selectedBucketStart, chartType != "bars",
               let bucket = buckets.first(where: { $0.contains(selected) }) {
                RuleMark(x: .value("Selected", bucket.midpoint))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXSelection(value: $selectedBucketStart)
        .chartXScale(domain: HistoryAggregation.rangeStart(range: range, now: snapshotNow, calendar: calendar)...HistoryAggregation.rangeEnd(range: range, now: snapshotNow, calendar: calendar))
        .chartYAxisLabel(range == .day ? "ml / hour" : "ml / day")
        .chartYScale(domain: 0...upper)
        .chartXAxis {
            switch range {
            case .day:
                AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(), centered: true)
                }
            case .week:
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            case .month:
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: false)
                }
            case .quarter:
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                }
            case .year:
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
        }
        .modifier(HistoryScrollModifier(range: range, calendar: calendar, position: $scrollPosition))
    }

    private func isSelected(_ bucket: HistoryAggregation.Bucket) -> Bool {
        guard let selected = selectedBucketStart else { return false }
        return bucket.contains(selected)
    }

    // MARK: Day list

    private func dayCard(_ day: DrinkDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.title)
                    .font(.headline)
                Spacer()
                Text("\(HydroCapFormat.ml(day.totalMl)) ml")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(HydroCapTheme.accent)
            }
            VStack(spacing: 0) {
                ForEach(Array(day.events.enumerated()), id: \.element.timestamp) { index, event in
                    DrinkRow(event: event)
                    if index < day.events.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .card()
    }

    private func load() async {
        let requestID = UUID()
        let requestedRange = range
        loadID = requestID
        let fetched = await model.allDrinkEvents()
        // Stores need not cooperate with task cancellation. Check both identity
        // and range after the await, including overlapping pull-to-refreshes.
        guard !Task.isCancelled, loadID == requestID, range == requestedRange else { return }
        let now = Date()
        events = fetched
        snapshotNow = now
        loaded = true
        let currentBuckets = HistoryAggregation.buckets(events: fetched, range: requestedRange, now: now, calendar: calendar)
        let visibleStart = max(0, currentBuckets.count - requestedRange.visibleBuckets)
        scrollPosition = currentBuckets.isEmpty ? now : currentBuckets[visibleStart].start
    }
}

/// Horizontal scrolling for 30 D / 90 D / 1 Y (`chartScrollableAxes` +
/// `chartXVisibleDomain` in seconds of the visible window); 7 D fits as is.
private struct HistoryScrollModifier: ViewModifier {
    let range: HistoryAggregation.Range
    let calendar: Calendar
    @Binding var position: Date

    func body(content: Content) -> some View {
        if range.scrolls {
            content
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: visibleSeconds)
                .chartScrollPosition(x: $position)
        } else {
            content
        }
    }

    /// Visible window in seconds: N buckets of the range's unit (calendar
    /// months vary, 30.5 days keeps 12 months in view without a gap).
    private var visibleSeconds: Double {
        switch range.unit {
        case .weekOfYear: Double(range.visibleBuckets) * 7 * 86_400
        case .month: Double(range.visibleBuckets) * 30.5 * 86_400
        default: Double(range.visibleBuckets) * 86_400
        }
    }
}
