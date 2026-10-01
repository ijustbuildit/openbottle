import SwiftUI

/// Settings: native grouped `Form` — Appearance, Bottle (profile + the Ring
/// screen), Daily target, Reminders, Battery alerts, Apple Health,
/// Background sync, Device, Debug, About.
struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var alertPercent = SettingsDefaults.batteryAlert
    @State private var criticalPercent = SettingsDefaults.batteryCritical
    @State private var showForgetConfirmation = false
    @State private var seeded = false
    @State private var overrideMl = HydrationTarget.defaultMl
    @State private var manualWeightText = ""
    @State private var manualSex: HydrationTarget.Sex?

    var body: some View {
        Form {
            appearanceSection
            bottleSection
            targetSection
            remindersSection
            batterySection
            healthSection
            backgroundSection
            deviceSection
            debugSection
            aboutSection
        }
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inlineLarge)
        .scrollDismissesKeyboard(.interactively)
        .task {
            await model.refreshPermissionStatus()
            await model.refreshHealthBody()
            await model.refresh()
            seed()
        }
        .confirmationDialog("Forget this bottle?", isPresented: $showForgetConfirmation, titleVisibility: .visible) {
            Button("Forget bottle", role: .destructive) {
                Task { await model.forgetDevice() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stored measurements stay on this iPhone. The pairing and the background sync trigger are removed.")
        }
    }

    // MARK: Sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Appearance", selection: Binding(
                get: { model.settings.appearance },
                set: { model.setAppearance($0) }
            )) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var bottleSection: some View {
        Section {
            NavigationLink(value: AppModel.Screen.reminder) {
                Label("Reminder ring & quiet hours", systemImage: "light.max")
            }
            NavigationLink(value: AppModel.Screen.bottleProfile) {
                LabeledContent("Profile", value: profileTitle(model.settings.bottleProfile()))
            }
            if let message = model.profileMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Bottle")
        } footer: {
            Text("The ring settings are read from and written to the cap. The cap reports its bottle size only as information; the profile is a setting.")
        }
    }

    /// Daily target: Apple Health estimate (default on) or a manual value.
    /// An editable estimate, not a prescription.
    private var targetSection: some View {
        Section {
            Toggle("Use Apple Health estimate", isOn: Binding(
                get: { model.settings.dailyTargetUseEstimate },
                set: { useEstimate in
                    model.setDailyTarget(useEstimate: useEstimate, overrideMl: useEstimate ? model.settings.dailyTargetOverrideMl : overrideMl)
                }
            ))
            if model.settings.dailyTargetUseEstimate {
                LabeledContent("Daily target", value: HydroCapFormat.litersPrecise(model.dailyTargetMl))
                if model.needsManualWeightInput {
                    HStack {
                        Text("Weight (optional)")
                        Spacer()
                        TextField("—", text: $manualWeightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: manualWeightText) { _, _ in saveManualBody() }
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                }
                if model.needsManualSexInput {
                    Picker("Sex (optional)", selection: $manualSex) {
                        Text("Skip").tag(HydrationTarget.Sex?.none)
                        Text("Female").tag(HydrationTarget.Sex?.some(.female))
                        Text("Male").tag(HydrationTarget.Sex?.some(.male))
                        Text("Other").tag(HydrationTarget.Sex?.some(.other))
                    }
                    .onChange(of: manualSex) { _, _ in saveManualBody() }
                }
            } else {
                Stepper(
                    value: $overrideMl,
                    in: HydrationTarget.overrideMinMl...HydrationTarget.overrideMaxMl,
                    step: HydrationTarget.overrideStepMl,
                ) {
                    LabeledContent("Daily target", value: HydroCapFormat.litersPrecise(Double(overrideMl)))
                }
                .onChange(of: overrideMl) { _, newValue in
                    guard seeded, newValue != model.settings.dailyTargetOverrideMl else { return }
                    model.setDailyTarget(useEstimate: false, overrideMl: newValue)
                }
            }
        } header: {
            Text("Daily target")
        } footer: {
            Text(targetFooter)
        }
    }

    private var targetFooter: String {
        if !model.settings.dailyTargetUseEstimate {
            return "Your own value. Used on Home, in History and for drink reminders."
        }
        switch model.dailyTarget.basis {
        case .weight(let kg, let source):
            let origin = source == .health ? "your latest weight in Apple Health" : "the weight you entered"
            return "From \(origin) (\(OnboardingOptionalStep.format(kg)) kg). \(HydrationTarget.estimateExplanation) You can set your own daily target."
        case .sex(_, let source):
            return source == .health
                ? "Estimate from biological sex in Apple Health (no weight found there). Enter a weight for a better estimate."
                : "Estimate from the sex you entered. Enter a weight for a better estimate."
        case .default:
            return "Nothing available from Apple Health (no data or no read access — iOS does not tell which). The 2.00 L default applies until you enter a weight or a value of your own."
        case .manual:
            return "Your own value."
        }
    }

    /// Drink reminders as local notifications, default off.
    private var remindersSection: some View {
        Section {
            Toggle("Remind me to drink", isOn: Binding(
                get: { model.settings.drinkRemindersEnabled },
                set: { enabled in Task { await model.setDrinkReminders(enabled: enabled) } }
            ))
            .disabled(model.updatingDrinkReminders)
            if let message = model.drinkReminderMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if model.updatingDrinkReminders { ProgressView() }
            if model.settings.drinkRemindersEnabled {
                Picker("Frequency", selection: Binding(
                    get: { model.settings.drinkReminderFrequencyMinutes },
                    set: { minutes in Task { await model.setDrinkReminders(enabled: true, frequencyMinutes: minutes) } }
                )) {
                    ForEach(DrinkReminderPlanner.frequencyChoicesMinutes, id: \.self) { minutes in
                        Text(Self.frequencyLabel(minutes)).tag(minutes)
                    }
                }
                Toggle("Only when behind target", isOn: Binding(
                    get: { model.settings.drinkReminderOnlyWhenBehind },
                    set: { behind in Task { await model.setDrinkReminders(enabled: true, onlyWhenBehind: behind) } }
                ))
                LabeledContent("Window") {
                    Text(verbatim: DrinkReminderPlanner.windowLabel(model.reminderWindow).replacingOccurrences(of: "Between ", with: ""))
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(remindersFooter)
        }
    }

    private var remindersFooter: String {
        guard model.settings.drinkRemindersEnabled else {
            return "Local notifications between the reminder-ring hours of your cap. Nothing is sent anywhere."
        }
        if model.reminderWindowFromCap {
            return "\(DrinkReminderPlanner.windowLabel(model.reminderWindow)), from your bottle's ring settings. Re-planned after every sync; \"only when behind\" compares today's intake with the share of the day that has passed."
        }
        return "The bottle's ring hours are not available. Keep the cap nearby and turn reminders on to read them; no reminders are scheduled without known hours."
    }

    static func frequencyLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return "every \(minutes / 60) h" }
        return String(format: "every %.1f h", Double(minutes) / 60)
    }

    private var batterySection: some View {
        Section {
            Stepper(
                value: $alertPercent,
                in: (SettingsDefaults.minBatteryThreshold + 1)...SettingsDefaults.maxBatteryThreshold,
                step: 1,
            ) {
                Text(verbatim: "Alert at \(alertPercent) %")
            }
            .onChange(of: alertPercent) { _, newValue in
                if criticalPercent >= newValue { criticalPercent = newValue - 1 }
                save()
            }
            Stepper(
                value: $criticalPercent,
                in: SettingsDefaults.minBatteryThreshold...max(SettingsDefaults.minBatteryThreshold, alertPercent - 1),
                step: 1,
            ) {
                Text(verbatim: "Critical at \(criticalPercent) %")
            }
            .onChange(of: criticalPercent) { _, _ in save() }
        } header: {
            Text("Battery alerts")
        } footer: {
            Text("Critical stays below the alert level. Changing a value re-arms both alerts.")
        }
    }

    private var healthSection: some View {
        Section {
            Toggle("Write drinks to Apple Health", isOn: Binding(
                get: { model.settings.healthSyncEnabled },
                set: { newValue in Task { await model.setHealthSyncEnabled(newValue) } }
            ))
            .disabled(!model.container.healthWriter.isAvailable)
            LabeledContent("Status", value: healthStatus)
            if model.container.healthWriter.isAvailable, !model.healthCanStillAsk {
                HealthAccessHelpButton()
            }
            LabeledContent("Weight", value: model.healthBody.weightKg.map { String(format: "%.1f kg", $0) } ?? "not available")
            Button("Write all drinks to Health now") {
                Task { await model.writeAllToHealth() }
            }
            .disabled(!model.settings.healthSyncEnabled || !model.healthAuthorized)
            if let message = model.healthWriteMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("\(model.healthTrackedCount) record\(model.healthTrackedCount == 1 ? "" : "s") written by OpenBottle. Weight and biological sex are read for the daily target; iOS does not report whether reading was allowed, so \"not available\" can also mean the access is off in Health → Sharing → Apps.")
        }
    }

    private var healthStatus: String {
        if !model.container.healthWriter.isAvailable { return "Not available" }
        if !model.settings.healthSyncEnabled { return "Off" }
        return model.healthAuthorized ? "Allowed" : "Permission missing"
    }

    private var backgroundSection: some View {
        Section {
            Toggle("Sync in the background", isOn: Binding(
                get: { model.settings.backgroundSyncEnabled },
                set: { model.setBackgroundSyncEnabled($0) }
            ))
            LabeledContent("Last run", value: lastBackgroundRun)
        } header: {
            Text("Background sync")
        } footer: {
            Text("iOS wakes OpenBottle when the cap is in range and adds a refresh roughly every 15 minutes. iOS decides when this actually runs.")
        }
    }

    private var lastBackgroundRun: String {
        guard let lastRun = model.settings.lastBackgroundRunMs else { return "Never" }
        let time = AppModel.relativeString(fromMs: lastRun, now: Date())
        if let outcome = model.settings.lastBackgroundOutcome { return "\(time) · \(outcome)" }
        return time
    }

    private var deviceSection: some View {
        Section("Device") {
            LabeledContent("Name", value: model.settings.pairedDeviceName ?? "No cap paired")
            LabeledContent("Serial", value: model.settings.pairedDeviceIdHex ?? "—")
            Button("Pair a different bottle") {
                model.navigate(.scan)
            }
            Button("Forget bottle", role: .destructive) {
                showForgetConfirmation = true
            }
            .disabled(!model.settings.hasPairedDevice)
        }
    }

    private var debugSection: some View {
        Section("Debug") {
            NavigationLink(value: AppModel.Screen.debug) {
                Label("Debug log & actions", systemImage: "ladybug")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: AppContainer.version)
            Text("No OpenBottle account or server. Apple Health follows your system settings.")
                .font(.footnote)
        } header: {
            Text("About")
        } footer: {
            Text("OpenBottle is not affiliated with, endorsed by, or supported by BRITA SE or LARQ, Inc. \"BRITA\" and \"LARQ\" are trademarks of their respective owners and are used here only to identify the hardware the app works with.")
        }
    }

    // MARK: Helpers

    private func profileTitle(_ profile: BottleProfile) -> String {
        BottleProfileView.title(for: profile.id)
    }

    private func seed() {
        guard !seeded else { return }
        alertPercent = model.settings.batteryAlertPercent
        criticalPercent = model.settings.batteryCriticalPercent
        overrideMl = model.settings.dailyTargetOverrideMl ?? model.dailyTarget.ml
        if let weight = model.settings.manualWeightKg { manualWeightText = OnboardingOptionalStep.format(weight) }
        manualSex = model.settings.manualSex.flatMap { HydrationTarget.Sex(rawValue: $0) }
        seeded = true
    }

    private func saveManualBody() {
        guard seeded else { return }
        let weight = OnboardingOptionalStep.parseWeight(manualWeightText)
        guard weight != model.settings.manualWeightKg || manualSex?.rawValue != model.settings.manualSex else { return }
        model.setManualBody(weightKg: weight, sex: manualSex)
    }

    private func save() {
        guard seeded else { return }
        let alert = alertPercent
        let critical = min(criticalPercent, alert - 1)
        criticalPercent = max(SettingsDefaults.minBatteryThreshold, critical)
        guard alert != model.settings.batteryAlertPercent || criticalPercent != model.settings.batteryCriticalPercent else { return }
        model.setBatteryThresholds(alert: alert, critical: criticalPercent)
    }
}

/// Bottle profile list: the three built-in curves plus custom coefficients.
struct BottleProfileView: View {
    @Bindable var model: AppModel
    @State private var coefficients: [String] = Array(repeating: "", count: 5)
    @State private var applying = false
    @State private var seeded = false

    private var selectedId: String { model.settings.bottleProfileId }

    var body: some View {
        Form {
            Section {
                ForEach(BottleProfile.builtIn) { profile in
                    profileRow(id: profile.id, title: Self.title(for: profile.id), subtitle: Self.subtitle(for: profile.id)) {
                        await model.setBottleProfile(profile)
                    }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Choosing a profile rebuilds every drink from the stored readings (and rewrites Apple Health when enabled).")
            }

            Section {
                ForEach(0..<5, id: \.self) { index in
                    LabeledContent("c\(index)") {
                        TextField("0", text: $coefficients[index])
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                Button {
                    Task { await applyCustom() }
                } label: {
                    HStack {
                        Text(selectedId == BottleProfile.idCustom ? "Custom coefficients" : "Use custom coefficients")
                        Spacer()
                        if selectedId == BottleProfile.idCustom {
                            Image(systemName: "checkmark")
                                .foregroundStyle(HydroCapTheme.accent)
                        }
                    }
                }
                .disabled(applying)
            } header: {
                Text("Custom")
            } footer: {
                Text("V(d) = c0·d⁴ + c1·d³ + c2·d² + c3·d + c4, d = distance in mm.")
            }

            if let message = model.profileMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Bottle profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { seed() }
        .overlay {
            if applying {
                ProgressView("Rebuilding drinks…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func profileRow(id: String, title: String, subtitle: String, action: @escaping () async -> Void) -> some View {
        Button {
            applying = true
            Task {
                await action()
                applying = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedId == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(HydroCapTheme.accent)
                }
            }
        }
        .disabled(applying)
    }

    static func title(for id: String) -> String {
        switch id {
        case BottleProfile.id680Cal: "680 ml, no filter (calibrated)"
        case BottleProfile.id680: "680 ml (LARQ curve)"
        case BottleProfile.id1000: "1000 ml (LARQ curve)"
        case BottleProfile.idCustom: "Custom coefficients"
        default: id
        }
    }

    static func subtitle(for id: String) -> String {
        switch id {
        case BottleProfile.id680Cal: "Default · measured on the 680 ml body, ±10 ml"
        case BottleProfile.id680: "Community curve, unverified"
        case BottleProfile.id1000: "Community curve, unverified"
        default: ""
        }
    }

    private func seed() {
        guard !seeded else { return }
        seeded = true
        let values = model.settings.customCoefficients ?? BottleProfile.body680NoFilterCal.coefficients
        coefficients = values.map { String($0) }
    }

    private func applyCustom() async {
        let values = coefficients.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 5 else {
            model.setProfileMessage("A custom profile needs five numeric coefficients (c0…c4).")
            return
        }
        applying = true
        defer { applying = false }
        await model.setBottleProfile(BottleProfile(
            id: BottleProfile.idCustom,
            label: "Custom",
            nominalMl: 0,
            coefficients: values,
        ))
    }
}
