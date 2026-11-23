import Combine
import CryptoKit
import Foundation
import AppKit

enum PairingCapability: Equatable {
    case unavailable(String)
    case available

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

@MainActor
final class MacCoordinator: ObservableObject {
    @Published private(set) var bluetoothState = "Starting Bluetooth…"
    @Published private(set) var isSubscribed = false
    @Published private(set) var lastRSSI: Int16?
    @Published private(set) var countdown: Int?
    @Published private(set) var logPath = ""
    @Published private(set) var pairingOffer: PairingOffer?
    @Published private(set) var pairingCodeImage: NSImage?
    @Published private(set) var pairingSecondsRemaining = 0
    @Published private(set) var pairedPhoneFingerprint: String?
    @Published private(set) var pendingPhoneFingerprint: String?
    @Published private(set) var pairingStatus = ""
    @Published private(set) var pairingCapability: PairingCapability
    @Published var monitoringEnabled: Bool {
        didSet {
            UserDefaults.standard.set(monitoringEnabled, forKey: Self.monitoringPreferenceKey)
            monitoringEnabled ? beginMonitoringEpoch() : pauseMonitoring()
        }
    }
    @Published var signalThreshold: SignalThreshold {
        didSet {
            UserDefaults.standard.set(Int(signalThreshold.rawValue), forKey: Self.thresholdPreferenceKey)
            tracker.threshold = signalThreshold
            if let link = pairingLink, securePeerID != nil { sendThreshold(on: link) }
        }
    }
    @Published var isPairingPresented = false
    @Published var isConfirmingReplacement = false
    @Published var isConfirmingForget = false

    private let peripheral: MacPeripheral
    private let logger: CSVLogger?
    private let identityStore: MacPairedIdentityStore
    private var pairingSession: PeerSession?
    private var pairingLink: LinkID?
    private var candidateID: CandidateID?
    private var securePeerID: UUID?
    private var pairingExpiryTask: Task<Void, Never>?
    private var schedule = ChallengeSchedule()
    private var tracker: PresenceTracker
    private var outstandingSequence: UInt32?
    private var displayTimer: Timer?
    private var monitoringTask: Task<Void, Never>?
    private var responseWasMissed = false

    private static let monitoringPreferenceKey = "monitoringEnabled"
    private static let thresholdPreferenceKey = "signalThresholdDBm"

    var pairingAvailabilityMessage: String {
        if case let .unavailable(reason) = pairingCapability { return reason }
        return "Secure QR pairing is available on this Mac."
    }

    var canLockNow: Bool { false }
    var canUnlock: Bool { false }

    func setSignalThreshold(_ value: Int16) {
        guard let threshold = SignalThreshold(validating: value) else { return }
        signalThreshold = threshold
    }

    init(
        peripheral: MacPeripheral? = nil,
        identityStore: MacPairedIdentityStore? = nil,
        pairingCapability: PairingCapability = .available
    ) {
        self.peripheral = peripheral ?? MacPeripheral()
        self.identityStore = identityStore ?? MacPairedIdentityStore()
        self.pairingCapability = pairingCapability
        monitoringEnabled = UserDefaults.standard.bool(forKey: Self.monitoringPreferenceKey)
        let storedThreshold = UserDefaults.standard.object(forKey: Self.thresholdPreferenceKey) as? Int
        let initialThreshold = storedThreshold.flatMap { SignalThreshold(validating: Int16(clamping: $0)) } ?? .default
        signalThreshold = initialThreshold
        tracker = PresenceTracker(threshold: initialThreshold)
        do {
            logger = try CSVLogger()
            logPath = logger?.fileURL.path ?? ""
        } catch {
            logger = nil
            bluetoothState = "Log unavailable: \(error.localizedDescription)"
        }
        do {
            pairedPhoneFingerprint = Self.fingerprint(try self.identityStore.pairedIdentity()?.publicKey)
        } catch {
            self.pairingStatus = "Secure identity storage is unavailable."
            self.pairingCapability = .unavailable(self.pairingStatus)
        }
        self.peripheral.onEvent = { [weak self] event in self?.handle(event) }
        if monitoringEnabled { beginMonitoringEpoch() }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshDisplay() }
        }
    }

    func requestPairing() {
        guard pairingCapability.isAvailable else {
            pairingStatus = pairingAvailabilityMessage
            isPairingPresented = true
            return
        }
        isPairingPresented = true
        do {
            if try identityStore.pairedIdentity() != nil {
                isConfirmingReplacement = true
                return
            }
            beginPairing()
        } catch {
            pairingStatus = "Could not read the paired phone from Keychain."
            pairingCapability = .unavailable("Secure identity storage is unavailable.")
            isPairingPresented = true
        }
    }

    func updatePairingCapability(_ capability: PairingCapability) {
        pairingCapability = capability
        guard !capability.isAvailable else { return }
        closePairingSession()
        cancelPairingOffer(status: pairingAvailabilityMessage)
    }

    func confirmReplacementAndPair() {
        guard pairingCapability.isAvailable else {
            pairingStatus = pairingAvailabilityMessage
            return
        }
        do {
            closePairingSession()
            try identityStore.forgetPairedIdentity()
            pairedPhoneFingerprint = nil
            beginPairing()
        } catch {
            pairingStatus = "Could not replace the paired phone. Check Keychain access and try again."
            isPairingPresented = true
        }
    }

    func requestForgetPhone() {
        isConfirmingForget = true
    }

    func dismissPairingDetails() {
        if pairingOffer != nil || candidateID != nil {
            cancelPairing()
            return
        }
        isPairingPresented = false
    }

    func forgetPhone() {
        closePairingSession()
        cancelPairingOffer(status: "Phone forgotten.")
        do {
            try identityStore.forgetPairedIdentity()
            pairedPhoneFingerprint = nil
            pairingStatus = "No phone is paired."
        } catch {
            pairingStatus = "Could not remove the paired phone from Keychain."
        }
        clearOperationalState()
    }

    func cancelPairing() {
        closePairingSession()
        cancelPairingOffer(status: "Pairing cancelled.")
        isPairingPresented = false
    }

    func approvePhone() throws {
        guard let session = pairingSession, let candidateID, let pairingLink else {
            throw PeerSessionError.invalidState
        }
        let effects: SessionEffects
        do { effects = try session.approvePairing(candidateID) }
        catch {
            if error as? PeerSessionError == .keychainUnavailable {
                pairingCapability = .unavailable("Secure identity storage is unavailable.")
            }
            throw error
        }
        self.candidateID = nil
        pendingPhoneFingerprint = nil
        pairingStatus = "Approval sent. Waiting for the phone to confirm pairing."
        process(effects, on: pairingLink)
    }

    private func beginSession(on link: LinkID) {
        guard pairingCapability.isAvailable, pairingSession == nil else {
            peripheral.closeSecureLink(link)
            return
        }

        let intent: SessionIntent
        if let pairingOffer {
            intent = .enrollMac(pairingOffer)
        } else {
            do {
                guard try identityStore.pairedIdentity() != nil else {
                    peripheral.closeSecureLink(link)
                    return
                }
                intent = .reconnect
            } catch {
                pairingCapability = .unavailable("Secure identity storage is unavailable.")
                peripheral.closeSecureLink(link)
                return
            }
        }

        switch intent {
        case .reconnect:
            peripheral.armAuthenticationDeadline(for: link, after: .seconds(20))
        case let .enrollMac(offer):
            let remaining = ContinuousClock.now.duration(to: offer.expiresAt)
            if remaining > .zero {
                peripheral.armAuthenticationDeadline(for: link, after: remaining)
            }
        case .enrollPhone(_):
            peripheral.closeSecureLink(link)
            return
        }

        let session = PeerSession(role: .mac, store: identityStore, intent: intent)
        pairingSession = session
        pairingLink = link
        do {
            process(try session.start(on: link), on: link)
        } catch {
            if error as? PeerSessionError == .keychainUnavailable {
                pairingCapability = .unavailable("Secure identity storage is unavailable.")
            }
            closePairingSession()
        }
    }

    private func receiveSecureRecord(_ record: Data, on link: LinkID) {
        guard let session = pairingSession, pairingLink == link else {
            peripheral.closeSecureLink(link)
            return
        }
        do {
            process(try session.receive(record, from: link), on: link)
        } catch {
            if error as? PeerSessionError == .keychainUnavailable {
                pairingCapability = .unavailable("Secure identity storage is unavailable.")
            }
            closePairingSession()
        }
    }

    private func process(_ effects: SessionEffects, on link: LinkID) {
        guard pairingLink == link else {
            peripheral.closeSecureLink(link)
            return
        }
        if !effects.outbound.isEmpty, !peripheral.send(effects.outbound, on: link) {
            closePairingSession()
            return
        }

        for event in effects.events {
            switch event {
            case let .candidate(candidate, peerStaticKey):
                candidateID = candidate
                pendingPhoneFingerprint = Self.fingerprint(peerStaticKey)
                pairingStatus = "A phone is requesting to pair."
                isPairingPresented = true
            case let .ready(peerID, _):
                guard peripheral.markAuthenticated(link) else {
                    closePairingSession()
                    return
                }
                securePeerID = peerID
                pairedPhoneFingerprint = Self.fingerprint(try? identityStore.pairedIdentity()?.publicKey)
                pairingStatus = "The phone authenticated. Waiting for a fresh verified presence message."
                sendThreshold(on: link)
                if monitoringEnabled { beginMonitoringEpoch() }
                else { pauseMonitoring() }
                pairingExpiryTask?.cancel()
                pairingExpiryTask = nil
                pairingOffer?.invalidate()
                pairingOffer = nil
                pairingCodeImage = nil
                pairingSecondsRemaining = 0
                logger?.log("authenticated_session_ready")
            case let .received(verified):
                handleVerifiedMessage(verified, on: link)
            case let .closed(error):
                pairingStatus = error == .pairingExpired
                    ? "The pairing code expired. Start again to create a new one."
                    : "Pairing could not be completed. Start again to try again."
                closePairingSession()
                if pairingOffer != nil { cancelPairingOffer(status: pairingStatus) }
                return
            case .pairingDisplayCleared:
                pairingExpiryTask?.cancel()
                pairingExpiryTask = nil
                pairingOffer?.invalidate()
                pairingOffer = nil
                pairingCodeImage = nil
                pairingSecondsRemaining = 0
            }
        }
    }

    private func handleVerifiedMessage(_ verified: VerifiedMessage, on link: LinkID) {
        guard pairingLink == link, securePeerID == verified.peerID else { return }
        switch verified.message {
        case let .acknowledgement(sequence, rssi):
            if receive(BLEProtocol.Acknowledgement(sequence: sequence, rssi: rssi)) {
                isSubscribed = true
                responseWasMissed = false
                sendStatus(tracker.lossStartedAt == nil ? .nearby : .weakSignal, on: link)
            }
        default:
            break
        }
    }

    private func beginPairing() {
        closePairingSession()
        cancelPairingOffer(status: "")
        do {
            let local = try identityStore.loadOrCreateLocalIdentity()
            let offer = PairingOffer(
                id: UUID(),
                macIdentityID: local.id,
                macPublicKey: local.publicKey,
                expiresAt: ContinuousClock.now.advanced(by: PairingOffer.lifetime),
                secret: try identityStore.makePairingSecret()
            )
            pairingCodeImage = try PairingQRCode.makeImage(for: offer)
            pairingOffer = offer
            pairingSecondsRemaining = 120
            pairingStatus = "Scan this one-use code with the phone. Pairing expires in two minutes."
            isPairingPresented = true
            pairingExpiryTask = Task { [weak self] in
                try? await ContinuousClock().sleep(until: offer.expiresAt)
                guard !Task.isCancelled, let self, self.pairingOffer?.id == offer.id else { return }
                self.closePairingSession()
                self.cancelPairingOffer(status: "The pairing code expired. Start again to create a new one.")
            }
        } catch {
            pairingStatus = "Could not create a secure pairing code. Check Keychain access and try again."
            pairingCapability = .unavailable("Secure identity storage is unavailable.")
            isPairingPresented = true
        }
    }

    private func closePairingSession() {
        let oldLink = pairingLink
        if let oldLink { pairingSession?.close(oldLink) }
        pairingSession = nil
        pairingLink = nil
        candidateID = nil
        securePeerID = nil
        pendingPhoneFingerprint = nil
        if let oldLink {
            peripheral.closeSecureLink(oldLink)
        } else {
            peripheral.closeCurrentLink()
        }
        if pairingOffer != nil {
            cancelPairingOffer(status: "The pairing connection ended. Create a fresh code to try again.")
        }
        clearOperationalState()
    }

    private func cancelPairingOffer(status: String) {
        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil
        pairingOffer?.invalidate()
        pairingOffer = nil
        pairingCodeImage = nil
        pairingSecondsRemaining = 0
        pendingPhoneFingerprint = nil
        pairingStatus = status
    }

    private static func fingerprint(_ key: PeerPublicKey?) -> String? {
        guard let key else { return nil }
        return fingerprint(key.data)
    }

    private static func fingerprint(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).prefix(6).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func handle(_ event: MacTransportEvent) {
        switch event {
        case let .bluetoothState(state):
            bluetoothState = state
            logger?.log("bluetooth_state", details: state)
            if state != "Bluetooth on" {
                closePairingSession()
                clearOperationalState()
            } else if monitoringEnabled {
                beginMonitoringEpoch()
            }
        case let .secureLinkOpened(link):
            beginSession(on: link)
        case let .secureRecord(link, record):
            receiveSecureRecord(record, on: link)
        case let .secureLinkClosed(link):
            guard pairingLink == link else { return }
            pairingSession?.close(link)
            pairingSession = nil
            pairingLink = nil
            candidateID = nil
            securePeerID = nil
            pendingPhoneFingerprint = nil
            if pairingOffer != nil {
                cancelPairingOffer(status: "The pairing connection ended. Create a fresh code to try again.")
            }
            clearOperationalState()
        case let .log(event, details):
            logger?.log(event, details: details)
        }
    }

    private func receive(_ acknowledgement: BLEProtocol.Acknowledgement) -> Bool {
        guard let expected = outstandingSequence, acknowledgement.sequence == expected else {
            logger?.log("invalid_acknowledgement")
            return false
        }
        let now = ContinuousClock.now
        let wasCountingDown = tracker.lossStartedAt != nil
        schedule.acknowledge(acknowledgement.sequence, at: now)
        tracker.observeRSSI(acknowledgement.rssi, at: now)
        lastRSSI = acknowledgement.rssi
        if !wasCountingDown, tracker.lossStartedAt != nil, let rssi = acknowledgement.rssi {
            logger?.log("weak_signal", sequence: acknowledgement.sequence, rssi: rssi,
                        details: "threshold_dbm=\(tracker.threshold.rawValue)")
        } else if wasCountingDown, tracker.lossStartedAt == nil, let rssi = acknowledgement.rssi {
            logger?.log("signal_recovered", sequence: acknowledgement.sequence, rssi: rssi)
        }
        logger?.log("acknowledgement", sequence: acknowledgement.sequence, rssi: acknowledgement.rssi,
                    details: acknowledgement.rssi == nil ? "rssi_unavailable" : "")
        outstandingSequence = nil
        refreshDisplay(at: now)
        return true
    }

    private func clearOperationalState() {
        monitoringTask?.cancel()
        monitoringTask = nil
        responseWasMissed = false
        isSubscribed = false
        lastRSSI = nil
        outstandingSequence = nil
        schedule.clearPendingChallenge()
        tracker = PresenceTracker(threshold: signalThreshold)
        countdown = nil
    }

    private func refreshDisplay(at now: ContinuousClock.Instant = .now) {
        countdown = tracker.secondsRemaining(at: now)
        if let offer = pairingOffer {
            let remaining = now.duration(to: offer.expiresAt).components
            pairingSecondsRemaining = max(0, Int(remaining.seconds) + (remaining.attoseconds > 0 ? 1 : 0))
        }
        guard monitoringEnabled, securePeerID != nil, let link = pairingLink else { return }
        if schedule.responseTimedOut(at: now), !responseWasMissed {
            responseWasMissed = true
            tracker.missedChallenge(at: now)
            sendStatus(.signalLost, on: link)
        }
        if tracker.takeWouldLock(at: now), let started = tracker.lossStartedAt {
            logger?.log("lock_unavailable", sequence: outstandingSequence,
                        details: "elapsed_seconds=\(started.duration(to: now).components.seconds)")
            sendStatus(.lockUnavailable, on: link)
        }
    }

    private func beginMonitoringEpoch() {
        monitoringTask?.cancel()
        monitoringTask = nil
        clearOperationalState()
        guard monitoringEnabled, bluetoothState == "Bluetooth on",
              let session = pairingSession, let link = pairingLink, securePeerID != nil else { return }
        pairingStatus = "Waiting for authenticated iPhone."
        sendStatus(.waiting, on: link)
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await ContinuousClock().sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled, self.monitoringEnabled,
                      self.pairingSession === session, self.pairingLink == link else { return }
                let now = ContinuousClock.now
                if let action = self.schedule.nextAction(at: now) {
                    do {
                        let effects = try session.send(.challenge(sequence: action.sequence), on: link)
                        self.process(effects, on: link)
                        self.schedule.didQueue(action, at: now)
                        self.outstandingSequence = action.sequence
                    } catch {
                        self.closePairingSession()
                        return
                    }
                }
                self.refreshDisplay(at: now)
            }
        }
    }

    private func pauseMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        clearOperationalState()
        if let link = pairingLink, securePeerID != nil { sendStatus(.unavailable, on: link) }
    }

    private func sendStatus(_ status: MacStatus, on link: LinkID) {
        guard pairingLink == link, let session = pairingSession, securePeerID != nil else { return }
        do { process(try session.send(.status(status), on: link), on: link) }
        catch { closePairingSession() }
    }

    private func sendThreshold(on link: LinkID) {
        guard pairingLink == link, let session = pairingSession, securePeerID != nil else { return }
        do { process(try session.send(.threshold(signalThreshold.rawValue), on: link), on: link) }
        catch { closePairingSession() }
    }
}
