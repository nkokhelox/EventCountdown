import Foundation
import Observation

@Observable
final class EmojiMappingStore {
    private(set) var rules: [EmojiRule] = []

    init() {
        load()
    }

    func load() {
        guard
            let data = UserDefaults.standard.data(forKey: AppConstants.emojiRulesKey),
            let decoded = try? JSONDecoder().decode([EmojiRule].self, from: data)
        else {
            rules = []
            return
        }
        rules = decoded.sorted { $0.priority < $1.priority }
    }

    func save() {
        let data = try? JSONEncoder().encode(rules)
        UserDefaults.standard.set(data, forKey: AppConstants.emojiRulesKey)
    }

    func addRule(_ rule: EmojiRule) {
        rules.append(rule)
        rules.sort { $0.priority < $1.priority }
        save()
    }

    func updateRule(_ rule: EmojiRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        rules.sort { $0.priority < $1.priority }
        save()
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        for index in rules.indices {
            rules[index].priority = index
        }
        save()
    }

    func ruleEmoji(for event: CalendarEvent) -> String? {
        for rule in rules.sorted(by: { $0.priority < $1.priority }) where rule.matches(event: event) {
            return rule.emoji
        }
        return nil
    }

    func matchingRules(for sampleTitle: String, calendarName: String) -> [EmojiRule] {
        let sample = CalendarEvent(
            from: SampleEvent(title: sampleTitle, calendarTitle: calendarName)
        )
        return rules.filter { $0.matches(event: sample) }
    }
}

private struct SampleEvent {
    let title: String
    let calendarTitle: String
}

private extension CalendarEvent {
    init(from sample: SampleEvent) {
        self.id = UUID().uuidString
        self.eventIdentifier = UUID().uuidString
        self.title = sample.title
        self.startDate = Date()
        self.endDate = Date()
        self.isAllDay = false
        self.location = nil
        self.notes = nil
        self.url = nil
        self.calendarTitle = sample.calendarTitle
        self.calendarID = UUID().uuidString
        self.calendarColor = .accentColor
    }
}
