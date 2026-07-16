import Foundation

/// Small typed wrapper over the App Group `UserDefaults`, shared between the app and the
/// widget extension. Holds lightweight cross-process state: the pagination offset, an
/// in-flight-sync flag, selected calendar ids, and the last successful sync time.
///
/// `UserDefaults` is injectable so this is testable off-device with a throwaway suite.
public struct AppGroupStore {
    private let defaults: UserDefaults

    private enum Key {
        static let pageOffset = "pageOffset"
        static let isSyncing = "isSyncing"
        static let selectedCalendarIds = "selectedCalendarIds"
        static let lastSyncedAt = "lastSyncedAt"
        static let accountEmail = "accountEmail"
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

    /// Signed count of whole windows from "the window containing today".
    /// 0 = current, +1 = next window, -1 = previous.
    public var pageOffset: Int {
        get { defaults.integer(forKey: Key.pageOffset) }
        nonmutating set { defaults.set(newValue, forKey: Key.pageOffset) }
    }

    /// True while a sync is in flight. Read by `RefreshNowIntent` (to no-op on double-tap)
    /// and by the widget UI (to disable/dim the refresh button).
    public var isSyncing: Bool {
        get { defaults.bool(forKey: Key.isSyncing) }
        nonmutating set { defaults.set(newValue, forKey: Key.isSyncing) }
    }

    public var selectedCalendarIds: [String] {
        get { defaults.stringArray(forKey: Key.selectedCalendarIds) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.selectedCalendarIds) }
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
}
