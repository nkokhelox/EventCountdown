import SwiftUI
import XCTest

final class EventTitleEmojiTests: XCTestCase {
    private func makeEvent(title: String, calendarTitle: String = "Work") -> CalendarEvent {
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

    // MARK: - leadingEmoji

    func testLeadingEmojiExtractsFirstCharacter() {
        XCTAssertEqual(EventTitleEmoji.leadingEmoji(in: "🎉 Party"), "🎉")
    }

    func testLeadingEmojiIgnoresLeadingWhitespace() {
        XCTAssertEqual(EventTitleEmoji.leadingEmoji(in: "  🎂 Birthday"), "🎂")
    }

    func testLeadingEmojiReturnsNilWithoutOne() {
        XCTAssertNil(EventTitleEmoji.leadingEmoji(in: "Team Standup"))
    }

    // MARK: - inferredEmoji

    func testInferredEmojiMatchesFirstWordKeyword() {
        XCTAssertEqual(EventTitleEmoji.inferredEmoji(forTitle: "Birthday party"), "🎂")
        XCTAssertEqual(EventTitleEmoji.inferredEmoji(forTitle: "Flight to Cape Town"), "✈️")
    }

    func testInferredEmojiIsCaseInsensitive() {
        XCTAssertEqual(EventTitleEmoji.inferredEmoji(forTitle: "DINNER with friends"), "🍽️")
    }

    func testInferredEmojiReturnsNilForUnknownFirstWord() {
        XCTAssertNil(EventTitleEmoji.inferredEmoji(forTitle: "Zzyzx unmatched thing"))
    }

    // MARK: - resolve priority order

    func testResolvePrefersLeadingTitleEmojiOverEverythingElse() {
        let event = makeEvent(title: "🎯 Birthday planning")
        let resolution = EventTitleEmoji.resolve(for: event, titleRuleEmoji: "🚀", calendarRuleEmoji: "📅")
        XCTAssertEqual(resolution.character, "🎯")
    }

    func testResolveFallsBackToTitleRuleEmoji() {
        let event = makeEvent(title: "Unrecognized event title")
        let resolution = EventTitleEmoji.resolve(for: event, titleRuleEmoji: "🚀", calendarRuleEmoji: "📅")
        XCTAssertEqual(resolution.character, "🚀")
    }

    func testResolveFallsBackToInferredKeywordWhenNoTitleRule() {
        let event = makeEvent(title: "Birthday planning")
        let resolution = EventTitleEmoji.resolve(for: event, titleRuleEmoji: nil, calendarRuleEmoji: "📅")
        XCTAssertEqual(resolution.character, "🎂")
    }

    func testResolveFallsBackToCalendarRuleEmoji() {
        let event = makeEvent(title: "Zzyzx unmatched thing")
        let resolution = EventTitleEmoji.resolve(for: event, titleRuleEmoji: nil, calendarRuleEmoji: "📅")
        XCTAssertEqual(resolution.character, "📅")
    }

    func testResolveFallsBackToLeadingCalendarEmoji() {
        let event = makeEvent(title: "Zzyzx unmatched thing", calendarTitle: "📅 Work")
        let resolution = EventTitleEmoji.resolve(for: event, titleRuleEmoji: nil, calendarRuleEmoji: nil)
        XCTAssertEqual(resolution.character, "📅")
    }

    func testResolveDefaultsToCalendarEmojiWhenNothingElseMatches() {
        let event = makeEvent(title: "Zzyzx unmatched thing", calendarTitle: "Work")
        let resolution = EventTitleEmoji.resolve(for: event, titleRuleEmoji: nil, calendarRuleEmoji: nil)
        XCTAssertEqual(resolution.character, "🗓️")
    }

    // MARK: - titleWithoutLeadingEmoji

    func testTitleWithoutLeadingEmojiStripsEmojiAndSpace() {
        XCTAssertEqual(EventTitleEmoji.titleWithoutLeadingEmoji("🎉 Party time"), "Party time")
    }

    func testTitleWithoutLeadingEmojiKeepsTitleWhenNoRemainder() {
        XCTAssertEqual(EventTitleEmoji.titleWithoutLeadingEmoji("🎉"), "🎉")
    }

    func testTitleWithoutLeadingEmojiKeepsTitleWhenNoEmoji() {
        XCTAssertEqual(EventTitleEmoji.titleWithoutLeadingEmoji("Team Standup"), "Team Standup")
    }

    // MARK: - labeledTitle

    func testLabeledTitleKeepsExistingLeadingEmoji() {
        let resolution = EventEmojiResolution(character: "🚀")
        XCTAssertEqual(EventTitleEmoji.labeledTitle(fullTitle: "🎉 Party time", resolution: resolution), "🎉 Party time")
    }

    func testLabeledTitlePrependsResolvedEmojiWhenTitleHasNone() {
        let resolution = EventEmojiResolution(character: "🚀")
        XCTAssertEqual(EventTitleEmoji.labeledTitle(fullTitle: "Launch review", resolution: resolution), "🚀 Launch review")
    }

    func testLabeledTitleLeavesTitleUnchangedWhenUsingAppIcon() {
        XCTAssertEqual(
            EventTitleEmoji.labeledTitle(fullTitle: "Launch review", resolution: .appIcon),
            "Launch review"
        )
    }
}
