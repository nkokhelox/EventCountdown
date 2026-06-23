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
        XCTAssertEqual(value.menuBarText, "2hrs")
    }
}
