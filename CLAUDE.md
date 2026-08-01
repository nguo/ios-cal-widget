# CalWidgetApp

iOS Google Calendar widgets: a two-week grid and two paginating agendas. The app owns sign-in;
everything renders from a shared cache, which the app syncs and — on three specific paths — the
widget extension does too (see Data flow).

**Vocabulary:** the widgets *paginate* — they never scroll. WidgetKit has no scroll view; a page
turn is an App Intent that changes a stored offset and reloads the timeline. Reserve "scroll"
for things that genuinely scroll, i.e. Google Calendar's own views.

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

Sync is one-way — everything flows cache-ward, and nothing reads back up the chain:

```
GoogleCalendarAPIClient → CalendarSyncService (map + merge, color denormalized)
  → EventCacheData → EventCache.write (atomic, App Group) → widgets read
```

`SyncCoordinator` is the canonical sync — it reads the refresh token from the shared Keychain
and needs no GoogleSignIn SDK, so it runs in the extension too. Triggered by `AppRefresh`
(app foreground/background), `RefreshNowIntent` and `ShiftWindowIntent` (widget), and
`CoverageRefresh` (either timeline provider, when the reload lands on a window the cache no
longer covers). Cross-process scratch state (pagination offsets, pending deep link, sync flag)
lives in `AppGroupStore`.

**The widget extension does network, on those three paths only.** It's a real constraint worth
stating precisely rather than as "widgets only read the cache", which is what this said while
three networking paths existed. *Rendering* never networks: an entry is built from the cache and
nothing else. What networks is a paging tap into an uncached window, the refresh button, and the
coverage check that runs before a build — the last gated on `covers()` being false, so an
ordinary reload still costs nothing. All three go through `SyncCoordinator` and hold the shared
sync flag while they run, so they can't stack up on each other or on the app's syncs.

Calendar *selection* is per placed widget instance, stored in its `SelectCalendarsIntent`
configuration — not globally. The cache is a superset; filtering happens at render.

## The widgets

Registered in `CalendarWidgetBundle.swift`.

**`TwoWeekWidget`** (systemMedium) — `CalendarTimelineProvider` → `CalendarEntryBuilder` →
`CalendarGridView` (`MonthHeaderView` + `WeekdayHeaderRow` + `WeekRowView`). Window size is
`AppConfig.gridWeekCount`. Paging via `ShiftWindowIntent`/`GoToTodayIntent`, offset in
`AppGroupStore.twoWeekPageOffset`.

Don't read that as "generic over week count". `DateWindow` is — it's pure math and tested at
several sizes — but the plumbing around it isn't, and it used to *look* like it was while
`ShiftWindowIntent` hardcoded a 2 of its own. The intents run in another process and aren't told
which widget invoked them, and every grid instance shares one page offset, so a second grid of a
different size would page against this one's windows. Adding one means giving the grid what
`AgendaVariant` gives the agendas — a per-widget offset key and an intent parameter — so the
single constant is what's honest until then.

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
- **A day is not 86,400 seconds. Step days with `calendar.date(byAdding: .day, …)`.** Not a
  theoretical purity point: a grid window's last day is a Saturday, and several zones move the
  clock at midnight *entering Sunday* (America/Santiago, America/Nuuk, Asia/Beirut, Asia/Gaza,
  Pacific/Easter), so that Saturday is 23 or 25 hours. `DateWindow.endExclusive` added a flat day
  and on the 25-hour one landed at 23:00 Saturday — an hour *inside* the window it bounds, which
  shortened the fetch's `timeMax` so events in the window's last hour were never returned, and
  left a gap between windows that should abut. It's stored now, computed in `init` where the
  calendar is in scope; `DateWindowTests` pins it in Santiago. The one acceptable use is the
  `?? now.addingTimeInterval(86_400)` fallbacks in the timeline providers, which are only
  reached if calendar arithmetic fails outright and only pick a reload time.
- **Filter cached events through `EventCacheData.visibleEvents(calendarIds:showDeclined:)`.**
  It is the single definition of "visible". The reload scheduler and the render path must agree,
  or the widget wakes for events it doesn't draw.
- **Never construct a `DateFormatter` in a render or parse path** — init costs milliseconds and
  these run per row and per event. Go through `DateFormatterCache.shared.formatter(...)` (keyed
  by timezone, so it survives travel and DST) or `ISO8601Parsers`. Never mutate one you get back.
- **`UIScreen` is read exactly once, at launch, from `primeDeviceMetrics()`.** It's
  main-thread-only and timeline providers run on a background queue, so both the app and the
  widget bundle prime it in their initializers. Don't add a second read site.
- **Never call `Color(hex:)` directly in a view.** Go through the `WidgetStyle.eventBar` /
  `allDayFill` / `cardFill` / `cardTitle` / `cardDetail` / `eventTitle` / `eventDetail` helpers,
  which take a `WidgetRenderingMode`. A tinted Home Screen (`.accented`) or StandBy (`.vibrant`)
  flattens hue, so raw event colors collapse to one indistinguishable shade. Per-calendar
  identity is genuinely unrecoverable in those modes — the goal is legibility, not fidelity.
- **Never draw a label on top of an opaque fill. Use `.eventPlate(_:fill:mode:)`.** An opaque
  plate and the text on it flatten to the *same* flat color when recolored, so every all-day bar,
  medium-agenda card, and the "today" button rendered as a blank white slab. `eventPlate`
  switches the plate to a thin outline when recolored, leaving the label on the plain background
  — the arrangement timed rows already use.

  What's actually been verified, since the distinction matters if you revisit this: the *opaque*
  fills hid their labels (observed on the pre-tinting code), and the outline version renders
  correctly (observed on device). Whether a translucent plate would also have worked was never
  tested — the ~0.15-alpha chevron circles stayed legible throughout, which suggests it might
  have. The outline is kept because it doesn't depend on tuning alpha against a system behavior
  we can't easily predict, not because translucency was ruled out.
- **`.widgetAccentable()` covers a view *and its subtree*.** Only put it on things with no text
  inside them (timed capsules, the Sunday column, the today strip). Marking a plate that has a
  label inside drags the label into the same recolored group and hides it.
- **The midnight timeline reload is render-only — `CoverageRefresh` is what makes it sync.**
  `.after(tomorrow)` advances "today" from the cache; it doesn't refetch, so the cached window
  falls a day short of the horizon per day that passes, and at a week rollover the grid's window
  moves to a new Sunday the cache can't cover. Both providers call
  `CoverageRefresh.syncIfUncovered` before building, which is the **only** networking in the
  render path — it is gated on `covers()` being false, so a covered reload still costs nothing.
  The sync claim matters here: all three widgets wake on the same midnight tick and would
  otherwise each fetch the same range. `refreshCanonical` holds that claim, so the first widget
  to arrive does the work and the others get `.skipped`, render from disk, and pick up the
  result from its reload.
- **No spinners in a widget — say it in words.** A widget is a static snapshot; WidgetKit never
  animates it, so a `ProgressView` renders as an inert ring (and tinting flattened the one we
  had into a pale blob). In-progress state goes in `CalendarGridView`'s `banner`, which shows
  "Loading…" and takes priority over the stale banner — otherwise the widget tells you to tap
  refresh *during* a refresh. `ProgressView` in the **app** is fine; the app animates.
- **Paging intents must guard on `isSyncing` themselves**, not rely on the dimmed controls.
  The disabled state only reaches the screen once WidgetKit delivers the reloaded timeline, so
  taps landing before then each advanced the offset and ran ahead of the in-flight fetch.
  `ShiftWindowIntent` claims the flag *before* writing the new offset, to close that gap — via
  `claimSync()`, which re-checks, since the cache read between the entry guard and the claim is
  itself a window another process can start syncing in.
- **Read the cache once per timeline build and pass it down** (both builders take `cache:`).
  The agenda provider builds an entry per reload point; re-decoding the file for each is real
  memory and CPU inside a jetsam-limited extension. The grid builds one entry, but still gets
  the cache handed to it — `CoverageRefresh` returns the copy it read back after syncing, and
  decoding the same bytes a second time to build from them is free to avoid.
- **`CalendarEvent.id` does not identify an event — `cacheKey` (calendar + id) does.** It's
  Google's event id, unique only *within* a calendar, so the same meeting reachable through two
  calendars comes back once per calendar under one id. Two consequences, same root cause:
  never key a `ForEach` on it (duplicate SwiftUI ids render the first row twice in the wrong
  calendar's color — key by position), and never key a de-dupe or lookup on it
  (`EventCacheData.appending` did, which collapsed the copies and left the survivor wearing
  whichever calendar arrived last). `EventCacheTests` pins both halves of the merge behaviour:
  copies on different calendars survive, a refetch of one calendar still replaces its own.
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
  offset, its own spinner). Note this means `CoverageRefresh` also reloads the very provider
  that called it, costing one redundant rebuild — that has been weighed and kept. Excluding the
  caller needs an enumerable list of widget kinds, and a list that falls behind a newly added
  widget strands it on stale data, which is a worse failure than a rebuild that happens at most
  once per rollover and can't loop (the retriggered build finds `covers()` true).
- **A total sync failure must not be written.** `CalendarSyncService.buildCache` returns nil
  when *every* calendar fails; callers skip the write so the last good cache survives. Writing
  the empty result blanked the widget while leaving it looking freshly synced. A partial
  failure still writes — some data beats none.
- **Every sync replaces the cache with exactly one canonical range — `refreshCanonical`.** That
  is the whole reason no pruning exists: nothing accumulates, so nothing needs trimming.
  Pagination (`fetchWindowIfNeeded`) is the one writer that *merges*, and the next sync reclaims
  whatever it added — so back-paging stays cached within a session but never permanently. Don't
  reintroduce a union-with-existing-window refresh; that was `refetchAll`, and it grew the
  refetched range without bound for anyone who refreshed from the widget instead of the app.
  **This applies to the app's `AppSyncManager.syncNow` too**, which is where a second copy of
  that union survived after `refetchAll` was deleted: it read the cache's own `windowStart` /
  `windowEnd` and unioned against them, so each sync widened the window the *next* sync would
  union against. `syncNow` keeps its own fetch (it needs the GoogleSignIn token and the
  freshly-listed sources, which `refreshCanonical` can't supply on first run) but must take its
  range from `canonicalRange(coveringOffset:)` unmodified. No sync's range may be a function of
  what is currently cached — that is the whole property, and it is why nothing needs pruning.
- **That one range must satisfy both widgets, which want different windows.** The grid is
  week-aligned (most-recent Sunday … +`gridWeekCount` weeks); the agenda is
  today … +`agendaHorizonDays`.
  `canonicalRange(coveringOffset:)` spans the union — it starts at the *Sunday* (not today) and
  ends at whichever reaches further. The agenda's far edge lands exactly on `windowEnd` with zero
  slack, which is why `canonicalRange` **derives** its end from `AppConfig.agendaHorizonDays`
  instead of hardcoding a matching 14. Don't put the constant back: nothing tells the agenda its
  cache fell short — it just renders fewer days — and `CoverageRefresh` would see `covers()` false
  on every build and fire a sync that can't ever fix it.
- **A refresh while paged fetches the *visible* window, not just the canonical one.** Every sync
  passes `coveringOffset: twoWeekPageOffset`, so refreshing a widget paged to +5 fetches
  today … that window's end contiguously. This is what makes the refresh button work on a paged
  view, and it's why deleting `refetchAll` lost nothing — only *other* windows, previously paged
  to but not on screen, are dropped.
- **Multi-day spans survive the replace.** A trip that began last week meets a cache starting
  today. Google's `timeMin` bounds an event's *end* (and `timeMax` its start), so the fetch
  returns overlapping spans; `AgendaPagination.orderedEvents` and `CalendarEntryBuilder.groupByDay`
  then clip to the window with `max(startOfDay(event.start), first)` rather than dropping events
  that start out of range. Both halves are pinned by tests — keep the clipping if you touch them.
- **Never percent-encode a path and then call `appendingPathComponent`.** It re-encodes the
  "%", so a calendar id's "%23" became "%2523" and every holiday/contacts calendar 404'd.
  Build URLs via `GoogleCalendarAPIClient.makeURL(encodedPath:query:)`.
- **The sync flag is a timestamp, not a Bool.** `AppGroupStore.isSyncing` derives from
  `syncStartedAt` and expires after `syncFlagTimeout`. An App Intent killed mid-sync never
  clears a plain flag, which then persists across launches and permanently dims the refresh
  button. Claim it with `claimSync()` / `endSync()`; `beginSync()` is the unconditional
  primitive underneath and is not how you start a sync.
- **`refreshCanonical` claims the sync flag itself — don't guard it at the call site.** It
  returns `.skipped` when another sync holds the claim. The guard sits inside because that
  function *replaces* the whole cache, so two overlapping syncs mean the loser's write is
  silently discarded — and when the loser is `ShiftWindowIntent`'s pagination fetch, the widget
  lands on the page the user just navigated to with no events on it. Guarding per-call-site is
  what left `AppRefresh`'s foreground and background syncs unguarded in both directions.
  Callers that reload widgets to clear a spinner must check `.ran`, not just success: a
  `.skipped` call never touched the in-flight state, and whoever holds the claim will reload.
  Two paths still claim externally, both deliberately: `ShiftWindowIntent` (it must hold the
  claim from before it publishes the new offset until after `fetchWindowIfNeeded` returns) and
  `AppSyncManager.syncNow` (it fetches with the app's own signed-in sources rather than going
  through `refreshCanonical`).
- **Deep links are gated by `DeepLinkBuilder.isTrustedGoogleHost`.** `hasSuffix("google.com")`
  also matches `evilgoogle.com`. Both the `onOpenURL` router and the pending-link forwarder
  validate; the forwarder clears the stashed link *before* validating so a rejected one can't
  wedge the queue.
- Cross-account duplicate events currently render twice by design; deduping was deferred. The
  cache preserves them deliberately (see `cacheKey`) — if they're ever collapsed, it has to
  happen at render, where the widget can pick which calendar's color to show.
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

**If `xcode-select -p` returns `/Library/Developer/CommandLineTools` rather than an Xcode path
— it does on the machine this was written on — the first two commands fail**: `xcodebuild` with
"requires Xcode", `swift test` with "no such module 'XCTest'". Export the toolchain instead of
`sudo xcode-select --switch`, which changes a system-wide setting:

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

`calcore-check` is the exception and runs fine on the stock toolchain — being able to check the
logic with no Xcode at all is the reason it exists, so reach for it first. Set `DEVELOPER_DIR`
consistently across a session once you do need it: mixing toolchains poisons `CalCore/.build`
("module compiled with Swift 6.3.3 cannot be imported by the Swift 6.1.2 compiler").

Agenda paging math is `AgendaPagination` in CalCore and is covered by `AgendaPaginationTests`
plus `calcore-check`, so change it test-first. What those tests *cannot* see is whether
`WidgetStyle`'s heights match what SwiftUI actually renders — that half still has to be
verified by rendering on a real device (an SE is the tight case).
