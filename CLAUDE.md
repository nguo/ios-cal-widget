# CalWidgetApp

iOS Google Calendar widgets: a two-week grid and two scrolling agendas. The app signs in and
syncs; the widget extension only renders from a shared cache.

**Read this file instead of re-exploring the tree.** If a change makes it wrong, fix it in the
same commit.

## Layout

| Path | Target | Contents |
|---|---|---|
| `CalCore/` | SPM package (both) | Models, networking, storage, formatting, layout math. Foundation-only, testable off-device. |
| `CalCore/…/Layout/` | SPM package (both) | Layout *decisions* as pure data: `WeekLayout`, `DayCellContent`, `AgendaPagination`. UI measurements injected, never read. |
| `CalWidgetApp/` | app | Sign-in, sync management, the calendar picker + in-app widget previews. |
| `CalendarWidgetExtension/` | extension only | Widget declarations, timeline providers, `SelectCalendarsIntent`. |
| `CalendarWidgetExtension/Shared/` | **app + extension** | Views, entries, builders, intents, style. |

`Shared/` compiling into *both* targets is the rule that's easy to get wrong: the app hosts
in-app previews, so anything it renders must live there. Widget declarations and timeline
providers stay at the extension root.

**What belongs in CalCore is decided by dependencies, not by target.** The criterion is
*Foundation-only, therefore testable off-device* — which is what makes `swift test` and
`calcore-check` work with no simulator. It is emphatically **not** "shared between targets",
since `Shared/` is shared too. So widget-only logic does belong in CalCore when it's pure:
`WeekLayout`, `DayCellContent`, and `AgendaPagination` are all consumed solely by widget
rendering, and living in CalCore is exactly why they have tests. Anything importing SwiftUI,
WidgetKit, or UIKit stays in `Shared/`. The pattern for straddling that line is to inject the
UI's numbers — `WeekLayout` takes `maxRowsPerCell`, `AgendaPagination` takes `AgendaMetrics`
(supplied by `WidgetStyle` via `AgendaVariant`).

## Data flow

Sync is one-way and the widget never networks:

```
GoogleCalendarAPIClient → CalendarSyncService (map + merge, color denormalized)
  → EventCacheData → EventCache.write (atomic, App Group) → widgets read
```

`SyncCoordinator` is the canonical sync — it reads the refresh token from the shared Keychain
and needs no GoogleSignIn SDK, so it runs in the extension too. Triggered by `AppRefresh`
(app foreground/background) and `RefreshNowIntent` (widget). Cross-process scratch state
(pagination offsets, pending deep link, sync flag) lives in `AppGroupStore`.

Calendar *selection* is per placed widget instance, stored in its `SelectCalendarsIntent`
configuration — not globally. The cache is a superset; filtering happens at render.

## The widgets

Registered in `CalendarWidgetBundle.swift`.

**`TwoWeekWidget`** (systemMedium) — `CalendarTimelineProvider` → `CalendarEntryBuilder` →
`CalendarGridView` (`MonthHeaderView` + `WeekdayHeaderRow` + `WeekRowView`). Generic over
`weekCount`. Paging via `ShiftWindowIntent`/`GoToTodayIntent`, offset in
`AppGroupStore.twoWeekPageOffset`.

**`AgendaWidget`** (systemSmall) and **`AgendaMediumWidget`** (systemMedium) share one pipeline:

```
AgendaEntryBuilder.live(calendarIds:showDeclined:variant:cache:)   ← Shared/, WidgetKit
  → AgendaPagination.orderedEvents    flat forward [AgendaSlot] over agendaHorizonDays
  → AgendaPagination.boundaries / pageStart / groups → [AgendaDayGroup]   ← CalCore, tested
  → AgendaView (small) | AgendaMediumView (medium)
```

All the page math is `AgendaPagination` in CalCore and covered by `AgendaPaginationTests`.
`AgendaEntryBuilder` is only the part that can't move: reading `AppGroupStore`/`EventCache` and
producing a `TimelineEntry`. Pass `cache:` when you already hold one — the timeline provider
builds many entries per reload and re-decoding the file for each is pure waste.

`AgendaVariant` is the seam between the two widgets. It bundles the three things that differ and
must travel together: WidgetKit `kind`, `AppGroupStore` offset key, and `AgendaPageSizing`
(`.heightFit(AgendaMetrics)` for small — a greedy row-height walk; `.fixedCount` for medium —
uniform cards). It's also where `WidgetStyle`'s measurements cross into CalCore. Raw-value
backed because `AppIntent` parameters must be simple types; the paging intents carry it across
the process hop as a string.

The two agendas use **separate offset keys on purpose** — one shared key would page them in
lockstep against mismatched boundaries.

## Invariants

- **`WidgetStyle` row heights and the page-fit math must stay in sync.** The page walk assumes
  rows render at exactly those heights; changing one alone silently mis-paginates. They meet at
  `WidgetStyle.agendaMetrics` → `AgendaVariant.pageSizing` → `AgendaPagination` — edit the
  heights and the rendering together.
- **One Sunday-first calendar: `Calendar.calWidget`.** Never hand-roll
  `Calendar.current` + `firstWeekday = 1` again; `DateWindow`'s week alignment depends on it, so
  a single site drifting is an off-by-one-day bug. (`DateWindow` normalizes its injected
  calendar internally — that one is deliberate.)
- **Filter cached events through `EventCacheData.visibleEvents(calendarIds:showDeclined:)`.**
  It is the single definition of "visible". The reload scheduler and the render path must agree,
  or the widget wakes for events it doesn't draw.
- **Never key a `ForEach` on `CalendarEvent.id`.** It's Google's event id and repeats across
  calendars when you're invited on two connected accounts — duplicate SwiftUI ids render the
  first row twice, showing the wrong calendar color. Key by position.
- **A widget tap can only open this app.** `Link` does *not* launch Google Calendar; iOS hands
  the URL to `CalWidgetApp.onOpenURL`, which forwards it. `OpenDeepLinkIntent` exists only
  because `systemSmall` ignores `Link` — it is not a way to skip the app hop. The 500ms
  cold-launch delay in `openPendingDeepLink` is a deliberate race workaround; leave it.
- **Use `View.clippedGridRow(height:)` for dense text rows.** A bare `.fixedSize()` propagates
  the text's natural width and stretches the whole widget.
- **Anything that writes the cache must `WidgetReloader.reloadAll()`.** All three widgets read
  the same cache, so a per-kind reload silently strands the others on stale data — which is
  exactly what happened when background/foreground/manual refresh each named only the grid.
  `WidgetReloader.reload(kind:)` is only for state that provably affects one widget (a paging
  offset, its own spinner).
- **A total sync failure must not be written.** `CalendarSyncService.buildCache` returns nil
  when *every* calendar fails; callers skip the write so the last good cache survives. Writing
  the empty result blanked the widget while leaving it looking freshly synced. A partial
  failure still writes — some data beats none.
- **Never percent-encode a path and then call `appendingPathComponent`.** It re-encodes the
  "%", so a calendar id's "%23" became "%2523" and every holiday/contacts calendar 404'd.
  Build URLs via `GoogleCalendarAPIClient.makeURL(encodedPath:query:)`.
- **The sync flag is a timestamp, not a Bool.** `AppGroupStore.isSyncing` derives from
  `syncStartedAt` and expires after `syncFlagTimeout`. An App Intent killed mid-sync never
  clears a plain flag, which then persists across launches and permanently dims the refresh
  button. Use `beginSync()` / `endSync()`.
- **Deep links are gated by `DeepLinkBuilder.isTrustedGoogleHost`.** `hasSuffix("google.com")`
  also matches `evilgoogle.com`. Both the `onOpenURL` router and the pending-link forwarder
  validate; the forwarder clears the stashed link *before* validating so a rejected one can't
  wedge the queue.
- Cross-account duplicate events currently render twice by design; deduping was deferred.
- Sync is **full-refetch only**. `nextSyncToken` is surfaced by the API client but not yet
  stored, so every refresh refetches the whole window — a known, deliberate gap.

## Build

`.xcodeproj` is generated by XcodeGen from `project.yml` and is gitignored, so **new files need
no `project.yml` edit** — drop them in the right directory and re-run `xcodegen generate`.
`Local.xcconfig` (Google client ID) is gitignored too, so a fresh worktree needs a copy from the
main checkout before XcodeGen will validate.

```
xcodegen generate
xcodebuild -project CalWidgetApp.xcodeproj -scheme CalWidgetApp \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
cd CalCore && swift test          # XCTest suite
cd CalCore && swift run calcore-check   # assertion harness, no XCTest needed
```

Agenda paging math is `AgendaPagination` in CalCore and is covered by `AgendaPaginationTests`
plus `calcore-check`, so change it test-first. What those tests *cannot* see is whether
`WidgetStyle`'s heights match what SwiftUI actually renders — that half still has to be
verified by rendering on a real device (an SE is the tight case).
