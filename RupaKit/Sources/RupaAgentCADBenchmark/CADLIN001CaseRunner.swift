import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAutomation
import RupaCore
import RupaKit
import SwiftCAD

struct CADLIN001Recorder: Equatable, Sendable {
    fileprivate init() {}
}

/// Executes one LIN-001 attempt through the registered production Agent route.
@MainActor
struct CADLIN001CaseRunner {
    private enum Mode {
        case normal
        case stale
    }

    private static let caseID: CADBenchmarkCaseID = "LIN-001"
    private static let operationName = "createLineSketch"
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000
    private let recorder = CADLIN001Recorder()
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64
    private let postRegistrationDelayNanoseconds: UInt64

    init(
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preRouteDelayNanoseconds: UInt64 = 0,
        postRegistrationDelayNanoseconds: UInt64 = 0
    ) {
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
        self.postRegistrationDelayNanoseconds = postRegistrationDelayNanoseconds
    }

    func runReference() async throws -> CADLIN001CaseResult {
        let totalStart = now()
        let deadline = CADLIN001Deadline(
            timeoutWallNanoseconds: timeoutWallNanoseconds
        )
        let controller = ProjectAgentCommandController(name: "LIN-001")
        guard !Task.isCancelled else {
            return await preflightResult(
                outcome: .cancellation,
                controller: controller,
                totalStart: totalStart,
                diagnostics: ["LIN-001 was cancelled before candidate planning."]
            )
        }

        let entry = try catalogEntry()
        let planningStart = now()
        let context = candidateContext(
            challenge: entry.challenge,
            controller: controller
        )
        try context.validate()
        let decision: CADCandidateDecision
        do {
            decision = try await deadline.run {
                try await CADLIN001ReferenceCandidate().decide(for: context)
            }
        } catch is CADLIN001DeadlineError {
            return await preflightResult(
                outcome: .timeout,
                controller: controller,
                totalStart: totalStart,
                planningWallNanoseconds: elapsed(since: planningStart),
                diagnostics: ["LIN-001 candidate planning exceeded its shared deadline."]
            )
        }
        guard case .action(let action) = decision else {
            throw CADBenchmarkError.invalidInput(
                caseID: Self.caseID.rawValue,
                reason: "The LIN-001 control candidate must produce one action."
            )
        }
        let planningWall = elapsed(since: planningStart)
        return await perform(
            action: action,
            entry: entry,
            controller: controller,
            mode: .normal,
            deadline: deadline,
            planningWallNanoseconds: planningWall,
            totalStart: totalStart
        )
    }

    func run(action: CADCandidateAction) async throws -> CADLIN001CaseResult {
        let totalStart = now()
        let deadline = CADLIN001Deadline(
            timeoutWallNanoseconds: timeoutWallNanoseconds
        )
        let planningStart = totalStart
        let controller = ProjectAgentCommandController(name: "LIN-001")
        return await perform(
            action: action,
            entry: try catalogEntry(),
            controller: controller,
            mode: .normal,
            deadline: deadline,
            planningWallNanoseconds: elapsed(since: planningStart),
            totalStart: totalStart
        )
    }

    func runStaleReference() async throws -> CADLIN001CaseResult {
        let totalStart = now()
        let deadline = CADLIN001Deadline(
            timeoutWallNanoseconds: timeoutWallNanoseconds
        )
        let planningStart = totalStart
        let entry = try catalogEntry()
        let action = try CADLIN001ReferenceCandidate.action(for: entry.challenge)
        let controller = ProjectAgentCommandController(name: "LIN-001.stale")
        return await perform(
            action: action,
            entry: entry,
            controller: controller,
            mode: .stale,
            deadline: deadline,
            planningWallNanoseconds: elapsed(since: planningStart),
            totalStart: totalStart
        )
    }

    private func perform(
        action: CADCandidateAction,
        entry: CADCatalogEntry,
        controller: ProjectAgentCommandController,
        mode: Mode,
        deadline: CADLIN001Deadline,
        planningWallNanoseconds: UInt64,
        totalStart: UInt64
    ) async -> CADLIN001CaseResult {
        let workspace: ProjectWorkspace
        do {
            workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
                document: .empty(named: Self.caseID.rawValue)
            )
            _ = try await deadline.run { @MainActor in
                try await workspace.evaluate()
            }
        } catch is CADLIN001DeadlineError {
            return await preflightResult(
                outcome: .timeout,
                controller: controller,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["LIN-001 workspace evaluation exceeded its shared deadline."]
            )
        } catch {
            return await preflightResult(
                outcome: .infrastructureFailure,
                controller: controller,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["LIN-001 fresh workspace setup failed: \(message(error))"]
            )
        }

        guard let initialView = workspace.view else {
            return await preflightResult(
                outcome: .infrastructureFailure,
                controller: controller,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["LIN-001 fresh workspace published no initial view."]
            )
        }
        let commandResult = Result {
            try makeCommand(
                from: action,
                modelingTolerance: initialView.document.document.modelingSettings.tolerance
            )
        }

        let sessionID = UUID()
        do {
            _ = try await deadline.run { @MainActor in
                let registeredID = try await controller.register(
                    workspace: workspace,
                    id: sessionID
                )
                if postRegistrationDelayNanoseconds > 0 {
                    let delay = Int64(min(
                        postRegistrationDelayNanoseconds,
                        UInt64(Int64.max)
                    ))
                    try await Task.sleep(for: .nanoseconds(delay))
                }
                return registeredID
            }
        } catch is CADLIN001DeadlineError {
            await controller.unregister(id: sessionID)
            return await preflightResult(
                outcome: .timeout,
                controller: controller,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["LIN-001 registration exceeded its shared deadline."]
            )
        } catch {
            await controller.unregister(id: sessionID)
            return await preflightResult(
                outcome: .infrastructureFailure,
                controller: controller,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["LIN-001 registration failed: \(message(error))"]
            )
        }

        let attempted: CADLIN001CaseResult
        switch commandResult {
        case .failure(let error):
            let retained = workspace.view ?? initialView
            attempted = result(
                outcome: .invalidSubmission,
                routeEvidence: routeEvidence(from: initialView, to: retained),
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    totalStart: totalStart,
                    actionCount: 1,
                    cancellationCheckpointCount: 2
                ),
                diagnostics: [message(error)]
            )
        case .success(let command):
            attempted = await execute(
                command: command,
                entry: entry,
                controller: controller,
                workspace: workspace,
                sessionID: sessionID,
                initialView: initialView,
                mode: mode,
                deadline: deadline,
                planningWallNanoseconds: planningWallNanoseconds,
                totalStart: totalStart
            )
        }

        let cleanupStart = now()
        await controller.unregister(id: sessionID)
        let remainingRegistrationCount = await sessionCount(controller)
        return attempted
            .withCleanupEvidence(
                cleanupWallNanoseconds: elapsed(since: cleanupStart),
                remainingRegistrationCount: remainingRegistrationCount
            )
            .withTotalWallNanoseconds(elapsed(since: totalStart))
    }

    private func execute(
        command: AutomationCommand,
        entry: CADCatalogEntry,
        controller: ProjectAgentCommandController,
        workspace: ProjectWorkspace,
        sessionID: UUID,
        initialView: ProjectViewSnapshot,
        mode: Mode,
        deadline: CADLIN001Deadline,
        planningWallNanoseconds: UInt64,
        totalStart: UInt64
    ) async -> CADLIN001CaseResult {
        if Task.isCancelled {
            return result(
                outcome: .cancellation,
                routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    totalStart: totalStart,
                    actionCount: 1,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: ["LIN-001 was cancelled before the production route."]
            )
        }
        if deadline.exceeded {
            return result(
                outcome: .timeout,
                routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    totalStart: totalStart,
                    actionCount: 1,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: ["LIN-001 exceeded its wall-time budget before publication."]
            )
        }

        if mode == .stale {
            let preparation: AgentResponse
            do {
                preparation = try await deadlineResponse(
                    controller: controller,
                    request: request(
                        command: command,
                        sessionID: sessionID,
                        coordinates: initialView
                    ),
                    deadline: deadline
                )
            } catch is CADLIN001DeadlineError {
                return result(
                    outcome: .timeout,
                    routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                    telemetry: telemetry(
                        planningWallNanoseconds: planningWallNanoseconds,
                        totalStart: totalStart,
                        actionCount: 1,
                        cancellationCheckpointCount: 3
                    ),
                    diagnostics: ["LIN-001 stale-fixture preparation exceeded its shared deadline."]
                )
            } catch {
                return result(
                    outcome: .infrastructureFailure,
                    routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                    telemetry: telemetry(
                        planningWallNanoseconds: planningWallNanoseconds,
                        totalStart: totalStart,
                        actionCount: 1,
                        cancellationCheckpointCount: 3
                    ),
                    diagnostics: ["LIN-001 stale-fixture preparation failed: \(message(error))"]
                )
            }
            guard case .command = preparation,
                  let retained = workspace.view else {
                return result(
                    outcome: .infrastructureFailure,
                    routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                    telemetry: telemetry(
                        planningWallNanoseconds: planningWallNanoseconds,
                        totalStart: totalStart,
                        actionCount: 1,
                        commandCount: 1,
                        cancellationCheckpointCount: 3
                    ),
                    diagnostics: ["LIN-001 could not establish stale production coordinates."]
                )
            }
            let routeStart = now()
            let staleResponse: AgentResponse
            do {
                staleResponse = try await deadlineResponse(
                    controller: controller,
                    request: request(
                        command: command,
                        sessionID: sessionID,
                        coordinates: initialView
                    ),
                    deadline: deadline
                )
            } catch is CADLIN001DeadlineError {
                let after = workspace.view ?? retained
                return result(
                    outcome: .timeout,
                    routeEvidence: routeEvidence(from: retained, to: after),
                    telemetry: telemetry(
                        planningWallNanoseconds: planningWallNanoseconds,
                        routeWallNanoseconds: elapsed(since: routeStart),
                        totalStart: totalStart,
                        actionCount: 2,
                        commandCount: 2,
                        cancellationCheckpointCount: 4
                    ),
                    diagnostics: ["LIN-001 stale request exceeded its shared deadline."]
                )
            } catch {
                return result(
                    outcome: .infrastructureFailure,
                    routeEvidence: routeEvidence(from: retained, to: workspace.view ?? retained),
                    telemetry: telemetry(
                        planningWallNanoseconds: planningWallNanoseconds,
                        routeWallNanoseconds: elapsed(since: routeStart),
                        totalStart: totalStart,
                        actionCount: 2,
                        commandCount: 2,
                        cancellationCheckpointCount: 4
                    ),
                    diagnostics: ["LIN-001 stale request failed: \(message(error))"]
                )
            }
            let routeWall = elapsed(since: routeStart)
            let after = workspace.view ?? retained
            guard case .failure = staleResponse else {
                return result(
                    outcome: .infrastructureFailure,
                    routeEvidence: routeEvidence(from: retained, to: after),
                    telemetry: telemetry(
                        planningWallNanoseconds: planningWallNanoseconds,
                        routeWallNanoseconds: routeWall,
                        totalStart: totalStart,
                        actionCount: 2,
                        commandCount: 2,
                        cancellationCheckpointCount: 4
                    ),
                    diagnostics: ["LIN-001 stale coordinates were not rejected."]
                )
            }
            return result(
                outcome: .executionFailure,
                routeEvidence: routeEvidence(from: retained, to: after),
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 2,
                    commandCount: 2,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: [responseMessage(staleResponse)]
            )
        }

        let routeStart = now()
        let response: AgentResponse
        do {
            response = try await deadlineResponse(
                controller: controller,
                request: request(
                    command: command,
                    sessionID: sessionID,
                    coordinates: initialView
                ),
                deadline: deadline
            )
        } catch is CADLIN001DeadlineError {
            return result(
                outcome: .timeout,
                routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: elapsed(since: routeStart),
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["LIN-001 production route exceeded its shared deadline."]
            )
        } catch {
            return result(
                outcome: .infrastructureFailure,
                routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: elapsed(since: routeStart),
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["LIN-001 production route failed: \(message(error))"]
            )
        }
        let routeWall = elapsed(since: routeStart)
        guard case .command(let automationResult) = response else {
            return result(
                outcome: .executionFailure,
                routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: [responseMessage(response)]
            )
        }

        guard let finalView = workspace.view else {
            return result(
                outcome: .infrastructureFailure,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["LIN-001 production mutation published no final view."]
            )
        }
        let publishedEvidence = routeEvidence(from: initialView, to: finalView)
        let commandCount = 1
        if let metrics = automationResult.executionMetrics,
           metrics.commandCount != commandCount {
            return result(
                outcome: .infrastructureFailure,
                routeEvidence: publishedEvidence,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: commandCount,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["LIN-001 production metrics disagreed with the dispatched command count."]
            )
        }
        let stepResult = CADCandidateStepResult(
            stepIndex: 0,
            operation: Self.operationName,
            status: automationResult.didMutate ? .published : .unchanged,
            primaryFeatureID: automationResult.primaryFeatureID?.description,
            createdFeatureIDs: automationResult.createdFeatureIDs.map(\.description),
            diagnostics: automationResult.diagnostics.map(\.message)
        )
        let bindings = CADOutputRoleBindings(bindings: [
            CADOutputRoleBinding(role: "segment", stepIndex: 0, selector: .primary),
        ])
        guard automationResult.didMutate else {
            return result(
                outcome: .executionFailure,
                candidateResult: stepResult,
                routeEvidence: publishedEvidence,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: commandCount,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["LIN-001 command returned without source publication."]
            )
        }

        if Task.isCancelled {
            return result(
                outcome: .cancellation,
                candidateResult: stepResult,
                roleBindings: bindings,
                routeEvidence: publishedEvidence,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: commandCount,
                    cancellationCheckpointCount: 5
                ),
                diagnostics: ["LIN-001 was cancelled after publication; the committed coordinate was retained without retry."]
            )
        }

        let oracleStart = now()
        do {
            guard case .line(let expected) = entry.expected else {
                throw CADLIN001OracleError.mismatch("LIN-001 has no private line expectation.")
            }
            let observation = try await deadline.run {
                try CADLIN001Oracle.evaluate(
                    expected: expected,
                    challenge: entry.challenge,
                    bindings: bindings,
                    stepResults: [stepResult],
                    snapshot: finalView
                )
            }
            let oracleWall = elapsed(since: oracleStart)
            return result(
                outcome: .realized,
                candidateResult: stepResult,
                roleBindings: bindings,
                routeEvidence: publishedEvidence,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    oracleWallNanoseconds: oracleWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: commandCount,
                    readCount: observation.readCount,
                    entityCount: observation.entityCount,
                    featureCount: observation.featureCount,
                    bodyCount: observation.bodyCount,
                    cancellationCheckpointCount: 6
                )
            )
        } catch is CADLIN001DeadlineError {
            return result(
                outcome: .timeout,
                candidateResult: stepResult,
                roleBindings: bindings,
                routeEvidence: publishedEvidence,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: commandCount,
                    readCount: 1,
                    featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                    bodyCount: finalView.evaluationSnapshot.bodyCount,
                    cancellationCheckpointCount: 6
                ),
                diagnostics: ["LIN-001 oracle exceeded its shared deadline after publication; no retry was attempted."]
            )
        } catch let error as CADLIN001OracleError {
            let observedCounts: (readCount: Int, entityCount: Int)
            do {
                let source = try SketchEntitySnapshotService().snapshot(
                    document: finalView.document.document,
                    objectRegistry: finalView.objectRegistry
                )
                observedCounts = (2, source.counts.entityCount)
            } catch {
                return result(
                    outcome: .oracleFailure,
                    candidateResult: stepResult,
                    roleBindings: bindings,
                    routeEvidence: publishedEvidence,
                    telemetry: telemetry(
                        planningWallNanoseconds: planningWallNanoseconds,
                        routeWallNanoseconds: routeWall,
                        oracleWallNanoseconds: elapsed(since: oracleStart),
                        totalStart: totalStart,
                        actionCount: 1,
                        commandCount: commandCount,
                        readCount: 2,
                        featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                        bodyCount: finalView.evaluationSnapshot.bodyCount,
                        cancellationCheckpointCount: 6
                    ),
                    diagnostics: ["LIN-001 failure telemetry read failed: \(message(error))"]
                )
            }
            return result(
                outcome: .invalidSubmission,
                candidateResult: stepResult,
                roleBindings: bindings,
                routeEvidence: publishedEvidence,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: commandCount,
                    readCount: observedCounts.readCount,
                    entityCount: observedCounts.entityCount,
                    featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                    bodyCount: finalView.evaluationSnapshot.bodyCount,
                    cancellationCheckpointCount: 6
                ),
                diagnostics: [error.description]
            )
        } catch {
            return result(
                outcome: .oracleFailure,
                candidateResult: stepResult,
                roleBindings: bindings,
                routeEvidence: publishedEvidence,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    oracleWallNanoseconds: elapsed(since: oracleStart),
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: commandCount,
                    readCount: 1,
                    featureCount: finalView.document.document.cadDocument.designGraph.nodes.count,
                    bodyCount: finalView.evaluationSnapshot.bodyCount,
                    cancellationCheckpointCount: 6
                ),
                diagnostics: ["LIN-001 oracle failed: \(message(error))"]
            )
        }
    }

    private func candidateContext(
        challenge: CADChallenge,
        controller: ProjectAgentCommandController
    ) -> CADCandidateContext {
        let available = controller.capabilityDescriptors().contains { descriptor in
            descriptor.name == Self.operationName
        }
        return CADCandidateContext(
            challenge: challenge,
            capabilities: CADCapabilitySnapshot(
                version: "agent-capabilities.v1",
                statuses: [
                    CADCapabilityStatus(
                        id: challenge.requiredCapability.id,
                        version: challenge.requiredCapability.version,
                        available: available,
                        reasonCode: available ? nil : "not-exposed"
                    ),
                ]
            ),
            remainingRounds: challenge.budget.maximumRounds,
            remainingActions: challenge.budget.maximumActions
        )
    }

    private func makeCommand(
        from action: CADCandidateAction,
        modelingTolerance: ModelingTolerance
    ) throws -> AutomationCommand {
        guard case .automation(.sketch(.line(let name, let plane, let start, let end))) = action,
              !name.isEmpty,
              plane == .xy else {
            throw CADBenchmarkError.invalidInput(
                caseID: Self.caseID.rawValue,
                reason: "LIN-001 accepts one named XY line action."
            )
        }
        try start.validate(caseID: Self.caseID, field: "action.start")
        try end.validate(caseID: Self.caseID, field: "action.end")
        let startMeters = start.meters
        let endMeters = end.meters
        guard abs(startMeters.z) <= modelingTolerance.distance,
              abs(endMeters.z) <= modelingTolerance.distance else {
            throw CADBenchmarkError.invalidInput(
                caseID: Self.caseID.rawValue,
                reason: "LIN-001 XY endpoints must have zero normal coordinates."
            )
        }
        return .createLineSketch(
            name: name,
            plane: .xy,
            start: SketchPoint(
                x: .constant(.length(startMeters.x, unit: .meter)),
                y: .constant(.length(startMeters.y, unit: .meter))
            ),
            end: SketchPoint(
                x: .constant(.length(endMeters.x, unit: .meter)),
                y: .constant(.length(endMeters.y, unit: .meter))
            )
        )
    }

    private func request(
        command: AutomationCommand,
        sessionID: UUID,
        coordinates: ProjectViewSnapshot
    ) -> AgentRequest {
        .execute(
            sessionID: sessionID,
            command: command,
            expectedGeneration: coordinates.documentGeneration,
            expectedWorkspaceRevision: coordinates.workspaceState.revision
        )
    }

    private func deadlineResponse(
        controller: ProjectAgentCommandController,
        request: AgentRequest,
        deadline: CADLIN001Deadline
    ) async throws -> AgentResponse {
        if preRouteDelayNanoseconds > 0 {
            let delay = Int64(min(preRouteDelayNanoseconds, UInt64(Int64.max)))
            try await deadline.run {
                try await Task.sleep(for: .nanoseconds(delay))
            }
        }
        return try await deadline.run { @MainActor in
            await controller.handle(request)
        }
    }

    private func catalogEntry() throws -> CADCatalogEntry {
        guard let entry = try CADInternalCatalogStore.entries().first(where: {
            $0.challenge.id == Self.caseID
        }) else {
            throw CADBenchmarkError.missingCaseID(Self.caseID.rawValue)
        }
        return entry
    }

    private func routeEvidence(
        from initial: ProjectViewSnapshot,
        to final: ProjectViewSnapshot
    ) -> CADLIN001RouteEvidence {
        CADLIN001RouteEvidence(
            initialDocumentGeneration: initial.documentGeneration,
            finalDocumentGeneration: final.documentGeneration,
            initialTransactionRevision: initial.transactionRevision,
            finalTransactionRevision: final.transactionRevision,
            initialPublicationSequence: initial.publicationSequence,
            finalPublicationSequence: final.publicationSequence,
            initialWorkspaceRevision: initial.workspaceState.revision,
            finalWorkspaceRevision: final.workspaceState.revision,
            didPublish: final.publicationSequence > initial.publicationSequence
        )
    }

    private func preflightResult(
        outcome: CADCaseOutcome,
        controller: ProjectAgentCommandController,
        totalStart: UInt64,
        planningWallNanoseconds: UInt64 = 1,
        diagnostics: [String]
    ) async -> CADLIN001CaseResult {
        let cleanupStart = now()
        let count = await sessionCount(controller)
        return result(
            outcome: outcome,
            routeEvidence: .empty,
            telemetry: telemetry(
                planningWallNanoseconds: planningWallNanoseconds,
                totalStart: totalStart,
                cancellationCheckpointCount: 1
            ),
            diagnostics: diagnostics
        )
        .withCleanupEvidence(
            cleanupWallNanoseconds: elapsed(since: cleanupStart),
            remainingRegistrationCount: count
        )
        .withTotalWallNanoseconds(elapsed(since: totalStart))
    }

    private func sessionCount(_ controller: ProjectAgentCommandController) async -> Int {
        guard case .status(let status) = await controller.handle(.status) else {
            return 1
        }
        return status.sessionCount
    }

    private func result(
        outcome: CADCaseOutcome,
        candidateResult: CADCandidateStepResult? = nil,
        roleBindings: CADOutputRoleBindings? = nil,
        routeEvidence: CADLIN001RouteEvidence = .empty,
        telemetry: CADLIN001Telemetry,
        diagnostics: [String] = []
    ) -> CADLIN001CaseResult {
        CADLIN001CaseResult(
            recordedBy: recorder,
            outcome: outcome,
            candidateResult: candidateResult,
            roleBindings: roleBindings,
            routeEvidence: routeEvidence,
            telemetry: telemetry,
            diagnostics: diagnostics
        )
    }

    private func telemetry(
        planningWallNanoseconds: UInt64,
        routeWallNanoseconds: UInt64 = 0,
        oracleWallNanoseconds: UInt64 = 0,
        totalStart: UInt64,
        actionCount: Int = 0,
        commandCount: Int = 0,
        readCount: Int = 0,
        entityCount: Int = 0,
        featureCount: Int = 0,
        bodyCount: Int = 0,
        cancellationCheckpointCount: Int
    ) -> CADLIN001Telemetry {
        CADLIN001Telemetry(
            planningWallNanoseconds: max(1, planningWallNanoseconds),
            routeWallNanoseconds: routeWallNanoseconds,
            oracleWallNanoseconds: oracleWallNanoseconds,
            totalWallNanoseconds: min(
                timeoutWallNanoseconds,
                max(1, elapsed(since: totalStart))
            ),
            actionCount: actionCount,
            commandCount: commandCount,
            readCount: readCount,
            entityCount: entityCount,
            featureCount: featureCount,
            bodyCount: bodyCount,
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            cancellationCheckpointCount: cancellationCheckpointCount
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

    private func responseMessage(_ response: AgentResponse) -> String {
        if case .failure(let error) = response {
            return "LIN-001 production route rejected the command: \(error.message)"
        }
        return "LIN-001 production route returned an unexpected response: \(response)"
    }
}
