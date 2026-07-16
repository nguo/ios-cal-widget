import Foundation

/// Shared identifiers used by both the app and the widget extension.
public enum AppConfig {
    /// App Group container id (must match both targets' entitlements).
    public static let appGroupID = "group.com.ninbit.calwidget"

    /// WidgetKit `kind` for the two-week widget (used for reloadTimelines + the Widget).
    public static let twoWeekWidgetKind = "TwoWeekWidget"

    /// Shared Keychain access group suffix (prefixed with the team's AppIdentifierPrefix at runtime).
    public static let keychainAccessGroupSuffix = "com.ninbit.calwidget.tokens"

    /// Google OAuth iOS client ID. Read from the running process's Info.plist `GIDClientID`
    /// (injected from the gitignored `Local.xcconfig` at build time) — kept out of committed
    /// source. Both the app and the widget extension carry the key in their Info.plist, so
    /// `Bundle.main` resolves it in either process.
    public static var googleClientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
    }

    /// BGTask identifier for periodic background refresh (must match Info.plist
    /// BGTaskSchedulerPermittedIdentifiers).
    public static let backgroundRefreshTaskID = "com.ninbit.calwidget.refresh"
}
