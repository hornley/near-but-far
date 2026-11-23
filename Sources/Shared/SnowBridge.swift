import Foundation
import NearButFarSessionC

enum SnowBridgeError: Error {
    case status(Int32)
}

enum SnowRole: UInt32 { case phone = 1, mac = 2 }
enum SnowMode: UInt32 { case enrollment = 1, reconnect = 2 }

struct SnowHandshakeResult {
    let outbound: Data
    let finished: Bool
    let peerStaticKey: Data?
    let sessionID: Data?
}

final class SnowBridge {
    private var handle: OpaquePointer?

    init(role: SnowRole, mode: SnowMode, localPrivateKey: Data, localPublicKey: Data,
         expectedRemoteStaticKey: Data = Data(), pairingPSK: Data = Data(), offerID: Data = Data()) throws {
        var result: OpaquePointer?
        let status = Self.withBytes(localPrivateKey) { localPrivate in
            Self.withBytes(localPublicKey) { localPublic in
                Self.withBytes(expectedRemoteStaticKey) { expected in
                    Self.withBytes(pairingPSK) { psk in
                        Self.withBytes(offerID) { offer in
                            var config = NbfConfig(role: role.rawValue, mode: mode.rawValue,
                                                   local_private: localPrivate, local_public: localPublic,
                                                   expected_remote: expected, psk: psk, offer_id: offer)
                            return nbf_session_new(&config, &result)
                        }
                    }
                }
            }
        }
        try Self.check(status)
        guard let result else { throw SnowBridgeError.status(5) }
        handle = result
    }

    deinit { close() }

    func close() {
        guard let handle else { return }
        self.handle = nil
        _ = nbf_session_close(handle)
        nbf_session_free(handle)
    }

    func start() throws -> Data {
        let handle = try requireHandle()
        var bytes = [UInt8](repeating: 0, count: 1024)
        var written = 0
        var finished: UInt32 = 0
        let status = bytes.withUnsafeMutableBufferPointer { buffer in
            withUnsafeMutablePointer(to: &written) { writtenPointer in
                let output = NbfOutput(ptr: buffer.baseAddress, capacity: buffer.count, written: writtenPointer)
                return nbf_session_start(handle, output, &finished)
            }
        }
        try Self.check(status)
        return Data(bytes.prefix(written))
    }

    func receive(_ record: Data) throws -> SnowHandshakeResult {
        let handle = try requireHandle()
        var outbound = [UInt8](repeating: 0, count: 1024)
        var peer = [UInt8](repeating: 0, count: 32)
        var sessionID = [UInt8](repeating: 0, count: 32)
        var written = 0
        var peerWritten = 0
        var sessionWritten = 0
        var finished: UInt32 = 0
        let status = Self.withBytes(record) { input in
            outbound.withUnsafeMutableBufferPointer { outputBuffer in
                peer.withUnsafeMutableBufferPointer { peerBuffer in
                    sessionID.withUnsafeMutableBufferPointer { sessionBuffer in
                        withUnsafeMutablePointer(to: &written) { writtenPointer in
                            withUnsafeMutablePointer(to: &peerWritten) { peerWrittenPointer in
                                withUnsafeMutablePointer(to: &sessionWritten) { sessionWrittenPointer in
                                    let output = NbfOutput(ptr: outputBuffer.baseAddress, capacity: outputBuffer.count, written: writtenPointer)
                                    let peerOutput = NbfOutput(ptr: peerBuffer.baseAddress, capacity: peerBuffer.count, written: peerWrittenPointer)
                                    let sessionOutput = NbfOutput(ptr: sessionBuffer.baseAddress, capacity: sessionBuffer.count, written: sessionWrittenPointer)
                                    return nbf_session_receive(handle, input, output, &finished, peerOutput, sessionOutput)
                                }
                            }
                        }
                    }
                }
            }
        }
        try Self.check(status)
        return SnowHandshakeResult(outbound: Data(outbound.prefix(written)), finished: finished != 0,
                                   peerStaticKey: finished == 0 ? nil : Data(peer),
                                   sessionID: finished == 0 ? nil : Data(sessionID))
    }

    func seal(_ plaintext: Data) throws -> Data { try crypt(plaintext, sealing: true) }
    func open(_ ciphertext: Data) throws -> Data { try crypt(ciphertext, sealing: false) }

    private func crypt(_ input: Data, sealing: Bool) throws -> Data {
        let handle = try requireHandle()
        var outputBytes = [UInt8](repeating: 0, count: 1024)
        var written = 0
        let status = Self.withBytes(input) { borrowed in
            outputBytes.withUnsafeMutableBufferPointer { outputBuffer in
                withUnsafeMutablePointer(to: &written) { writtenPointer in
                    let output = NbfOutput(ptr: outputBuffer.baseAddress, capacity: outputBuffer.count, written: writtenPointer)
                    return sealing
                        ? nbf_session_seal(handle, borrowed, output)
                        : nbf_session_open(handle, borrowed, output)
                }
            }
        }
        try Self.check(status)
        return Data(outputBytes.prefix(written))
    }

    private func requireHandle() throws -> OpaquePointer {
        guard let handle else { throw SnowBridgeError.status(2) }
        return handle
    }

    private static func withBytes<R>(_ data: Data, _ body: (NbfBytes) throws -> R) rethrows -> R {
        try data.withUnsafeBytes { raw in
            try body(NbfBytes(ptr: raw.bindMemory(to: UInt8.self).baseAddress, len: raw.count))
        }
    }

    private static func check(_ status: Int32) throws {
        guard status == 0 else { throw SnowBridgeError.status(status) }
    }
}
