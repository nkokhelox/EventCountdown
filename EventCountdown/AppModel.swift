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

        calendarService = CalendarService()
    }

    private var didBootstrap = false

    @MainActor
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        calendarService.start()
        if calendarService.authorizationState == .notDetermined {
            await calendarService.requestAccess()
        } else {
            await calendarService.refresh()
        }
        startTickLoop()
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

    private(set) var tick = Date()

    @MainActor
    private func startTickLoop() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick = Date()
        }
    }
}
