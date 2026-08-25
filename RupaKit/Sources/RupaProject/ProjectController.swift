import Foundation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaProjectPackage
import SwiftCAD

public actor ProjectController: ProjectOperating {
    private var session: EditorSession
    private var packageDocument: ProjectPackageDocument
    private var evaluationSource: ProjectSourceModel
    private var evaluation: EvaluatedProjectSnapshot?
    private var publicationSequence: UInt64
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
            DefaultGeometrySourceCommandApplier()
    ) throws {
        let initial = try Self.makeInitialState(
            document: document,
            projector: projector,
            productSourceCodec: productSourceCodec,
            cadSourceCodec: cadSourceCodec,
            packageValidator: packageValidator
        )
        session = EditorSession(document: document)
        packageDocument = initial.package
        evaluationSource = initial.evaluationSource
        evaluation = nil
        publicationSequence = 0
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
            DefaultGeometrySourceCommandApplier()
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
            cadSourceCodec: cadSourceCodec
        )
        session = EditorSession(document: initial.document)
        packageDocument = package
        evaluationSource = initial.evaluationSource
        evaluation = nil
        publicationSequence = 0
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
            document: session.document,
            package: packageDocument,
            documentGeneration: session.generation,
            transactionRevision: session.transactionRevision,
            publicationSequence: publicationSequence,
            isDirty: session.isDirty,
            selection: session.selection,
            workspaceState: session.workspaceState,
            evaluationSource: evaluationSource,
            cadInteraction: session.currentEvaluation,
            evaluation: try currentEvaluation()
        )
    }

    public func evaluateCurrent() async throws -> EvaluatedProjectSnapshot {
        let baseRevision = session.transactionRevision
        let stagedEvaluation = try await evaluate(
            document: session.document,
            source: evaluationSource,
            purpose: .presentation,
            revision: baseRevision,
            reusing: session.currentEvaluation
        )
        try requireTransactionRevision(baseRevision)
        let nextPublicationSequence = try advancedPublicationSequence()
        evaluation = stagedEvaluation
        publicationSequence = nextPublicationSequence
        return stagedEvaluation
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
        _ transaction: ProjectSourceTransaction
    ) async throws -> ProjectSourceCommitResult {
        try requireTransactionRevision(transaction.expectedTransactionRevision)
        try await validateMakeEditableEvaluationBindings(in: transaction)

        let prepared: PreparedEditorSourceTransaction<StagedCommandResults>
        do {
            prepared = try session.prepareIsolatedSourceTransaction(
                commandName: transaction.name,
                expectedTransactionRevision: transaction.expectedTransactionRevision
            ) { stagedSession in
                try stagedSession.withSourceCommandGroup(named: transaction.name) {
                    groupedSession in
                    let commandResults = try transaction.commands.map { command in
                        try groupedSession.execute(command)
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
                        geometrySourceCommandResults: geometrySourceCommandResults
                    )
                }
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
        let stagedProductSource = try await encodeProductSource(prepared.stagedDocument)
        let stagedCADSource = try await encodeCADSourceIfAuthoritative(
            prepared.stagedDocument
        )
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
        let reconstructed = try await reconstructState(from: stagedPackage)
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

        do {
            try requireTransactionRevision(prepared.baseTransactionRevision)
            let nextPublicationSequence = try advancedPublicationSequence()
            try session.commitPreparedSourceTransaction(prepared)
            publicationSequence = nextPublicationSequence
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        packageDocument = stagedPackage
        evaluationSource = reconstructed.evaluationSource
        evaluation = stagedEvaluation
        return ProjectSourceCommitResult(
            baseTransactionRevision: prepared.baseTransactionRevision,
            transactionRevision: prepared.proposedTransactionRevision,
            documentGeneration: prepared.proposedGeneration,
            document: prepared.stagedDocument,
            package: stagedPackage,
            evaluation: stagedEvaluation,
            commandResults: prepared.value.commandResults,
            geometrySourceCommandResults: prepared.value.geometrySourceCommandResults
        )
    }

    public func load(
        from url: URL,
        expectedTransactionRevision: DocumentTransactionRevision
    ) async throws -> ProjectStateSnapshot {
        try requireTransactionRevision(expectedTransactionRevision)
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
        try requireTransactionRevision(expectedTransactionRevision)
        let nextPublicationSequence = try advancedPublicationSequence()

        session = EditorSession(
            document: reconstructed.document,
            transactionRevision: loadedRevision
        )
        packageDocument = loadedPackage
        evaluationSource = reconstructed.evaluationSource
        evaluation = loadedEvaluation
        publicationSequence = nextPublicationSequence
        return ProjectStateSnapshot(
            document: reconstructed.document,
            package: loadedPackage,
            documentGeneration: session.generation,
            transactionRevision: loadedRevision,
            publicationSequence: publicationSequence,
            isDirty: session.isDirty,
            selection: session.selection,
            workspaceState: session.workspaceState,
            evaluationSource: reconstructed.evaluationSource,
            cadInteraction: session.currentEvaluation,
            evaluation: loadedEvaluation
        )
    }

    /// Saves synchronously inside actor isolation so no source transaction can
    /// pass the revision check before the atomic file replacement completes.
    public func save(
        to url: URL,
        expectedTransactionRevision: DocumentTransactionRevision
    ) throws -> ProjectPackageSaveResult {
        try requireTransactionRevision(expectedTransactionRevision)
        do {
            let result = try packageWriter.save(packageDocument, to: url)
            packageDocument = result.document
            return result
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Project package save failed: \(error)."
            )
        }
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
            cadDocument: cadDocument
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
        packageValidator: any ProjectPackageValidating
    ) throws -> (package: ProjectPackageDocument, evaluationSource: ProjectSourceModel) {
        do {
            _ = try document.validate()
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
            cadSourceCodec: cadSourceCodec
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
        cadSourceCodec: any ProjectCADSourceCoding
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
            cadDocument: cadDocument
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
        cadDocument: CADDocument?
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
            _ = try document.validate()
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "Decoded project sources are semantically invalid: \(error)."
            )
        }
        return document
    }
}

private struct StagedCommandResults: Sendable {
    let commandResults: [CommandExecutionResult]
    let geometrySourceCommandResults: [GeometrySourceCommandResult]

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
