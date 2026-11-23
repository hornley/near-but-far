import CryptoKit
import Foundation
import Security

@MainActor
final class PhonePairedIdentityStore: PeerIdentityStore {
    private let service = "com.nearbutfar.identity"
    private let localAccount = "phone-local-v1"
    private let pairedAccount = "paired-mac-v1"

    func prepareForFreshInstall() throws {
        for account in [localAccount, pairedAccount] {
            let status = SecItemDelete(query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw PeerSessionError.keychainUnavailable
            }
        }
    }

    func loadOrCreateLocalIdentity() throws -> LocalIdentity {
        if let data = try read(localAccount) { return try decodeLocalIdentity(data) }
        let key = Curve25519.KeyAgreement.PrivateKey()
        let identity = try LocalIdentity(id: UUID(), publicKey: PeerPublicKey(validating: key.publicKey.rawRepresentation), privateKey: key.rawRepresentation)
        var data = encode(identity)
        defer { data.resetBytes(in: 0..<data.count) }
        if try insert(data, account: localAccount) { return identity }
        guard let saved = try read(localAccount) else { throw PeerSessionError.keychainUnavailable }
        return try decodeLocalIdentity(saved)
    }

    func pairedIdentity() throws -> PairedIdentity? {
        guard let data = try read(pairedAccount) else { return nil }
        guard data.count == 49, data[0] == 1 else { throw PeerSessionError.keychainUnavailable }
        return PairedIdentity(id: try UUIDBytes.decode(data[1..<17]), publicKey: try PeerPublicKey(validating: Data(data[17..<49])))
    }

    func replacePairedIdentity(with candidate: PairedIdentity) throws {
        var data = Data([1])
        data.append(contentsOf: UUIDBytes.encode(candidate.id))
        data.append(candidate.publicKey.data)
        try write(data, account: pairedAccount)
    }

    func forgetPairedIdentity() throws {
        let status = SecItemDelete(query(pairedAccount) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PeerSessionError.keychainUnavailable }
    }

    private func encode(_ identity: LocalIdentity) -> Data {
        var data = Data([1])
        data.append(contentsOf: UUIDBytes.encode(identity.id))
        identity.withPrivateKey { data.append($0) }
        data.append(identity.publicKey.data)
        return data
    }

    private func decodeLocalIdentity(_ data: Data) throws -> LocalIdentity {
        guard data.count == 81, data[0] == 1 else { throw PeerSessionError.keychainUnavailable }
        let privateKey = Data(data[17..<49])
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let storedKey = try PeerPublicKey(validating: Data(data[49..<81]))
        let publicKey = try PeerPublicKey(validating: key.publicKey.rawRepresentation)
        guard publicKey == storedKey else { throw PeerSessionError.keychainUnavailable }
        return try LocalIdentity(id: UUIDBytes.decode(data[1..<17]), publicKey: publicKey, privateKey: privateKey)
    }

    private func read(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PeerSessionError.keychainUnavailable }
        return data
    }

    private func insert(_ data: Data, account: String) throws -> Bool {
        var request = query(account)
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw PeerSessionError.keychainUnavailable }
        return true
    }

    private func write(_ data: Data, account: String) throws {
        let key = query(account)
        let updates = [kSecValueData as String: data]
        let status = SecItemUpdate(key as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var request = key
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(request as CFDictionary, nil)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else { throw PeerSessionError.keychainUnavailable }
            if addStatus == errSecDuplicateItem {
                guard SecItemUpdate(key as CFDictionary, updates as CFDictionary) == errSecSuccess else { throw PeerSessionError.keychainUnavailable }
            }
        } else if status != errSecSuccess { throw PeerSessionError.keychainUnavailable }
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
}
