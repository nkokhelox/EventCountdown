import XCTest

final class CountdownScheduleTests: XCTestCase {
    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 60 * 60
    private let day: TimeInterval = 24 * 60 * 60

    // Seconds until the next scheduled change for an upcoming event `remaining` away.
    private func step(startIn remaining: TimeInterval, now: Date = Date()) -> TimeInterval {
        let start = now.addingTimeInterval(remaining)
        let end = start.addingTimeInterval(hour)
        let next = CountdownSchedule.nextChange(now: now, startDate: start, endDate: end, hasStarted: false)
        return next.timeIntervalSince(now)
    }

    func testNoEventReturnsDistantFuture() {
        let next = CountdownSchedule.nextChange(now: Date(), startDate: nil, endDate: nil, hasStarted: false)
        XCTAssertEqual(next, .distantFuture)
    }

    // 5 days out lands exactly on a 0.1-day boundary, so the next change is a full
    // 5 days shows a whole number (>= 2 days), so the cadence is a whole day, not seconds.
    func testFiveDaysOutStepsByWholeDay() {
        XCTAssertEqual(step(startIn: 5 * day), day, accuracy: 1)
    }

    // Mid-bucket: 5.3 days re-arms when it drops to the next whole day (0.3 day away).
    func testDaysMidBucketReArmsAtNextWholeDay() {
        XCTAssertEqual(step(startIn: 5 * day + 0.3 * day), 0.3 * day, accuracy: 1)
    }

    // 3 hours shows a whole number (>= 2 hours), so the cadence is a whole hour.
    func testThreeHoursStepByWholeHour() {
        XCTAssertEqual(step(startIn: 3 * hour), hour, accuracy: 1)
    }

    // 90 min is the final "1.x hours" window (< 2 hours) -> decimal shown, 0.1h = 6 min steps.
    func testNinetyMinutesStepsByTenthOfAnHour() {
        XCTAssertEqual(step(startIn: 90 * minute), hour / 10, accuracy: 1)
    }

    // 3 min shows a whole number (>= 2 minutes) -> whole-minute (60s) steps.
    func testThreeMinutesStepsByWholeMinute() {
        XCTAssertEqual(step(startIn: 3 * minute), minute, accuracy: 0.5)
    }

    // 90 seconds is the final "1.x minutes" window (< 2 minutes) -> 0.1 min = 6s steps.
    func testNinetySecondsStepsByTenthOfAMinute() {
        XCTAssertEqual(step(startIn: 90), minute / 10, accuracy: 0.2)
    }

    // Under a minute: whole-second cadence, aligned to the next whole-second boundary.
    func testUnderAMinuteAlignsToWholeSecondBoundary() {
        let s = step(startIn: 45.3)
        XCTAssertGreaterThan(s, 0)
        XCTAssertLessThanOrEqual(s, 1.0)
        XCTAssertEqual(s, 0.3, accuracy: 0.05)
    }

    // At/after start: about to flip to "Now", re-check almost immediately.
    func testAtStartFiresAlmostImmediately() {
        XCTAssertLessThanOrEqual(step(startIn: 0), 0.3)
    }

    // Ongoing < ackNowDisplaySeconds: next change is the "Now" -> "Ongoing" flip.
    func testOngoingBeforeNowMarkFiresAtNowMark() {
        let now = Date()
        let start = now.addingTimeInterval(-10)
        let end = now.addingTimeInterval(hour)
        let next = CountdownSchedule.nextChange(now: now, startDate: start, endDate: end, hasStarted: true)
        XCTAssertEqual(next.timeIntervalSince(start), AppConstants.ackNowDisplaySeconds, accuracy: 0.001)
    }

    // Ongoing past the "Now" window: "Ongoing" is static until the event ends.
    func testOngoingAfterNowMarkFiresAtEnd() {
        let now = Date()
        let start = now.addingTimeInterval(-(AppConstants.ackNowDisplaySeconds + 30))
        let end = now.addingTimeInterval(30 * minute)
        let next = CountdownSchedule.nextChange(now: now, startDate: start, endDate: end, hasStarted: true)
        XCTAssertEqual(next, end)
    }
}
