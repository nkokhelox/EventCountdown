import Foundation
import Observation

// How a click on an event row opens Calendar: not at all, on a single click, or on a
// double click.
enum OpenCalendarClickMode: Int, CaseIterable {
    case never = 0
    case single = 1
    case double = 2
}

@Observable
final class AppModel {
    let calendarService: CalendarService
    let emojiStore: EmojiMappingStore
    let launchAtLoginService: LaunchAtLoginService

    var hasSeenFirstRunHint: Bool {
        didSet { UserDefaults.standard.set(hasSeenFirstRunHint, forKey: AppConstants.firstRunKey) }
    }

    var openCalendarClickMode: OpenCalendarClickMode {
        didSet { UserDefaults.standard.set(openCalendarClickMode.rawValue, forKey: AppConstants.openCalendarClickModeKey) }
    }

    // How long a just-passed event stays in the panel's "Past" section, in hours.
    var pastEventWindowHours: Int {
        didSet { UserDefaults.standard.set(pastEventWindowHours, forKey: AppConstants.pastEventWindowHoursKey) }
    }

    // How soon before it starts an event moves into the panel's "Next" section, in hours.
    // 0 means never show a Next section (events stay in Upcoming until they begin).
    var nextEventWindowHours: Int {
        didSet { UserDefaults.standard.set(nextEventWindowHours, forKey: AppConstants.nextEventWindowHoursKey) }
    }

    // How many day-groups in the panel's Upcoming list start expanded by default; the rest
    // start collapsed. Clamped to 1 (today only) through 7.
    var expandedDayCount: Int {
        didSet {
            let clamped = min(max(expandedDayCount, AppConstants.minExpandedDayCount), AppConstants.maxExpandedDayCount)
            if clamped != expandedDayCount {
                expandedDayCount = clamped
                return
            }
            UserDefaults.standard.set(expandedDayCount, forKey: AppConstants.expandedDayCountKey)
        }
    }

    init() {
        emojiStore = EmojiMappingStore()
        launchAtLoginService = LaunchAtLoginService()
        hasSeenFirstRunHint = UserDefaults.standard.bool(forKey: AppConstants.firstRunKey)
        if let storedClickMode = UserDefaults.standard.object(forKey: AppConstants.openCalendarClickModeKey) as? Int,
           let mode = OpenCalendarClickMode(rawValue: storedClickMode) {
            openCalendarClickMode = mode
        } else {
            // Migrate the old single-click boolean; absence defaults to double click.
            openCalendarClickMode = UserDefaults.standard.bool(forKey: AppConstants.openCalendarOnSingleClickKey) ? .single : .double
        }
        // Presence check, not `== 0`: 0 is a valid stored value meaning "Off" (hide the
        // Past section). Only fall back to the default when nothing has been stored yet.
        if UserDefaults.standard.object(forKey: AppConstants.pastEventWindowHoursKey) == nil {
            pastEventWindowHours = AppConstants.defaultPastEventWindowHours
        } else {
            pastEventWindowHours = UserDefaults.standard.integer(forKey: AppConstants.pastEventWindowHoursKey)
        }
        // Presence check, not `== 0`: 0 is a valid stored value meaning "Never".
        if UserDefaults.standard.object(forKey: AppConstants.nextEventWindowHoursKey) == nil {
            nextEventWindowHours = AppConstants.defaultNextEventWindowHours
        } else {
            nextEventWindowHours = UserDefaults.standard.integer(forKey: AppConstants.nextEventWindowHoursKey)
        }
        if let stored = UserDefaults.standard.object(forKey: AppConstants.expandedDayCountKey) as? Int {
            expandedDayCount = min(max(stored, AppConstants.minExpandedDayCount), AppConstants.maxExpandedDayCount)
        } else {
            expandedDayCount = AppConstants.defaultExpandedDayCount
        }

        calendarService = CalendarService()
    }

    private var didBootstrap = false

    @MainActor
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        // Re-arm the menu-bar clock whenever the fetched events change (calendar edits,
        // wake, the periodic refresh) so a newly-appeared or sooner event is picked up.
        calendarService.onRefresh = { [weak self] in
            self?.scheduleNextMenuBarUpdate()
        }
        calendarService.start()
        if calendarService.authorizationState == .notDetermined {
            await calendarService.requestAccess()
        } else {
            await calendarService.refresh()
        }
        scheduleNextMenuBarUpdate()
    }

    func emojiResolution(for event: CalendarEvent) -> EventEmojiResolution {
        EventTitleEmoji.resolve(
            for: event,
            titleRuleEmoji: emojiStore.titleRuleEmoji(for: event),
            calendarRuleEmoji: emojiStore.calendarRuleEmoji(for: event)
        )
    }

    var nextCountdownEvent: CalendarEvent? {
        let now = Date()
        return calendarService.upcomingEvents.first { $0.startDate > now }
    }

    // The currently in-progress event (most recently started, if several overlap).
    // Drives the menu bar "now" / "ongoing" label for the whole time it is running,
    // until its end time passes and it leaves nowEvents.
    var ongoingEvent: CalendarEvent? {
        calendarService.nowEvents.max { $0.startDate < $1.startDate }
    }

    // When the next upcoming event starts before the in-progress event ends, the two
    // overlap — surface the next event's countdown so you can see when it begins.
    var overlappingNextEvent: CalendarEvent? {
        guard let ongoing = ongoingEvent, let next = nextCountdownEvent else { return nil }
        return next.startDate < ongoing.endDate ? next : nil
    }

    var menuBarEvent: CalendarEvent? {
        if let overlappingNextEvent { return overlappingNextEvent }
        return ongoingEvent ?? nextCountdownEvent
    }

    var menuBarEventHasStarted: Bool {
        overlappingNextEvent == nil && ongoingEvent != nil
    }

    // The menu-bar label re-renders when this changes. It is advanced only at the exact
    // moments the label text can change (see CountdownSchedule), not on a fixed 1s poll.
    private(set) var tick = Date()
    private var menuBarTimer: Timer?

    // Surfaced in the About screen: how often the menu-bar label currently refreshes and
    // the event driving that cadence. Updated whenever the timer is re-armed.
    private(set) var menuBarRefreshInterval: TimeInterval?
    private(set) var menuBarRefreshSourceTitle: String?
    // The instant the menu-bar label will next update (nil when nothing is scheduled).
    private(set) var menuBarNextRefresh: Date?

    // Arm a single non-repeating timer for the next instant the menu-bar text changes.
    // Runs on the main run loop in `.common` mode so it keeps firing while other run-loop
    // tracking (e.g. the open panel) is in progress. Re-armed on every fire and refresh.
    private func scheduleNextMenuBarUpdate() {
        menuBarTimer?.invalidate()

        let now = Date()
        let event = menuBarEvent
        let hasStarted = menuBarEventHasStarted
        menuBarRefreshSourceTitle = event?.title
        menuBarRefreshInterval = CountdownSchedule.updateCadence(now: now, startDate: event?.startDate, endDate: event?.endDate, hasStarted: hasStarted)

        let fireDate = CountdownSchedule.nextChange(now: now, startDate: event?.startDate, endDate: event?.endDate, hasStarted: hasStarted)
        guard fireDate < .distantFuture else {
            // No event to count down: leave no timer armed until the next refresh.
            menuBarTimer = nil
            menuBarNextRefresh = nil
            return
        }

        let interval = max(0, fireDate.timeIntervalSince(now))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.tick = Date()
            self.scheduleNextMenuBarUpdate()
        }
        RunLoop.main.add(timer, forMode: .common)
        menuBarTimer = timer
        menuBarNextRefresh = fireDate
    }

    deinit {
        menuBarTimer?.invalidate()
    }
}
