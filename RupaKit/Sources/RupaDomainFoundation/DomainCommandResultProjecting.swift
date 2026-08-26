import RupaCore

public protocol DomainCommandResultProjecting: Sendable {
    func project(
        resolution: DomainCommandPlanResolution,
        record: DomainCommandExecutionRecord,
        currentGeneration: DocumentGeneration,
        currentTransactionRevision: DocumentTransactionRevision
    ) throws -> DomainExecutionResult
}
