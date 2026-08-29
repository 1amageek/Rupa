import Foundation
import RupaAgentProtocol
import RupaAgentRuntime

/// Runs one activated sphere case through the production Agent capability surface.
///
/// The current Agent has no sphere ingress, so this runner deliberately owns
/// no project document and dispatches no action or command. It observes
/// capabilities, evaluates the candidate's typed decision, and confirms that
/// the fresh controller still has zero sessions before returning.
@MainActor
struct CADSphereCaseRunner {
    private static let defaultTimeoutWallNanoseconds: UInt64 = 10_000_000_000

    private let activatedCase: CADActivatedSphereCase
    private let timeoutWallNanoseconds: UInt64
    private let preObservationDelayNanoseconds: UInt64
    private let recorder = CADSphereRecorder()

    init(
        case activatedCase: CADActivatedSphereCase,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preObservationDelayNanoseconds: UInt64 = 0
    ) {
        self.activatedCase = activatedCase
        self.timeoutWallNanoseconds = max(1, timeoutWallNanoseconds)
        self.preObservationDelayNanoseconds = preObservationDelayNanoseconds
    }

    init(
        caseID: CADBenchmarkCaseID,
        timeoutWallNanoseconds: UInt64 = Self.defaultTimeoutWallNanoseconds,
        preObservationDelayNanoseconds: UInt64 = 0
    ) throws {
        self.init(
            case: try CADActivatedSphereCase(caseID: caseID),
            timeoutWallNanoseconds: timeoutWallNanoseconds,
            preObservationDelayNanoseconds: preObservationDelayNanoseconds
        )
    }

    var caseID: CADBenchmarkCaseID {
        activatedCase.caseID
    }

    func runReference() async throws -> CADSphereCaseResult {
        try await run(candidate: CADSphereReferenceCandidate())
    }

    func run(candidate: any CADCandidateProtocol) async throws -> CADSphereCaseResult {
        let totalStart = now()
        let deadline = CADCaseDeadline(timeoutWallNanoseconds: timeoutWallNanoseconds)
        let controller = ProjectAgentCommandController(name: caseID.rawValue)

        guard !Task.isCancelled else {
            let pending = result(
                outcome: .cancellation,
                routeEvidence: .empty,
                telemetry: telemetry(
                    planningWallNanoseconds: elapsed(since: totalStart),
                    routeWallNanoseconds: 0,
                    totalStart: totalStart,
                    capabilityRequestCount: 0,
                    readCount: 0,
                    cancellationCheckpointCount: 1
                ),
                diagnostics: [
                    "\(caseID.rawValue) was cancelled before sphere capability observation."
                ]
            )
            return await finalizeCleanup(
                pending,
                controller: controller,
                totalStart: totalStart
            )
        }

        let entry: CADCatalogEntry
        do {
            entry = try activatedCase.catalogEntry
        } catch {
            let pending = result(
                outcome: .infrastructureFailure,
                routeEvidence: .empty,
                telemetry: telemetry(
                    planningWallNanoseconds: elapsed(since: totalStart),
                    routeWallNanoseconds: 0,
                    totalStart: totalStart,
                    capabilityRequestCount: 0,
                    readCount: 0,
                    cancellationCheckpointCount: 1
                ),
                diagnostics: [
                    "\(caseID.rawValue) sphere catalog lookup failed: \(message(error))"
                ]
            )
            return await finalizeCleanup(
                pending,
                controller: controller,
                totalStart: totalStart
            )
        }

        let planningStart = now()
        let routeStart = now()
        let observation: CADSphereCapabilityObservation
        do {
            if preObservationDelayNanoseconds > 0 {
                let delay = Int64(min(preObservationDelayNanoseconds, UInt64(Int64.max)))
                try await deadline.run {
                    try await Task.sleep(for: .nanoseconds(delay))
                }
            }
            observation = try await deadline.run {
                try await CADSphereCapabilityObservation.observe(
                    challenge: entry.challenge,
                    controller: controller
                )
            }
        } catch is CADCaseDeadlineError {
            let pending = result(
                outcome: .timeout,
                routeEvidence: routeEvidence(capabilityObserved: false),
                telemetry: telemetry(
                    planningWallNanoseconds: elapsed(since: planningStart),
                    routeWallNanoseconds: elapsed(since: routeStart),
                    totalStart: totalStart,
                    capabilityRequestCount: 0,
                    readCount: 0,
                    cancellationCheckpointCount: 2
                ),
                diagnostics: [
                    "\(caseID.rawValue) production capability observation exceeded its shared deadline."
                ]
            )
            return await finalizeCleanup(
                pending,
                controller: controller,
                totalStart: totalStart
            )
        } catch is CancellationError {
            let pending = result(
                outcome: .cancellation,
                routeEvidence: routeEvidence(capabilityObserved: false),
                telemetry: telemetry(
                    planningWallNanoseconds: elapsed(since: planningStart),
                    routeWallNanoseconds: elapsed(since: routeStart),
                    totalStart: totalStart,
                    capabilityRequestCount: 0,
                    readCount: 0,
                    cancellationCheckpointCount: 2
                ),
                diagnostics: [
                    "\(caseID.rawValue) was cancelled during capability observation."
                ]
            )
            return await finalizeCleanup(
                pending,
                controller: controller,
                totalStart: totalStart
            )
        } catch {
            let pending = result(
                outcome: .infrastructureFailure,
                routeEvidence: routeEvidence(capabilityObserved: false),
                telemetry: telemetry(
                    planningWallNanoseconds: elapsed(since: planningStart),
                    routeWallNanoseconds: elapsed(since: routeStart),
                    totalStart: totalStart,
                    capabilityRequestCount: 0,
                    readCount: 0,
                    cancellationCheckpointCount: 2
                ),
                diagnostics: [
                    "\(caseID.rawValue) production capability observation failed: \(message(error))"
                ]
            )
            return await finalizeCleanup(
                pending,
                controller: controller,
                totalStart: totalStart
            )
        }

        let routeWall = elapsed(since: routeStart)
        let context = observation.candidateContext()
        if Task.isCancelled {
            let pending = result(
                outcome: .cancellation,
                capabilityError: observation.typedUnavailable,
                routeEvidence: routeEvidence(capabilityObserved: true),
                telemetry: telemetry(
                    planningWallNanoseconds: elapsed(since: planningStart),
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    capabilityRequestCount: observation.requestCount,
                    readCount: observation.requestCount,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: [
                    "\(caseID.rawValue) was cancelled before candidate decision."
                ]
            )
            return await finalizeCleanup(
                pending,
                controller: controller,
                totalStart: totalStart
            )
        }

        let decision: CADCandidateDecision
        do {
            decision = try await deadline.run {
                try await candidate.decide(for: context)
            }
        } catch is CADCaseDeadlineError {
            let pending = result(
                outcome: .timeout,
                capabilityError: observation.typedUnavailable,
                routeEvidence: routeEvidence(capabilityObserved: true),
                telemetry: telemetry(
                    planningWallNanoseconds: elapsed(since: planningStart),
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    capabilityRequestCount: observation.requestCount,
                    readCount: observation.requestCount,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: [
                    "\(caseID.rawValue) candidate planning exceeded its shared deadline."
                ]
            )
            return await finalizeCleanup(
                pending,
                controller: controller,
                totalStart: totalStart
            )
        } catch is CancellationError {
            let pending = result(
                outcome: .cancellation,
                capabilityError: observation.typedUnavailable,
                routeEvidence: routeEvidence(capabilityObserved: true),
                telemetry: telemetry(
                    planningWallNanoseconds: elapsed(since: planningStart),
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    capabilityRequestCount: observation.requestCount,
                    readCount: observation.requestCount,
                    cancellationCheckpointCount: 3
                ),
                diagnostics: [
                    "\(caseID.rawValue) was cancelled during candidate planning."
                ]
            )
            return await finalizeCleanup(
                pending,
                controller: controller,
                totalStart: totalStart
            )
        } catch {
            // Candidate failures are owned by the activated executor, which
            // converts them to its typed candidateFailure error. Do not turn
            // an arbitrary candidate error into an execution outcome here.
            throw error
        }

        if Task.isCancelled {
            let pending = result(
                outcome: .cancellation,
                candidateDecision: decision,
                capabilityError: observation.typedUnavailable,
                routeEvidence: routeEvidence(capabilityObserved: true),
                telemetry: telemetry(
                    planningWallNanoseconds: elapsed(since: planningStart),
                    routeWallNanoseconds: routeWall,
                    totalStart: totalStart,
                    capabilityRequestCount: observation.requestCount,
                    readCount: observation.requestCount,
                    cancellationCheckpointCount: 4
                ),
                diagnostics: [
                    "\(caseID.rawValue) was cancelled after candidate planning."
                ]
            )
            return await finalizeCleanup(
                pending,
                controller: controller,
                totalStart: totalStart
            )
        }

        let candidateOutcome = evaluate(
            decision: decision,
            challenge: entry.challenge,
            observation: observation
        )
        let pending = result(
            outcome: candidateOutcome.outcome,
            candidateDecision: decision,
            capabilityError: candidateOutcome.capabilityError,
            routeEvidence: routeEvidence(capabilityObserved: true),
            telemetry: telemetry(
                planningWallNanoseconds: elapsed(since: planningStart),
                routeWallNanoseconds: routeWall,
                totalStart: totalStart,
                capabilityRequestCount: observation.requestCount,
                readCount: observation.requestCount,
                cancellationCheckpointCount: 4
            ),
            diagnostics: candidateOutcome.diagnostics
        )
        return await finalizeCleanup(
            pending,
            controller: controller,
            totalStart: totalStart
        )
    }

    private func result(
        outcome: CADCaseOutcome,
        candidateDecision: CADCandidateDecision? = nil,
        capabilityError: CADSphereCapabilityObservationError? = nil,
        routeEvidence: CADSphereRouteEvidence,
        telemetry: CADSphereTelemetry,
        diagnostics: [String] = []
    ) -> CADSphereCaseResult {
        CADSphereCaseResult(
            recordedBy: recorder,
            caseID: caseID,
            outcome: outcome,
            candidateDecision: candidateDecision,
            capabilityError: capabilityError,
            routeEvidence: routeEvidence,
            telemetry: telemetry,
            diagnostics: diagnostics
        )
    }

    private func evaluate(
        decision: CADCandidateDecision,
        challenge: CADChallenge,
        observation: CADSphereCapabilityObservation
    ) -> (
        outcome: CADCaseOutcome,
        capabilityError: CADSphereCapabilityObservationError?,
        diagnostics: [String]
    ) {
        switch decision {
        case let .unsupported(declaration):
            do {
                try declaration.validate(
                    for: challenge,
                    capabilities: observation.snapshot
                )
                guard let unavailable = observation.typedUnavailable else {
                    return (
                        .unexpectedUnsupported,
                        nil,
                        [
                            "\(caseID.rawValue) declared unsupported while the observed capability was available."
                        ]
                    )
                }
                return (.expectedUnsupported, unavailable, [])
            } catch {
                return (
                    .invalidSubmission,
                    observation.typedUnavailable,
                    [
                        "\(caseID.rawValue) unsupported declaration was invalid: \(message(error))"
                    ]
                )
            }
        case .action:
            return (
                .invalidSubmission,
                observation.typedUnavailable,
                [
                    "\(caseID.rawValue) received an action even though no sphere Agent ingress exists."
                ]
            )
        case .finish:
            return (
                .invalidSubmission,
                observation.typedUnavailable,
                [
                    "\(caseID.rawValue) received a finish decision before a sphere capability became available."
                ]
            )
        }
    }

    private func finalizeCleanup(
        _ pending: CADSphereCaseResult,
        controller: ProjectAgentCommandController,
        totalStart: UInt64
    ) async -> CADSphereCaseResult {
        let cleanupStart = now()
        let remaining = await sessionCount(controller)
        let evidence = pending.routeEvidence.withCleanup(
            cleanupWallNanoseconds: elapsed(since: cleanupStart),
            remainingRegistrationCount: remaining
        )
        return pending.replacing(
            routeEvidence: evidence,
            telemetry: pending.telemetry.replacing(
                totalWallNanoseconds: elapsed(since: totalStart)
            )
        )
    }

    private func sessionCount(_ controller: ProjectAgentCommandController) async -> Int {
        guard case let .status(status) = await controller.handle(.status) else {
            return 1
        }
        return status.sessionCount
    }

    private func routeEvidence(capabilityObserved: Bool) -> CADSphereRouteEvidence {
        CADSphereRouteEvidence(
            capabilityObservedThroughController: capabilityObserved
        )
    }

    private func telemetry(
        planningWallNanoseconds: UInt64,
        routeWallNanoseconds: UInt64,
        totalStart: UInt64,
        capabilityRequestCount: Int,
        readCount: Int,
        cancellationCheckpointCount: Int
    ) -> CADSphereTelemetry {
        CADSphereTelemetry(
            planningWallNanoseconds: max(1, planningWallNanoseconds),
            routeWallNanoseconds: routeWallNanoseconds,
            oracleWallNanoseconds: 0,
            totalWallNanoseconds: max(1, elapsed(since: totalStart)),
            capabilityRequestCount: capabilityRequestCount,
            actionCount: 0,
            commandCount: 0,
            readCount: readCount,
            entityCount: 0,
            featureCount: 0,
            bodyCount: 0,
            publicationCount: 0,
            sourceMutationCount: 0,
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
}
