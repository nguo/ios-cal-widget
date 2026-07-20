import Foundation

public extension Calendar {
    /// The calendar every part of this app must use: the user's current calendar, forced to
    /// Sunday-first so it matches the widget's "S M T W T F S" header.
    ///
    /// `firstWeekday` drives `DateWindow`'s week alignment, so a `Calendar.current` that
    /// disagreed (much of the world defaults to Monday) would shift the grid by a day against
    /// its own header. This was previously rebuilt by hand in eleven places; one of them
    /// drifting is a silent off-by-one-day bug.
    static var calWidget: Calendar {
        var c = Calendar.current
        c.firstWeekday = 1 // Sunday
        return c
    }
}
