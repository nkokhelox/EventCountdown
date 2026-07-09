import Foundation

enum AppConstants {
    static let bundleID = "com.pisd.EventCountdown"
    // How long a started event keeps showing in the menu bar as "now" / "Late".
    static let ackWindowSeconds: TimeInterval = 5 * 60
    // How long the menu bar shows "now" before switching to "Late".
    static let ackNowDisplaySeconds: TimeInterval = 60
    static let defaultPastEventWindowHours = 2
    static let defaultNextEventWindowHours = 2
    static let displayEventCount = 5
    static let panelHorizonDays = 7
    static let pastFetchHorizonDays = 30
    static let scheduleEventCount = 20
    static let fetchHorizonYears = 3
    static let firstRunKey = "hasSeenFirstRunHint"
    static let openCalendarOnSingleClickKey = "openCalendarOnSingleClick"
    static let openCalendarClickModeKey = "openCalendarClickMode"
    static let pastEventWindowHoursKey = "pastEventWindowHours"
    static let nextEventWindowHoursKey = "nextEventWindowHours"
    static let launchAtLoginKey = "launchAtLoginEnabled"
    static let enabledCalendarIDsKey = "enabledCalendarIDs"
    static let emojiRulesKey = "emojiRules"
}
