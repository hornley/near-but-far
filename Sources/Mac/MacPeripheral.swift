import CoreBluetooth
import Foundation

enum MacTransportEvent {
    case bluetoothState(String)
    case subscriptionChanged(Bool)
    case acknowledgement(BLEProtocol.Acknowledgement, respond: (CBATTError.Code) -> Void)
    case readyToUpdate
    case log(String, details: String)
}

final class MacPeripheral: NSObject {
    var onEvent: ((MacTransportEvent) -> Void)?

    private var manager: CBPeripheralManager!
    private var challengeCharacteristic: CBMutableCharacteristic?
    private var acknowledgementCharacteristic: CBMutableCharacteristic?
    private var service: CBMutableService?

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    @discardableResult
    func publish(_ action: ChallengeAction) -> Bool {
        guard let characteristic = challengeCharacteristic else { return false }
        return manager.updateValue(BLEProtocol.encodeChallenge(action.sequence), for: characteristic, onSubscribedCentrals: nil)
    }

    private func updateBluetoothState() {
        let state: String
        switch manager.state {
        case .poweredOn:
            state = "Bluetooth on"
            if service == nil { installService() }
        case .poweredOff:
            state = "Bluetooth off — monitoring unavailable"
        case .unauthorized:
            state = "Bluetooth access denied — monitoring unavailable"
        case .unsupported:
            state = "Bluetooth unsupported — monitoring unavailable"
        case .resetting:
            state = "Bluetooth resetting…"
        case .unknown:
            state = "Bluetooth state unavailable"
        @unknown default:
            state = "Bluetooth state unavailable"
        }
        if manager.state != .poweredOn {
            manager.stopAdvertising()
            manager.removeAllServices()
            service = nil
            challengeCharacteristic = nil
            acknowledgementCharacteristic = nil
        }
        onEvent?(.bluetoothState(state))
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
}

extension MacPeripheral: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        updateBluetoothState()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            onEvent?(.bluetoothState("Service error: \(error.localizedDescription)"))
            onEvent?(.log("service_error", details: error.localizedDescription))
        } else {
            peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BLEProtocol.serviceUUID]])
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            onEvent?(.bluetoothState("Advertising error: \(error.localizedDescription)"))
            onEvent?(.log("advertising_error", details: error.localizedDescription))
        } else {
            onEvent?(.log("advertising_started", details: ""))
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        onEvent?(.subscriptionChanged(true))
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        onEvent?(.subscriptionChanged(false))
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        onEvent?(.readyToUpdate)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == BLEProtocol.acknowledgementUUID,
                  let value = request.value,
                  let acknowledgement = BLEProtocol.decodeAcknowledgement(value) else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                continue
            }
            onEvent?(.acknowledgement(acknowledgement, respond: { result in
                peripheral.respond(to: request, withResult: result)
            }))
        }
    }
}

private extension ChallengeAction {
    var sequence: UInt32 {
        switch self {
        case let .sendNew(sequence), let .retry(sequence): sequence
        }
    }
}
