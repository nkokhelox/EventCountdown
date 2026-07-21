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
    // The day chosen in the calendar. Reset to today every time the panel appears.
    @State private var pickerDate = Date()

    private static let defaultExpandedDayCount = 2
    private static let contentHorizontalPadding: CGFloat = 12

    // The selected day, normalized to midnight. `isTodaySelected` drives whether the panel
    // shows the live upcoming list (today) or just that day's events (any other day).
    private var selectedDay: Date { Calendar.current.startOfDay(for: pickerDate) }
    private var isTodaySelected: Bool { Calendar.current.isDateInToday(pickerDate) }

    private enum EventRowMode {
        case upcoming
        case next
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
        let groups = groupedPanelEvents(now: Date())
        return !groups.isEmpty && groups.allSatisfy { collapsedDayIDs.contains($0.day) }
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
        .onAppear {
            pickerDate = Date() // today is always selected by default when the panel opens
            applyDefaultDayCollapse()
        }
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
        VStack(alignment: .leading, spacing: 8) {
            calendarPicker
            // A per-second timeline drives section re-bucketing (an event moves between
            // Upcoming/Now/Past the instant its start/end passes) only while the panel is
            // on screen. It is independent of the menu bar's adaptive clock (AppModel.tick),
            // which no longer fires every second. The calendar is kept outside the timeline
            // so it isn't rebuilt each second.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                sectionsBody(now: context.date)
            }
        }
        .padding(.horizontal, Self.contentHorizontalPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scrollHeightReader)
    }

    private var calendarPicker: some View {
        // A custom month grid (rather than DatePicker's .graphical style, which stays
        // intrinsic-sized and centered on macOS) so the calendar fills the full list width.
        MonthCalendarView(selection: $pickerDate, eventDays: eventDayStarts)
            .frame(maxWidth: .infinity)
    }

    // Day-starts (midnight) that have at least one event, for the calendar's event dots.
    // Covers every day a (possibly multi-day) event spans.
    private var eventDayStarts: Set<Date> {
        let calendar = Calendar.current
        var days: Set<Date> = []
        for event in appModel.calendarService.fetchedEvents {
            var day = calendar.startOfDay(for: event.startDate)
            let last = calendar.startOfDay(for: event.endDate)
            var guardCount = 0
            while day <= last && guardCount < 400 {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                guardCount += 1
            }
        }
        return days
    }

    @ViewBuilder
    private func sectionsBody(now: Date) -> some View {
        let past = visiblePastEvent(now: now)
        let nowEvents = appModel.calendarService.nowEvents
        let next = nextEvents(now: now)
        VStack(alignment: .leading, spacing: allDaysCollapsed ? 6 : 8) {
            if let past {
                pastSection(past)
            }
            if !nowEvents.isEmpty {
                nowSection(nowEvents, showsSettings: past == nil)
            }
            if !next.isEmpty {
                nextSection(next, showsSettings: past == nil && nowEvents.isEmpty)
            }
            // The selected day's events live below the time-relative sections. Today shows
            // the full live upcoming list (as before); any other day shows just that day.
            selectedDaySection(now: now, hasPast: past != nil, nowEvents: nowEvents, next: next)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func selectedDaySection(now: Date, hasPast: Bool, nowEvents: [CalendarEvent], next: [CalendarEvent]) -> some View {
        // The settings gear lives in the first visible section header; it lands here only
        // when there is no Past / Now / Next section above.
        let showsSettings = !hasPast && nowEvents.isEmpty && next.isEmpty
        if isTodaySelected {
            let remaining = remainingPanelEvents(now: now)
            if !remaining.isEmpty {
                upcomingHeader(showsSettings: showsSettings)
                upcomingEventsList(now: now)
            } else if next.isEmpty {
                upcomingHeader(showsSettings: showsSettings)
                Text("No upcoming events in the selected calendars.")
                    .foregroundStyle(.secondary)
            }
        } else {
            selectedDayList(showsSettings: showsSettings)
        }
    }

    @ViewBuilder
    private func selectedDayList(showsSettings: Bool) -> some View {
        let events = eventsOnSelectedDay
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dayDividerLabel(selectedDay))
                    .font(.headline)
                Spacer()
                if showsSettings {
                    settingsButton
                }
            }
            if events.isEmpty {
                Text("No events on this day.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    eventRow(event, showDivider: index < events.count - 1, mode: .upcoming)
                }
            }
        }
    }

    // Events overlapping the selected day, sorted by start. Drawn from the full fetched set
    // so past days within the fetch horizon show their events too.
    private var eventsOnSelectedDay: [CalendarEvent] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDay)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return appModel.calendarService.fetchedEvents
            .filter { $0.startDate < dayEnd && $0.endDate > dayStart }
            .sorted { $0.startDate < $1.startDate }
    }

    private var firstRunHint: some View {
        HStack {
            Text("Events Countdown lives in your menu bar.")
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
    // when it finished. Evaluated against the panel timeline's `now` so it ages out on time.
    private func visiblePastEvent(now: Date) -> CalendarEvent? {
        guard appModel.pastEventWindowHours > 0 else { return nil } // Off: never show a past event
        guard let past = appModel.calendarService.recentPastEvent else { return nil }
        let elapsed = now.timeIntervalSince(past.endDate)
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

    // The soonest upcoming event(s). Usually one; when several share the exact same
    // earliest start time (a start-time conflict) they all appear here, tinted a deeper
    // red than the ongoing "Now" rows.
    private func nextSection(_ events: [CalendarEvent], showsSettings: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Next")
                    .font(.headline)
                Spacer()
                if showsSettings {
                    settingsButton
                }
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                eventRow(event, showDivider: index < events.count - 1, mode: .next)
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

    private func upcomingEventsList(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groupedPanelEvents(now: now)) { group in
                daySection(group)
            }
        }
    }

    // Source events for the panel's Next + Upcoming sections: normally the horizon window,
    // but if that has no events, fall back to any upcoming events across up to a capped
    // number of distinct event-days so the panel is never blank when events exist further
    // out than the horizon.
    private var panelSourceEvents: [CalendarEvent] {
        let horizon = appModel.calendarService.panelEvents
        if !horizon.isEmpty { return horizon }
        let calendar = Calendar.current
        var seenDays: [Date] = []
        var result: [CalendarEvent] = []
        for event in appModel.calendarService.upcomingEvents {
            let day = calendar.startOfDay(for: event.startDate)
            if !seenDays.contains(day) {
                if seenDays.count == AppConstants.fallbackUpcomingEventDays { break }
                seenDays.append(day)
            }
            result.append(event)
        }
        return result
    }

    private var panelEventsSpanMultipleYears: Bool {
        let calendar = Calendar.current
        let years = Set(panelSourceEvents.map {
            calendar.component(.year, from: $0.startDate)
        })
        return years.count > 1
    }

    // The soonest upcoming event and any others starting at the exact same time — but
    // only once that start is within the chosen window (Never / ≤N hours). Until then it
    // stays in Upcoming. panelEvents is sorted by start ascending, so the equal-start run
    // is a leading prefix.
    private func nextEvents(now: Date) -> [CalendarEvent] {
        let windowHours = appModel.nextEventWindowHours
        guard windowHours > 0 else { return [] } // Never: no Next section
        let events = panelSourceEvents
        guard let first = events.first else { return [] }
        let window = TimeInterval(windowHours) * 60 * 60
        guard first.startDate.timeIntervalSince(now) <= window else { return [] }
        let firstStart = first.startDate
        return Array(events.prefix { $0.startDate == firstStart })
    }

    // Upcoming panel events excluding the Next run — these are grouped by day below.
    private func remainingPanelEvents(now: Date) -> [CalendarEvent] {
        Array(panelSourceEvents.dropFirst(nextEvents(now: now).count))
    }

    private func groupedPanelEvents(now: Date) -> [DayEventGroup] {
        let calendar = Calendar.current
        var groups: [Date: [CalendarEvent]] = [:]
        var order: [Date] = []

        for event in remainingPanelEvents(now: now) {
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
        groupedPanelEvents(now: Date()).map(\.day)
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
                        EventTitleLabel(event: event, strikethrough: mode == .past)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if event.mapLink == nil && event.callLink == nil {
                            calendarIndicator(event)
                        }
                        if let mapLink = event.mapLink {
                            iconLinkButton(system: "mappin.and.ellipse", label: "Open Location", greyed: mode == .past, color: event.calendarColor) {
                                NSWorkspace.shared.open(mapLink)
                                dismiss()
                            }
                        }
                        if let callLink = event.callLink {
                            // Phone icon for a dial-in (tel:/audio); video icon for a web/app meeting link.
                            let isPhone = ["tel", "facetime-audio"].contains(callLink.scheme?.lowercased() ?? "")
                            iconLinkButton(system: isPhone ? "phone" : "video", label: isPhone ? "Call" : "Join Call", greyed: mode == .past, color: event.calendarColor) {
                                NSWorkspace.shared.open(callLink)
                                dismiss()
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Text(rowSubtitle(for: event, mode: mode, now: context.date))
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
            .modifier(OpenCalendarOnClick(mode: appModel.openCalendarClickMode) {
                appModel.calendarService.openCalendar(to: event.startDate)
            })

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

    // Ongoing ("Now") rows get a faint red tint; the imminent "Next" event(s) get a
    // deeper red so the very next thing on the schedule stands out most.
    private func rowTint(for mode: EventRowMode, event: CalendarEvent) -> Color {
        switch mode {
        case .now: return Color.red.opacity(0.12)
        // Deeper red only when there is a start-time conflict (more than one Next event).
        case .next: return nextEvents(now: Date()).count > 1 ? Color.red.opacity(0.22) : .clear
        default: return .clear
        }
    }

    // Single most-significant unit, e.g. "1 hour" or "45 minutes".
    private func singleUnitCountdown(for date: Date, now: Date) -> String {
        CountdownFormatter.format(
            remaining: CountdownFormatter.remaining(until: date, now: now)
        ).listText
    }

    // Trailing status text for an event row: time until it starts (upcoming),
    // time until it ends (now / in progress), or how long ago it ended (past).
    private func trailingCountdown(for event: CalendarEvent, mode: EventRowMode, now: Date) -> String {
        switch mode {
        case .upcoming, .next:
            return fullCountdown(for: event.startDate, now: now)
        case .now:
            return "ends in \(singleUnitCountdown(for: event.endDate, now: now))"
        case .past:
            return agoText(for: event.endDate, now: now)
        }
    }

    // Calendar provenance shown on a row: a single color dot for a normal event; one dot
    // per calendar (in each calendar's color) for an event merged from 2–3 calendars; and a
    // git-merge icon once it spans more than 3 calendars.
    @ViewBuilder
    private func calendarIndicator(_ event: CalendarEvent) -> some View {
        if event.calendarCount > 3 {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .help("On \(event.calendarCount) calendars")
                .accessibilityHidden(true)
        } else {
            HStack(spacing: -2) {
                ForEach(Array(event.calendarColors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 0.5))
                }
            }
            .help(event.calendarCount > 1 ? "On \(event.calendarCount) calendars" : "")
            .accessibilityHidden(true)
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

    // Row subtitle: upcoming rows show the start date-time; the Next event shows
    // "at <start> for <length>"; an ongoing event shows how much of it is left; a past
    // event shows the time it ended.
    private func rowSubtitle(for event: CalendarEvent, mode: EventRowMode, now: Date) -> String {
        switch mode {
        case .next:
            return nextStartAndDuration(event)
        case .now:
            if event.isAllDay { return "all day" }
            return "\(CountdownFormatter.durationText(event.endDate.timeIntervalSince(now))) left"
        case .past:
            return event.isAllDay ? "all day" : Self.timeFormatter.string(from: event.endDate)
        case .upcoming:
            return formattedStart(event.startDate)
        }
    }

    // Next-event subtitle: start time and length, e.g. "at 12:00 for 1 hr 30 mins".
    // All-day events just read "all day".
    private func nextStartAndDuration(_ event: CalendarEvent) -> String {
        if event.isAllDay { return "all day" }
        let time = Self.timeFormatter.string(from: event.startDate)
        let duration = CountdownFormatter.durationText(event.endDate.timeIntervalSince(event.startDate))
        return "at \(time) for \(duration)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter
    }()
}

private struct DayEventGroup: Identifiable {
    let day: Date
    let events: [CalendarEvent]

    var id: Date { day }

    var earliestEvent: CalendarEvent? {
        events.min(by: { $0.startDate < $1.startDate })
    }
}

// A full-width month calendar: a header with month/year + prev/next, a weekday row, and a
// 6-week grid of equal flexible columns so it stretches to fill the panel. Selecting a day
// updates `selection`; today is outlined, the selected day is filled.
private struct MonthCalendarView: View {
    @Binding var selection: Date
    var eventDays: Set<Date>

    @State private var visibleMonth = Date()

    private let calendar = Calendar.current
    private static let daysPerWeek = 7
    private static let weeksShown = 6

    var body: some View {
        VStack(spacing: 6) {
            header
            weekdayHeader
            daysGrid
        }
        .onAppear { visibleMonth = startOfMonth(selection) }
        .onChange(of: selection) { _, newValue in
            // Follow the selection into its month (e.g. when it resets to today on reopen).
            if !calendar.isDate(newValue, equalTo: visibleMonth, toGranularity: .month) {
                visibleMonth = startOfMonth(newValue)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(monthTitle)
                .font(.headline)
            Spacer()
            HStack(spacing: 12) {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left").fontWeight(.bold)
                }
                .help("Previous month")
                .accessibilityLabel("Previous month")
                Button(action: goToToday) {
                    Image(systemName: todaySymbolName)
                        .font(.system(size: 13, weight: .semibold))
                }
                .help("Today")
                .accessibilityLabel("Today")
                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right").fontWeight(.bold)
                }
                .help("Next month")
                .accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: Self.daysPerWeek)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(gridDays, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let hasEvent = eventDays.contains(calendar.startOfDay(for: day))
        return Button {
            selection = day
        } label: {
            ZStack {
                Group {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 1)
                    }
                }
                .frame(width: 30, height: 30)

                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 14))
                    .foregroundStyle(dayColor(inMonth: inMonth, isSelected: isSelected))
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .overlay(alignment: .bottom) {
                Circle()
                    .fill(dotColor(inMonth: inMonth, isSelected: isSelected))
                    .frame(width: 4, height: 4)
                    // Hidden on the selected day (clashes with the fill circle) and on today
                    // (the accent ring already marks it, so the dot would be redundant).
                    .opacity(hasEvent && !isSelected && !isToday ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayColor(inMonth: Bool, isSelected: Bool) -> Color {
        if isSelected { return .white }
        return inMonth ? .primary : Color.secondary.opacity(0.4)
    }

    private func dotColor(inMonth: Bool, isSelected: Bool) -> Color {
        if isSelected { return .white }
        return inMonth ? .accentColor : Color.secondary.opacity(0.4)
    }

    // MARK: Date math

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: visibleMonth)
    }

    // Locale-aware weekday initials, rotated so the first column is the locale's first day.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    // Six weeks of dates starting on the first-weekday on/before the 1st of the month, so
    // the grid is a stable height and shows leading/trailing days of adjacent months.
    private var gridDays: [Date] {
        let firstOfMonth = startOfMonth(visibleMonth)
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekday - calendar.firstWeekday + Self.daysPerWeek) % Self.daysPerWeek
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: firstOfMonth) else {
            return []
        }
        return (0..<(Self.daysPerWeek * Self.weeksShown)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func changeMonth(by delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = newMonth
        }
    }

    private func goToToday() {
        let today = calendar.startOfDay(for: Date())
        selection = today
        visibleMonth = startOfMonth(today)
    }

    // SF Symbol for today's date in a circle, e.g. "20.circle" (1...31 all exist).
    private var todaySymbolName: String {
        "\(calendar.component(.day, from: Date())).circle"
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
    var strikethrough: Bool = false

    var body: some View {
        Text(EventTitleEmoji.titleWithoutLeadingEmoji(event.title))
            .font(.body)
            .strikethrough(strikethrough)
    }
}

// Opens Calendar on a tap when enabled — single or double click per the user's setting,
// or not at all when set to Never (no gesture is attached).
private struct OpenCalendarOnClick: ViewModifier {
    let mode: OpenCalendarClickMode
    let action: () -> Void

    func body(content: Content) -> some View {
        switch mode {
        case .never:
            content
        case .single:
            content.onTapGesture(count: 1, perform: action)
        case .double:
            content.onTapGesture(count: 2, perform: action)
        }
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
