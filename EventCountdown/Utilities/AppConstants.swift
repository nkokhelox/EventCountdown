import Foundation

enum AppConstants {
    static let bundleID = "com.pisd.EventCountdown"
    static let notificationPrefix = "eventcountdown."
    static let ackWindowSeconds: TimeInterval = 5 * 60
    static let ackNowDisplaySeconds: TimeInterval = 60
    static let reminderIntervalSeconds: TimeInterval = {
        #if DEBUG && DEBUG_SHORT_ACK_WINDOW
        return 60
        #else
        return 15 * 60
        #endif
    }()
    static let maxReminderChains = 10
    static let displayEventCount = 5
    static let panelHorizonDays = 7
    static let pastFetchHorizonDays = 30
    static let scheduleEventCount = 20
    static let fetchHorizonYears = 3
    static let firstRunKey = "hasSeenFirstRunHint"
    static let openCalendarOnSingleClickKey = "openCalendarOnSingleClick"
    static let countdownRoundsUpKey = "countdownRoundsUp"
    static let launchAtLoginKey = "launchAtLoginEnabled"
    static let notificationsEnabledKey = "notificationsEnabled"
    static let enabledCalendarIDsKey = "enabledCalendarIDs"
    static let emojiRulesKey = "emojiRules"
    static let ackStoreKey = "acknowledgmentStore"
}
