@MainActor
struct CADBenchmarkReferenceRunner {
    typealias ExecutionOverride = @MainActor @Sendable (
        CADBenchmarkCaseID,
        any CADCandidateProtocol
    ) async throws -> CADActivatedCaseExecution

    private let executor: DefaultCADActivatedCaseExecutor
    private let activatedCaseIDs: [CADBenchmarkCaseID]
    private let executionOverride: ExecutionOverride?

    init(
        executor: DefaultCADActivatedCaseExecutor = DefaultCADActivatedCaseExecutor(),
        activatedCaseIDs: [CADBenchmarkCaseID]? = nil,
        executionOverride: ExecutionOverride? = nil
    ) {
        self.executor = executor
        self.activatedCaseIDs = activatedCaseIDs ?? executor.activatedCaseIDs
        self.executionOverride = executionOverride
    }

    func runSerial() async throws -> CADBenchmarkReferenceRunAttempt {
        let manifest = try validatedManifest()
        var executions: [CADActivatedCaseExecution] = []
        executions.reserveCapacity(manifest.orderedCaseIDs.count)

        for caseID in manifest.orderedCaseIDs {
            try Task.checkCancellation()
            executions.append(try await executeReference(caseID: caseID))
        }
        return try CADBenchmarkReferenceRunAttempt(
            manifest: manifest,
            executions: executions
        )
    }

    func validatedManifest() throws -> CADBenchmarkManifest {
        let manifest = try CADBenchmarkCatalog().manifest
        try validateActivation(against: manifest)
        return manifest
    }

    func executeReference(
        caseID: CADBenchmarkCaseID
    ) async throws -> CADActivatedCaseExecution {
        let requestContext = try executor.context(for: caseID)
        let candidate = try CADReferenceCandidateFactory.candidate(for: requestContext)
        let execution: CADActivatedCaseExecution
        if let executionOverride {
            execution = try await executionOverride(caseID, candidate)
        } else {
            execution = try await executor.executeDetailed(
                caseID: caseID,
                candidate: candidate
            )
        }
        guard execution.publicResult.id == caseID,
              execution.context == requestContext else {
            throw CADBenchmarkReferenceRunError.invalidEvidence(caseID)
        }
        try execution.validate()
        return execution
    }

    private func validateActivation(against manifest: CADBenchmarkManifest) throws {
        guard activatedCaseIDs.count == manifest.orderedCaseIDs.count else {
            throw CADBenchmarkReferenceRunError.incompleteRun(
                expected: manifest.orderedCaseIDs.count,
                actual: activatedCaseIDs.count
            )
        }
        var identities = Set<CADBenchmarkCaseID>()
        for caseID in activatedCaseIDs {
            guard identities.insert(caseID).inserted else {
                throw CADBenchmarkReferenceRunError.duplicateCase(caseID)
            }
        }
        let manifestIdentities = Set(manifest.orderedCaseIDs)
        if let missing = manifest.orderedCaseIDs.first(where: { !identities.contains($0) }) {
            throw CADBenchmarkReferenceRunError.missingCase(missing)
        }
        guard identities == manifestIdentities else {
            throw CADBenchmarkReferenceRunError.activationMismatch
        }
    }
}
