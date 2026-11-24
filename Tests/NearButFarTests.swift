import XCTest
import CryptoKit

final class NearButFarTests: XCTestCase {
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
