import WidgetKit
import Foundation
import CalCore

/// What the placed widgets currently ask for — the set of calendars a sync fetches events for.
///
/// Events are fetched on demand rather than for every calendar of every account. At one account
/// "fetch everything" was fine; at three it is 45 event requests, which won't finish inside an App
/// Intent's time budget and draws Google's rate limiter besides. So the sync needs to know what is
/// actually on screen, and WidgetKit is the only thing that knows.
///
/// `SyncCoordinator` can't ask: it lives in CalCore, which is Foundation-only so it stays testable
/// off-device. Hence the split — this side enumerates and mirrors into `AppGroupStore`, and the
/// sync reads the mirror. Compiled into both targets, because the app refreshes on foreground and
/// the extension refreshes from its intents.
enum WidgetDemand {

    /// Re-reads every placed widget's configuration and mirrors the union of their selections into
    /// `AppGroupStore.demandedCalendarRefs`.
    ///
    /// `currentConfigurations()` is the authority: a widget the user removed disappears from it,
    /// which a registry we maintained ourselves could never notice. It can also fail, and on
    /// failure the previous mirror is deliberately left alone — syncing a slightly stale calendar
    /// set beats syncing nothing.
    static func refreshMirror() async {
        guard let store = AppGroupStore(suiteName: AppConfig.appGroupID) else { return }
        guard let refs = await currentRefs() else { return }
        store.demandedCalendarRefs = refs
    }

    /// nil when the configurations couldn't be read at all — distinct from an empty set, which
    /// legitimately means every placed widget is unconfigured.
    ///
    /// The completion-handler form, resolved into the ref set inside the callback: the async
    /// `currentConfigurations()` is iOS 18 and this ships to 17.
    private static func currentRefs() async -> Set<CalendarRef>? {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                guard let infos = try? result.get() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: infos.reduce(into: Set<CalendarRef>()) { refs, info in
                    guard let intent = info.widgetConfigurationIntent(of: SelectCalendarsIntent.self) else { return }
                    refs.formUnion(intent.selectedRefs)
                })
            }
        }
    }

    /// The canonical sync, with the demand mirror refreshed first.
    ///
    /// **This is how app and extension code syncs — never `SyncCoordinator.refreshCanonical`
    /// directly.** The mirror is the only thing the coordinator can read to decide what to fetch,
    /// so calling past this leaves a calendar the user just selected permanently unfetched: the
    /// widget renders it empty, and every later sync reproduces the same gap.
    @discardableResult
    static func refreshCanonical(
        calendar: Calendar = .calWidget,
        now: Date = Date(),
        onClaim: () -> Void = {}
    ) async -> SyncOutcome {
        await refreshMirror()
        return await SyncCoordinator.refreshCanonical(calendar: calendar, now: now, onClaim: onClaim)
    }
}
