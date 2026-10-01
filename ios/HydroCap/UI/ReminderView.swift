import SwiftUI

/// Reminder ring & quiet hours. Opening the screen reads both settings from
/// the cap (the cap is the source of truth); Apply writes both, then re-reads.
/// Every rule (seconds of day, midnight = 86400, Auto semantics, snooze
/// untouched) lives in `ReminderRules` — this view only calls it.
struct ReminderView: View {
    @Bindable var model: AppModel

    // Draft (what the pickers show)
    @State private var mode: Int32 = ReminderSettings.modeAdaptive
    @State private var intervalMinutes = 30
    @State private var startTime = Date()
    @State private var stopTime = Date()
    @State private var color = RingColor.firmwareDefault
    @State private var dndMode: Int32 = DndSettings.modeAuto
    @State private var quietStart = Date()
    @State private var quietStop = Date()
    @State private var customColor = Color.blue

    // What the cap holds (seeded on load / after apply) for the "changed" check
    @State private var baseline: CapReminderConfig?
    @State private var loading = false
    @State private var loadRequested = false
    @State private var applying = false
    @State private var errorText: String?
    @State private var appliedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.self) private var environment

    private var isOn: Bool { mode != ReminderSettings.modeOff }
    private var busy: Bool { loading || applying }
    private var hasConfig: Bool { baseline != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HydroCapTheme.sectionSpacing) {
                if let errorText, !hasConfig {
                    errorCard(errorText)
                } else {
                    ringCard
                    if isOn {
                        intervalCard
                        activeHoursCard
                        colorCard
                    }
                    quietHoursCard
                    if let errorText, hasConfig {
                        Label(Self.friendly(errorText), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                    }
                    if let validation = validationMessage {
                        Label(validation, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                    }
                    if let appliedAt, !hasChanges {
                        Label("Cap stored the settings at \(AppModel.timeString(appliedAt))", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                    }
                    if hasConfig, !busy {
                        Button("Read from the cap again", systemImage: "arrow.clockwise") {
                            Task { await load() }
                        }
                        .font(.footnote)
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(HydroCapTheme.screenPadding)
            .padding(.bottom, 8)
            .redacted(reason: (loading || !loadRequested) && !hasConfig && errorText == nil ? .placeholder : [])
            .disabled(busy)
            .animation(reduceMotion ? nil : .snappy, value: isOn)
            .animation(reduceMotion ? nil : .snappy, value: dndMode)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ring")
        .navigationSubtitle(subtitle)
        .toolbarTitleDisplayMode(.inlineLarge)
        .safeAreaBar(edge: .bottom) {
            applyButton
        }
        .onAppear {
            // Read once per screen instance, as an unstructured task so that
            // switching tabs cannot cancel the cap job halfway. Retry is manual.
            guard baseline == nil, !loadRequested else { return }
            loadRequested = true
            Task { await load() }
        }
    }

    private var subtitle: String {
        if loading { return "Reading from the cap…" }
        if applying { return "Writing to the cap…" }
        if case .loaded(_, let atMs, _) = model.reminderStatus {
            return "Read from the cap \(AppModel.relativeString(fromMs: atMs, now: Date()))"
        }
        return "Reminder & quiet hours"
    }

    // MARK: Cards

    private var ringCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Reminder ring", systemImage: "light.max")
            Text(modeExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Mode", selection: $mode) {
                Text("Off").tag(ReminderSettings.modeOff)
                Text("Always").tag(ReminderSettings.modeFixed)
                Text("Adaptive").tag(ReminderSettings.modeAdaptive)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .card()
    }

    private var modeExplanation: String {
        switch mode {
        case ReminderSettings.modeOff: "The ring stays dark."
        case ReminderSettings.modeFixed: "The ring lights up every interval."
        default: "The ring lights up only when you have not drunk for one interval."
        }
    }

    private var intervalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Interval", systemImage: "clock")
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(ReminderRules.intervalChoicesMinutes, id: \.self) { minutes in
                            intervalChip(minutes: minutes, title: "\(minutes) min")
                        }
                        if !ReminderRules.intervalChoicesMinutes.contains(intervalMinutes) {
                            intervalChip(minutes: intervalMinutes, title: "\(intervalMinutes) min")
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
        .card()
    }

    /// Selected chip: accent-tinted glass. Unselected chips: a plain tinted
    /// capsule — glass over a flat grouped card has too little contrast.
    private func intervalChip(minutes: Int, title: String) -> some View {
        let selected = intervalMinutes == minutes
        return Button {
            intervalMinutes = minutes
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if !selected {
                        Capsule().fill(Color(.tertiarySystemFill))
                    }
                }
        }
        .buttonStyle(.plain)
        .modifier(SelectedGlassCapsule(active: selected))
        .animation(reduceMotion ? nil : .snappy, value: intervalMinutes)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var activeHoursCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardTitle(text: "Active hours", systemImage: "sun.max")
                .padding(.bottom, 8)
            DatePicker("From", selection: $startTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
            Divider()
            DatePicker("Until", selection: $stopTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
        }
        .card()
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Ring colour", systemImage: "paintpalette")
            HStack(spacing: 12) {
                swatch(color: nil, selected: color.isFirmwareDefault, label: "Firmware default") {
                    color = .firmwareDefault
                }
                ForEach(RingColor.presets) { preset in
                    swatch(color: HydroCapTheme.color(for: preset.color), selected: color == preset.color, label: preset.name) {
                        color = preset.color
                        customColor = HydroCapTheme.color(for: preset.color)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            ColorPicker("Custom colour", selection: $customColor, supportsOpacity: false)
                .onChange(of: customColor) { _, newValue in
                    // sRGB components; wide-gamut picks are clamped into the
                    // 0…1 range the cap accepts.
                    let resolved = newValue.resolve(in: environment)
                    let picked = RingColor(
                        red: min(max(resolved.red, 0), 1),
                        green: min(max(resolved.green, 0), 1),
                        blue: min(max(resolved.blue, 0), 1),
                        alpha: 1,
                    )
                    // Tolerance avoids a resolve round-trip loop on float noise.
                    if Self.differs(picked, color) { color = picked }
                }
            Text(color.isFirmwareDefault
                ? "Firmware default is the cap's own colour, not black."
                : "RGB \(color.red255), \(color.green255), \(color.blue255)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .card()
    }

    private func swatch(color: Color?, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if let color {
                    Circle().fill(color)
                } else {
                    Circle().stroke(Color.secondary, lineWidth: 1.5)
                    Image(systemName: "circle.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Circle()
                    .stroke(HydroCapTheme.accent, lineWidth: selected ? 3 : 0)
                    .padding(-4)
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var quietHoursCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Quiet hours", systemImage: "moon.fill")
            Text(quietExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Quiet hours", selection: $dndMode) {
                Text("Off").tag(DndSettings.modeOff)
                Text("Auto").tag(DndSettings.modeAuto)
                Text("Custom").tag(DndSettings.modeCustom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if dndMode == DndSettings.modeCustom {
                VStack(spacing: 4) {
                    DatePicker("Quiet from", selection: $quietStart, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                    Divider()
                    DatePicker("Quiet until", selection: $quietStop, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                }
                .padding(.top, 4)
            }
        }
        .card()
    }

    private var quietExplanation: String {
        switch dndMode {
        case DndSettings.modeOff: "The ring may light up at any time."
        case DndSettings.modeCustom: "The ring stays dark between the hours below."
        default: "The ring stays dark outside the active hours."
        }
    }

    private func errorCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Could not read the cap", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(Self.friendly(text))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Wake the cap with a tap and keep it nearby.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Retry", systemImage: "arrow.clockwise") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .card()
    }

    /// Engine errors are precise but technical; the two common ones get a
    /// plain sentence, everything else is shown as is.
    private static func friendly(_ reason: String) -> String {
        if reason.localizedCaseInsensitiveContains("already running") {
            return "The cap is busy with a sync. Try again in a moment."
        }
        if reason.localizedCaseInsensitiveContains("not found") || reason.localizedCaseInsensitiveContains("no cap matched") {
            return "The cap did not answer within the scan window."
        }
        return reason
    }

    // MARK: Apply

    private var applyButton: some View {
        Button {
            Task { await apply() }
        } label: {
            HStack(spacing: 8) {
                if applying {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark")
                }
                Text(applying ? "Writing…" : "Apply to cap")
                    .font(.headline)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(busy || !hasConfig || !hasChanges || validationMessage != nil)
        .animation(reduceMotion ? nil : .snappy, value: applying)
    }

    // MARK: Draft ↔ config

    /// Exactly the patch `apply()` writes (same rules as the previous screen:
    /// Off keeps the picker hours, interval 0).
    private var draftPatch: ReminderPatch {
        var reminder = ReminderValues(
            mode: mode,
            startSec: seconds(of: startTime),
            stopSec: seconds(of: stopTime),
            intervalSec: intervalMinutes * 60,
            color: color,
        )
        if mode == ReminderSettings.modeOff {
            reminder.intervalSec = 0
        }
        return ReminderPatch(
            reminder: reminder,
            dnd: DndValues(mode: dndMode, startSec: seconds(of: quietStart), stopSec: seconds(of: quietStop)),
        )
    }

    /// The draft merged over the cap's values, as `SyncEngine.applyReminder`
    /// would resolve it — nil before the first successful read.
    private var resolvedDraft: CapReminderConfig? {
        baseline.map { ReminderRules.resolve(current: $0, patch: draftPatch) }
    }

    private var validationMessage: String? {
        guard let resolvedDraft else { return nil }
        return ReminderRules.validate(resolvedDraft)
    }

    /// True when writing the draft would change what the cap holds. Both
    /// sides go through `ReminderRules.resolve` so the Auto quiet hours are
    /// derived identically, and an Off reminder's unused interval is ignored.
    private var hasChanges: Bool {
        guard let baseline, let resolvedDraft else { return false }
        let current = ReminderRules.resolve(current: baseline, patch: ReminderPatch(reminder: ReminderValues(), dnd: DndValues()))
        return Self.normalized(resolvedDraft) != Self.normalized(current)
    }

    private static func normalized(_ config: CapReminderConfig) -> CapReminderConfig {
        var config = config
        if config.reminder.mode == ReminderSettings.modeOff {
            config.reminder.intervalSec = 0
        }
        return config
    }

    private func apply() async {
        applying = true
        errorText = nil
        defer { applying = false }
        if let config = await model.applyReminder(draftPatch) {
            seed(from: config)
            appliedAt = Date()
        } else {
            errorText = model.reminderMessage
        }
    }

    private func load() async {
        loading = true
        errorText = nil
        appliedAt = nil
        defer { loading = false }
        await model.loadReminder()
        if let config = model.reminderConfig {
            seed(from: config)
        } else {
            errorText = model.reminderMessage
        }
    }

    private func seed(from config: CapReminderConfig) {
        mode = config.reminder.mode
        // An Off reminder reports interval 0; offer a sensible default for
        // when the user switches it on (the write still sends 0 while Off).
        intervalMinutes = config.reminder.intervalSec > 0 ? max(1, config.reminder.intervalSec / 60) : 30
        startTime = date(fromSecondsOfDay: config.reminder.startSec)
        stopTime = date(fromSecondsOfDay: config.reminder.stopSec)
        color = config.reminder.color
        dndMode = config.dnd.mode
        quietStart = date(fromSecondsOfDay: config.dnd.startSec)
        quietStop = date(fromSecondsOfDay: config.dnd.stopSec)
        if !config.reminder.color.isFirmwareDefault {
            customColor = HydroCapTheme.color(for: config.reminder.color)
        }
        baseline = config
    }

    private func seconds(of date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ReminderRules.secOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    /// True when any channel differs by more than one 8-bit step.
    private static func differs(_ a: RingColor, _ b: RingColor) -> Bool {
        abs(a.red - b.red) > 1 / 255 || abs(a.green - b.green) > 1 / 255 || abs(a.blue - b.blue) > 1 / 255
    }

    private func date(fromSecondsOfDay secOfDay: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = ReminderRules.hourOf(secOfDay)
        components.minute = ReminderRules.minuteOf(secOfDay)
        return Calendar.current.date(from: components) ?? Date()
    }
}


/// Applies accent-tinted glass only while `active`; otherwise leaves the
/// view untouched (there is no "no glass" `Glass` value to pass).
private struct SelectedGlassCapsule: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.glassEffect(.regular.tint(HydroCapTheme.accent).interactive(), in: .capsule)
        } else {
            content
        }
    }
}
