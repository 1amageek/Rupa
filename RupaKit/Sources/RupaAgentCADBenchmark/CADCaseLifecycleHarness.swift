import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAutomation
import RupaCore
import RupaKit

/// Runs the category-neutral production lifecycle and returns only immutable evidence.
/// Candidate selection and command construction are injected through public contracts;
/// geometry expectations and category oracles remain outside this harness.
@MainActor
struct CADCaseLifecycleHarness {
    enum Mode {
        case normal
        case stale
    }

    private static let defaultPlanningWallNanoseconds: UInt64 = 1
    private let caseID: CADBenchmarkCaseID
    private let challenge: CADChallenge
    private let routing: CADCaseActionRouting
    private let timeoutWallNanoseconds: UInt64
    private let preRouteDelayNanoseconds: UInt64
    private let postRegistrationDelayNanoseconds: UInt64

    init(
        caseID: CADBenchmarkCaseID,
        challenge: CADChallenge,
        routing: CADCaseActionRouting,
        timeoutWallNanoseconds: UInt64,
        preRouteDelayNanoseconds: UInt64 = 0,
        postRegistrationDelayNanoseconds: UInt64 = 0
    ) {
        self.caseID = caseID
        self.challenge = challenge
        self.routing = routing
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preRouteDelayNanoseconds = preRouteDelayNanoseconds
        self.postRegistrationDelayNanoseconds = postRegistrationDelayNanoseconds
    }

    func runReference(
        candidate: any CADCandidateProtocol
    ) async throws -> CADCaseLifecycleRecord {
        let totalStart = now()
        let deadline = CADCaseDeadline(timeoutWallNanoseconds: timeoutWallNanoseconds)
        let controller = ProjectAgentCommandController(name: caseID.rawValue)
        guard !Task.isCancelled else {
            return await preflightResult(
                outcome: .cancellation,
                controller: controller,
                deadline: deadline,
                totalStart: totalStart,
                diagnostics: ["\(caseID.rawValue) was cancelled before candidate planning."]
            )
        }

        let planningStart = now()
        let context = candidateContext(controller: controller)
        try context.validate()
        let decision: CADCandidateDecision
        do {
            decision = try await deadline.run {
                try await candidate.decide(for: context)
            }
        } catch is CADCaseDeadlineError {
            return await preflightResult(
                outcome: .timeout,
                controller: controller,
                deadline: deadline,
                totalStart: totalStart,
                planningWallNanoseconds: elapsed(since: planningStart),
                diagnostics: ["\(caseID.rawValue) candidate planning exceeded its shared deadline."]
            )
        }
        guard case .action(let action) = decision else {
            return await preflightResult(
                outcome: .invalidSubmission,
                controller: controller,
                deadline: deadline,
                totalStart: totalStart,
                planningWallNanoseconds: elapsed(since: planningStart),
                diagnostics: [
                    "\(caseID.rawValue) candidate returned a non-action decision before publication."
                ]
            )
        }
        return await perform(
            action: action,
            controller: controller,
            mode: .normal,
            deadline: deadline,
            planningWallNanoseconds: elapsed(since: planningStart),
            totalStart: totalStart
        )
    }

    func run(
        action: CADCandidateAction
    ) async throws -> CADCaseLifecycleRecord {
        let totalStart = now()
        let deadline = CADCaseDeadline(timeoutWallNanoseconds: timeoutWallNanoseconds)
        let controller = ProjectAgentCommandController(name: caseID.rawValue)
        return await perform(
            action: action,
            controller: controller,
            mode: .normal,
            deadline: deadline,
            planningWallNanoseconds: elapsed(since: totalStart),
            totalStart: totalStart
        )
    }

    func runStale(
        action: CADCandidateAction
    ) async throws -> CADCaseLifecycleRecord {
        let totalStart = now()
        let deadline = CADCaseDeadline(timeoutWallNanoseconds: timeoutWallNanoseconds)
        let controller = ProjectAgentCommandController(name: "\(caseID.rawValue).stale")
        return await perform(
            action: action,
            controller: controller,
            mode: .stale,
            deadline: deadline,
            planningWallNanoseconds: elapsed(since: totalStart),
            totalStart: totalStart
        )
    }

    private func perform(
        action: CADCandidateAction,
        controller: ProjectAgentCommandController,
        mode: Mode,
        deadline: CADCaseDeadline,
        planningWallNanoseconds: UInt64,
        totalStart: UInt64
    ) async -> CADCaseLifecycleRecord {
        let workspace: ProjectWorkspace
        do {
            workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
                document: .empty(named: caseID.rawValue)
            )
            _ = try await deadline.run { @MainActor in
                try await workspace.evaluate()
            }
        } catch is CADCaseDeadlineError {
            return await preflightResult(
                outcome: .timeout,
                controller: controller,
                deadline: deadline,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["\(caseID.rawValue) workspace evaluation exceeded its shared deadline."]
            )
        } catch {
            return await preflightResult(
                outcome: .infrastructureFailure,
                controller: controller,
                deadline: deadline,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["\(caseID.rawValue) fresh workspace setup failed: \(message(error))"]
            )
        }

        guard let initialView = workspace.view else {
            return await preflightResult(
                outcome: .infrastructureFailure,
                controller: controller,
                deadline: deadline,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["\(caseID.rawValue) fresh workspace published no initial view."]
            )
        }
        let commandResult = Result {
            try routing.makeCommand(
                from: action,
                challenge: challenge,
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
        } catch is CADCaseDeadlineError {
            return await preflightResult(
                outcome: .timeout,
                controller: controller,
                sessionIDToUnregister: sessionID,
                deadline: deadline,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["\(caseID.rawValue) registration exceeded its shared deadline."]
            )
        } catch {
            return await preflightResult(
                outcome: .infrastructureFailure,
                controller: controller,
                sessionIDToUnregister: sessionID,
                deadline: deadline,
                totalStart: totalStart,
                planningWallNanoseconds: planningWallNanoseconds,
                diagnostics: ["\(caseID.rawValue) registration failed: \(message(error))"]
            )
        }

        let attempted: CADCaseLifecycleRecord
        switch commandResult {
        case .failure(let error):
            let retained = workspace.view ?? initialView
            attempted = record(
                outcome: .invalidSubmission,
                initialView: initialView,
                finalView: retained,
                routeEvidence: routeEvidence(from: initialView, to: retained),
                deadline: deadline,
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

        return await finalizeCleanup(
            attempted,
            controller: controller,
            sessionIDToUnregister: sessionID,
            totalStart: totalStart
        )
    }

    private func execute(
        command: AutomationCommand,
        controller: ProjectAgentCommandController,
        workspace: ProjectWorkspace,
        sessionID: UUID,
        initialView: ProjectViewSnapshot,
        mode: Mode,
        deadline: CADCaseDeadline,
        planningWallNanoseconds: UInt64,
        totalStart: UInt64
    ) async -> CADCaseLifecycleRecord {
        if Task.isCancelled {
            return record(
                outcome: .cancellation,
                initialView: initialView,
                finalView: workspace.view ?? initialView,
                routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    totalStart: totalStart,
                    actionCount: 1,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: ["\(caseID.rawValue) was cancelled before the production route."]
            )
        }
        if deadline.exceeded {
            return record(
                outcome: .timeout,
                initialView: initialView,
                finalView: workspace.view ?? initialView,
                routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    totalStart: totalStart,
                    actionCount: 1,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: ["\(caseID.rawValue) exceeded its wall-time budget before publication."]
            )
        }

        if mode == .stale {
            return await executeStale(
                command: command,
                controller: controller,
                workspace: workspace,
                sessionID: sessionID,
                initialView: initialView,
                deadline: deadline,
                planningWallNanoseconds: planningWallNanoseconds,
                totalStart: totalStart
            )
        }

        let routeStart = now()
        let response: AgentResponse
        do {
            response = try await deadlineResponse(
                controller: controller,
                request: request(command: command, sessionID: sessionID, coordinates: initialView),
                deadline: deadline
            )
        } catch is CADCaseDeadlineError {
            return record(
                outcome: .timeout,
                initialView: initialView,
                finalView: workspace.view ?? initialView,
                routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: elapsed(since: routeStart),
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["\(caseID.rawValue) production route exceeded its shared deadline."]
            )
        } catch {
            return record(
                outcome: .infrastructureFailure,
                initialView: initialView,
                finalView: workspace.view ?? initialView,
                routeEvidence: routeEvidence(from: initialView, to: workspace.view ?? initialView),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: elapsed(since: routeStart),
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["\(caseID.rawValue) production route failed: \(message(error))"]
            )
        }

        let routeWall = elapsed(since: routeStart)
        let finalView = workspace.view ?? initialView
        guard case .command(let automationResult) = response else {
            return record(
                outcome: .executionFailure,
                initialView: initialView,
                finalView: finalView,
                response: response,
                routeEvidence: routeEvidence(from: initialView, to: finalView),
                deadline: deadline,
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
        guard workspace.view != nil else {
            return record(
                outcome: .infrastructureFailure,
                initialView: initialView,
                response: response,
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["\(caseID.rawValue) production mutation published no final view."]
            )
        }
        if let metrics = automationResult.executionMetrics,
           metrics.commandCount != 1 {
            return record(
                outcome: .infrastructureFailure,
                initialView: initialView,
                finalView: finalView,
                response: response,
                routeEvidence: routeEvidence(from: initialView, to: finalView),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["\(caseID.rawValue) production metrics disagreed with the dispatched command count."]
            )
        }
        guard automationResult.didMutate else {
            return record(
                outcome: .executionFailure,
                initialView: initialView,
                finalView: finalView,
                response: response,
                routeEvidence: routeEvidence(from: initialView, to: finalView),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["\(caseID.rawValue) command returned without source publication."]
            )
        }
        if Task.isCancelled {
            return record(
                outcome: .cancelledAfterPublication,
                initialView: initialView,
                finalView: finalView,
                response: response,
                routeEvidence: routeEvidence(from: initialView, to: finalView),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 5
                ),
                diagnostics: ["\(caseID.rawValue) was cancelled after publication; the committed coordinate was retained without retry."]
            )
        }
        return record(
            outcome: .published,
            initialView: initialView,
            finalView: finalView,
            response: response,
            routeEvidence: routeEvidence(from: initialView, to: finalView),
            deadline: deadline,
            telemetry: telemetry(
                planningWallNanoseconds: planningWallNanoseconds,
                routeWallNanoseconds: routeWall,
                totalStart: totalStart,
                actionCount: 1,
                commandCount: 1,
                cancellationCheckpointCount: 5
            )
        )
    }

    private func executeStale(
        command: AutomationCommand,
        controller: ProjectAgentCommandController,
        workspace: ProjectWorkspace,
        sessionID: UUID,
        initialView: ProjectViewSnapshot,
        deadline: CADCaseDeadline,
        planningWallNanoseconds: UInt64,
        totalStart: UInt64
    ) async -> CADCaseLifecycleRecord {
        let preparation: AgentResponse
        do {
            preparation = try await deadlineResponse(
                controller: controller,
                request: request(command: command, sessionID: sessionID, coordinates: initialView),
                deadline: deadline
            )
        } catch is CADCaseDeadlineError {
            return record(
                outcome: .timeout,
                initialView: initialView,
                finalView: workspace.view ?? initialView,
                routeEvidence: routeEvidence(
                    from: initialView,
                    to: workspace.view ?? initialView
                ),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    totalStart: totalStart,
                    actionCount: 1,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: ["\(caseID.rawValue) stale-fixture preparation exceeded its shared deadline."]
            )
        } catch {
            return record(
                outcome: .infrastructureFailure,
                initialView: initialView,
                finalView: workspace.view ?? initialView,
                routeEvidence: routeEvidence(
                    from: initialView,
                    to: workspace.view ?? initialView
                ),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    totalStart: totalStart,
                    actionCount: 1,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: ["\(caseID.rawValue) stale-fixture preparation failed: \(message(error))"]
            )
        }
        guard case .command = preparation,
              let retained = workspace.view else {
            return record(
                outcome: .infrastructureFailure,
                initialView: initialView,
                finalView: workspace.view ?? initialView,
                routeEvidence: routeEvidence(
                    from: initialView,
                    to: workspace.view ?? initialView
                ),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    totalStart: totalStart,
                    actionCount: 1,
                    commandCount: 1,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: ["\(caseID.rawValue) could not establish stale production coordinates."]
            )
        }

        let routeStart = now()
        let staleResponse: AgentResponse
        do {
            staleResponse = try await deadlineResponse(
                controller: controller,
                request: request(command: command, sessionID: sessionID, coordinates: initialView),
                deadline: deadline
            )
        } catch is CADCaseDeadlineError {
            let after = workspace.view ?? retained
            return record(
                outcome: .timeout,
                initialView: retained,
                finalView: after,
                routeEvidence: routeEvidence(from: retained, to: after),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: elapsed(since: routeStart),
                    totalStart: totalStart,
                    actionCount: 2,
                    commandCount: 2,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["\(caseID.rawValue) stale request exceeded its shared deadline."]
            )
        } catch {
            return record(
                outcome: .infrastructureFailure,
                initialView: retained,
                finalView: workspace.view ?? retained,
                routeEvidence: routeEvidence(from: retained, to: workspace.view ?? retained),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: elapsed(since: routeStart),
                    totalStart: totalStart,
                    actionCount: 2,
                    commandCount: 2,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["\(caseID.rawValue) stale request failed: \(message(error))"]
            )
        }
        let routeWall = elapsed(since: routeStart)
        let after = workspace.view ?? retained
        guard case .failure = staleResponse else {
            return record(
                outcome: .infrastructureFailure,
                initialView: retained,
                finalView: after,
                response: staleResponse,
                routeEvidence: routeEvidence(from: retained, to: after),
                deadline: deadline,
                telemetry: telemetry(
                    planningWallNanoseconds: planningWallNanoseconds,
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    actionCount: 2,
                    commandCount: 2,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: ["\(caseID.rawValue) stale coordinates were not rejected."]
            )
        }
        return record(
            outcome: .executionFailure,
            initialView: retained,
            finalView: after,
            response: staleResponse,
            routeEvidence: routeEvidence(from: retained, to: after),
            deadline: deadline,
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

    private func candidateContext(
        controller: ProjectAgentCommandController
    ) -> CADCandidateContext {
        CADActivatedCaseContextFactory.make(
            challenge: challenge,
            operationName: routing.operationName,
            controller: controller
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
        deadline: CADCaseDeadline
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

    private func preflightResult(
        outcome: CADCaseLifecycleRecord.Outcome,
        controller: ProjectAgentCommandController,
        sessionIDToUnregister: UUID? = nil,
        deadline: CADCaseDeadline,
        totalStart: UInt64,
        planningWallNanoseconds: UInt64 = defaultPlanningWallNanoseconds,
        diagnostics: [String]
    ) async -> CADCaseLifecycleRecord {
        let pending = record(
            outcome: outcome,
            routeEvidence: .empty,
            deadline: deadline,
            telemetry: telemetry(
                planningWallNanoseconds: planningWallNanoseconds,
                totalStart: totalStart,
                cancellationCheckpointCount: 1
            ),
            diagnostics: diagnostics
        )
        return await finalizeCleanup(
            pending,
            controller: controller,
            sessionIDToUnregister: sessionIDToUnregister,
            totalStart: totalStart
        )
    }

    private func finalizeCleanup(
        _ record: CADCaseLifecycleRecord,
        controller: ProjectAgentCommandController,
        sessionIDToUnregister: UUID?,
        totalStart: UInt64
    ) async -> CADCaseLifecycleRecord {
        let cleanupStart = now()
        if let sessionIDToUnregister {
            await controller.unregister(id: sessionIDToUnregister)
        }
        let remainingRegistrationCount = await sessionCount(controller)
        return record.withCleanup(
            cleanupWallNanoseconds: elapsed(since: cleanupStart),
            remainingRegistrationCount: remainingRegistrationCount,
            totalWallNanoseconds: elapsed(since: totalStart)
        )
    }

    private func sessionCount(_ controller: ProjectAgentCommandController) async -> Int {
        guard case .status(let status) = await controller.handle(.status) else {
            return 1
        }
        return status.sessionCount
    }

    private func record(
        outcome: CADCaseLifecycleRecord.Outcome,
        initialView: ProjectViewSnapshot? = nil,
        finalView: ProjectViewSnapshot? = nil,
        response: AgentResponse? = nil,
        routeEvidence: CADCaseLifecycleRecord.RouteEvidence = .empty,
        deadline: CADCaseDeadline,
        telemetry: CADCaseLifecycleRecord.Telemetry,
        diagnostics: [String] = []
    ) -> CADCaseLifecycleRecord {
        CADCaseLifecycleRecord(
            caseID: caseID,
            outcome: outcome,
            initialView: initialView,
            finalView: finalView,
            response: response,
            routeEvidence: routeEvidence,
            telemetry: telemetry,
            deadline: deadline,
            diagnostics: diagnostics
        )
    }

    private func telemetry(
        planningWallNanoseconds: UInt64,
        routeWallNanoseconds: UInt64 = 0,
        totalStart: UInt64,
        actionCount: Int = 0,
        commandCount: Int = 0,
        cancellationCheckpointCount: Int
    ) -> CADCaseLifecycleRecord.Telemetry {
        CADCaseLifecycleRecord.Telemetry(
            planningWallNanoseconds: max(1, planningWallNanoseconds),
            routeWallNanoseconds: routeWallNanoseconds,
            totalWallNanoseconds: min(
                timeoutWallNanoseconds,
                max(1, elapsed(since: totalStart))
            ),
            actionCount: actionCount,
            commandCount: commandCount,
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            cancellationCheckpointCount: cancellationCheckpointCount
        )
    }

    private func routeEvidence(
        from initial: ProjectViewSnapshot,
        to final: ProjectViewSnapshot
    ) -> CADCaseLifecycleRecord.RouteEvidence {
        CADCaseLifecycleRecord.RouteEvidence(from: initial, to: final)
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
            return "\(caseID.rawValue) production route rejected the command: \(error.message)"
        }
        return "\(caseID.rawValue) production route returned an unexpected response: \(response)"
    }
}
