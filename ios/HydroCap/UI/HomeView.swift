import SwiftUI

/// Home overview: header (bottle name, serial, status line), the "Today" hero
/// card with the daily-target caption, Bottle + Battery gauges side by side
/// (equal height), today's drinks. No sync button: pull-to-refresh and the
/// background sync are the triggers; the status line says what is going on.
struct HomeView: View {
    @Bindable var model: AppModel
    @State private var showAllDrinks = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSyncing: Bool { model.syncStatus.isRunning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HydroCapTheme.sectionSpacing) {
                statusHeader

                if model.hasAnyData {
                    todayCard
                    // Equal heights: the row is sized to its tallest card
                    // (`fixedSize` vertical), and each card stretches to the
                    // row height via `maxHeight: .infinity` inside `card()`.
                    HStack(alignment: .top, spacing: HydroCapTheme.sectionSpacing) {
                        bottleCard
                        batteryCard
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    drinksCard
                } else {
                    emptyState
                }
            }
            .padding(HydroCapTheme.screenPadding)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(model.displayName)
        .navigationSubtitle(model.pairedSerial.map { "Serial \($0)" } ?? "No cap paired")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(isPresented: $showAllDrinks) {
            DrinkHistoryView(model: model)
        }
        .refreshable {
            await model.refresh()
            // Unstructured so an interrupted pull-to-refresh cannot cancel a
            // BLE job halfway; the indicator still waits for it.
            let sync = Task { await model.syncNow() }
            await sync.value
        }
        .task { await model.refresh() }
    }

    // MARK: Header

    private var statusHeader: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSyncing ? HydroCapTheme.accent : .secondary)
                    .symbolEffect(.pulse, isActive: isSyncing && !reduceMotion)
                Text(model.syncStatusLine(now: context.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                Spacer()
            }
            .padding(.horizontal, 4)
            .animation(reduceMotion ? nil : .snappy, value: model.syncStatus)
        }
    }

    private var statusSymbol: String {
        switch model.syncStatus {
        case .running: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .idle, .done: "checkmark.circle.fill"
        }
    }

    // MARK: Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Today", systemImage: "drop.fill")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(HydroCapFormat.ml(model.todayMl))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: model.todayMl)
                Text("ml")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "of \(HydroCapFormat.litersPrecise(model.dailyTargetMl))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            WaterProgressBar(fraction: model.todayProgress)
            HStack {
                Text(verbatim: "\(model.todayEvents.count) drink\(model.todayEvents.count == 1 ? "" : "s")")
                    .contentTransition(.numericText())
                Spacer()
                Text(verbatim: "\(Int((model.todayProgress * 100).rounded())) %")
                    .contentTransition(.numericText())
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .animation(reduceMotion ? nil : .snappy, value: model.todayEvents.count)
            Text(verbatim: model.dailyTargetCaption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .card()
    }

    // MARK: Bottle

    private var bottleCard: some View {
        let fill = model.fillEstimate
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Bottle", systemImage: "waterbottle.fill")
            HStack(alignment: .center, spacing: 12) {
                BottleFillView(fraction: fill.map { $0.percent / 100 })
                    .frame(width: 36, height: 76)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: fill.map { HydroCapFormat.ml($0.ml) } ?? "—")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(verbatim: fill.map { "ml · \(Int($0.percent.rounded())) %" } ?? "no reading")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: fill.map { "last reading \($0.at)" } ?? "Appears after a sync")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
        .animation(reduceMotion ? nil : .snappy, value: fill?.ml)
    }

    // MARK: Battery

    private var batteryCard: some View {
        let tier = model.batteryTier
        let percent = model.latestBattery?.percent
        let color = HydroCapTheme.batteryColor(for: tier)
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Battery", systemImage: "bolt.fill")
            HStack(alignment: .center, spacing: 12) {
                RingGauge(fraction: percent.map { Double($0) / 100 }, color: color, lineWidth: 8) {
                    Text(verbatim: percent.map { "\($0)" } ?? "—")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    if percent != nil {
                        Text("%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: batteryTierLabel(tier))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tier == nil ? Color.secondary : color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: model.batteryMeasuredAt.map { "measured \($0)" } ?? "Appears after a sync")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
        .animation(reduceMotion ? nil : .snappy, value: percent)
    }

    private func batteryTierLabel(_ tier: AppModel.BatteryTier?) -> String {
        switch tier {
        case .ok: "Good"
        case .low: "Low"
        case .critical: "Charge now"
        case nil: "No data"
        }
    }

    // MARK: Drinks

    private var drinksCard: some View {
        let drinks = model.todayDrinksNewestFirst
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: "Today's drinks", systemImage: "list.bullet")
                Spacer()
                Button("Show all") { showAllDrinks = true }
                    .font(.subheadline.weight(.medium))
            }
            if drinks.isEmpty {
                Text("No drinks today yet. They appear after a sync.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(drinks.prefix(8).enumerated()), id: \.element.timestamp) { index, event in
                        DrinkRow(event: event)
                        if index < min(drinks.count, 8) - 1 {
                            Divider()
                        }
                    }
                }
                if drinks.count > 8 {
                    Text("\(drinks.count - 8) more today")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .card()
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waterbottle.fill")
                .font(.system(size: 36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HydroCapTheme.accent)
            Text(model.initialImportRunning ? "Your bottle is connected" : "Nothing synced yet")
                .font(.headline)
            if model.initialImportRunning {
                ProgressView("Importing saved drinks…")
                Text("You can use the app while your history loads. Keep the bottle nearby.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Keep the cap nearby and pull down to sync. Saved drinks will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: model.dailyTargetCaption)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .card()
    }
}

/// One drink: time on the left, volume on the right.
struct DrinkRow: View {
    let event: DrinkEvent

    var body: some View {
        HStack {
            Text(HydroCapFormat.time(event.timestamp))
                .font(.body)
            Spacer()
            Text("\(HydroCapFormat.ml(event.volumeMl)) ml")
                .font(.body.weight(.semibold))
                .fontDesign(.rounded)
        }
        .padding(.vertical, 10)
    }
}

/// Every stored drink, grouped by day (newest day first), from
/// `container.store.allDrinkEvents()`.
struct DrinkHistoryView: View {
    @Bindable var model: AppModel
    @State private var days: [DrinkDay] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded, days.isEmpty {
                ContentUnavailableView {
                    Label("No drinks yet", systemImage: "drop")
                } description: {
                    Text("Drinks appear here after a sync.")
                }
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.events, id: \.timestamp) { event in
                        DrinkRow(event: event)
                            .padding(.vertical, -6)
                    }
                } header: {
                    HStack {
                        Text(day.title)
                        Spacer()
                        Text("\(HydroCapFormat.ml(day.totalMl)) ml")
                            .fontDesign(.rounded)
                    }
                }
            }
        }
        .navigationTitle("All drinks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        days = DrinkDay.group(await model.allDrinkEvents())
        loaded = true
    }
}

/// Drinks of one calendar day, newest first; days sorted newest first.
nonisolated struct DrinkDay: Identifiable, Sendable {
    let day: Date
    let events: [DrinkEvent]

    var id: Date { day }
    var totalMl: Double { events.reduce(0) { $0 + $1.volumeMl } }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    static func group(_ events: [DrinkEvent]) -> [DrinkDay] {
        let calendar = Calendar.current
        var byDay: [Date: [DrinkEvent]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(event.timestamp)))
            byDay[day, default: []].append(event)
        }
        return byDay
            .map { DrinkDay(day: $0.key, events: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.day > $1.day }
    }
}
