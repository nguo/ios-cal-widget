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
    /// In-flight debounced resync scheduled by calendar-selection changes.
    private var resyncTask: Task<Void, Never>?

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }

    func rebind(auth: GoogleAuthService) { self.auth = auth }

    /// Fetch the account's calendar list and reconcile with persisted selection.
    func loadCalendars() async {
        guard let auth else { return }
        do {
            let token = try await auth.accessToken()
            let entries = try await api.calendarList(accessToken: token)
            let selected = Set(AppGroupStore(suiteName: AppConfig.appGroupID)?.selectedCalendarIds ?? [])
            let email = auth.email ?? ""
            sources = entries.map { entry in
                CalendarSource(
                    id: entry.id,
                    accountEmail: email,
                    summary: entry.summary ?? entry.id,
                    colorHex: entry.backgroundColor ?? "#4285F4",
                    isSelected: selected.contains(entry.id)
                )
            }
        } catch {
            status = "Failed to load calendars: \(error.localizedDescription)"
        }
    }

    func toggle(_ id: String) {
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[i].isSelected.toggle()
        persistSelection()
        scheduleResync()
    }

    /// Refetch so the widget's cache reflects the new calendar set. Debounced so toggling
    /// several calendars in a row coalesces into one sync with the final selection rather than
    /// firing (and racing) a full fetch per tap.
    private func scheduleResync() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func persistSelection() {
        let ids = sources.filter { $0.isSelected }.map { $0.id }
        AppGroupStore(suiteName: AppConfig.appGroupID)?.selectedCalendarIds = ids
    }

    /// Fetch across selected calendars and write the cache. Covers the canonical −2/+6-week
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
            status = "Synced \(cache.events.count) events across \(sources.filter { $0.isSelected }.count) calendars."
            WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.twoWeekWidgetKind)
        } catch {
            status = "Sync failed: \(error.localizedDescription)"
        }
    }

    /// Range to fetch: canonical, widened to cover the widget's currently-paged window and
    /// whatever breadth pagination had already cached (so a selection change refetches all of it).
    private func syncRange(now: Date) -> (start: Date, end: Date) {
        let offset = AppGroupStore(suiteName: AppConfig.appGroupID)?.pageOffset ?? 0
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
