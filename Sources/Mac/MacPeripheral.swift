import Combine
import CoreBluetooth
import Foundation

final class MacPeripheral: NSObject, ObservableObject {
    @Published private(set) var bluetoothState = "Starting Bluetooth…"
    @Published private(set) var isSubscribed = false
    @Published private(set) var lastRSSI: Int16?
    @Published private(set) var countdown: Int?
    @Published private(set) var logPath = ""

    private var manager: CBPeripheralManager!
    private var challengeCharacteristic: CBMutableCharacteristic?
    private var acknowledgementCharacteristic: CBMutableCharacteristic?
    private var service: CBMutableService?
    private var logger: CSVLogger?
    private var tracker = PresenceTracker()
    private var nextSequence: UInt32 = 1
    private var outstandingSequence: UInt32?
    private var queuedAt: Date?
    private var lastQueuedAt: Date?
    private var retrySequence: UInt32?
    private var challengeTimer: Timer?
    private var presenceTimer: Timer?

    override init() {
        super.init()
        do {
            logger = try CSVLogger()
            logPath = logger?.fileURL.path ?? ""
        } catch {
            bluetoothState = "Log unavailable: \(error.localizedDescription)"
        }
        manager = CBPeripheralManager(delegate: self, queue: .main)
        challengeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.challengeInterval()
        }
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updatePresence()
        }
    }

    private func updateBluetoothState() {
        switch manager.state {
        case .poweredOn:
            bluetoothState = "Bluetooth on"
            if service == nil { installService() }
        case .poweredOff:
            bluetoothState = "Bluetooth off — monitoring unavailable"
            isSubscribed = false
            resetAdvertisement()
        case .unauthorized:
            bluetoothState = "Bluetooth access denied — monitoring unavailable"
            isSubscribed = false
            resetAdvertisement()
        case .unsupported:
            bluetoothState = "Bluetooth unsupported — monitoring unavailable"
            isSubscribed = false
            resetAdvertisement()
        case .resetting:
            bluetoothState = "Bluetooth resetting…"
            isSubscribed = false
            resetAdvertisement()
        case .unknown:
            bluetoothState = "Bluetooth state unavailable"
            isSubscribed = false
            resetAdvertisement()
        @unknown default:
            bluetoothState = "Bluetooth state unavailable"
            isSubscribed = false
            resetAdvertisement()
        }
        logger?.log("bluetooth_state", details: bluetoothState)
    }

    private func installService() {
        let challenge = CBMutableCharacteristic(type: BLEProtocol.challengeUUID, properties: [.notify], value: nil, permissions: [])
        let acknowledgement = CBMutableCharacteristic(type: BLEProtocol.acknowledgementUUID, properties: [.write], value: nil, permissions: [.writeable])
        let newService = CBMutableService(type: BLEProtocol.serviceUUID, primary: true)
        newService.characteristics = [challenge, acknowledgement]
        challengeCharacteristic = challenge
        acknowledgementCharacteristic = acknowledgement
        service = newService
        manager.add(newService)
    }

    private func challengeInterval() {
        guard manager.state == .poweredOn else { return }
        if let sequence = outstandingSequence {
            let now = Date()
            if let queuedAt, now.timeIntervalSince(queuedAt) >= 5, tracker.isArmed, tracker.lossStartedAt == nil {
                tracker.missedChallenge(at: now)
                logger?.log("missed_response", sequence: sequence)
            }
            if retrySequence == nil, let lastQueuedAt, now.timeIntervalSince(lastQueuedAt) >= 5 {
                publish(sequence)
            }
            return
        }
        guard isSubscribed else { return }
        let sequence = nextSequence
        nextSequence &+= 1
        outstandingSequence = sequence
        publish(sequence)
    }

    private func publish(_ sequence: UInt32) {
        guard let characteristic = challengeCharacteristic, isSubscribed else { return }
        if manager.updateValue(BLEProtocol.encodeChallenge(sequence), for: characteristic, onSubscribedCentrals: nil) {
            let now = Date()
            if queuedAt == nil { queuedAt = now }
            let isRetry = lastQueuedAt != nil
            lastQueuedAt = now
            retrySequence = nil
            logger?.log(isRetry ? "challenge_retransmitted" : "challenge_queued", sequence: sequence)
        } else {
            retrySequence = sequence
            logger?.log("challenge_queue_full", sequence: sequence)
        }
    }

    private func updatePresence() {
        let now = Date()
        countdown = tracker.secondsRemaining(at: now)
        if tracker.takeWouldLock(at: now), let started = tracker.lossStartedAt {
            logger?.log("would_lock", sequence: outstandingSequence, details: "elapsed_seconds=\(Int(now.timeIntervalSince(started)))")
        }
    }

    private func resetAdvertisement() {
        manager.stopAdvertising()
        manager.removeAllServices()
        service = nil
        challengeCharacteristic = nil
        acknowledgementCharacteristic = nil
        outstandingSequence = nil
        queuedAt = nil
        lastQueuedAt = nil
        retrySequence = nil
        tracker = PresenceTracker()
        countdown = nil
    }
}

extension MacPeripheral: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        updateBluetoothState()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            bluetoothState = "Service error: \(error.localizedDescription)"
            logger?.log("service_error", details: error.localizedDescription)
            return
        }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BLEProtocol.serviceUUID]])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            bluetoothState = "Advertising error: \(error.localizedDescription)"
            logger?.log("advertising_error", details: error.localizedDescription)
        } else {
            logger?.log("advertising_started")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        isSubscribed = true
        logger?.log("subscribed")
        if let retrySequence { publish(retrySequence) }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        isSubscribed = false
        logger?.log("unsubscribed")
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        if let sequence = retrySequence { publish(sequence) }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == BLEProtocol.acknowledgementUUID,
                  let value = request.value,
                  let acknowledgement = BLEProtocol.decodeAcknowledgement(value),
                  let expected = outstandingSequence,
                  queuedAt != nil,
                  acknowledgement.sequence == expected else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                logger?.log("invalid_acknowledgement")
                continue
            }
            lastRSSI = acknowledgement.rssi
            let now = Date()
            let wasCountingDown = tracker.lossStartedAt != nil
            tracker.observeRSSI(acknowledgement.rssi, at: now)
            if !wasCountingDown, tracker.lossStartedAt != nil, let rssi = acknowledgement.rssi {
                logger?.log("weak_signal", sequence: acknowledgement.sequence, rssi: rssi,
                            details: "threshold_dbm=\(PresenceTracker.weakSignalThreshold)")
            } else if wasCountingDown, tracker.lossStartedAt == nil, let rssi = acknowledgement.rssi {
                logger?.log("signal_recovered", sequence: acknowledgement.sequence, rssi: rssi)
            }
            countdown = tracker.secondsRemaining(at: now)
            logger?.log("acknowledgement", sequence: acknowledgement.sequence, rssi: acknowledgement.rssi, details: acknowledgement.rssi == nil ? "rssi_unavailable" : "")
            outstandingSequence = nil
            queuedAt = nil
            lastQueuedAt = nil
            retrySequence = nil
            peripheral.respond(to: request, withResult: .success)
        }
    }
}
