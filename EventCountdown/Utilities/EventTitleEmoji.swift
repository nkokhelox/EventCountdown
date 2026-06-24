import Foundation

enum EventTitleEmoji {
    static func leadingEmoji(in text: String) -> String? {
        text.leadingEmojiAndRemainder()?.emoji
    }

    static func resolve(for event: CalendarEvent, ruleEmoji: String?) -> EventEmojiResolution {
        if let titleEmoji = leadingEmoji(in: event.title) {
            return EventEmojiResolution(character: titleEmoji)
        }
        if let ruleEmoji {
            return EventEmojiResolution(character: ruleEmoji)
        }
        if let calendarEmoji = leadingEmoji(in: event.calendarTitle) {
            return EventEmojiResolution(character: calendarEmoji)
        }
        return .appIcon
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
