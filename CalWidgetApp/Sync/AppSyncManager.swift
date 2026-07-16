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
    }

    private func persistSelection() {
        let ids = sources.filter { $0.isSelected }.map { $0.id }
        AppGroupStore(suiteName: AppConfig.appGroupID)?.selectedCalendarIds = ids
    }

    /// Fetch the canonical −2/+6-week window across selected calendars and write the cache.
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
            let today = calendar.startOfDay(for: Date())
            let start = calendar.date(byAdding: .day, value: -14, to: today)!
            let end = calendar.date(byAdding: .day, value: 42, to: today)!

            let cache = await service.buildCache(
                sources: sources,
                rangeStart: start,
                rangeEnd: end,
                now: Date(),
                tokenProvider: { _ in token } // single account for now
            )
            try EventCache(appGroupIdentifier: AppConfig.appGroupID)?.write(cache)
            status = "Synced \(cache.events.count) events across \(sources.filter { $0.isSelected }.count) calendars."
            WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.twoWeekWidgetKind)
        } catch {
            status = "Sync failed: \(error.localizedDescription)"
        }
    }
}
