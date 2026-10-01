import SwiftUI
import UIKit

/// Debug: the session log (ring buffer + `Documents/debug-log.txt`), copy,
/// and the same actions the `hydrocap://` URL hooks run.
struct DebugView: View {
    @Bindable var model: AppModel

    @State private var busy: String?
    @State private var liveTofText: String?
    @State private var copied = false

    var body: some View {
        List {
            Section("Actions") {
                actionButton("Scan 20 s", systemImage: "dot.radiowaves.left.and.right") {
                    busy = "scanning"
                    await model.container.debugActions.scan()
                    busy = nil
                }
                actionButton("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                    busy = "syncing"
                    await model.syncNow()
                    busy = nil
                }
                actionButton("Live ToF", systemImage: "ruler") {
                    busy = "measuring"
                    if let measurement = await model.liveTof() {
                        liveTofText = "\(measurement.distanceMm) mm, \(measurement.kcps) kcps"
                    } else {
                        liveTofText = "failed (see log)"
                    }
                    busy = nil
                }
                actionButton("Read all settings", systemImage: "list.bullet.rectangle") {
                    busy = "reading"
                    await model.readAllSettings()
                    busy = nil
                }
                actionButton("Read reminder", systemImage: "light.max") {
                    busy = "reading"
                    await model.loadReminder()
                    busy = nil
                }
                if let busy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(busy)
                            .foregroundStyle(.secondary)
                    }
                }
                if let liveTofText {
                    LabeledContent("Live ToF", value: liveTofText)
                        .font(.footnote)
                }
            }

            Section("State") {
                LabeledContent("Sync", value: model.syncStatus.label)
                LabeledContent("Connection", value: model.connectionState.label)
                LabeledContent("Stored readings", value: "\(model.tofCount)")
                if let capSize = model.settings.lastCapBottleSizeMl {
                    LabeledContent("Cap reports", value: "\(capSize) ml")
                }
                LabeledContent("Profile", value: model.settings.bottleProfile().label)
                if let fill = model.fillEstimate {
                    LabeledContent("Last reading", value: "\(fill.distanceMm) mm, \(fill.kcps) kcps at \(fill.at)")
                }
            }

            Section("Last background run") {
                if let lastRun = model.settings.lastBackgroundRunMs {
                    LabeledContent(HydroCapFormat.timeMs(lastRun), value: model.settings.lastBackgroundOutcome ?? "—")
                        .font(.footnote)
                } else {
                    Text("no run yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Misses in a row", value: "\(model.settings.consecutiveCapMisses)")
                    .font(.footnote)
            }

            Section {
                Button(copied ? "Copied" : "Copy log", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = model.debugText
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                Button("Clear view", systemImage: "trash") {
                    model.clearDebugLog()
                }
            } footer: {
                if let url = model.container.debugLogFileURL {
                    Text("file: \(url.path)")
                        .font(.caption2)
                }
            }

            Section("Log (\(model.debugEntries.count) lines)") {
                ForEach(Array(recentEntries.enumerated()), id: \.offset) { _, entry in
                    Text(entry.format())
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
                if model.debugEntries.isEmpty {
                    Text("empty").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
    }

    private var recentEntries: [DebugEntry] {
        Array(model.debugEntries.suffix(300)).reversed()
    }

    private func actionButton(_ title: String, systemImage: String, _ action: @escaping () async -> Void) -> some View {
        Button(title, systemImage: systemImage) {
            Task { await action() }
        }
        .disabled(busy != nil)
    }
}
