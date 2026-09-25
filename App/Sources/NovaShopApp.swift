import AppFeature
import NovaCore
import SwiftUI

/// The entire app target. Everything else lives in `Packages/NovaKit`, which keeps this target's
/// compile time near zero and lets features build and test without the app.
@main
struct NovaShopApp: App {
    @State private var container: AppContainer

    init() {
        LaunchTimeline.shared.markAppInit()
        // Cheap by design: allocates objects, performs no I/O. See `AppContainer.bootstrap()`.
        _container = State(initialValue: AppContainer.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        // Background App Refresh: upload local-first changes made before the app was closed.
        .backgroundTask(.appRefresh(BackgroundSync.taskIdentifier)) { [container] in
            await container.backgroundSync()
        }
    }
}
