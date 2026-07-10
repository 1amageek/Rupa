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
