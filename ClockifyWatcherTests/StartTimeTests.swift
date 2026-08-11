import XCTest
@testable import ClockifyWatcher

final class StartTimeTests: XCTestCase {

    /// Fixed UTC calendar so these tests do not depend on the machine's timezone.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day,
                                      hour: hour, minute: minute, second: second))!
    }

    func testEarlierTimeSucceedsWithSecondsZeroedOnToday() {
        let result = resolveStartTime(picked: date(2026, 8, 10, 9, 15, 30),
                                      currentStart: date(2026, 8, 10, 10, 0),
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .success(date(2026, 8, 10, 9, 15, 0)))
    }

    func testPickedDateComponentIsIgnoredInFavorOfToday() {
        // The picker can hand back any date; only the clock time is used.
        let result = resolveStartTime(picked: date(1999, 1, 1, 9, 15),
                                      currentStart: date(2026, 8, 10, 10, 0),
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .success(date(2026, 8, 10, 9, 15, 0)))
    }

    func testEqualToCurrentStartSucceeds() {
        let currentStart = date(2026, 8, 10, 10, 0)
        let result = resolveStartTime(picked: currentStart,
                                      currentStart: currentStart,
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .success(currentStart))
    }

    func testPickingTheDisplayedMinuteTrimsSecondsFromTheCurrentStart() {
        // Real Clockify starts carry seconds; picking the minute the picker displays
        // for the current start is a success that trims those seconds away.
        let result = resolveStartTime(picked: date(2026, 8, 10, 10, 0),
                                      currentStart: date(2026, 8, 10, 10, 0, 37),
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .success(date(2026, 8, 10, 10, 0, 0)))
    }

    func testLaterThanCurrentStartFails() {
        let result = resolveStartTime(picked: date(2026, 8, 10, 10, 45),
                                      currentStart: date(2026, 8, 10, 10, 0),
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .failure(.notEarlier))
    }

    func testYesterdayStartRejectsEveryTimeToday() {
        // An overnight timer cannot be edited: every time today is later than
        // yesterday's start, so it is rejected rather than losing a day.
        let result = resolveStartTime(picked: date(2026, 8, 10, 9, 15),
                                      currentStart: date(2026, 8, 9, 23, 0),
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .failure(.notEarlier))
    }
}
