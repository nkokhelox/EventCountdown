import SwiftUI
import XCTest

final class EventMergerTests: XCTestCase {
    private func event(
        id: String,
        ext: String?,
        title: String = "Meet",
        start: Date,
        end: Date? = nil,
        cal: String,
        calTitle: String = "A",
        color: Color = .red,
        location: String? = nil,
        url: URL? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            eventIdentifier: id,
            title: title,
            startDate: start,
            endDate: end ?? start.addingTimeInterval(3600),
            calendarTitle: calTitle,
            calendarID: cal,
            calendarColor: color,
            externalID: ext,
            location: location,
            url: url
        )
    }

    func testMergesSameExternalIDAcrossCalendars() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let a = event(id: "a", ext: "X", start: start, cal: "cal1", calTitle: "Alpha", color: .red)
        let b = event(id: "b", ext: "X", start: start, cal: "cal2", calTitle: "Beta", color: .blue)
        let merged = EventMerger.merge([a, b])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].calendarCount, 2)
        XCTAssertEqual(merged[0].calendarColors.count, 2)
    }

    func testDoesNotMergeDifferentOccurrences() {
        let a = event(id: "a", ext: "X", start: Date(timeIntervalSince1970: 1000), cal: "c1")
        let b = event(id: "b", ext: "X", start: Date(timeIntervalSince1970: 5000), cal: "c2")
        XCTAssertEqual(EventMerger.merge([a, b]).count, 2)
    }

    func testMergesByContentWhenNoExternalID() {
        let start = Date(timeIntervalSince1970: 2000)
        let end = start.addingTimeInterval(1800)
        let a = event(id: "a", ext: nil, title: "Lunch", start: start, end: end, cal: "c1", calTitle: "A")
        let b = event(id: "b", ext: nil, title: "Lunch", start: start, end: end, cal: "c2", calTitle: "B")
        XCTAssertEqual(EventMerger.merge([a, b]).count, 1)
    }

    func testDoesNotMergeContentWithDifferentEnd() {
        let start = Date(timeIntervalSince1970: 2000)
        let a = event(id: "a", ext: nil, title: "Lunch", start: start, end: start.addingTimeInterval(1800), cal: "c1")
        let b = event(id: "b", ext: nil, title: "Lunch", start: start, end: start.addingTimeInterval(3600), cal: "c2")
        XCTAssertEqual(EventMerger.merge([a, b]).count, 2)
    }

    func testRepresentativeKeepsNonNilLocationAndURL() {
        let start = Date(timeIntervalSince1970: 3000)
        // Representative is the alphabetically-first calendar title ("Alpha"), which lacks a
        // location/url; those should be filled in from the other copy.
        let a = event(id: "a", ext: "Y", start: start, cal: "c1", calTitle: "Alpha")
        let b = event(id: "b", ext: "Y", start: start, cal: "c2", calTitle: "Beta",
                      location: "Room 5", url: URL(string: "https://zoom.us/j/1"))
        let merged = EventMerger.merge([a, b])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].location, "Room 5")
        XCTAssertEqual(merged[0].url?.absoluteString, "https://zoom.us/j/1")
    }

    func testSingleEventIsUnchanged() {
        let a = event(id: "solo", ext: "Z", start: Date(timeIntervalSince1970: 100), cal: "c1")
        let merged = EventMerger.merge([a])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, "solo")
        XCTAssertEqual(merged[0].calendarCount, 1)
    }
}
