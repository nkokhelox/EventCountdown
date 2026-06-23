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
    @Environment(\.dismiss) private var dismiss
    @State private var measuredScrollContentHeight: CGFloat = 0
    @State private var expandedEventIDs: Set<String> = []
    @State private var collapsedDayIDs: Set<Date> = []

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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: MenuBarPanelMetrics.maxPanelHeight(), alignment: .top)
    }

    private var maxScrollAreaHeight: CGFloat {
        MenuBarPanelMetrics.maxPanelHeight() - nonScrollChromeHeight
    }

    private var needsScroll: Bool {
        measuredScrollContentHeight > maxScrollAreaHeight && measuredScrollContentHeight > 0
    }

    private var allDaysCollapsed: Bool {
        !groupedPanelEvents.isEmpty && groupedPanelEvents.allSatisfy { collapsedDayIDs.contains($0.day) }
    }

    private var nonScrollChromeHeight: CGFloat {
        var height: CGFloat = 39
        if !appModel.hasSeenFirstRunHint { height += 46 }
        return height
    }

    @ViewBuilder
    private var content: some View {
        switch appModel.calendarService.authorizationState {
        case .authorized:
            Group {
                if needsScroll {
                    ScrollView {
                        eventsContent
                    }
                    .frame(height: maxScrollAreaHeight)
                } else {
                    eventsContent
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
        VStack(alignment: .leading, spacing: allDaysCollapsed ? 6 : 8) {
            if let pending = appModel.ackStore.primaryPendingRecord {
                pendingSection(pending)
            }
            upcomingHeader
            if appModel.calendarService.panelEvents.isEmpty {
                Text("No upcoming events in the selected calendars.")
                    .foregroundStyle(.secondary)
            } else {
                upcomingEventsList
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, allDaysCollapsed ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scrollHeightReader)
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

    private var upcomingHeader: some View {
        HStack {
            Text("Upcoming")
                .font(.headline)
            Spacer()
            Button {
                appModel.calendarService.openCalendarToToday()
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .help("Open Calendar to today")
            .accessibilityLabel("Open Calendar to today")
        }
    }

    private var upcomingEventsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groupedPanelEvents) { group in
                daySection(group)
            }
        }
    }

    private var panelEventsSpanMultipleYears: Bool {
        let calendar = Calendar.current
        let years = Set(appModel.calendarService.panelEvents.map {
            calendar.component(.year, from: $0.startDate)
        })
        return years.count > 1
    }

    private var groupedPanelEvents: [DayEventGroup] {
        let calendar = Calendar.current
        var groups: [Date: [CalendarEvent]] = [:]
        var order: [Date] = []

        for event in appModel.calendarService.panelEvents {
            let day = calendar.startOfDay(for: event.startDate)
            if groups[day] == nil {
                order.append(day)
                groups[day] = []
            }
            groups[day, default: []].append(event)
        }

        return order.map { DayEventGroup(day: $0, events: groups[$0]!) }
    }

    private func daySection(_ group: DayEventGroup) -> some View {
        let isCollapsed = collapsedDayIDs.contains(group.day)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleDayCollapse(group.day)
            } label: {
                daySectionHeader(group: group, isCollapsed: isCollapsed)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                ForEach(group.events) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func daySectionHeader(group: DayEventGroup, isCollapsed: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                Text(daySectionTitle(group))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if isCollapsed, let earliest = group.earliestEvent {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 1)

                    Text(shortCountdown(for: earliest.startDate, now: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 1)
                }
            }
        }
        .padding(.vertical, isCollapsed ? 2 : 4)
        .contentShape(Rectangle())
    }

    private func daySectionTitle(_ group: DayEventGroup) -> String {
        let count = group.events.count
        let eventWord = count == 1 ? "event" : "events"
        return "\(dayDividerLabel(group.day)) (\(count) \(eventWord))"
    }

    private func dayDividerLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        if panelEventsSpanMultipleYears {
            formatter.dateStyle = .full
        } else {
            formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        }
        return formatter.string(from: day)
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        let isExpanded = expandedEventIDs.contains(event.id)

        return TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    toggleEventExpansion(event.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)

                        Circle().fill(event.calendarColor).frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(appModel.labeledTitle(for: event))
                            Text(formattedStart(event.startDate)).font(.caption).foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(shortCountdown(for: event.startDate, now: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    expandedEventDetails(event, now: context.date)
                }
            }
            .modifier(EventRowHoverHighlight())
        }
    }

    private func expandedEventDetails(_ event: CalendarEvent, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fullCountdown(for: event.startDate, now: now))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Open in Calendar") {
                    appModel.calendarService.openCalendar(to: event.startDate)
                }
                .buttonStyle(.link)

                if let callLink = event.callLink {
                    Button {
                        NSWorkspace.shared.open(callLink)
                    } label: {
                        Label("Join Call", systemImage: "video.fill")
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(.leading, 28)
        .padding(.bottom, 6)
    }

    private func shortCountdown(for date: Date, now: Date) -> String {
        CountdownFormatter.format(
            remaining: CountdownFormatter.remaining(until: date, now: now)
        ).listText
    }

    private func fullCountdown(for date: Date, now: Date) -> String {
        CountdownFormatter.fullRemainingListText(
            remaining: CountdownFormatter.remaining(until: date, now: now)
        )
    }

    private func toggleDayCollapse(_ day: Date) {
        if collapsedDayIDs.contains(day) {
            collapsedDayIDs.remove(day)
        } else {
            collapsedDayIDs.insert(day)
        }
    }

    private func toggleEventExpansion(_ eventID: String) {
        if expandedEventIDs.contains(eventID) {
            expandedEventIDs.remove(eventID)
        } else {
            expandedEventIDs.insert(eventID)
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
            Button { showSettingsInForeground() } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(10)
    }

    private func showSettingsInForeground() {
        dismiss()
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.showSettings { openSettings() }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
    }

    private func formattedStart(_ date: Date) -> String {
        let formatter = DateFormatter()
        let dateTemplate = panelEventsSpanMultipleYears ? "yMMMd" : "MMMd"
        formatter.setLocalizedDateFormatFromTemplate("\(dateTemplate)jm")
        return formatter.string(from: date)
    }
}

private struct DayEventGroup: Identifiable {
    let day: Date
    let events: [CalendarEvent]

    var id: Date { day }

    var earliestEvent: CalendarEvent? {
        events.min(by: { $0.startDate < $1.startDate })
    }
}

private struct EventRowHoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
    }
}
