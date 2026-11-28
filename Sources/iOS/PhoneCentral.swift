import CoreBluetooth
import Foundation
import SwiftUI

private enum PhoneConnectionPhase: Equatable {
    case connecting, serviceDiscovery, characteristicDiscovery, notificationSubscription, sessionAuthentication
}

@MainActor
final class PhoneCentral: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published private(set) var bluetoothState = "Starting"
    @Published private(set) var connectionState = "Scanning"
    @Published private(set) var events: [String]
    @Published private(set) var pairingState: PairingScannerState = .unpaired
    @Published private(set) var canRetryConnection = false

    var bluetoothIsAvailable: Bool { central.state == .poweredOn }
    var canSendAppScreenCommand: Bool {
        PhoneAppScreenCommandReadiness.canSend(
            sessionReady: model.sessionReady,
            stateReceived: model.hasReceivedAppScreenStateForSession,
            bluetoothAvailable: bluetoothIsAvailable,
            hasActiveLink: activeLink != nil,
            hasSession: session != nil,
            hasPeripheral: peripheral != nil,
            hasCharacteristic: acknowledgementCharacteristic != nil
        )
    }

    private let restorationID = "com.hornley.nearbutfar.phone.central"
    private let eventsKey = "nearButFar.bleEvents"
    private let installMarkerKey = "nearButFar.phone.installInitialized.v1"
    private let store = PhonePairedIdentityStore()
    private var central: CBCentralManager!
    private var presenceTimer: Timer?
    private var peripheral: CBPeripheral?
    private var challengeCharacteristic: CBCharacteristic?
    private var acknowledgementCharacteristic: CBCharacteristic?
    private var activeLink: LinkID?
    private var reassembler: BLEProtocol.RecordReassembler?
    private var session: PeerSession?
    private var scannedOffer: ScannedOffer?
    private var outgoingSequence: UInt32 = 0
    private var outgoingExhausted = false
    private var pendingFrames: [Data] = []
    private var writeInFlight = false
    private var pairingPreparedRequestQueued = false
    private var pendingRSSI: (sequence: UInt32, link: LinkID)?
    private var identityStoreReady = true
    private var enrollmentLink = false
    private var recoveryAttempts = 0
    private var recoveryGeneration: UInt64 = 0
    private var recoveryTask: Task<Void, Never>?
    private var offerExpiryTask: Task<Void, Never>?
    private var phaseDeadlineTask: Task<Void, Never>?
    private var phaseGeneration: UInt64 = 0
    private var connectionPhase: PhoneConnectionPhase?
    let model: PhoneModel

    private var awaitingPairingAction: Bool {
        [.scanning, .expired, .qrMismatch, .cameraUnavailable].contains(pairingState)
    }

    init(model: PhoneModel? = nil) {
        self.model = model ?? PhoneModel()
        events = UserDefaults.standard.stringArray(forKey: eventsKey) ?? []
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: restorationID])
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: installMarkerKey) {
            do {
                try store.prepareForFreshInstall()
                defaults.set(true, forKey: installMarkerKey)
                guard defaults.bool(forKey: installMarkerKey) else { throw PeerSessionError.keychainUnavailable }
            } catch {
                identityStoreReady = false
                pairingState = .storageUnavailable
            }
        }
        if identityStoreReady {
            do { pairingState = try store.pairedIdentity() == nil ? .unpaired : .paired }
            catch { identityStoreReady = false; pairingState = .storageUnavailable }
        }
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.refreshPresence() }
        }
    }

    func beginPairing() {
        guard identityStoreReady else { pairingState = .storageUnavailable; return }
        cancelRecovery(resetAttempts: true)
        cancelOfferExpiry()
        scannedOffer?.invalidate()
        scannedOffer = nil
        closeSession()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        enrollmentLink = false
        pairingState = .scanning
        central.stopScan()
        model.didDisconnect(cause: .pairingStarted, at: .now)
        connectionState = "Scan the one-use QR code shown by the Mac."
    }

    func cancelPairing() {
        cancelRecovery(resetAttempts: true)
        cancelOfferExpiry()
        cancelPhaseDeadline()
        let wasPairingFlow = scannedOffer != nil || enrollmentLink || pairingState != .paired && pairingState != .storageUnavailable
        if wasPairingFlow { central.stopScan() }
        scannedOffer?.invalidate()
        scannedOffer = nil
        enrollmentLink = false
        if identityStoreReady {
            do { pairingState = try store.pairedIdentity() == nil ? .unpaired : .paired }
            catch { identityStoreReady = false; pairingState = .storageUnavailable }
        } else { pairingState = .storageUnavailable }
        guard wasPairingFlow else { return }
        closeSession()
        model.didDisconnect(cause: .pairingStarted, at: .now)
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        if identityStoreReady, (try? store.pairedIdentity()) != nil, central.state == .poweredOn {
            DispatchQueue.main.async { [weak self] in self?.scanAgain() }
        }
    }

    func acceptScannedPayload(_ payload: String) {
        guard identityStoreReady else { pairingState = .storageUnavailable; return }
        do {
            let offer = try ScannedOffer(validating: payload)
            cancelRecovery(resetAttempts: true)
            cancelOfferExpiry()
            scannedOffer?.invalidate()
            closeSession()
            model.didDisconnect(cause: .pairingStarted, at: .now)
            if let peripheral { central.cancelPeripheralConnection(peripheral) }
            peripheral = nil
            challengeCharacteristic = nil
            acknowledgementCharacteristic = nil
            enrollmentLink = false
            scannedOffer = offer
            scheduleOfferExpiry(for: offer)
            pairingState = .connecting
            scanAgain()
        } catch PeerSessionError.pairingExpired {
            pairingState = .expired
        } catch PeerSessionError.keychainUnavailable {
            identityStoreReady = false
            cancelOfferExpiry()
            scannedOffer?.invalidate()
            scannedOffer = nil
            pairingState = .storageUnavailable
        } catch {
            pairingState = .scanning
            record("invalid_pairing_qr")
        }
    }

    func cameraUnavailable() { pairingState = .cameraUnavailable }

    func activateAppScreen() { sendAppScreenCommand(.activate) }
    func dismissAppScreen() { sendAppScreenCommand(.dismiss) }

    private func sendAppScreenCommand(_ command: AppScreenCommand) {
        guard canSendAppScreenCommand, let link = activeLink, let session else { return }
        do { process(try session.send(.appScreenCommand(command), on: link)) }
        catch { failSecureLink(link, error: error as? PeerSessionError ?? .authenticationFailed) }
    }

    func scanAgain() {
        cancelRecovery(resetAttempts: true)
        startScan()
    }

    func retryPairing() {
        cancelRecovery(resetAttempts: true)
        if pairingState == .expired || pairingState == .unpaired || pairingState == .qrMismatch || pairingState == .cameraUnavailable {
            scannedOffer?.invalidate()
            scannedOffer = nil
            pairingState = .scanning
            closeSession()
            central.stopScan()
            if let peripheral { central.cancelPeripheralConnection(peripheral) }
            peripheral = nil
            challengeCharacteristic = nil
            acknowledgementCharacteristic = nil
            model.didDisconnect(cause: .pairingStarted, at: .now)
            connectionState = "Scan a new QR code shown by the Mac."
            return
        }
        startScan()
    }

    private func startScan() {
        cancelRecovery(resetAttempts: false)
        cancelPhaseDeadline()
        closeSession()
        model.didDisconnect(cause: .reconnectAttempt, at: .now)
        if enrollmentLink { clearEnrollmentAfterFailure(expired: false) }
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        challengeCharacteristic = nil
        acknowledgementCharacteristic = nil
        guard identityStoreReady else {
            connectionState = "Secure storage unavailable. Restart the app and try again."
            return
        }
        guard central.state == .poweredOn else {
            connectionState = "Bluetooth unavailable"
            return
        }
        central.stopScan()
        central.scanForPeripherals(withServices: [BLEProtocol.serviceUUID])
        connectionState = intentIsEnrollment ? "Connecting to Mac" : "Scanning for Mac"
        record("scan_started")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = stateName(central.state)
        record("bluetooth_\(bluetoothState.lowercased().replacingOccurrences(of: " ", with: "_"))")
        if central.state == .poweredOn {
            model.setBluetoothAvailable(true)
            if awaitingPairingAction {
                connectionState = "Scan the one-use QR code shown by the Mac."
            } else {
                scanAgain()
            }
        } else {
            cancelRecovery(resetAttempts: true)
            cancelPhaseDeadline()
            closeSession()
            if let peripheral { central.cancelPeripheralConnection(peripheral) }
            peripheral = nil
            model.didDisconnect(cause: .bluetoothUnavailable, at: .now)
            model.setBluetoothAvailable(false)
            if enrollmentLink { clearEnrollmentAfterFailure(expired: false) }
            connectionState = "Bluetooth unavailable. Turn Bluetooth on, then scan again."
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        record("core_bluetooth_restored")
        guard identityStoreReady else { return }
        guard let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first else { return }
        if awaitingPairingAction || pairingState == .waitingForMacApproval {
            central.cancelPeripheralConnection(restored)
            if pairingState == .waitingForMacApproval { scanAgain() }
            return
        }
        peripheral = restored
        restored.delegate = self
        connectionState = intentIsEnrollment ? "Connecting to Mac" : "Restoring connection"
        armPhaseDeadline(.connecting, duration: .seconds(15))
        central.connect(restored)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !awaitingPairingAction else { return }
        cancelRecovery(resetAttempts: false)
        model.didDisconnect(cause: .reconnectAttempt, at: .now)
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        connectionState = intentIsEnrollment ? "Connecting to Mac" : "Connecting"
        armPhaseDeadline(.connecting, duration: .seconds(15))
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        cancelRecovery(resetAttempts: false)
        closeSession()
        armPhaseDeadline(.serviceDiscovery, duration: .seconds(12))
        model.didDisconnect(cause: .reconnectAttempt, at: .now)
        record("connected")
        connectionState = intentIsEnrollment ? "Connecting to Mac" : "Discovering service"
        peripheral.delegate = self
        peripheral.discoverServices([BLEProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        cancelPhaseDeadline()
        if let error {
            let nsError = error as NSError
            record("connect_failed domain=\(nsError.domain) code=\(nsError.code)")
        } else {
            record("connect_failed")
        }
        scheduleRecovery("Could not connect to the Mac.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        closeSession()
        cancelPhaseDeadline()
        if enrollmentLink { clearEnrollmentAfterFailure(expired: false) }
        record("disconnected")
        model.didDisconnect(cause: awaitingPairingAction ? .pairingStarted : .transportLost, at: .now)
        if !identityStoreReady {
            pairingState = .storageUnavailable
            connectionState = "Secure storage unavailable. Restart the app and try again."
        } else if awaitingPairingAction {
            return
        } else if scannedOffer != nil || (try? store.pairedIdentity()) != nil {
            scheduleRecovery("Connection to the Mac ended.")
        } else {
            connectionState = "Pairing ended. Create a new code on the Mac and scan again."
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BLEProtocol.serviceUUID }) else {
            scheduleRecovery("Mac pairing service is unavailable.")
            return
        }
        armPhaseDeadline(.characteristicDiscovery, duration: .seconds(12))
        peripheral.discoverCharacteristics([BLEProtocol.challengeUUID, BLEProtocol.acknowledgementUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil, let characteristics = service.characteristics else {
            scheduleRecovery("Mac pairing service is incomplete.")
            return
        }
        armPhaseDeadline(.notificationSubscription, duration: .seconds(12))
        challengeCharacteristic = characteristics.first(where: { $0.uuid == BLEProtocol.challengeUUID })
        acknowledgementCharacteristic = characteristics.first(where: { $0.uuid == BLEProtocol.acknowledgementUUID })
        guard let challengeCharacteristic, acknowledgementCharacteristic != nil else {
            scheduleRecovery("Mac pairing service is incomplete.")
            return
        }
        peripheral.setNotifyValue(true, for: challengeCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == BLEProtocol.challengeUUID else { return }
        guard error == nil, characteristic.isNotifying, let peripheral = self.peripheral else {
            scheduleRecovery("Could not receive from the Mac.")
            return
        }
        let link = LinkID(rawValue: UUID())
        cancelPhaseDeadline()
        model.didDisconnect(cause: .reconnectAttempt, at: .now)
        activeLink = link
        reassembler = BLEProtocol.RecordReassembler(link: link) { [weak self] failedLink in
            self?.failSecureLink(failedLink, error: .malformedRecord)
        }
        let intent: SessionIntent
        if let scannedOffer { intent = .enrollPhone(scannedOffer) }
        else {
            do {
                guard try store.pairedIdentity() != nil else {
                    connectionState = "No Mac is paired. Open Pair a Mac to scan its QR code."
                    closeSession()
                    central.cancelPeripheralConnection(peripheral)
                    return
                }
                intent = .reconnect
            } catch {
                identityStoreReady = false
                pairingState = .storageUnavailable
                closeSession()
                return
            }
        }
        let secure = PeerSession(role: .phone, store: store, intent: intent)
        session = secure
        enrollmentLink = intentIsEnrollment
        if let scannedOffer {
            let remaining = ContinuousClock.now.duration(to: scannedOffer.expiresAt)
            if remaining > .zero { armPhaseDeadline(.sessionAuthentication, duration: remaining) }
        } else {
            armPhaseDeadline(.sessionAuthentication, duration: .seconds(20))
        }
        secure.onEvent = { [weak self] event in self?.handleSessionEvent(event, on: link) }
        do {
            process(try secure.start(on: link))
            connectionState = intentIsEnrollment ? "Connecting to Mac" : "Authenticating Mac"
        } catch {
            failSecureLink(link, error: error as? PeerSessionError ?? .internalFailure)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == BLEProtocol.challengeUUID else { return }
        guard error == nil, let frame = characteristic.value, let link = activeLink,
              let reassembler, let session else {
            if let link = activeLink { failSecureLink(link, error: .transportLost) }
            return
        }
        do {
            guard let record = try reassembler.append(frame) else { return }
            process(try session.receive(record, from: link))
        } catch {
            failSecureLink(link, error: error as? PeerSessionError ?? .authenticationFailed)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == BLEProtocol.acknowledgementUUID else { return }
        writeInFlight = false
        if error != nil {
            if let link = activeLink { failSecureLink(link, error: .transportLost) }
            return
        }
        flushWrites()
        if pairingPreparedRequestQueued, pendingFrames.isEmpty, !writeInFlight {
            pairingPreparedRequestQueued = false
            pairingState = .waitingForMacApproval
            connectionState = "Waiting for Mac approval"
        }
    }

    private var intentIsEnrollment: Bool { scannedOffer != nil }

    private func process(_ effects: SessionEffects) {
        guard let link = activeLink else { return }
        if effects.generatedPairingPrepared { pairingPreparedRequestQueued = true }
        for event in effects.events {
            handleSessionEvent(event, on: link)
        }
        for record in effects.outbound {
            guard record.link == link, !outgoingExhausted else {
                failSecureLink(link, error: .malformedRecord)
                return
            }
            do { pendingFrames.append(contentsOf: try BLEProtocol.fragment(record.bytes, sequence: outgoingSequence)) }
            catch { failSecureLink(link, error: .malformedRecord); return }
            if outgoingSequence == .max { outgoingExhausted = true } else { outgoingSequence += 1 }
        }
        flushWrites()
    }

    private func handleSessionEvent(_ event: PeerSessionEvent, on link: LinkID) {
        guard activeLink == link else { return }
        switch event {
            case let .ready(peerID, _):
                pairingPreparedRequestQueued = false
                cancelPhaseDeadline()
                cancelOfferExpiry()
                cancelRecovery(resetAttempts: true)
                canRetryConnection = false
                model.didAuthenticate(peerID: peerID)
                if scannedOffer != nil {
                    scannedOffer?.invalidate()
                    scannedOffer = nil
                    pairingState = .paired
                } else if (try? store.pairedIdentity()) != nil {
                    pairingState = .paired
                }
                enrollmentLink = false
                connectionState = "Authenticated Mac"
            case let .received(verified):
                model.didReceiveAuthenticated(verified.message, at: .now)
                if case let .challenge(sequence) = verified.message { readRSSI(for: sequence) }
            case let .closed(error):
                failSecureLink(link, error: error)
            case .candidate, .pairingDisplayCleared: break
        }
    }

    private func readRSSI(for sequence: UInt32) {
        guard pendingRSSI == nil, let peripheral = self.peripheral, let link = activeLink else { return }
        peripheral.readRSSI()
        pendingRSSI = (sequence, link)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral === self.peripheral, let pendingRSSI,
              pendingRSSI.link == activeLink, let session, let link = activeLink else { return }
        self.pendingRSSI = nil
        let value = error == nil ? RSSI.intValue : nil
        let rssi = value.flatMap { (-127...20).contains($0) ? Int16($0) : nil }
        model.didReadAuthenticatedRSSI(rssi, at: .now)
        do { process(try session.send(.acknowledgement(sequence: pendingRSSI.sequence, rssi: rssi), on: link)) }
        catch { failSecureLink(link, error: error as? PeerSessionError ?? .authenticationFailed) }
    }

    private func flushWrites() {
        guard !writeInFlight, let frame = pendingFrames.first, let peripheral,
              let characteristic = acknowledgementCharacteristic else { return }
        pendingFrames.removeFirst()
        writeInFlight = true
        peripheral.writeValue(frame, for: characteristic, type: .withResponse)
    }

    private func failSecureLink(_ link: LinkID, error: PeerSessionError) {
        guard activeLink == link else { return }
        cancelPhaseDeadline()
        let wasEnrollment = enrollmentLink
        session?.close(link)
        reassembler?.discardIncompleteRecord()
        session = nil
        reassembler = nil
        activeLink = nil
        pendingFrames.removeAll()
        writeInFlight = false
        pairingPreparedRequestQueued = false
        pendingRSSI = nil
        scannedOffer?.invalidate()
        scannedOffer = nil
        cancelOfferExpiry()
        enrollmentLink = false
        var message = error == .pairingExpired
            ? "Pairing code expired. Create a new code on the Mac and scan again."
            : wasEnrollment ? "Pairing ended. Create a new code on the Mac and scan again."
            : "Secure connection failed. Scan again to reconnect."

        if error == .keychainUnavailable {
            identityStoreReady = false
            pairingState = .storageUnavailable
        } else if error == .pairingExpired {
            pairingState = .expired
        } else if error == .wrongPeer {
            do {
                if wasEnrollment {
                    pairingState = .qrMismatch
                    message = "The nearby Mac did not match the QR code. Scan a new code from the intended Mac."
                } else if try store.pairedIdentity() != nil {
                    pairingState = .untrustedMac
                    message = "This Mac does not match the saved identity. The saved pairing was kept."
                } else {
                    pairingState = .unpaired
                    message = "The Mac identity did not match the QR code. Scan again from the intended Mac."
                }
            } catch {
                identityStoreReady = false
                pairingState = .storageUnavailable
                message = "Secure storage is unavailable. The saved pairing was not changed."
            }
        } else if wasEnrollment {
            pairingState = .scanning
            message = "Pairing did not finish. Scan the one-use QR code again."
        } else if (try? store.pairedIdentity()) == nil {
            pairingState = .unpaired
        }
        connectionState = message
        model.didDisconnect(cause: .transportLost, at: .now)
        record(error == .pairingExpired ? "pairing_expired" : "secure_session_closed")
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }

    private func closeSession() {
        cancelPhaseDeadline()
        if let activeLink { session?.close(activeLink); reassembler?.discardIncompleteRecord() }
        session = nil
        reassembler = nil
        activeLink = nil
        pendingFrames.removeAll()
        writeInFlight = false
        pairingPreparedRequestQueued = false
        pendingRSSI = nil
        outgoingSequence = 0
        outgoingExhausted = false
    }

    private func scheduleRecovery(_ message: String) {
        cancelPhaseDeadline()
        recoveryAttempts += 1
        guard recoveryAttempts <= 3 else {
            canRetryConnection = true
            connectionState = "\(message) Tap Scan again to retry."
            return
        }
        canRetryConnection = false
        recoveryGeneration &+= 1
        let generation = recoveryGeneration
        recoveryTask?.cancel()
        connectionState = "\(message) Reconnecting…"
        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, !Task.isCancelled, self.recoveryGeneration == generation,
                  self.central.state == .poweredOn else { return }
            self.recoveryTask = nil
            self.startScan()
        }
    }

    private func cancelRecovery(resetAttempts: Bool) {
        recoveryGeneration &+= 1
        recoveryTask?.cancel()
        recoveryTask = nil
        if resetAttempts {
            recoveryAttempts = 0
            canRetryConnection = false
        }
    }

    private func scheduleOfferExpiry(for offer: ScannedOffer) {
        cancelOfferExpiry()
        offerExpiryTask = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: offer.expiresAt) } catch { return }
            guard let self, self.scannedOffer?.id == offer.id, !Task.isCancelled else { return }
            self.expireEnrollmentOffer()
        }
    }

    private func cancelOfferExpiry() {
        offerExpiryTask?.cancel()
        offerExpiryTask = nil
    }

    private func expireEnrollmentOffer() {
        cancelRecovery(resetAttempts: true)
        cancelOfferExpiry()
        central.stopScan()
        scannedOffer?.invalidate()
        scannedOffer = nil
        closeSession()
        enrollmentLink = false
        pairingState = .expired
        connectionState = "Pairing code expired. Create a new code on the Mac and scan again."
        model.didDisconnect(cause: .pairingStarted, at: .now)
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        challengeCharacteristic = nil
        acknowledgementCharacteristic = nil
    }

    private func armPhaseDeadline(_ phase: PhoneConnectionPhase, duration: Duration) {
        cancelPhaseDeadline()
        connectionPhase = phase
        let generation = phaseGeneration
        phaseDeadlineTask = Task { [weak self] in
            do { try await ContinuousClock().sleep(for: duration) } catch { return }
            guard let self, !Task.isCancelled, self.phaseGeneration == generation,
                  self.connectionPhase == phase else { return }
            self.phaseDeadlineTask = nil
            self.connectionPhase = nil
            if phase == .sessionAuthentication, let link = self.activeLink {
                self.failSecureLink(link, error: .transportLost)
            } else {
                self.model.didDisconnect(cause: .reconnectAttempt, at: .now)
                if let peripheral = self.peripheral { self.central.cancelPeripheralConnection(peripheral) }
                self.peripheral = nil
                self.challengeCharacteristic = nil
                self.acknowledgementCharacteristic = nil
                self.scheduleRecovery("The Mac connection timed out.")
            }
        }
    }

    private func cancelPhaseDeadline() {
        phaseGeneration &+= 1
        phaseDeadlineTask?.cancel()
        phaseDeadlineTask = nil
        connectionPhase = nil
    }

    private func clearEnrollmentAfterFailure(expired: Bool) {
        let wasEnrollment = enrollmentLink || scannedOffer != nil
        cancelOfferExpiry()
        scannedOffer?.invalidate()
        scannedOffer = nil
        enrollmentLink = false
        if expired {
            pairingState = .expired
        } else if wasEnrollment {
            pairingState = .scanning
        } else {
            restoreStoredPairingState()
        }
        connectionState = expired
            ? "Pairing code expired. Create a new code on the Mac and scan again."
            : "Pairing ended. Create a new code on the Mac and scan again."
    }

    private func restoreStoredPairingState() {
        do {
            pairingState = try store.pairedIdentity() == nil ? .unpaired : .paired
        } catch {
            identityStoreReady = false
            pairingState = .storageUnavailable
        }
    }

    private func stateName(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: "Bluetooth on"
        case .poweredOff: "Bluetooth off"
        case .unauthorized: "Bluetooth permission denied"
        case .unsupported: "Bluetooth unsupported"
        case .resetting: "Bluetooth resetting"
        case .unknown: "Bluetooth unknown"
        @unknown default: "Bluetooth unknown"
        }
    }

    private func record(_ event: String) {
        events.append("\(ISO8601DateFormatter().string(from: Date()))  \(event)")
        events = Array(events.suffix(200))
        UserDefaults.standard.set(events, forKey: eventsKey)
    }
}
