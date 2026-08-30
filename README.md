# EventCountdown

Native macOS menu bar app ("Events Countdown") that shows a smart, adaptive countdown to
your next calendar event, with a full event browser panel, quick event creation, and
per-event emoji.

## Requirements

- macOS 14.0 or later
- Xcode 15+

## Open and run

```bash
open /Users/nkokhelo/PISD_PROJECTS/EventCountdown/EventCountdown.xcodeproj
```

1. Select the **EventCountdown** scheme
2. Press **Cmd+R** to build and run
3. Grant **Calendar** access when prompted

The app lives in the menu bar only (no Dock icon). Click the menu bar item to open the
panel; **Settings…** and **Quit** are in the footer.

## Features

### Menu bar

- Live countdown text (e.g. `🎯 in 45 mins`) that switches to an ongoing label — `Now` /
  `Late` for timed events, `All day` for all-day events — once the event starts
- An emoji prefix resolved per event (see Emoji rules below), falling back to the app
  icon as the leading mark
- Adaptive refresh cadence: updates every second near a transition, and far less often
  for a distant event (see the **Menu bar refresh** settings group for live diagnostics)
- Hover tooltip with the event title and its start/end time
- A "0 events" empty state (with its own tooltip) when no events are found

### Dropdown panel

- A full month calendar for browsing any day — days with events are dot-marked, today is
  outlined, the selected day is filled. Picking a non-today day shows just that day's
  events; today shows the live sections below instead
- **Past** — the most recently-ended event, shown for a configurable window (or turned off)
- **All Day** — today's all-day events, kept separate from timed events
- **Now** — events currently in progress, faintly highlighted, with "ends in …"
- **Next** — the soonest upcoming event(s) (simultaneous starts all show together, tinted
  more strongly), folded out of Upcoming once its start falls inside a configurable window
- **Upcoming** — the rest of the events, grouped by day; each day group is collapsible and
  a configurable number of days start expanded
- Each row shows an emoji/app-icon glyph, the title, a color dot per source calendar (or a
  merge icon once an event spans more than 3 calendars), map/call quick-link buttons
  auto-detected from the location, notes, or event URL (Zoom, Meet, Teams, Webex, `tel:`,
  FaceTime, and more), the start time + duration, and a live countdown/elapsed label
- Click a row (single-click, double-click, or never — configurable) to open Calendar.app
  to that event
- **Add Event** popover — title, inline date + time pickers, a duration stepper, and a
  destination calendar picker; writes straight to EventKit
- Events that appear on more than one calendar are merged into a single row

### Settings window

- **Calendars** — choose which calendars feed the countdown and panel
- **Emoji** — custom rules matched by "title contains" or calendar name, reorderable by
  drag; resolution order is title emoji → matching rule → inferred/keyword emoji →
  calendar emoji → app icon
- **About** — launch at login, "Open Calendar on" click mode, "Show past event for"
  window, "Days expanded in Upcoming", "Move to Next section" window, live menu bar
  refresh diagnostics, app version, and the fixed countdown-unit facts below

### Other

- Optional launch at login
- Dark mode via semantic system colors

## App icon

The icon is a **calendar with a countdown clock inside** (red header, blue clock face, gold countdown arc). Assets live in `EventCountdown/Assets.xcassets/AppIcon.appiconset`.

Regenerate all sizes:

```bash
swift scripts/GenerateAppIcon.swift EventCountdown/Assets.xcassets/AppIcon.appiconset
```

## Testing

`EventCountdownTests` unit-tests `CountdownFormatter`, `CountdownSchedule`,
`EventCallLink`, `EventKey`, `EventMerger`, `EventTitleEmoji`, and `EmojiRule`:

```bash
xcodebuild -project EventCountdown.xcodeproj -scheme EventCountdown -destination 'platform=macOS' test
```

A GitHub Actions workflow (`.github/workflows/tests.yml`) runs the same suite on every
push to `main` and on every pull request.

## Countdown units

Fixed durations: 1 year = 365 days, 1 month = 30 days, 1 week = 7 days.
