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
    static func menuBarAcknowledgmentLabel(elapsedSinceStart: TimeInterval) -> String {
        if elapsedSinceStart < AppConstants.ackNowDisplaySeconds {
            return "now"
        }
        return "Late"
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

    static func format(remaining interval: TimeInterval, roundUp: Bool = false) -> CountdownValue {
        if interval <= 0 {
            return CountdownValue(value: 0, unit: .seconds, isPast: true)
        }

        func amount(_ unit: TimeInterval) -> Int {
            let raw = interval / unit
            return max(1, Int(roundUp ? raw.rounded(.up) : raw.rounded(.down)))
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

    static func remaining(until date: Date, now: Date = Date()) -> TimeInterval {
        date.timeIntervalSince(now)
    }

    static func agoText(elapsed interval: TimeInterval, roundUp: Bool = false) -> String {
        if interval <= 0 { return "now" }
        return "\(format(remaining: interval, roundUp: roundUp).menuBarText) ago"
    }

    static func fullRemainingListText(remaining interval: TimeInterval, roundUp: Bool = false) -> String {
        if interval <= 0 { return "now" }

        var seconds = roundUp ? Int((interval / minute).rounded(.up)) * Int(minute) : Int(interval)
        var parts: [String] = []
        let units: [(Int, CountdownUnit)] = [
            (Int(year), .years),
            (Int(month), .months),
            (Int(week), .weeks),
            (Int(day), .days),
            (Int(hour), .hours),
            (Int(minute), .minutes),
        ]

        for (unitSeconds, unit) in units {
            let count = seconds / unitSeconds
            if count > 0 {
                parts.append("\(count) \(unit.fullLabel(for: count))")
                seconds %= unitSeconds
            }
        }

        if parts.isEmpty {
            return "1 minute"
        }
        return parts.joined(separator: " ")
    }
}
