import Foundation

/// Lays out one week (7 columns) for the widget: multi-day all-day events become **lane-packed
/// spanning segments** (so a bar can connect across days), while timed events stay per-column.
/// Pure/testable — the SwiftUI `WeekRowView` turns this into geometry.
public struct WeekLayout: Equatable, Sendable {

    /// One all-day event clipped to this week: which columns it covers, which lane (row) it sits
    /// in, and whether its true span continues beyond this week (for squared vs. rounded ends).
    public struct AllDaySegment: Equatable, Sendable {
        public let event: CalendarEvent
        public let startColumn: Int      // 0…6
        public let endColumn: Int        // 0…6 (inclusive)
        public let lane: Int
        public let continuesLeft: Bool
        public let continuesRight: Bool

        public var columnSpan: Int { endColumn - startColumn + 1 }
    }

    public let allDaySegments: [AllDaySegment]
    /// Total all-day lanes used in the week (capped).
    public let laneCount: Int
    /// Per-column count of all-day lanes that actually cover that column — how far down that
    /// column's timed events start. A day with no all-day event covering it reserves 0.
    public let lanesByColumn: [Int: Int]
    /// Per-column timed content (below that column's lanes), budget reduced per column.
    public let timedByColumn: [Int: DayCellContent]

    public init(
        days: [Date],
        eventsByDay: [Date: [CalendarEvent]],
        calendar: Calendar,
        maxRowsPerCell: Int = DayCellContent.defaultMaxRows,
        maxAllDayLanes: Int? = nil
    ) {
        // Always leave at least one row for timed events / "+N more".
        let laneCap = maxAllDayLanes ?? max(1, maxRowsPerCell - 1)

        // 1. Unique all-day events touching this week (they appear in every covered day's array).
        var allDayById: [String: CalendarEvent] = [:]
        for day in days {
            for e in (eventsByDay[day] ?? []) where e.isAllDay { allDayById[e.id] = e }
        }

        // 2. Clip each to this week's columns + note cross-week continuation.
        let day0 = calendar.startOfDay(for: days.first ?? Date())
        let day6 = calendar.startOfDay(for: days.last ?? Date())
        struct Raw { let event: CalendarEvent; let startCol: Int; let endCol: Int; let left: Bool; let right: Bool }
        var raws: [Raw] = []
        for e in allDayById.values {
            let coveredCols = days.enumerated().compactMap { e.covers(day: $0.element, calendar: calendar) ? $0.offset : nil }
            guard let startCol = coveredCols.first, let endCol = coveredCols.last else { continue }
            let left = calendar.startOfDay(for: e.startDate) < day0
            let right = e.lastCoveredDay(in: calendar) > day6
            raws.append(Raw(event: e, startCol: startCol, endCol: endCol, left: left, right: right))
        }

        // 3. Greedy lane packing: earliest start first, longer spans first, title as tiebreak.
        let sorted = raws.sorted {
            if $0.startCol != $1.startCol { return $0.startCol < $1.startCol }
            let s0 = $0.endCol - $0.startCol, s1 = $1.endCol - $1.startCol
            if s0 != s1 { return s0 > s1 }
            return $0.event.title < $1.event.title
        }
        var laneLastEnd: [Int] = []   // last endCol placed in each lane
        var segments: [AllDaySegment] = []
        for raw in sorted {
            var lane = laneLastEnd.firstIndex { $0 < raw.startCol }
            if let l = lane {
                laneLastEnd[l] = raw.endCol
            } else {
                lane = laneLastEnd.count
                laneLastEnd.append(raw.endCol)
            }
            segments.append(AllDaySegment(
                event: raw.event, startColumn: raw.startCol, endColumn: raw.endCol,
                lane: lane!, continuesLeft: raw.left, continuesRight: raw.right
            ))
        }

        // Cap lanes (drop overflow all-day events — rare on a medium widget).
        let laneCount = min(laneLastEnd.count, laneCap)
        let capped = segments.filter { $0.lane < laneCount }
        self.allDaySegments = capped
        self.laneCount = laneCount

        // 4. Per-column reserved lanes: only push a column's timed events down by the lanes with
        // a bar actually covering that column, so a day with no all-day event keeps its top row.
        var lanesByColumn: [Int: Int] = [:]
        for col in 0 ..< days.count {
            let maxLane = capped.filter { $0.startColumn <= col && col <= $0.endColumn }.map(\.lane).max()
            lanesByColumn[col] = maxLane.map { $0 + 1 } ?? 0
        }
        self.lanesByColumn = lanesByColumn

        // 5. Timed events per column, using the rows left below THAT column's reserved lanes.
        var timed: [Int: DayCellContent] = [:]
        for (col, day) in days.enumerated() {
            let reserved = lanesByColumn[col] ?? 0
            let dayTimed = (eventsByDay[day] ?? []).filter { !$0.isAllDay }
            timed[col] = DayCellContent(events: dayTimed, calendar: calendar, maxRows: max(1, maxRowsPerCell - reserved))
        }
        self.timedByColumn = timed
    }
}
