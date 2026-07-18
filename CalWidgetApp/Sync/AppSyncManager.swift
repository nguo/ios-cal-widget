import Foundation
import SwiftUI
import WidgetKit
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

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }

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

    /// Fetch across every calendar and write the cache. Covers the canonical today/+2wk
    /// window, the widget's currently-paged window, and any wider range pagination had already
    /// fetched — so an app-initiated sync never strands a paged widget on the stale banner.
    func syncNow() async {
        guard let auth else { return }
        guard EventCache(appGroupIdentifier: AppConfig.appGroupID) != nil else {
            status = "App Group container unavailable — needs a signing team to run."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await auth.accessToken()
            let service = CalendarSyncService(api: api, calendar: calendar)
            let now = Date()
            let (start, end) = syncRange(now: now)

            let cache = await service.buildCache(
                sources: sources,
                rangeStart: start,
                rangeEnd: end,
                now: now,
                tokenProvider: { _ in token } // single account for now
            )
            try EventCache(appGroupIdentifier: AppConfig.appGroupID)?.write(cache)
            AppGroupStore(suiteName: AppConfig.appGroupID)?.lastSyncedAt = now
            status = "Synced \(cache.events.count) events across \(sources.count) calendars."
            WidgetCenter.shared.reloadAllTimelines() // refresh both the grid and agenda widgets
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
