# Google Calendar Widget for iOS

iOS widgets for displaying Google Calendar,including:
* Two-week view with pagination and force refresh. Tapping on a cell will open Google Calendar for that day.

## Architecture
- **CalCore** — local Swift package (Foundation-only): models, date math, formatting, cache,
  networking, sync. Unit-tested; also runnable off-device via `swift run calcore-check`.
- **CalWidgetApp** — companion app: Google Sign-In, calendar picker, sync, background refresh.
- **CalendarWidgetExtension** — the WidgetKit extension (`TwoWeekWidget`), reads a shared cache.
- App + widget share event data via an **App Group** and the Google refresh token via a shared
  **Keychain** access group.
- The Xcode project is **generated from `project.yml` by [XcodeGen]** (the `.xcodeproj` is gitignored).

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
Select the **CalWidgetApp** scheme + a Simulator or your device → ⌘R. In the app: sign in with
Google, pick calendars, tap **Sync now**. Then long-press the home screen → add the
**Two Week Calendar** widget.

## Testing
```sh
cd CalCore && swift run calcore-check   # fast off-device logic check (no Xcode needed)
cd CalCore && swift test                # full XCTest suite (Xcode toolchain)
```

## Notes
- The tap-a-day deep link needs a **physical device** with the Google Calendar app installed;
  on the Simulator it falls back to opening the app/Safari.
- The client ID + Team ID are supplied via the gitignored `Local.xcconfig`.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
[Google Cloud Console]: https://console.cloud.google.com
