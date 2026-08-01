import Foundation
import SwiftUI
import CalCore

/// App-side orchestration of calendar listing, selection persistence, and syncing the cache
/// the widget reads. Uses `CalendarSyncService` (CalCore) for the actual fetch/merge.
@MainActor
final class AppSyncManager: ObservableObject {
    @Published var sources: [CalendarSource] = []
    @Published var status: String = ""
    @Published var isSyncing = false

    /// Late-bound because SwiftUI `@StateObject` can't read `@EnvironmentObject` at init.
    private weak var auth: GoogleAuthService?
    private let api = GoogleCalendarAPIClient()

    private var calendar: Calendar { .calWidget }

    func rebind(auth: GoogleAuthService) { self.auth = auth }

    /// Fetch the account's full calendar list. Every calendar is synced into the cache (a
    /// superset); which of them a given widget shows is chosen per-instance in the widget's
    /// edit sheet, so there's no app-level selection to reconcile here.
    func loadCalendars() async {
        guard let auth else { return }
        do {
            let token = try await auth.accessToken()
            let entries = try await api.calendarList(accessToken: token)
            let email = auth.email ?? ""
            sources = entries.map { entry in
                CalendarSource(
                    id: entry.id,
                    accountEmail: email,
                    summary: entry.summary ?? entry.id,
                    colorHex: entry.backgroundColor ?? "#4285F4"
                )
            }
            // First run has no cache, and the widget's calendar picker (and every widget) reads
            // from it — so seed it now rather than making the user tap "Sync now" first. The
            // extension-side foreground/background refresh can't do this: it derives the calendars
            // to fetch from the existing cache, which doesn't exist yet.
            if EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read() == nil {
                await syncNow()
            }
        } catch {
            status = "Failed to load calendars: \(error.localizedDescription)"
        }
    }

    /// Claims both in-flight flags together, or returns false when another process is already
    /// syncing. Paired with `endSyncing` — the only two places either flag is written, so they
    /// can't drift apart.
    ///
    /// They are genuinely two flags, not one duplicated. `isSyncing` is `@Published` because
    /// SwiftUI needs a publisher to re-render the disabled button and spinner, and it tracks
    /// this process exactly (`defer` guarantees the clear). The App Group flag is cross-process
    /// mutual exclusion, and it self-expires after `syncFlagTimeout`, since a remote process can
    /// die without ever clearing it. That expiry is deliberately *not* applied to the local flag:
    /// a sync legitimately running past the timeout would otherwise drop the app's spinner while
    /// the work was still going.
    ///
    /// The claim has to be *checked*, not just set: this path writes the whole cache from its own
    /// fetch rather than going through `refreshCanonical`, so starting behind a widget's sync
    /// would clobber it. A missing App Group suite degrades to the local flag alone.
    private func beginSyncing(store: AppGroupStore?) -> Bool {
        guard store?.claimSync() ?? true else { return false }
        isSyncing = true
        return true
    }

    private func endSyncing(store: AppGroupStore?) {
        isSyncing = false
        store?.endSync()
    }

    /// Fetch across every calendar and write the cache. Covers the canonical today/+2wk
    /// window, the widget's currently-paged window, and any wider range pagination had already
    /// fetched — so an app-initiated sync never strands a paged widget on the stale banner.
    func syncNow() async {
        guard let auth else { return }
        guard EventCache(appGroupIdentifier: AppConfig.appGroupID) != nil else {
            status = "App Group container unavailable — needs a signing team to run."
            return
        }
        let store = AppGroupStore(suiteName: AppConfig.appGroupID)
        guard beginSyncing(store: store) else {
            status = "A sync is already in progress."
            return
        }
        defer { endSyncing(store: store) }
        do {
            let token = try await auth.accessToken()
            let service = CalendarSyncService(api: api, calendar: calendar)
            let now = Date()
            let (start, end) = syncRange(now: now)

            // nil ⇒ every calendar failed. Skip the write so the last good cache survives;
            // overwriting it with an empty result would blank the widgets while still looking
            // freshly synced.
            guard let cache = await service.buildCache(
                sources: sources,
                rangeStart: start,
                rangeEnd: end,
                now: now,
                tokenProvider: { _ in token } // single account for now
            ) else {
                status = "Sync failed — couldn't reach any calendar. Showing last synced data."
                return
            }
            try EventCache(appGroupIdentifier: AppConfig.appGroupID)?.write(cache)
            store?.lastSyncedAt = now
            status = "Synced \(cache.events.count) events across \(sources.count) calendars."
            WidgetReloader.reloadAll()
        } catch {
            status = "Sync failed: \(error.localizedDescription)"
        }
    }

    /// Range to fetch: canonical, widened to cover the widget's currently-paged window and
    /// whatever breadth pagination had already cached (so a selection change refetches all of it).
    private func syncRange(now: Date) -> (start: Date, end: Date) {
        let offset = AppGroupStore(suiteName: AppConfig.appGroupID)?.twoWeekPageOffset ?? 0
        var (start, end) = SyncCoordinator.canonicalRange(
            coveringOffset: offset, weekCount: 2, calendar: calendar, now: now
        )
        if let existing = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read() {
            start = min(start, existing.windowStart)
            end = max(end, existing.windowEnd)
        }
        return (start, end)
    }
}
