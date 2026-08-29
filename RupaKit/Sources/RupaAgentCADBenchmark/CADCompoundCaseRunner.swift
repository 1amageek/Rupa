import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAutomation
import RupaCore
import RupaKit
import SwiftCAD

/// Projects the category-neutral lifecycle into one ordered compound result.
///
/// Candidate decisions cross the public CADCandidateProtocol and
/// CADCandidateAction contracts. A public compound action is lowered to one
/// ordered batch of primitive commands, while the production controller owns
/// validation, staging, commit, evaluation, and history publication.
@MainActor
struct CADCompoundCaseRunner {
    struct SourceCounts: Equatable, Sendable {
        let readCount: Int
        let entityCount: Int
        let featureCount: Int
        let bodyCount: Int
        let faceCount: Int
        let edgeCount: Int
        let vertexCount: Int
    }

    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let activatedCase: CADActivatedCompoundCase
    private let recorder = CADCompoundRecorder()
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64
    private let postRegistrationDelayNanoseconds: UInt64
    private let failureSourceReader: @MainActor (ProjectViewSnapshot) throws -> SourceCounts

    init(
        case activatedCase: CADActivatedCompoundCase,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0,
        postRegistrationDelayNanoseconds: UInt64 = 0,
        failureSourceReader: @escaping @MainActor (ProjectViewSnapshot) throws -> SourceCounts = {
            try Self.readSourceCounts(in: $0)
        }
    ) {
        self.activatedCase = activatedCase
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
        self.postRegistrationDelayNanoseconds = postRegistrationDelayNanoseconds
        self.failureSourceReader = failureSourceReader
    }

    private var caseID: CADBenchmarkCaseID { activatedCase.caseID }

    func runReference() async throws -> CADCompoundCaseResult {
        try await run(candidate: CADCompoundReferenceCandidate())
    }

    func run(candidate: any CADCandidateProtocol) async throws -> CADCompoundCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let record = try await harness(challenge: entry.challenge).runReference(candidate: candidate)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    /// Runs one public compound action through one production batch.
    func run(actions: [CADCompoundMemberAction]) async throws -> CADCompoundCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let action = CADCandidateAction.compound(CADCompoundAction(members: actions))
        let record = try await harness(challenge: entry.challenge).run(action: action)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    func runStaleReference() async throws -> CADCompoundCaseResult {
        let entry = try activatedCase.catalogEntry
        let members = try CADCompoundReferenceCandidate.members(for: entry.challenge)
        return try await runStale(actions: members)
    }

    func runStale(actions: [CADCompoundMemberAction]) async throws -> CADCompoundCaseResult {
        let totalStart = now()
        let entry = try activatedCase.catalogEntry
        let action = CADCandidateAction.compound(CADCompoundAction(members: actions))
        let record = try await harness(challenge: entry.challenge).runStale(action: action)
        return await project(record, entry: entry, totalStart: totalStart)
    }

    private func harness(
        challenge: CADChallenge
    ) -> CADCaseLifecycleHarness {
        CADCaseLifecycleHarness(
            caseID: caseID,
            challenge: challenge,
            routing: CADCaseActionRouting(
                operationName: "",
                planBuilder: { [self] action, challenge, tolerance in
                    return try makePlan(
                        from: action,
                        challenge: challenge,
                        modelingTolerance: tolerance
                    )
                }
            ),
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preRouteDelayNanoseconds: preRouteDelayNanoseconds,
            postRegistrationDelayNanoseconds: postRegistrationDelayNanoseconds
        )
    }

    private func makePlan(
        from action: CADCandidateAction,
        challenge: CADChallenge,
        modelingTolerance: ModelingTolerance
    ) throws -> CADCaseActionPlan {
        guard case .compound(let compound) = action else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A compound case requires one public compound action."
            )
        }
        let projection = try CADCompoundChallengeProjection.decode(challenge)
        guard compound.members.count == projection.members.count else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A compound candidate must provide exactly one member for every declared role."
            )
        }

        var commands: [AutomationCommand] = []
        commands.reserveCapacity(compound.members.count)
        for (index, submitted) in compound.members.enumerated() {
            let expected = projection.members[index]
            commands.append(
                try CADCompoundGeometryMapping.command(
                    for: submitted,
                    expected: expected,
                    modelingTolerance: modelingTolerance,
                    caseID: caseID
                )
            )
        }
        return .batch(commands)
    }

    private func project(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        totalStart: UInt64
    ) async -> CADCompoundCaseResult {
        let expectedMemberCount = expectedMembers(in: entry)
        let evidence = routeEvidence(
            from: record,
            expectedMemberCount: expectedMemberCount
        )
        switch record.outcome {
        case .published:
            return await projectPublished(
                record,
                entry: entry,
                evidence: evidence,
                totalStart: totalStart
            )
        case .cancelledAfterPublication:
            return finish(
                publishedMutation(
                    record,
                    entry: entry,
                    evidence: evidence,
                    outcome: .cancellation
                ),
                totalStart: totalStart
            )
        case .invalidSubmission:
            return finish(result(.invalidSubmission, record, evidence), totalStart: totalStart)
        case .executionFailure:
            return finish(result(.executionFailure, record, evidence), totalStart: totalStart)
        case .timeout:
            return finish(result(.timeout, record, evidence), totalStart: totalStart)
        case .cancellation:
            return finish(result(.cancellation, record, evidence), totalStart: totalStart)
        case .infrastructureFailure:
            return finish(result(.infrastructureFailure, record, evidence), totalStart: totalStart)
        }
    }

    private func projectPublished(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        evidence: CADCompoundRouteEvidence,
        totalStart: UInt64
    ) async -> CADCompoundCaseResult {
        guard let initialView = record.initialView,
              let finalView = record.finalView,
              let batch = batchResult(from: record.response),
              batch.results.count == entry.challenge.outputRoles.count,
              initialView.documentGeneration.value
                  <= UInt64.max - UInt64(batch.results.count),
              batch.results.enumerated().allSatisfy({ index, result in
                  result.didMutate
                      && result.generation.value
                          == initialView.documentGeneration.value + UInt64(index + 1)
              }) else {
            return finish(result(.infrastructureFailure, record, evidence), totalStart: totalStart)
        }
        let (steps, bindings) = publishedEvidence(
            from: batch.results,
            challenge: entry.challenge
        )
        let oracleStart = now()
        do {
            guard case .compound(let expected) = entry.expected else {
                throw CADCompoundOracleError.mismatch(
                    "The activated compound has no private compound expectation."
                )
            }
            let observation = try await record.deadline.run {
                try CADCompoundOracle.evaluate(
                    expected: expected,
                    challenge: entry.challenge,
                    bindings: bindings,
                    stepResults: steps,
                    snapshot: finalView
                )
            }
            return finish(
                result(
                    .realized,
                    record,
                    evidence,
                    candidateResults: steps,
                    roleBindings: bindings,
                    telemetry: telemetry(from: record).replacing(
                        oracleWallNanoseconds: elapsed(since: oracleStart),
                        readCount: observation.readCount,
                        entityCount: observation.entityCount,
                        featureCount: observation.featureCount,
                        bodyCount: observation.bodyCount,
                        faceCount: observation.faceCount,
                        edgeCount: observation.edgeCount,
                        vertexCount: observation.vertexCount
                    )
                ),
                totalStart: totalStart
            )
        } catch is CADCaseDeadlineError {
            return finish(
                failureResult(
                    outcome: .timeout,
                    record: record,
                    evidence: evidence,
                    candidateResults: steps,
                    roleBindings: bindings,
                    view: finalView,
                    oracleStart: oracleStart,
                    diagnostic: "\(caseID.rawValue) compound oracle exceeded its shared deadline after publication; no retry was attempted."
                ),
                totalStart: totalStart
            )
        } catch let error as CADCompoundOracleError {
            return finish(
                failureResult(
                    outcome: .invalidSubmission,
                    record: record,
                    evidence: evidence,
                    candidateResults: steps,
                    roleBindings: bindings,
                    view: finalView,
                    oracleStart: oracleStart,
                    diagnostic: error.description
                ),
                totalStart: totalStart
            )
        } catch {
            return finish(
                failureResult(
                    outcome: .oracleFailure,
                    record: record,
                    evidence: evidence,
                    candidateResults: steps,
                    roleBindings: bindings,
                    view: finalView,
                    oracleStart: oracleStart,
                    diagnostic: "\(caseID.rawValue) compound oracle failed: \(message(error))"
                ),
                totalStart: totalStart
            )
        }
    }

    private func publishedMutation(
        _ record: CADCaseLifecycleRecord,
        entry: CADCatalogEntry,
        evidence: CADCompoundRouteEvidence,
        outcome: CADCaseOutcome
    ) -> CADCompoundCaseResult {
        guard let batch = batchResult(from: record.response),
              batch.results.count == entry.challenge.outputRoles.count else {
            return result(.infrastructureFailure, record, evidence)
        }
        let (steps, bindings) = publishedEvidence(
            from: batch.results,
            challenge: entry.challenge
        )
        return result(
            outcome,
            record,
            evidence,
            candidateResults: steps,
            roleBindings: bindings
        )
    }

    private func failureResult(
        outcome: CADCaseOutcome,
        record: CADCaseLifecycleRecord,
        evidence: CADCompoundRouteEvidence,
        candidateResults: [CADCandidateStepResult],
        roleBindings: CADOutputRoleBindings,
        view: ProjectViewSnapshot,
        oracleStart: UInt64,
        diagnostic: String
    ) -> CADCompoundCaseResult {
        do {
            let counts = try sourceCounts(in: view)
            return result(
                outcome,
                record,
                evidence,
                candidateResults: candidateResults,
                roleBindings: roleBindings,
                telemetry: telemetry(from: record).replacing(
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    readCount: counts.readCount,
                    entityCount: counts.entityCount,
                    featureCount: counts.featureCount,
                    bodyCount: counts.bodyCount,
                    faceCount: counts.faceCount,
                    edgeCount: counts.edgeCount,
                    vertexCount: counts.vertexCount
                ),
                diagnostics: [diagnostic]
            )
        } catch {
            return result(
                .oracleFailure,
                record,
                evidence,
                candidateResults: candidateResults,
                roleBindings: roleBindings,
                telemetry: telemetry(from: record).replacing(
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    readCount: 2,
                    featureCount: view.document.document.cadDocument.designGraph.nodes.count,
                    bodyCount: view.evaluationSnapshot.bodyCount
                ),
                diagnostics: [
                    diagnostic,
                    "\(caseID.rawValue) compound failure telemetry read failed: \(message(error))",
                ]
            )
        }
    }

    private func result(
        _ outcome: CADCaseOutcome,
        _ record: CADCaseLifecycleRecord,
        _ evidence: CADCompoundRouteEvidence,
        candidateResults: [CADCandidateStepResult]? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        telemetry: CADCompoundTelemetry? = nil,
        diagnostics: [String]? = nil
    ) -> CADCompoundCaseResult {
        CADCompoundCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateResults: candidateResults,
            roleBindings: roleBindings,
            routeEvidence: evidence,
            telemetry: telemetry ?? self.telemetry(from: record),
            diagnostics: diagnostics ?? record.diagnostics
        )
    }

    private func telemetry(from record: CADCaseLifecycleRecord) -> CADCompoundTelemetry {
        CADCompoundTelemetry(
            planningWallNanoseconds: record.telemetry.planningWallNanoseconds,
            routeWallNanoseconds: record.telemetry.routeWallNanoseconds,
            oracleWallNanoseconds: 0,
            totalWallNanoseconds: record.telemetry.totalWallNanoseconds,
            actionCount: record.telemetry.actionCount,
            commandCount: record.telemetry.commandCount,
            readCount: 0,
            entityCount: 0,
            featureCount: 0,
            bodyCount: 0,
            faceCount: 0,
            edgeCount: 0,
            vertexCount: 0,
            timeoutWallNanoseconds: record.telemetry.timeoutWallNanoseconds,
            cancellationCheckpointCount: record.telemetry.cancellationCheckpointCount
        )
    }

    private func routeEvidence(
        from record: CADCaseLifecycleRecord,
        expectedMemberCount: Int
    ) -> CADCompoundRouteEvidence {
        guard record.routeEvidence.didPublish,
              let batch = batchResult(from: record.response) else {
            return CADCompoundRouteEvidence(from: record.routeEvidence)
        }
        return CADCompoundRouteEvidence(
            from: record.routeEvidence,
            memberCount: expectedMemberCount,
            commandCount: batch.metrics.commandCount,
            evaluationPassCount: batch.metrics.evaluationPassCount,
            historyEntryCount: batch.metrics.historyEntryCount
        )
    }

    private func expectedMembers(in entry: CADCatalogEntry) -> Int {
        guard case .compound(let expected) = entry.expected else { return 0 }
        return expected.members.count
    }

    private func batchResult(from response: AgentResponse?) -> AgentBatchResult? {
        guard case .batch(let result) = response else { return nil }
        return result
    }

    private func publishedEvidence(
        from results: [AutomationResult],
        challenge: CADChallenge
    ) -> ([CADCandidateStepResult], CADOutputRoleBindings) {
        let roles = challenge.outputRoles.map(\.name)
        let projection: CADCompoundChallengeProjection?
        do {
            projection = try CADCompoundChallengeProjection.decode(challenge)
        } catch {
            projection = nil
        }
        let steps = results.enumerated().map { index, result in
            let primitiveName: String
            if let member = projection?.members[safe: index] {
                primitiveName = member.primitive == .box
                    ? "createExtrudedRectangle"
                    : "createExtrudedCircle"
            } else {
                primitiveName = "compound"
            }
            let role = roles[safe: index] ?? "member-\(index)"
            return CADCandidateStepResult(
                stepIndex: index,
                operation: "\(primitiveName).\(role)",
                status: result.didMutate ? .published : .unchanged,
                primaryFeatureID: result.primaryFeatureID?.description,
                createdFeatureIDs: result.createdFeatureIDs.map(\.description),
                diagnostics: result.diagnostics.map(\.message)
            )
        }
        return (
            steps,
            CADOutputRoleBindings(bindings: roles.enumerated().map { index, role in
                CADOutputRoleBinding(role: role, stepIndex: index, selector: .primary)
            })
        )
    }

    private func sourceCounts(in view: ProjectViewSnapshot) throws -> SourceCounts {
        try failureSourceReader(view)
    }

    private static func readSourceCounts(in view: ProjectViewSnapshot) throws -> SourceCounts {
        let source = try SketchEntitySnapshotService().snapshot(
            document: view.document.document,
            objectRegistry: view.objectRegistry
        )
        let topology = try TopologySnapshotService().snapshot(
            document: view.document.document,
            objectRegistry: view.objectRegistry,
            currentEvaluation: view.cadInteraction,
            currentGeneration: view.documentGeneration
        )
        return SourceCounts(
            readCount: 2,
            entityCount: source.counts.entityCount,
            featureCount: view.document.document.cadDocument.designGraph.nodes.count,
            bodyCount: topology.counts.bodyCount,
            faceCount: topology.counts.faceCount,
            edgeCount: topology.counts.edgeCount,
            vertexCount: topology.counts.vertexCount
        )
    }

    private func finish(
        _ result: CADCompoundCaseResult,
        totalStart: UInt64
    ) -> CADCompoundCaseResult {
        result.replacingTotalWallNanoseconds(elapsed(since: totalStart))
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
           description.isEmpty == false {
            return description
        }
        return String(describing: error)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
