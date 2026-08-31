import Foundation
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaProjectAccess
import Testing
@testable import RupaCLIKit

@Test
func projectAccessErrorsMapToStableCLIExitCategories() {
    let input = URL(fileURLWithPath: "/tmp/input.rupa")
    let other = URL(fileURLWithPath: "/tmp/input.txt")
    let expectedSessionID = UUID()
    let actualSessionID = UUID()
    let outcome = AgentCommittedMutationOutcome(
        stage: .viewProjection,
        mutation: .source,
        requestMethod: "command.apply",
        projectID: ProjectID(rawValue: "project.exit-code"),
        documentGeneration: DocumentGeneration(3),
        transactionRevision: DocumentTransactionRevision(3),
        publicationSequence: 3,
        workspaceRevision: WorkspaceRevision(3),
        message: "Committed."
    )

    let cases: [(ProjectAccessError, CLIExitCode)] = [
        (.invalidTarget(input), .usage),
        (.unsupportedProjectFormat(other), .usage),
        (.sessionMismatch(expected: expectedSessionID, actual: actualSessionID), .data),
        (.outcomeUnknown(requestID: UUID()), .data),
        (.committedMutation(outcome), .data),
        (.saveUnavailable, .inputOutput),
        (.sessionUnavailable(expectedSessionID), .unavailable),
        (.deadlineExceeded, .unavailable),
        (.authorityUnavailable, .unavailable),
        (.finished, .software),
    ]

    for (error, expectedExitCode) in cases {
        #expect(CLIExitCode.value(for: error) == expectedExitCode)
    }
    #expect(
        CLIExitCode.value(for: CLICommittedMutationError(outcome: outcome)) == .data
    )
}
