import CryptoKit
import Foundation
import Security

enum AgentHTTPAuthentication {
    static let protocolVersion = "1"
    static let keyByteCount = 32
    static let nonceByteCount = 32

    static func nonce() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: nonceByteCount)
        let result = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        guard result == errSecSuccess else {
            throw AgentHTTPError.randomnessUnavailable
        }
        return Data(bytes)
    }

    static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    static func challengeProof(
        key: Data,
        clientNonce: Data,
        serverNonce: Data,
        generation: UInt64,
        port: UInt16,
        requestID: String
    ) -> Data {
        hmac(
            key: key,
            label: "rupa-agent/challenge/v1",
            fields: [
                clientNonce,
                serverNonce,
                uint64(generation),
                uint16(port),
                Data(protocolVersion.utf8),
                Data(requestID.utf8),
            ]
        )
    }

    static func clientProof(
        key: Data,
        clientNonce: Data,
        serverNonce: Data,
        generation: UInt64,
        port: UInt16,
        requestID: String,
        bodyDigest: Data
    ) -> Data {
        hmac(
            key: key,
            label: "rupa-agent/client/v1",
            fields: [
                clientNonce,
                serverNonce,
                uint64(generation),
                uint16(port),
                Data(protocolVersion.utf8),
                Data(requestID.utf8),
                bodyDigest,
            ]
        )
    }

    static func responseProof(
        key: Data,
        clientNonce: Data,
        serverNonce: Data,
        generation: UInt64,
        port: UInt16,
        requestID: String,
        status: Int,
        responseDigest: Data
    ) -> Data {
        hmac(
            key: key,
            label: "rupa-agent/response/v1",
            fields: [
                clientNonce,
                serverNonce,
                uint64(generation),
                uint16(port),
                Data(protocolVersion.utf8),
                Data(requestID.utf8),
                uint64(UInt64(max(status, 0))),
                responseDigest,
            ]
        )
    }

    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        let count = lhs.count
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            difference |= left ^ right
        }
        return difference == 0
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func decode(_ string: String) -> Data? {
        Data(base64Encoded: string)
    }

    private static func hmac(key: Data, label: String, fields: [Data]) -> Data {
        var transcript = Data(label.utf8)
        transcript.append(0)
        for field in fields {
            appendLength(field.count, to: &transcript)
            transcript.append(field)
        }
        return Data(
            HMAC<SHA256>.authenticationCode(
                for: transcript,
                using: SymmetricKey(data: key)
            )
        )
    }

    private static func appendLength(_ value: Int, to data: inout Data) {
        appendBytes(UInt64(value), to: &data)
    }

    private static func uint64(_ value: UInt64) -> Data {
        var value = value.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }

    private static func uint16(_ value: UInt16) -> Data {
        var value = value.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }

    private static func appendBytes(_ value: UInt64, to data: inout Data) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}
