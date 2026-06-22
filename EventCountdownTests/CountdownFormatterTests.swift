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
        XCTAssertEqual(value.value, 3)
    }

    func testExactlyTwoYearsUsesMonths() {
        let value = CountdownFormatter.format(remaining: 2 * year)
        XCTAssertEqual(value.unit, .months)
        XCTAssertEqual(value.value, 25)
    }

    func testExactlyThreeMonthsUsesWeeks() {
        let value = CountdownFormatter.format(remaining: 3 * month)
        XCTAssertEqual(value.unit, .weeks)
    }

    func testExactlyTwoWeeksUsesDays() {
        let value = CountdownFormatter.format(remaining: 2 * week)
        XCTAssertEqual(value.unit, .days)
    }

    func testExactlyTwoDaysUsesHours() {
        let value = CountdownFormatter.format(remaining: 2 * day)
        XCTAssertEqual(value.unit, .hours)
    }

    func testExactlyTwoHoursUsesMinutes() {
        let value = CountdownFormatter.format(remaining: 2 * hour)
        XCTAssertEqual(value.unit, .minutes)
    }

    func testExactlyOneMinuteUsesSeconds() {
        let value = CountdownFormatter.format(remaining: minute)
        XCTAssertEqual(value.unit, .seconds)
    }

    func testZeroOrNegativeIsPast() {
        let value = CountdownFormatter.format(remaining: 0)
        XCTAssertTrue(value.isPast)
    }
}
