import Testing
import RupaAgentCADBenchmark
import RupaAgentCADBenchmarkJSONAdapter
@testable import RupaAgentCADBenchmarkCLI

struct CADBenchmarkCLIExitCodeTests {
    @Test
    func adapterFailuresUseStableUsageOrSoftwareExitCodes() {
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.malformedJSON) == .usage)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.oversizedInput) == .usage)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.caseMismatch) == .usage)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.fingerprintMismatch) == .usage)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.invalidDecision) == .usage)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.candidateFailure) == .software)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.oracleFailure) == .software)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.infrastructureFailure) == .software)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.outputOverflow) == .software)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.timeout) == .nonRealized)
        #expect(CADBenchmarkCLIExitCode.value(for: CADJSONErrorCode.cancellation) == .nonRealized)
    }

    @Test
    func resultOutcomesUseStableExitCodes() {
        #expect(
            CADBenchmarkCLIExitCode.value(
                for: CADCaseResult(id: "LIN-001", category: .line, outcome: .realized)
            ) == .success
        )
        #expect(
            CADBenchmarkCLIExitCode.value(
                for: CADCaseResult(id: "LIN-001", category: .line, outcome: .invalidSubmission)
            ) == .nonRealized
        )
        #expect(
            CADBenchmarkCLIExitCode.value(
                for: CADCaseResult(id: "LIN-001", category: .line, outcome: .expectedUnsupported)
            ) == .nonRealized
        )
        #expect(
            CADBenchmarkCLIExitCode.value(
                for: CADCaseResult(id: "LIN-001", category: .line, outcome: .timeout)
            ) == .nonRealized
        )
        #expect(
            CADBenchmarkCLIExitCode.value(
                for: CADCaseResult(id: "LIN-001", category: .line, outcome: .cancellation)
            ) == .nonRealized
        )
        #expect(
            CADBenchmarkCLIExitCode.value(
                for: CADCaseResult(id: "LIN-001", category: .line, outcome: .executionFailure)
            ) == .software
        )
        #expect(
            CADBenchmarkCLIExitCode.value(
                for: CADCaseResult(id: "LIN-001", category: .line, outcome: .oracleFailure)
            ) == .software
        )
        #expect(
            CADBenchmarkCLIExitCode.value(
                for: CADCaseResult(id: "LIN-001", category: .line, outcome: .infrastructureFailure)
            ) == .software
        )
    }
}
