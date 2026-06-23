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
        return "\(value)\(unit.compactLabel(for: value))"
    }
}

enum CountdownFormatter {
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

    static func format(remaining interval: TimeInterval, now: Date = Date()) -> CountdownValue {
        format(remaining: interval)
    }

    static func format(remaining interval: TimeInterval) -> CountdownValue {
        if interval <= 0 {
            return CountdownValue(value: 0, unit: .seconds, isPast: true)
        }

        if interval > twoYears {
            return CountdownValue(value: max(1, Int(interval / year)), unit: .years, isPast: false)
        }
        if interval > threeMonths {
            return CountdownValue(value: max(1, Int(interval / month)), unit: .months, isPast: false)
        }
        if interval > twoWeeks {
            return CountdownValue(value: max(1, Int(interval / week)), unit: .weeks, isPast: false)
        }
        if interval > twoDays {
            return CountdownValue(value: max(1, Int(interval / day)), unit: .days, isPast: false)
        }
        if interval >= oneHour {
            return CountdownValue(value: max(1, Int(interval / hour)), unit: .hours, isPast: false)
        }
        if interval > oneMinute {
            return CountdownValue(value: max(1, Int(interval / minute)), unit: .minutes, isPast: false)
        }
        return CountdownValue(value: max(1, Int(interval)), unit: .seconds, isPast: false)
    }

    static func remaining(until date: Date, now: Date = Date()) -> TimeInterval {
        date.timeIntervalSince(now)
    }

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
