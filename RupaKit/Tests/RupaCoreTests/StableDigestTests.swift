import Foundation
import RupaCoreTypes
import Testing

@Test(.timeLimit(.minutes(1)))
func stableDigestMatchesSHA256ReferenceVectors() {
    #expect(
        StableDigest.sha256Hex(for: Data())
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    )
    #expect(
        StableDigest.sha256Hex(for: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
    #expect(
        StableDigest.sha256Hex(
            for: Data("The quick brown fox jumps over the lazy dog".utf8)
        ) == "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
    )
}

@Test(.timeLimit(.minutes(1)))
func stableSHA256HasherMatchesOneShotDigestAcrossBlockBoundaries() {
    let payload = Data((0..<257).map { UInt8($0 % 251) })
    var hasher = StableSHA256Hasher()
    hasher.update(payload.prefix(1))
    hasher.update(payload[1..<64])
    hasher.update(payload[64..<129])
    hasher.update(payload[129...])

    #expect(hasher.hexDigest() == StableDigest.sha256Hex(for: payload))
    #expect(hasher.hexDigest() == StableDigest.sha256Hex(for: payload))
}

#if canImport(CryptoKit)
import CryptoKit

/// Every length across the one- and two-block padding boundaries agrees with the platform
/// digest, whether the bytes arrive at once, in random chunks, or one byte at a time.
@Test(.timeLimit(.minutes(1)))
func stableSHA256HasherMatchesThePlatformDigestAcrossPaddingAndChunking() {
    var generator = SystemRandomNumberGenerator()
    for length in Array(0...200) + [4_095, 4_096, 65_537] {
        let data = Data((0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let expected = CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(StableDigest.sha256Hex(for: data) == expected, "length \(length)")

        var chunked = StableSHA256Hasher()
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + Int.random(in: 1...150, using: &generator))
            chunked.update(data[offset..<end])
            offset = end
        }
        #expect(chunked.hexDigest() == expected, "chunked length \(length)")

        if length <= 200 {
            var bytewise = StableSHA256Hasher()
            for byte in data { bytewise.update(byte: byte) }
            #expect(bytewise.hexDigest() == expected, "bytewise length \(length)")
        }
    }
}

/// A string hashes as its UTF-8 byte count followed by its UTF-8 bytes.
@Test(.timeLimit(.minutes(1)))
func stableSHA256HasherHashesAStringAsItsCountAndUTF8Bytes() {
    let string = "Rupa — 形状 \u{1F4D0}"
    var hasher = StableSHA256Hasher()
    hasher.update(string: string)
    var reference = Data()
    withUnsafeBytes(of: UInt64(string.utf8.count).bigEndian) { reference.append(contentsOf: $0) }
    reference.append(contentsOf: string.utf8)
    let expected = CryptoKit.SHA256.hash(data: reference).map { String(format: "%02x", $0) }.joined()
    #expect(hasher.hexDigest() == expected)
}
#endif
