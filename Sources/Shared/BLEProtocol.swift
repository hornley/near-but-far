import CoreBluetooth
import Foundation

enum BLEProtocol {
    static let serviceUUID = CBUUID(string: "F4A1D0F0-77A1-4F2D-A578-4B7B25D8C5A1")
    static let challengeUUID = CBUUID(string: "F4A1D0F1-77A1-4F2D-A578-4B7B25D8C5A1")
    static let acknowledgementUUID = CBUUID(string: "F4A1D0F2-77A1-4F2D-A578-4B7B25D8C5A1")

    struct Acknowledgement: Equatable {
        let sequence: UInt32
        let rssi: Int16?
    }

    static func encodeChallenge(_ sequence: UInt32) -> Data {
        var value = sequence.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    static func decodeChallenge(_ data: Data) -> UInt32? {
        guard data.count == 4 else { return nil }
        return data.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
    }

    static func encodeAcknowledgement(sequence: UInt32, rssi: Int16?) -> Data {
        var data = encodeChallenge(sequence)
        var rawRSSI = UInt16(bitPattern: rssi ?? .min).bigEndian
        withUnsafeBytes(of: &rawRSSI) { data.append(contentsOf: $0) }
        return data
    }

    static func decodeAcknowledgement(_ data: Data) -> Acknowledgement? {
        guard data.count == 6, let sequence = decodeChallenge(Data(data.prefix(4))) else { return nil }
        let rawRSSI = UInt16(data[4]) << 8 | UInt16(data[5])
        let rssi = rawRSSI == UInt16(bitPattern: Int16.min) ? nil : Int16(bitPattern: rawRSSI)
        return Acknowledgement(sequence: sequence, rssi: rssi)
    }
}
