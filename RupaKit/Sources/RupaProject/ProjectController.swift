import Foundation
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaProjectPackage
import SwiftCAD

public actor ProjectController: ProjectOperating {
    private var documentLifetimeID: ProjectDocumentLifetimeID
    private var session: EditorSession
    private var packageDocument: ProjectPackageDocument
    private var evaluationSource: ProjectSourceModel
    private var evaluation: EvaluatedProjectSnapshot?
    private var publicationSequence: UInt64
    private let objectRegistry: ObjectTypeRegistry
    private let commandContextResolver: any EditorCommandContextResolving
    private let automationExecutor: any AutomationStagedBatchExecuting
    private let evaluatorPreparer: any ProjectEvaluatorPreparing
    private let projector: any ProjectSourceProjecting
    private let productSourceCodec: any ProjectProductSourceCoding
    private let cadSourceCodec: any ProjectCADSourceCoding
    private let packageReader: any ProjectPackageReading
    private let packageWriter: any ProjectPackageWriting
    private let packageValidator: any ProjectPackageValidating
    private let geometrySourceCommandApplier: any GeometrySourceCommandApplying

    public init(
        document: DesignDocument,
        evaluatorPreparer: any ProjectEvaluatorPreparing,
        projector: any ProjectSourceProjecting,
        productSourceCodec: any ProjectProductSourceCoding = JSONProjectProductSourceCodec(),
        cadSourceCodec: any ProjectCADSourceCoding = JSONProjectCADSourceCodec(),
        packageReader: any ProjectPackageReading = ProjectPackageStore(),
        packageWriter: any ProjectPackageWriting = ProjectPackageStore(),
        packageValidator: any ProjectPackageValidating = ProjectPackageStore(),
        geometrySourceCommandApplier: any GeometrySourceCommandApplying =
            DefaultGeometrySourceCommandApplier(),
        objectRegistry: ObjectTypeRegistry = .builtIn,
        commandContextResolver: any EditorCommandContextResolving =
            DefaultEditorCommandContextResolver(),
        automationExecutor: any AutomationStagedBatchExecuting =
            AutomationStagedBatchExecutor()
    ) throws {
        let initial = try Self.makeInitialState(
            document: document,
            projector: projector,
            productSourceCodec: productSourceCodec,
            cadSourceCodec: cadSourceCodec,
            packageValidator: packageValidator,
            objectRegistry: objectRegistry
        )
        documentLifetimeID = ProjectDocumentLifetimeID()
        session = EditorSession(
            document: document,
            objectRegistry: objectRegistry,
            commandContextResolver: commandContextResolver
        )
        packageDocument = initial.package
        evaluationSource = initial.evaluationSource
        evaluation = nil
        publicationSequence = 0
        self.objectRegistry = objectRegistry
        self.commandContextResolver = commandContextResolver
        self.automationExecutor = automationExecutor
        self.evaluatorPreparer = evaluatorPreparer
        self.projector = projector
        self.productSourceCodec = productSourceCodec
        self.cadSourceCodec = cadSourceCodec
        self.packageReader = packageReader
        self.packageWriter = packageWriter
        self.packageValidator = packageValidator
        self.geometrySourceCommandApplier = geometrySourceCommandApplier
    }

    public init(
        package: ProjectPackageDocument,
        evaluatorPreparer: any ProjectEvaluatorPreparing,
        projector: any ProjectSourceProjecting,
        productSourceCodec: any ProjectProductSourceCoding = JSONProjectProductSourceCodec(),
        cadSourceCodec: any ProjectCADSourceCoding = JSONProjectCADSourceCodec(),
        packageReader: any ProjectPackageReading = ProjectPackageStore(),
        packageWriter: any ProjectPackageWriting = ProjectPackageStore(),
        packageValidator: any ProjectPackageValidating = ProjectPackageStore(),
        geometrySourceCommandApplier: any GeometrySourceCommandApplying =
            DefaultGeometrySourceCommandApplier(),
        objectRegistry: ObjectTypeRegistry = .builtIn,
        commandContextResolver: any EditorCommandContextResolving =
            DefaultEditorCommandContextResolver(),
        automationExecutor: any AutomationStagedBatchExecuting =
            AutomationStagedBatchExecutor()
    ) throws {
        do {
            try packageValidator.validateForSave(package)
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Initial project package validation failed: \(error)."
            )
        }
        let initial = try Self.decodeAndValidate(
            package: package,
            projector: projector,
            productSourceCodec: productSourceCodec,
            cadSourceCodec: cadSourceCodec,
            objectRegistry: objectRegistry
        )
        documentLifetimeID = ProjectDocumentLifetimeID()
        session = EditorSession(
            document: initial.document,
            objectRegistry: objectRegistry,
            commandContextResolver: commandContextResolver
        )
        packageDocument = package
        evaluationSource = initial.evaluationSource
        evaluation = nil
        publicationSequence = 0
        self.objectRegistry = objectRegistry
        self.commandContextResolver = commandContextResolver
        self.automationExecutor = automationExecutor
        self.evaluatorPreparer = evaluatorPreparer
        self.projector = projector
        self.productSourceCodec = productSourceCodec
        self.cadSourceCodec = cadSourceCodec
        self.packageReader = packageReader
        self.packageWriter = packageWriter
        self.packageValidator = packageValidator
        self.geometrySourceCommandApplier = geometrySourceCommandApplier
    }

    public func currentDocument() -> DesignDocument {
        session.document
    }

    public func currentPackage() -> ProjectPackageDocument {
        packageDocument
    }

    public func currentEvaluationSource() -> ProjectSourceModel {
        evaluationSource
    }

    public func currentTransactionRevision() -> DocumentTransactionRevision {
        session.transactionRevision
    }

    public func currentAuthorityCoordinate() -> ProjectAuthorityCoordinate {
        ProjectAuthorityCoordinate(
            projectID: session.document.projectID,
            transactionRevision: session.transactionRevision,
            publicationSequence: publicationSequence
        )
    }

    public func currentEvaluation() throws -> EvaluatedProjectSnapshot {
        guard let evaluation else {
            throw ProjectControllerError(
                code: .snapshotUnavailable,
                message: "The project has not been evaluated yet."
            )
        }
        return evaluation
    }

    public func currentState() throws -> ProjectStateSnapshot {
        ProjectStateSnapshot(
            documentLifetimeID: documentLifetimeID,
            document: session.document,
            package: packageDocument,
            documentGeneration: session.generation,
            transactionRevision: session.transactionRevision,
            publicationSequence: publicationSequence,
            isDirty: session.isDirty,
            canUndo: session.commandStack.canUndo,
            canRedo: session.commandStack.canRedo,
            selection: session.selection,
            workspaceState: session.workspaceState,
            objectRegistry: session.objectRegistry,
            evaluationSnapshot: session.evaluationSnapshot,
            evaluationSource: evaluationSource,
            cadInteraction: session.currentEvaluation,
            evaluation: try currentEvaluation()
        )
    }

    public func withValidatedCoordinates<Result: Sendable>(
        expectedProjectID: ProjectID,
        expectedDocumentGeneration: DocumentGeneration,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        expectedWorkspaceRevision: WorkspaceRevision,
        operationGuard: @escaping ProjectOperationGuard,
        _ body: @Sendable () throws -> Result
    ) throws -> Result {
        try Task.checkCancellation()
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)
        do {
            try session.store.requireGeneration(expectedDocumentGeneration)
            try session.workspaceState.requireRevision(expectedWorkspaceRevision)
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        try Task.checkCancellation()
        return try body()
    }

    public func applyInteraction(
        _ transaction: ProjectInteractionTransaction,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectInteractionCommitResult {
        try operationGuard()
        let prepared = try prepareInteractionMutation(transaction)
        try Task.checkCancellation()
        try operationGuard()
        return try publishInteractionMutation(prepared, transaction: transaction)
    }

    public func previewInteraction(
        _ transaction: ProjectInteractionTransaction,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectInteractionPreviewResult {
        try operationGuard()
        let prepared = try prepareInteractionMutation(transaction)
        try Task.checkCancellation()
        try operationGuard()
        try requireProjectID(transaction.expectedProjectID)
        try requireTransactionRevision(transaction.expectedTransactionRevision)
        try requirePublicationSequence(transaction.expectedPublicationSequence)
        try requirePublicationSequence(prepared.basePublicationSequence)
        return ProjectInteractionPreviewResult(
            base: ProjectPreviewBaseCoordinate(
                projectID: transaction.expectedProjectID,
                transactionRevision: prepared.baseSessionSnapshot.transactionRevision,
                publicationSequence: prepared.basePublicationSequence,
                documentGeneration: prepared.baseSessionSnapshot.store.document.generation
            ),
            proposedSelection: prepared.proposedSelection,
            proposedWorkspaceState: prepared.proposedWorkspaceState,
            wouldPublish: prepared.wouldPublish,
            automationExecution: prepared.automationExecution
        )
    }

    public func evaluateCurrent() async throws -> EvaluatedProjectSnapshot {
        let state = try await evaluateCurrent(operationGuard: {})
        return state.evaluation
    }

    public func evaluateCurrent(
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot {
        try await evaluateCurrent(
            expectedProjectID: session.document.projectID,
            expectedTransactionRevision: session.transactionRevision,
            expectedPublicationSequence: publicationSequence,
            operationGuard: operationGuard
        )
    }

    public func evaluateCurrent(
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot {
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)
        let stagedEvaluation = try await evaluate(
            document: session.document,
            source: evaluationSource,
            purpose: .presentation,
            revision: expectedTransactionRevision,
            reusing: session.currentEvaluation
        )
        try Task.checkCancellation()
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)
        let nextPublicationSequence = try advancedPublicationSequence()
        evaluation = stagedEvaluation
        publicationSequence = nextPublicationSequence
        return try currentState()
    }

    /// Prepares an explicit source command that promotes the selected modeling
    /// CAD representation's immutable evaluation into an Authored Mesh asset.
    /// The prepared command remains subject to revision and CAD-content checks
    /// when it is committed.
    public func prepareMakeCADRepresentationEditableCommand(
        sceneNodeID: SceneNodeID,
        authoredMeshSourceID: GeometrySourceID,
        authoredMeshRepresentationID: GeometryRepresentationID,
        switchesPresentationSelection: Bool = true,
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> GeometrySourceCommand {
        try requireTransactionRevision(expectedTransactionRevision)
        let baseRevision = session.transactionRevision
        let document = session.document
        let source = evaluationSource

        do {
            try authoredMeshSourceID.validate()
            try authoredMeshRepresentationID.validate()
        } catch let error as EditorError {
            throw ProjectControllerError(code: .transactionInvalid, message: error.message)
        }

        guard let sceneNode = document.productMetadata.sceneNodes[sceneNodeID],
              let object = sceneNode.object,
              object.category == .body,
              let selection = object.geometryRepresentations.selection,
              let sourceRepresentation = object.geometryRepresentations
                .representations[selection.modeling] else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Make Editable requires an existing CAD body modeling selection."
            )
        }
        guard case .cad = sourceRepresentation.source else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Make Editable requires the target object's modeling selection to be CAD."
            )
        }
        guard document.authoredMeshAssets[authoredMeshSourceID] == nil,
              object.geometryRepresentations
                .representations[authoredMeshRepresentationID] == nil else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Make Editable requires unused Authored Mesh source and representation identities."
            )
        }

        let sourceIdentity: ContentIdentity
        do {
            sourceIdentity = try CADSourceContentIdentityService().identity(for: document)
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "Make Editable could not identify the authoritative CAD source: \(error)."
            )
        }
        let modelingSnapshot = try await evaluate(
            document: document,
            source: source,
            purpose: .modeling,
            revision: baseRevision,
            reusing: session.currentEvaluation
        )
        try requireTransactionRevision(baseRevision)
        guard modelingSnapshot.id == EvaluationSnapshotID(
            projectID: source.id,
            purpose: .modeling,
            sourceRevision: baseRevision
        ) else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Make Editable received an evaluation snapshot with a different project, purpose, or revision."
            )
        }
        let occurrence = modelingSnapshot.occurrences.values
            .filter {
                $0.representationID == sourceRepresentation.id
                    && $0.reference == sourceRepresentation.source
            }
            .sorted { $0.occurrenceID.rawValue < $1.occurrenceID.rawValue }
            .first
        guard let occurrence else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Make Editable could not resolve the selected CAD representation in the modeling snapshot."
            )
        }

        do {
            return .makeCADRepresentationEditable(
                try MakeCADRepresentationEditableCommand(
                    sceneNodeID: sceneNodeID,
                    sourceRepresentationID: sourceRepresentation.id,
                    sourceReference: sourceRepresentation.source,
                    evaluationSnapshotID: modelingSnapshot.id,
                    sourceIdentity: sourceIdentity,
                    evaluatedMesh: occurrence.mesh,
                    evaluationCopyTelemetry: occurrence.copyTelemetry,
                    authoredMeshSourceID: authoredMeshSourceID,
                    authoredMeshRepresentationID: authoredMeshRepresentationID,
                    switchesPresentationSelection: switchesPresentationSelection
                )
            )
        } catch let error as EditorError {
            throw ProjectControllerError(code: .transactionInvalid, message: error.message)
        } catch {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Make Editable command preparation failed: \(error)."
            )
        }
    }

    public func commit(
        _ transaction: ProjectSourceTransaction,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectSourceCommitResult {
        try operationGuard()
        let staged = try await prepareSourceMutation(transaction)
        try Task.checkCancellation()
        try operationGuard()
        do {
            try requireProjectID(transaction.expectedProjectID)
            try requireTransactionRevision(transaction.expectedTransactionRevision)
            try requirePublicationSequence(transaction.expectedPublicationSequence)
            try requireTransactionRevision(staged.source.baseTransactionRevision)
            try requirePublicationSequence(staged.basePublicationSequence)
            try session.store.requireGeneration(staged.source.baseGeneration)
            let nextPublicationSequence = try advancedPublicationSequence()
            try session.commitPreparedSourceTransaction(staged.source)
            publicationSequence = nextPublicationSequence
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        packageDocument = staged.package
        evaluationSource = staged.evaluationSource
        evaluation = staged.evaluation
        let committedState = try currentState()
        return ProjectSourceCommitResult(
            baseTransactionRevision: staged.source.baseTransactionRevision,
            state: committedState,
            commandResults: staged.source.value.commandResults,
            geometrySourceCommandResults: staged.source.value.geometrySourceCommandResults,
            automationExecution: committedAutomationExecution(
                staged.source.value.automationExecution,
                state: committedState,
                didCommit: staged.source.wouldMutate
            )
        )
    }

    public func previewSource(
        _ transaction: ProjectSourceTransaction,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectSourcePreviewResult {
        try operationGuard()
        let staged = try await prepareSourceMutation(transaction)
        try Task.checkCancellation()
        try operationGuard()
        do {
            try requireProjectID(transaction.expectedProjectID)
            try requireTransactionRevision(transaction.expectedTransactionRevision)
            try requirePublicationSequence(transaction.expectedPublicationSequence)
            try requireTransactionRevision(staged.source.baseTransactionRevision)
            try requirePublicationSequence(staged.basePublicationSequence)
            try session.store.requireGeneration(staged.source.baseGeneration)
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        let automationExecution = previewAutomationExecution(
            staged.source.value.automationExecution,
            source: staged.source
        )
        return ProjectSourcePreviewResult(
            base: ProjectPreviewBaseCoordinate(
                projectID: transaction.expectedProjectID,
                transactionRevision: staged.source.baseTransactionRevision,
                publicationSequence: staged.basePublicationSequence,
                documentGeneration: staged.source.baseGeneration
            ),
            proposedTransactionRevision: staged.source.proposedTransactionRevision,
            proposedDocumentGeneration: staged.source.proposedGeneration,
            wouldMutate: staged.source.wouldMutate,
            commandResults: staged.source.value.commandResults,
            geometrySourceCommandResults: staged.source.value.geometrySourceCommandResults,
            automationExecution: automationExecution,
            diagnostics: EditorDiagnostic.stableMerged([
                staged.source.value.commandResults.flatMap(\.diagnostics),
                automationExecution?.diagnostics ?? [],
                staged.source.stagedDocumentState.diagnostics,
            ])
        )
    }

    public func executeReadOnlyAutomation(
        _ automation: PreparedAutomationBatch,
        expectedProjectID: ProjectID,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) throws -> AutomationBatchExecution {
        try operationGuard()
        guard automation.effect == .readOnly else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "The project read route accepts only read-only Automation batches."
            )
        }
        let batch = automation.batch
        do {
            try Task.checkCancellation()
            try requireProjectID(expectedProjectID)
            try requirePublicationSequence(expectedPublicationSequence)
            try session.store.requireGeneration(batch.expectedGeneration)
            try session.requireTransactionRevision(batch.expectedTransactionRevision)
            try session.workspaceState.requireRevision(batch.expectedWorkspaceRevision)
            let execution = try session.executeIsolatedReadTransaction { stagedSession in
                try Task.checkCancellation()
                return try automationExecutor.execute(
                    automation,
                    in: stagedSession
                )
            }
            try Task.checkCancellation()
            try requireProjectID(expectedProjectID)
            try requirePublicationSequence(expectedPublicationSequence)
            try session.store.requireGeneration(batch.expectedGeneration)
            try session.requireTransactionRevision(batch.expectedTransactionRevision)
            try session.workspaceState.requireRevision(batch.expectedWorkspaceRevision)
            try operationGuard()
            return execution
        } catch let error as EditorError {
            throw projectError(for: error)
        }
    }

    private func prepareSourceMutation(
        _ transaction: ProjectSourceTransaction
    ) async throws -> PreparedProjectSourceMutation {
        try requireProjectID(transaction.expectedProjectID)
        try requireTransactionRevision(transaction.expectedTransactionRevision)
        try requirePublicationSequence(transaction.expectedPublicationSequence)
        do {
            try commandContextResolver.requireFullyResolved(transaction.commands)
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        let basePublicationSequence = publicationSequence
        try Task.checkCancellation()
        try await validateMakeEditableEvaluationBindings(in: transaction)
        try Task.checkCancellation()
        try requireProjectID(transaction.expectedProjectID)
        try requireTransactionRevision(transaction.expectedTransactionRevision)
        try requirePublicationSequence(transaction.expectedPublicationSequence)

        let prepared: PreparedEditorSourceTransaction<StagedCommandResults>
        do {
            prepared = try session.prepareIsolatedSourceTransaction(
                commandName: transaction.name,
                expectedTransactionRevision: transaction.expectedTransactionRevision
            ) { stagedSession in
                let initialEvaluationPassCount = stagedSession.store.completedEvaluationPassCount
                let initialHistoryEntryCount = stagedSession.commandStack.undoEntries.count
                var stagedResults = try stagedSession.withSourceCommandGroup(named: transaction.name) {
                    groupedSession in
                    let commandResults: [CommandExecutionResult]
                    let automationExecution: AutomationBatchExecution?
                    switch transaction.mutation {
                    case .commands(let commands):
                        commandResults = try commands.map { command in
                            try groupedSession.execute(command)
                        }
                        automationExecution = nil
                    case .automation(let automation):
                        commandResults = []
                        automationExecution = try automationExecutor.execute(
                            automation,
                            in: groupedSession
                        )
                    }
                    let geometrySourceCommandResults = try transaction
                        .geometrySourceCommands.map { command in
                            try groupedSession.execute(
                                command,
                                using: geometrySourceCommandApplier
                            )
                        }
                    return StagedCommandResults(
                        commandResults: commandResults,
                        geometrySourceCommandResults: geometrySourceCommandResults,
                        automationExecution: automationExecution
                    )
                }
                if let automationExecution = stagedResults.automationExecution {
                    stagedResults.automationExecution = automationExecutor.finalizingSourceMetrics(
                        automationExecution,
                        initialEvaluationPassCount: initialEvaluationPassCount,
                        initialHistoryEntryCount: initialHistoryEntryCount,
                        in: stagedSession
                    )
                }
                return stagedResults
            }
        } catch let error as EditorError {
            throw projectError(for: error)
        } catch {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project source staging failed: \(error)."
            )
        }

        let stagedAuthority = try await sourceAuthoritySnapshot(
            for: prepared.stagedDocument,
            includesCADSource: prepared.stagedDocument.hasAuthoritativeCADSource
        )
        try Task.checkCancellation()
        let stagedProductSource = try await encodeProductSource(prepared.stagedDocument)
        try Task.checkCancellation()
        let stagedCADSource = try await encodeCADSourceIfAuthoritative(
            prepared.stagedDocument
        )
        try Task.checkCancellation()
        let stagedEvaluationSource = try await projectSource(prepared.stagedDocument)
        guard stagedEvaluationSource.id == packageDocument.documentID else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "A source transaction cannot change the project identity."
            )
        }
        let stagedPackage: ProjectPackageDocument
        do {
            let replacedPackage = try packageDocument.replacingSources(
                documentID: stagedEvaluationSource.id,
                product: stagedProductSource,
                cad: stagedCADSource,
                authoredMeshAssets: prepared.stagedDocument.authoredMeshAssets
            )
            stagedPackage = prepared.value.didMutateAuthoredMesh
                ? replacedPackage.garbageCollectingUnreferencedSourceBlobs()
                : replacedPackage
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Staged project package validation failed: \(error)."
            )
        }
        try await validatePackageForSave(stagedPackage)
        try Task.checkCancellation()
        let reconstructed = try await reconstructState(from: stagedPackage)
        try Task.checkCancellation()
        let reconstructedAuthority = try await sourceAuthoritySnapshot(
            for: reconstructed.document,
            includesCADSource: stagedPackage.cadSource != nil
        )
        try Self.requireMatchingAuthority(
            expected: stagedAuthority,
            actual: reconstructedAuthority,
            context: "Staged project sources"
        )
        guard reconstructed.evaluationSource == stagedEvaluationSource else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Staged Product, CAD, and Mesh sources do not reproduce the edited document."
            )
        }
        let stagedEvaluation = try await evaluate(
            document: reconstructed.document,
            source: reconstructed.evaluationSource,
            purpose: .presentation,
            revision: prepared.proposedTransactionRevision,
            reusing: prepared.stagedEvaluation
        )
        try Task.checkCancellation()
        return PreparedProjectSourceMutation(
            basePublicationSequence: basePublicationSequence,
            source: prepared,
            package: stagedPackage,
            evaluationSource: reconstructed.evaluationSource,
            evaluation: stagedEvaluation
        )
    }

    private func committedAutomationExecution(
        _ execution: AutomationBatchExecution?,
        state: ProjectStateSnapshot,
        didCommit: Bool
    ) -> AutomationBatchExecution? {
        execution.map { execution in
            var committed = execution
            committed.proposedGeneration = state.documentGeneration
            committed.proposedTransactionRevision = state.transactionRevision
            committed.proposedWorkspaceRevision = state.workspaceState.revision
            committed.didCommit = didCommit
            committed.finalContext = AutomationBatchFinalContext(
                document: state.document,
                generation: state.documentGeneration,
                transactionRevision: state.transactionRevision,
                selection: state.selection,
                workspaceState: state.workspaceState,
                objectRegistry: state.objectRegistry,
                evaluationSnapshot: state.evaluationSnapshot,
                currentEvaluation: state.cadInteraction,
                isDirty: state.isDirty,
                diagnostics: EditorDiagnostic.stableMerged([
                    execution.finalContext.diagnostics,
                    state.evaluationSnapshot.diagnostics,
                ])
            )
            return committed
        }
    }

    private func previewAutomationExecution(
        _ execution: AutomationBatchExecution?,
        source: PreparedEditorSourceTransaction<StagedCommandResults>
    ) -> AutomationBatchExecution? {
        execution.map { execution in
            let documentState = source.stagedDocumentState
            var preview = execution
            preview.proposedGeneration = source.proposedGeneration
            preview.proposedTransactionRevision = source.proposedTransactionRevision
            preview.proposedWorkspaceRevision = source.stagedWorkspaceState.revision
            preview.didCommit = false
            preview.finalContext = AutomationBatchFinalContext(
                document: documentState.document,
                generation: documentState.generation,
                transactionRevision: source.proposedTransactionRevision,
                selection: source.stagedSelection,
                workspaceState: source.stagedWorkspaceState,
                objectRegistry: objectRegistry,
                evaluationSnapshot: EvaluationSnapshot(
                    status: documentState.evaluationStatus,
                    evaluatedGeneration: documentState.evaluatedGeneration,
                    renderInvalidation: documentState.renderInvalidation,
                    bodyCount: documentState.evaluatedBodyCount,
                    diagnostics: documentState.diagnostics
                ),
                currentEvaluation: source.stagedEvaluation,
                isDirty: documentState.isDirty,
                diagnostics: EditorDiagnostic.stableMerged([
                    execution.finalContext.diagnostics,
                    documentState.diagnostics,
                ])
            )
            return preview
        }
    }

    public func undo(
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> ProjectStateSnapshot {
        try await performHistoryTransaction(
            direction: .undo,
            expectedProjectID: session.document.projectID,
            expectedTransactionRevision: expectedTransactionRevision,
            expectedPublicationSequence: publicationSequence,
            operationGuard: {}
        )
    }

    public func undo(
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot {
        try await performHistoryTransaction(
            direction: .undo,
            expectedProjectID: expectedProjectID,
            expectedTransactionRevision: expectedTransactionRevision,
            expectedPublicationSequence: expectedPublicationSequence,
            operationGuard: operationGuard
        )
    }

    public func redo(
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> ProjectStateSnapshot {
        try await performHistoryTransaction(
            direction: .redo,
            expectedProjectID: session.document.projectID,
            expectedTransactionRevision: expectedTransactionRevision,
            expectedPublicationSequence: publicationSequence,
            operationGuard: {}
        )
    }

    public func redo(
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot {
        try await performHistoryTransaction(
            direction: .redo,
            expectedProjectID: expectedProjectID,
            expectedTransactionRevision: expectedTransactionRevision,
            expectedPublicationSequence: expectedPublicationSequence,
            operationGuard: operationGuard
        )
    }

    public func load(
        from url: URL,
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> ProjectStateSnapshot {
        try await load(
            from: url,
            expectedProjectID: session.document.projectID,
            expectedTransactionRevision: expectedTransactionRevision,
            expectedPublicationSequence: publicationSequence,
            operationGuard: {}
        )
    }

    public func load(
        from url: URL,
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot {
        try Task.checkCancellation()
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)
        let basePublicationSequence = publicationSequence
        let reader = packageReader
        let loadedPackage: ProjectPackageDocument
        do {
            loadedPackage = try await Self.performDetached {
                try Task.checkCancellation()
                let package = try reader.load(from: url)
                try Task.checkCancellation()
                return package
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Project package load failed: \(error)."
            )
        }

        let reconstructed = try await reconstructState(from: loadedPackage)
        let loadedRevision: DocumentTransactionRevision
        do {
            loadedRevision = try expectedTransactionRevision.advanced()
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        let loadedEvaluation = try await evaluate(
            document: reconstructed.document,
            source: reconstructed.evaluationSource,
            purpose: .presentation,
            revision: loadedRevision,
            reusing: nil
        )
        try Task.checkCancellation()
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)
        try requirePublicationSequence(basePublicationSequence)
        let nextPublicationSequence = try advancedPublicationSequence()

        documentLifetimeID = ProjectDocumentLifetimeID()
        session = EditorSession(
            document: reconstructed.document,
            transactionRevision: loadedRevision,
            objectRegistry: objectRegistry,
            commandContextResolver: commandContextResolver
        )
        packageDocument = loadedPackage
        evaluationSource = reconstructed.evaluationSource
        evaluation = loadedEvaluation
        publicationSequence = nextPublicationSequence
        return ProjectStateSnapshot(
            documentLifetimeID: documentLifetimeID,
            document: reconstructed.document,
            package: loadedPackage,
            documentGeneration: session.generation,
            transactionRevision: loadedRevision,
            publicationSequence: publicationSequence,
            isDirty: session.isDirty,
            canUndo: session.commandStack.canUndo,
            canRedo: session.commandStack.canRedo,
            selection: session.selection,
            workspaceState: session.workspaceState,
            objectRegistry: session.objectRegistry,
            evaluationSnapshot: session.evaluationSnapshot,
            evaluationSource: reconstructed.evaluationSource,
            cadInteraction: session.currentEvaluation,
            evaluation: loadedEvaluation
        )
    }

    public func replace(
        with document: DesignDocument,
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot {
        try Task.checkCancellation()
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)

        let initial = try Self.makeInitialState(
            document: document,
            projector: projector,
            productSourceCodec: productSourceCodec,
            cadSourceCodec: cadSourceCodec,
            packageValidator: packageValidator,
            objectRegistry: objectRegistry
        )
        let replacementRevision: DocumentTransactionRevision
        do {
            replacementRevision = try expectedTransactionRevision.advanced()
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        let replacementEvaluation = try await evaluate(
            document: document,
            source: initial.evaluationSource,
            purpose: .presentation,
            revision: replacementRevision,
            reusing: nil
        )

        try Task.checkCancellation()
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)
        let nextPublicationSequence = try advancedPublicationSequence()

        documentLifetimeID = ProjectDocumentLifetimeID()
        session = EditorSession(
            document: document,
            transactionRevision: replacementRevision,
            objectRegistry: objectRegistry,
            commandContextResolver: commandContextResolver
        )
        packageDocument = initial.package
        evaluationSource = initial.evaluationSource
        evaluation = replacementEvaluation
        publicationSequence = nextPublicationSequence
        return try currentState()
    }

    /// Saves synchronously inside actor isolation so no source transaction can
    /// pass the revision check before the atomic file replacement completes.
    public func save(
        to url: URL,
        expectedTransactionRevision: DocumentTransactionRevision
    ) throws -> ProjectPackageSaveResult {
        try savePackage(
            to: url,
            expectedProjectID: session.document.projectID,
            expectedTransactionRevision: expectedTransactionRevision,
            expectedPublicationSequence: publicationSequence,
            operationGuard: {}
        )
    }

    public func save(
        to url: URL,
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) throws -> ProjectSaveCommitResult {
        _ = try currentEvaluation()
        let package = try savePackage(
            to: url,
            expectedProjectID: expectedProjectID,
            expectedTransactionRevision: expectedTransactionRevision,
            expectedPublicationSequence: expectedPublicationSequence,
            operationGuard: operationGuard
        )
        return ProjectSaveCommitResult(
            package: package,
            state: try currentState()
        )
    }

    private func savePackage(
        to url: URL,
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) throws -> ProjectPackageSaveResult {
        try Task.checkCancellation()
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)
        let nextPublicationSequence = try advancedPublicationSequence()
        do {
            let result = try packageWriter.save(packageDocument, to: url)
            packageDocument = result.document
            session.markClean()
            publicationSequence = nextPublicationSequence
            return result
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Project package save failed: \(error)."
            )
        }
    }

    private func performHistoryTransaction(
        direction: HistoryDirection,
        expectedProjectID: ProjectID,
        expectedTransactionRevision: DocumentTransactionRevision,
        expectedPublicationSequence: UInt64,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot {
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)
        let historyIsAvailable: Bool
        switch direction {
        case .undo:
            historyIsAvailable = session.commandStack.canUndo
        case .redo:
            historyIsAvailable = session.commandStack.canRedo
        }
        guard historyIsAvailable else {
            throw ProjectControllerError(
                code: .historyUnavailable,
                message: "There is no project history entry to \(direction.operationName)."
            )
        }

        let prepared: PreparedEditorHistoryTransaction
        do {
            switch direction {
            case .undo:
                prepared = try session.prepareUndo(
                    expectedTransactionRevision: expectedTransactionRevision
                )
            case .redo:
                prepared = try session.prepareRedo(
                    expectedTransactionRevision: expectedTransactionRevision
                )
            }
        } catch let error as EditorError {
            throw projectError(for: error)
        }

        let stagedAuthority = try await sourceAuthoritySnapshot(
            for: prepared.stagedDocument,
            includesCADSource: prepared.stagedDocument.hasAuthoritativeCADSource
        )
        let stagedProductSource = try await encodeProductSource(prepared.stagedDocument)
        let stagedCADSource = try await encodeCADSourceIfAuthoritative(prepared.stagedDocument)
        let stagedEvaluationSource = try await projectSource(prepared.stagedDocument)
        guard stagedEvaluationSource.id == packageDocument.documentID else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Project history cannot change the project identity."
            )
        }

        let stagedPackage: ProjectPackageDocument
        do {
            stagedPackage = try packageDocument.replacingSources(
                documentID: stagedEvaluationSource.id,
                product: stagedProductSource,
                cad: stagedCADSource,
                authoredMeshAssets: prepared.stagedDocument.authoredMeshAssets
            ).garbageCollectingUnreferencedSourceBlobs()
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Staged project history package validation failed: \(error)."
            )
        }
        try await validatePackageForSave(stagedPackage)
        let reconstructed = try await reconstructState(from: stagedPackage)
        let reconstructedAuthority = try await sourceAuthoritySnapshot(
            for: reconstructed.document,
            includesCADSource: stagedPackage.cadSource != nil
        )
        try Self.requireMatchingAuthority(
            expected: stagedAuthority,
            actual: reconstructedAuthority,
            context: "Staged project history sources"
        )
        guard reconstructed.evaluationSource == stagedEvaluationSource else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Staged project history sources do not reproduce the restored document."
            )
        }
        let stagedEvaluation = try await evaluate(
            document: reconstructed.document,
            source: reconstructed.evaluationSource,
            purpose: .presentation,
            revision: prepared.proposedTransactionRevision,
            reusing: prepared.stagedEvaluation
        )

        try Task.checkCancellation()
        try operationGuard()
        try requireProjectID(expectedProjectID)
        try requireTransactionRevision(expectedTransactionRevision)
        try requirePublicationSequence(expectedPublicationSequence)
        do {
            try requireTransactionRevision(prepared.baseTransactionRevision)
            try requirePublicationSequence(expectedPublicationSequence)
            let nextPublicationSequence = try advancedPublicationSequence()
            try session.commitPreparedHistoryTransaction(prepared)
            packageDocument = stagedPackage
            evaluationSource = reconstructed.evaluationSource
            evaluation = stagedEvaluation
            publicationSequence = nextPublicationSequence
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        return try currentState()
    }

    private func requireTransactionRevision(
        _ expectedTransactionRevision: DocumentTransactionRevision
    ) throws {
        do {
            try session.requireTransactionRevision(expectedTransactionRevision)
        } catch let error as EditorError {
            throw projectError(for: error)
        }
    }

    private func requireProjectID(_ expectedProjectID: ProjectID) throws {
        guard session.document.projectID == expectedProjectID else {
            throw ProjectControllerError(
                code: .projectMismatch,
                message: "The project transaction belongs to a different project."
            )
        }
    }

    private func requirePublicationSequence(
        _ expectedPublicationSequence: UInt64
    ) throws {
        guard publicationSequence == expectedPublicationSequence else {
            throw ProjectControllerError(
                code: .publicationConflict,
                message: "Expected project publication sequence \(expectedPublicationSequence), but current sequence is \(publicationSequence)."
            )
        }
    }

    private func prepareInteractionMutation(
        _ transaction: ProjectInteractionTransaction
    ) throws -> PreparedProjectInteractionMutation {
        try requireProjectID(transaction.expectedProjectID)
        try requireTransactionRevision(transaction.expectedTransactionRevision)
        try requirePublicationSequence(transaction.expectedPublicationSequence)
        _ = try currentEvaluation()

        let basePublicationSequence = publicationSequence
        let baseSessionSnapshot = session.transactionSnapshot()
        let proposedSelection: SelectionModel
        let proposedWorkspaceState: WorkspaceState
        let automationExecution: AutomationBatchExecution?

        switch transaction.mutation {
        case .direct(let requestedSelection, let workspaceCommands):
            if let requestedSelection {
                proposedSelection = try validatedSelection(for: requestedSelection)
            } else {
                proposedSelection = baseSessionSnapshot.selection
            }
            var stagedWorkspaceState = baseSessionSnapshot.workspaceState
            if !workspaceCommands.isEmpty {
                do {
                    for workspaceCommand in workspaceCommands {
                        _ = try stagedWorkspaceState.apply(
                            workspaceCommand,
                            document: session.document
                        )
                    }
                    try stagedWorkspaceState.validate(against: session.document)
                } catch let error as EditorError {
                    throw projectError(for: error)
                } catch {
                    throw ProjectControllerError(
                        code: .transactionInvalid,
                        message: "Persistent workspace staging failed: \(error)."
                    )
                }
            }
            proposedWorkspaceState = stagedWorkspaceState
            automationExecution = nil

        case .automation(let automation):
            let isolated: IsolatedWorkspaceTransactionExecution<AutomationBatchExecution>
            do {
                isolated = try session.executeIsolatedWorkspaceTransaction(
                    commits: false
                ) { stagedSession in
                    try automationExecutor.execute(
                        automation,
                        in: stagedSession
                    )
                }
            } catch let error as EditorError {
                throw projectError(for: error)
            } catch {
                throw ProjectControllerError(
                    code: .transactionInvalid,
                    message: "Project interaction Automation staging failed: \(error)."
                )
            }
            let finalContext = isolated.value.finalContext
            guard finalContext.generation == session.generation,
                  finalContext.transactionRevision == session.transactionRevision,
                  finalContext.selection == baseSessionSnapshot.selection else {
                throw ProjectControllerError(
                    code: .sourceMismatch,
                    message: "Project interaction Automation changed source or selection authority."
                )
            }
            proposedSelection = finalContext.selection
            proposedWorkspaceState = finalContext.workspaceState
            automationExecution = isolated.value
        }

        let workspaceChanged = hasSemanticWorkspaceChange(
            from: baseSessionSnapshot.workspaceState,
            to: proposedWorkspaceState
        )
        let canonicalWorkspaceState = workspaceChanged
            ? proposedWorkspaceState
            : baseSessionSnapshot.workspaceState
        let canonicalAutomationExecution = automationExecution.map { execution in
            var preview = execution
            preview.proposedGeneration = baseSessionSnapshot.store.document.generation
            preview.proposedTransactionRevision = baseSessionSnapshot.transactionRevision
            preview.proposedWorkspaceRevision = canonicalWorkspaceState.revision
            preview.didCommit = false
            preview.finalContext = AutomationBatchFinalContext(
                document: baseSessionSnapshot.store.document.document,
                generation: baseSessionSnapshot.store.document.generation,
                transactionRevision: baseSessionSnapshot.transactionRevision,
                selection: proposedSelection,
                workspaceState: canonicalWorkspaceState,
                objectRegistry: objectRegistry,
                evaluationSnapshot: EvaluationSnapshot(
                    status: baseSessionSnapshot.store.document.evaluationStatus,
                    evaluatedGeneration: baseSessionSnapshot.store.document.evaluatedGeneration,
                    renderInvalidation: baseSessionSnapshot.store.document.renderInvalidation,
                    bodyCount: baseSessionSnapshot.store.document.evaluatedBodyCount,
                    diagnostics: baseSessionSnapshot.store.document.diagnostics
                ),
                currentEvaluation: session.currentEvaluation,
                isDirty: baseSessionSnapshot.store.document.isDirty,
                diagnostics: execution.finalContext.diagnostics
            )
            return preview
        }
        return PreparedProjectInteractionMutation(
            basePublicationSequence: basePublicationSequence,
            baseSessionSnapshot: baseSessionSnapshot,
            proposedSelection: proposedSelection,
            proposedWorkspaceState: canonicalWorkspaceState,
            wouldPublish: proposedSelection != baseSessionSnapshot.selection
                || workspaceChanged,
            automationExecution: canonicalAutomationExecution
        )
    }

    private func publishInteractionMutation(
        _ prepared: PreparedProjectInteractionMutation,
        transaction: ProjectInteractionTransaction
    ) throws -> ProjectInteractionCommitResult {
        try requireProjectID(transaction.expectedProjectID)
        try requireTransactionRevision(transaction.expectedTransactionRevision)
        try requirePublicationSequence(transaction.expectedPublicationSequence)
        try requirePublicationSequence(prepared.basePublicationSequence)

        guard prepared.wouldPublish else {
            let state = try currentState()
            return ProjectInteractionCommitResult(
                state: state,
                automationExecution: committedAutomationExecution(
                    prepared.automationExecution,
                    state: state,
                    didCommit: false
                )
            )
        }

        var stagedSessionSnapshot = prepared.baseSessionSnapshot
        stagedSessionSnapshot.selection = prepared.proposedSelection
        stagedSessionSnapshot.workspaceState = prepared.proposedWorkspaceState
        let nextPublicationSequence = try advancedPublicationSequence()
        do {
            session.restoreTransactionSnapshot(stagedSessionSnapshot)
            publicationSequence = nextPublicationSequence
            let state = try currentState()
            return ProjectInteractionCommitResult(
                state: state,
                automationExecution: committedAutomationExecution(
                    prepared.automationExecution,
                    state: state,
                    didCommit: true
                )
            )
        } catch {
            session.restoreTransactionSnapshot(prepared.baseSessionSnapshot)
            publicationSequence = prepared.basePublicationSequence
            throw error
        }
    }

    private func validatedSelection(
        for operation: ProjectSelectionOperation
    ) throws -> SelectionModel {
        let requestedSelection: SelectionModel
        switch operation {
        case .replace(let selection):
            requestedSelection = selection
        case .clear:
            return .empty
        }
        guard requestedSelection.selectedTargets.isEmpty
                || requestedSelection.selectedReferences.isEmpty else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "A selection transaction cannot contain object targets and subshape references together."
            )
        }
        guard requestedSelection.hoveredTarget == nil,
              requestedSelection.hoveredReference == nil else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Selection hover state is transient and cannot be committed by a project interaction transaction."
            )
        }

        var validated = SelectionModel.empty
        do {
            if !requestedSelection.selectedTargets.isEmpty {
                try validated.selectTargets(
                    requestedSelection.selectedTargets,
                    in: session.document
                )
            } else if !requestedSelection.selectedReferences.isEmpty {
                try validated.selectReferences(
                    requestedSelection.selectedReferences,
                    in: session.document
                )
            }
        } catch let error as EditorError {
            throw projectError(for: error)
        } catch {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Selection staging failed: \(error)."
            )
        }
        guard validated == requestedSelection else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "The selection transaction is not in canonical form."
            )
        }
        return validated
    }

    private func hasSemanticWorkspaceChange(
        from base: WorkspaceState,
        to staged: WorkspaceState
    ) -> Bool {
        base.ruler != staged.ruler
            || base.viewportGridSettings != staged.viewportGridSettings
            || base.activeConstructionPlaneID != staged.activeConstructionPlaneID
            || base.curveCurvatureDisplays != staged.curveCurvatureDisplays
            || base.pointDisplays != staged.pointDisplays
            || base.surfaceControlPointDisplays != staged.surfaceControlPointDisplays
            || base.surfaceFrameDisplays != staged.surfaceFrameDisplays
    }

    private func encodeProductSource(
        _ document: DesignDocument
    ) async throws -> ProjectPackageProductSource {
        let codec = productSourceCodec
        do {
            return try await Self.performDetached {
                try Task.checkCancellation()
                let source = try codec.encode(document)
                try Task.checkCancellation()
                return source
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .productSourceFailed,
                message: "Product source encoding failed: \(error)."
            )
        }
    }

    private func decodeProductSource(
        _ source: ProjectPackageProductSource
    ) async throws -> ProjectProductSourceModel {
        let codec = productSourceCodec
        do {
            return try await Self.performDetached {
                try Task.checkCancellation()
                let product = try codec.decode(source)
                try Task.checkCancellation()
                return product
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProjectControllerError {
            throw error
        } catch {
            throw ProjectControllerError(
                code: .productSourceFailed,
                message: "Product source decoding failed: \(error)."
            )
        }
    }

    private func encodeCADSourceIfAuthoritative(
        _ document: DesignDocument
    ) async throws -> ProjectPackageCADSource? {
        guard document.hasAuthoritativeCADSource else {
            return nil
        }
        let codec = cadSourceCodec
        let cadDocument = document.cadDocument
        do {
            return try await Self.performDetached {
                try Task.checkCancellation()
                let source = try codec.encode(cadDocument)
                try Task.checkCancellation()
                return source
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .cadSourceFailed,
                message: "CAD source encoding failed: \(error)."
            )
        }
    }

    private func decodeOptionalCADSource(
        _ source: ProjectPackageCADSource?
    ) async throws -> CADDocument? {
        guard let source else {
            return nil
        }
        let codec = cadSourceCodec
        do {
            return try await Self.performDetached {
                try Task.checkCancellation()
                let document = try codec.decode(source)
                try Task.checkCancellation()
                return document
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .cadSourceFailed,
                message: "CAD source decoding failed: \(error)."
            )
        }
    }

    private func projectSource(
        _ document: DesignDocument
    ) async throws -> ProjectSourceModel {
        let projector = self.projector
        do {
            return try await Self.performDetached {
                try Task.checkCancellation()
                let source = try projector.project(document)
                try source.validate()
                try Task.checkCancellation()
                return source
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .projectionFailed,
                message: "Project evaluation-source projection failed: \(error)."
            )
        }
    }

    private func sourceAuthoritySnapshot(
        for document: DesignDocument,
        includesCADSource: Bool
    ) async throws -> ProjectSourceAuthoritySnapshot {
        do {
            return try await Self.performDetached {
                try Task.checkCancellation()
                let snapshot = try ProjectSourceAuthoritySnapshot(
                    document: document,
                    includesCADSource: includesCADSource
                )
                try Task.checkCancellation()
                return snapshot
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "Project source authority identity generation failed: \(error)."
            )
        }
    }

    private func reconstructState(
        from package: ProjectPackageDocument
    ) async throws -> (document: DesignDocument, evaluationSource: ProjectSourceModel) {
        let product = try await decodeProductSource(package.productSource)
        let cadDocument = try await decodeOptionalCADSource(package.cadSource)
        let document = try Self.assembleDocument(
            package: package,
            product: product,
            cadDocument: cadDocument,
            objectRegistry: objectRegistry
        )
        let source = try await projectSource(document)
        guard source.id == package.documentID else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Product identity and evaluation projection differ."
            )
        }
        return (document, source)
    }

    private func validatePackageForSave(
        _ package: ProjectPackageDocument
    ) async throws {
        let validator = packageValidator
        do {
            try await Self.performDetached {
                try Task.checkCancellation()
                try validator.validateForSave(package)
                try Task.checkCancellation()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Staged project package encoding validation failed: \(error)."
            )
        }
    }

    private func evaluate(
        document: DesignDocument,
        source: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) async throws -> EvaluatedProjectSnapshot {
        let evaluatorPreparer = self.evaluatorPreparer
        do {
            return try await Self.performDetached {
                try Task.checkCancellation()
                let evaluator = try evaluatorPreparer.makeEvaluator(
                    for: document,
                    reusing: currentEvaluation
                )
                try Task.checkCancellation()
                let result = try evaluator.evaluate(
                    project: source,
                    purpose: purpose,
                    revision: revision
                )
                try Task.checkCancellation()
                return result
            }
        } catch let error as EvaluationError {
            throw ProjectControllerError(
                code: .evaluationFailed,
                message: error.message
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .evaluationFailed,
                message: "Project evaluation failed: \(error)."
            )
        }
    }

    /// Re-evaluates the current modeling projection so a caller-provided
    /// command cannot promote an arbitrary Mesh payload under valid-looking
    /// snapshot and CAD identities. The shared CAD cache keeps this validation
    /// zero-copy after command preparation while the exact payload comparison
    /// remains independent from cache-storage identity.
    private func validateMakeEditableEvaluationBindings(
        in transaction: ProjectSourceTransaction
    ) async throws {
        let baseRevision = session.transactionRevision
        var requiresModelingEvaluation = false
        for geometryCommand in transaction.geometrySourceCommands {
            guard case .makeCADRepresentationEditable(let command) = geometryCommand else {
                continue
            }
            do {
                try command.validate()
            } catch let error as EditorError {
                throw ProjectControllerError(code: .transactionInvalid, message: error.message)
            }
            guard command.evaluationSnapshotID.sourceRevision == baseRevision else {
                throw ProjectControllerError(
                    code: .revisionConflict,
                    message: "Make Editable command was prepared from a stale transaction revision."
                )
            }
            requiresModelingEvaluation = true
        }
        guard requiresModelingEvaluation else {
            return
        }

        let document = session.document
        let source = evaluationSource
        let snapshot = try await evaluate(
            document: document,
            source: source,
            purpose: .modeling,
            revision: baseRevision,
            reusing: session.currentEvaluation
        )
        try requireTransactionRevision(baseRevision)

        for geometryCommand in transaction.geometrySourceCommands {
            guard case .makeCADRepresentationEditable(let command) = geometryCommand else {
                continue
            }
            guard command.evaluationSnapshotID == snapshot.id else {
                throw ProjectControllerError(
                    code: .sourceMismatch,
                    message: "Make Editable command is not bound to the current modeling evaluation snapshot."
                )
            }
            let matchesEvaluatedSource = snapshot.occurrences.values.contains { occurrence in
                occurrence.representationID == command.sourceRepresentationID
                    && occurrence.reference == command.sourceReference
                    && occurrence.mesh == command.evaluatedMesh
            }
            guard matchesEvaluatedSource else {
                throw ProjectControllerError(
                    code: .sourceMismatch,
                    message: "Make Editable Mesh payload does not match the bound CAD modeling evaluation."
                )
            }
        }
    }

    private func projectError(for error: EditorError) -> ProjectControllerError {
        if error.code == .documentTransactionRevisionMismatch {
            return ProjectControllerError(code: .revisionConflict, message: error.message)
        }
        return ProjectControllerError(code: .transactionInvalid, message: error.message)
    }

    private func advancedPublicationSequence() throws -> UInt64 {
        let advanced = publicationSequence.addingReportingOverflow(1)
        guard !advanced.overflow else {
            throw ProjectControllerError(
                code: .transactionInvalid,
                message: "Project state publication sequence overflowed."
            )
        }
        return advanced.partialValue
    }

    private static func performDetached<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: nil, operation: operation)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func makeInitialState(
        document: DesignDocument,
        projector: any ProjectSourceProjecting,
        productSourceCodec: any ProjectProductSourceCoding,
        cadSourceCodec: any ProjectCADSourceCoding,
        packageValidator: any ProjectPackageValidating,
        objectRegistry: ObjectTypeRegistry
    ) throws -> (package: ProjectPackageDocument, evaluationSource: ProjectSourceModel) {
        do {
            _ = try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "Initial DesignDocument validation failed: \(error)."
            )
        }
        let expectedAuthority: ProjectSourceAuthoritySnapshot
        do {
            expectedAuthority = try ProjectSourceAuthoritySnapshot(
                document: document,
                includesCADSource: document.hasAuthoritativeCADSource
            )
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "Initial project source authority identity generation failed: \(error)."
            )
        }
        let source: ProjectSourceModel
        do {
            source = try projector.project(document)
            try source.validate()
        } catch {
            throw ProjectControllerError(
                code: .projectionFailed,
                message: "Initial project evaluation-source projection failed: \(error)."
            )
        }
        let productSource: ProjectPackageProductSource
        do {
            productSource = try productSourceCodec.encode(document)
        } catch {
            throw ProjectControllerError(
                code: .productSourceFailed,
                message: "Initial Product source encoding failed: \(error)."
            )
        }
        let cadSource: ProjectPackageCADSource?
        do {
            cadSource = document.hasAuthoritativeCADSource
                ? try cadSourceCodec.encode(document.cadDocument)
                : nil
        } catch {
            throw ProjectControllerError(
                code: .cadSourceFailed,
                message: "Initial CAD source encoding failed: \(error)."
            )
        }
        let package: ProjectPackageDocument
        do {
            package = try ProjectPackageDocument(
                documentID: source.id,
                productSource: productSource,
                cadSource: cadSource,
                authoredMeshAssets: document.authoredMeshAssets
            )
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Initial project package creation failed: \(error)."
            )
        }
        do {
            try packageValidator.validateForSave(package)
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Initial project package encoding validation failed: \(error)."
            )
        }
        let reconstructed = try decodeAndValidate(
            package: package,
            projector: projector,
            productSourceCodec: productSourceCodec,
            cadSourceCodec: cadSourceCodec,
            objectRegistry: objectRegistry
        )
        let reconstructedAuthority: ProjectSourceAuthoritySnapshot
        do {
            reconstructedAuthority = try ProjectSourceAuthoritySnapshot(
                document: reconstructed.document,
                includesCADSource: package.cadSource != nil
            )
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "Initial reconstructed source authority identity generation failed: \(error)."
            )
        }
        try requireMatchingAuthority(
            expected: expectedAuthority,
            actual: reconstructedAuthority,
            context: "Initial project sources"
        )
        guard reconstructed.evaluationSource == source else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Initial codecs do not reproduce the supplied DesignDocument."
            )
        }
        return (package, source)
    }

    private static func requireMatchingAuthority(
        expected: ProjectSourceAuthoritySnapshot,
        actual: ProjectSourceAuthoritySnapshot,
        context: String
    ) throws {
        guard expected.product == actual.product else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "\(context) do not reproduce the Product authority."
            )
        }
        guard expected.cad == actual.cad else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "\(context) do not reproduce the CAD authority."
            )
        }
        guard expected.authoredMeshAssets == actual.authoredMeshAssets else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "\(context) do not reproduce the Authored-Mesh authority."
            )
        }
    }

    private static func decodeAndValidate(
        package: ProjectPackageDocument,
        projector: any ProjectSourceProjecting,
        productSourceCodec: any ProjectProductSourceCoding,
        cadSourceCodec: any ProjectCADSourceCoding,
        objectRegistry: ObjectTypeRegistry
    ) throws -> (document: DesignDocument, evaluationSource: ProjectSourceModel) {
        let product: ProjectProductSourceModel
        do {
            product = try productSourceCodec.decode(package.productSource)
        } catch {
            throw ProjectControllerError(
                code: .productSourceFailed,
                message: "Initial Product source decoding failed: \(error)."
            )
        }
        let cadDocument: CADDocument?
        do {
            cadDocument = try package.cadSource.map(cadSourceCodec.decode)
        } catch {
            throw ProjectControllerError(
                code: .cadSourceFailed,
                message: "Initial CAD source decoding failed: \(error)."
            )
        }
        let document = try assembleDocument(
            package: package,
            product: product,
            cadDocument: cadDocument,
            objectRegistry: objectRegistry
        )
        let source: ProjectSourceModel
        do {
            source = try projector.project(document)
            try source.validate()
        } catch {
            throw ProjectControllerError(
                code: .projectionFailed,
                message: "Initial project evaluation-source projection failed: \(error)."
            )
        }
        guard source.id == package.documentID else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Initial Product identity and evaluation projection differ."
            )
        }
        return (document, source)
    }

    private static func assembleDocument(
        package: ProjectPackageDocument,
        product: ProjectProductSourceModel,
        cadDocument: CADDocument?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> DesignDocument {
        guard product.projectID == package.documentID else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Package and Product document identities differ."
            )
        }
        let runtimeCADDocument: CADDocument
        if let cadDocument {
            guard cadDocument.id == product.documentID,
                cadDocument.units == product.units,
                cadDocument.metadata.name == product.name
            else {
                throw ProjectControllerError(
                    code: .sourceMismatch,
                    message: "Product and CAD document identity, units, or name differ."
                )
            }
            runtimeCADDocument = cadDocument
        } else {
            runtimeCADDocument = CADDocument(
                id: product.documentID,
                units: product.units,
                metadata: DocumentMetadata(name: product.name)
            )
        }
        let document = DesignDocument(
            cadDocument: runtimeCADDocument,
            modelingSettings: product.modelingSettings,
            productMetadata: product.productMetadata,
            authoredMeshAssets: package.authoredMeshAssets
        )
        do {
            _ = try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "Decoded project sources are semantically invalid: \(error)."
            )
        }
        return document
    }
}

private enum HistoryDirection {
    case undo
    case redo

    var operationName: String {
        switch self {
        case .undo:
            return "undo"
        case .redo:
            return "redo"
        }
    }
}

private struct StagedCommandResults: Sendable {
    let commandResults: [CommandExecutionResult]
    let geometrySourceCommandResults: [GeometrySourceCommandResult]
    var automationExecution: AutomationBatchExecution?

    var didMutateAuthoredMesh: Bool {
        geometrySourceCommandResults.contains { result in
            switch result {
            case .authoredMeshEdit, .makeEditable:
                return result.didMutate
            case .representationSelection:
                return false
            }
        }
    }
}

private struct PreparedProjectSourceMutation: Sendable {
    let basePublicationSequence: UInt64
    let source: PreparedEditorSourceTransaction<StagedCommandResults>
    let package: ProjectPackageDocument
    let evaluationSource: ProjectSourceModel
    let evaluation: EvaluatedProjectSnapshot
}

private struct PreparedProjectInteractionMutation: Sendable {
    let basePublicationSequence: UInt64
    let baseSessionSnapshot: EditorSessionTransactionSnapshot
    let proposedSelection: SelectionModel
    let proposedWorkspaceState: WorkspaceState
    let wouldPublish: Bool
    let automationExecution: AutomationBatchExecution?
}
