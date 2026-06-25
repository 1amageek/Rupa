import Foundation

struct PatternArrayStableDigest: Sendable {
    private var value: UInt64 = 0xcbf29ce484222325

    mutating func append(_ byte: UInt8) {
        value ^= UInt64(byte)
        value &*= 0x100000001b3
    }

    mutating func append(_ data: Data) {
        for byte in data {
            append(byte)
        }
    }

    func hexValue() -> String {
        String(format: "%016llx", value)
    }

    static func hexDigest(for data: Data) -> String {
        var digest = PatternArrayStableDigest()
        digest.append(data)
        return digest.hexValue()
    }
}
