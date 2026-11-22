import CoreBluetooth
import Foundation
import SwiftUI

@MainActor
final class PhoneCentral: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published private(set) var bluetoothState = "Starting"
    @Published private(set) var connectionState = "Scanning"
    @Published private(set) var events: [String]

    private let restorationID = "com.hornley.nearbutfar.phone.central"
    private let eventsKey = "nearButFar.bleEvents"
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var challengeCharacteristic: CBCharacteristic?
    private var acknowledgementCharacteristic: CBCharacteristic?
    private var lastSequence: UInt32?
    private var presenceTimer: Timer?
    private(set) var connectionGeneration: UInt64 = 0
    private var rssiReadInFlight = false
    private var rssiReadGeneration: UInt64?
    private var pendingRSSISequence: UInt32?
    private var deferredRSSIChallenge: (sequence: UInt32, generation: UInt64)?
    let model: PhoneModel

    init(model: PhoneModel? = nil) {
        self.model = model ?? PhoneModel()
        events = UserDefaults.standard.stringArray(forKey: eventsKey) ?? []
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restorationID]
        )
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.refreshPresence()
            }
        }
    }

    func scanAgain() {
        guard central.state == .poweredOn else {
            connectionState = "Bluetooth unavailable"
            return
        }
        connectionGeneration &+= 1
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
            model.setBluetoothAvailable(true)
            scanAgain()
        } else {
            connectionState = "Bluetooth unavailable"
            model.setBluetoothAvailable(false)
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        record("core_bluetooth_restored")
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let restored = peripherals.first else { return }
        connectionGeneration &+= 1
        peripheral = restored
        restored.delegate = self
        connectionState = "Restoring connection"
        central.connect(restored)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        record("discovered_rssi_\(RSSI.intValue)")
        connectionGeneration &+= 1
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        connectionState = "Connecting"
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        connectionGeneration &+= 1
        record("connected")
        connectionState = "Discovering service"
        lastSequence = nil // The Mac restarts its challenge counter when its app restarts.
        challengeCharacteristic = nil
        acknowledgementCharacteristic = nil
        peripheral.delegate = self
        peripheral.discoverServices([BLEProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        record("connect_failed")
        connectionState = "Connection failed; scanning again"
        scanAgainAfterDelay()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        connectionGeneration &+= 1
        record("disconnected")
        connectionState = "Disconnected; scanning again"
        challengeCharacteristic = nil
        acknowledgementCharacteristic = nil
        model.didDisconnect(at: ContinuousClock.now)
        scanAgainAfterDelay()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BLEProtocol.serviceUUID }) else {
            record("service_discovery_failed")
            connectionState = "Service unavailable"
            return
        }
        peripheral.discoverCharacteristics([BLEProtocol.challengeUUID, BLEProtocol.acknowledgementUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
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
        guard peripheral === self.peripheral else { return }
        if error == nil, characteristic.isNotifying {
            connectionState = "Connected to Mac"
            record("subscribed_to_challenges")
            model.setBluetoothAvailable(true)
            model.didSubscribe(at: ContinuousClock.now)
        } else {
            connectionState = "Challenge subscription failed"
            record("subscription_failed")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil,
              characteristic.uuid == BLEProtocol.challengeUUID,
              let data = characteristic.value,
              let sequence = BLEProtocol.decodeChallenge(data),
              acknowledgementCharacteristic != nil else { return }

        if let lastSequence {
            if sequence < lastSequence {
                record("stale_challenge_\(sequence)")
                return
            }
        }
        if let lastSequence {
            if sequence > lastSequence { self.lastSequence = sequence }
        } else {
            lastSequence = sequence
        }
        let now = ContinuousClock.now
        model.didReceiveChallenge(at: now)
        if (pendingRSSISequence == sequence && rssiReadGeneration == connectionGeneration)
            || (deferredRSSIChallenge?.sequence == sequence && deferredRSSIChallenge?.generation == connectionGeneration) {
            record("duplicate_challenge_\(sequence)")
            return
        }
        guard !rssiReadInFlight else {
            deferredRSSIChallenge = (sequence, connectionGeneration)
            return
        }
        pendingRSSISequence = sequence
        startRSSIRead(on: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard rssiReadInFlight else { return }
        rssiReadInFlight = false
        let callbackGeneration = rssiReadGeneration
        rssiReadGeneration = nil
        let sequence = pendingRSSISequence
        pendingRSSISequence = nil
        guard peripheral === self.peripheral,
              callbackGeneration == connectionGeneration,
              let sequence,
              let acknowledgementCharacteristic else {
            startDeferredRSSIRead()
            return
        }

        let value = error == nil ? RSSI.intValue : nil
        let rssi: Int16? = value.flatMap { (-127...20).contains($0) ? Int16($0) : nil }
        let now = ContinuousClock.now
        model.didReadRSSI(rssi, at: now)
        peripheral.writeValue(
            BLEProtocol.encodeAcknowledgement(sequence: sequence, rssi: rssi),
            for: acknowledgementCharacteristic,
            type: .withResponse
        )
        record(rssi.map { "rssi_\($0)_ack_\(sequence)" } ?? "rssi_unavailable_ack_\(sequence)")
        startDeferredRSSIRead()
    }

    private func startRSSIRead(on peripheral: CBPeripheral) {
        guard !rssiReadInFlight, peripheral === self.peripheral else { return }
        rssiReadInFlight = true
        rssiReadGeneration = connectionGeneration
        peripheral.readRSSI()
    }

    private func startDeferredRSSIRead() {
        guard !rssiReadInFlight,
              let deferred = deferredRSSIChallenge,
              deferred.generation == connectionGeneration,
              let peripheral,
              acknowledgementCharacteristic != nil else {
            if deferredRSSIChallenge?.generation != connectionGeneration {
                deferredRSSIChallenge = nil
            }
            return
        }
        deferredRSSIChallenge = nil
        pendingRSSISequence = deferred.sequence
        startRSSIRead(on: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        record(error == nil ? "acknowledgement_written" : "acknowledgement_write_failed")
    }

    private func scanAgainAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.central.state == .poweredOn else { return }
            self.scanAgain()
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
