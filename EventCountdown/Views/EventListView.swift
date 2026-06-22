import AppKit
import SwiftUI

private struct ScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct EventListView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openSettings) private var openSettings
    @State private var measuredScrollContentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appModel.hasSeenFirstRunHint {
                firstRunHint
            }

            content
            Divider()
            footer
        }
        .frame(width: MenuBarPanelMetrics.panelWidth)
        .frame(maxHeight: MenuBarPanelMetrics.maxPanelHeight())
    }

    private var nonScrollChromeHeight: CGFloat {
        var height: CGFloat = 39
        if !appModel.hasSeenFirstRunHint { height += 46 }
        return height
    }

    private var maxScrollAreaHeight: CGFloat {
        max(80, MenuBarPanelMetrics.maxPanelHeight() - nonScrollChromeHeight)
    }

    private var scrollAreaHeight: CGFloat? {
        guard measuredScrollContentHeight > 0 else { return nil }
        return min(measuredScrollContentHeight, maxScrollAreaHeight)
    }

    @ViewBuilder
    private var content: some View {
        switch appModel.calendarService.authorizationState {
        case .authorized:
            Group {
                if let scrollAreaHeight {
                    ScrollView {
                        eventsContent
                            .background(scrollHeightReader)
                    }
                    .frame(height: scrollAreaHeight)
                } else {
                    ScrollView {
                        eventsContent
                            .background(scrollHeightReader)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onPreferenceChange(ScrollContentHeightKey.self) { measuredScrollContentHeight = $0 }
        case .notDetermined:
            permissionPrompt("Calendar access is required to show countdowns.")
        case .denied, .restricted:
            permissionPrompt("Calendar access is denied. Open System Settings to allow access.")
        }
    }

    private var scrollHeightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ScrollContentHeightKey.self,
                value: proxy.size.height
            )
        }
    }

    @ViewBuilder
    private var eventsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pending = appModel.ackStore.primaryPendingRecord {
                pendingSection(pending)
            }
            if appModel.calendarService.panelEvents.isEmpty {
                Text("No upcoming events in the selected calendars.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                upcomingSection
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstRunHint: some View {
        HStack {
            Text("EventCountdown lives in your menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("OK") { appModel.hasSeenFirstRunHint = true }
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func pendingSection(_ record: AcknowledgmentRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Needs acknowledgment")
                .font(.headline)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.key.title).font(.body)
                    Text(formattedStart(record.key.startDate)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Acknowledge") {
                    Task { await appModel.acknowledge(record.key) }
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming")
                .font(.headline)
            ForEach(appModel.calendarService.panelEvents) { event in
                eventRow(event)
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 10) {
                Circle().fill(event.calendarColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(appModel.emoji(for: event)) \(event.title)")
                    Text(formattedStart(event.startDate)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(
                    CountdownFormatter.format(
                        remaining: CountdownFormatter.remaining(until: event.startDate, now: context.date)
                    ).listText
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionPrompt(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).foregroundStyle(.secondary)
            Button("Request Access") {
                Task { await appModel.calendarService.requestAccess() }
            }
            Button("Open System Settings") {
                appModel.calendarService.openCalendarSettings()
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button { openSettings() } label: {
                Image(nsImage: NSImage(named: NSImage.preferencesGeneralName)!)
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(10)
    }

    private func formattedStart(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
