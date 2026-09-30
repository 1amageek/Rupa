import Foundation

public enum StableDigest {
    public static func sha256Hex(for data: Data) -> String {
        var hasher = StableSHA256Hasher()
        hasher.update(data)
        return hasher.hexDigest()
    }
}

/// Streaming SHA-256 (FIPS 180-4).
///
/// Hashing allocates nothing per block: full blocks are read in place from the caller's bytes
/// through one stack message schedule, only a partial block waits in `pendingBytes`, and the
/// padded tail is built in a stack buffer when the digest is read.
public struct StableSHA256Hasher: Sendable {
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

    /// The working hash value H(i).
    private struct State: Sendable {
        var h0: UInt32 = 0x6a09e667
        var h1: UInt32 = 0xbb67ae85
        var h2: UInt32 = 0x3c6ef372
        var h3: UInt32 = 0xa54ff53a
        var h4: UInt32 = 0x510e527f
        var h5: UInt32 = 0x9b05688c
        var h6: UInt32 = 0x1f83d9ab
        var h7: UInt32 = 0x5be0cd19

        var words: [UInt32] { [h0, h1, h2, h3, h4, h5, h6, h7] }
    }

    private var state: State
    /// The bytes of a block not yet complete, fewer than 64.
    private var pendingBytes: [UInt8]
    private var byteCount: UInt64

    public init() {
        state = State()
        pendingBytes = []
        pendingBytes.reserveCapacity(64)
        byteCount = 0
    }

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { bytes in
            update(bytes)
        }
    }

    /// Hashes a synchronously borrowed byte span without materializing `Data`.
    public mutating func update(_ bytes: borrowing Span<UInt8>) {
        bytes.withUnsafeBytes { rawBytes in
            update(rawBytes)
        }
    }

    /// Hashes the UTF-8 byte count followed by the UTF-8 bytes.
    public mutating func update(string: String) {
        var string = string
        update(count: string.utf8.count)
        string.withUTF8 { bytes in
            update(UnsafeRawBufferPointer(bytes))
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
            compressPendingBlock()
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
            pendingBytes.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[0..<required]))
            offset = required
            if pendingBytes.count == 64 {
                compressPendingBlock()
            }
        }

        let fullByteCount = (bytes.count - offset) / 64 * 64
        if fullByteCount > 0 {
            Self.compressBlocks(
                UnsafeRawBufferPointer(rebasing: bytes[offset..<(offset + fullByteCount)]),
                into: &state
            )
            offset += fullByteCount
        }

        if offset < bytes.count {
            pendingBytes.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[offset..<bytes.count]))
        }
    }

    private mutating func compressPendingBlock() {
        pendingBytes.withUnsafeBytes { block in
            Self.compressBlocks(block, into: &state)
        }
        pendingBytes.removeAll(keepingCapacity: true)
    }

    /// The digest words after padding: the pending bytes, the 0x80 marker and the big-endian bit
    /// length, which span two blocks when the pending bytes leave no room for the length.
    private func finalizedWords() -> [UInt32] {
        var state = self.state
        let pendingCount = pendingBytes.count
        let tailCount = pendingCount < 56 ? 64 : 128
        let bitLength = byteCount &* 8
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 128) { tail in
            tail.initialize(repeating: 0)
            for index in 0..<pendingCount {
                tail[index] = pendingBytes[index]
            }
            tail[pendingCount] = 0x80
            for index in 0..<8 {
                tail[tailCount - 1 - index] = UInt8(truncatingIfNeeded: bitLength >> (UInt64(index) * 8))
            }
            Self.compressBlocks(
                UnsafeRawBufferPointer(rebasing: UnsafeRawBufferPointer(tail)[0..<tailCount]),
                into: &state
            )
        }
        return state.words
    }

    /// Folds whole 64-byte blocks into `state`.
    private static func compressBlocks(_ blocks: UnsafeRawBufferPointer, into state: inout State) {
        roundConstants.withUnsafeBufferPointer { constants in
            withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 64) { schedule in
                var start = 0
                while start < blocks.count {
                    compress(
                        UnsafeRawBufferPointer(rebasing: blocks[start..<(start &+ 64)]),
                        into: &state,
                        schedule: schedule,
                        constants: constants
                    )
                    start &+= 64
                }
            }
        }
    }

    private static func compress(
        _ block: UnsafeRawBufferPointer,
        into state: inout State,
        schedule: UnsafeMutableBufferPointer<UInt32>,
        constants: UnsafeBufferPointer<UInt32>
    ) {
        // Index loops rather than range iteration: an unoptimized build walks a range through
        // the generic iterator, which dominated the digest's cost.
        var index = 0
        while index < 16 {
            let offset = index &* 4
            schedule[index] = UInt32(block[offset]) << 24
                | UInt32(block[offset &+ 1]) << 16
                | UInt32(block[offset &+ 2]) << 8
                | UInt32(block[offset &+ 3])
            index &+= 1
        }
        while index < 64 {
            schedule[index] = smallSigma1(schedule[index &- 2])
                &+ schedule[index &- 7]
                &+ smallSigma0(schedule[index &- 15])
                &+ schedule[index &- 16]
            index &+= 1
        }

        var a = state.h0
        var b = state.h1
        var c = state.h2
        var d = state.h3
        var e = state.h4
        var f = state.h5
        var g = state.h6
        var h = state.h7
        index = 0
        while index < 64 {
            let temporary1 = h
                &+ bigSigma1(e)
                &+ ((e & f) ^ (~e & g))
                &+ constants[index]
                &+ schedule[index]
            let temporary2 = bigSigma0(a) &+ ((a & b) ^ (a & c) ^ (b & c))
            h = g
            g = f
            f = e
            e = d &+ temporary1
            d = c
            c = b
            b = a
            a = temporary1 &+ temporary2
            index &+= 1
        }
        state.h0 = state.h0 &+ a
        state.h1 = state.h1 &+ b
        state.h2 = state.h2 &+ c
        state.h3 = state.h3 &+ d
        state.h4 = state.h4 &+ e
        state.h5 = state.h5 &+ f
        state.h6 = state.h6 &+ g
        state.h7 = state.h7 &+ h
    }

    private static func rotateRight(_ value: UInt32, by shift: UInt32) -> UInt32 {
        (value >> shift) | (value << (32 - shift))
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
