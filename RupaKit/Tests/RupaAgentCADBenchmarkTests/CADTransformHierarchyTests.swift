import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaGeometry
import RupaKit
import SwiftCAD
import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADTransformHierarchyTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func productionTransformUsesParentTimesLocalAndPublishesOnce() async throws {
        let preparedCase = CADTransformPreparedCase.transform004
        let entry = try preparedCase.catalogEntry
        let projection = try CADTransformChallengeProjection.decode(entry.challenge)
        let seed = try CADTransformGeometryMapping.seed(projection: projection)
        let submission = try CADTransformReferenceCandidate().submission(
            for: entry.challenge
        )
        let localTransform = try CADTransformGeometryMapping.localTransform(
            submission: submission,
            caseID: preparedCase.caseID
        )
        let parentValues = [
            0.0, -1.0, 0.0, 0.12,
            1.0, 0.0, 0.0, -0.03,
            0.0, 0.0, 1.0, 0.04,
            0.0, 0.0, 0.0, 1.0,
        ]
        let parentTransform = Transform3D(
            matrix: try Matrix4x4(values: parentValues)
        )
        var document = seed.document
        let parentID = try document.productMetadata.appendSceneNodeToFirstRoot(
            name: "TRN-004 test parent",
            reference: nil,
            object: .group()
        )
        document.productMetadata.sceneNodes[parentID]?.localTransform = parentTransform
        try document.productMetadata.nestSceneNode(seed.sceneNodeID, under: parentID)
        try document.validate()

        let harness = CADCaseLifecycleHarness(
            caseID: preparedCase.caseID,
            challenge: entry.challenge,
            routing: CADCaseActionRouting(
                operationName: "setSceneNodeTransform",
                planBuilder: { action, _, _ in
                    guard action == seed.sourceAction else {
                        throw CADTransformHierarchyTestError.unexpectedAction
                    }
                    return .command(.setSceneNodeTransform(
                        id: seed.sceneNodeID,
                        localTransform: localTransform
                    ))
                }
            ),
            timeoutWallNanoseconds: 10_000_000_000,
            initialDocumentProvider: { document }
        )
        let record = try await harness.run(action: seed.sourceAction)

        #expect(record.outcome == .published)
        #expect(record.routeEvidence.didPublish)
        #expect(record.routeEvidence.finalPublicationSequence
            == record.routeEvidence.initialPublicationSequence + 1)
        #expect(record.telemetry.actionCount == 1)
        #expect(record.telemetry.commandCount == 1)
        #expect(record.routeEvidence.cleanupCompleted)
        #expect(record.routeEvidence.remainingRegistrationCount == 0)

        let initial = try #require(record.initialView)
        let final = try #require(record.finalView)
        let expectedWorld = try CADTransformOracle.parentTimesLocal(
            parent: try GeometryTransform3D(values: parentTransform.matrix.values),
            local: localTransform
        )
        let occurrenceID = SceneOccurrenceID(rawValue: "scene.\(seed.sceneNodeID.description)")
        let occurrence = try #require(final.viewport.items.first { $0.id == occurrenceID })
        #expect(occurrence.worldTransform == expectedWorld)
        #expect(final.document.document.productMetadata.sceneNodes[parentID]?.localTransform
            == parentTransform)
        #expect(initial.document.document.cadDocument.designGraph.nodes
            == final.document.document.cadDocument.designGraph.nodes)
        #expect(initial.document.document.cadDocument.designGraph.order
            == final.document.document.cadDocument.designGraph.order)
        #expect(initial.document.document.cadDocument.designGraph.revision
            == final.document.document.cadDocument.designGraph.revision)

        guard case .transform(let expected) = entry.expected else {
            throw CADTransformHierarchyTestError.unexpectedExpectation
        }
        let observation = try CADTransformOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            sceneNodeID: seed.sceneNodeID,
            expectedTransform: localTransform,
            initial: initial,
            final: final
        )
        #expect(observation.readCount == 3)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func exactOracleRejectsWrongInitialSourceAfterTheSameFinalTransform() async throws {
        let preparedCase = CADTransformPreparedCase.transform001
        let entry = try preparedCase.catalogEntry
        let projection = try CADTransformChallengeProjection.decode(entry.challenge)
        guard case .line(let source) = projection.source else {
            throw CADTransformHierarchyTestError.unexpectedSource
        }
        let wrongEnd = CADPoint3D(
            x: source.end.x + 5,
            y: source.end.y,
            z: source.end.z,
            unit: source.end.unit
        )
        let wrongProjection = CADTransformChallengeProjection(
            id: projection.id,
            source: .line(CADLineChallengeProjection(
                id: source.id,
                orientation: source.orientation,
                length: source.length,
                start: source.start,
                end: wrongEnd,
                anchor: source.anchor
            )),
            translation: projection.translation,
            axisPoint: projection.axisPoint,
            rotationAxis: projection.rotationAxis,
            rotation: projection.rotation
        )
        let wrongSeed = try CADTransformGeometryMapping.seed(projection: wrongProjection)
        let submission = try CADTransformReferenceCandidate().submission(
            for: entry.challenge
        )
        let targetTransform = try CADTransformGeometryMapping.localTransform(
            submission: submission,
            caseID: preparedCase.caseID
        )
        let harness = CADCaseLifecycleHarness(
            caseID: preparedCase.caseID,
            challenge: entry.challenge,
            routing: CADCaseActionRouting(
                operationName: "setSceneNodeTransform",
                planBuilder: { action, _, _ in
                    guard action == wrongSeed.sourceAction else {
                        throw CADTransformHierarchyTestError.unexpectedAction
                    }
                    return .command(.setSceneNodeTransform(
                        id: wrongSeed.sceneNodeID,
                        localTransform: targetTransform
                    ))
                }
            ),
            timeoutWallNanoseconds: 10_000_000_000,
            initialDocumentProvider: { wrongSeed.document }
        )

        let record = try await harness.run(action: wrongSeed.sourceAction)

        #expect(record.outcome == .published)
        #expect(record.routeEvidence.finalPublicationSequence
            == record.routeEvidence.initialPublicationSequence + 1)
        #expect(record.telemetry.commandCount == 1)
        let initial = try #require(record.initialView)
        let final = try #require(record.finalView)
        #expect(final.document.document.productMetadata
            .sceneNodes[wrongSeed.sceneNodeID]?.localTransform == targetTransform)
        guard case .transform(let expected) = entry.expected else {
            throw CADTransformHierarchyTestError.unexpectedExpectation
        }
        #expect(throws: CADTransformOracleError.self) {
            try CADTransformOracle.evaluate(
                expected: expected,
                challenge: entry.challenge,
                sceneNodeID: wrongSeed.sceneNodeID,
                expectedTransform: targetTransform,
                initial: initial,
                final: final
            )
        }
    }
}

private enum CADTransformHierarchyTestError: Error {
    case unexpectedAction
    case unexpectedExpectation
    case unexpectedSource
}
