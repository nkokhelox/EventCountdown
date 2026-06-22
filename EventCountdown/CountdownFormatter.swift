import Foundation

enum CountdownUnit: String, CaseIterable {
    case years
    case months
    case weeks
    case days
    case hours
    case minutes
    case seconds

    var compactSuffix: String {
        switch self {
        case .years: return "yr"
        case .months: return "mo"
        case .weeks: return "wk"
        case .days: return "d"
        case .hours: return "hr"
        case .minutes: return "min"
        case .seconds: return "sec"
        }
    }
}

struct CountdownValue: Equatable, Sendable {
    let value: Int
    let unit: CountdownUnit
    let isPast: Bool

    var compactText: String {
        if isPast { return "now" }
        return "\(value)\(unit.compactSuffix)"
    }

    var listText: String {
        if isPast { return "now" }
        let label = value == 1 ? String(unit.compactSuffix.dropLast()) : unit.compactSuffix
        return "\(value) \(label)"
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
    private static let twoHours = 2 * hour
    private static let oneMinute = minute

    static func format(remaining interval: TimeInterval, now: Date = Date()) -> CountdownValue {
        format(remaining: interval)
    }

    static func format(remaining interval: TimeInterval) -> CountdownValue {
        if interval <= 0 {
            return CountdownValue(value: 0, unit: .seconds, isPast: true)
        }

        if interval > twoYears {
            return CountdownValue(value: max(1, Int(ceil(interval / year))), unit: .years, isPast: false)
        }
        if interval > threeMonths {
            return CountdownValue(value: max(1, Int(ceil(interval / month))), unit: .months, isPast: false)
        }
        if interval > twoWeeks {
            return CountdownValue(value: max(1, Int(ceil(interval / week))), unit: .weeks, isPast: false)
        }
        if interval > twoDays {
            return CountdownValue(value: max(1, Int(ceil(interval / day))), unit: .days, isPast: false)
        }
        if interval > twoHours {
            return CountdownValue(value: max(1, Int(ceil(interval / hour))), unit: .hours, isPast: false)
        }
        if interval > oneMinute {
            return CountdownValue(value: max(1, Int(ceil(interval / minute))), unit: .minutes, isPast: false)
        }
        return CountdownValue(value: max(1, Int(ceil(interval))), unit: .seconds, isPast: false)
    }

    static func remaining(until date: Date, now: Date = Date()) -> TimeInterval {
        date.timeIntervalSince(now)
    }
}
