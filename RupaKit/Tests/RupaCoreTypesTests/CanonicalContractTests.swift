import Foundation
import RupaCoreTypes
import Testing

@Test(.timeLimit(.minutes(1)))
func canonicalValuesProduceStableBytesAndNormalizeNegativeZero() throws {
    let first: CanonicalValue = .object([
        "z": .number(-0.0),
        "a": .array([.bool(true), .null]),
    ])
    let second: CanonicalValue = .object([
        "a": .array([.bool(true), .null]),
        "z": .number(0.0),
    ])

    let firstData = try first.canonicalJSONData()
    let secondData = try second.canonicalJSONData()

    #expect(firstData == secondData)
    #expect(String(decoding: firstData, as: UTF8.self) == "{\"a\":[true,null],\"z\":0}")
    #expect(try JSONDecoder().decode(CanonicalValue.self, from: firstData) == second)
}

@Test(.timeLimit(.minutes(1)))
func canonicalValuesRejectInvalidNumbersKeysAndDepth() {
    #expect(throws: EditorError.self) {
        try CanonicalValue.number(.infinity).validate()
    }
    #expect(throws: EditorError.self) {
        try CanonicalValue.object([" padded": .null]).validate()
    }
    #expect(throws: (any Error).self) {
        _ = try JSONEncoder().encode(CanonicalValue.object([" padded": .null]))
    }
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(
            CanonicalValue.self,
            from: Data("{\" padded\":null}".utf8)
        )
    }

    var nested = CanonicalValue.null
    for _ in 0..<130 {
        nested = .array([nested])
    }
    #expect(throws: EditorError.self) {
        try nested.validate()
    }
}

@Test(.timeLimit(.minutes(1)))
func stableSHA256MatchesPublishedVectors() {
    #expect(
        StableDigest.sha256Hex(for: Data())
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    )
    #expect(
        StableDigest.sha256Hex(for: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
}

@Test(.timeLimit(.minutes(1)))
func stableSHA256HashesBorrowedSpansWithoutMaterialization() {
    let bytes = ContiguousArray("abc".utf8)
    var hasher = StableSHA256Hasher()

    bytes.withUnsafeBufferPointer { pointer in
        let span = Span(_unsafeElements: pointer)
        hasher.update(span)
    }

    #expect(
        hasher.hexDigest()
            == "ba7816bf8f01cfea414140de5dae2223"
                + "b00361a396177a9cb410ff61f20015ad"
    )
}

@Test(.timeLimit(.minutes(1)))
func contentFingerprintsRejectNonCanonicalRepresentations() throws {
    let fingerprint = try ContentFingerprint.sha256(
        algorithm: "sha256-test-v1",
        data: Data("content".utf8)
    )
    #expect(fingerprint.value.count == 64)

    #expect(throws: EditorError.self) {
        _ = try ContentFingerprint(algorithm: " sha256-test-v1", value: fingerprint.value)
    }
    #expect(throws: EditorError.self) {
        _ = try ContentFingerprint(
            algorithm: "sha256-test-v1",
            value: fingerprint.value.uppercased()
        )
    }
    #expect(throws: EditorError.self) {
        _ = try ContentFingerprint(
            algorithm: "custom-v1",
            value: String(repeating: "a", count: 1_025)
        )
    }
}
