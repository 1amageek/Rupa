import Foundation
import Security

/// Stores the live listener's short-lived key and endpoint in the Team Keychain.
public struct KeychainAgentDiscoveryStore: AgentDiscoveryRecordStore, Sendable {
    private let service: String
    private let account: String
    private let accessGroup: String

    public init(
        service: String,
        account: String,
        accessGroup: String
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    public func read() throws -> AgentDiscoveryRecord {
        try validateConfiguration()
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw map(status) }
        guard let data = result as? Data else {
            throw AgentDiscoveryError.malformed("The Keychain value is not binary data.")
        }
        do {
            return try JSONDecoder().decode(AgentDiscoveryRecord.self, from: data)
        } catch {
            throw AgentDiscoveryError.malformed("The Keychain value could not be decoded.")
        }
    }

    public func publish(_ record: AgentDiscoveryRecord) throws {
        try validateConfiguration()
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(record)
        } catch {
            throw AgentDiscoveryError.malformed("The discovery record could not be encoded.")
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrGeneric as String] = generationData(record.generation)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecDuplicateItem else {
            guard addStatus == errSecSuccess else { throw map(addStatus) }
            return
        }
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrGeneric as String: generationData(record.generation),
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        guard updateStatus == errSecSuccess else { throw map(updateStatus) }
    }

    public func remove(ifGeneration generation: UInt64) throws {
        try validateConfiguration()
        let current: AgentDiscoveryRecord
        do {
            current = try read()
        } catch let error as AgentDiscoveryError where isNotFound(error) {
            return
        }
        guard current.generation == generation else {
            throw AgentDiscoveryError.staleGeneration(
                expected: generation,
                actual: current.generation
            )
        }
        var query = baseQuery
        query[kSecAttrGeneric as String] = generationData(generation)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw map(status)
        }
        if status == errSecItemNotFound {
            do {
                let replacement = try read()
                throw AgentDiscoveryError.staleGeneration(
                    expected: generation,
                    actual: replacement.generation
                )
            } catch let error as AgentDiscoveryError where isNotFound(error) {
                return
            }
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func validateConfiguration() throws {
        guard !service.isEmpty, !account.isEmpty, !accessGroup.isEmpty else {
            throw AgentDiscoveryError.invalidConfiguration
        }
    }

    private func generationData(_ generation: UInt64) -> Data {
        var value = generation.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }

    private func map(_ status: OSStatus) -> AgentDiscoveryError {
        switch status {
        case errSecItemNotFound:
            return .unavailable("No live Rupa agent is published.")
        case errSecAuthFailed, errSecMissingEntitlement, errSecInteractionNotAllowed:
            return .unauthorized("The Team Keychain access group is unavailable.")
        default:
            return .unavailable("Keychain operation failed with status \(status).")
        }
    }

    private func isNotFound(_ error: AgentDiscoveryError) -> Bool {
        if case .unavailable(let message) = error {
            return message == "No live Rupa agent is published."
        }
        return false
    }
}
