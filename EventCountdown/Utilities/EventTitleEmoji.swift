import Foundation

enum EventTitleEmoji {
    static func resolvedEmoji(for title: String, mappedEmoji: String) -> String {
        title.leadingEmojiAndRemainder()?.emoji ?? mappedEmoji
    }

    static func labeledTitle(fullTitle: String, mappedEmoji: String) -> String {
        if let (emoji, remainder) = fullTitle.leadingEmojiAndRemainder() {
            return remainder.isEmpty ? emoji : "\(emoji) \(remainder)"
        }
        return "\(mappedEmoji) \(fullTitle)"
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
