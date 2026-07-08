import Foundation

enum EventTitleEmoji {
    static func leadingEmoji(in text: String) -> String? {
        text.leadingEmojiAndRemainder()?.emoji
    }

    static func resolve(
        for event: CalendarEvent,
        titleRuleEmoji: String?,
        calendarRuleEmoji: String?
    ) -> EventEmojiResolution {
        if let titleEmoji = leadingEmoji(in: event.title) {
            return EventEmojiResolution(character: titleEmoji)
        }
        if let titleRuleEmoji {
            return EventEmojiResolution(character: titleRuleEmoji)
        }
        if let inferred = inferredEmoji(forTitle: event.title) {
            return EventEmojiResolution(character: inferred)
        }
        if let searched = EmojiNameSearch.firstEmoji(matchingName: event.title) {
            return EventEmojiResolution(character: searched)
        }
        if let calendarRuleEmoji {
            return EventEmojiResolution(character: calendarRuleEmoji)
        }
        if let calendarEmoji = leadingEmoji(in: event.calendarTitle) {
            return EventEmojiResolution(character: calendarEmoji)
        }
        return EventEmojiResolution(character: "🗓️")
    }

    static func firstWord(of title: String) -> String? {
        guard let raw = title.split(separator: " ").first else { return nil }
        let word = String(raw).filter(\.isLetter).lowercased()
        return word.isEmpty ? nil : word
    }

    static func inferredEmoji(forTitle title: String) -> String? {
        guard let word = firstWord(of: title) else { return nil }
        for (keywords, emoji) in keywordEmojiMap {
            for keyword in keywords {
                let normalized = keyword.filter(\.isLetter).lowercased()
                if !normalized.isEmpty, normalized == word {
                    return emoji
                }
            }
        }
        return nil
    }

    private static let keywordEmojiMap: [([String], String)] = [
        (["birthday", "bday", "hbd"], "🎂"),
        (["wedding"], "💒"),
        (["anniversary"], "💞"),
        (["flight", "airport", "boarding"], "✈️"),
        (["travel", "trip", "commute"], "🧳"),
        (["hotel", "check-in", "checkin"], "🏨"),
        (["coffee", "espresso", "latte"], "☕"),
        (["breakfast"], "🥐"),
        (["lunch"], "🍽️"),
        (["dinner", "supper"], "🍽️"),
        (["drinks", "beer", "happy hour"], "🍻"),
        (["gym", "workout", "training", "yoga", "pilates", "run"], "🏋️"),
        (["doctor", "dentist", "clinic", "appointment", "checkup"], "🩺"),
        (["interview"], "💼"),
        (["1:1", "one-on-one", "1-1"], "🧑‍🤝‍🧑"),
        (["standup", "stand-up", "scrum", "sync", "sprint"], "🗣️"),
        (["meeting", "meet", "catchup", "catch-up", "review", "retro"], "👥"),
        (["call", "phone"], "📞"),
        (["demo"], "🖥️"),
        (["release", "launch", "deploy"], "🚀"),
        (["deadline", "due"], "⏰"),
        (["party", "celebration"], "🎉"),
        (["holiday", "vacation", "pto", "leave"], "🏖️"),
        (["class", "lecture", "study", "exam", "lesson", "course"], "📚"),
        (["movie", "cinema", "film"], "🎬"),
        (["concert", "gig", "show"], "🎵"),
        (["game", "match", "soccer", "football", "basketball"], "🏆"),
        (["pay", "payday", "salary", "invoice", "bill", "rent"], "💰"),
        (["shopping", "groceries"], "🛒"),
        (["email", "mail"], "✉️"),
    ]

    static func titleWithoutLeadingEmoji(_ fullTitle: String) -> String {
        guard let (_, remainder) = fullTitle.leadingEmojiAndRemainder(), !remainder.isEmpty else {
            return fullTitle
        }
        return remainder
    }

    static func labeledTitle(fullTitle: String, resolution: EventEmojiResolution) -> String {
        if let (emoji, remainder) = fullTitle.leadingEmojiAndRemainder() {
            return remainder.isEmpty ? emoji : "\(emoji) \(remainder)"
        }
        if resolution.usesAppIcon {
            return fullTitle
        }
        return "\(resolution.character!) \(fullTitle)"
    }
}

private extension String {
    func leadingEmojiAndRemainder() -> (emoji: String, remainder: String)? {
        var index = startIndex
        while index < endIndex, self[index].isWhitespace {
            index = self.index(after: index)
        }
        guard index < endIndex else { return nil }

        let first = self[index]
        guard first.isEmojiCharacter else { return nil }

        let emojiEnd = self.index(after: index)
        let emoji = String(self[index..<emojiEnd])

        var remainderIndex = emojiEnd
        while remainderIndex < endIndex, self[remainderIndex].isWhitespace {
            remainderIndex = self.index(after: remainderIndex)
        }

        return (emoji, String(self[remainderIndex..<endIndex]))
    }
}

private extension Character {
    var isEmojiCharacter: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }
}

enum EmojiNameSearch {
    static func firstEmoji(matchingName name: String) -> String? {
        guard let firstWord = EventTitleEmoji.firstWord(of: name),
              firstWord.count >= 3,
              !stopWords.contains(firstWord)
        else {
            return nil
        }

        return index.first(where: { matches(nameTokens: $0.tokens, term: firstWord) })?.emoji
    }

    private struct Entry {
        let emoji: String
        let tokens: [String]
    }

    private static func matches(nameTokens: [String], term: String) -> Bool {
        for token in nameTokens {
            if token == term { return true }
            if token.commonPrefix(with: term).count >= 4 { return true }
        }
        return false
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "out", "off", "our", "your",
        "this", "that", "are", "was", "will", "you", "get", "let", "new"
    ]

    private static let index: [Entry] = buildIndex()

    private static func buildIndex() -> [Entry] {
        // Emoticons first so generic words like "smile" resolve to a face.
        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F, // Emoticons
            0x1F300...0x1F5FF, // Misc Symbols and Pictographs
            0x1F680...0x1F6FF, // Transport and Map
            0x1F900...0x1F9FF, // Supplemental Symbols and Pictographs
            0x1FA70...0x1FAFF, // Symbols and Pictographs Extended-A
            0x2600...0x26FF,   // Misc symbols
            0x2700...0x27BF    // Dingbats
        ]

        var entries: [Entry] = []
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let props = scalar.properties
                guard props.isEmoji, props.isEmojiPresentation, let rawName = props.name, !rawName.isEmpty else {
                    continue
                }
                let tokens = rawName.lowercased().split(separator: " ").map(String.init)
                entries.append(Entry(emoji: String(scalar), tokens: tokens))
            }
        }
        return entries
    }
}
