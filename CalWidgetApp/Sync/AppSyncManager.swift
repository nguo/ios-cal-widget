import Foundation
import SwiftUI
import CalCore

/// The app's "Sync now" button, and the local in-flight state SwiftUI renders it from.
///
/// It has no fetch of its own any more. It used to: `refreshCanonical` derived the calendars to
/// fetch *from the cache*, so it could never seed one, and first run needed a second
/// implementation running on the GoogleSignIn token with freshly-listed sources. That copy kept
/// its own window arithmetic, which drifted — it unioned against the cached window, so each sync
/// widened the range the next one would union against. Now that what to fetch comes from the
/// catalog and the widget demand, the shared path can seed from nothing and there is one
/// implementation.
@MainActor
final class AppSyncManager: ObservableObject {
    @Published var status: String = ""
    @Published var isSyncing = false

    private var calendar: Calendar { .calWidget }

    /// Lists every account's calendars, then fetches events for whatever the placed widgets ask
    /// for. Both halves matter on first run: nothing can be picked until the catalog exists, and
    /// nothing is fetched until something is picked.
    func syncNow() async {
        guard EventCache(appGroupIdentifier: AppConfig.appGroupID) != nil else {
            status = "App Group container unavailable — needs a signing team to run."
            return
        }
        // Local flag only. Cross-process mutual exclusion lives inside `refreshCanonical`, which
        // claims the shared timestamp itself and returns `.skipped` if it loses. This one exists
        // because SwiftUI needs a publisher to disable the button and show the spinner, and it
        // deliberately does *not* expire the way the shared flag does — a sync legitimately running
        // past the timeout shouldn't drop the spinner while the work is still going.
        isSyncing = true
        defer { isSyncing = false }

        let listed = await SyncCoordinator.refreshCatalog(calendar: calendar)
        switch await WidgetDemand.refreshCanonical(calendar: calendar) {
        case .succeeded:
            WidgetReloader.reloadAll()
            status = "Synced."
        case .skipped:
            status = "A sync is already in progress."
        case .failed:
            // The common "failure" here is benign and worth naming separately: with nothing
            // selected there is nothing to fetch, and the fix is to configure a widget, not retry.
            status = listed
                ? "No calendars selected yet — pick some in a widget's Edit Widget sheet."
                : "Sync failed — couldn't reach Google. Showing last synced data."
        }
    }
}
