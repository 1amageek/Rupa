import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaProject

/// Plans explicit project mutations from one immutable published view.
public struct DefaultProjectWorkspaceActionPlanner: ProjectWorkspaceActionPlanning, Sendable {
    private let commandContextResolver: any EditorCommandContextResolving
    private let automationBatchPlanner: any AutomationBatchPlanning

    public init(
        commandContextResolver: any EditorCommandContextResolving =
            DefaultEditorCommandContextResolver(),
        automationBatchPlanner: (any AutomationBatchPlanning)? = nil
    ) {
        self.commandContextResolver = commandContextResolver
        self.automationBatchPlanner = automationBatchPlanner
            ?? DefaultAutomationBatchPlanner(
                commandContextResolver: commandContextResolver
            )
    }

    public func source(
        name: String,
        commands: [EditorCommand] = [],
        geometrySourceCommands: [GeometrySourceCommand] = [],
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectWorkspaceAction {
        let context = EditorCommandPlanningContext(
            document: snapshot.document.document,
            selection: snapshot.selection,
            objectRegistry: snapshot.objectRegistry,
            evaluationSnapshot: snapshot.evaluationSnapshot
        )
        let resolvedCommands = try commands.map { command in
            try ContextResolvedEditorCommand(
                resolving: command,
                in: context,
                using: commandContextResolver
            )
        }
        return .source(
            try ProjectSourceTransaction(
                name: name,
                resolvedCommands: resolvedCommands,
                geometrySourceCommands: geometrySourceCommands,
                expectedProjectID: snapshot.projectID,
                expectedTransactionRevision: snapshot.transactionRevision,
                expectedPublicationSequence: snapshot.publicationSequence
            )
        )
    }

    public func interaction(
        selection: ProjectSelectionOperation? = nil,
        workspaceCommands: [WorkspaceCommand] = [],
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectWorkspaceAction {
        .interaction(
            try ProjectInteractionTransaction(
                selection: selection,
                workspaceCommands: workspaceCommands,
                expectedProjectID: snapshot.projectID,
                expectedTransactionRevision: snapshot.transactionRevision,
                expectedPublicationSequence: snapshot.publicationSequence
            )
        )
    }

    public func automation(
        _ batch: AutomationBatch,
        from snapshot: ProjectViewSnapshot
    ) throws -> ProjectWorkspaceAction {
        let prepared = try automationBatchPlanner.prepare(
            batch,
            in: AutomationPlanningContext(
                document: snapshot.document.document,
                generation: snapshot.documentGeneration,
                transactionRevision: snapshot.transactionRevision,
                publicationSequence: snapshot.publicationSequence,
                selection: snapshot.selection,
                workspaceState: snapshot.workspaceState,
                objectRegistry: snapshot.objectRegistry,
                evaluationSnapshot: snapshot.evaluationSnapshot,
                currentEvaluation: snapshot.cadInteraction
            )
        )
        switch prepared.effect {
        case .sourceMutation:
            return .source(
                try ProjectSourceTransaction(
                    name: "automationBatch.source",
                    automation: prepared,
                    expectedProjectID: snapshot.projectID,
                    expectedTransactionRevision: snapshot.transactionRevision,
                    expectedPublicationSequence: snapshot.publicationSequence
                )
            )
        case .workspaceMutation:
            return .interaction(
                try ProjectInteractionTransaction(
                    automation: prepared,
                    expectedProjectID: snapshot.projectID,
                    expectedTransactionRevision: snapshot.transactionRevision,
                    expectedPublicationSequence: snapshot.publicationSequence
                )
            )
        case .readOnly:
            throw ProjectWorkspaceActionError(
                code: .readRouteRequired,
                message: "Read-only Automation batches require the immutable read route."
            )
        }
    }
}
