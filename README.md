# EventCountdown

Native macOS menu bar app that shows a smart countdown to your next calendar event.

## Requirements

- macOS 14.0 or later
- Xcode 15+

## Open and run

```bash
open /Users/nkokhelo/PISD_PROJECTS/EventCountdown/EventCountdown.xcodeproj
```

1. Select the **EventCountdown** scheme
2. Press **Cmd+R** to build and run
3. Grant **Calendar** and **Notifications** when prompted

The app lives in the menu bar only (no Dock icon). Use the calendar menu bar item to open the panel; **Settings…** and **Quit** are in the footer.

## Features

- Menu bar countdown with emoji prefixes (configurable rules in Settings)
- Hover tooltip with full event title
- Next 5 upcoming events in the dropdown
- End-of-countdown notifications with **Acknowledge** action
- Pre-scheduled reminder chain for up to 12 hours (or 5 minutes in Debug with `DEBUG_SHORT_ACK_WINDOW`)
- Optional launch at login
- Dark mode via semantic system colors

## App icon

The icon is a **calendar with a countdown clock inside** (red header, blue clock face, gold countdown arc). Assets live in `EventCountdown/Assets.xcassets/AppIcon.appiconset`.

Regenerate all sizes:

```bash
swift scripts/GenerateAppIcon.swift EventCountdown/Assets.xcassets/AppIcon.appiconset
```

## Debug testing

The Debug configuration defines `DEBUG_SHORT_ACK_WINDOW`, which shortens the acknowledgment window to 5 minutes and reminder interval to 1 minute.

## Countdown units

Fixed durations: 1 year = 365 days, 1 month = 30 days, 1 week = 7 days.
