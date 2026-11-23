import CoreBluetooth
import Foundation

enum BLEProtocol {
    static let maximumRecordSize = 1_024
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
        let bytes = Array(data)
        guard bytes.count == 6, let sequence = decodeChallenge(Data(bytes.prefix(4))) else { return nil }
        let rawRSSI = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        let rssi = rawRSSI == UInt16(bitPattern: Int16.min) ? nil : Int16(bitPattern: rawRSSI)
        return Acknowledgement(sequence: sequence, rssi: rssi)
    }

    static func fragment(_ record: Data, sequence: UInt32) throws -> [Data] {
        guard !record.isEmpty, record.count <= maximumRecordSize else { throw PeerSessionError.malformedRecord }
        let bytes = Array(record)
        let fragmentCount = (bytes.count + 8) / 9
        var fragments: [Data] = []
        fragments.reserveCapacity(fragmentCount)
        for index in 0..<fragmentCount {
            let start = index * 9
            let end = min(start + 9, bytes.count)
            var frame = Data([0x4e, 0x42, 1])
            frame.append(contentsOf: [UInt8(sequence >> 24), UInt8((sequence >> 16) & 0xff),
                                      UInt8((sequence >> 8) & 0xff), UInt8(sequence & 0xff)])
            frame.append(UInt8(index))
            frame.append(UInt8(fragmentCount))
            frame.append(UInt8(bytes.count >> 8))
            frame.append(UInt8(bytes.count & 0xff))
            frame.append(contentsOf: bytes[start..<end])
            fragments.append(frame)
        }
        return fragments
    }

    @MainActor
    final class RecordReassembler {
        private struct Partial {
            let sequence: UInt32
            let count: Int
            let length: Int
            let expiresAt: ContinuousClock.Instant
            var nextIndex: Int
            var bytes: Data
        }

        let link: LinkID
        private let closeLink: (LinkID) -> Void
        private var expectedSequence: UInt32 = 0
        private var sequenceExhausted = false
        private var partial: Partial?
        private var expiryTask: Task<Void, Never>?

        init(link: LinkID, closeLink: @escaping (LinkID) -> Void) {
            self.link = link
            self.closeLink = closeLink
        }

        func append(_ frame: Data, at now: ContinuousClock.Instant = .now) throws -> Data? {
            let bytes = Array(frame)
            guard !sequenceExhausted, (12...20).contains(bytes.count),
                  bytes[0] == 0x4e, bytes[1] == 0x42, bytes[2] == 1 else {
                try reject(.malformedRecord)
            }
            let sequence = Self.readUInt32(Array(bytes[3..<7]))
            let index = Int(bytes[7])
            let count = Int(bytes[8])
            let length = Int(bytes[9]) << 8 | Int(bytes[10])
            let payload = Data(bytes[11..<bytes.count])
            let expectedCount = (length + 8) / 9
            let expectedPayload = min(9, length - index * 9)
            guard (1...BLEProtocol.maximumRecordSize).contains(length),
                  count == expectedCount, (1...114).contains(count), index < count,
                  payload.count == expectedPayload else { try reject(.malformedRecord) }

            if var partial {
                guard now < partial.expiresAt else { try reject(.recordExpired) }
                guard partial.sequence == sequence, partial.count == count,
                      partial.length == length, index == partial.nextIndex else {
                    try reject(.malformedRecord)
                }
                partial.bytes.append(payload)
                partial.nextIndex += 1
                if partial.nextIndex == partial.count {
                    guard partial.bytes.count == partial.length else { try reject(.malformedRecord) }
                    self.partial = nil
                    expiryTask?.cancel()
                    expiryTask = nil
                    advanceSequence()
                    return partial.bytes
                }
                self.partial = partial
                return nil
            }

            guard sequence == expectedSequence, index == 0 else { try reject(.malformedRecord) }
            if count == 1 {
                guard payload.count == length else { try reject(.malformedRecord) }
                advanceSequence()
                return payload
            }
            partial = Partial(sequence: sequence, count: count, length: length,
                              expiresAt: now.advanced(by: .seconds(30)), nextIndex: 1, bytes: payload)
            scheduleExpiry(sequence)
            return nil
        }

        func discardIncompleteRecord() {
            partial = nil
            expiryTask?.cancel()
            expiryTask = nil
        }

        private func reject(_ error: PeerSessionError) throws -> Never {
            discardIncompleteRecord()
            closeLink(link)
            throw error
        }

        private func scheduleExpiry(_ sequence: UInt32) {
            expiryTask?.cancel()
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.partial?.sequence == sequence else { return }
                self.discardIncompleteRecord()
                self.closeLink(self.link)
            }
        }

        private func advanceSequence() {
            if expectedSequence == .max {
                sequenceExhausted = true
            } else {
                expectedSequence += 1
            }
        }

        private static func readUInt32(_ bytes: [UInt8]) -> UInt32 {
            bytes.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
        }
    }
}
