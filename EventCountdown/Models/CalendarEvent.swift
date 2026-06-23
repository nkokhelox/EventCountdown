import EventKit
import SwiftUI

struct CalendarEvent: Identifiable, Sendable {
    let id: String
    let eventIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: URL?
    let calendarTitle: String
    let calendarID: String
    let calendarColor: Color

    var eventKey: EventKey {
        EventKey(from: self)
    }

    var callLink: URL? {
        EventCallLink.resolve(eventURL: url, location: location, notes: notes)
    }

    init(from event: EKEvent) {
        let identifier = event.eventIdentifier ?? UUID().uuidString
        self.id = "\(identifier)|\(event.startDate.timeIntervalSince1970)"
        self.eventIdentifier = identifier
        self.title = event.title ?? "Untitled Event"
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.isAllDay = event.isAllDay
        self.location = event.location
        self.notes = event.notes
        self.url = event.url
        self.calendarTitle = event.calendar.title
        self.calendarID = event.calendar.calendarIdentifier
        self.calendarColor = Color(cgColor: event.calendar.cgColor)
    }

    init(from key: EventKey) {
        self.id = key.storageKey
        self.eventIdentifier = key.eventIdentifier
        self.title = key.title
        self.startDate = key.startDate
        self.endDate = key.startDate.addingTimeInterval(3600)
        self.isAllDay = false
        self.location = nil
        self.notes = nil
        self.url = nil
        self.calendarTitle = ""
        self.calendarID = key.calendarID
        self.calendarColor = .accentColor
    }
}
