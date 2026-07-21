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
    // Merge provenance: an identity shared across calendars, plus the colors and number of
    // calendars this (possibly merged) event came from. Non-merged events have one color.
    let externalID: String?
    let calendarColors: [Color]
    let calendarCount: Int

    var eventKey: EventKey {
        EventKey(from: self)
    }

    var callLink: URL? {
        EventCallLink.resolve(eventURL: url, location: location, notes: notes)
    }

    var mapLink: URL? {
        guard let location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
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
        let color = Color(cgColor: event.calendar.cgColor)
        self.calendarColor = color
        self.externalID = event.calendarItemExternalIdentifier
        self.calendarColors = [color]
        self.calendarCount = 1
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
        self.externalID = nil
        self.calendarColors = [.accentColor]
        self.calendarCount = 1
    }

    // Full initializer for constructing events in the merger and in tests. Optional
    // parameters default to the non-merged single-calendar case.
    init(
        id: String,
        eventIdentifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        calendarTitle: String,
        calendarID: String,
        calendarColor: Color,
        externalID: String? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
        calendarColors: [Color]? = nil,
        calendarCount: Int? = nil
    ) {
        self.id = id
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarTitle = calendarTitle
        self.calendarID = calendarID
        self.calendarColor = calendarColor
        self.externalID = externalID
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.url = url
        self.calendarColors = calendarColors ?? [calendarColor]
        self.calendarCount = calendarCount ?? 1
    }
}
