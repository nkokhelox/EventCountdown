import Foundation

struct EmojiRule: Codable, Identifiable, Hashable, Sendable {
    enum MatchKind: String, Codable, CaseIterable, Identifiable {
        case exactTitle
        case titleContains
        case titleStartsWith
        case titleEndsWith
        case calendarName

        var id: String { rawValue }

        var label: String {
            switch self {
            case .exactTitle: return "Exact title"
            case .titleContains: return "Title contains"
            case .titleStartsWith: return "Title starts with"
            case .titleEndsWith: return "Title ends with"
            case .calendarName: return "Calendar name"
            }
        }
    }

    var id: UUID
    var matchKind: MatchKind
    var matchValue: String
    var emoji: String
    var priority: Int

    init(
        id: UUID = UUID(),
        matchKind: MatchKind,
        matchValue: String,
        emoji: String,
        priority: Int
    ) {
        self.id = id
        self.matchKind = matchKind
        self.matchValue = matchValue
        self.emoji = emoji
        self.priority = priority
    }

    func matches(event: CalendarEvent) -> Bool {
        switch matchKind {
        case .exactTitle:
            return event.title == matchValue
        case .titleContains:
            return event.title.localizedCaseInsensitiveContains(matchValue)
        case .titleStartsWith:
            return event.title.localizedCaseInsensitiveHasPrefix(matchValue)
        case .titleEndsWith:
            return event.title.localizedCaseInsensitiveHasSuffix(matchValue)
        case .calendarName:
            return event.calendarTitle.localizedCaseInsensitiveContains(matchValue)
        }
    }
}

private extension String {
    func localizedCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
    }

    func localizedCaseInsensitiveHasSuffix(_ suffix: String) -> Bool {
        range(of: suffix, options: [.anchored, .backwards, .caseInsensitive]) != nil
    }
}
