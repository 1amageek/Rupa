import Foundation
import RupaCADDomain
import RupaCore
import RupaKit
import SwiftCAD

/// Projects the shared production lifecycle into one analytic-sphere result.
@MainActor
struct CADSphereCaseRunner {
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let activatedCase: CADActivatedSphereCase
    private let recorder = CADSphereRecorder()
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64

    init(
        case activatedCase: CADActivatedSphereCase,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0
    ) {
        self.activatedCase = activatedCase
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
    }

    init(
        caseID: CADBenchmarkCaseID,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0
    ) throws {
        self.init(
            case: try CADActivatedSphereCase(caseID: caseID),
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds
        )
    }

    private var caseID: CADBenchmarkCaseID { activatedCase.caseID }

    func runReference() async throws -> CADSphereCaseResult {
        try await run(candidate: CADSphereReferenceCandidate())
    }

    func run(candidate: any CADCandidateProtocol) async throws -> CADSphereCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(entry: entry).runReference(candidate: candidate)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    func run(action: CADCandidateAction) async throws -> CADSphereCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(entry: entry).run(action: action)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    private func harness(entry: CADCatalogEntry) -> CADCaseLifecycleHarness {
        CADCaseLifecycleHarness(
            caseID: caseID,
            challenge: entry.challenge,
            programPlanner: { action in
                try DefaultCADSemanticProgramPlanner().plan(for: entry, action: action)
            },
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds
        )
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        totalStart: UInt64
    ) async -> CADSphereCaseResult {
        let evidence = CADSphereRouteEvidence(from: record.routeEvidence)
        let pending: CADSphereCaseResult
        switch record.outcome {
        case .published:
            pending = await projectPublished(record, entry: entry, evidence: evidence)
        case .cancelledAfterPublication:
            pending = publishedMutation(record, evidence: evidence, outcome: .cancellation)
        case .invalidSubmission:
            pending = result(.invalidSubmission, record, evidence)
        case .executionFailure:
            pending = result(.executionFailure, record, evidence)
        case .timeout:
            pending = result(.timeout, record, evidence)
        case .cancellation:
            pending = result(.cancellation, record, evidence)
        case .infrastructureFailure:
            pending = result(.infrastructureFailure, record, evidence)
        }
        return pending.replacingTotalWallNanoseconds(elapsed(since: totalStart))
    }

    private func projectPublished(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        evidence: CADSphereRouteEvidence
    ) async -> CADSphereCaseResult {
        guard let finalView = record.finalView,
              let receipt = CADSemanticExecutionEvidence.committedReceipt(from: record.response) else {
            return result(.infrastructureFailure, record, evidence)
        }
        let semanticEvidence = CADSemanticExecutionEvidence(receipt: receipt)
        let stepResult = semanticEvidence.stepResult(
            node: "sphere",
            operation: RupaCADSemanticOperationID.solidSphere.rawValue,
            index: 0,
            primaryOutputs: ["body"]
        )
        let bindings = CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "sphere", stepIndex: 0, selector: .primary),
        ])
        guard case let .sphere(expected, requiresAnalyticSurface) = entry.expected,
              requiresAnalyticSurface,
              let featureID = stepResult.primaryFeatureID else {
            return result(
                .infrastructureFailure,
                record,
                evidence,
                candidateResult: stepResult,
                roleBindings: bindings,
                diagnostics: ["\(caseID.rawValue) sphere receipt or expectation is incomplete."]
            )
        }

        let oracleStart = now()
        let observed: CADSphereObservedGeometry
        do {
            observed = try await record.deadline.run {
                try Self.observeSphere(featureID: featureID, in: finalView)
            }
        } catch is CADCaseDeadlineError {
            return result(
                .timeout,
                record,
                evidence,
                candidateResult: stepResult,
                roleBindings: bindings,
                telemetry: telemetry(from: record).replacing(
                    oracleWallNanoseconds: elapsed(since: oracleStart)
                ),
                diagnostics: [
                    "\(caseID.rawValue) sphere source/B-rep observation exceeded its shared deadline after publication; no retry was attempted."
                ]
            )
        } catch {
            return result(
                .oracleFailure,
                record,
                evidence,
                candidateResult: stepResult,
                roleBindings: bindings,
                telemetry: telemetry(from: record).replacing(
                    oracleWallNanoseconds: elapsed(since: oracleStart)
                ),
                diagnostics: ["\(caseID.rawValue) sphere observation failed: \(message(error))"]
            )
        }

        let observedTelemetry = telemetry(from: record).replacing(
            oracleWallNanoseconds: elapsed(since: oracleStart),
            readCount: 2,
            featureCount: observed.featureCount,
            bodyCount: observed.bodyCount,
            faceCount: observed.faceCount,
            edgeCount: observed.edgeCount,
            vertexCount: observed.vertexCount,
            analyticSurfaceCount: observed.analyticSurfaceCount
        )
        do {
            _ = try CADSphereOracle.evaluate(
                expected: expected,
                challenge: entry.challenge,
                observed: observed,
                modelingTolerance: finalView.document.document.modelingSettings.tolerance
            )
            return result(
                .realized,
                record,
                evidence,
                candidateResult: stepResult,
                roleBindings: bindings,
                telemetry: observedTelemetry
            )
        } catch let error as CADSphereOracleError {
            return result(
                .invalidSubmission,
                record,
                evidence,
                candidateResult: stepResult,
                roleBindings: bindings,
                telemetry: observedTelemetry,
                diagnostics: [error.description]
            )
        } catch {
            return result(
                .oracleFailure,
                record,
                evidence,
                candidateResult: stepResult,
                roleBindings: bindings,
                telemetry: observedTelemetry,
                diagnostics: ["\(caseID.rawValue) sphere oracle failed: \(message(error))"]
            )
        }
    }

    private func publishedMutation(
        _ record: CADCaseLifecycleRecord,
        evidence: CADSphereRouteEvidence,
        outcome: CADCaseOutcome
    ) -> CADSphereCaseResult {
        guard let receipt = CADSemanticExecutionEvidence.committedReceipt(from: record.response) else {
            return result(.infrastructureFailure, record, evidence)
        }
        let stepResult = CADSemanticExecutionEvidence(receipt: receipt).stepResult(
            node: "sphere",
            operation: RupaCADSemanticOperationID.solidSphere.rawValue,
            index: 0,
            primaryOutputs: ["body"]
        )
        return result(
            outcome,
            record,
            evidence,
            candidateResult: stepResult,
            roleBindings: CADOutputRoleBindings(bindings: [
                CADOutputRoleBinding(role: "sphere", stepIndex: 0, selector: .primary),
            ])
        )
    }

    private func result(
        _ outcome: CADCaseOutcome,
        _ record: CADCaseLifecycleRecord,
        _ evidence: CADSphereRouteEvidence,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        telemetry: CADSphereTelemetry? = nil,
        diagnostics: [String]? = nil
    ) -> CADSphereCaseResult {
        CADSphereCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateResult: candidateResult,
            roleBindings: roleBindings,
            routeEvidence: evidence,
            telemetry: telemetry ?? self.telemetry(from: record),
            diagnostics: diagnostics ?? record.diagnostics
        )
    }

    private func telemetry(from record: CADCaseLifecycleRecord) -> CADSphereTelemetry {
        CADSphereTelemetry(
            planningWallNanoseconds: record.telemetry.planningWallNanoseconds,
            routeWallNanoseconds: record.telemetry.routeWallNanoseconds,
            oracleWallNanoseconds: 0,
            totalWallNanoseconds: record.telemetry.totalWallNanoseconds,
            actionCount: record.telemetry.actionCount,
            commandCount: record.telemetry.commandCount,
            readCount: 0,
            featureCount: 0,
            bodyCount: 0,
            faceCount: 0,
            edgeCount: 0,
            vertexCount: 0,
            analyticSurfaceCount: 0,
            timeoutWallNanoseconds: record.telemetry.timeoutWallNanoseconds,
            cancellationCheckpointCount: record.telemetry.cancellationCheckpointCount
        )
    }

    nonisolated private static func observeSphere(
        featureID description: String,
        in snapshot: ProjectViewSnapshot
    ) throws -> CADSphereObservedGeometry {
        guard let uuid = UUID(uuidString: description) else {
            throw CADSphereOracleError.mismatch("The semantic body binding is not a FeatureID.")
        }
        let featureID = FeatureID(uuid)
        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        guard graph.order == [featureID],
              graph.nodes.count == 1,
              let node = graph.nodes[featureID],
              node.isSuppressed == false,
              node.outputs.contains(where: { $0.role == .body }),
              case .primitive(let primitive) = node.operation else {
            throw CADSphereOracleError.mismatch(
                "The bound sphere must be the sole unsuppressed primitive source feature."
            )
        }

        let representation: CADSphereRepresentationKind
        let center: CADPoint3D
        let radiusMeters: Double
        switch primitive.definition {
        case .sphere(let sphere):
            let radius = try document.cadDocument.parameters.resolvedValue(for: sphere.radius)
            guard radius.kind == .length else {
                throw CADSphereOracleError.mismatch("The sphere radius is not a length.")
            }
            representation = .analyticSphere
            center = CADPoint3D(
                x: sphere.placement.origin.x,
                y: sphere.placement.origin.y,
                z: sphere.placement.origin.z,
                unit: .meter
            )
            radiusMeters = radius.value
        case .box:
            representation = .box
            center = CADPoint3D(x: 0, y: 0, z: 0, unit: .meter)
            radiusMeters = 0
        case .cylinder:
            representation = .cylinder
            center = CADPoint3D(x: 0, y: 0, z: 0, unit: .meter)
            radiusMeters = 0
        case .cone, .torus:
            representation = .unknown
            center = CADPoint3D(x: 0, y: 0, z: 0, unit: .meter)
            radiusMeters = 0
        }

        let topology = try TopologySnapshotService().snapshot(
            document: document,
            objectRegistry: snapshot.objectRegistry,
            currentEvaluation: snapshot.cadInteraction,
            currentGeneration: snapshot.documentGeneration,
            metricPolicy: .omit
        )
        let measurement = try MeasurementService().measure(
            document: document,
            ruler: snapshot.workspaceState.ruler,
            objectRegistry: snapshot.objectRegistry,
            currentEvaluation: snapshot.cadInteraction,
            currentGeneration: snapshot.documentGeneration
        )
        guard let solid = measurement.solids.first(where: {
            $0.featureID == description && $0.sourceFeatureID == description
        }),
        solid.volumeMethod == .exactBRep,
        measurement.solids.count == 1 else {
            throw CADSphereOracleError.mismatch(
                "The sphere has no single exact evaluated solid measurement."
            )
        }

        let primaryBody = SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        guard let evaluation = snapshot.cadInteraction?.evaluatedDocument,
              case .body(let bodyID) = try evaluation.subshapes.reference(for: primaryBody),
              evaluation.brep.bodies[bodyID]?.kind == .solid else {
            throw CADSphereOracleError.mismatch("The evaluated sphere body is not a closed solid.")
        }
        let sourceIsAuthoritative = document.productMetadata.sceneNodes.values.contains {
            $0.reference == .body(featureID)
                && $0.object?.category == .body
                && $0.object?.geometryRole == .solid
                && $0.object?.typeID == .sphere
        }
        let analyticSurfaceCount = topology.entries.filter {
            $0.kind == .face
                && $0.sourceFeatureID == description
                && $0.surfaceKind == "analytic"
        }.count
        return CADSphereObservedGeometry(
            representation: representation,
            center: center,
            radiusMeters: radiusMeters,
            bodyCount: topology.counts.bodyCount,
            faceCount: topology.counts.faceCount,
            edgeCount: topology.counts.edgeCount,
            vertexCount: topology.counts.vertexCount,
            analyticSurfaceCount: analyticSurfaceCount,
            featureCount: graph.nodes.count,
            volumeCubicMeters: solid.volumeCubicMeters,
            isClosed: true,
            sourceIsAuthoritative: sourceIsAuthoritative
        )
    }

    private func now() -> UInt64 {
        UInt64((ProcessInfo.processInfo.systemUptime * 1_000_000_000).rounded())
    }

    private func elapsed(since start: UInt64) -> UInt64 {
        max(1, now() - start)
    }

    private func message(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }
}
