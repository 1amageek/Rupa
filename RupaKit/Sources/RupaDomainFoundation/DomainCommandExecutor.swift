import RupaAutomation
import RupaCore
import RupaCoreTypes

public struct DomainCommandExecutor {
    private let registry: DomainRegistry
    private let automationRunner: AutomationRunner

    public init(
        registry: DomainRegistry,
        automationRunner: AutomationRunner = AutomationRunner()
    ) {
        self.registry = registry
        self.automationRunner = automationRunner
    }

    public func execute(
        _ request: DomainCommandRequest,
        in session: EditorSession
    ) throws -> DomainExecutionResult {
        let descriptor = try descriptor(for: request)
        try validateDryRunSupport(request: request, descriptor: descriptor)
        let plan = try registry.lower(request)
        try validate(plan: plan, for: descriptor)
        let baseGeneration = session.generation
        let result: DomainExecutionResult
        switch plan {
        case .automationBatch(let batch):
            result = try executeAutomationBatch(
                batch,
                request: request,
                in: session
            )
        case .documentTransaction(let transaction):
            result = try executeDocumentTransaction(
                transaction,
                request: request,
                in: session
            )
        case .query(let query):
            result = try executeQuery(
                query,
                request: request,
                in: session
            )
        }
        try validate(
            result: result,
            request: request,
            descriptor: descriptor,
            baseGeneration: baseGeneration,
            currentGeneration: session.generation
        )
        return result
    }

    private func descriptor(for request: DomainCommandRequest) throws -> DomainCapabilityDescriptor {
        guard let descriptor = registry.capabilityDescriptor(for: request.capabilityID) else {
            throw DomainRegistryError(
                code: .missingCapability,
                message: "No domain capability is registered for \(request.capabilityID.rawValue)."
            )
        }
        guard descriptor.namespace == request.namespace else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain command request namespace does not match the capability namespace."
            )
        }
        return descriptor
    }

    private func validateDryRunSupport(
        request: DomainCommandRequest,
        descriptor: DomainCapabilityDescriptor
    ) throws {
        guard !request.dryRun || descriptor.supportsDryRun else {
            throw EditorError(
                code: .commandInvalid,
                message: "Domain capability \(request.capabilityID.rawValue) does not support dry-run execution."
            )
        }
    }

    private func validate(
        plan: DomainCommandPlan,
        for descriptor: DomainCapabilityDescriptor
    ) throws {
        let isCompatible: Bool
        switch (descriptor.effect, plan) {
        case (.query, .query),
             (.documentMutation, .automationBatch),
             (.documentMutation, .documentTransaction):
            isCompatible = true
        default:
            isCompatible = false
        }
        guard isCompatible else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain capability effect is incompatible with its lowered execution plan."
            )
        }
    }

    private func validate(
        result: DomainExecutionResult,
        request: DomainCommandRequest,
        descriptor: DomainCapabilityDescriptor,
        baseGeneration: DocumentGeneration,
        currentGeneration: DocumentGeneration
    ) throws {
        guard result.capabilityID == request.capabilityID,
              result.namespace == request.namespace,
              result.dryRun == request.dryRun else {
            throw EditorError(
                code: .commandFailed,
                message: "Domain execution returned an identity that does not match its request."
            )
        }
        guard result.baseGeneration == baseGeneration,
              result.generation == currentGeneration else {
            throw EditorError(
                code: .commandFailed,
                message: "Domain execution returned inconsistent document generations."
            )
        }
        if descriptor.effect == .query {
            guard !result.didMutate,
                  !result.wouldMutate,
                  result.proposedGeneration == baseGeneration else {
                throw EditorError(
                    code: .commandFailed,
                    message: "Query domain capabilities must not propose or commit document mutations."
                )
            }
        }
    }

    private func executeAutomationBatch(
        _ batch: AutomationBatch,
        request: DomainCommandRequest,
        in session: EditorSession
    ) throws -> DomainExecutionResult {
        let effectiveBatch = try batchApplyingExpectedGeneration(
            batch,
            requestExpectedGeneration: request.expectedGeneration
        )
        let execution = try automationRunner.executeBatchTransaction(
            effectiveBatch,
            in: session,
            commits: !request.dryRun
        )
        return DomainExecutionResult(
            capabilityID: request.capabilityID,
            namespace: request.namespace,
            message: message(for: request),
            baseGeneration: execution.baseGeneration,
            generation: request.dryRun ? execution.baseGeneration : execution.proposedGeneration,
            proposedGeneration: execution.proposedGeneration,
            didMutate: execution.didCommit && execution.results.contains { $0.didMutate },
            wouldMutate: execution.results.contains { $0.didMutate },
            dryRun: request.dryRun,
            diagnostics: execution.results.flatMap(\.diagnostics),
            automationResults: execution.results
        )
    }

    private func executeDocumentTransaction(
        _ transaction: DomainDocumentTransaction,
        request: DomainCommandRequest,
        in session: EditorSession
    ) throws -> DomainExecutionResult {
        try transaction.validate()
        let effectiveExpectedGeneration = try mergedExpectedGeneration(
            planExpectedGeneration: transaction.expectedGeneration,
            requestExpectedGeneration: request.expectedGeneration
        )
        try session.store.requireGeneration(effectiveExpectedGeneration)
        let expectedProposedGeneration = try proposedGeneration(
            from: session.generation,
            mutationCount: transaction.sourceCommands.count + 1
        )
        let execution = try session.executeIsolatedSourceTransaction(
            commandName: transaction.name,
            commits: !request.dryRun
        ) { stagedSession in
            var sourceCommandResults: [CommandExecutionResult] = []
            for command in transaction.sourceCommands {
                sourceCommandResults.append(try stagedSession.execute(command))
            }
            let semanticMutations = try transaction.semanticMutations.map { mutation in
                try canonicalSemanticMutation(
                    mutation,
                    namespace: request.namespace,
                    generation: expectedProposedGeneration,
                    in: stagedSession
                )
            }
            _ = try stagedSession.execute(
                .applySemanticExtensionMutations(semanticMutations)
            )
            guard stagedSession.generation == expectedProposedGeneration else {
                throw EditorError(
                    code: .commandFailed,
                    message: "Domain transaction generation did not match its validated mutation plan."
                )
            }
            guard case .valid = stagedSession.evaluationStatus else {
                throw EditorError(
                    code: .commandFailed,
                    message: "Domain transaction did not produce a valid evaluated document."
                )
            }
            return StagedDocumentTransactionResult(
                sourceCommandResults: sourceCommandResults,
                diagnostics: stagedSession.diagnostics
            )
        }
        return DomainExecutionResult(
            capabilityID: request.capabilityID,
            namespace: request.namespace,
            message: message(for: request),
            baseGeneration: execution.baseGeneration,
            generation: request.dryRun ? execution.baseGeneration : execution.proposedGeneration,
            proposedGeneration: execution.proposedGeneration,
            didMutate: execution.didCommit,
            wouldMutate: execution.proposedGeneration != execution.baseGeneration,
            dryRun: request.dryRun,
            diagnostics: execution.value.diagnostics,
            sourceCommandResults: execution.value.sourceCommandResults,
            commandName: transaction.name,
            payload: transaction.resultPayload
        )
    }

    private func executeQuery(
        _ query: any DomainCommandQuery,
        request: DomainCommandRequest,
        in session: EditorSession
    ) throws -> DomainExecutionResult {
        try session.store.requireGeneration(request.expectedGeneration)
        let generation = session.generation
        let queryResult = try query.execute(
            request,
            in: DomainQueryContext(
                document: session.document,
                generation: generation,
                objectRegistry: session.objectRegistry,
                currentEvaluation: session.currentEvaluation,
                evaluationSnapshot: session.evaluationSnapshot
            )
        )
        try queryResult.validate()
        return DomainExecutionResult(
            capabilityID: request.capabilityID,
            namespace: request.namespace,
            message: queryResult.message,
            baseGeneration: generation,
            generation: generation,
            proposedGeneration: generation,
            didMutate: false,
            wouldMutate: false,
            dryRun: request.dryRun,
            diagnostics: queryResult.diagnostics,
            validationFindings: queryResult.validationFindings,
            validationRegions: queryResult.validationRegions,
            payload: queryResult.payload
        )
    }

    private func canonicalSemanticMutation(
        _ mutation: SemanticExtensionMutation,
        namespace: SemanticNamespaceID,
        generation: DocumentGeneration,
        in session: EditorSession
    ) throws -> SemanticExtensionMutation {
        switch mutation {
        case .upsert(var envelope):
            guard envelope.namespace == namespace else {
                throw crossNamespaceMutationError()
            }
            for index in envelope.projection.semanticEntities.indices {
                let semanticEntityID = envelope.projection.semanticEntities[index].id
                envelope.projection.semanticEntities[index].dependencyIdentity = envelope.projection
                    .hasSourceBoundReferences(for: semanticEntityID)
                    ? try ProjectionDependencyIdentityBuilder().identity(
                        for: semanticEntityID,
                        in: envelope,
                        document: session.document,
                        generation: generation
                    )
                    : nil
            }
            return .upsert(envelope)
        case .remove(let extensionID):
            guard let envelope = session.document.productMetadata.semanticExtensions[extensionID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Semantic extension \(extensionID.rawValue.uuidString) does not exist."
                )
            }
            guard envelope.namespace == namespace else {
                throw crossNamespaceMutationError()
            }
            return mutation
        }
    }

    private func crossNamespaceMutationError() -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Domain transactions cannot mutate another semantic namespace."
        )
    }

    private func proposedGeneration(
        from baseGeneration: DocumentGeneration,
        mutationCount: Int
    ) throws -> DocumentGeneration {
        var generation = baseGeneration
        for _ in 0..<mutationCount {
            generation = try generation.advanced()
        }
        return generation
    }

    private func batchApplyingExpectedGeneration(
        _ batch: AutomationBatch,
        requestExpectedGeneration: DocumentGeneration?
    ) throws -> AutomationBatch {
        let expectedGeneration = try mergedExpectedGeneration(
            planExpectedGeneration: batch.expectedGeneration,
            requestExpectedGeneration: requestExpectedGeneration
        )
        return AutomationBatch(
            commands: batch.commands,
            expectedGeneration: expectedGeneration,
            expectedWorkspaceRevision: batch.expectedWorkspaceRevision
        )
    }

    private func mergedExpectedGeneration(
        planExpectedGeneration: DocumentGeneration?,
        requestExpectedGeneration: DocumentGeneration?
    ) throws -> DocumentGeneration? {
        if let planExpectedGeneration,
           let requestExpectedGeneration,
           planExpectedGeneration != requestExpectedGeneration {
            throw EditorError(
                code: .commandInvalid,
                message: "Domain command lowering returned an expected generation that conflicts with the request."
            )
        }
        return planExpectedGeneration ?? requestExpectedGeneration
    }

    private func message(for request: DomainCommandRequest) -> String {
        if request.dryRun {
            return "Domain capability \(request.capabilityID.rawValue) dry-run completed."
        }
        return "Domain capability \(request.capabilityID.rawValue) executed."
    }

    private struct StagedDocumentTransactionResult {
        var sourceCommandResults: [CommandExecutionResult]
        var diagnostics: [EditorDiagnostic]
    }
}
