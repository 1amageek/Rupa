import Foundation

public enum StableDigest {
    public static func sha256Hex(for data: Data) -> String {
        var hasher = StableSHA256Hasher()
        hasher.update(data)
        return hasher.hexDigest()
    }
}

public struct StableSHA256Hasher: Sendable {
    private static let initialState: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]

    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private var state: [UInt32]
    private var pendingBytes: [UInt8]
    private var byteCount: UInt64

    public init() {
        state = Self.initialState
        pendingBytes = []
        pendingBytes.reserveCapacity(64)
        byteCount = 0
    }

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { bytes in
            update(bytes)
        }
    }

    public mutating func update(string: String) {
        update(count: string.utf8.count)
        for byte in string.utf8 {
            update(byte: byte)
        }
    }

    public mutating func update(count: Int) {
        update(UInt64(count))
    }

    public mutating func update(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            update(bytes)
        }
    }

    public mutating func update(_ value: UInt32) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            update(bytes)
        }
    }

    public mutating func update(byte: UInt8) {
        byteCount &+= 1
        pendingBytes.append(byte)
        if pendingBytes.count == 64 {
            processPendingBlock()
        }
    }

    public func hexDigest() -> String {
        let words = finalizedWords()
        let digits = Array("0123456789abcdef".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(64)
        for word in words {
            for shift in stride(from: 28, through: 0, by: -4) {
                output.append(digits[Int((word >> UInt32(shift)) & 0x0f)])
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private mutating func update(_ bytes: UnsafeRawBufferPointer) {
        guard !bytes.isEmpty else {
            return
        }
        byteCount &+= UInt64(bytes.count)
        var offset = 0

        if !pendingBytes.isEmpty {
            let required = min(64 - pendingBytes.count, bytes.count)
            pendingBytes.append(contentsOf: bytes.prefix(required))
            offset += required
            if pendingBytes.count == 64 {
                processPendingBlock()
            }
        }

        while offset + 64 <= bytes.count {
            process(UnsafeRawBufferPointer(rebasing: bytes[offset..<(offset + 64)]))
            offset += 64
        }

        if offset < bytes.count {
            pendingBytes.append(contentsOf: bytes[offset..<bytes.count])
        }
    }

    private mutating func processPendingBlock() {
        pendingBytes.withUnsafeBytes { bytes in
            process(bytes)
        }
        pendingBytes.removeAll(keepingCapacity: true)
    }

    private mutating func process(_ block: UnsafeRawBufferPointer) {
        precondition(block.count == 64)
        var words = Array(repeating: UInt32(0), count: 64)
        for index in 0..<16 {
            let offset = index * 4
            words[index] = UInt32(block[offset]) << 24
                | UInt32(block[offset + 1]) << 16
                | UInt32(block[offset + 2]) << 8
                | UInt32(block[offset + 3])
        }
        for index in 16..<64 {
            words[index] = Self.smallSigma1(words[index - 2])
                &+ words[index - 7]
                &+ Self.smallSigma0(words[index - 15])
                &+ words[index - 16]
        }

        var a = state[0]
        var b = state[1]
        var c = state[2]
        var d = state[3]
        var e = state[4]
        var f = state[5]
        var g = state[6]
        var h = state[7]

        for index in 0..<64 {
            let temporary1 = h
                &+ Self.bigSigma1(e)
                &+ Self.choose(e, f, g)
                &+ Self.roundConstants[index]
                &+ words[index]
            let temporary2 = Self.bigSigma0(a) &+ Self.majority(a, b, c)
            h = g
            g = f
            f = e
            e = d &+ temporary1
            d = c
            c = b
            b = a
            a = temporary1 &+ temporary2
        }

        state[0] = state[0] &+ a
        state[1] = state[1] &+ b
        state[2] = state[2] &+ c
        state[3] = state[3] &+ d
        state[4] = state[4] &+ e
        state[5] = state[5] &+ f
        state[6] = state[6] &+ g
        state[7] = state[7] &+ h
    }

    private func finalizedWords() -> [UInt32] {
        var copy = self
        let bitLength = copy.byteCount &* 8
        copy.pendingBytes.append(0x80)
        while copy.pendingBytes.count % 64 != 56 {
            copy.pendingBytes.append(0)
        }
        var bigEndianBitLength = bitLength.bigEndian
        withUnsafeBytes(of: &bigEndianBitLength) { bytes in
            copy.pendingBytes.append(contentsOf: bytes)
        }
        var offset = 0
        while offset < copy.pendingBytes.count {
            copy.pendingBytes.withUnsafeBytes { bytes in
                copy.process(
                    UnsafeRawBufferPointer(rebasing: bytes[offset..<(offset + 64)])
                )
            }
            offset += 64
        }
        return copy.state
    }

    private static func rotateRight(_ value: UInt32, by shift: UInt32) -> UInt32 {
        (value >> shift) | (value << (32 - shift))
    }

    private static func choose(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) ^ (~x & z)
    }

    private static func majority(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) ^ (x & z) ^ (y & z)
    }

    private static func bigSigma0(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 2) ^ rotateRight(value, by: 13) ^ rotateRight(value, by: 22)
    }

    private static func bigSigma1(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 6) ^ rotateRight(value, by: 11) ^ rotateRight(value, by: 25)
    }

    private static func smallSigma0(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 7) ^ rotateRight(value, by: 18) ^ (value >> 3)
    }

    private static func smallSigma1(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 17) ^ rotateRight(value, by: 19) ^ (value >> 10)
    }
}
