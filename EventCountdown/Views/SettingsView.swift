import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    private let countdownUnitFacts = [
        "1 year = 365 days",
        "1 month = 30 days",
        "1 week = 7 days",
    ]

    var body: some View {
        TabView {
            calendarsTab
                .tabItem { Label("Calendars", systemImage: "calendar") }
            emojiTab
                .tabItem { Label("Emoji", systemImage: "face.smiling") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }

    private var calendarsTab: some View {
        Form {
            switch appModel.calendarService.authorizationState {
            case .authorized:
                Text("Select calendars to include.")
                    .foregroundStyle(.secondary)
                ForEach(appModel.calendarService.allCalendars, id: \.calendarIdentifier) { calendar in
                    Toggle(isOn: calendarEnabledBinding(calendar.calendarIdentifier)) {
                        Text(calendar.title)
                    }
                }
            default:
                Text("Calendar access is required.")
                Button("Request Access") { Task { await appModel.calendarService.requestAccess() } }
                Button("Open System Settings") { appModel.calendarService.openCalendarSettings() }
            }
        }
        .padding()
    }

    private func calendarEnabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { appModel.calendarService.enabledCalendarIDs.contains(id) },
            set: { enabled in
                if enabled {
                    appModel.calendarService.enabledCalendarIDs.insert(id)
                } else {
                    appModel.calendarService.enabledCalendarIDs.remove(id)
                }
                Task {
                    await appModel.calendarService.refresh()
                }
            }
        )
    }

    private var emojiTab: some View {
        EmojiRulesEditor(store: appModel.emojiStore)
            .padding()
    }

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                aboutSettingsGroup(title: "Startup", systemImage: "power") {
                    Toggle("Run at startup", isOn: Binding(
                        get: { appModel.launchAtLoginService.isEnabled },
                        set: { appModel.launchAtLoginService.isEnabled = $0 }
                    ))
                    if let message = appModel.launchAtLoginService.statusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                aboutSettingsGroup(title: "Events", systemImage: "hand.tap") {
                    eventsSubgroup(
                        "Open Calendar on",
                        description: "Choose whether a single click, a double-click, or neither opens Calendar to that day."
                    ) {
                        Picker("", selection: Binding(
                            get: { appModel.openCalendarClickMode },
                            set: { appModel.openCalendarClickMode = $0 }
                        )) {
                            Text("Never").tag(OpenCalendarClickMode.never)
                            Text("Single click").tag(OpenCalendarClickMode.single)
                            Text("Double click").tag(OpenCalendarClickMode.double)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }

                    eventsSubgroup(
                        "Show past event for",
                        description: "How long a just-passed event stays in the panel's Past section; choose Never to hide it."
                    ) {
                        Picker("", selection: Binding(
                            get: { appModel.pastEventWindowHours },
                            set: { appModel.pastEventWindowHours = $0 }
                        )) {
                            Text("Never").tag(0)
                            Text("1 hour").tag(1)
                            Text("2 hours").tag(2)
                            Text("4 hours").tag(4)
                            Text("8 hours").tag(8)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }

                    eventsSubgroup(
                        "Days expanded in Upcoming",
                        description: "How many day-groups in the Upcoming list start expanded when the panel opens; the rest start collapsed. From 1 (today only) to 7."
                    ) {
                        Stepper(
                            "\(appModel.expandedDayCount) day\(appModel.expandedDayCount == 1 ? "" : "s")",
                            value: Binding(
                                get: { appModel.expandedDayCount },
                                set: { appModel.expandedDayCount = $0 }
                            ),
                            in: AppConstants.minExpandedDayCount...AppConstants.maxExpandedDayCount
                        )
                    }

                    eventsSubgroup(
                        "Move to Next section",
                        description: "The soonest event moves out of Upcoming into its own Next section once its start is within this window. Never keeps everything in Upcoming (no Next section)."
                    ) {
                        Picker("", selection: Binding(
                            get: { appModel.nextEventWindowHours },
                            set: { appModel.nextEventWindowHours = $0 }
                        )) {
                            Text("Never").tag(0)
                            Text("1 hour").tag(1)
                            Text("2 hours").tag(2)
                            Text("4 hours").tag(4)
                            Text("8 hours").tag(8)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                }

                aboutSettingsGroup(title: "Menu bar refresh", systemImage: "timer") {
                    menuBarRefreshInfo
                }

                aboutInfoCard
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appModel.launchAtLoginService.syncStatus() }
    }

    private var aboutInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Events Countdown")
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 8)
                if let version = appVersionText {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("The units of measure we use are fixed for simplicity")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(countdownUnitFacts, id: \.self) { fact in
                    Text(fact)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("This keeps boundaries consistent but differs from calendar months.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var menuBarRefreshInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Refresh cadence")
                Spacer()
                Text(refreshCadenceText)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Next refresh time")
                Spacer()
                Text(nextRefreshText)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Driven by Event")
                Spacer()
                Text(appModel.menuBarRefreshSourceTitle ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.callout)
    }

    // How often the menu bar currently refreshes (widens as the event gets further away).
    private var refreshCadenceText: String {
        guard let interval = appModel.menuBarRefreshInterval else {
            return appModel.menuBarRefreshSourceTitle == nil ? "Idle" : "While ongoing"
        }
        return cadenceText(interval)
    }

    private func cadenceText(_ interval: TimeInterval) -> String {
        let value: Double
        let unit: String
        switch interval {
        case ..<60: value = interval; unit = "sec"
        case ..<3600: value = interval / 60; unit = "min"
        case ..<86400: value = interval / 3600; unit = "hr"
        default: value = interval / 86400; unit = "day"
        }
        let number = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "Every \(number) \(unit)\(value == 1 ? "" : "s")"
    }

    // When the menu bar will next update. The label only changes when its text can, so for
    // a far-off event this is minutes/hours away; when it's counting down by the second we
    // just say "Seconds" rather than a fast-moving timestamp.
    private var nextRefreshText: String {
        if let interval = appModel.menuBarRefreshInterval, interval < 60 {
            return "Seconds"
        }
        guard let next = appModel.menuBarNextRefresh else {
            return "Idle — no upcoming event"
        }
        return formattedNextRefresh(next)
    }

    private func formattedNextRefresh(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.setLocalizedDateFormatFromTemplate("jmmss")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
        }
        return formatter.string(from: date)
    }

    private var appVersionText: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return nil }
        if let build = info?["CFBundleVersion"] as? String, build != short {
            return "Version \(short) (\(build))"
        }
        return "Version \(short)"
    }

    private func aboutSettingsGroup<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }

    // A titled sub-section inside a settings group: the setting name is the subgroup
    // title, with the control (radio buttons) and its description subtext inside.
    private func eventsSubgroup<Content: View>(
        _ title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
