import Foundation

enum CountdownUnit: String, CaseIterable {
    case years
    case months
    case weeks
    case days
    case hours
    case minutes
    case seconds

    func fullLabel(for value: Int) -> String {
        let plural = value != 1
        switch self {
        case .years: return plural ? "years" : "year"
        case .months: return plural ? "months" : "month"
        case .weeks: return plural ? "weeks" : "week"
        case .days: return plural ? "days" : "day"
        case .hours: return plural ? "hours" : "hour"
        case .minutes: return plural ? "minutes" : "minute"
        case .seconds: return plural ? "seconds" : "second"
        }
    }

    func compactLabel(for value: Int) -> String {
        let plural = value != 1
        switch self {
        case .years: return plural ? "years" : "year"
        case .months: return plural ? "mons" : "mon"
        case .weeks: return plural ? "weeks" : "week"
        case .days: return plural ? "days" : "day"
        case .hours: return plural ? "hours" : "hour"
        case .minutes: return plural ? "mins" : "min"
        case .seconds: return plural ? "secs" : "sec"
        }
    }

    // Single letter for the tightest labels. Months and minutes deliberately share "m" —
    // the two never appear in the same reading, since only one unit is ever shown.
    var letter: String {
        switch self {
        case .years: return "y"
        case .months: return "m"
        case .weeks: return "w"
        case .days: return "d"
        case .hours: return "h"
        case .minutes: return "m"
        case .seconds: return "s"
        }
    }
}

struct CountdownValue: Equatable, Sendable {
    let value: Int
    let unit: CountdownUnit
    let isPast: Bool

    var compactText: String {
        if isPast { return "now" }
        return "\(value) \(unit.fullLabel(for: value))"
    }

    var listText: String {
        if isPast { return "now" }
        return "\(value) \(unit.fullLabel(for: value))"
    }

    var menuBarText: String {
        if isPast { return "now" }
        return "\(value) \(unit.compactLabel(for: value))"
    }
}

enum CountdownFormatter {
    // Menu bar label for an event that has already started: "now" for the first
    // ackNowDisplaySeconds, then "ongoing" for the remainder of the window.
    static func ongoingLabel(elapsedSinceStart: TimeInterval) -> String {
        if elapsedSinceStart < AppConstants.ackNowDisplaySeconds {
            return "Now"
        }
        return "Ongoing"
    }
    // Gregorian mean year (365 + 1/4 - 1/100 + 1/400 days) so the year length accounts for
    // leap years rather than assuming a flat 365 days.
    private static let year: TimeInterval = 365.2425 * 24 * 60 * 60
    private static let month: TimeInterval = 30 * 24 * 60 * 60
    private static let week: TimeInterval = 7 * 24 * 60 * 60
    private static let day: TimeInterval = 24 * 60 * 60
    private static let hour: TimeInterval = 60 * 60
    private static let minute: TimeInterval = 60
    // A unit hands off to the next-smaller one before its value would reach 1.0, so the
    // countdown never shows "1 <unit>" (e.g. 1 hour is shown as 60 minutes). Seconds are
    // the exception and count all the way down to 0.
    private static let unitSwitchFactor: Double = 1.1
    private static let twoYears = 2 * year
    private static let threeMonths = 3 * month
    private static let twoWeeks = 2 * week
    private static let twoDays = 2 * day
    private static let oneHour = hour
    private static let oneMinute = minute

    static func format(remaining interval: TimeInterval) -> CountdownValue {
        if interval <= 0 {
            return CountdownValue(value: 0, unit: .seconds, isPast: true)
        }

        func amount(_ unit: TimeInterval) -> Int {
            max(1, Int((interval / unit).rounded(.down)))
        }

        if interval > twoYears {
            return CountdownValue(value: amount(year), unit: .years, isPast: false)
        }
        if interval > threeMonths {
            return CountdownValue(value: amount(month), unit: .months, isPast: false)
        }
        if interval > twoWeeks {
            return CountdownValue(value: amount(week), unit: .weeks, isPast: false)
        }
        if interval > twoDays {
            return CountdownValue(value: amount(day), unit: .days, isPast: false)
        }
        if interval >= oneHour {
            return CountdownValue(value: amount(hour), unit: .hours, isPast: false)
        }
        if interval > oneMinute {
            return CountdownValue(value: amount(minute), unit: .minutes, isPast: false)
        }
        return CountdownValue(value: amount(1), unit: .seconds, isPast: false)
    }

    // Menu bar countdown as a single unit, e.g. "5 hrs", "1.5 hrs", "45 secs". The largest
    // fitting unit is shown whole for two or more of it, and with one decimal for its final
    // 1.1–1.9 stretch; below that it has already handed off to the next-smaller unit, so
    // "1 <unit>" never appears. Seconds are the exception and count whole down to 0.
    static func menuBarDecimalText(remaining interval: TimeInterval) -> String {
        if interval <= 0 { return "Now" }

        let (unit, unitSeconds) = menuBarUnit(for: interval)

        if unit == .seconds {
            // Whole seconds, rounded up so each value shows for a full second.
            let seconds = Int(interval.rounded(.up))
            return "\(seconds) \(CountdownUnit.seconds.compactLabel(for: seconds))".capitalized
        }

        // Truncated so the value never overstates the true remaining time.
        let raw = interval / unitSeconds
        if raw >= 2 {
            let whole = Int(raw.rounded(.down))
            return "\(whole) \(unit.compactLabel(for: whole))".capitalized
        }
        // Final stretch: raw is in [1.1, 2), always shown with one decimal (never "1.0").
        let value = max(1.1, (raw * 10).rounded(.down) / 10)
        return "\(String(format: "%.1f", value)) \(unit.compactLabel(for: 2))".capitalized
    }

    private static func menuBarUnit(for interval: TimeInterval) -> (CountdownUnit, TimeInterval) {
        // Switch to the next-smaller unit before this one's value would reach 1.0, so its
        // final displayed stretch is 1.1–1.9 (a decimal) and "1 <unit>" is never shown.
        if interval >= unitSwitchFactor * year { return (.years, year) }
        if interval >= unitSwitchFactor * month { return (.months, month) }
        if interval >= unitSwitchFactor * week { return (.weeks, week) }
        if interval >= unitSwitchFactor * day { return (.days, day) }
        if interval >= unitSwitchFactor * hour { return (.hours, hour) }
        if interval >= unitSwitchFactor * minute { return (.minutes, minute) }
        return (.seconds, 1)
    }

    // Seconds-per-unit of the unit the menu-bar decimal label uses at `interval`.
    // Exposed so CountdownSchedule can size its update cadence to 0.1 of this unit
    // using the exact same thresholds as -menuBarDecimalText, so the two never drift.
    static func menuBarUnitSeconds(for interval: TimeInterval) -> TimeInterval {
        menuBarUnit(for: interval).1
    }

    static func remaining(until date: Date, now: Date = Date()) -> TimeInterval {
        date.timeIntervalSince(now)
    }

    // Length of an event, e.g. "45 mins", "1 hr 30 mins", "2 days 3 hrs". Zero units are
    // dropped; a zero-length span reads "0 mins".
    static func durationText(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) \(days == 1 ? "day" : "days")") }
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hr" : "hrs")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "min" : "mins")") }
        return parts.isEmpty ? "0 mins" : parts.joined(separator: " ")
    }

    // Event length on the same single-unit decimal scale the menu bar uses, with the unit as
    // one letter and no space, e.g. "45m", "1.5h", "2d". Sharing menuBarUnit keeps the two
    // from drifting apart, which also means "1 <unit>" never appears — a one-hour event reads
    // "60m", the same handoff the menu bar makes.
    static func compactDurationText(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }

        let (unit, unitSeconds) = menuBarUnit(for: interval)
        if unit == .seconds {
            return "\(Int(interval.rounded(.up)))\(unit.letter)"
        }

        // Truncated rather than rounded so the label never overstates the length.
        let raw = interval / unitSeconds
        if raw >= 2 {
            return "\(Int(raw.rounded(.down)))\(unit.letter)"
        }
        let value = max(1.1, (raw * 10).rounded(.down) / 10)
        return "\(String(format: "%.1f", value))\(unit.letter)"
    }

    static func agoText(elapsed interval: TimeInterval) -> String {
        if interval <= 0 { return "now" }
        // Single most-significant unit, e.g. "1 hour ago".
        return "\(format(remaining: interval).listText) ago"
    }

    // Event-list countdown: the two most significant non-zero units, e.g.
    // "1 year 3 months" or "2 days 3 hours". Smaller units are omitted.
    static func fullRemainingListText(remaining interval: TimeInterval) -> String {
        if interval <= 0 { return "now" }

        var seconds = Int(interval)
        var parts: [String] = []
        let units: [(Int, CountdownUnit)] = [
            (Int(year), .years),
            (Int(month), .months),
            (Int(week), .weeks),
            (Int(day), .days),
            (Int(hour), .hours),
            (Int(minute), .minutes),
            (1, .seconds),
        ]

        for (unitSeconds, unit) in units where parts.count < 2 {
            let count = seconds / unitSeconds
            if count > 0 {
                parts.append("\(count) \(unit.fullLabel(for: count))")
                seconds %= unitSeconds
            }
        }

        if parts.isEmpty {
            return "0 seconds"
        }
        return parts.joined(separator: " ")
    }
}
