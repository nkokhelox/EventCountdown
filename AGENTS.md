# AGENTS.md

Guidance for AI agents working in the **EventCountdown** repository.

## What this is

A native macOS **menu bar** app (SwiftUI + AppKit + EventKit) that shows a smart
countdown to your next calendar event. No Dock icon — the UI lives entirely in the
menu bar panel. Targets macOS 14.0+, built with Xcode 15+.

## Layout

```
EventCountdown/
  EventCountdownApp.swift      App entry point (menu bar scene)
  AppDelegate.swift            AppKit delegate (settings window, activation)
  AppModel.swift               Observable app state (@Observable)
  CountdownFormatter.swift     Countdown math + list/menu-bar text formatting
  Models/                      CalendarEvent, EmojiRule, EventKey
  Services/                    CalendarService, EmojiMappingStore, LaunchAtLoginService
  Utilities/                   Emoji resolution, call-link parsing, panel metrics
  Views/                       EventListView (the panel), SettingsView, editors, labels
  Assets.xcassets/             App icon
EventCountdownTests/           XCTest unit tests
scripts/GenerateAppIcon.swift  Regenerates the app icon at all sizes
```

## Build / test / run

Build (Debug):

```bash
xcodebuild -project EventCountdown.xcodeproj -scheme EventCountdown -destination 'platform=macOS' build
```

Run tests:

```bash
xcodebuild -project EventCountdown.xcodeproj -scheme EventCountdown -destination 'platform=macOS' test
```

Restart the built app (menu bar app, so relaunch to see changes):

```bash
osascript -e 'quit app "EventCountdown"' 2>/dev/null; pkill -x EventCountdown 2>/dev/null; sleep 1
open "$(xcodebuild -project EventCountdown.xcodeproj -scheme EventCountdown -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{d=$3}/ FULL_PRODUCT_NAME/{n=$3}END{print d"/"n}')"
```

**Repo rule: always restart the app after editing it.** Every time you change app
code, rebuild and then restart the running app with the command above so the menu
bar instance reflects your change — don't leave a stale instance running. The built
product is under `~/Library/Developer/Xcode/DerivedData/EventCountdown-*/Build/Products/Debug/`.

## Conventions

- **Swift / SwiftUI** for views; **AppKit** (`NSWorkspace`, `NSAppleScript`) where the
  system API requires it. State is an `@Observable` `AppModel` injected via
  `.environment`.
- **Countdown text** goes through `CountdownFormatter` — don't format durations
  inline. `listText` = compact row form, `fullRemainingListText` = expanded form.
  Fixed units: 1 year = 365 days, 1 month = 30 days, 1 week = 7 days.
- **No single-use one-liner helpers.** If a helper is only called once and is
  essentially one expression, inline it at the call site.
- **Remove dead code** you orphan. When you delete the last caller of a private
  helper, delete the helper too (unless a test still exercises it — grep first).
- **Calendar access** goes through `CalendarService`; opening Calendar.app uses
  `openCalendar(to:)` (AppleScript date navigation — first use prompts for Apple
  Events permission).

## Commits

Follow **Conventional Commits** (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`,
`test:`). Commit or push only when the user explicitly asks. Keep the app icon
assets out of unrelated diffs.

## Verifying

Unit tests cover `CountdownFormatter` and `EventCallLink`. Anything touching the
menu bar panel, AppleScript, or Calendar/Notification permissions can't be fully
verified headlessly — build, then ask the user to confirm the interaction in the
running app.
