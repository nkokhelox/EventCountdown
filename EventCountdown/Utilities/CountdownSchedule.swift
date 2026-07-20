import Foundation

// Computes *when* the menu-bar countdown label will next change, so the app can arm a
// single precise timer to that instant instead of polling every second. The cadence is
// derived from what CountdownFormatter.menuBarDecimalText actually displays:
//
//   - under a minute: whole seconds -> re-check on the next whole-second boundary
//   - a minute or more: one decimal of the largest fitting unit -> re-check every 0.1
//     of that unit (i.e. ~10 updates per major unit: days every 2.4h, hours every 6min…)
//   - started events: "Now" for the first ackNowDisplaySeconds, then "Ongoing" until end
//
// Everything is re-derived on each call, so unit-threshold crossings (e.g. days -> hours)
// need no special-casing: the caller re-arms on every fire and this recomputes.
enum CountdownSchedule {
    // Smallest timer interval we will schedule, to avoid a busy loop when `now` sits a
    // hair above a boundary.
    private static let minInterval: TimeInterval = 0.05

    // The steady spacing between menu-bar label updates (the "refresh rate"), or nil when
    // updates aren't periodic right now: no event, an event about to start, or an ongoing
    // event whose label only changes at its Now->Ongoing flip and at its end.
    static func updateCadence(now: Date, startDate: Date?, endDate: Date?, hasStarted: Bool) -> TimeInterval? {
        guard let startDate, !hasStarted else { return nil }
        let remaining = startDate.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return menuBarStep(remaining: remaining)
    }

    // The spacing between menu-bar label changes at `remaining`: whole seconds under a
    // minute, whole minutes in the minutes range (no fractional countdown), otherwise 0.1
    // of the current unit. Shared by nextChange and updateCadence so they never drift.
    private static func menuBarStep(remaining: TimeInterval) -> TimeInterval {
        if remaining < 60 { return 1 }
        let unitSeconds = CountdownFormatter.menuBarUnitSeconds(for: remaining)
        let raw = remaining / unitSeconds
        // Whole-unit cadence while showing whole numbers (>= 2 of the unit); the finer
        // 0.1-unit cadence only in the final "1.x" window that shows a decimal.
        return raw >= 2 ? unitSeconds : unitSeconds / 10
    }

    static func nextChange(now: Date, startDate: Date?, endDate: Date?, hasStarted: Bool) -> Date {
        // No event to count down: no timer. A calendar change or the periodic refresh
        // repopulates the menu bar and re-arms the clock.
        guard let startDate else { return .distantFuture }

        if hasStarted {
            // "Now" until start + ackNowDisplaySeconds, then "Ongoing" (static) until the
            // event ends and falls out of the menu bar's "now" set.
            let nowMark = startDate.addingTimeInterval(AppConstants.ackNowDisplaySeconds)
            if now < nowMark { return nowMark }
            return endDate ?? nowMark
        }

        let remaining = startDate.timeIntervalSince(now)
        // At/after start: about to flip to "Now"; re-check almost immediately.
        if remaining <= 0 { return now.addingTimeInterval(0.2) }

        // Re-arm at the next boundary of the current step: whole seconds under a minute,
        // whole minutes in the minutes range, otherwise the next 0.1 of the unit.
        let step = menuBarStep(remaining: remaining)
        let remainder = remaining.truncatingRemainder(dividingBy: step)
        let delta = remainder <= 0.001 ? step : remainder
        return now.addingTimeInterval(max(minInterval, delta))
    }
}
