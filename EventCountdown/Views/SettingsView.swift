import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

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
                    await appModel.resyncNotifications()
                }
            }
        )
    }

    private var emojiTab: some View {
        EmojiRulesEditor(store: appModel.emojiStore)
            .padding()
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    Picker("Open Calendar on", selection: Binding(
                        get: { appModel.openCalendarOnSingleClick },
                        set: { appModel.openCalendarOnSingleClick = $0 }
                    )) {
                        Text("Double click").tag(false)
                        Text("Single click").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    Text("Choose whether clicking or double-clicking an event opens Calendar to that day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                aboutSettingsGroup(title: "Notifications", systemImage: "bell") {
                    Toggle("Enable notifications", isOn: Binding(
                        get: { appModel.notificationService.isEnabled },
                        set: { appModel.notificationService.isEnabled = $0; Task { await appModel.resyncNotifications() } }
                    ))
                    if !appModel.notificationService.permissionGranted {
                        Text("Notifications are disabled in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Notification Settings") { openNotificationSettings() }
                    }
                    Text("Schedules the next event notification after the current one is acknowledged or expires.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Shows \"now\" for 1 minute after start, then \"Late\" for up to 5 minutes in the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if appModel.notificationService.isEnabled && !appModel.launchAtLoginService.isEnabled {
                        Text("Tip: enable Run at startup for menu bar countdown and in-app reminders.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 24)

            aboutDetailsFooter
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appModel.launchAtLoginService.syncStatus() }
    }

    private var aboutDetailsFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("EventCountdown")
                .font(.headline)
            Text("Countdown units use fixed durations: 1 year = 365 days, 1 month = 30 days, 1 week = 7 days. This keeps boundaries consistent but differs from calendar months.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            #if DEBUG && DEBUG_SHORT_ACK_WINDOW
            Text("DEBUG: DEBUG_SHORT_ACK_WINDOW is enabled for legacy reminder cleanup constants.")
                .font(.caption)
                .foregroundStyle(.orange)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
