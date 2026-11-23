import CryptoKit
import Foundation
import Security

@MainActor
final class MacPairedIdentityStore: PeerIdentityStore {
    private let service = "com.nearbutfar.identity"
    private let localAccount = "mac-local-v1"
    private let pairedAccount = "paired-phone-v1"

    func loadOrCreateLocalIdentity() throws -> LocalIdentity {
        if let data = try read(localAccount) {
            return try decodeLocalIdentity(data)
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let identity = try LocalIdentity(
            id: UUID(),
            publicKey: PeerPublicKey(validating: privateKey.publicKey.rawRepresentation),
            privateKey: privateKey.rawRepresentation
        )
        var record = encodeLocalIdentity(identity)
        defer { record.resetBytes(in: 0..<record.count) }
        if try insert(record, account: localAccount) { return identity }
        guard let saved = try read(localAccount) else { throw PeerSessionError.keychainUnavailable }
        return try decodeLocalIdentity(saved)
    }

    func pairedIdentity() throws -> PairedIdentity? {
        guard let data = try read(pairedAccount) else { return nil }
        guard data.count == 49, data[0] == 1 else { throw PeerSessionError.keychainUnavailable }
        let id = try UUIDBytes.decode(data[1..<17])
        let key = try PeerPublicKey(validating: Data(data[17..<49]))
        return PairedIdentity(id: id, publicKey: key)
    }

    func replacePairedIdentity(with candidate: PairedIdentity) throws {
        var record = Data([1])
        record.append(contentsOf: UUIDBytes.encode(candidate.id))
        record.append(candidate.publicKey.data)
        try write(record, account: pairedAccount)
    }

    func forgetPairedIdentity() throws {
        let status = SecItemDelete(query(for: pairedAccount) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PeerSessionError.keychainUnavailable
        }
    }

    func makePairingSecret() throws -> OneUseSecret {
        var bytes = Data(count: OneUseSecret.byteCount)
        let status = bytes.withUnsafeMutableBytes { raw in
            SecRandomCopyBytes(kSecRandomDefault, raw.count, raw.baseAddress!)
        }
        guard status == errSecSuccess else {
            bytes.resetBytes(in: 0..<bytes.count)
            throw PeerSessionError.internalFailure
        }
        defer { bytes.resetBytes(in: 0..<bytes.count) }
        return try OneUseSecret(validating: bytes)
    }

    private func encodeLocalIdentity(_ identity: LocalIdentity) -> Data {
        var record = Data([1])
        record.append(contentsOf: UUIDBytes.encode(identity.id))
        identity.withPrivateKey { record.append($0) }
        record.append(identity.publicKey.data)
        return record
    }

    private func decodeLocalIdentity(_ data: Data) throws -> LocalIdentity {
        guard data.count == 81, data[0] == 1 else { throw PeerSessionError.keychainUnavailable }
        let id = try UUIDBytes.decode(data[1..<17])
        let privateBytes = Data(data[17..<49])
        let storedPublic = try PeerPublicKey(validating: Data(data[49..<81]))
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateBytes)
        let derivedPublic = try PeerPublicKey(validating: key.publicKey.rawRepresentation)
        guard storedPublic == derivedPublic else { throw PeerSessionError.keychainUnavailable }
        return try LocalIdentity(id: id, publicKey: derivedPublic, privateKey: privateBytes)
    }

    private func read(_ account: String) throws -> Data? {
        var item: CFTypeRef?
        var request = query(for: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw PeerSessionError.keychainUnavailable
        }
        return data
    }

    private func write(_ data: Data, account: String) throws {
        let key = query(for: account)
        let updates: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(key as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = key
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                let retryStatus = SecItemUpdate(key as CFDictionary, updates as CFDictionary)
                guard retryStatus == errSecSuccess else { throw PeerSessionError.keychainUnavailable }
            } else if addStatus != errSecSuccess {
                throw PeerSessionError.keychainUnavailable
            }
        } else if status != errSecSuccess {
            throw PeerSessionError.keychainUnavailable
        }
    }

    private func insert(_ data: Data, account: String) throws -> Bool {
        var item = query(for: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw PeerSessionError.keychainUnavailable }
        return true
    }

    private func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}
