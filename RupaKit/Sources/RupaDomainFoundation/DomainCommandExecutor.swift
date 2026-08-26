import RupaAutomation
import RupaCore
import RupaCoreTypes

public struct DomainCommandExecutor {
    private let planResolver: any DomainCommandPlanResolving
    private let resultProjector: any DomainCommandResultProjecting
    private let automationRunner: AutomationRunner

    public init(
        registry: DomainRegistry,
        automationRunner: AutomationRunner = AutomationRunner(),
        planResolver: (any DomainCommandPlanResolving)? = nil,
        resultProjector: any DomainCommandResultProjecting =
            DefaultDomainCommandResultProjector()
    ) {
        self.planResolver = planResolver ?? DefaultDomainCommandPlanResolver(registry: registry)
        self.resultProjector = resultProjector
        self.automationRunner = automationRunner
    }

    public func execute(
        _ request: DomainCommandRequest,
        in session: EditorSession
    ) throws -> DomainExecutionResult {
        try Task.checkCancellation()
        let resolution = try planResolver.resolve(request)
        let baseGeneration = session.generation
        let baseTransactionRevision = session.transactionRevision
        let record: DomainCommandExecutionRecord
        switch resolution.plan {
        case .automationBatch(let batch):
            record = try executeAutomationBatch(
                batch,
                resolution: resolution,
                in: session
            )
        case .documentTransaction(let transaction):
            record = try executeDocumentTransaction(
                transaction,
                resolution: resolution,
                in: session
            )
        case .query(let query):
            record = try executeQuery(
                query,
                resolution: resolution,
                in: session
            )
        }
        guard baseGeneration == record.baseGeneration,
              baseTransactionRevision == record.baseTransactionRevision else {
            throw EditorError(
                code: .commandFailed,
                message: "Domain execution returned a base revision that does not match the session."
            )
        }
        do {
            try Task.checkCancellation()
            return try resultProjector.project(
                resolution: resolution,
                record: record,
                currentGeneration: session.generation,
                currentTransactionRevision: session.transactionRevision
            )
        } catch {
            guard record.didMutate else {
                throw error
            }
            throw DomainCommandPostCommitError(
                record: record,
                finalContext: AutomationBatchFinalContext(session: session),
                message: "The domain mutation committed, but its result could not be projected: \(error)."
            )
        }
    }

    private func executeAutomationBatch(
        _ batch: AutomationBatch,
        resolution: DomainCommandPlanResolution,
        in session: EditorSession
    ) throws -> DomainCommandExecutionRecord {
        let effectiveBatch = AutomationBatch(
            commands: batch.commands,
            expectedGeneration: resolution.expectedGeneration,
            expectedTransactionRevision: resolution.expectedTransactionRevision,
            expectedWorkspaceRevision: batch.expectedWorkspaceRevision
        )
        let execution = try automationRunner.executeBatchTransaction(
            effectiveBatch,
            in: session,
            commits: !resolution.request.dryRun
        )
        return DomainCommandExecutionRecord(
            baseGeneration: execution.baseGeneration,
            generation: resolution.request.dryRun
                ? execution.baseGeneration
                : execution.proposedGeneration,
            proposedGeneration: execution.proposedGeneration,
            baseTransactionRevision: execution.baseTransactionRevision,
            transactionRevision: resolution.request.dryRun
                ? execution.baseTransactionRevision
                : execution.proposedTransactionRevision,
            proposedTransactionRevision: execution.proposedTransactionRevision,
            didMutate: execution.didCommit && execution.results.contains { $0.didMutate },
            wouldMutate: execution.results.contains { $0.didMutate },
            diagnostics: execution.diagnostics,
            automationResults: execution.results
        )
    }

    private func executeDocumentTransaction(
        _ transaction: DomainDocumentTransaction,
        resolution: DomainCommandPlanResolution,
        in session: EditorSession
    ) throws -> DomainCommandExecutionRecord {
        let expectedGeneration = resolution.expectedGeneration
        let expectedTransactionRevision = resolution.expectedTransactionRevision
        try session.store.requireGeneration(expectedGeneration)
        try session.requireTransactionRevision(expectedTransactionRevision)
        let expectedProposedGeneration = try transaction.proposedGeneration(
            from: session.generation
        )
        let execution = try session.executeIsolatedSourceTransaction(
            commandName: transaction.name,
            commits: !resolution.request.dryRun,
            expectedTransactionRevision: expectedTransactionRevision
        ) { stagedSession in
            let sourceCommandResults = try stagedSession.withSourceCommandGroup(
                named: transaction.name
            ) { groupedSession in
                var sourceCommandResults: [CommandExecutionResult] = []
                for command in transaction.sourceCommands {
                    try Task.checkCancellation()
                    sourceCommandResults.append(try groupedSession.execute(command))
                }
                try Task.checkCancellation()
                _ = try groupedSession.execute(
                    .applyNamespacedSemanticExtensionMutations(
                        namespace: resolution.request.namespace,
                        mutations: transaction.semanticMutations
                    )
                )
                guard groupedSession.generation == expectedProposedGeneration else {
                    throw EditorError(
                        code: .commandFailed,
                        message: "Domain transaction generation did not match its validated mutation plan."
                    )
                }
                return sourceCommandResults
            }
            return StagedDocumentTransactionResult(
                sourceCommandResults: sourceCommandResults,
                diagnostics: EditorDiagnostic.stableMerged([
                    sourceCommandResults.flatMap(\.diagnostics),
                    stagedSession.diagnostics,
                    stagedSession.evaluationSnapshot.diagnostics,
                ])
            )
        }
        return DomainCommandExecutionRecord(
            baseGeneration: execution.baseGeneration,
            generation: resolution.request.dryRun
                ? execution.baseGeneration
                : execution.proposedGeneration,
            proposedGeneration: execution.proposedGeneration,
            baseTransactionRevision: execution.baseTransactionRevision,
            transactionRevision: resolution.request.dryRun
                ? execution.baseTransactionRevision
                : execution.proposedTransactionRevision,
            proposedTransactionRevision: execution.proposedTransactionRevision,
            didMutate: execution.didCommit,
            wouldMutate: execution.proposedGeneration != execution.baseGeneration,
            diagnostics: execution.value.diagnostics,
            sourceCommandResults: execution.value.sourceCommandResults,
            commandName: transaction.name,
            payload: transaction.resultPayload
        )
    }

    private func executeQuery(
        _ query: any DomainCommandQuery,
        resolution: DomainCommandPlanResolution,
        in session: EditorSession
    ) throws -> DomainCommandExecutionRecord {
        try session.store.requireGeneration(resolution.expectedGeneration)
        try session.requireTransactionRevision(resolution.expectedTransactionRevision)
        let generation = session.generation
        let transactionRevision = session.transactionRevision
        try Task.checkCancellation()
        let queryResult = try query.execute(
            resolution.request,
            in: DomainQueryContext(
                document: session.document,
                generation: generation,
                objectRegistry: session.objectRegistry,
                currentEvaluation: session.currentEvaluation,
                evaluationSnapshot: session.evaluationSnapshot
            )
        )
        try queryResult.validate()
        try Task.checkCancellation()
        return DomainCommandExecutionRecord(
            message: queryResult.message,
            baseGeneration: generation,
            generation: generation,
            proposedGeneration: generation,
            baseTransactionRevision: transactionRevision,
            transactionRevision: transactionRevision,
            proposedTransactionRevision: transactionRevision,
            didMutate: false,
            wouldMutate: false,
            diagnostics: queryResult.diagnostics,
            validationFindings: queryResult.validationFindings,
            validationRegions: queryResult.validationRegions,
            payload: queryResult.payload
        )
    }

    private struct StagedDocumentTransactionResult {
        var sourceCommandResults: [CommandExecutionResult]
        var diagnostics: [EditorDiagnostic]
    }
}
