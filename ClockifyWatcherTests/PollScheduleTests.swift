import XCTest
@testable import ClockifyWatcher

final class PollScheduleTests: XCTestCase {

    // MARK: - Steady state

    func testBaseIntervalStaysUnderTheFreePlanHourlyBudget() {
        // 30 requests/hour is the cap; the poll alone must leave room for menu actions.
        let requestsPerHour = 3600 / basePollInterval
        XCTAssertLessThan(requestsPerHour, 30)
        XCTAssertGreaterThanOrEqual(requestsPerHour, 12, "polling this slowly is not useful")
    }

    func testSuccessPollsAtBaseInterval() {
        XCTAssertEqual(nextPollDelay(after: .success, consecutiveRateLimits: 0), basePollInterval)
    }

    func testSuccessResetsBackoffEvenAfterManyRateLimits() {
        XCTAssertEqual(nextPollDelay(after: .success, consecutiveRateLimits: 9), basePollInterval)
    }

    func testTransientFailureKeepsBaseIntervalWithoutPunishment() {
        // A dropped network request should not stall the app for minutes.
        XCTAssertEqual(nextPollDelay(after: .failed, consecutiveRateLimits: 0), basePollInterval)
    }

    // MARK: - Rate-limit backoff

    func testFirstRateLimitBacksOffWellBeyondBaseInterval() {
        let delay = nextPollDelay(after: .rateLimited(retryAfter: nil), consecutiveRateLimits: 1)
        XCTAssertGreaterThan(delay, basePollInterval)
        XCTAssertEqual(delay, 300)
    }

    func testBackoffGrowsExponentiallyWithConsecutiveRateLimits() {
        let delays = (1...5).map {
            nextPollDelay(after: .rateLimited(retryAfter: nil), consecutiveRateLimits: $0)
        }
        XCTAssertEqual(delays, [300, 600, 1200, 2400, 3600])
    }

    func testBackoffIsCappedAtOneHour() {
        // Clockify's window is hourly, so waiting longer than an hour cannot help.
        for n in 5...20 {
            XCTAssertEqual(nextPollDelay(after: .rateLimited(retryAfter: nil),
                                         consecutiveRateLimits: n), maxRateLimitBackoff)
        }
    }

    func testServerRetryAfterIsHonoredOverOurOwnBackoff() {
        XCTAssertEqual(nextPollDelay(after: .rateLimited(retryAfter: 900),
                                     consecutiveRateLimits: 1), 900)
    }

    func testTinyRetryAfterIsClampedUpToAvoidHammering() {
        XCTAssertEqual(nextPollDelay(after: .rateLimited(retryAfter: 1),
                                     consecutiveRateLimits: 1), minRateLimitBackoff)
    }

    func testAbsurdRetryAfterIsClampedDownSoTheAppRecovers() {
        XCTAssertEqual(nextPollDelay(after: .rateLimited(retryAfter: 86_400),
                                     consecutiveRateLimits: 1), maxRateLimitBackoff)
    }

    func testRateLimitWithZeroCountIsTreatedAsTheFirstOne() {
        // Defensive: a caller that forgets to increment must still get a real backoff.
        XCTAssertEqual(nextPollDelay(after: .rateLimited(retryAfter: nil),
                                     consecutiveRateLimits: 0), 300)
    }
}
