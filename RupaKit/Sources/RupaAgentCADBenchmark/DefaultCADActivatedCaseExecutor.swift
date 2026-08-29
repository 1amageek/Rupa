import Foundation
import RupaAgentRuntime

/// Executes one candidate against one reviewed benchmark case.
@MainActor
public struct DefaultCADActivatedCaseExecutor: CADActivatedCaseExecuting, Sendable {
    private static let activatedIDs =
        CADActivatedLineCase.allCases.map(\.caseID)
        + CADActivatedRectangleCase.allCases.map(\.caseID)
        + CADActivatedCircleCase.allCases.map(\.caseID)
        + CADActivatedAngleCase.allCases.map(\.caseID)
        + CADActivatedBoxCase.allCases.map(\.caseID)
        + CADActivatedCylinderCase.allCases.map(\.caseID)

    public init() {}

    public var activatedCaseIDs: [CADBenchmarkCaseID] {
        Self.activatedIDs
    }

    public func context(for caseID: CADBenchmarkCaseID) throws -> CADCandidateContext {
        let challenge = try challenge(for: caseID)
        let controller = ProjectAgentCommandController(name: caseID.rawValue)
        return CADActivatedCaseContextFactory.make(
            challenge: challenge,
            operationName: operationName(for: caseID),
            controller: controller
        )
    }

    public func evaluate(
        caseID: CADBenchmarkCaseID,
        candidate: any CADCandidateProtocol
    ) async throws -> CADCaseResult {
        let challenge = try challenge(for: caseID)
        let start = now()
        let capturingCandidate = CandidateFailureCapturing(candidate: candidate)

        do {
            if CADActivatedLineCase.allCases.contains(where: { $0.caseID == caseID }) {
                let activatedCase = try CADActivatedLineCase(caseID: caseID)
                let internalResult = try await CADLineCaseRunner(case: activatedCase)
                    .run(candidate: capturingCandidate)
                try internalResult.validate()
                return try publicResult(
                    caseID: caseID,
                    category: challenge.category,
                    outcome: internalResult.outcome,
                    durationMilliseconds: milliseconds(
                        from: internalResult.telemetry.totalWallNanoseconds
                    )
                )
            }

            if CADActivatedCircleCase.allCases.contains(where: { $0.caseID == caseID }) {
                let activatedCase = try CADActivatedCircleCase(caseID: caseID)
                let internalResult = try await CADCircleCaseRunner(case: activatedCase)
                    .run(candidate: capturingCandidate)
                try internalResult.validate()
                return try publicResult(
                    caseID: caseID,
                    category: challenge.category,
                    outcome: internalResult.outcome,
                    durationMilliseconds: milliseconds(
                        from: internalResult.telemetry.totalWallNanoseconds
                    )
                )
            }

            if CADActivatedAngleCase.allCases.contains(where: { $0.caseID == caseID }) {
                let activatedCase = try CADActivatedAngleCase(caseID: caseID)
                let internalResult = try await CADAngleCaseRunner(case: activatedCase)
                    .run(candidate: capturingCandidate)
                try internalResult.validate()
                return try publicResult(
                    caseID: caseID,
                    category: challenge.category,
                    outcome: internalResult.outcome,
                    durationMilliseconds: milliseconds(
                        from: internalResult.telemetry.totalWallNanoseconds
                    )
                )
            }

            if CADActivatedBoxCase.allCases.contains(where: { $0.caseID == caseID }) {
                let activatedCase = try CADActivatedBoxCase(caseID: caseID)
                let internalResult = try await CADBoxCaseRunner(case: activatedCase)
                    .run(candidate: capturingCandidate)
                try internalResult.validate()
                return try publicResult(
                    caseID: caseID,
                    category: challenge.category,
                    outcome: internalResult.outcome,
                    durationMilliseconds: milliseconds(
                        from: internalResult.telemetry.totalWallNanoseconds
                    )
                )
            }

            if CADActivatedCylinderCase.allCases.contains(where: { $0.caseID == caseID }) {
                let activatedCase = try CADActivatedCylinderCase(caseID: caseID)
                let internalResult = try await CADCylinderCaseRunner(case: activatedCase)
                    .run(candidate: capturingCandidate)
                try internalResult.validate()
                return try publicResult(
                    caseID: caseID,
                    category: challenge.category,
                    outcome: internalResult.outcome,
                    durationMilliseconds: milliseconds(
                        from: internalResult.telemetry.totalWallNanoseconds
                    )
                )
            }

            let activatedCase = try CADActivatedRectangleCase(caseID: caseID)
            let internalResult = try await CADRectangleCaseRunner(case: activatedCase)
                .run(candidate: capturingCandidate)
            try internalResult.validate()
            return try publicResult(
                caseID: caseID,
                category: challenge.category,
                outcome: internalResult.outcome,
                durationMilliseconds: milliseconds(
                    from: internalResult.telemetry.totalWallNanoseconds
                )
            )
        } catch is CandidateInvocationFailure {
            throw CADActivatedCaseExecutorError.candidateFailure(caseID)
        } catch is CancellationError {
            return try publicResult(
                caseID: caseID,
                category: challenge.category,
                outcome: .cancellation,
                durationMilliseconds: milliseconds(from: elapsed(since: start))
            )
        } catch let error as CADActivatedCaseExecutorError {
            throw error
        } catch {
            throw CADActivatedCaseExecutorError.invalidResult(caseID)
        }
    }

    private func challenge(for caseID: CADBenchmarkCaseID) throws -> CADChallenge {
        guard Self.activatedIDs.contains(caseID) else {
            throw CADActivatedCaseExecutorError.inactiveCase(caseID)
        }
        do {
            return try CADBenchmarkCatalog().challenge(for: caseID)
        } catch {
            throw CADActivatedCaseExecutorError.catalogFailure(caseID)
        }
    }

    private func operationName(for caseID: CADBenchmarkCaseID) -> String {
        if CADActivatedLineCase.allCases.contains(where: { $0.caseID == caseID }) {
            return "createLineSketch"
        }
        if CADActivatedCircleCase.allCases.contains(where: { $0.caseID == caseID }) {
            return "createCircleSketch"
        }
        if CADActivatedAngleCase.allCases.contains(where: { $0.caseID == caseID }) {
            return "createLineSketch"
        }
        if CADActivatedBoxCase.allCases.contains(where: { $0.caseID == caseID }) {
            return "createExtrudedRectangle"
        }
        if CADActivatedCylinderCase.allCases.contains(where: { $0.caseID == caseID }) {
            return "createExtrudedCircle"
        }
        return "createRectangleSketch"
    }

    private func publicResult(
        caseID: CADBenchmarkCaseID,
        category: CADBenchmarkCategory,
        outcome: CADCaseOutcome,
        durationMilliseconds: Double
    ) throws -> CADCaseResult {
        let result = CADCaseResult(
            id: caseID,
            category: category,
            outcome: outcome,
            durationMilliseconds: durationMilliseconds
        )
        do {
            try result.validate()
        } catch {
            throw CADActivatedCaseExecutorError.invalidResult(caseID)
        }
        return result
    }

    private func milliseconds(from nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000.0
    }

    private func now() -> UInt64 {
        UInt64((ProcessInfo.processInfo.systemUptime * 1_000_000_000).rounded())
    }

    private func elapsed(since start: UInt64) -> UInt64 {
        max(1, now() - start)
    }
}

private struct CandidateInvocationFailure: Error, Sendable {}

private struct CandidateFailureCapturing: CADCandidateProtocol {
    let candidate: any CADCandidateProtocol

    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        do {
            return try await candidate.decide(for: context)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CandidateInvocationFailure()
        }
    }
}
