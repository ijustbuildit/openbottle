import SwiftUI

/// Root: onboarding → scan → the three-tab main screen. Onboarding (see
/// `OnboardingView.swift`) and Scan stay outside the tab bar (full-screen
/// flow before a cap is paired).
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.screen {
            case .onboarding:
                OnboardingView(model: model)
            case .scan:
                ScanView(model: model)
            case .home, .reminder, .settings, .debug, .bottleProfile:
                MainTabView(model: model)
            }
        }
        .overlay(alignment: .top) {
            if let notice = model.connectionNotice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .accessibilityLabel(notice)
            }
        }
        .task(id: model.connectionNotice) {
            guard model.connectionNotice != nil else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            model.dismissConnectionNotice()
        }
    }
}

/// Bottom tab bar (iOS 26 glass, minimises on scroll): Home / History /
/// Settings. Each tab owns its own `NavigationStack`; the Settings stack is
/// bound to `model.path` so `navigate(.reminder)` / `navigate(.debug)` can
/// push the Ring and Debug screens.
struct MainTabView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            Tab("Home", systemImage: "house.fill", value: AppModel.MainTab.home) {
                NavigationStack {
                    HomeView(model: model)
                }
            }
            Tab("History", systemImage: "chart.bar.fill", value: AppModel.MainTab.history) {
                NavigationStack {
                    HistoryView(model: model)
                }
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppModel.MainTab.settings) {
                NavigationStack(path: $model.path) {
                    SettingsView(model: model)
                        .navigationDestination(for: AppModel.Screen.self) { target in
                            switch target {
                            case .reminder: ReminderView(model: model)
                            case .debug: DebugView(model: model)
                            case .bottleProfile: BottleProfileView(model: model)
                            default: SettingsView(model: model)
                            }
                        }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

// MARK: - Scan

/// Found caps as cards with RSSI bars; tapping verifies the connection and
/// opens Home without waiting for the complete history import.
struct ScanView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pairing: Bool { model.pairingCap != nil }

    /// Live results while scanning; the cap being paired stays listed so its
    /// card can show the first-sync progress.
    private var caps: [DiscoveredCap] {
        var list = model.visibleCaps
        if let pairingCap = model.pairingCap, !list.contains(where: { $0.id == pairingCap.id }) {
            list.insert(pairingCap, at: 0)
        }
        return list
    }

    var body: some View {
        NavigationStack {
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
                            isPaired: cap.isSameCap(pairedName: model.settings.pairedDeviceName, pairedDeviceIdHex: model.settings.pairedDeviceIdHex),
                            isPairing: model.pairingCap?.id == cap.id,
                            statusText: "Connecting…",
                        ) {
                            Task { await model.selectCap(cap) }
                        }
                        .disabled(pairing && model.pairingCap?.id != cap.id)
                    }

                    if !model.scanning, caps.isEmpty, model.scanError == nil, !pairing {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("No cap found", systemImage: "waterbottle")
                                .font(.headline)
                            Text("Open the flap of your bottle once to wake it, then scan again.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Scan again", systemImage: "arrow.clockwise") {
                                model.startScan()
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                        .card()
                    }
                }
                .padding(HydroCapTheme.screenPadding)
                .animation(reduceMotion ? nil : .snappy, value: caps.count)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Find your cap")
            .toolbar {
                if model.settings.hasPairedDevice, !pairing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") { model.navigate(.home) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.scanning ? "Stop" : "Scan", systemImage: model.scanning ? "stop.fill" : "arrow.clockwise") {
                        model.scanning ? model.stopScan() : model.startScan()
                    }
                    .disabled(pairing)
                }
            }
            .task {
                if !model.scanning, !pairing { model.startScan() }
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HydroCapTheme.accent)
                .symbolEffect(.pulse, isActive: model.scanning)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.scanning ? "Searching…" : (pairing ? "Pairing…" : "Search stopped"))
                    .font(.headline)
                Text(model.scanning ? "Looking for LARQ caps nearby" : "\(caps.count) cap\(caps.count == 1 ? "" : "s") found")
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

/// One found cap. The identity is name + decoded serial; the address is a
/// session handle (the cap rotates it). While this cap pairs, the first
/// sync's status is shown inline.
struct CapCard: View {
    let cap: DiscoveredCap
    let isPaired: Bool
    let isPairing: Bool
    let statusText: String
    let action: () -> Void

    var body: some View {
        Button {
            if !isPairing { action() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "waterbottle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(HydroCapTheme.accent)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(cap.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if isPaired {
                                Text("paired")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(HydroCapTheme.accent.opacity(0.15), in: Capsule())
                                    .foregroundStyle(HydroCapTheme.accent)
                            }
                        }
                        Text("Serial \(cap.deviceIdHex ?? "unknown")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        RssiBars(rssi: cap.rssi)
                        Text("\(cap.rssi) dBm")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if isPairing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}
