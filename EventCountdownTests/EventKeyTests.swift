import SwiftUI
import XCTest

final class EventKeyTests: XCTestCase {
    private func makeEvent(
        id: String = "a",
        title: String = "Meet",
        start: Date,
        cal: String = "cal1"
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            eventIdentifier: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            calendarTitle: "A",
            calendarID: cal,
            calendarColor: .red
        )
    }

    func testInitFromEventCopiesIdentityFields() {
        let start = Date(timeIntervalSince1970: 1_000)
        let event = makeEvent(id: "abc", title: "Standup", start: start, cal: "cal1")
        let key = EventKey(from: event)
        XCTAssertEqual(key.eventIdentifier, "abc")
        XCTAssertEqual(key.startDate, start)
        XCTAssertEqual(key.title, "Standup")
        XCTAssertEqual(key.calendarID, "cal1")
    }

    func testStorageKeyCombinesIdentifierAndStartDate() {
        let start = Date(timeIntervalSince1970: 1_500)
        let key = EventKey(eventIdentifier: "xyz", startDate: start, title: "Lunch", calendarID: "cal1")
        XCTAssertEqual(key.storageKey, "xyz|1500.0")
    }

    func testMatchesSameIdentifierAndStartDateIgnoresTitleChange() {
        let start = Date(timeIntervalSince1970: 2_000)
        let original = EventKey(eventIdentifier: "id1", startDate: start, title: "Old Title", calendarID: "cal1")
        let renamed = EventKey(eventIdentifier: "id1", startDate: start, title: "New Title", calendarID: "cal2")
        XCTAssertTrue(original.matches(snapshot: renamed))
    }

    func testMatchesFallsBackToTitleCalendarAndStartDate() {
        let start = Date(timeIntervalSince1970: 3_000)
        let original = EventKey(eventIdentifier: "id1", startDate: start, title: "Lunch", calendarID: "cal1")
        let recreated = EventKey(eventIdentifier: "id2", startDate: start, title: "Lunch", calendarID: "cal1")
        XCTAssertTrue(original.matches(snapshot: recreated))
    }

    func testDoesNotMatchDifferentStartDate() {
        let original = EventKey(
            eventIdentifier: "id1", startDate: Date(timeIntervalSince1970: 3_000), title: "Lunch", calendarID: "cal1"
        )
        let other = EventKey(
            eventIdentifier: "id1", startDate: Date(timeIntervalSince1970: 4_000), title: "Lunch", calendarID: "cal1"
        )
        XCTAssertFalse(original.matches(snapshot: other))
    }

    func testDoesNotMatchDifferentCalendarWhenIdentifierDiffers() {
        let start = Date(timeIntervalSince1970: 3_000)
        let original = EventKey(eventIdentifier: "id1", startDate: start, title: "Lunch", calendarID: "cal1")
        let other = EventKey(eventIdentifier: "id2", startDate: start, title: "Lunch", calendarID: "cal2")
        XCTAssertFalse(original.matches(snapshot: other))
    }
}
