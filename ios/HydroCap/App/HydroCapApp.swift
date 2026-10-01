import SwiftUI

@main
struct HydroCapApp: App {
    @State private var container: AppContainer
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = AppContainer()
        _container = State(initialValue: container)
        _model = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(HydroCapTheme.accent)
                .preferredColorScheme(colorScheme)
                .onOpenURL { url in
                    handle(url)
                }
                .task {
                    container.start()
                    await model.refreshAfterBecomingActive()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.refreshAfterBecomingActive() }
                }
        }
    }

    /// Settings → Appearance: nil follows iOS ("system").
    private var colorScheme: ColorScheme? {
        switch model.settings.appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    /// URL-scheme debug hooks (DEBUG builds only) — the cable-free equivalent
    /// of the Android ADB intents.
    private func handle(_ url: URL) {
        #if DEBUG
        guard let route = DebugRouteParser.parse(url) else { return }
        container.debugActions.handle(route)
        #else
        _ = url
        #endif
    }
}
