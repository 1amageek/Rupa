import RupaCore
import RupaCoreTypes

/// Validates one Automation batch against a single immutable project snapshot.
public struct DefaultAutomationBatchPlanner: AutomationBatchPlanning, Sendable {
    private let commandContextResolver: any EditorCommandContextResolving

    public init(
        commandContextResolver: any EditorCommandContextResolving =
            DefaultEditorCommandContextResolver()
    ) {
        self.commandContextResolver = commandContextResolver
    }

    public func prepare(
        _ batch: AutomationBatch,
        in context: AutomationPlanningContext
    ) throws -> PreparedAutomationBatch {
        try validateInitialContext(context)
        try requireGeneration(batch.expectedGeneration, in: context)
        try requireTransactionRevision(
            batch.expectedTransactionRevision,
            in: context
        )
        try requireWorkspaceRevision(batch.expectedWorkspaceRevision, in: context)

        var preparedBatch = batch
        preparedBatch.commands = try batch.commands.map { command in
            try commandResolvingInitialContext(command, in: context)
        }
        preparedBatch.expectedGeneration = context.generation
        preparedBatch.expectedTransactionRevision = context.transactionRevision
        preparedBatch.expectedWorkspaceRevision = context.workspaceState.revision
        return PreparedAutomationBatch(
            batch: preparedBatch,
            effect: try preparedBatch.validatedEffect()
        )
    }

    private func validateInitialContext(
        _ context: AutomationPlanningContext
    ) throws {
        var prunedSelection = context.selection
        prunedSelection.pruneMissingReferences(in: context.document)
        guard prunedSelection == context.selection else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Automation planning selection contains a reference that is not present in the planning document."
            )
        }

        try context.workspaceState.validate(against: context.document)

        if let evaluatedGeneration = context.evaluationSnapshot.evaluatedGeneration {
            guard evaluatedGeneration == context.generation else {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "Automation planning evaluation snapshot does not match the planning generation."
                )
            }
        }

        if let currentEvaluation = context.currentEvaluation {
            guard currentEvaluation.matches(
                document: context.document,
                generation: context.generation
            ) else {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "Automation planning evaluation context does not match the planning document or generation."
                )
            }
        }
    }

    private func commandResolvingInitialContext(
        _ command: AutomationCommand,
        in context: AutomationPlanningContext
    ) throws -> AutomationCommand {
        guard case .offsetCurve(
            let target,
            let distance,
            let options,
            let vertexHandle
        ) = command else {
            return command
        }
        let editorContext = EditorCommandPlanningContext(
            document: context.document,
            selection: context.selection,
            objectRegistry: context.objectRegistry,
            evaluationSnapshot: context.evaluationSnapshot
        )
        let resolved = try ContextResolvedEditorCommand(
            resolving: .offsetCurve(
                target: target,
                distance: distance,
                options: options,
                vertexHandle: vertexHandle
            ),
            in: editorContext,
            using: commandContextResolver
        ).command
        guard case .offsetCurve(
            let resolvedTarget,
            let resolvedDistance,
            let resolvedOptions,
            let resolvedVertexHandle
        ) = resolved else {
            throw EditorError(
                code: .commandFailed,
                message: "Offset Curve context resolution returned a different command."
            )
        }
        return .offsetCurve(
            target: resolvedTarget,
            distance: resolvedDistance,
            options: resolvedOptions,
            vertexHandle: resolvedVertexHandle
        )
    }

    private func requireGeneration(
        _ expected: DocumentGeneration?,
        in context: AutomationPlanningContext
    ) throws {
        guard let expected, expected != context.generation else {
            return
        }
        throw EditorError(
            code: .documentGenerationMismatch,
            message: "Expected generation \(expected.value), but current generation is \(context.generation.value)."
        )
    }

    private func requireTransactionRevision(
        _ expected: DocumentTransactionRevision?,
        in context: AutomationPlanningContext
    ) throws {
        guard let expected, expected != context.transactionRevision else {
            return
        }
        throw EditorError(
            code: .documentTransactionRevisionMismatch,
            message: "Expected transaction revision \(expected.value), but current transaction revision is \(context.transactionRevision.value)."
        )
    }

    private func requireWorkspaceRevision(
        _ expected: WorkspaceRevision?,
        in context: AutomationPlanningContext
    ) throws {
        guard let expected, expected != context.workspaceState.revision else {
            return
        }
        throw EditorError(
            code: .workspaceRevisionMismatch,
            message: "Expected workspace revision \(expected.value), but current revision is \(context.workspaceState.revision.value)."
        )
    }
}
