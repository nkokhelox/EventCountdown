import XCTest

final class EventCallLinkTests: XCTestCase {
    func testResolvesZoomLinkFromLocation() {
        let url = EventCallLink.resolve(
            eventURL: nil,
            location: "https://zoom.us/j/123456789",
            notes: nil
        )
        XCTAssertEqual(url?.absoluteString, "https://zoom.us/j/123456789")
    }

    func testResolvesGoogleMeetFromNotes() {
        let url = EventCallLink.resolve(
            eventURL: nil,
            location: nil,
            notes: "Join: https://meet.google.com/abc-defg-hij"
        )
        XCTAssertEqual(url?.host, "meet.google.com")
    }

    func testResolvesTeamsFromEventURL() {
        let eventURL = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting")!
        let url = EventCallLink.resolve(eventURL: eventURL, location: nil, notes: nil)
        XCTAssertEqual(url?.host, "teams.microsoft.com")
    }

    func testResolvesPhoneNumber() {
        let url = EventCallLink.resolve(
            eventURL: nil,
            location: "Dial +1 (415) 555-0100",
            notes: nil
        )
        XCTAssertEqual(url?.scheme, "tel")
        XCTAssertTrue(url?.absoluteString.contains("4155550100") == true)
    }

    func testIgnoresMapsLink() {
        let url = EventCallLink.resolve(
            eventURL: nil,
            location: "https://maps.apple.com/?address=1+Infinite+Loop",
            notes: nil
        )
        XCTAssertNil(url)
    }

    func testReturnsNilWhenNoCallLink() {
        let url = EventCallLink.resolve(
            eventURL: nil,
            location: "Conference Room A",
            notes: "Bring slides"
        )
        XCTAssertNil(url)
    }
}
