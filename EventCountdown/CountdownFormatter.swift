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
        case .years: return plural ? "yrs" : "yr"
        case .months: return plural ? "mos" : "mo"
        case .weeks: return plural ? "wks" : "wk"
        case .days: return "d"
        case .hours: return plural ? "hrs" : "hr"
        case .minutes: return plural ? "mins" : "min"
        case .seconds: return plural ? "secs" : "sec"
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
            return "now"
        }
        return "ongoing"
    }
    private static let year: TimeInterval = 365 * 24 * 60 * 60
    private static let month: TimeInterval = 30 * 24 * 60 * 60
    private static let week: TimeInterval = 7 * 24 * 60 * 60
    private static let day: TimeInterval = 24 * 60 * 60
    private static let hour: TimeInterval = 60 * 60
    private static let minute: TimeInterval = 60
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

    // Menu bar countdown as a single unit with one decimal place, e.g. 1h30m -> "1.5 hrs".
    // The whole part is kept without a trailing ".0" (2h -> "2 hrs").
    static func menuBarDecimalText(remaining interval: TimeInterval) -> String {
        if interval <= 0 { return "now" }
        // Under a minute: whole seconds, rounded up so each value shows for exactly
        // one second and the countdown reaches the event (0 -> "now") on time.
        if interval < 60 {
            let seconds = Int(interval.rounded(.up))
            if seconds < 60 {
                return "\(seconds) \(CountdownUnit.seconds.compactLabel(for: seconds))"
            }
            // interval is in (59, 60): show "1 min" rather than "60 sec".
            return "1 \(CountdownUnit.minutes.compactLabel(for: 1))"
        }
        // A minute or more: the largest fitting unit with one decimal, truncated so
        // the value never overstates the true remaining time (no phantom extra minute).
        let (unit, unitSeconds) = menuBarUnit(for: interval)
        let value = max(0.1, (interval / unitSeconds * 10).rounded(.down) / 10)
        let number = value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
        return "\(number) \(unit.compactLabel(for: value == 1 ? 1 : 2))"
    }

    private static func menuBarUnit(for interval: TimeInterval) -> (CountdownUnit, TimeInterval) {
        if interval > twoYears { return (.years, year) }
        if interval > threeMonths { return (.months, month) }
        if interval > twoWeeks { return (.weeks, week) }
        if interval > twoDays { return (.days, day) }
        if interval >= oneHour { return (.hours, hour) }
        if interval >= oneMinute { return (.minutes, minute) }
        return (.seconds, 1)
    }

    static func remaining(until date: Date, now: Date = Date()) -> TimeInterval {
        date.timeIntervalSince(now)
    }

    static func agoText(elapsed interval: TimeInterval) -> String {
        if interval <= 0 { return "now" }
        return "\(fullRemainingListText(remaining: interval)) ago"
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
