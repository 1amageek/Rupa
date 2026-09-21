import Foundation
import RupaCoreTypes

struct CADCatalogEntry: Sendable {
    let challenge: CADChallenge
    let input: CADChallengeInput
    let expected: CADExpectedGeometry
    let expectationDigest: String
    let requiresAnalyticSurface: Bool
    let capabilityClassification: CADCapabilityClassification

    init(
        challenge: CADChallenge,
        input: CADChallengeInput,
        expected: CADExpectedGeometry,
        requiresAnalyticSurface: Bool
    ) throws {
        self.challenge = challenge
        self.input = input
        self.expected = expected
        self.requiresAnalyticSurface = requiresAnalyticSurface
        self.capabilityClassification = requiresAnalyticSurface ? .analyticSphere : .standardGeometry
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(expected)
        self.expectationDigest = StableDigest.sha256Hex(for: data)
    }
}
