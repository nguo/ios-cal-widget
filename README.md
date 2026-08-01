# Google Calendar Widget for iOS

Home Screen widgets that show your Google Calendars. Three of them:

| Widget | Size | What it shows |
|---|---|---|
| **Two Weeks** | medium | A two-week calendar view with events. |
| **Agenda** | small | A paginated list of upcoming days with events. |
| **Agenda (Medium)** | medium | A larger paginated list of upcoming days with events. |

For the two-week widget, tapping a date opens the Google Calendar schedule starting from that
date, and tapping the month name opens that month's view. In both agendas, tapping a date opens
that day in Google Calendar and tapping an event opens that event.

Sign in with **as many Google accounts as you like**. Each placed widget picks its **own**
calendars — and can mix calendars from several accounts — via long-press → **Edit Widget** →
**Select Calendars**, where they're listed under the account they belong to. Declined events are
hidden by default and can be shown struck through per widget.

Only the calendars a widget is actually showing get their events fetched, so adding an account
costs one request to list its calendars rather than a fetch per calendar it owns.

Events are synced into a shared cache and the widgets render from it — drawing a widget never
touches the network. The companion app syncs on launch and in the background, and the widgets
can sync too: the refresh button, paging into weeks not yet fetched, and a coverage check that
tops the cache up when a day or week rollover leaves it short — or when you add a calendar the
cache hasn't fetched yet.

## Architecture
- **CalCore** — local Swift package (Foundation-only): models, date math, formatting, layout
  and paging math, cache, networking, sync. Unit-tested; also runnable off-device via
  `swift run calcore-check`.
- **CalWidgetApp** — companion app: adding and removing Google accounts, sync, background
  refresh, and in-app previews of all three widgets.
- **CalendarWidgetExtension** — the WidgetKit extension: widget declarations, timeline
  providers, and the App Intents behind the paging/refresh buttons. Its `Shared/` directory
  compiles into *both* targets, since the app hosts the in-app previews.
- App + widget share event data via an **App Group** and each account's Google refresh token via
  a shared **Keychain** access group.
- The Xcode project is **generated from `project.yml` by [XcodeGen]** (the `.xcodeproj` is gitignored).

See [CLAUDE.md](CLAUDE.md) for the internals: data flow, the shared agenda pipeline, and the
invariants worth not breaking.

## Requirements
- Xcode 16+ (iOS 17+ interactive widgets / App Intents).
- [XcodeGen]: `brew install xcodegen`.
- An Apple Developer account — a **free Personal Team** is enough for the Simulator / your own device.
- A Google Cloud project with an **OAuth iOS client**.

## Setup

### 1. Google OAuth client
In the [Google Cloud Console], enable the Google Calendar API and create an **OAuth client ID**
of type **iOS**. You need its Client ID and Reversed Client ID for the next step.

### 2. Local config (not committed)
```sh
cp Local.xcconfig.example Local.xcconfig
```
Fill in your values:
```
DEVELOPMENT_TEAM   = <your 10-char Apple Team ID>    # Xcode → Settings → Accounts
GID_CLIENT_ID      = <client-id>.apps.googleusercontent.com
REVERSED_CLIENT_ID = com.googleusercontent.apps.<client-id>
```
`Local.xcconfig` is gitignored, so your IDs are never committed.

### 3. Generate & run
```sh
xcodegen generate
open CalWidgetApp.xcodeproj
```
Select the **CalWidgetApp** scheme + a Simulator or your device → ⌘R. In the app, sign in with
Google; **Add account** repeats that for as many accounts as you want. Your calendars are listed
straight away.

Then long-press the Home Screen → **+** → search for **Cal Widget**, and add any of **Two
Weeks**, **Agenda**, or **Agenda (Medium)**. A freshly added widget prompts you to choose
calendars: long-press it → **Edit Widget** → **Select Calendars**. Events start syncing once
something is selected — until then there's nothing to fetch.

## Testing
```sh
cd CalCore && swift run calcore-check   # fast off-device logic check (no Xcode needed)
cd CalCore && swift test                # full XCTest suite (Xcode toolchain)
```

## Notes
- Widget taps need a **physical device** with the Google Calendar app installed; on the
  Simulator they fall back to opening this app or Safari. A tap always routes through this app
  first — iOS won't let a widget launch another app directly.
- Tinted Home Screen and StandBy flatten all color, so per-calendar hues can't be distinguished
  in those modes. The widgets adapt — filled event plates become outlines — so everything stays
  readable, but which calendar an event belongs to is not recoverable there.
- Every sync refetches in full and replaces the cache with one rolling window — today through
  the agenda's horizon, widened to cover the grid's current page. Nothing accumulates, so
  nothing needs pruning. Incremental sync via Google's `syncToken` isn't implemented yet.
- If one account is unreachable while others sync fine, its last-known events are kept rather
  than blanked, so only the accounts that genuinely answered get replaced.
- Tapping an event from a second account opens Google Calendar's *first* account — the deep link
  can't yet name which account it belongs to.
- Paging the grid back or forward past the cached window fetches that window on demand. It stays
  cached for the session; the next full sync reclaims it.
- The client ID + Team ID are supplied via the gitignored `Local.xcconfig`.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
[Google Cloud Console]: https://console.cloud.google.com
