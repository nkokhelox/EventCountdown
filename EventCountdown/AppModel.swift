import Foundation
import Observation

@Observable
final class AppModel {
    let calendarService: CalendarService
    let emojiStore: EmojiMappingStore
    let ackStore: AcknowledgmentStore
    let notificationService: NotificationService
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
        ackStore = AcknowledgmentStore()
        emojiStore = EmojiMappingStore()
        notificationService = NotificationService(ackStore: ackStore)
        launchAtLoginService = LaunchAtLoginService()
        hasSeenFirstRunHint = UserDefaults.standard.bool(forKey: AppConstants.firstRunKey)
        openCalendarOnSingleClick = UserDefaults.standard.bool(forKey: AppConstants.openCalendarOnSingleClickKey)
        countdownRoundsUp = UserDefaults.standard.bool(forKey: AppConstants.countdownRoundsUpKey)
        let storedPastWindowHours = UserDefaults.standard.integer(forKey: AppConstants.pastEventWindowHoursKey)
        pastEventWindowHours = storedPastWindowHours == 0 ? AppConstants.defaultPastEventWindowHours : storedPastWindowHours

        let ack = ackStore
        calendarService = CalendarService(pendingKeysProvider: {
            if let key = ack.primaryPendingRecord?.key.storageKey {
                return [key]
            }
            return []
        })
    }

    private var didBootstrap = false

    @MainActor
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        calendarService.start()
        notificationService.start()
        notificationService.onAcknowledged = { [weak self] key in
            await self?.acknowledge(key)
        }
        if calendarService.authorizationState == .notDetermined {
            await calendarService.requestAccess()
        } else {
            await calendarService.refresh()
        }
        await notificationService.restoreOnLaunch(events: calendarService.upcomingEvents) { [weak self] event in
            self?.emojiResolution(for: event) ?? .appIcon
        }
        await resyncNotifications()
        startTickLoop()
    }

    @MainActor
    func resyncNotifications() async {
        await notificationService.scheduleUpcoming(events: calendarService.scheduleEvents) { [weak self] event in
            self?.emojiResolution(for: event) ?? .appIcon
        }
    }

    @MainActor
    func acknowledge(_ key: EventKey) async {
        await notificationService.acknowledge(key)
        tick = Date()
        await resyncNotifications()
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

    var primaryPendingAcknowledgmentEvent: CalendarEvent? {
        guard let record = ackStore.primaryPendingRecord else { return nil }
        return calendarService.upcomingEvents.first { $0.eventKey.matches(snapshot: record.key) }
            ?? CalendarEvent(from: record.key)
    }

    var menuBarEvent: CalendarEvent? {
        primaryPendingAcknowledgmentEvent ?? nextCountdownEvent
    }

    var hasPendingAcknowledgment: Bool {
        ackStore.primaryPendingRecord != nil
    }

    private(set) var tick = Date()

    @MainActor
    private func startTickLoop() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick = Date()
                await self.notificationService.handleTick(events: self.calendarService.upcomingEvents) { event in
                    self.emojiResolution(for: event)
                }
            }
        }
    }
}
