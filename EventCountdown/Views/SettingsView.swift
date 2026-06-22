import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        TabView {
            calendarsTab
                .tabItem { Label("Calendars", systemImage: "calendar") }
            emojiTab
                .tabItem { Label("Emoji", systemImage: "face.smiling") }
            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
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
                    await appModel.resyncNotifications()
                }
            }
        )
    }

    private var emojiTab: some View {
        EmojiRulesEditor(store: appModel.emojiStore)
            .padding()
    }

    private var notificationsTab: some View {
        Form {
            Toggle("Enable notifications", isOn: Binding(
                get: { appModel.notificationService.isEnabled },
                set: { appModel.notificationService.isEnabled = $0; Task { await appModel.resyncNotifications() } }
            ))
            if !appModel.notificationService.permissionGranted {
                Text("Notifications are disabled in System Settings.")
                    .foregroundStyle(.secondary)
                Button("Open Notification Settings") { openNotificationSettings() }
            }
            Text("Pre-scheduled reminders continue even when the app is quit.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if appModel.notificationService.isEnabled && !appModel.launchAtLoginService.isEnabled {
                Text("Tip: enable Launch at login for menubar countdown and in-app reminders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { appModel.launchAtLoginService.isEnabled },
                set: { appModel.launchAtLoginService.isEnabled = $0 }
            ))
            if let message = appModel.launchAtLoginService.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .onAppear { appModel.launchAtLoginService.syncStatus() }
    }

    private var aboutTab: some View {
        Form {
            Text("EventCountdown")
                .font(.headline)
            Text("Countdown units use fixed durations: 1 year = 365 days, 1 month = 30 days, 1 week = 7 days. This keeps boundaries consistent but differs from calendar months.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            #if DEBUG && DEBUG_SHORT_ACK_WINDOW
            Text("DEBUG: acknowledgment window is 5 minutes; reminder interval is 1 minute.")
                .font(.caption)
                .foregroundStyle(.orange)
            #endif
        }
        .padding()
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
