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
        static let agendaMediumEventOffset = "agendaMediumEventOffset"
        static let syncStartedAt = "syncStartedAt"
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
    /// (0 = the first event on the today page). Advances to the next page boundary, which is
    /// content-dependent — see `AgendaPageSizing`. Never negative: the agenda doesn't page
    /// into the past.
    public var agendaEventOffset: Int {
        get { defaults.integer(forKey: Key.agendaEventOffset) }
        nonmutating set { defaults.set(newValue, forKey: Key.agendaEventOffset) }
    }

    /// The medium agenda widget's own pagination offset. Deliberately a separate key from
    /// `agendaEventOffset`: the two agenda widgets fit a different number of events per page, so
    /// sharing one offset would page them in lockstep against mismatched boundaries.
    public var agendaMediumEventOffset: Int {
        get { defaults.integer(forKey: Key.agendaMediumEventOffset) }
        nonmutating set { defaults.set(newValue, forKey: Key.agendaMediumEventOffset) }
    }

    /// How long a sync may be in flight before its flag is assumed abandoned.
    public static let syncFlagTimeout: TimeInterval = 90

    /// When the in-flight sync started, or nil if none. Prefer `isSyncing` for reads; to start a
    /// sync use `claimSync()` / `endSync()`. `beginSync()` claims unconditionally — it's the
    /// primitive behind `claimSync`, not the way to begin a sync.
    public var syncStartedAt: Date? {
        get { defaults.object(forKey: Key.syncStartedAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.syncStartedAt) }
    }

    /// True while a sync is in flight. Read by `RefreshNowIntent` (to no-op on double-tap)
    /// and by the widget UI (to disable/dim the refresh button).
    ///
    /// Deliberately derived from a *timestamp* rather than stored as a Bool: App Intents run
    /// under a short budget, and an extension killed mid-sync never got to clear a plain flag.
    /// It then persisted in shared UserDefaults across launches, permanently dimming the
    /// refresh button and making `RefreshNowIntent`'s own guard early-return forever, with no
    /// way for the user to recover. A stale timestamp simply expires.
    public var isSyncing: Bool {
        guard let started = syncStartedAt else { return false }
        return Date().timeIntervalSince(started) < Self.syncFlagTimeout
    }

    public func beginSync(now: Date = Date()) { syncStartedAt = now }

    public func endSync() { syncStartedAt = nil }

    /// Claims the in-flight flag, or returns false if a sync is already running. The check and
    /// the claim are one call so every sync entry point guards identically — spelling the pair
    /// out by hand is how the app's foreground/background refresh ended up not guarding at all,
    /// letting a canonical rebuild land on top of a widget's paged fetch and drop it.
    public func claimSync(now: Date = Date()) -> Bool {
        guard !isSyncing else { return false }
        beginSync(now: now)
        return true
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
