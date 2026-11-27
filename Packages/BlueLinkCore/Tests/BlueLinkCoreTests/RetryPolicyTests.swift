import XCTest
@testable import BlueLinkCore

final class RetryPolicyTests: XCTestCase {
    func testDefaultBudgetIsFirstAttemptPlusFourRetries() {
        let policy = RetryPolicy()
        XCTAssertEqual(policy.maximumAttempts, 5)
        var delays: [Duration] = []
        for attempt in 1...4 {
            guard let delay = policy.delay(afterCompletedAttempts: attempt, randomUnit: 0.5) else {
                return XCTFail("missing delay for attempt \(attempt)")
            }
            delays.append(delay)
        }
        XCTAssertEqual(delays, [.seconds(1), .seconds(2), .seconds(4), .seconds(8)])
        XCTAssertNil(policy.delay(afterCompletedAttempts: 5, randomUnit: 0.5))
    }

    func testJitterStaysWithinBounds() {
        let policy = RetryPolicy(jitterFraction: 0.1)
        let low = policy.delay(afterCompletedAttempts: 1, randomUnit: 0)!
        let high = policy.delay(afterCompletedAttempts: 1, randomUnit: 0.999_999)!
        XCTAssertGreaterThanOrEqual(low, .milliseconds(900))
        XCTAssertLessThanOrEqual(high, .milliseconds(1_100))
    }

    func testZeroJitterIsDeterministic() {
        let policy = RetryPolicy(jitterFraction: 0)
        XCTAssertEqual(policy.delay(afterCompletedAttempts: 2, randomUnit: 0.9), .seconds(2))
    }

    func testTotalWindow() {
        XCTAssertEqual(RetryPolicy().totalWindow, .seconds(15))
    }
}
