import Foundation

struct EventKey: Hashable, Codable, Sendable {
    let eventIdentifier: String
    let startDate: Date
    let title: String
    let calendarID: String

    init(eventIdentifier: String, startDate: Date, title: String, calendarID: String) {
        self.eventIdentifier = eventIdentifier
        self.startDate = startDate
        self.title = title
        self.calendarID = calendarID
    }

    init(from event: CalendarEvent) {
        self.eventIdentifier = event.eventIdentifier
        self.startDate = event.startDate
        self.title = event.title
        self.calendarID = event.calendarID
    }

    var storageKey: String {
        "\(eventIdentifier)|\(startDate.timeIntervalSince1970)"
    }

    func matches(snapshot: EventKey) -> Bool {
        if eventIdentifier == snapshot.eventIdentifier && startDate == snapshot.startDate {
            return true
        }
        return title == snapshot.title
            && calendarID == snapshot.calendarID
            && startDate == snapshot.startDate
    }
}
