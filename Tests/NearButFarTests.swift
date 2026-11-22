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
        let now = Date(timeIntervalSince1970: 100)
        tracker.missedChallenge(at: now)
        XCTAssertNil(tracker.secondsRemaining(at: now))
        XCTAssertFalse(tracker.takeWouldLock(at: now.addingTimeInterval(120)))
    }

    func testPresenceTimerBoundaryAndOneShot() {
        var tracker = PresenceTracker()
        let now = Date(timeIntervalSince1970: 100)
        tracker.acknowledge(at: now)
        tracker.missedChallenge(at: now.addingTimeInterval(5))
        XCTAssertFalse(tracker.takeWouldLock(at: now.addingTimeInterval(64.999)))
        XCTAssertTrue(tracker.takeWouldLock(at: now.addingTimeInterval(65)))
        XCTAssertFalse(tracker.takeWouldLock(at: now.addingTimeInterval(70)))
    }

    func testAcknowledgementCancelsGracePeriod() {
        var tracker = PresenceTracker()
        let now = Date(timeIntervalSince1970: 100)
        tracker.acknowledge(at: now)
        tracker.missedChallenge(at: now.addingTimeInterval(5))
        tracker.acknowledge(at: now.addingTimeInterval(20))
        XCTAssertNil(tracker.secondsRemaining(at: now.addingTimeInterval(20)))
        XCTAssertFalse(tracker.takeWouldLock(at: now.addingTimeInterval(100)))
    }

    func testLaterMissStartsANewGracePeriodAfterRecovery() {
        var tracker = PresenceTracker()
        let now = Date(timeIntervalSince1970: 100)
        tracker.acknowledge(at: now)
        tracker.missedChallenge(at: now.addingTimeInterval(5))
        XCTAssertTrue(tracker.takeWouldLock(at: now.addingTimeInterval(65)))

        tracker.acknowledge(at: now.addingTimeInterval(70))
        tracker.missedChallenge(at: now.addingTimeInterval(75))
        XCTAssertFalse(tracker.takeWouldLock(at: now.addingTimeInterval(134.999)))
        XCTAssertTrue(tracker.takeWouldLock(at: now.addingTimeInterval(135)))
    }

    func testWeakRSSIAtThresholdStartsSixtySecondCountdown() {
        var tracker = PresenceTracker()
        let now = Date(timeIntervalSince1970: 100)

        tracker.observeRSSI(-70, at: now)

        XCTAssertTrue(tracker.isArmed)
        XCTAssertEqual(tracker.secondsRemaining(at: now), 60)
    }

    func testStrongerRSSICancelsWeakSignalCountdown() {
        var tracker = PresenceTracker()
        let now = Date(timeIntervalSince1970: 100)
        tracker.observeRSSI(-72, at: now)

        tracker.observeRSSI(-69, at: now.addingTimeInterval(10))

        XCTAssertNil(tracker.secondsRemaining(at: now.addingTimeInterval(10)))
    }

    func testRepeatedWeakRSSIDoesNotRestartCountdown() {
        var tracker = PresenceTracker()
        let now = Date(timeIntervalSince1970: 100)
        tracker.observeRSSI(-70, at: now)

        tracker.observeRSSI(-75, at: now.addingTimeInterval(10))

        XCTAssertEqual(tracker.secondsRemaining(at: now.addingTimeInterval(10)), 50)
    }

    func testMissingRSSIDoesNotClearWeakSignalCountdown() {
        var tracker = PresenceTracker()
        let now = Date(timeIntervalSince1970: 100)
        tracker.observeRSSI(-70, at: now)

        tracker.observeRSSI(nil, at: now.addingTimeInterval(10))

        XCTAssertEqual(tracker.secondsRemaining(at: now.addingTimeInterval(10)), 50)
    }

    func testWeakRSSIReportsWouldLockOnceAfterSixtySeconds() {
        var tracker = PresenceTracker()
        let now = Date(timeIntervalSince1970: 100)
        tracker.observeRSSI(-70, at: now)

        XCTAssertFalse(tracker.takeWouldLock(at: now.addingTimeInterval(59.999)))
        XCTAssertTrue(tracker.takeWouldLock(at: now.addingTimeInterval(60)))
        XCTAssertFalse(tracker.takeWouldLock(at: now.addingTimeInterval(61)))
    }
}
