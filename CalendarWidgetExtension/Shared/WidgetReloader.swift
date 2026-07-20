import WidgetKit
import CalCore

/// Single place that decides which widgets to reload, so the choice is explicit at each call
/// site instead of being spelled out ad hoc.
///
/// Compiled into both targets (it lives in `Shared/`), because the app's foreground/background
/// refresh and the extension's intents both need it.
enum WidgetReloader {

    /// Reload every widget. Use after **anything that writes the cache**.
    ///
    /// Deliberately `reloadAllTimelines()` rather than a list of kinds: all three widgets render
    /// from the same cache, and the previous per-kind calls named only the two-week grid — so a
    /// background sync, a foreground sync, and the widget's own refresh button all left both
    /// agenda widgets showing stale data until their next midnight reload. A blanket reload also
    /// can't go stale when a fourth widget is added.
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Reload a single kind. Only for state that provably affects that widget alone — a paging
    /// offset, or its own in-flight spinner. If the cache changed, use `reloadAll()`.
    static func reload(kind: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
