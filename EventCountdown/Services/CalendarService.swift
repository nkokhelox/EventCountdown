import AppKit
import EventKit
import Foundation
import Observation

enum CalendarAuthorizationState: Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@Observable
final class CalendarService {
    private let eventStore = EKEventStore()
    private var changeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var periodicTimer: Timer?
    private var lastDailyRefresh: Date?

    // Invoked on the main actor at the end of every refresh (including the empty,
    // unauthorized case) so the owner can react to the new event set — e.g. re-arm the
    // menu-bar countdown clock.
    var onRefresh: (() -> Void)?

    private(set) var authorizationState: CalendarAuthorizationState = .notDetermined
    // All events fetched on the last refresh (past window + future), sorted by start.
    // The section lists below are derived from this live, so an event moves between
    // Upcoming / Now / Past the instant its start or end time passes — no refresh wait.
    private(set) var fetchedEvents: [CalendarEvent] = []
    private(set) var allCalendars: [EKCalendar] = []

    var upcomingEvents: [CalendarEvent] {
        let now = Date()
        return fetchedEvents.filter { $0.startDate > now }
    }

    // Events that have started but not yet ended (in progress right now).
    var nowEvents: [CalendarEvent] {
        let now = Date()
        return fetchedEvents.filter { $0.startDate <= now && $0.endDate > now }
    }

    var recentPastEvent: CalendarEvent? {
        let now = Date()
        return fetchedEvents.filter { $0.endDate <= now }.max { $0.endDate < $1.endDate }
    }
    var enabledCalendarIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledCalendarIDs), forKey: AppConstants.enabledCalendarIDsKey) }
    }

    var nextEvent: CalendarEvent? {
        upcomingEvents.first { $0.startDate > Date() }
    }

    var displayEvents: [CalendarEvent] {
        Array(upcomingEvents.prefix(AppConstants.displayEventCount))
    }

    var panelEvents: [CalendarEvent] {
        let calendar = Calendar.current
        let now = Date()
        guard let horizonEnd = calendar.date(
            byAdding: .day,
            value: AppConstants.panelHorizonDays,
            to: calendar.startOfDay(for: now)
        ) else {
            return upcomingEvents
        }
        return upcomingEvents.filter { $0.startDate < horizonEnd }
    }

    var scheduleEvents: [CalendarEvent] {
        Array(upcomingEvents.prefix(AppConstants.scheduleEventCount))
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: AppConstants.enabledCalendarIDsKey) ?? []
        enabledCalendarIDs = Set(saved)
        authorizationState = currentAuthorizationState()
    }

    func start() {
        setupObservers()
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refresh()
        }
    }

    func requestAccess() async {
        if #available(macOS 14.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                authorizationState = granted ? .authorized : .denied
            } catch {
                authorizationState = .denied
            }
        } else {
            await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    self.authorizationState = granted ? .authorized : .denied
                    continuation.resume()
                }
            }
        }
        await refresh()
    }

    @MainActor
    func createEvent(title: String, start: Date, end: Date, calendarID: String?) async -> Bool {
        guard authorizationState == .authorized else { return false }
        let event = EKEvent(eventStore: eventStore)
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Event" : title
        event.startDate = start
        event.endDate = max(end, start.addingTimeInterval(60))

        let calendar = allCalendars.first { $0.calendarIdentifier == calendarID }
            ?? eventStore.defaultCalendarForNewEvents
            ?? allCalendars.first { $0.allowsContentModifications }
        guard let calendar else { return false }
        event.calendar = calendar

        do {
            try eventStore.save(event, span: .thisEvent)
            await refresh()
            return true
        } catch {
            return false
        }
    }

    func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func openCalendar(to date: Date) {
        if navigateCalendarWithAppleScript(to: date) {
            return
        }
        openCalendarApp()
    }

    private func navigateCalendarWithAppleScript(to date: Date) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return false
        }
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        let scriptSource = """
        tell application "Calendar"
            activate
            set targetDate to current date
            set year of targetDate to \(year)
            set month of targetDate to \(month)
            set day of targetDate to \(day)
            set hours of targetDate to \(hour)
            set minutes of targetDate to \(minute)
            set seconds of targetDate to 0
            view calendar at targetDate
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }

    private func openCalendarApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration, completionHandler: nil)
    }

    @MainActor
    func refresh() async {
        authorizationState = currentAuthorizationState()
        guard authorizationState == .authorized else {
            fetchedEvents = []
            allCalendars = []
            onRefresh?()
            return
        }

        let calendars = eventStore.calendars(for: .event).sorted { $0.title < $1.title }
        if enabledCalendarIDs.isEmpty {
            enabledCalendarIDs = Set(calendars.map(\.calendarIdentifier))
        }
        let selectedIDs = enabledCalendarIDs
        let now = Date()

        // Snapshot-and-isolate: run the EventKit query + model mapping + sort off the main
        // thread, then publish the immutable result back on the main actor. The autorelease
        // pool drains EventKit's temporary objects per fetch instead of at the next run-loop
        // turn. Mirrors Itsycal's off-main serial-queue fetch (EventCenter.m).
        let store = eventStore
        let events: [CalendarEvent] = await Task.detached(priority: .utility) {
            autoreleasepool {
                let end = Calendar.current.date(byAdding: .year, value: AppConstants.fetchHorizonYears, to: now) ?? now
                let start = Calendar.current.date(byAdding: .day, value: -AppConstants.pastFetchHorizonDays, to: now)
                    ?? now.addingTimeInterval(-AppConstants.ackWindowSeconds)
                let selected = calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
                let mapped = store.events(matching: predicate)
                    // Defensive: skip events with no calendar (orphaned / edge cases) —
                    // CalendarEvent.init force-reads calendar.title/.identifier/.cgColor.
                    // Mirrors Itsycal skipping nil-colour calendars (issue #152).
                    .filter { $0.calendar != nil }
                    .map(CalendarEvent.init(from:))
                // Collapse the same event appearing in multiple calendars into one.
                return EventMerger.merge(mapped)
                    .sorted { $0.startDate < $1.startDate }
            }
        }.value

        allCalendars = calendars
        fetchedEvents = events
        lastDailyRefresh = now
        onRefresh?()
    }

    private func currentAuthorizationState() -> CalendarAuthorizationState {
        if #available(macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess, .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            case .writeOnly: return .denied
            @unknown default: return .notDetermined
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        }
    }

    private func setupObservers() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRefresh(debounce: 2)
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRefresh(debounce: 0)
        }

        periodicTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.scheduleRefresh(debounce: 0)
            self?.refreshDailyIfNeeded()
        }
    }

    deinit {
        periodicTimer?.invalidate()
        refreshTask?.cancel()
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func refreshDailyIfNeeded() {
        guard let lastDailyRefresh else {
            scheduleRefresh(debounce: 0)
            return
        }
        if Date().timeIntervalSince(lastDailyRefresh) >= 24 * 60 * 60 {
            scheduleRefresh(debounce: 0)
        }
    }

    private func scheduleRefresh(debounce: TimeInterval) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}
