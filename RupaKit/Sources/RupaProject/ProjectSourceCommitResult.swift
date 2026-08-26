import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectPackage

public struct ProjectSourceCommitResult: Sendable {
    public let baseTransactionRevision: DocumentTransactionRevision
    public let state: ProjectStateSnapshot
    public let commandResults: [CommandExecutionResult]
    public let geometrySourceCommandResults: [GeometrySourceCommandResult]
    public let automationExecution: AutomationBatchExecution?

    public var transactionRevision: DocumentTransactionRevision {
        state.transactionRevision
    }

    public var documentGeneration: DocumentGeneration {
        state.documentGeneration
    }

    public var document: DesignDocument {
        state.document
    }

    public var package: ProjectPackageDocument {
        state.package
    }

    public var evaluation: EvaluatedProjectSnapshot {
        state.evaluation
    }

    /// Command diagnostics followed by diagnostics from the exact committed state.
    public var diagnostics: [EditorDiagnostic] {
        EditorDiagnostic.stableMerged([
            commandResults.flatMap(\.diagnostics),
            automationExecution?.diagnostics ?? [],
            state.evaluationSnapshot.diagnostics,
        ])
    }

    public init(
        baseTransactionRevision: DocumentTransactionRevision,
        state: ProjectStateSnapshot,
        commandResults: [CommandExecutionResult],
        geometrySourceCommandResults: [GeometrySourceCommandResult],
        automationExecution: AutomationBatchExecution? = nil
    ) {
        self.baseTransactionRevision = baseTransactionRevision
        self.state = state
        self.commandResults = commandResults
        self.geometrySourceCommandResults = geometrySourceCommandResults
        self.automationExecution = automationExecution
    }
}
