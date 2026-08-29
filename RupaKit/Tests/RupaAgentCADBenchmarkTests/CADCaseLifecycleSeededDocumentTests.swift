import RupaAutomation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADCaseLifecycleSeededDocumentTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func seededSourceReachesProductionTransformOnceAndPreservesGeometry() async throws {
        let seed = try seededLineDocument()
        let requestedTransform = try translation(x: 0.025, y: -0.010, z: 0.005)
        let record = try await harness(
            initialDocumentProvider: { seed.document },
            planBuilder: { .command(.setSceneNodeTransform(
                id: seed.sceneNodeID,
                localTransform: requestedTransform
            )) }
        ).run(action: fixtureAction())

        #expect(record.outcome == .published)
        #expect(record.routeEvidence.didPublish)
        let expectedGeneration = try record.routeEvidence.initialDocumentGeneration.advanced()
        let expectedTransaction = try record.routeEvidence.initialTransactionRevision.advanced()
        #expect(record.routeEvidence.finalPublicationSequence
            == record.routeEvidence.initialPublicationSequence + 1)
        #expect(record.routeEvidence.finalDocumentGeneration
            == expectedGeneration)
        #expect(record.routeEvidence.finalTransactionRevision
            == expectedTransaction)
        #expect(record.routeEvidence.finalWorkspaceRevision
            == record.routeEvidence.initialWorkspaceRevision)
        #expect(record.telemetry.actionCount == 1)
        #expect(record.telemetry.commandCount == 1)
        #expect(record.routeEvidence.cleanupCompleted)
        #expect(record.routeEvidence.remainingRegistrationCount == 0)

        let initial = try #require(record.initialView?.document.document)
        let final = try #require(record.finalView?.document.document)
        #expect(initial.cadDocument.designGraph.nodes == final.cadDocument.designGraph.nodes)
        #expect(initial.cadDocument.designGraph.order == final.cadDocument.designGraph.order)
        #expect(initial.cadDocument.designGraph.revision == final.cadDocument.designGraph.revision)
        #expect(initial.productMetadata.sceneNodes[seed.sceneNodeID]?.reference
            == final.productMetadata.sceneNodes[seed.sceneNodeID]?.reference)
        #expect(initial.productMetadata.sceneNodes[seed.sceneNodeID]?.localTransform == .identity)
        #expect(final.productMetadata.sceneNodes[seed.sceneNodeID]?.localTransform
            == requestedTransform)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func providerFailureIsTypedBeforeRegistrationCommandOrPublication() async throws {
        let record = try await harness(
            initialDocumentProvider: { throw FixtureError.rejected },
            planBuilder: { .command(lineCommand()) }
        ).run(action: fixtureAction())

        #expect(record.outcome == .infrastructureFailure)
        #expect(record.initialView == nil)
        #expect(record.finalView == nil)
        #expect(record.response == nil)
        #expect(record.routeEvidence.didPublish == false)
        #expect(record.telemetry.actionCount == 0)
        #expect(record.telemetry.commandCount == 0)
        #expect(record.routeEvidence.cleanupCompleted)
        #expect(record.routeEvidence.remainingRegistrationCount == 0)
        #expect(record.diagnostics.contains { $0.contains("initial document provider failed") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func defaultProviderRetainsNamedEmptyDocumentBehavior() async throws {
        let record = try await harness(
            planBuilder: { .command(lineCommand()) }
        ).run(action: fixtureAction())

        #expect(record.outcome == .published)
        let initial = try #require(record.initialView?.document.document)
        let final = try #require(record.finalView?.document.document)
        #expect(initial.cadDocument.metadata.name == "TRN-001")
        #expect(initial.cadDocument.designGraph.nodes.isEmpty)
        #expect(final.cadDocument.designGraph.nodes.count == 1)
        #expect(record.routeEvidence.finalPublicationSequence
            == record.routeEvidence.initialPublicationSequence + 1)
        #expect(record.routeEvidence.cleanupCompleted)
        #expect(record.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func preCancelledDirectRunStopsBeforeProviderAndRouting() async throws {
        var providerInvocationCount = 0
        var routingInvocationCount = 0
        let subject = try harness(
            initialDocumentProvider: {
                providerInvocationCount += 1
                return .empty(named: "unexpected")
            },
            planBuilder: {
                routingInvocationCount += 1
                return .command(lineCommand())
            }
        )

        let record = try await preCancelledRecord {
            try await subject.run(action: fixtureAction())
        }

        assertPreflightCancellation(record)
        #expect(providerInvocationCount == 0)
        #expect(routingInvocationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func preCancelledStaleRunStopsBeforeProviderAndRouting() async throws {
        var providerInvocationCount = 0
        var routingInvocationCount = 0
        let subject = try harness(
            initialDocumentProvider: {
                providerInvocationCount += 1
                return .empty(named: "unexpected")
            },
            planBuilder: {
                routingInvocationCount += 1
                return .command(lineCommand())
            }
        )

        let record = try await preCancelledRecord {
            try await subject.runStale(action: fixtureAction())
        }

        assertPreflightCancellation(record)
        #expect(providerInvocationCount == 0)
        #expect(routingInvocationCount == 0)
    }

    @MainActor
    private func harness(
        initialDocumentProvider: CADCaseLifecycleHarness.InitialDocumentProvider? = nil,
        planBuilder: @escaping @MainActor () throws -> CADCaseActionPlan
    ) throws -> CADCaseLifecycleHarness {
        CADCaseLifecycleHarness(
            caseID: "TRN-001",
            challenge: try CADBenchmarkCatalog().challenge(for: "TRN-001"),
            routing: CADCaseActionRouting(
                operationName: "setSceneNodeTransform.fixture",
                planBuilder: { _, _, _ in try planBuilder() }
            ),
            timeoutWallNanoseconds: 10_000_000_000,
            initialDocumentProvider: initialDocumentProvider
        )
    }

    @MainActor
    private func preCancelledRecord(
        operation: @escaping @MainActor () async throws -> CADCaseLifecycleRecord
    ) async throws -> CADCaseLifecycleRecord {
        try await Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await operation()
        }.value
    }

    private func assertPreflightCancellation(_ record: CADCaseLifecycleRecord) {
        #expect(record.outcome == .cancellation)
        #expect(record.initialView == nil)
        #expect(record.finalView == nil)
        #expect(record.response == nil)
        #expect(record.routeEvidence.didPublish == false)
        #expect(record.telemetry.actionCount == 0)
        #expect(record.telemetry.commandCount == 0)
        #expect(record.routeEvidence.cleanupCompleted)
        #expect(record.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    private func seededLineDocument() throws -> (
        document: DesignDocument,
        sceneNodeID: SceneNodeID
    ) {
        var document = DesignDocument.empty(named: "TRN-001")
        let featureID = try document.createLineSketch(
            name: "TRN-001.source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0, .millimeter),
                y: .length(0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(100, .millimeter),
                y: .length(0, .millimeter)
            )
        )
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference == .sketch(featureID)
        }?.id)
        return (document, sceneNodeID)
    }

    private func fixtureAction() -> CADCandidateAction {
        .automation(.sketch(.line(
            name: "fixture",
            plane: .xy,
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 100, y: 0, z: 0)
        )))
    }

    private func lineCommand() -> AutomationCommand {
        .createLineSketch(
            name: "fixture",
            plane: nil,
            start: SketchPoint(
                x: .length(0, .millimeter),
                y: .length(0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10, .millimeter),
                y: .length(0, .millimeter)
            )
        )
    }

    private func translation(x: Double, y: Double, z: Double) throws -> Transform3D {
        Transform3D(matrix: try Matrix4x4(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            x, y, z, 1,
        ]))
    }
}

private enum FixtureError: Error {
    case rejected
}
