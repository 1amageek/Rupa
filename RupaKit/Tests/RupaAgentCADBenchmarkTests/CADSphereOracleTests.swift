import Foundation
import Testing
import SwiftCAD
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADSphereOracleTests {
    @Test(.timeLimit(.minutes(1)), arguments: [
        CADSphereRepresentationKind.box,
        CADSphereRepresentationKind.cylinder,
        CADSphereRepresentationKind.circle,
        CADSphereRepresentationKind.polyhedron,
        CADSphereRepresentationKind.extrudedDisc,
        CADSphereRepresentationKind.mesh,
    ])
    func rejectsEveryNonAnalyticSphereSubstitute(
        representation: CADSphereRepresentationKind
    ) throws {
        let entry = try CADSpherePreparationCase.sph001.catalogEntry
        guard case let .sphere(expected) = entry.input else {
            Issue.record("SPH-001 must retain a sphere expectation.")
            return
        }
        let observed = CADSphereObservedGeometry(
            representation: representation,
            center: expected.center,
            radiusMeters: expected.radius.meters,
            bodyCount: 1,
            faceCount: 8,
            edgeCount: 12,
            vertexCount: 6,
            analyticSurfaceCount: 8,
            featureCount: 1,
            volumeCubicMeters: 4.0 * Double.pi * pow(expected.radius.meters, 3.0) / 3.0,
            isClosed: true,
            sourceIsAuthoritative: true
        )

        do {
            _ = try CADSphereOracle.evaluate(
                expected: expected,
                challenge: entry.challenge,
                observed: observed
            )
            Issue.record("The sphere oracle must reject \(representation.rawValue) as a substitute.")
        } catch let error as CADSphereOracleError {
            guard case let .substitute(rejected) = error else {
                Issue.record("Unexpected sphere oracle error: \(error)")
                return
            }
            #expect(rejected == representation)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsOnlyExactAnalyticSphereTopologyAndPlacementObservation() throws {
        let entry = try CADSpherePreparationCase.sph001.catalogEntry
        guard case let .sphere(expected) = entry.input else {
            Issue.record("SPH-001 must retain a sphere expectation.")
            return
        }
        let observed = CADSphereObservedGeometry(
            representation: .analyticSphere,
            center: expected.center,
            radiusMeters: expected.radius.meters,
            bodyCount: 1,
            faceCount: 8,
            edgeCount: 12,
            vertexCount: 6,
            analyticSurfaceCount: 8,
            featureCount: 1,
            volumeCubicMeters: 4.0 * Double.pi * pow(expected.radius.meters, 3.0) / 3.0,
            isClosed: true,
            sourceIsAuthoritative: true
        )

        let observation = try CADSphereOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            observed: observed
        )
        #expect(observation.readCount == 1)
        #expect(observation.featureCount == 1)
        #expect(observation.bodyCount == 1)
        #expect(observation.faceCount == 8)
        #expect(observation.edgeCount == 12)
        #expect(observation.vertexCount == 6)
        #expect(observation.analyticSurfaceCount == 8)
    }

    @Test
    func wrongAnalyticTopologyCannotPassByBoundsAlone() throws {
        let entry = try CADSpherePreparationCase.sph001.catalogEntry
        guard case let .sphere(expected) = entry.input else {
            Issue.record("SPH-001 must retain a sphere expectation.")
            return
        }
        let observed = CADSphereObservedGeometry(
            representation: .analyticSphere,
            center: expected.center,
            radiusMeters: expected.radius.meters,
            bodyCount: 1,
            faceCount: 1,
            edgeCount: 0,
            vertexCount: 0,
            analyticSurfaceCount: 1,
            featureCount: 1,
            volumeCubicMeters: 4.0 * Double.pi * pow(expected.radius.meters, 3.0) / 3.0,
            isClosed: true,
            sourceIsAuthoritative: true
        )

        do {
            _ = try CADSphereOracle.evaluate(
                expected: expected,
                challenge: entry.challenge,
                observed: observed
            )
            Issue.record("Sphere bounds alone must not satisfy the exact topology contract.")
        } catch let error as CADSphereOracleError {
            guard case .mismatch = error else {
                Issue.record("Unexpected sphere oracle error: \(error)")
                return
            }
        }
    }
}
