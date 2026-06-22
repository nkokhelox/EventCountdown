import SwiftUI

struct EmojiRulesEditor: View {
    @Bindable var store: EmojiMappingStore
    @State private var newMatchKind: EmojiRule.MatchKind = .titleContains
    @State private var newMatchValue = ""
    @State private var newEmoji = "🎂"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use exact title for important events. First matching rule wins.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(store.rules) { rule in
                    HStack {
                        Text(rule.emoji)
                        VStack(alignment: .leading) {
                            Text(rule.matchKind.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(rule.matchValue)
                        }
                        Spacer()
                        Text("#\(rule.priority)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        store.deleteRule(id: store.rules[index].id)
                    }
                }
                .onMove(perform: store.moveRules)
            }
            .frame(minHeight: 160)

            HStack {
                Picker("Match", selection: $newMatchKind) {
                    ForEach(EmojiRule.MatchKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .frame(width: 160)
                TextField("Match value", text: $newMatchValue)
                TextField("Emoji", text: $newEmoji)
                    .frame(width: 50)
                Button("Add") {
                    let rule = EmojiRule(
                        matchKind: newMatchKind,
                        matchValue: newMatchValue,
                        emoji: newEmoji,
                        priority: store.rules.count
                    )
                    store.addRule(rule)
                    newMatchValue = ""
                }
                .disabled(newMatchValue.isEmpty || newEmoji.isEmpty)
            }

            if !newMatchValue.isEmpty {
                let matches = store.matchingRules(for: newMatchValue, calendarName: newMatchValue)
                if matches.count > 1 {
                    Text("Warning: \(matches.count) existing rules may also match.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
