import Foundation

struct PeerPublicKey: Hashable {
    static let byteCount = 32
    private let bytes: Data

    init(validating bytes: Data) throws {
        guard bytes.count == Self.byteCount else { throw PeerSessionError.malformedRecord }
        self.bytes = bytes.withUnsafeBytes { raw in Data(bytes: raw.baseAddress!, count: raw.count) }
    }

    var data: Data { bytes }
}

struct LocalIdentity {
    let id: UUID
    let publicKey: PeerPublicKey
    private let privateKey: Data

    init(id: UUID, publicKey: PeerPublicKey, privateKey: Data) throws {
        guard privateKey.count == PeerPublicKey.byteCount else { throw PeerSessionError.internalFailure }
        self.id = id
        self.publicKey = publicKey
        self.privateKey = privateKey
    }

    func withPrivateKey<R>(_ body: (Data) throws -> R) rethrows -> R {
        try body(privateKey)
    }
}

struct PairedIdentity: Equatable {
    let id: UUID
    let publicKey: PeerPublicKey
}

@MainActor
protocol PeerIdentityStore: AnyObject {
    func loadOrCreateLocalIdentity() throws -> LocalIdentity
    func pairedIdentity() throws -> PairedIdentity?
    func replacePairedIdentity(with candidate: PairedIdentity) throws
    func forgetPairedIdentity() throws
}

final class OneUseSecret {
    static let byteCount = 32
    private var bytes: Data?

    init(validating bytes: Data) throws {
        guard bytes.count == Self.byteCount else { throw PeerSessionError.malformedRecord }
        self.bytes = bytes.withUnsafeBytes { raw in Data(bytes: raw.baseAddress!, count: raw.count) }
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        guard let bytes else { throw PeerSessionError.invalidState }
        return try bytes.withUnsafeBytes(body)
    }

    func invalidate() {
        guard var bytes = self.bytes else { return }
        self.bytes = nil
        bytes.resetBytes(in: 0..<bytes.count)
    }

    deinit { invalidate() }
}

struct PairingOffer {
    static let lifetime: Duration = .seconds(120)
    let id: UUID
    let macIdentityID: UUID
    let macPublicKey: PeerPublicKey
    let expiresAt: ContinuousClock.Instant
    private let secret: OneUseSecret

    init(id: UUID, macIdentityID: UUID, macPublicKey: PeerPublicKey,
         expiresAt: ContinuousClock.Instant, secret: OneUseSecret) {
        self.id = id
        self.macIdentityID = macIdentityID
        self.macPublicKey = macPublicKey
        self.expiresAt = expiresAt
        self.secret = secret
    }

    func withSecret<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        try secret.withUnsafeBytes(body)
    }

    func invalidate() { secret.invalidate() }

    func withQRPayload(_ body: (String) throws -> Void) throws {
        guard expiresAt > .now else { invalidate(); throw PeerSessionError.pairingExpired }
        try secret.withUnsafeBytes { secretBytes in
            var payload = Data([1])
            payload.append(contentsOf: UUIDBytes.encode(id))
            payload.append(contentsOf: UUIDBytes.encode(macIdentityID))
            payload.append(macPublicKey.data)
            payload.append(contentsOf: secretBytes)
            defer { payload.resetBytes(in: 0..<payload.count) }
            try body("nearbutfar://pair/v1/" + Self.base64URL(payload))
        }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct ScannedOffer {
    static let lifetime: Duration = .seconds(120)
    let id: UUID
    let macIdentityID: UUID
    let macPublicKey: PeerPublicKey
    let expiresAt: ContinuousClock.Instant
    private let secret: OneUseSecret

    init(validating qrPayload: String, now: ContinuousClock.Instant = .now) throws {
        let prefix = "nearbutfar://pair/v1/"
        guard qrPayload.utf8.count == prefix.utf8.count + 130,
              qrPayload.hasPrefix(prefix) else { throw PeerSessionError.malformedRecord }
        let encoded = String(qrPayload.dropFirst(prefix.count))
        guard Array(encoded.utf8).allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else {
            throw PeerSessionError.malformedRecord
        }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard var bytes = Data(base64Encoded: base64) else { throw PeerSessionError.malformedRecord }
        defer { bytes.resetBytes(in: 0..<bytes.count) }
        guard bytes.count == 97,
              Self.base64URL(bytes) == encoded, bytes[0] == 1 else {
            throw PeerSessionError.malformedRecord
        }
        id = try UUIDBytes.decode(bytes[1..<17])
        macIdentityID = try UUIDBytes.decode(bytes[17..<33])
        macPublicKey = try PeerPublicKey(validating: Data(bytes[33..<65]))
        secret = try OneUseSecret(validating: Data(bytes[65..<97]))
        expiresAt = now.advanced(by: Self.lifetime)
    }

    func withSecret<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        try secret.withUnsafeBytes(body)
    }

    func invalidate() { secret.invalidate() }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum UUIDBytes {
    static func encode(_ id: UUID) -> Data { withUnsafeBytes(of: id.uuid) { Data($0) } }

    static func decode(_ bytes: Data.SubSequence) throws -> UUID {
        guard bytes.count == 16 else { throw PeerSessionError.malformedRecord }
        let value = Array(bytes)
        return UUID(uuid: (
            value[0], value[1], value[2], value[3], value[4], value[5], value[6], value[7],
            value[8], value[9], value[10], value[11], value[12], value[13], value[14], value[15]
        ))
    }
}
