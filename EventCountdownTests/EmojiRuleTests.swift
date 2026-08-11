import SwiftUI
import XCTest

final class EmojiRuleTests: XCTestCase {
    private func makeEvent(title: String = "Team Standup", calendarTitle: String = "Work") -> CalendarEvent {
        CalendarEvent(
            id: "a",
            eventIdentifier: "a",
            title: title,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600),
            calendarTitle: calendarTitle,
            calendarID: "cal1",
            calendarColor: .red
        )
    }

    private func rule(_ kind: EmojiRule.MatchKind, _ value: String) -> EmojiRule {
        EmojiRule(matchKind: kind, matchValue: value, emoji: "🗣️", priority: 0)
    }

    func testExactTitleRequiresFullMatch() {
        XCTAssertTrue(rule(.exactTitle, "Team Standup").matches(event: makeEvent(title: "Team Standup")))
        XCTAssertFalse(rule(.exactTitle, "Team Standup").matches(event: makeEvent(title: "Team Standup Extra")))
    }

    func testTitleContainsIsCaseInsensitive() {
        XCTAssertTrue(rule(.titleContains, "standup").matches(event: makeEvent(title: "Team Standup")))
        XCTAssertFalse(rule(.titleContains, "retro").matches(event: makeEvent(title: "Team Standup")))
    }

    func testTitleStartsWithAnchorsToPrefix() {
        XCTAssertTrue(rule(.titleStartsWith, "team").matches(event: makeEvent(title: "Team Standup")))
        XCTAssertFalse(rule(.titleStartsWith, "standup").matches(event: makeEvent(title: "Team Standup")))
    }

    func testTitleEndsWithAnchorsToSuffix() {
        XCTAssertTrue(rule(.titleEndsWith, "standup").matches(event: makeEvent(title: "Team Standup")))
        XCTAssertFalse(rule(.titleEndsWith, "team").matches(event: makeEvent(title: "Team Standup")))
    }

    func testCalendarNameMatchesCalendarTitleNotEventTitle() {
        XCTAssertTrue(rule(.calendarName, "work").matches(event: makeEvent(calendarTitle: "Work")))
        XCTAssertFalse(rule(.calendarName, "work").matches(event: makeEvent(title: "Work Party", calendarTitle: "Personal")))
    }
}
