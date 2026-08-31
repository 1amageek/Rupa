import Foundation
import Security

struct ApplicationAgentAccessCredential: Equatable, Sendable {
    enum GenerationError: Error, Equatable, LocalizedError, Sendable {
        case secureRandomUnavailable(OSStatus)

        var errorDescription: String? {
            switch self {
            case .secureRandomUnavailable(let status):
                return "Secure random generation failed with status \(status)."
            }
        }
    }

    static let keyByteCount = 32

    let key: Data
    let generation: UInt64

    static func generate() throws -> ApplicationAgentAccessCredential {
        let key = try secureRandomData(count: keyByteCount)
        var generation: UInt64 = 0
        while generation == 0 {
            let bytes = try secureRandomData(count: MemoryLayout<UInt64>.size)
            generation = bytes.reduce(into: UInt64(0)) { value, byte in
                value = (value << 8) | UInt64(byte)
            }
        }
        return ApplicationAgentAccessCredential(
            key: key,
            generation: generation
        )
    }

    private static func secureRandomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(
                kSecRandomDefault,
                buffer.count,
                baseAddress
            )
        }
        guard status == errSecSuccess else {
            throw GenerationError.secureRandomUnavailable(status)
        }
        return Data(bytes)
    }
}
