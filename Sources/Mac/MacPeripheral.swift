import CoreBluetooth
import Foundation

enum MacTransportEvent {
    case bluetoothState(String)
    case secureLinkOpened(LinkID)
    case secureRecord(LinkID, Data)
    case secureLinkClosed(LinkID)
    case log(String, details: String)
}

@MainActor
final class MacPeripheral: NSObject {
    private struct Link {
        let id: LinkID
        let central: CBCentral
        let reassembler: BLEProtocol.RecordReassembler
        var outgoingSequence: UInt32 = 0
        var outgoingSequenceExhausted = false
        var pendingFrames: [Data] = []
        var pendingFrameIndex = 0
    }

    var onEvent: ((MacTransportEvent) -> Void)?

    private var manager: CBPeripheralManager!
    private var challengeCharacteristic: CBMutableCharacteristic?
    private var acknowledgementCharacteristic: CBMutableCharacteristic?
    private var service: CBMutableService?
    private var linksByCentral: [UUID: Link] = [:]
    private var centralByLink: [LinkID: UUID] = [:]
    private var activeLink: LinkID?
    private(set) var authenticatedCentralID: UUID?
    private var authenticationDeadlineTask: Task<Void, Never>?
    private var authenticationDeadlineLink: LinkID?

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func send(_ records: [OutboundRecord], on linkID: LinkID) -> Bool {
        guard activeLink == linkID,
              let centralID = centralByLink[linkID],
              var link = linksByCentral[centralID],
              link.id == linkID else { return false }

        for record in records {
            guard record.link == linkID, !link.outgoingSequenceExhausted else {
                closeSecureLink(linkID)
                return false
            }
            let frames: [Data]
            do { frames = try BLEProtocol.fragment(record.bytes, sequence: link.outgoingSequence) }
            catch {
                closeSecureLink(linkID)
                return false
            }
            guard link.pendingFrames.count - link.pendingFrameIndex + frames.count <= 128 else {
                closeSecureLink(linkID)
                return false
            }
            link.pendingFrames.append(contentsOf: frames)
            if link.outgoingSequence == .max {
                link.outgoingSequenceExhausted = true
            } else {
                link.outgoingSequence += 1
            }
        }
        linksByCentral[centralID] = link
        flushOutbound(on: centralID)
        return true
    }

    func markAuthenticated(_ linkID: LinkID) -> Bool {
        guard activeLink == linkID,
              let centralID = centralByLink[linkID],
              linksByCentral[centralID]?.id == linkID else { return false }
        authenticatedCentralID = centralID
        cancelAuthenticationDeadline(for: linkID)
        return true
    }

    func armAuthenticationDeadline(for linkID: LinkID, after duration: Duration = .seconds(20)) {
        guard activeLink == linkID, authenticatedCentralID == nil else { return }
        cancelAuthenticationDeadline()
        authenticationDeadlineLink = linkID
        authenticationDeadlineTask = Task { [weak self] in
            do { try await ContinuousClock().sleep(for: duration) } catch { return }
            guard let self, !Task.isCancelled, self.activeLink == linkID,
                  self.authenticatedCentralID == nil,
                  self.authenticationDeadlineLink == linkID else { return }
            self.cancelAuthenticationDeadline(for: linkID)
            self.closeSecureLink(linkID)
        }
    }

    func closeSecureLink(_ linkID: LinkID) {
        guard let centralID = centralByLink.removeValue(forKey: linkID),
              let link = linksByCentral.removeValue(forKey: centralID), link.id == linkID else { return }
        link.reassembler.discardIncompleteRecord()
        if activeLink == linkID { activeLink = nil }
        cancelAuthenticationDeadline(for: linkID)
        if authenticatedCentralID == centralID { authenticatedCentralID = nil }
        onEvent?(.secureLinkClosed(linkID))
    }

    func closeCurrentLink() {
        guard let activeLink else { return }
        closeSecureLink(activeLink)
    }

    private func cancelAuthenticationDeadline(for linkID: LinkID? = nil) {
        if let linkID, authenticationDeadlineLink != linkID { return }
        authenticationDeadlineTask?.cancel()
        authenticationDeadlineTask = nil
        authenticationDeadlineLink = nil
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
            closeCurrentLink()
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

    private func openSecureLink(for central: CBCentral) {
        guard linksByCentral[central.identifier] == nil, activeLink == nil else { return }
        let id = LinkID(rawValue: UUID())
        let reassembler = BLEProtocol.RecordReassembler(link: id) { [weak self] closedLink in
            self?.closeSecureLink(closedLink)
        }
        let link = Link(id: id, central: central, reassembler: reassembler)
        linksByCentral[central.identifier] = link
        centralByLink[id] = central.identifier
        activeLink = id
        onEvent?(.secureLinkOpened(id))
    }

    private func flushOutbound(on centralID: UUID) {
        guard var link = linksByCentral[centralID], activeLink == link.id,
              let characteristic = challengeCharacteristic else { return }
        while link.pendingFrameIndex < link.pendingFrames.count {
            let frame = link.pendingFrames[link.pendingFrameIndex]
            guard manager.updateValue(frame, for: characteristic, onSubscribedCentrals: [link.central]) else {
                linksByCentral[centralID] = link
                return
            }
            link.pendingFrameIndex += 1
        }
        link.pendingFrames.removeAll(keepingCapacity: false)
        link.pendingFrameIndex = 0
        linksByCentral[centralID] = link
    }
}

extension MacPeripheral: @preconcurrency CBPeripheralManagerDelegate {
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
        guard characteristic.uuid == BLEProtocol.challengeUUID else { return }
        openSecureLink(for: central)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic.uuid == BLEProtocol.challengeUUID,
              let link = linksByCentral[central.identifier]?.id else { return }
        closeSecureLink(link)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let centralID = activeLink.flatMap({ centralByLink[$0] }) else { return }
        flushOutbound(on: centralID)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == BLEProtocol.acknowledgementUUID,
                  let link = linksByCentral[request.central.identifier],
                  link.central.identifier == request.central.identifier,
                  link.id == activeLink,
                  authenticatedCentralID == nil || authenticatedCentralID == request.central.identifier,
                  let value = request.value else {
                peripheral.respond(to: request, withResult: .insufficientAuthentication)
                continue
            }

            do {
                let record = try link.reassembler.append(value)
                peripheral.respond(to: request, withResult: .success)
                if let record { onEvent?(.secureRecord(link.id, record)) }
            } catch {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            }
        }
    }
}
