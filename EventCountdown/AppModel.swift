import Foundation
import Observation

@Observable
final class AppModel {
    let calendarService: CalendarService
    let emojiStore: EmojiMappingStore
    let launchAtLoginService: LaunchAtLoginService

    var hasSeenFirstRunHint: Bool {
        didSet { UserDefaults.standard.set(hasSeenFirstRunHint, forKey: AppConstants.firstRunKey) }
    }

    var openCalendarOnSingleClick: Bool {
        didSet { UserDefaults.standard.set(openCalendarOnSingleClick, forKey: AppConstants.openCalendarOnSingleClickKey) }
    }

    var countdownRoundsUp: Bool {
        didSet { UserDefaults.standard.set(countdownRoundsUp, forKey: AppConstants.countdownRoundsUpKey) }
    }

    // How long a just-passed event stays in the panel's "Past" section, in hours.
    var pastEventWindowHours: Int {
        didSet { UserDefaults.standard.set(pastEventWindowHours, forKey: AppConstants.pastEventWindowHoursKey) }
    }

    init() {
        emojiStore = EmojiMappingStore()
        launchAtLoginService = LaunchAtLoginService()
        hasSeenFirstRunHint = UserDefaults.standard.bool(forKey: AppConstants.firstRunKey)
        openCalendarOnSingleClick = UserDefaults.standard.bool(forKey: AppConstants.openCalendarOnSingleClickKey)
        countdownRoundsUp = UserDefaults.standard.bool(forKey: AppConstants.countdownRoundsUpKey)
        let storedPastWindowHours = UserDefaults.standard.integer(forKey: AppConstants.pastEventWindowHoursKey)
        pastEventWindowHours = storedPastWindowHours == 0 ? AppConstants.defaultPastEventWindowHours : storedPastWindowHours

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
