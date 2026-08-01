import Foundation

/// Shared identifiers used by both the app and the widget extension.
public enum AppConfig {
    /// App Group container id (must match both targets' entitlements).
    public static let appGroupID = "group.com.ninbit.calwidget"

    /// WidgetKit `kind` for the two-week widget (used for reloadTimelines + the Widget).
    public static let twoWeekWidgetKind = "TwoWeekWidget"

    /// WidgetKit `kind` for the paginating agenda widget.
    public static let agendaWidgetKind = "AgendaWidget"

    /// WidgetKit `kind` for the medium (three-column) agenda widget.
    public static let agendaMediumWidgetKind = "AgendaMediumWidget"

    /// How many weeks the grid widget's window spans.
    ///
    /// The grid pipeline reads this everywhere rather than being generic per widget instance.
    /// `DateWindow` genuinely is generic over week count — it's pure math and tested that way —
    /// but the plumbing around it isn't: the paging intents run in a separate process and can't
    /// see which widget invoked them, and all grid instances share one `twoWeekPageOffset`. So a
    /// second grid widget of a different size would page against this one's windows regardless.
    /// Adding one means giving the grid the same treatment `AgendaVariant` gives the agendas — a
    /// per-widget offset key and an intent parameter — not just passing a different number here.
    public static let gridWeekCount = 2

    /// Agenda widget: how many days forward the agenda covers, starting at today. This is the
    /// source of the canonical cache window's far edge — `SyncCoordinator.canonicalRange` reads it
    /// — so raising it widens the fetch to match instead of leaving the agenda asking for days
    /// nothing ever fetched.
    public static let agendaHorizonDays = 14

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
