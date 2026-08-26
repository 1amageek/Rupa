import RupaCore

/// Adds request identity and enforces result invariants after provider execution.
public struct DefaultDomainCommandResultProjector: DomainCommandResultProjecting, Sendable {
    public init() {}

    public func project(
        resolution: DomainCommandPlanResolution,
        record: DomainCommandExecutionRecord,
        currentGeneration: DocumentGeneration,
        currentTransactionRevision: DocumentTransactionRevision
    ) throws -> DomainExecutionResult {
        let request = resolution.request
        let result = DomainExecutionResult(
            capabilityID: request.capabilityID,
            namespace: request.namespace,
            message: record.message ?? defaultMessage(for: request),
            baseGeneration: record.baseGeneration,
            generation: record.generation,
            proposedGeneration: record.proposedGeneration,
            baseTransactionRevision: record.baseTransactionRevision,
            transactionRevision: record.transactionRevision,
            proposedTransactionRevision: record.proposedTransactionRevision,
            didMutate: record.didMutate,
            wouldMutate: record.wouldMutate,
            dryRun: request.dryRun,
            diagnostics: record.diagnostics,
            validationFindings: record.validationFindings,
            validationRegions: record.validationRegions,
            automationResults: record.automationResults,
            sourceCommandResults: record.sourceCommandResults,
            commandName: record.commandName,
            payload: record.payload
        )
        try validate(
            result: result,
            resolution: resolution,
            currentGeneration: currentGeneration,
            currentTransactionRevision: currentTransactionRevision
        )
        return result
    }

    private func validate(
        result: DomainExecutionResult,
        resolution: DomainCommandPlanResolution,
        currentGeneration: DocumentGeneration,
        currentTransactionRevision: DocumentTransactionRevision
    ) throws {
        let request = resolution.request
        guard result.capabilityID == request.capabilityID,
              result.namespace == request.namespace,
              result.dryRun == request.dryRun else {
            throw EditorError(
                code: .commandFailed,
                message: "Domain execution returned an identity that does not match its request."
            )
        }
        guard result.generation == currentGeneration,
              result.transactionRevision == currentTransactionRevision else {
            throw EditorError(
                code: .commandFailed,
                message: "Domain execution returned inconsistent document revisions."
            )
        }
        if resolution.route.isReadOnly {
            guard !result.didMutate,
                  !result.wouldMutate,
                  result.proposedGeneration == result.baseGeneration,
                  result.proposedTransactionRevision == result.baseTransactionRevision else {
                let message = resolution.route == .query
                    ? "Query domain capabilities must not propose or commit document mutations."
                    : "Read-only domain capabilities must not propose or commit document mutations."
                throw EditorError(
                    code: .commandFailed,
                    message: message
                )
            }
        }
    }

    private func defaultMessage(for request: DomainCommandRequest) -> String {
        if request.dryRun {
            return "Domain capability \(request.capabilityID.rawValue) dry-run completed."
        }
        return "Domain capability \(request.capabilityID.rawValue) executed."
    }
}
