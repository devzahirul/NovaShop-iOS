import BackgroundTasks
import NovaCore

/// Background App Refresh for pending local-first changes (e.g. the user edited the bag in a
/// dead zone and closed the app). iOS decides the exact time; we only state the earliest.
/// The handler is registered on the scene in `NovaShopApp` via `.backgroundTask(.appRefresh(…))`.
public enum BackgroundSync {
    public static let taskIdentifier = "com.novashop.app.sync"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulators and devices with Background App Refresh off reject requests — sync still
            // happens on the next launch / foreground / network change.
            Log.app.info("Background sync not scheduled: \(String(describing: error), privacy: .public)")
        }
    }
}
