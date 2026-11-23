import XCTest

final class NearButFarTests: XCTestCase {
    func testChallengeRoundTrip() {
        XCTAssertEqual(BLEProtocol.decodeChallenge(BLEProtocol.encodeChallenge(0x1234ABCD)), 0x1234ABCD)
        XCTAssertNil(BLEProtocol.decodeChallenge(Data([1, 2, 3])))
    }

    func testAcknowledgementPreservesNegativeRSSI() {
        let data = BLEProtocol.encodeAcknowledgement(sequence: 12, rssi: -67)
        XCTAssertEqual(BLEProtocol.decodeAcknowledgement(data), .init(sequence: 12, rssi: -67))
    }

    func testAcknowledgementCanOmitRSSI() {
        let data = BLEProtocol.encodeAcknowledgement(sequence: 1, rssi: nil)
        XCTAssertEqual(BLEProtocol.decodeAcknowledgement(data), .init(sequence: 1, rssi: nil))
        XCTAssertNil(BLEProtocol.decodeAcknowledgement(Data([0, 1])))
    }

    func testPresenceTimerStartsOnlyAfterFirstAcknowledgement() {
        var tracker = PresenceTracker()
        let now = ContinuousClock.now
        tracker.missedChallenge(at: now)
        XCTAssertNil(tracker.secondsRemaining(at: now))
        XCTAssertFalse(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(120000))))
    }

    func testPresenceTimerBoundaryAndOneShot() {
        var tracker = PresenceTracker()
        let now = ContinuousClock.now
        tracker.acknowledge(at: now)
        tracker.missedChallenge(at: now.advanced(by: .milliseconds(5000)))
        XCTAssertFalse(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(64999))))
        XCTAssertTrue(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(65000))))
        XCTAssertFalse(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(70000))))
    }

    func testAcknowledgementCancelsGracePeriod() {
        var tracker = PresenceTracker()
        let now = ContinuousClock.now
        tracker.acknowledge(at: now)
        tracker.missedChallenge(at: now.advanced(by: .milliseconds(5000)))
        tracker.acknowledge(at: now.advanced(by: .milliseconds(20000)))
        XCTAssertNil(tracker.secondsRemaining(at: now.advanced(by: .milliseconds(20000))))
        XCTAssertFalse(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(100000))))
    }

    func testLaterMissStartsANewGracePeriodAfterRecovery() {
        var tracker = PresenceTracker()
        let now = ContinuousClock.now
        tracker.acknowledge(at: now)
        tracker.missedChallenge(at: now.advanced(by: .milliseconds(5000)))
        XCTAssertTrue(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(65000))))

        tracker.acknowledge(at: now.advanced(by: .milliseconds(70000)))
        tracker.missedChallenge(at: now.advanced(by: .milliseconds(75000)))
        XCTAssertFalse(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(134999))))
        XCTAssertTrue(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(135000))))
    }

    func testWeakRSSIAtThresholdStartsSixtySecondCountdown() {
        var tracker = PresenceTracker()
        let now = ContinuousClock.now

        tracker.observeRSSI(-70, at: now)

        XCTAssertTrue(tracker.isArmed)
        XCTAssertEqual(tracker.secondsRemaining(at: now), 60)
    }

    func testStrongerRSSICancelsWeakSignalCountdown() {
        var tracker = PresenceTracker()
        let now = ContinuousClock.now
        tracker.observeRSSI(-72, at: now)

        tracker.observeRSSI(-69, at: now.advanced(by: .milliseconds(10000)))

        XCTAssertNil(tracker.secondsRemaining(at: now.advanced(by: .milliseconds(10000))))
    }

    func testRepeatedWeakRSSIDoesNotRestartCountdown() {
        var tracker = PresenceTracker()
        let now = ContinuousClock.now
        tracker.observeRSSI(-70, at: now)

        tracker.observeRSSI(-75, at: now.advanced(by: .milliseconds(10000)))

        XCTAssertEqual(tracker.secondsRemaining(at: now.advanced(by: .milliseconds(10000))), 50)
    }

    func testMissingRSSIDoesNotClearWeakSignalCountdown() {
        var tracker = PresenceTracker()
        let now = ContinuousClock.now
        tracker.observeRSSI(-70, at: now)

        tracker.observeRSSI(nil, at: now.advanced(by: .milliseconds(10000)))

        XCTAssertEqual(tracker.secondsRemaining(at: now.advanced(by: .milliseconds(10000))), 50)
    }

    func testClearingMonitoringEpochKeepsChallengeIDsMonotonic() throws {
        var schedule = ChallengeSchedule()
        let now = ContinuousClock.now
        let first = try XCTUnwrap(schedule.nextAction(at: now))
        XCTAssertEqual(first, .sendNew(sequence: 1))
        schedule.didQueue(first, at: now)

        schedule.clearPendingChallenge()

        let second = try XCTUnwrap(schedule.nextAction(at: now.advanced(by: .seconds(1))))
        XCTAssertEqual(second, .sendNew(sequence: 2))
        schedule.didQueue(second, at: now.advanced(by: .seconds(1)))
        schedule.acknowledge(1, at: now.advanced(by: .seconds(2)))

        XCTAssertNil(schedule.nextAction(at: now.advanced(by: .seconds(3))))
        XCTAssertTrue(schedule.responseTimedOut(at: now.advanced(by: .seconds(6))))
    }

    func testWeakRSSIReportsWouldLockOnceAfterSixtySeconds() {
        var tracker = PresenceTracker()
        let now = ContinuousClock.now
        tracker.observeRSSI(-70, at: now)

        XCTAssertFalse(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(59999))))
        XCTAssertTrue(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(60000))))
        XCTAssertFalse(tracker.takeWouldLock(at: now.advanced(by: .milliseconds(61000))))
    }
}
