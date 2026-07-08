import AppKit
import EventKit
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
    @State private var collapsedDayIDs: Set<Date> = []
    @State private var isAddingEvent = false

    private static let defaultExpandedDayCount = 2

    private enum EventRowMode {
        case upcoming
        case now
        case past
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appModel.hasSeenFirstRunHint {
                firstRunHint
            }

            content
        }
        .frame(width: MenuBarPanelMetrics.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
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
        var height: CGFloat = 40 // footer
        if !appModel.hasSeenFirstRunHint { height += 46 }
        return height
    }

    @ViewBuilder
    private var content: some View {
        switch appModel.calendarService.authorizationState {
        case .authorized:
            eventsPanel
        case .notDetermined:
            panelWithFooter {
                permissionPrompt("Calendar access is required to show countdowns.")
            }
        case .denied, .restricted:
            panelWithFooter {
                permissionPrompt("Calendar access is denied. Open System Settings to allow access.")
            }
        }
    }

    private var eventsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if needsScroll {
                    ScrollView {
                        eventsBody
                    }
                    .frame(height: maxScrollAreaHeight)
                } else {
                    eventsBody
                }
            }
            .onPreferenceChange(ScrollContentHeightKey.self) { measuredScrollContentHeight = $0 }

            footer
        }
        .onAppear(perform: applyDefaultDayCollapse)
        .onChange(of: eventDays) { _, _ in
            applyDefaultDayCollapse()
        }
    }

    private func panelWithFooter<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            footer
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
    private var eventsBody: some View {
        // Re-evaluate every tick so events move between Upcoming/Now/Past the instant
        // their start/end time passes (section lists are computed live off the clock).
        let _ = appModel.tick
        VStack(alignment: .leading, spacing: allDaysCollapsed ? 6 : 8) {
            if let past = visiblePastEvent {
                pastSection(past)
            }
            if !appModel.calendarService.nowEvents.isEmpty {
                nowSection(appModel.calendarService.nowEvents, showsSettings: visiblePastEvent == nil)
            }
            upcomingHeader(showsSettings: visiblePastEvent == nil && appModel.calendarService.nowEvents.isEmpty)
            if appModel.calendarService.panelEvents.isEmpty {
                Text("No upcoming events in the selected calendars.")
                    .foregroundStyle(.secondary)
            } else {
                upcomingEventsList
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, allDaysCollapsed ? 6 : 8)
        .padding(.bottom, allDaysCollapsed ? 4 : 6)
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

    // The recent past event while it is still within its display window, measured from
    // when it finished. Tracked live off appModel.tick so it ages out on time.
    private var visiblePastEvent: CalendarEvent? {
        guard let past = appModel.calendarService.recentPastEvent else { return nil }
        let elapsed = appModel.tick.timeIntervalSince(past.endDate)
        let window = TimeInterval(appModel.pastEventWindowHours) * 60 * 60
        return (elapsed >= 0 && elapsed <= window) ? past : nil
    }

    private func pastSection(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Past")
                    .font(.headline)
                Spacer()
                settingsButton
            }
            eventRow(event, showDivider: false, mode: .past)
        }
    }

    private func nowSection(_ events: [CalendarEvent], showsSettings: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Now")
                    .font(.headline)
                Spacer()
                if showsSettings {
                    settingsButton
                }
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                eventRow(event, showDivider: index < events.count - 1, mode: .now)
            }
        }
    }

    private func upcomingHeader(showsSettings: Bool) -> some View {
        HStack {
            Text("Upcoming")
                .font(.headline)
            Spacer()
            if showsSettings {
                settingsButton
            }
        }
    }

    private var settingsButton: some View {
        Button { showSettingsInForeground() } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    private var addButton: some View {
        Button {
            isAddingEvent = true
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Add Event")
        .popover(isPresented: $isAddingEvent, arrowEdge: .top) {
            AddEventForm()
                .environment(appModel)
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

    private var eventDays: [Date] {
        groupedPanelEvents.map(\.day)
    }

    private func applyDefaultDayCollapse() {
        collapsedDayIDs = Set(eventDays.dropFirst(Self.defaultExpandedDayCount))
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
                ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                    eventRow(event, showDivider: index < group.events.count - 1)
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

    private func eventRow(_ event: CalendarEvent, showDivider: Bool, mode: EventRowMode = .upcoming) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                EventLeadingGlyph(resolution: appModel.emojiResolution(for: event))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        EventTitleLabel(event: event)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if event.mapLink == nil && event.callLink == nil {
                            Circle()
                                .fill(event.calendarColor)
                                .frame(width: 7, height: 7)
                                .accessibilityHidden(true)
                        }
                        if let mapLink = event.mapLink {
                            iconLinkButton(system: "mappin.and.ellipse", label: "Open Location", greyed: mode == .past, color: event.calendarColor) {
                                NSWorkspace.shared.open(mapLink)
                            }
                        }
                        if let callLink = event.callLink {
                            iconLinkButton(system: "video", label: "Join Call", greyed: mode == .past, color: event.calendarColor) {
                                NSWorkspace.shared.open(callLink)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Text(formattedStart(event.startDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(trailingCountdown(for: event, mode: mode, now: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(EventRowHoverHighlight(baseTint: rowTint(for: mode, event: event)))
            .onTapGesture(count: appModel.openCalendarOnSingleClick ? 1 : 2) {
                appModel.calendarService.openCalendar(to: event.startDate)
            }

                if showDivider {
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
    }

    private func shortCountdown(for date: Date, now: Date) -> String {
        CountdownFormatter.menuBarDecimalText(
            remaining: CountdownFormatter.remaining(until: date, now: now)
        ).lowercased()
    }

    private func fullCountdown(for date: Date, now: Date) -> String {
        CountdownFormatter.fullRemainingListText(
            remaining: CountdownFormatter.remaining(until: date, now: now)
        )
    }

    // Only the in-progress (ongoing) event is tinted, with a faint red highlight.
    private func rowTint(for mode: EventRowMode, event: CalendarEvent) -> Color {
        mode == .now ? Color.red.opacity(0.12) : .clear
    }

    // Single most-significant unit, e.g. "1 hour" or "45 minutes".
    private func singleUnitCountdown(for date: Date, now: Date) -> String {
        CountdownFormatter.format(
            remaining: CountdownFormatter.remaining(until: date, now: now)
        ).listText
    }

    // Trailing status text for an event row: time until it starts (upcoming),
    // time until it ends (now / in progress), or how long ago it started (past).
    private func trailingCountdown(for event: CalendarEvent, mode: EventRowMode, now: Date) -> String {
        switch mode {
        case .upcoming:
            return fullCountdown(for: event.startDate, now: now)
        case .now:
            return "ends in \(singleUnitCountdown(for: event.endDate, now: now))"
        case .past:
            return agoText(for: event.startDate, now: now)
        }
    }

    @ViewBuilder
    private func iconLinkButton(
        system: String,
        label: String,
        greyed: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .foregroundStyle(greyed ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(color))
                .opacity(greyed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func agoText(for date: Date, now: Date) -> String {
        CountdownFormatter.agoText(
            elapsed: now.timeIntervalSince(date)
        )
    }

    private func toggleDayCollapse(_ day: Date) {
        if collapsedDayIDs.contains(day) {
            collapsedDayIDs.remove(day)
        } else {
            collapsedDayIDs.insert(day)
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
            addButton
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
            .accessibilityLabel("Quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
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

private struct AddEventForm: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var start = Date()
    @State private var durationMinutes = 60
    @State private var calendarID = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Event").font(.headline)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            DatePicker("Starts", selection: $start)
                .datePickerStyle(.compact)

            Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 15...600, step: 15)

            Picker("Calendar", selection: $calendarID) {
                ForEach(writableCalendars, id: \.calendarIdentifier) { calendar in
                    Text(calendar.title).tag(calendar.calendarIdentifier)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { addEvent() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            if calendarID.isEmpty {
                calendarID = writableCalendars.first?.calendarIdentifier ?? ""
            }
        }
    }

    private var writableCalendars: [EKCalendar] {
        appModel.calendarService.allCalendars.filter(\.allowsContentModifications)
    }

    private func addEvent() {
        isSaving = true
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        Task {
            _ = await appModel.calendarService.createEvent(
                title: title,
                start: start,
                end: end,
                calendarID: calendarID.isEmpty ? nil : calendarID
            )
            dismiss()
        }
    }
}

private struct EventLeadingGlyph: View {
    let resolution: EventEmojiResolution

    var body: some View {
        if resolution.usesAppIcon, let image = AppIconRenderer.image(pointSize: 28) {
            Image(nsImage: image)
                .frame(width: 28, height: 28)
        } else if let character = resolution.character {
            Text(character)
                .font(.system(size: 26))
        }
    }
}

private struct EventTitleLabel: View {
    let event: CalendarEvent

    var body: some View {
        Text(EventTitleEmoji.titleWithoutLeadingEmoji(event.title))
            .font(.body)
    }
}

private struct EventRowHoverHighlight: ViewModifier {
    var baseTint: Color = .clear
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(baseTint)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
    }
}
