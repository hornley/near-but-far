import CoreBluetooth
import Foundation
import SwiftUI

enum PhonePresenceState: Equatable {
    case waiting
    case nearby
    case weakSignalCountdown(Int)
    case connectionLostCountdown(Int)
    case wouldLock
    case unavailable
}

private enum PresenceLossReason: Equatable {
    case weakSignal
    case connectionLost
}

@MainActor
final class PhoneCentral: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published private(set) var bluetoothState = "Starting"
    @Published private(set) var connectionState = "Scanning"
    @Published private(set) var lastRSSI: Int?
    @Published private(set) var events: [String]
    @Published private(set) var presenceState: PhonePresenceState = .waiting

    private let restorationID = "com.hornley.nearbutfar.phone.central"
    private let eventsKey = "nearButFar.bleEvents"
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var challengeCharacteristic: CBCharacteristic?
    private var acknowledgementCharacteristic: CBCharacteristic?
    private var lastSequence: UInt32?
    private var pendingRSSISequence: UInt32?
    private var presenceTracker = PresenceTracker()
    private var lastChallengeAt: Date?
    private var presenceTimer: Timer?
    private var presenceLossReason: PresenceLossReason?

    override init() {
        events = UserDefaults.standard.stringArray(forKey: eventsKey) ?? []
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restorationID]
        )
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPresence()
            }
        }
    }

    func scanAgain() {
        guard central.state == .poweredOn else {
            connectionState = "Bluetooth unavailable"
            return
        }
        peripheral = nil
        challengeCharacteristic = nil
        acknowledgementCharacteristic = nil
        central.stopScan()
        central.scanForPeripherals(withServices: [BLEProtocol.serviceUUID])
        connectionState = "Scanning for Mac"
        record("scan_started")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = stateName(central.state)
        record("bluetooth_\(bluetoothState.lowercased().replacingOccurrences(of: " ", with: "_"))")
        if central.state == .poweredOn {
            scanAgain()
        } else {
            connectionState = "Bluetooth unavailable"
            presenceTracker = PresenceTracker()
            lastChallengeAt = nil
            presenceLossReason = nil
            presenceState = .unavailable
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        record("core_bluetooth_restored")
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let restored = peripherals.first else { return }
        peripheral = restored
        restored.delegate = self
        connectionState = "Restoring connection"
        central.connect(restored)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        record("discovered_rssi_\(RSSI.intValue)")
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        connectionState = "Connecting"
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        record("connected")
        connectionState = "Discovering service"
        lastSequence = nil // The Mac restarts its challenge counter when its app restarts.
        pendingRSSISequence = nil
        peripheral.delegate = self
        peripheral.discoverServices([BLEProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        record("connect_failed")
        connectionState = "Connection failed; scanning again"
        scanAgainAfterDelay()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        record("disconnected")
        connectionState = "Disconnected; scanning again"
        challengeCharacteristic = nil
        acknowledgementCharacteristic = nil
        startEstimatedLoss(at: Date())
        refreshPresence()
        scanAgainAfterDelay()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BLEProtocol.serviceUUID }) else {
            record("service_discovery_failed")
            connectionState = "Service unavailable"
            return
        }
        peripheral.discoverCharacteristics([BLEProtocol.challengeUUID, BLEProtocol.acknowledgementUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            record("characteristic_discovery_failed")
            connectionState = "Characteristics unavailable"
            return
        }
        challengeCharacteristic = characteristics.first(where: { $0.uuid == BLEProtocol.challengeUUID })
        acknowledgementCharacteristic = characteristics.first(where: { $0.uuid == BLEProtocol.acknowledgementUUID })
        guard let challengeCharacteristic, acknowledgementCharacteristic != nil else {
            record("required_characteristic_missing")
            connectionState = "Characteristics unavailable"
            return
        }
        peripheral.setNotifyValue(true, for: challengeCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error == nil, characteristic.isNotifying {
            connectionState = "Connected to Mac"
            record("subscribed_to_challenges")
            let now = Date()
            lastChallengeAt = now
            if !presenceTracker.isArmed {
                presenceTracker.acknowledge(at: now)
            }
            refreshPresence(at: now)
        } else {
            connectionState = "Challenge subscription failed"
            record("subscription_failed")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              characteristic.uuid == BLEProtocol.challengeUUID,
              let data = characteristic.value,
              let sequence = BLEProtocol.decodeChallenge(data),
              acknowledgementCharacteristic != nil else { return }

        if let lastSequence, sequence < lastSequence {
            record("stale_challenge_\(sequence)")
            return
        }
        lastSequence = sequence
        pendingRSSISequence = sequence
        lastChallengeAt = Date()
        peripheral.readRSSI()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard let sequence = pendingRSSISequence,
              let acknowledgementCharacteristic,
              let peripheral = self.peripheral else { return }
        let rssi = error == nil ? Int16(clamping: RSSI.intValue) : nil
        lastRSSI = rssi.map(Int.init)
        let now = Date()
        let wasCountingDown = presenceTracker.lossStartedAt != nil
        presenceTracker.observeRSSI(rssi, at: now)
        if let rssi {
            if rssi <= PresenceTracker.weakSignalThreshold {
                presenceLossReason = .weakSignal
                if !wasCountingDown, presenceTracker.lossStartedAt != nil {
                    record("weak_signal_started_\(rssi)_dbm_threshold_\(PresenceTracker.weakSignalThreshold)")
                }
            } else {
                presenceLossReason = nil
                if wasCountingDown, presenceTracker.lossStartedAt == nil {
                    record("signal_recovered_\(rssi)_dbm")
                }
            }
        }
        let data = BLEProtocol.encodeAcknowledgement(sequence: sequence, rssi: rssi)
        peripheral.writeValue(data, for: acknowledgementCharacteristic, type: .withResponse)
        pendingRSSISequence = nil
        record(rssi.map { "rssi_\($0)_ack_\(sequence)" } ?? "rssi_unavailable_ack_\(sequence)")
        refreshPresence(at: now)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        record(error == nil ? "acknowledgement_written" : "acknowledgement_write_failed")
    }

    private func scanAgainAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.central.state == .poweredOn else { return }
            self.scanAgain()
        }
    }

    private func startEstimatedLoss(at time: Date) {
        guard presenceTracker.isArmed else { return }
        let wasCountingDown = presenceTracker.lossStartedAt != nil
        presenceTracker.missedChallenge(at: time)
        if presenceTracker.lossStartedAt != nil {
            presenceLossReason = .connectionLost
        }
        if !wasCountingDown, presenceTracker.lossStartedAt != nil {
            record("estimated_presence_lost")
        }
    }

    private func refreshPresence(at now: Date = Date()) {
        guard central.state == .poweredOn else {
            presenceState = .unavailable
            return
        }

        if let lastChallengeAt,
           presenceTracker.isArmed,
           presenceTracker.lossStartedAt == nil,
           now.timeIntervalSince(lastChallengeAt) >= 10 {
            startEstimatedLoss(at: lastChallengeAt.addingTimeInterval(10))
        }

        if presenceTracker.takeWouldLock(at: now) {
            record("phone_estimated_would_lock")
        }

        guard presenceTracker.isArmed else {
            presenceLossReason = nil
            presenceState = .waiting
            return
        }

        if let remaining = presenceTracker.secondsRemaining(at: now) {
            if remaining == 0 {
                presenceState = .wouldLock
            } else if presenceLossReason == .weakSignal {
                presenceState = .weakSignalCountdown(remaining)
            } else {
                presenceState = .connectionLostCountdown(remaining)
            }
        } else {
            presenceLossReason = nil
            presenceState = .nearby
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
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(event)"
        events.append(line)
        events = Array(events.suffix(200))
        UserDefaults.standard.set(events, forKey: eventsKey)
    }
}
