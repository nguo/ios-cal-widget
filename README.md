# Google Calendar Widget for iOS

Home Screen widgets that show your Google Calendars. Three of them:

| Widget | Size | What it shows |
|---|---|---|
| **Two Weeks** | medium | A two-week grid. Multi-day events render as connected spanning bars. Page by whole windows, jump back to today, force a refresh. Tapping a day opens Google Calendar's Schedule view there. |
| **Agenda** | small | A scrolling list of upcoming days, paged by whole events. Tapping an event opens it in Google Calendar. |
| **Agenda (Medium)** | medium | The same agenda with room for full event cards — a date column and a paging rail. |

Each placed widget picks its **own** calendars: long-press → **Edit Widget** → **Select
Calendars**. Declined events are hidden by default and can be shown struck through per widget.

Events are synced by the companion app into a shared cache; the widgets only ever read that
cache, never the network.

## Architecture
- **CalCore** — local Swift package (Foundation-only): models, date math, formatting, layout
  and paging math, cache, networking, sync. Unit-tested; also runnable off-device via
  `swift run calcore-check`.
- **CalWidgetApp** — companion app: Google Sign-In, calendar list, sync, background refresh,
  and in-app previews of all three widgets.
- **CalendarWidgetExtension** — the WidgetKit extension: widget declarations, timeline
  providers, and the App Intents behind the paging/refresh buttons. Its `Shared/` directory
  compiles into *both* targets, since the app hosts the in-app previews.
- App + widget share event data via an **App Group** and the Google refresh token via a shared
  **Keychain** access group.
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
Need Client ID and Reverse Client ID for a Google-Calendar-API-enabled OAuth Client

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
Google — the first sync runs automatically.

Then long-press the Home Screen → **+** → search for **Cal Widget**, and add any of **Two
Weeks**, **Agenda**, or **Agenda (Medium)**. A freshly added widget prompts you to choose
calendars: long-press it → **Edit Widget** → **Select Calendars**.

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
- Sync is a full refetch of a rolling two-week window; incremental sync via Google's
  `syncToken` isn't implemented yet.
- The client ID + Team ID are supplied via the gitignored `Local.xcconfig`.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
[Google Cloud Console]: https://console.cloud.google.com
