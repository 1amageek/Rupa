import Foundation
import RupaCoreTypes
import Testing

@Test(.timeLimit(.minutes(1)))
func contentIdentitiesPreserveDomainAndFingerprint() throws {
    let fingerprint = try ContentFingerprint.sha256(
        algorithm: "sha256-document-v1",
        data: Data("document".utf8)
    )
    let content = try ContentIdentity(
        domain: "rupa.geometry-source.v1",
        fingerprint: fingerprint
    )
    let document = try DocumentContentIdentity(fingerprint: fingerprint)

    #expect(content.domain == "rupa.geometry-source.v1")
    #expect(document.content.domain == "rupa.document-source.v1")
    #expect(document.content.fingerprint == fingerprint)

    let data = try JSONEncoder().encode(document)
    #expect(try JSONDecoder().decode(DocumentContentIdentity.self, from: data) == document)
}

@Test(.timeLimit(.minutes(1)))
func stableErrorEnvelopeRoundTripsCanonicalDetails() throws {
    let envelope = try StableErrorEnvelope(
        code: "project.revisionConflict",
        message: "The project revision is stale.",
        details: .object([
            "expected": .number(4),
            "actual": .number(5),
        ])
    )
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(StableErrorEnvelope.self, from: data)

    let stableEncoder = JSONEncoder()
    stableEncoder.outputFormatting = [.sortedKeys]
    let stableData = try stableEncoder.encode(envelope)

    #expect(decoded == envelope)
    #expect(decoded.errorDescription == envelope.message)
    #expect(
        String(decoding: stableData, as: UTF8.self)
            == "{\"code\":\"project.revisionConflict\","
            + "\"details\":{\"actual\":5,\"expected\":4},"
            + "\"message\":\"The project revision is stale.\"}"
    )
}

@Test(.timeLimit(.minutes(1)))
func stableErrorEnvelopeRejectsInvalidCodesMessagesAndDetails() {
    #expect(throws: EditorError.self) {
        _ = try StableErrorEnvelope(code: "invalid", message: "Failure")
    }
    #expect(throws: EditorError.self) {
        _ = try StableErrorEnvelope(code: "core.invalid", message: "   ")
    }
    #expect(throws: EditorError.self) {
        _ = try StableErrorEnvelope(
            code: "core.invalid",
            message: "Failure",
            details: .number(.nan)
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func canonicalQuantitiesUseFiniteSIBaseMagnitudes() throws {
    let length = try CanonicalQuantity(magnitude: -0.0, dimension: .length)
    let area = try CanonicalQuantity(magnitude: 4.0, dimension: .area)
    let angle = try CanonicalQuantity(magnitude: .pi, dimension: .angle)

    #expect(length.magnitude == 0)
    #expect(area.dimension.length == 2)
    #expect(angle.dimension.angle == 1)
    #expect(throws: EditorError.self) {
        _ = try CanonicalQuantity(magnitude: .infinity, dimension: .time)
    }
}

@Test(.timeLimit(.minutes(1)))
func revisionsAdvanceMonotonicallyAndRejectOverflow() throws {
    #expect(try DocumentTransactionRevision(8).advanced() == DocumentTransactionRevision(9))
    #expect(try DocumentGeneration(8).advanced() == DocumentGeneration(9))
    #expect(throws: EditorError.self) {
        _ = try DocumentTransactionRevision(UInt64.max).advanced()
    }
    #expect(throws: EditorError.self) {
        _ = try DocumentGeneration(UInt64.max).advanced()
    }
}
