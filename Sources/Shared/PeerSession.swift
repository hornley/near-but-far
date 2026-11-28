import Foundation

enum PeerRole: UInt8 {
    case phone = 1
    case mac = 2

    var remote: PeerRole { self == .phone ? .mac : .phone }
    var snowRole: SnowRole { self == .phone ? .phone : .mac }
}

enum SessionIntent {
    case enrollMac(PairingOffer)
    case enrollPhone(ScannedOffer)
    case reconnect
}

struct LinkID: Hashable { let rawValue: UUID }
struct CandidateID: Hashable { let rawValue: UUID }

enum MacStatus: UInt8, Equatable {
    case unavailable = 1
    case waiting = 2
    case nearby = 3
    case weakSignal = 4
    case signalLost = 5
}

enum AppScreenCommand: UInt8, Equatable {
    case activate = 1
    case dismiss = 2
}

enum AppScreenState: UInt8, Equatable {
    case inactive = 1
    case active = 2
}

enum PeerMessage: Equatable {
    case pairingPrepared
    case pairingAccepted
    case pairingComplete
    case challenge(sequence: UInt32)
    case acknowledgement(sequence: UInt32, rssi: Int16?)
    case status(MacStatus)
    case threshold(Int16)
    case countdownDuration(UInt16)
    case appScreenCommand(AppScreenCommand)
    case appScreenState(AppScreenState)
    case macBatteryLevel(UInt8?)
}

struct VerifiedMessage {
    let peerID: UUID
    let sessionID: Data
    let message: PeerMessage

    fileprivate init(peerID: UUID, sessionID: Data, message: PeerMessage) {
        self.peerID = peerID
        self.sessionID = sessionID
        self.message = message
    }
}

struct OutboundRecord {
    let link: LinkID
    let bytes: Data
}

enum PeerSessionEvent {
    case candidate(CandidateID, peerStaticKey: Data)
    case ready(peerID: UUID, sessionID: Data)
    case received(VerifiedMessage)
    case closed(PeerSessionError)
    case pairingDisplayCleared
}

enum PeerSessionError: Error, Equatable {
    case invalidState
    case malformedRecord
    case unsupportedVersion
    case authenticationFailed
    case wrongPeer
    case pairingExpired
    case cancelled
    case keychainUnavailable
    case transportLost
    case recordExpired
    case internalFailure
}

struct SessionEffects {
    let outbound: [OutboundRecord]
    let events: [PeerSessionEvent]
    let generatedPairingPrepared: Bool

    init(outbound: [OutboundRecord], events: [PeerSessionEvent], generatedPairingPrepared: Bool = false) {
        self.outbound = outbound
        self.events = events
        self.generatedPairingPrepared = generatedPairingPrepared
    }
}

@MainActor
final class PeerSession {
    private enum Phase {
        case handshaking
        case awaitingPhonePrepared
        case awaitingMacApproval
        case awaitingMacConfirmation
        case awaitingApproval
        case awaitingPhoneComplete
        case awaitingMacComplete
        case established
    }

    private struct LinkState {
        let id: LinkID
        let bridge: SnowBridge
        let localIdentity: LocalIdentity
        let intent: SessionIntent
        var phase: Phase = .handshaking
        var expectedPeerID: UUID?
        var expectedPeerKey: PeerPublicKey?
        var peerID: UUID?
        var peerKey: PeerPublicKey?
        var sessionID: Data?
        var candidateID: CandidateID?
    }

    private static let envelopeVersion: UInt8 = 1
    private static let envelopeSize = 67
    private let role: PeerRole
    private let store: PeerIdentityStore
    private let intent: SessionIntent
    private var active: LinkState?
    private var offerExpiryTask: Task<Void, Never>?
    var onEvent: ((PeerSessionEvent) -> Void)?

    init(role: PeerRole, store: PeerIdentityStore, intent: SessionIntent) {
        self.role = role
        self.store = store
        self.intent = intent
    }

    func start(on link: LinkID) throws -> SessionEffects {
        guard active == nil else { throw PeerSessionError.invalidState }
        let local: LocalIdentity
        do { local = try store.loadOrCreateLocalIdentity() }
        catch { throw PeerSessionError.keychainUnavailable }
        let bridge: SnowBridge
        var peerID: UUID?
        var peerKey: PeerPublicKey?

        switch (role, intent) {
        case let (.mac, .enrollMac(offer)):
            guard offer.expiresAt > .now else { offer.invalidate(); throw PeerSessionError.pairingExpired }
            guard offer.macIdentityID == local.id, offer.macPublicKey == local.publicKey else {
                offer.invalidate()
                throw PeerSessionError.wrongPeer
            }
            guard try pairedIdentity() == nil else { throw PeerSessionError.invalidState }
            bridge = try offer.withSecret { raw in
                var psk = Data(raw)
                defer { psk.resetBytes(in: 0..<psk.count) }
                return try Self.makeBridge(role: role, mode: .enrollment, local: local,
                                           expectedRemote: nil, offerID: offer.id, psk: psk)
            }
        case let (.phone, .enrollPhone(offer)):
            guard offer.expiresAt > .now else {
                offer.invalidate()
                throw PeerSessionError.pairingExpired
            }
            // Retain any existing pin until the approved Mac returns its authenticated pairing message.
            peerID = offer.macIdentityID
            peerKey = offer.macPublicKey
            bridge = try offer.withSecret { raw in
                var psk = Data(raw)
                defer { psk.resetBytes(in: 0..<psk.count) }
                return try Self.makeBridge(role: role, mode: .enrollment, local: local,
                                           expectedRemote: offer.macPublicKey, offerID: offer.id, psk: psk)
            }
        case (.mac, .reconnect), (.phone, .reconnect):
            guard let paired = try pairedIdentity() else { throw PeerSessionError.wrongPeer }
            peerID = paired.id
            peerKey = paired.publicKey
            bridge = try Self.makeBridge(role: role, mode: .reconnect, local: local,
                                         expectedRemote: paired.publicKey, offerID: nil, psk: Data())
        default:
            throw PeerSessionError.invalidState
        }

        let state = LinkState(id: link, bridge: bridge, localIdentity: local, intent: intent,
                              expectedPeerID: peerID, expectedPeerKey: peerKey)
        do {
            let first = try bridge.start()
            active = state
            scheduleOfferExpiry(for: link)
            return SessionEffects(outbound: first.isEmpty ? [] : [OutboundRecord(link: link, bytes: first)], events: [])
        } catch {
            state.bridge.close()
            invalidateOffer()
            throw Self.map(error)
        }
    }

    func receive(_ completeRecord: Data, from link: LinkID) throws -> SessionEffects {
        guard let state = active, state.id == link else { throw PeerSessionError.invalidState }
        if let expiry = pendingOfferExpiry(for: state), expiry <= .now {
            expire(link)
            throw PeerSessionError.pairingExpired
        }
        guard !completeRecord.isEmpty, completeRecord.count <= BLEProtocol.maximumRecordSize else {
            close(link)
            throw PeerSessionError.malformedRecord
        }
        do {
            if case .handshaking = state.phase {
                return try receiveHandshake(completeRecord, state: state)
            }
            return try receiveMessage(completeRecord, state: state)
        } catch {
            close(link)
            throw Self.map(error)
        }
    }

    func approvePairing(_ candidate: CandidateID) throws -> SessionEffects {
        guard role == .mac, var state = active, state.candidateID == candidate,
              case .awaitingApproval = state.phase,
              case let .enrollMac(offer) = state.intent,
              let peerID = state.peerID,
              let peerKey = state.peerKey else { throw PeerSessionError.invalidState }
        guard offer.expiresAt > .now else {
            expire(state.id)
            throw PeerSessionError.pairingExpired
        }
        guard state.sessionID != nil else {
            close(state.id)
            throw PeerSessionError.invalidState
        }

        do { try store.replacePairedIdentity(with: PairedIdentity(id: peerID, publicKey: peerKey)) }
        catch {
            close(state.id)
            throw PeerSessionError.keychainUnavailable
        }
        offer.invalidate()
        cancelOfferExpiry()
        state.phase = .awaitingPhoneComplete
        let record: Data
        do { record = try seal(.pairingAccepted, on: state) }
        catch {
            close(state.id)
            throw Self.map(error)
        }
        active = state
        return SessionEffects(outbound: [OutboundRecord(link: state.id, bytes: record)],
                              events: [.pairingDisplayCleared])
    }

    func send(_ message: PeerMessage, on link: LinkID) throws -> SessionEffects {
        guard let state = active, state.id == link, case .established = state.phase,
              Self.operationalMessage(message, isValidForSender: role) else { throw PeerSessionError.invalidState }
        do {
            let bytes = try seal(message, on: state)
            return SessionEffects(outbound: [OutboundRecord(link: link, bytes: bytes)], events: [])
        } catch {
            close(link)
            throw Self.map(error)
        }
    }

    func close(_ link: LinkID) {
        guard let state = active, state.id == link else { return }
        cancelOfferExpiry()
        active = nil
        state.bridge.close()
        invalidateOffer(state.intent)
    }

    private func receiveHandshake(_ record: Data, state: LinkState) throws -> SessionEffects {
        let result = try state.bridge.receive(record)
        var outbound = result.outbound.isEmpty ? [] : [OutboundRecord(link: state.id, bytes: result.outbound)]
        guard result.finished else { return SessionEffects(outbound: outbound, events: []) }
        guard let peerBytes = result.peerStaticKey, let hash = result.sessionID,
              hash.count == 32, let peerKey = try? PeerPublicKey(validating: peerBytes) else {
            throw PeerSessionError.authenticationFailed
        }
        if let expectedKey = state.expectedPeerKey, expectedKey != peerKey {
            throw PeerSessionError.wrongPeer
        }

        var next = state
        next.peerKey = peerKey
        next.sessionID = hash
        switch (role, state.intent) {
        case (.phone, .enrollPhone):
            next.phase = .awaitingMacApproval
            outbound.append(OutboundRecord(link: state.id, bytes: try seal(.pairingPrepared, on: next)))
            active = next
            return SessionEffects(outbound: outbound, events: [], generatedPairingPrepared: true)
        case (.mac, .enrollMac):
            next.phase = .awaitingPhonePrepared
            active = next
        case (.mac, .reconnect):
            guard let peerID = next.expectedPeerID else { throw PeerSessionError.wrongPeer }
            next.peerID = peerID
            next.phase = .established
            active = next
            return SessionEffects(outbound: outbound, events: [.ready(peerID: peerID, sessionID: hash)])
        case (.phone, .reconnect):
            next.phase = .awaitingMacConfirmation
            active = next
        default:
            throw PeerSessionError.invalidState
        }
        return SessionEffects(outbound: outbound, events: [])
    }

    private func receiveMessage(_ record: Data, state: LinkState) throws -> SessionEffects {
        let plaintext = try state.bridge.open(record)
        let (peerID, message) = try decodeEnvelope(plaintext, state: state)
        var next = state
        if next.peerID == nil { next.peerID = peerID }
        guard let sessionID = state.sessionID else { throw PeerSessionError.invalidState }
        let verified = VerifiedMessage(peerID: peerID, sessionID: sessionID, message: message)
        var events: [PeerSessionEvent] = [.received(verified)]
        var outbound: [OutboundRecord] = []

        switch (role, state.phase, message) {
        case (.mac, .awaitingPhonePrepared, .pairingPrepared):
            guard case .enrollMac = state.intent, let peerKey = state.peerKey else {
                throw PeerSessionError.invalidState
            }
            let candidate = CandidateID(rawValue: UUID())
            next.candidateID = candidate
            next.peerID = peerID
            next.expectedPeerID = peerID
            next.phase = .awaitingApproval
            events.append(.candidate(candidate, peerStaticKey: peerKey.data))
        case (.phone, .awaitingMacApproval, .pairingAccepted):
            guard case let .enrollPhone(offer) = state.intent,
                  peerID == offer.macIdentityID, let peerKey = state.peerKey else {
                throw PeerSessionError.wrongPeer
            }
            do { try store.replacePairedIdentity(with: PairedIdentity(id: peerID, publicKey: peerKey)) }
            catch { throw PeerSessionError.keychainUnavailable }
            offer.invalidate()
            cancelOfferExpiry()
            next.phase = .awaitingMacComplete
            outbound.append(OutboundRecord(link: state.id, bytes: try seal(.pairingComplete, on: next)))
        case (.mac, .awaitingPhoneComplete, .pairingComplete):
            guard next.peerID == peerID, let hash = next.sessionID else { throw PeerSessionError.wrongPeer }
            next.phase = .established
            outbound.append(OutboundRecord(link: state.id, bytes: try seal(.pairingComplete, on: next)))
            events.append(.ready(peerID: peerID, sessionID: hash))
        case (.phone, .awaitingMacComplete, .pairingComplete):
            guard next.expectedPeerID == peerID, let hash = next.sessionID else { throw PeerSessionError.wrongPeer }
            next.phase = .established
            events.append(.ready(peerID: peerID, sessionID: hash))
        case (.phone, .awaitingMacConfirmation, .threshold):
            guard next.expectedPeerID == peerID, let hash = next.sessionID else { throw PeerSessionError.wrongPeer }
            next.phase = .established
            events.append(.ready(peerID: peerID, sessionID: hash))
        case (.mac, .established, .acknowledgement), (.phone, .established, .challenge),
             (.phone, .established, .status), (.phone, .established, .threshold),
             (.phone, .established, .macBatteryLevel), (.phone, .established, .countdownDuration),
             (.mac, .established, .appScreenCommand), (.phone, .established, .appScreenState):
            guard next.expectedPeerID == peerID else { throw PeerSessionError.wrongPeer }
        default:
            throw PeerSessionError.invalidState
        }

        if case .established = next.phase {
            cancelOfferExpiry()
            invalidateOffer(state.intent)
        }
        active = next
        return SessionEffects(outbound: outbound, events: events)
    }

    private func seal(_ message: PeerMessage, on state: LinkState) throws -> Data {
        guard let peerID = state.peerID ?? state.expectedPeerID, let sessionID = state.sessionID else {
            throw PeerSessionError.invalidState
        }
        return try state.bridge.seal(encodeEnvelope(message, senderID: state.localIdentity.id,
                                                    recipientID: peerID, sessionID: sessionID))
    }

    private func encodeEnvelope(_ message: PeerMessage, senderID: UUID, recipientID: UUID,
                                sessionID: Data) -> Data {
        var bytes = Data([Self.envelopeVersion, role.rawValue, Self.messageTag(message)])
        bytes.append(UUIDBytes.encode(senderID))
        bytes.append(UUIDBytes.encode(recipientID))
        bytes.append(sessionID)
        switch message {
        case let .challenge(sequence):
            bytes.append(contentsOf: Self.uint32(sequence))
        case let .acknowledgement(sequence, rssi):
            bytes.append(contentsOf: Self.uint32(sequence))
            let encoded = UInt16(bitPattern: rssi ?? .min).bigEndian
            withUnsafeBytes(of: encoded) { bytes.append(contentsOf: $0) }
        case let .status(status):
            bytes.append(status.rawValue)
        case let .appScreenCommand(command):
            bytes.append(command.rawValue)
        case let .appScreenState(state):
            bytes.append(state.rawValue)
        case let .macBatteryLevel(level):
            bytes.append(level ?? 0xff)
        case let .threshold(value):
            let encoded = UInt16(bitPattern: value).bigEndian
            withUnsafeBytes(of: encoded) { bytes.append(contentsOf: $0) }
        case let .countdownDuration(value):
            var encoded = value.bigEndian
            withUnsafeBytes(of: &encoded) { bytes.append(contentsOf: $0) }
        case .pairingPrepared, .pairingAccepted, .pairingComplete:
            break
        }
        return bytes
    }

    private func decodeEnvelope(_ bytes: Data, state: LinkState) throws -> (UUID, PeerMessage) {
        let envelope = Array(bytes)
        guard envelope.count >= Self.envelopeSize else { throw PeerSessionError.malformedRecord }
        guard envelope[0] == Self.envelopeVersion else { throw PeerSessionError.unsupportedVersion }
        guard envelope[1] == role.remote.rawValue else { throw PeerSessionError.wrongPeer }
        let senderID = try UUIDBytes.decode(Data(envelope[3..<19]))
        let recipientID = try UUIDBytes.decode(Data(envelope[19..<35]))
        guard let sessionID = state.sessionID,
              recipientID == state.localIdentity.id,
              Data(envelope[35..<67]) == sessionID else { throw PeerSessionError.wrongPeer }
        if let expectedID = state.expectedPeerID, senderID != expectedID { throw PeerSessionError.wrongPeer }
        if let peerID = state.peerID, senderID != peerID { throw PeerSessionError.wrongPeer }
        let payload = Array(envelope.dropFirst(Self.envelopeSize))
        let message = try Self.decodeMessage(tag: envelope[2], payload: payload, receiver: role)
        guard Self.message(message, isValidForSender: role.remote) else { throw PeerSessionError.wrongPeer }
        return (senderID, message)
    }

    static func decodeMessage(tag: UInt8, payload: [UInt8], receiver role: PeerRole) throws -> PeerMessage {
        switch tag {
        case 1:
            guard payload.isEmpty else { throw PeerSessionError.malformedRecord }
            return .pairingPrepared
        case 2:
            guard payload.isEmpty else { throw PeerSessionError.malformedRecord }
            return .pairingAccepted
        case 3:
            guard payload.isEmpty else { throw PeerSessionError.malformedRecord }
            return .pairingComplete
        case 4:
            guard role == .phone, payload.count == 4 else { throw PeerSessionError.malformedRecord }
            return .challenge(sequence: Self.readUInt32(Data(payload)))
        case 5:
            guard role == .mac, payload.count == 6 else { throw PeerSessionError.malformedRecord }
            let raw = UInt16(payload[4]) << 8 | UInt16(payload[5])
            let rssi = raw == UInt16(bitPattern: Int16.min) ? nil : Int16(bitPattern: raw)
            return .acknowledgement(sequence: Self.readUInt32(Data(payload[0..<4])), rssi: rssi)
        case 6:
            guard role == .phone, payload.count == 1,
                  let status = MacStatus(rawValue: payload[0]) else { throw PeerSessionError.malformedRecord }
            return .status(status)
        case 7:
            guard payload.count == 2 else { throw PeerSessionError.malformedRecord }
            guard role == .phone else { throw PeerSessionError.wrongPeer }
            let value = Int16(bitPattern: UInt16(payload[0]) << 8 | UInt16(payload[1]))
            guard SignalThreshold(validating: value) != nil else { throw PeerSessionError.malformedRecord }
            return .threshold(value)
        case 8:
            guard role == .mac, payload.count == 1,
                  let command = AppScreenCommand(rawValue: payload[0]) else { throw PeerSessionError.malformedRecord }
            return .appScreenCommand(command)
        case 9:
            guard role == .phone, payload.count == 1,
                  let state = AppScreenState(rawValue: payload[0]) else { throw PeerSessionError.malformedRecord }
            return .appScreenState(state)
        case 10:
            guard role == .phone, payload.count == 1 else { throw PeerSessionError.malformedRecord }
            let level = payload[0]
            guard level == 0xff || level <= 100 else { throw PeerSessionError.malformedRecord }
            return .macBatteryLevel(level == 0xff ? nil : level)
        case 11:
            guard role == .phone, payload.count == 2 else { throw PeerSessionError.malformedRecord }
            let value = UInt16(payload[0]) << 8 | UInt16(payload[1])
            guard CountdownDuration(validating: Int(value)) != nil else { throw PeerSessionError.malformedRecord }
            return .countdownDuration(value)
        default:
            throw PeerSessionError.malformedRecord
        }
    }

    private static func message(_ message: PeerMessage, isValidForSender role: PeerRole) -> Bool {
        switch (role, message) {
        case (.phone, .pairingPrepared), (.phone, .pairingComplete), (.phone, .acknowledgement),
             (.mac, .pairingAccepted), (.mac, .pairingComplete), (.mac, .challenge), (.mac, .status),
             (.mac, .threshold), (.mac, .countdownDuration), (.phone, .appScreenCommand), (.mac, .appScreenState),
             (.mac, .macBatteryLevel):
            return true
        default:
            return false
        }
    }

    private static func operationalMessage(_ message: PeerMessage, isValidForSender role: PeerRole) -> Bool {
        switch (role, message) {
        case (.mac, .challenge), (.mac, .status), (.phone, .acknowledgement),
             (.phone, .appScreenCommand), (.mac, .appScreenState):
            return true
        case let (.mac, .macBatteryLevel(level)):
            return level.map { $0 <= 100 } ?? true
        case let (.mac, .threshold(value)):
            return SignalThreshold(validating: value) != nil
        case let (.mac, .countdownDuration(value)):
            return CountdownDuration(validating: Int(value)) != nil
        default:
            return false
        }
    }

    private static func messageTag(_ message: PeerMessage) -> UInt8 {
        switch message {
        case .pairingPrepared: 1
        case .pairingAccepted: 2
        case .pairingComplete: 3
        case .challenge: 4
        case .acknowledgement: 5
        case .status: 6
        case .threshold: 7
        case .appScreenCommand: 8
        case .appScreenState: 9
        case .macBatteryLevel: 10
        case .countdownDuration: 11
        }
    }

    private static func uint32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }

    private static func readUInt32(_ bytes: Data) -> UInt32 {
        bytes.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
    }

    private static func makeBridge(role: PeerRole, mode: SnowMode, local: LocalIdentity,
                                   expectedRemote: PeerPublicKey?, offerID: UUID?, psk: Data) throws -> SnowBridge {
        do {
            return try local.withPrivateKey { privateKey in
                try SnowBridge(role: role.snowRole, mode: mode, localPrivateKey: privateKey,
                               localPublicKey: local.publicKey.data,
                               expectedRemoteStaticKey: expectedRemote?.data ?? Data(),
                               pairingPSK: psk, offerID: offerID.map(UUIDBytes.encode) ?? Data())
            }
        } catch {
            throw map(error)
        }
    }

    private func pairedIdentity() throws -> PairedIdentity? {
        do { return try store.pairedIdentity() }
        catch { throw PeerSessionError.keychainUnavailable }
    }

    private func offerExpiry(_ intent: SessionIntent) -> ContinuousClock.Instant? {
        switch intent {
        case let .enrollMac(offer): offer.expiresAt
        case let .enrollPhone(offer): offer.expiresAt
        case .reconnect: nil
        }
    }

    private func pendingOfferExpiry(for state: LinkState) -> ContinuousClock.Instant? {
        switch (role, state.intent) {
        case (.mac, .enrollMac(let offer)):
            switch state.phase {
            case .handshaking, .awaitingPhonePrepared, .awaitingApproval: offer.expiresAt
            default: nil
            }
        case (.phone, .enrollPhone(let offer)):
            switch state.phase {
            case .handshaking, .awaitingMacApproval: offer.expiresAt
            default: nil
            }
        default: nil
        }
    }

    private func scheduleOfferExpiry(for link: LinkID) {
        guard let expiry = offerExpiry(intent) else { return }
        offerExpiryTask = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: expiry) }
            catch { return }
            guard let self, let state = self.active, state.id == link,
                  self.pendingOfferExpiry(for: state) == expiry else { return }
            self.expire(link)
        }
    }

    private func cancelOfferExpiry() {
        offerExpiryTask?.cancel()
        offerExpiryTask = nil
    }

    private func expire(_ link: LinkID) {
        close(link)
        onEvent?(.closed(.pairingExpired))
        onEvent?(.pairingDisplayCleared)
    }

    private func invalidateOffer(_ intent: SessionIntent? = nil) {
        switch intent ?? self.intent {
        case let .enrollMac(offer): offer.invalidate()
        case let .enrollPhone(offer): offer.invalidate()
        case .reconnect: break
        }
    }

    private static func map(_ error: Error) -> PeerSessionError {
        if let error = error as? PeerSessionError { return error }
        guard let error = error as? SnowBridgeError,
              case let .status(code) = error else { return .internalFailure }
        switch code {
        case 1: return .malformedRecord
        case 2: return .invalidState
        case 3, 5: return .internalFailure
        case 4: return .authenticationFailed
        default: return .internalFailure
        }
    }
}
