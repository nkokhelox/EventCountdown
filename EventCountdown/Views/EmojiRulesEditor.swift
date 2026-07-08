import SwiftUI

struct EmojiRulesEditor: View {
    @Bindable var store: EmojiMappingStore
    @State private var newMatchKind: EmojiRule.MatchKind = .titleContains
    @State private var newMatchValue = ""
    @State private var newEmoji = ""
    @State private var emojiShake: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Emoji priority: title emoji, then first matching rule, then calendar emoji, then app icon. Drag rules to reorder.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                if store.rules.isEmpty {
                    Text("No emoji rules yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.rules) { rule in
                    HStack(spacing: 10) {
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
                        Button {
                            store.deleteRule(id: rule.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete rule")
                        .accessibilityLabel("Delete rule")
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
                    .modifier(ShakeEffect(animatableData: emojiShake))
                    .onChange(of: newEmoji) { _, value in
                        // Accept a single emoji only: keep the first emoji character
                        // and ignore anything extra or non-emoji, shaking to signal it.
                        let allowed = value.first.flatMap { $0.isEmoji ? String($0) : nil } ?? ""
                        if value != allowed {
                            newEmoji = allowed
                            withAnimation(.linear(duration: 0.3)) { emojiShake += 1 }
                        }
                    }
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

// Horizontal shake used to reject invalid emoji input.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 6
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = travel * sin(animatableData * .pi * CGFloat(shakesPerUnit))
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

private extension Character {
    var isEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }
}
