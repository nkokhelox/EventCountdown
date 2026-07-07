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
    private var lastDailyRefresh: Date?

    private(set) var authorizationState: CalendarAuthorizationState = .notDetermined
    private(set) var upcomingEvents: [CalendarEvent] = []
    private(set) var allCalendars: [EKCalendar] = []
    var enabledCalendarIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledCalendarIDs), forKey: AppConstants.enabledCalendarIDsKey) }
    }

    var nextEvent: CalendarEvent? {
        upcomingEvents.first { $0.startDate > Date() || isEffectivelyActive($0) }
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

    private let pendingKeysProvider: () -> Set<String>

    init(pendingKeysProvider: @escaping () -> Set<String> = { [] }) {
        let saved = UserDefaults.standard.stringArray(forKey: AppConstants.enabledCalendarIDsKey) ?? []
        enabledCalendarIDs = Set(saved)
        self.pendingKeysProvider = pendingKeysProvider
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
            upcomingEvents = []
            allCalendars = []
            return
        }

        allCalendars = eventStore.calendars(for: .event).sorted { $0.title < $1.title }
        if enabledCalendarIDs.isEmpty {
            enabledCalendarIDs = Set(allCalendars.map(\.calendarIdentifier))
        }

        let now = Date()
        let end = Calendar.current.date(byAdding: .year, value: AppConstants.fetchHorizonYears, to: now) ?? now
        let calendars = allCalendars.filter { enabledCalendarIDs.contains($0.calendarIdentifier) }
        let predicate = eventStore.predicateForEvents(withStart: now.addingTimeInterval(-AppConstants.ackWindowSeconds), end: end, calendars: calendars)
        let ekEvents = eventStore.events(matching: predicate)

        let pendingKeys = pendingKeysProvider()
        let mapped = ekEvents.map(CalendarEvent.init(from:)).filter { event in
            event.startDate > now || pendingKeys.contains(event.eventKey.storageKey)
        }
        upcomingEvents = mapped.sorted { $0.startDate < $1.startDate }
        lastDailyRefresh = now
    }

    private func isEffectivelyActive(_ event: CalendarEvent) -> Bool {
        pendingKeysProvider().contains(event.eventKey.storageKey)
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

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.scheduleRefresh(debounce: 0)
            self?.refreshDailyIfNeeded()
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
