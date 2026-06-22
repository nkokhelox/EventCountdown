import Foundation

struct EmojiRule: Codable, Identifiable, Hashable, Sendable {
    enum MatchKind: String, Codable, CaseIterable, Identifiable {
        case exactTitle
        case titleContains
        case calendarName

        var id: String { rawValue }

        var label: String {
            switch self {
            case .exactTitle: return "Exact title"
            case .titleContains: return "Title contains"
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
        case .calendarName:
            return event.calendarTitle.localizedCaseInsensitiveContains(matchValue)
        }
    }
}
