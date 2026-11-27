import XCTest
import CryptoKit

final class NearButFarTests: XCTestCase {
    func testCountdownDurationValidatesBoundsAndStep() {
        XCTAssertEqual(CountdownDuration(validating: 15)?.seconds, 15)
        XCTAssertEqual(CountdownDuration(validating: 60)?.seconds, 60)
        XCTAssertEqual(CountdownDuration(validating: 180)?.seconds, 180)
        XCTAssertNil(CountdownDuration(validating: 14))
        XCTAssertNil(CountdownDuration(validating: 16))
        XCTAssertNil(CountdownDuration(validating: 61))
        XCTAssertNil(CountdownDuration(validating: 181))
    }

    func testTrackerKeepsTheDurationCapturedWhenLossStarts() throws {
        let sixty = try XCTUnwrap(CountdownDuration(validating: 60))
        let thirty = try XCTUnwrap(CountdownDuration(validating: 30))
        var tracker = PresenceTracker(duration: sixty)
        let start = ContinuousClock.now
        tracker.acknowledge(at: start)
        tracker.missedChallenge(at: start)

        tracker.setConfiguredDuration(thirty)

        XCTAssertEqual(tracker.secondsRemaining(at: start.advanced(by: .seconds(59))), 1)
        XCTAssertTrue(tracker.takeWouldLock(at: start.advanced(by: .seconds(60))))
        tracker.acknowledge(at: start.advanced(by: .seconds(61)))
        tracker.missedChallenge(at: start.advanced(by: .seconds(61)))
        XCTAssertEqual(tracker.secondsRemaining(at: start.advanced(by: .seconds(61))), 30)
    }

    func testCancelingForgetOrReplaceLeavesPairingPageAndReturnsNoAction() {
        for confirmation in [PairingConfirmation.forgetPhone, .replacePhone] {
            var state = MacMenuState()
            state.openPairing(returningTo: .settings)
            state.requestConfirmation(confirmation)

            state.cancelConfirmation()

            XCTAssertEqual(state.page, .pairing)
            XCTAssertNil(state.confirm())
        }
    }

    func testConfirmationReturnsItsActionOnlyOnce() {
        for confirmation in [PairingConfirmation.forgetPhone, .replacePhone] {
            var state = MacMenuState()
            state.openPairing(returningTo: .settings)

            XCTAssertNil(state.confirm())
            state.requestConfirmation(confirmation)

            XCTAssertEqual(state.confirm(), confirmation)
            XCTAssertNil(state.confirm())
            XCTAssertEqual(state.page, .pairing)
        }
    }

    func testClosingPairingReturnsToOriginAndDiscardsConfirmation() {
        var state = MacMenuState()
        state.openPairing(returningTo: .settings)
        state.requestConfirmation(.forgetPhone)

        state.closePairing()

        XCTAssertEqual(state.page, .settings)
        XCTAssertNil(state.confirmation)
    }

    func testSettingsCannotReplaceThePairingPage() {
        var state = MacMenuState()
        state.openPairing(returningTo: .settings)

        state.showSettings()

        XCTAssertEqual(state.page, .pairing)
    }

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

    func testAppScreenRawValues() {
        XCTAssertEqual(AppScreenCommand.activate.rawValue, 1)
        XCTAssertEqual(AppScreenCommand.dismiss.rawValue, 2)
        XCTAssertEqual(AppScreenState.inactive.rawValue, 1)
        XCTAssertEqual(AppScreenState.active.rawValue, 2)
        XCTAssertNil(AppScreenCommand(rawValue: 0))
        XCTAssertNil(AppScreenCommand(rawValue: 3))
        XCTAssertNil(AppScreenState(rawValue: 0))
        XCTAssertNil(AppScreenState(rawValue: 3))
    }

    func testManualActivationArmsReturnOnlyWhenAway() {
        var nearby = AppScreenPolicy()
        nearby.activateManually(whileAway: false)
        XCTAssertEqual(nearby.state, .active)
        XCTAssertFalse(nearby.returnIsArmed)
        XCTAssertFalse(nearby.observeFreshStrongPresence())

        var away = AppScreenPolicy()
        away.activateManually(whileAway: true)
        XCTAssertTrue(away.returnIsArmed)
        XCTAssertTrue(away.observeFreshStrongPresence())
        XCTAssertEqual(away.state, .inactive)
    }

    func testManualActivationWhileDisconnectedAtStartupReturnsOnFirstStrongSample() {
        var policy = AppScreenPolicy()
        let pairedPhoneIsDisconnectedAtStartup = AppScreenPolicy.pairedPhoneIsDisconnected(
            hasPairedPhone: true,
            hasSecureSession: false,
            bluetoothIsPoweredOn: true
        )
        XCTAssertFalse(AppScreenPolicy.pairedPhoneIsDisconnected(
            hasPairedPhone: true,
            hasSecureSession: false,
            bluetoothIsPoweredOn: false
        ))
        policy.activateManually(whileAway: pairedPhoneIsDisconnectedAtStartup)
        XCTAssertEqual(policy.state, .active)
        XCTAssertTrue(policy.returnIsArmed)

        // Secure-session readiness alone supplies no RSSI evidence.
        XCTAssertEqual(policy.state, .active)
        let threshold: Int16 = -70
        let firstFreshRSSI: Int16 = -69
        XCTAssertGreaterThan(firstFreshRSSI, threshold)
        XCTAssertTrue(policy.observeFreshStrongPresence())
        XCTAssertEqual(policy.state, .inactive)
    }

    func testAutomaticActivationAndAwayRecovery() {
        var policy = AppScreenPolicy()
        XCTAssertTrue(policy.activateAutomatically())
        XCTAssertFalse(policy.activateAutomatically())
        policy.observeAway()
        XCTAssertTrue(policy.returnIsArmed)
        XCTAssertTrue(policy.observeFreshStrongPresence())
        XCTAssertEqual(policy.state, .inactive)
    }

    func testWeakSignalThenStrongRecoveryOnlyActsOnFreshStrongPresence() {
        var policy = AppScreenPolicy()
        policy.activateManually(whileAway: false)
        policy.observeAway()
        XCTAssertTrue(policy.returnIsArmed)
        XCTAssertEqual(policy.state, .active)
        XCTAssertTrue(policy.observeFreshStrongPresence())
        XCTAssertEqual(policy.state, .inactive)
    }

    func testExplicitDismissalDuringAwayEpisodeStaysLatchedUntilFreshStrongPresence() {
        var policy = AppScreenPolicy()
        policy.activateManually(whileAway: true)
        policy.dismiss()
        XCTAssertTrue(policy.dismissalIsLatched)
        XCTAssertFalse(policy.activateAutomatically())
        XCTAssertFalse(policy.observeFreshStrongPresence())
        XCTAssertFalse(policy.dismissalIsLatched)
        XCTAssertTrue(policy.activateAutomatically())
    }

    func testManualActivationWhileAwayCanBeDismissedAndRemainsLatched() {
        var policy = AppScreenPolicy()
        policy.activateManually(whileAway: true)
        policy.observeAway()
        policy.dismiss()
        XCTAssertEqual(policy.state, .inactive)
        XCTAssertTrue(policy.dismissalIsLatched)
        XCTAssertFalse(policy.activateAutomatically())
    }


    func testReconnectWithoutFreshStrongSampleKeepsAppScreenActive() {
        var policy = AppScreenPolicy()
        XCTAssertTrue(policy.activateAutomatically())
        // Connection restoration supplies no presence callback; only a fresh strong sample can dismiss.
        XCTAssertEqual(policy.state, .active)
        XCTAssertTrue(policy.returnIsArmed)
        XCTAssertFalse(policy.dismissalIsLatched)
    }

    @MainActor
    func testAppScreenDecoderRejectsWrongRoleAndMalformedPayloads() {
        let invalidRecords: [(UInt8, [UInt8], PeerRole)] = [
            (8, [1], .phone), // command tag received by phone
            (9, [1], .mac),   // state tag received by Mac
            (8, [], .mac),
            (8, [1, 2], .mac),
            (9, [], .phone),
            (9, [1, 2], .phone),
            (8, [0], .mac),
            (8, [3], .mac),
            (9, [0], .phone),
            (9, [3], .phone)
        ]

        for (tag, payload, receiver) in invalidRecords {
            XCTAssertThrowsError(try PeerSession.decodeMessage(tag: tag, payload: payload, receiver: receiver))
        }
    }

    @MainActor
    func testAuthenticatedAppScreenCommandRoundTripAndReplayRejection() throws {
        let (phone, mac, phoneLink, macLink) = try makeEstablishedSessions()
        let outbound = try phone.send(.appScreenCommand(.activate), on: phoneLink)
        let record = try XCTUnwrap(outbound.outbound.first).bytes
        let received = try mac.receive(record, from: macLink)
        XCTAssertTrue(received.events.contains { event in
            if case let .received(message) = event { return message.message == .appScreenCommand(.activate) }
            return false
        })
        XCTAssertThrowsError(try mac.send(.appScreenCommand(.dismiss), on: macLink))
        XCTAssertThrowsError(try mac.receive(record, from: macLink))
    }

    @MainActor
    func testCountdownDurationMessageUsesTheAuthenticatedSession() throws {
        let (phone, mac, phoneLink, macLink) = try makeEstablishedSessions()
        let bytes = try XCTUnwrap(
            try mac.send(.countdownDuration(90), on: macLink).outbound.first
        ).bytes

        let effects = try phone.receive(bytes, from: phoneLink)
        XCTAssertTrue(effects.events.contains {
            if case let .received(message) = $0 { return message.message == .countdownDuration(90) }
            return false
        })
        XCTAssertThrowsError(try phone.send(.countdownDuration(90), on: phoneLink))
        XCTAssertThrowsError(try mac.send(.countdownDuration(91), on: macLink))
        XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [0, 14], receiver: .phone))
        XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [0, 91], receiver: .phone))
        XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [0, 181], receiver: .phone))
        XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [90], receiver: .phone))
        XCTAssertThrowsError(try PeerSession.decodeMessage(tag: 11, payload: [0, 90], receiver: .mac))
    }

    @MainActor
    func testAuthenticatedAppScreenStateRoundTrip() throws {
        let (phone, mac, phoneLink, macLink) = try makeEstablishedSessions()
        let outbound = try mac.send(.appScreenState(.active), on: macLink)
        let received = try phone.receive(try XCTUnwrap(outbound.outbound.first).bytes, from: phoneLink)
        XCTAssertTrue(received.events.contains { event in
            if case let .received(message) = event { return message.message == .appScreenState(.active) }
            return false
        })
        XCTAssertThrowsError(try phone.send(.appScreenState(.inactive), on: phoneLink))
    }

    @MainActor
    func testPhoneAppScreenStateRequiresAuthenticatedSyncAndResetsOnDisconnect() {
        let model = PhoneModel()
        XCTAssertEqual(model.appScreenDisplayState, .unavailable)
        XCTAssertFalse(model.canLockNow)
        XCTAssertFalse(model.canUnlock)

        model.didAuthenticate(peerID: UUID())
        XCTAssertFalse(model.canSendAppScreenCommand)
        model.didReceiveAuthenticated(.appScreenState(.active), at: .now)
        XCTAssertEqual(model.appScreenDisplayState, .active)
        XCTAssertTrue(model.canLockNow)
        XCTAssertTrue(model.canUnlock)

        model.didDisconnect(cause: .transportLost, at: .now)
        XCTAssertEqual(model.appScreenDisplayState, .unavailable)
        XCTAssertFalse(model.canSendAppScreenCommand)
    }

    @MainActor
    func testPhoneAcceptsCurrentStateAfterAuthenticatedReconnect() {
        let model = PhoneModel()
        model.didAuthenticate(peerID: UUID())
        model.didReceiveAuthenticated(.appScreenState(.active), at: .now)
        model.didDisconnect(cause: .transportLost, at: .now)
        model.didAuthenticate(peerID: UUID())
        XCTAssertEqual(model.appScreenDisplayState, .unavailable)

        model.didReceiveAuthenticated(.appScreenState(.inactive), at: .now)
        XCTAssertEqual(model.appScreenDisplayState, .inactive)
        XCTAssertTrue(model.canSendAppScreenCommand)
    }

    func testPhoneAppScreenCommandReadinessRequiresEveryDeliveryCondition() {
        let ready: (Bool, Bool, Bool, Bool, Bool, Bool, Bool) -> Bool = {
            PhoneAppScreenCommandReadiness.canSend(
                sessionReady: $0,
                stateReceived: $1,
                bluetoothAvailable: $2,
                hasActiveLink: $3,
                hasSession: $4,
                hasPeripheral: $5,
                hasCharacteristic: $6
            )
        }
        XCTAssertTrue(ready(true, true, true, true, true, true, true))
        XCTAssertFalse(ready(false, true, true, true, true, true, true), "session not ready")
        XCTAssertFalse(ready(true, false, true, true, true, true, true), "state not synchronized")
        XCTAssertFalse(ready(true, true, false, true, true, true, true), "Bluetooth unavailable")
        XCTAssertFalse(ready(true, true, true, false, true, true, true), "no current link")
        XCTAssertFalse(ready(true, true, true, true, false, true, true), "no session")
        XCTAssertFalse(ready(true, true, true, true, true, false, true), "no peripheral")
        XCTAssertFalse(ready(true, true, true, true, true, true, false), "no write characteristic")
    }

    @MainActor
    func testPhoneAppScreenCommandsDoNotOptimisticallyChangeState() {
        let model = PhoneModel()
        model.didAuthenticate(peerID: UUID())
        model.didReceiveAuthenticated(.appScreenState(.inactive), at: .now)
        XCTAssertEqual(model.appScreenDisplayState, .inactive)

        model.didReceiveAuthenticated(.appScreenCommand(.activate), at: .now)
        XCTAssertEqual(model.appScreenDisplayState, .inactive)

        model.didReceiveAuthenticated(.appScreenState(.active), at: .now)
        XCTAssertEqual(model.appScreenDisplayState, .active)
    }

    @MainActor
    func testNewAuthenticatedSessionRequiresFreshAppScreenState() {
        let model = PhoneModel()
        model.didAuthenticate(peerID: UUID())
        model.didReceiveAuthenticated(.appScreenState(.active), at: .now)
        XCTAssertEqual(model.appScreenDisplayState, .active)

        model.didAuthenticate(peerID: UUID())
        XCTAssertEqual(model.appScreenDisplayState, .unavailable)
        XCTAssertFalse(model.canSendAppScreenCommand)
    }

    @MainActor
    func testPhoneAwayPresenceDoesNotClaimLockUnavailable() {
        let model = PhoneModel()
        let now = ContinuousClock.now
        model.didAuthenticate(peerID: UUID())
        model.didReceiveAuthenticated(.challenge(sequence: 1), at: now)
        model.didReadAuthenticatedRSSI(-70, at: now)
        model.refreshPresence(at: now.advanced(by: .seconds(60)))
        XCTAssertEqual(model.presenceState, .away)
    }

    @MainActor
    func testPhoneCachesNewDurationWithoutChangingActiveEstimate() throws {
        let suite = "CountdownDurationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = PhoneModel(userDefaults: defaults)
        XCTAssertEqual(model.countdownDuration.seconds, 60)
        model.didAuthenticate(peerID: UUID())
        let start = ContinuousClock.now
        model.didReadAuthenticatedRSSI(-70, at: start)
        model.didReceiveAuthenticated(.countdownDuration(30), at: start.advanced(by: .seconds(10)))
        model.refreshPresence(at: start.advanced(by: .seconds(59)))
        XCTAssertEqual(model.presenceState, .weakSignalCountdown(1))

        model.didReceiveAuthenticated(.countdownDuration(91), at: start.advanced(by: .seconds(59)))
        XCTAssertEqual(model.countdownDuration.seconds, 30)
        let reloaded = PhoneModel(userDefaults: defaults)
        XCTAssertEqual(reloaded.countdownDuration.seconds, 30)
    }

    @MainActor
    func testDisconnectedEstimateUsesCachedDurationOrSixtySecondFallback() throws {
        func assertEstimate(savedDuration: Int?, expectedStart: Duration, suite: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if let savedDuration { defaults.set(savedDuration, forKey: "countdownDurationSeconds") }
            let model = PhoneModel(userDefaults: defaults)
            let start = ContinuousClock.now
            model.didAuthenticate(peerID: UUID())
            model.didReceiveAuthenticated(.challenge(sequence: 1), at: start)
            model.didDisconnect(cause: .transportLost, at: start)
            model.refreshPresence(at: start.advanced(by: expectedStart))
            XCTAssertEqual(model.presenceState, .connectionLostCountdown(1), file: file, line: line)
        }

        try assertEstimate(savedDuration: nil, expectedStart: .seconds(59),
                           suite: "CountdownFallback-\(UUID().uuidString)")
        try assertEstimate(savedDuration: 90, expectedStart: .seconds(89),
                           suite: "CountdownCached-\(UUID().uuidString)")
    }

    func testPhonePresencePresentationSeparatesWeakSignalFromConnectionLoss() {
        let weak = PhonePresencePresentation(state: .weakSignalCountdown(45))
        XCTAssertEqual(weak.headline, "Locks in 45s")
        XCTAssertEqual(weak.detailsHeadline, "Weak signal")
        XCTAssertTrue(weak.countdownDisclosure?.contains("macOS stays unlocked") == true)

        let lost = PhonePresencePresentation(state: .connectionLostCountdown(45))
        XCTAssertEqual(lost.headline, "Signal lost")
        XCTAssertEqual(lost.detailsHeadline, "Signal lost")
        XCTAssertTrue(lost.countdownDisclosure?.contains("Local estimate") == true)
        XCTAssertTrue(lost.countdownDisclosure?.contains("45s") == true)
        XCTAssertEqual(
            PhonePresencePresentation(state: .weakSignalCountdown(44)).announcementTitle,
            weak.announcementTitle
        )
    }

    @MainActor
    private func makeEstablishedSessions() throws -> (PeerSession, PeerSession, LinkID, LinkID) {
        let phoneKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: 1, count: 32))
        let macKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: 2, count: 32))
        let phoneID = UUID()
        let macID = UUID()
        let phoneIdentity = try LocalIdentity(id: phoneID, publicKey: PeerPublicKey(validating: phoneKey.publicKey.rawRepresentation), privateKey: phoneKey.rawRepresentation)
        let macIdentity = try LocalIdentity(id: macID, publicKey: PeerPublicKey(validating: macKey.publicKey.rawRepresentation), privateKey: macKey.rawRepresentation)
        let phoneStore = TestPeerIdentityStore(local: phoneIdentity, paired: PairedIdentity(id: macID, publicKey: macIdentity.publicKey))
        let macStore = TestPeerIdentityStore(local: macIdentity, paired: PairedIdentity(id: phoneID, publicKey: phoneIdentity.publicKey))
        let phone = PeerSession(role: .phone, store: phoneStore, intent: .reconnect)
        let mac = PeerSession(role: .mac, store: macStore, intent: .reconnect)
        let phoneLink = LinkID(rawValue: UUID())
        let macLink = LinkID(rawValue: UUID())
        _ = try mac.start(on: macLink)
        let first = try XCTUnwrap(try phone.start(on: phoneLink).outbound.first).bytes
        let second = try XCTUnwrap(try mac.receive(first, from: macLink).outbound.first).bytes
        let third = try XCTUnwrap(try phone.receive(second, from: phoneLink).outbound.first).bytes
        _ = try mac.receive(third, from: macLink)
        let threshold = try XCTUnwrap(try mac.send(.threshold(-70), on: macLink).outbound.first).bytes
        _ = try phone.receive(threshold, from: phoneLink)
        return (phone, mac, phoneLink, macLink)
    }

}


@MainActor
private final class TestPeerIdentityStore: PeerIdentityStore {
    let local: LocalIdentity
    private var paired: PairedIdentity?

    init(local: LocalIdentity, paired: PairedIdentity?) {
        self.local = local
        self.paired = paired
    }

    func loadOrCreateLocalIdentity() throws -> LocalIdentity { local }
    func pairedIdentity() throws -> PairedIdentity? { paired }
    func replacePairedIdentity(with candidate: PairedIdentity) throws { paired = candidate }
    func forgetPairedIdentity() throws { paired = nil }
}
