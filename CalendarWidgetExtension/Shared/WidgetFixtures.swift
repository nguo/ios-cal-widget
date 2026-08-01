import Foundation
import CalCore

/// Sample data for widget placeholders, the gallery snapshot, the in-app widget preview, and
/// SwiftUI previews. Events are positioned relative to "today" so they always fall inside the
/// current window.
enum WidgetFixtures {
    static let blue = "#4285F4"
    static let green = "#0B8043"
    static let red = "#D50000"
    static let purple = "#8E24AA"

    static func cache(calendar: Calendar, reference: Date = Date()) -> EventCacheData {
        let cal = calendar
        let today = cal.startOfDay(for: reference)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day(dayOffset))!
        }

        let events: [CalendarEvent] = [
            .init(id: "1", calendarId: "a", title: "Lunch", startDate: at(0, 12), endDate: at(0, 13), isAllDay: false, colorHex: green),
            .init(id: "2", calendarId: "a", title: "Museum", startDate: at(0, 15), endDate: at(0, 16, 30), isAllDay: false, colorHex: purple),
            .init(id: "3", calendarId: "b", title: "Cycling", startDate: at(2, 17, 30), endDate: at(2, 19), isAllDay: false, colorHex: blue),
            // Multi-day all-day events (spanning bars): a 3-day trip, an overlapping conference,
            // and a longer one that crosses the week boundary.
            .init(id: "4", calendarId: "b", title: "Trip to Portland", startDate: day(1), endDate: day(4), isAllDay: true, colorHex: blue),
            .init(id: "4b", calendarId: "a", title: "Conf", startDate: day(2), endDate: day(4), isAllDay: true, colorHex: purple),
            .init(id: "4c", calendarId: "b", title: "Vacation", startDate: day(5), endDate: day(10), isAllDay: true, colorHex: green),
            .init(id: "5", calendarId: "a", title: "Standup", startDate: at(8, 9), endDate: at(8, 9, 30), isAllDay: false, colorHex: blue),
            .init(id: "6", calendarId: "a", title: "1:1", startDate: at(8, 11), endDate: at(8, 11, 30), isAllDay: false, colorHex: green),
            .init(id: "7", calendarId: "a", title: "Review", startDate: at(8, 14), endDate: at(8, 15), isAllDay: false, colorHex: purple),
            .init(id: "8", calendarId: "a", title: "Dinner", startDate: at(8, 18), endDate: at(8, 20), isAllDay: false, colorHex: green),
            .init(id: "9", calendarId: "a", title: "Late", startDate: at(8, 21), endDate: at(8, 22), isAllDay: false, colorHex: blue)
        ]

        let sources = [
            CalendarSource(id: "a", accountEmail: "me@example.com", summary: "Personal", colorHex: green),
            CalendarSource(id: "b", accountEmail: "me@example.com", summary: "Fun", colorHex: blue)
        ]

        return EventCacheData(
            generatedAt: reference,
            windowStart: cal.date(byAdding: .day, value: -14, to: today)!,
            windowEnd: cal.date(byAdding: .day, value: 42, to: today)!,
            sources: sources,
            events: events
        )
    }

    /// A ready-to-render entry for SwiftUI/widget previews.
    static func entry(pageOffset: Int = 0, isSyncing: Bool = false, reference: Date = Date()) -> CalendarTimelineEntry {
        let cal = Calendar.calWidget
        let data = cache(calendar: cal, reference: reference)
        let window = DateWindow(referenceDate: reference, pageOffset: pageOffset, weekCount: AppConfig.gridWeekCount, calendar: cal)
        return CalendarTimelineEntry(
            date: reference,
            window: window,
            eventsByDay: CalendarEntryBuilder.groupByDay(events: data.events, window: window, calendar: cal),
            cacheIsStale: false,
            isSyncing: isSyncing,
            lastSyncedAt: reference
        )
    }

    /// A ready-to-render agenda entry for SwiftUI/widget previews. `eventOffset` selects the page;
    /// `variant` picks the page sizing so a medium preview breaks pages where the medium widget does.
    static func agendaEntry(eventOffset: Int = 0, variant: AgendaVariant = .small, reference: Date = Date()) -> AgendaEntry {
        let cal = Calendar.calWidget
        let data = cache(calendar: cal, reference: reference)
        let ordered = AgendaPagination.orderedEvents(reference: reference, calendar: cal, cache: data)
        let sizing = variant.pageSizing
        let bounds = AgendaPagination.boundaries(ordered, sizing: sizing)
        let start = AgendaPagination.pageStart(for: eventOffset, in: bounds)
        return AgendaEntry(
            date: reference,
            groups: AgendaPagination.groups(from: ordered, offset: start, sizing: sizing),
            canPageBack: start > 0,
            canPageForward: start < (bounds.last ?? 0),
            pageStart: start,
            lastSyncedAt: reference,
            calendarIds: nil
        )
    }
}
