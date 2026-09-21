import Foundation
import SwiftCAD

enum CADSphereOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)
    case substitute(CADSphereRepresentationKind)

    var description: String {
        switch self {
        case let .mismatch(reason):
            "Sphere oracle mismatch: \(reason)"
        case let .substitute(representation):
            "Sphere oracle rejected \(representation.rawValue) as a sphere substitute."
        }
    }
}

/// Exact analytic-sphere observation returned by the source/B-rep oracle.
struct CADSphereOracleObservation: Equatable, Sendable {
    let readCount: Int
    let featureCount: Int
    let bodyCount: Int
    let faceCount: Int
    let edgeCount: Int
    let vertexCount: Int
    let analyticSurfaceCount: Int
    let volumeCubicMeters: Double
}

/// Validates only immutable source/B-rep observations. It never constructs a
/// sphere, calls an Agent command, evaluates a candidate action, or reads Mesh
/// bounds as authority.
enum CADSphereOracle {
    private static let expectedFaceCount = 8
    private static let expectedEdgeCount = 12
    private static let expectedVertexCount = 6

    static func evaluate(
        expected: CADSphereChallengeInput,
        challenge: CADChallenge,
        observed: CADSphereObservedGeometry,
        modelingTolerance: ModelingTolerance = .standard
    ) throws -> CADSphereOracleObservation {
        let caseID = challenge.id
        guard CADSpherePreparationCase(rawValue: caseID.rawValue) != nil,
              challenge.category == .sphere else {
            throw CADSphereOracleError.mismatch(
                "The oracle received an inactive or non-sphere challenge."
            )
        }
        try CADChallengeGeometryValidator.validate(.sphere(expected), caseID: caseID)
        guard challenge.requiredCapability.id == CADBenchmarkCategory.sphere.capabilityID,
              challenge.requiredCapability.version == "1",
              challenge.outputRoles.map(\.name) == ["sphere"] else {
            throw CADSphereOracleError.mismatch(
                "The sphere challenge does not preserve its required capability or role."
            )
        }

        let entry = try CADSpherePreparationCase(caseID: caseID).catalogEntry
        guard case let .sphere(catalogInput) = entry.input,
              catalogInput == expected else {
            throw CADSphereOracleError.mismatch(
                "The candidate-visible sphere challenge and private expectation disagree."
            )
        }

        try modelingTolerance.validate()
        guard observed.representation == .analyticSphere else {
            throw CADSphereOracleError.substitute(observed.representation)
        }
        guard observed.center.isFinite,
              observed.radiusMeters.isFinite,
              observed.radiusMeters > modelingTolerance.distance,
              observed.bodyCount == 1,
              observed.featureCount == 1,
              observed.faceCount == expectedFaceCount,
              observed.edgeCount == expectedEdgeCount,
              observed.vertexCount == expectedVertexCount,
              observed.analyticSurfaceCount == expectedFaceCount,
              observed.isClosed,
              observed.sourceIsAuthoritative else {
            throw CADSphereOracleError.mismatch(
                "The observed source is not one closed analytic sphere with exact topology."
            )
        }

        let expectedCenter = expected.center.meters
        guard accepts(
            expected: expectedCenter.x,
            observed: observed.center.meters.x,
            tolerance: modelingTolerance
        ),
        accepts(
            expected: expectedCenter.y,
            observed: observed.center.meters.y,
            tolerance: modelingTolerance
        ),
        accepts(
            expected: expectedCenter.z,
            observed: observed.center.meters.z,
            tolerance: modelingTolerance
        ),
        accepts(
            expected: expected.radius.meters,
            observed: observed.radiusMeters,
            tolerance: modelingTolerance
        ) else {
            throw CADSphereOracleError.mismatch(
                "The analytic sphere center or radius is outside the document tolerance."
            )
        }

        let expectedVolume = 4.0 * Double.pi * pow(expected.radius.meters, 3.0) / 3.0
        guard accepts(
            expected: expectedVolume,
            observed: observed.volumeCubicMeters,
            tolerance: modelingTolerance
        ) else {
            throw CADSphereOracleError.mismatch(
                "The analytic sphere volume does not match its radius."
            )
        }

        return CADSphereOracleObservation(
            readCount: 1,
            featureCount: observed.featureCount,
            bodyCount: observed.bodyCount,
            faceCount: observed.faceCount,
            edgeCount: observed.edgeCount,
            vertexCount: observed.vertexCount,
            analyticSurfaceCount: observed.analyticSurfaceCount,
            volumeCubicMeters: observed.volumeCubicMeters
        )
    }

    private static func accepts(
        expected: Double,
        observed: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard expected.isFinite, observed.isFinite else { return false }
        let limit = max(
            tolerance.distance,
            tolerance.relative * max(1.0, abs(expected), abs(observed))
        )
        return abs(expected - observed) <= limit
    }
}
