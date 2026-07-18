import Foundation

/// Small typed wrapper over the App Group `UserDefaults`, shared between the app and the
/// widget extension. Holds lightweight cross-process state: the pagination offset, an
/// in-flight-sync flag, and the last successful sync time. Calendar selection is no longer
/// global — it's stored per-widget in each instance's configuration intent.
///
/// `UserDefaults` is injectable so this is testable off-device with a throwaway suite.
public struct AppGroupStore {
    private let defaults: UserDefaults

    private enum Key {
        static let twoWeekPageOffset = "twoWeekPageOffset"
        static let agendaEventOffset = "agendaEventOffset"
        static let isSyncing = "isSyncing"
        static let lastSyncedAt = "lastSyncedAt"
        static let accountEmail = "accountEmail"
        static let pendingDeepLink = "pendingDeepLink"
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Convenience init against the shared App Group suite. Returns nil if the suite
    /// can't be opened (e.g. missing entitlement).
    public init?(suiteName: String) {
        guard let d = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = d
    }

    /// Two-week grid pagination: signed count of whole windows from "the window containing
    /// today". 0 = current, +1 = next window, -1 = previous.
    public var twoWeekPageOffset: Int {
        get { defaults.integer(forKey: Key.twoWeekPageOffset) }
        nonmutating set { defaults.set(newValue, forKey: Key.twoWeekPageOffset) }
    }

    /// Agenda pagination: index of the first visible event in the forward-ordered event list
    /// (0 = first event on the today page, then steps of `AppConfig.agendaEventsPerPage`). Never
    /// negative — the agenda doesn't page into the past.
    public var agendaEventOffset: Int {
        get { defaults.integer(forKey: Key.agendaEventOffset) }
        nonmutating set { defaults.set(newValue, forKey: Key.agendaEventOffset) }
    }

    /// True while a sync is in flight. Read by `RefreshNowIntent` (to no-op on double-tap)
    /// and by the widget UI (to disable/dim the refresh button).
    public var isSyncing: Bool {
        get { defaults.bool(forKey: Key.isSyncing) }
        nonmutating set { defaults.set(newValue, forKey: Key.isSyncing) }
    }

    public var lastSyncedAt: Date? {
        get { defaults.object(forKey: Key.lastSyncedAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastSyncedAt) }
    }

    /// The signed-in Google account email (single-account for now). Lets the widget's refresh
    /// intent find the right refresh token in the shared Keychain.
    public var accountEmail: String? {
        get { defaults.string(forKey: Key.accountEmail) }
        nonmutating set { defaults.set(newValue, forKey: Key.accountEmail) }
    }

    /// A deep link the widget wants the app to open. A small widget can't follow a `Link`, so a
    /// tapped agenda row stashes its Google Calendar URL here and opens the app; the app reads and
    /// forwards to it, then clears this. Written by `OpenDeepLinkIntent`, consumed by the app.
    public var pendingDeepLink: String? {
        get { defaults.string(forKey: Key.pendingDeepLink) }
        nonmutating set { defaults.set(newValue, forKey: Key.pendingDeepLink) }
    }
}
