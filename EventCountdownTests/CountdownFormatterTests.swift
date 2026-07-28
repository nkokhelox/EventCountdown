import XCTest

final class CountdownFormatterTests: XCTestCase {
    private let year: TimeInterval = 365 * 24 * 60 * 60
    private let month: TimeInterval = 30 * 24 * 60 * 60
    private let week: TimeInterval = 7 * 24 * 60 * 60
    private let day: TimeInterval = 24 * 60 * 60
    private let hour: TimeInterval = 60 * 60
    private let minute: TimeInterval = 60

    func testGreaterThanTwoYearsUsesYears() {
        let value = CountdownFormatter.format(remaining: 2 * year + day)
        XCTAssertEqual(value.unit, .years)
        XCTAssertEqual(value.value, 2)
    }

    func testExactlyTwoYearsUsesMonths() {
        let value = CountdownFormatter.format(remaining: 2 * year)
        XCTAssertEqual(value.unit, .months)
        XCTAssertEqual(value.value, 24)
    }

    func testExactlyThreeMonthsUsesWeeks() {
        let value = CountdownFormatter.format(remaining: 3 * month)
        XCTAssertEqual(value.unit, .weeks)
        XCTAssertEqual(value.value, 12)
    }

    func testExactlyTwoWeeksUsesDays() {
        let value = CountdownFormatter.format(remaining: 2 * week)
        XCTAssertEqual(value.unit, .days)
    }

    func testExactlyTwoDaysUsesHours() {
        let value = CountdownFormatter.format(remaining: 2 * day)
        XCTAssertEqual(value.unit, .hours)
    }

    func testExactlyOneHourUsesOneHour() {
        let value = CountdownFormatter.format(remaining: hour)
        XCTAssertEqual(value.unit, .hours)
        XCTAssertEqual(value.value, 1)
    }

    func testJustUnderOneHourUsesMinutes() {
        let value = CountdownFormatter.format(remaining: hour - minute)
        XCTAssertEqual(value.unit, .minutes)
        XCTAssertEqual(value.value, 59)
    }

    func testOneHourFortyFiveMinutesUsesOneHour() {
        let value = CountdownFormatter.format(remaining: hour + 45 * minute)
        XCTAssertEqual(value.unit, .hours)
        XCTAssertEqual(value.value, 1)
    }

    func testExactlyOneMinuteUsesSeconds() {
        let value = CountdownFormatter.format(remaining: minute)
        XCTAssertEqual(value.unit, .seconds)
    }

    func testZeroOrNegativeIsPast() {
        let value = CountdownFormatter.format(remaining: 0)
        XCTAssertTrue(value.isPast)
    }

    func testListTextUsesSingularHour() {
        let value = CountdownFormatter.format(remaining: hour)
        XCTAssertEqual(value.listText, "1 hour")
    }

    func testListTextUsesPluralHours() {
        let value = CountdownFormatter.format(remaining: 2 * hour)
        XCTAssertEqual(value.listText, "2 hours")
    }

    func testMenuBarTextUsesCompactPluralHours() {
        let value = CountdownFormatter.format(remaining: 2 * hour)
        XCTAssertEqual(value.menuBarText, "2 hours")
    }

    func testFullRemainingListTextIncludesHoursAndMinutes() {
        let text = CountdownFormatter.fullRemainingListText(remaining: 13 * hour + 45 * minute)
        XCTAssertEqual(text, "13 hours 45 minutes")
    }

    func testFullRemainingListTextShowsTopTwoUnitsOnly() {
        let text = CountdownFormatter.fullRemainingListText(remaining: 2 * day + 3 * hour + 20 * minute)
        XCTAssertEqual(text, "2 days 3 hours")
    }

    func testCompactDurationTextUsesSingleMajorUnit() {
        XCTAssertEqual(CountdownFormatter.compactDurationText(45 * minute), "45m")
        XCTAssertEqual(CountdownFormatter.compactDurationText(hour + 30 * minute), "1.5h")
        XCTAssertEqual(CountdownFormatter.compactDurationText(2 * day + 3 * hour), "2d")
    }

    // Same handoff as the menu bar: a unit is abandoned before its value reaches 1.0, so a
    // one-hour event reads in minutes rather than as "1h".
    func testCompactDurationTextNeverShowsOneOfAUnit() {
        XCTAssertEqual(CountdownFormatter.compactDurationText(hour), "60m")
        XCTAssertEqual(CountdownFormatter.compactDurationText(day), "24h")
    }

    func testCompactDurationTextZeroAndNegativeReadAsZeroMinutes() {
        XCTAssertEqual(CountdownFormatter.compactDurationText(0), "0m")
        XCTAssertEqual(CountdownFormatter.compactDurationText(-hour), "0m")
    }

    func testOngoingLabelIsCapitalized() {
        XCTAssertEqual(CountdownFormatter.ongoingLabel(elapsedSinceStart: 0), "Now")
        XCTAssertEqual(CountdownFormatter.ongoingLabel(elapsedSinceStart: 2 * minute), "Ongoing")
    }

    func testMenuBarDecimalTextIsCapitalized() {
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: 30), "30 Secs")
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: 2 * minute), "2 Mins")
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: hour + 30 * minute), "1.5 Hours")
    }

    // Whole numbers for >= 2 of the unit; one decimal only in the final "1.1-1.9" window.
    func testMenuBarDecimalTextWholeVersusFractional() {
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: 5 * hour), "5 Hours")
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: 2 * hour), "2 Hours")
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: hour + 18 * minute), "1.3 Hours")
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: 3 * day), "3 Days")
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: 2 * minute + 30), "2 Mins")
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: 90), "1.5 Mins")
    }

    // A unit never displays exactly 1.0 — it hands off to the next-smaller unit first.
    func testMenuBarDecimalTextNeverShowsOnePointZero() {
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: hour), "60 Mins")       // not "1 Hour"
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: minute), "60 Secs")     // not "1 Min"
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: 1.1 * hour), "1.1 Hours")
        XCTAssertEqual(CountdownFormatter.menuBarDecimalText(remaining: 1.1 * minute), "1.1 Mins")
    }
}
