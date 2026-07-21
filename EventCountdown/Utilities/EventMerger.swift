import SwiftUI

// Collapses copies of the same event that appear in more than one calendar into a single
// CalendarEvent, keeping the colors and count of every calendar it came from. "Same event"
// is decided by EventKit's shared calendarItemExternalIdentifier (paired with the start
// date, since recurring occurrences share one id); when that's absent it falls back to a
// content key of title + start + end + all-day. Pure over value types, so it's unit-testable.
enum EventMerger {
    static func merge(_ events: [CalendarEvent]) -> [CalendarEvent] {
        var order: [String] = []
        var groups: [String: [CalendarEvent]] = [:]
        for event in events {
            let key = mergeKey(for: event)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(event)
        }
        return order.map { collapse(groups[$0]!) }
    }

    private static func mergeKey(for event: CalendarEvent) -> String {
        if let externalID = event.externalID, !externalID.isEmpty {
            return "ext|\(externalID)|\(event.startDate.timeIntervalSince1970)"
        }
        return "content|\(event.title)|\(event.startDate.timeIntervalSince1970)|\(event.endDate.timeIntervalSince1970)|\(event.isAllDay)"
    }

    private static func collapse(_ copies: [CalendarEvent]) -> CalendarEvent {
        guard copies.count > 1 else { return copies[0] }

        // Representative: the copy from the alphabetically-first calendar title, so the
        // choice is deterministic across refreshes.
        let ordered = copies.sorted {
            $0.calendarTitle.localizedCaseInsensitiveCompare($1.calendarTitle) == .orderedAscending
        }
        let representative = ordered[0]

        // One color per source calendar, primary first (used to draw a dot per calendar).
        let colors = ordered.map(\.calendarColor)

        // Fall back to whichever copy actually has a location / notes / url.
        let location = ordered.compactMap { nonEmpty($0.location) }.first ?? representative.location
        let notes = ordered.compactMap { nonEmpty($0.notes) }.first ?? representative.notes
        let url = ordered.compactMap { $0.url }.first ?? representative.url

        return CalendarEvent(
            id: mergeKey(for: representative),
            eventIdentifier: representative.eventIdentifier,
            title: representative.title,
            startDate: representative.startDate,
            endDate: representative.endDate,
            calendarTitle: representative.calendarTitle,
            calendarID: representative.calendarID,
            calendarColor: representative.calendarColor,
            externalID: representative.externalID,
            isAllDay: representative.isAllDay,
            location: location,
            notes: notes,
            url: url,
            calendarColors: colors,
            calendarCount: copies.count
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
