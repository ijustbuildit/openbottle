import SwiftUI
import UIKit

/// Onboarding (UX round 2): one `NavigationStack`, three steps switched in
/// place (no back arrows), a subtle "1 of 3" in the toolbar.
///
/// 1. Welcome + Apple Health — an authorized Bluetooth scan can run here;
///    otherwise Bluetooth is requested after Health is connected or skipped.
/// 2. Optional things — missing water-write access, notifications, Bluetooth,
///    and independent manual fallbacks for unavailable weight or sex.
///    HealthKit never reports *read* grants, so "missing weight" is shown as
///    "not available", never as "denied".
/// 3. Find your bottle — connect, then Home while history imports.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                switch model.onboardingStep {
                case .welcome:
                    OnboardingWelcomeStep(model: model)
                case .optional:
                    OnboardingOptionalStep(model: model)
                case .findBottle:
                    OnboardingFindBottleStep(model: model)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    OnboardingStepIndicator(step: model.onboardingStep.rawValue)
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.onboardingStep)
        }
        .onAppear {
            model.startOnboardingScanIfAllowed()
        }
    }
}

// MARK: - Step 1

struct OnboardingWelcomeStep: View {
    @Bindable var model: AppModel
    @State private var connecting = false

    private var healthAvailable: Bool { model.container.healthWriter.isAvailable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HydroCapTheme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "waterbottle.fill")
                        .font(.system(size: 64))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(HydroCapTheme.accent)
                        .padding(.bottom, 4)
                    Text("Track your bottle")
                        .font(.largeTitle.weight(.bold))
                    Text("HydroCap reads your LARQ iQ cap and can write drinks to Apple Health. Available body values help estimate an editable daily drink goal.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 10) {
                    Label("No HydroCap account or server. Apple Health follows your system settings.", systemImage: "lock.fill")
                    Label("The cap needs no pairing code.", systemImage: "dot.radiowaves.left.and.right")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(HydroCapTheme.screenPadding)
        }
        .navigationTitle("Welcome")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
            OnboardingWelcomeActions(
                connecting: connecting,
                healthAvailable: healthAvailable,
                onConnect: { Task { await connect() } },
                onSkip: { Task { await model.advanceFromWelcome() } }
            )
        }
    }

    /// Granted or not, the flow continues: to step 3 when nothing is
    /// missing, otherwise to step 2.
    private func connect() async {
        connecting = true
        defer { connecting = false }
        await model.connectAppleHealth()
        await model.advanceFromWelcome()
    }
}

/// Non-compressible toolbar label; UIKit must not truncate "1 of 3".
struct OnboardingStepIndicator: View {
    let step: Int
    var body: some View {
        Text(verbatim: "\(step) of 3")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 80, minHeight: 32)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Step \(step) of 3")
    }
}

/// Both choices have their own generous tap area. Added bottom space and a
/// taller secondary choice raise the primary button away from the home edge.
struct OnboardingWelcomeActions: View {
    let connecting: Bool
    let healthAvailable: Bool
    let onConnect: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Button(action: onConnect) {
                HStack(spacing: 8) {
                    if connecting { ProgressView().tint(.white) }
                    else { Image(systemName: "heart.fill") }
                    Text("Connect Apple Health").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(connecting || !healthAvailable)

            Button(action: onSkip) {
                Text("Not now")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(connecting)
        }
        .padding(.horizontal, HydroCapTheme.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
}

// MARK: - Step 2

struct OnboardingOptionalStep: View {
    @Bindable var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var weightText = ""
    @State private var sex: HydrationTarget.Sex?
    @State private var connectingHealth = false
    @State private var bodySaved = false
    @State private var bodySeeded = false

    private var container: AppContainer { model.container }
    private var showHealthRow: Bool { !model.healthWriteGranted && container.healthWriter.isAvailable }
    private var showNotificationsRow: Bool { model.notificationStatus != .authorized }
    private var showBluetoothRow: Bool { model.bluetoothDenied }
    private var showBodyRow: Bool {
        (model.needsManualWeightInput || model.needsManualSexInput)
            && (model.bodyValuesMissing || bodySaved)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HydroCapTheme.sectionSpacing) {
                Text("A few optional things. You can leave these off and change them later in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                if showHealthRow {
                    OptionalRow(
                        systemImage: "heart.fill",
                        title: "Apple Health",
                        text: model.healthCanStillAsk
                            ? "Write drinks as water and use available body values for an editable target."
                            : "Writing water is not allowed. You can change HydroCap's access in Apple Health; body values are optional.",
                    ) {
                        if model.healthCanStillAsk {
                            Button("Connect") {
                                connectingHealth = true
                                Task {
                                    await model.connectAppleHealth()
                                    connectingHealth = false
                                }
                            }
                            .disabled(connectingHealth)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        } else {
                            HealthAccessHelpButton()
                        }
                    }
                }

                if showNotificationsRow {
                    OptionalRow(
                        systemImage: "bell.badge.fill",
                        title: "Notifications",
                        text: model.notificationStatus == .denied
                            ? "Turned off in iOS Settings. Needed for battery alerts and drink reminders."
                            : "Needed for battery alerts and drink reminders.",
                    ) {
                        if model.notificationStatus == .denied {
                            openSettingsButton
                        } else {
                            Button("Allow") {
                                Task { await model.requestNotifications() }
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    }
                }

                if showBluetoothRow {
                    OptionalRow(
                        systemImage: "dot.radiowaves.left.and.right",
                        title: "Bluetooth",
                        text: "Bluetooth access is off for HydroCap, so the cap cannot be found. Turn it on in iOS Settings.",
                    ) {
                        openSettingsButton
                    }
                }

                if showBodyRow {
                    bodyCard
                }

                if !showHealthRow, !showNotificationsRow, !showBluetoothRow, !showBodyRow {
                    Label("Ready to find your bottle.", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(HydroCapTheme.accent)
                        .card()
                }
            }
            .padding(HydroCapTheme.screenPadding)
        }
        .navigationTitle("Optional")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .bottom) {
            Button {
                saveBody()
                model.showFindBottle()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, HydroCapTheme.screenPadding)
        }
        .task {
            await model.refreshPermissionStatus()
            seedBody()
        }
    }

    private var openSettingsButton: some View {
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    /// Offer each unavailable Health field independently; blanks are optional.
    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(HydroCapTheme.accent)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daily target")
                        .font(.headline)
                    Text("Some body values are not available from Apple Health. Add only the missing values for an estimated drink goal, or leave them blank. The goal is editable in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if model.needsManualWeightInput {
                HStack {
                    Text("Weight (optional)")
                    Spacer()
                    TextField("—", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: weightText) { _, _ in saveBody() }
                    Text("kg")
                        .foregroundStyle(.secondary)
                }
            }
            if model.needsManualSexInput {
                Picker("Sex (optional)", selection: $sex) {
                    Text("Skip").tag(HydrationTarget.Sex?.none)
                    Text("Female").tag(HydrationTarget.Sex?.some(.female))
                    Text("Male").tag(HydrationTarget.Sex?.some(.male))
                    Text("Other").tag(HydrationTarget.Sex?.some(.other))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: sex) { _, _ in saveBody() }
            }
            Text(verbatim: model.dailyTargetCaption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
        .card()
    }

    private func seedBody() {
        guard !bodySeeded else { return }
        if let weight = model.settings.manualWeightKg { weightText = Self.format(weight) }
        sex = model.settings.manualSex.flatMap { HydrationTarget.Sex(rawValue: $0) }
        bodySeeded = true
    }

    private func saveBody() {
        guard bodySeeded else { return }
        let weight = Self.parseWeight(weightText)
        guard weight != model.settings.manualWeightKg || sex?.rawValue != model.settings.manualSex else { return }
        model.setManualBody(weightKg: weight, sex: sex)
        bodySaved = weight != nil || sex != nil
    }

    static func parseWeight(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized), value.isFinite, value >= 20, value <= 300 else { return nil }
        return value
    }

    static func format(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}

/// Health has no public URL to this app's individual permission page. Give
/// explicit instructions rather than repeating a sheet that cannot ask again.
struct HealthAccessHelpButton: View {
    @State private var showingHelp = false

    var body: some View {
        Button("Change access in Apple Health") { showingHelp = true }
            .alert("Change Health access", isPresented: $showingHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Open Apple Health, tap your profile, then Apps and Services → HydroCap. Allow writing Water to sync drinks. Reading Weight and Biological Sex is optional. Return to HydroCap to refresh the status.")
            }
    }
}

/// One optional item: symbol, title, one-liner, its own action.
struct OptionalRow<Action: View>: View {
    let systemImage: String
    let title: String
    let text: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HydroCapTheme.accent)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                action()
                    .padding(.top, 4)
            }
        }
        .card()
    }
}

// MARK: - Step 3

struct OnboardingFindBottleStep: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Long enough to cover steps 1–2; restarted here when it ran out.
    nonisolated static let onboardingScanSeconds = 45.0
    nonisolated static let wakeHintSeconds = 20.0
    @State private var showWakeHint = false

    private var pairing: Bool { model.pairingCap != nil }

    /// Caps seen so far; the cap being paired is always listed (its card
    /// shows the first-sync progress) even while the scan list settles.
    private var caps: [DiscoveredCap] {
        var list = model.visibleCaps
        if let pairingCap = model.pairingCap, !list.contains(where: { $0.id == pairingCap.id }) {
            list.insert(pairingCap, at: 0)
        }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HydroCapTheme.sectionSpacing) {
                searchHeader

                if let error = model.scanError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .card()
                }

                ForEach(caps) { cap in
                    CapCard(
                        cap: cap,
                        isPaired: false,
                        isPairing: model.pairingCap?.id == cap.id,
                        statusText: "Connecting…",
                    ) {
                        Task { await model.selectCap(cap) }
                    }
                    .disabled(pairing && model.pairingCap?.id != cap.id)
                }

                if caps.isEmpty, !pairing, showWakeHint || !model.scanning {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("No cap found yet", systemImage: "waterbottle")
                            .font(.headline)
                        Text("Open the flap of your bottle once to wake it, then keep it next to the iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Scan again", systemImage: "arrow.clockwise") {
                            showWakeHint = false
                            model.startScan(seconds: Self.onboardingScanSeconds)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .disabled(model.scanning)
                    }
                    .card()
                }
            }
            .padding(HydroCapTheme.screenPadding)
            .animation(reduceMotion ? nil : .snappy, value: caps.count)
            .animation(reduceMotion ? nil : .snappy, value: showWakeHint)
        }
        .navigationTitle("Find your bottle")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !model.scanning, caps.isEmpty, !pairing {
                model.startScan(seconds: Self.onboardingScanSeconds)
            }
        }
        .task {
            // The hint after 20 s without a result (the scan may still run).
            try? await Task.sleep(for: .seconds(Self.wakeHintSeconds))
            if caps.isEmpty { showWakeHint = true }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HydroCapTheme.accent)
                .symbolEffect(.pulse, isActive: model.scanning && !reduceMotion)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.scanning ? "Searching…" : (pairing ? "Pairing…" : "Search stopped"))
                    .font(.headline)
                Text(caps.isEmpty ? "Tap your cap when it shows up" : "Tap your cap to pair it")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.scanning {
                ProgressView()
            }
        }
        .padding(.horizontal, 4)
    }
}
