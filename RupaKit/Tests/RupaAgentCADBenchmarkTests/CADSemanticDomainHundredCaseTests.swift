import Testing

@testable import RupaAgentCADBenchmark

/// Replays the complete reviewed catalog through the semantic production executor.
@MainActor
@Test(.timeLimit(.minutes(5)))
func semanticDomainExecutesTheFixedHundredCasesThroughProductionAuthority() async throws {
    let catalog = try CADBenchmarkCatalog()
    let executor = DefaultCADActivatedCaseExecutor()
    #expect(catalog.caseIDs.count == 100)
    #expect(executor.activatedCaseIDs.count == 100)

    var failures: [String] = []
    for caseID in catalog.caseIDs {
        do {
            let context = try executor.context(for: caseID)
            let candidate = try CADReferenceCandidateFactory.candidate(for: context)
            let result = try await executor.evaluate(
                caseID: caseID,
                candidate: candidate
            )
            try result.validate()
            guard result.outcome == .realized else {
                throw HundredCaseReplayError.unrealized(result.outcome)
            }
        } catch {
            failures.append("\(caseID.rawValue): \(error)")
        }
    }

    #expect(
        failures.isEmpty,
        Comment(rawValue: failures.joined(separator: "\n"))
    )
}

private enum HundredCaseReplayError: Error, CustomStringConvertible {
    case unrealized(CADCaseOutcome)

    var description: String {
        switch self {
        case .unrealized(let outcome):
            "A catalog case returned \(outcome) instead of realized."
        }
    }
}
