import Foundation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaProjectPackage

public actor ProjectController {
    private var session: EditorSession
    private var packageDocument: ProjectPackageDocument
    private var evaluation: EvaluatedProjectSnapshot?
    private let evaluator: any ProjectEvaluating
    private let projector: any ProjectSourceProjecting
    private let cadSourceCodec: any ProjectCADSourceCoding
    private let packageReader: any ProjectPackageReading
    private let packageWriter: any ProjectPackageWriting

    public init(
        document: DesignDocument,
        evaluator: any ProjectEvaluating,
        projector: any ProjectSourceProjecting,
        cadSourceCodec: any ProjectCADSourceCoding,
        packageReader: any ProjectPackageReading = ProjectPackageStore(),
        packageWriter: any ProjectPackageWriting = ProjectPackageStore()
    ) throws {
        let initialPackage = try Self.makePackage(
            document: document,
            projector: projector,
            cadSourceCodec: cadSourceCodec
        )
        self.session = EditorSession(document: document)
        self.packageDocument = initialPackage
        self.evaluation = nil
        self.evaluator = evaluator
        self.projector = projector
        self.cadSourceCodec = cadSourceCodec
        self.packageReader = packageReader
        self.packageWriter = packageWriter
    }

    public init(
        package: ProjectPackageDocument,
        evaluator: any ProjectEvaluating,
        projector: any ProjectSourceProjecting,
        cadSourceCodec: any ProjectCADSourceCoding,
        packageReader: any ProjectPackageReading = ProjectPackageStore(),
        packageWriter: any ProjectPackageWriting = ProjectPackageStore()
    ) throws {
        let document = try Self.decodeAndValidate(
            package: package,
            projector: projector,
            cadSourceCodec: cadSourceCodec
        )
        self.session = EditorSession(document: document)
        self.packageDocument = package
        self.evaluation = nil
        self.evaluator = evaluator
        self.projector = projector
        self.cadSourceCodec = cadSourceCodec
        self.packageReader = packageReader
        self.packageWriter = packageWriter
    }

    public func currentDocument() -> DesignDocument {
        session.document
    }

    public func currentPackage() -> ProjectPackageDocument {
        packageDocument
    }

    public func currentSource() -> ProjectSourceModel {
        packageDocument.source
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
            transactionRevision: session.transactionRevision,
            evaluation: try currentEvaluation()
        )
    }

    public func evaluateCurrent() async throws -> EvaluatedProjectSnapshot {
        let baseRevision = session.transactionRevision
        let source = packageDocument.source
        let stagedEvaluation = try await evaluate(source: source, revision: baseRevision)
        try requireTransactionRevision(baseRevision)
        evaluation = stagedEvaluation
        return stagedEvaluation
    }

    public func commit(
        _ transaction: ProjectSourceTransaction
    ) async throws -> ProjectSourceCommitResult {
        try requireTransactionRevision(transaction.expectedTransactionRevision)

        let prepared: PreparedEditorSourceTransaction<[CommandExecutionResult]>
        do {
            prepared = try session.prepareIsolatedSourceTransaction(
                commandName: transaction.name,
                expectedTransactionRevision: transaction.expectedTransactionRevision
            ) { stagedSession in
                try stagedSession.withSourceCommandGroup(named: transaction.name) {
                    groupedSession in
                    try transaction.commands.map { command in
                        try groupedSession.execute(command)
                    }
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

        let stagedCADSource = try await encodeCADSource(prepared.stagedDocument)
        let stagedSource = try await projectSource(prepared.stagedDocument)
        guard stagedSource.id == packageDocument.source.id else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "A source transaction cannot change the project identity."
            )
        }
        let stagedEvaluation = try await evaluate(
            source: stagedSource,
            revision: prepared.proposedTransactionRevision
        )
        let stagedPackage: ProjectPackageDocument
        do {
            stagedPackage = try packageDocument.replacingSources(
                project: stagedSource,
                cad: stagedCADSource
            )
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Staged project package validation failed: \(error)."
            )
        }

        do {
            try requireTransactionRevision(prepared.baseTransactionRevision)
            try session.commitPreparedSourceTransaction(prepared)
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        packageDocument = stagedPackage
        evaluation = stagedEvaluation
        return ProjectSourceCommitResult(
            baseTransactionRevision: prepared.baseTransactionRevision,
            transactionRevision: prepared.proposedTransactionRevision,
            documentGeneration: prepared.proposedGeneration,
            document: prepared.stagedDocument,
            package: stagedPackage,
            evaluation: stagedEvaluation,
            commandResults: prepared.value
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
            loadedPackage = try await Task.detached(priority: nil) {
                try Task.checkCancellation()
                let package = try reader.load(from: url)
                try Task.checkCancellation()
                return package
            }.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Project package load failed: \(error)."
            )
        }

        let loadedDocument = try await decodeCADSource(loadedPackage.cadSource)
        let projectedSource = try await projectSource(loadedDocument)
        guard projectedSource == loadedPackage.source else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Loaded CAD and universal project sources do not match."
            )
        }
        let loadedRevision: DocumentTransactionRevision
        do {
            loadedRevision = try expectedTransactionRevision.advanced()
        } catch let error as EditorError {
            throw projectError(for: error)
        }
        let loadedEvaluation = try await evaluate(
            source: projectedSource,
            revision: loadedRevision
        )
        try requireTransactionRevision(expectedTransactionRevision)

        session = EditorSession(
            document: loadedDocument,
            transactionRevision: loadedRevision
        )
        packageDocument = loadedPackage
        evaluation = loadedEvaluation
        return ProjectStateSnapshot(
            document: loadedDocument,
            package: loadedPackage,
            transactionRevision: loadedRevision,
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

    private func encodeCADSource(
        _ document: DesignDocument
    ) async throws -> ProjectPackageCADSource {
        let codec = cadSourceCodec
        do {
            return try await Task.detached(priority: nil) {
                try Task.checkCancellation()
                let source = try codec.encode(document)
                try Task.checkCancellation()
                return source
            }.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .cadSourceFailed,
                message: "CAD source encoding failed: \(error)."
            )
        }
    }

    private func decodeCADSource(
        _ source: ProjectPackageCADSource
    ) async throws -> DesignDocument {
        let codec = cadSourceCodec
        do {
            return try await Task.detached(priority: nil) {
                try Task.checkCancellation()
                let document = try codec.decode(source)
                _ = try document.validate()
                try Task.checkCancellation()
                return document
            }.value
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
            return try await Task.detached(priority: nil) {
                try Task.checkCancellation()
                let source = try projector.project(document)
                try source.validate()
                try Task.checkCancellation()
                return source
            }.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProjectControllerError(
                code: .projectionFailed,
                message: "CAD project source projection failed: \(error)."
            )
        }
    }

    private func evaluate(
        source: ProjectSourceModel,
        revision: DocumentTransactionRevision
    ) async throws -> EvaluatedProjectSnapshot {
        let evaluator = self.evaluator
        do {
            return try await Task.detached(priority: nil) {
                try Task.checkCancellation()
                let result = try evaluator.evaluate(
                    project: source,
                    purpose: .presentation,
                    revision: revision
                )
                try Task.checkCancellation()
                return result
            }.value
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

    private func projectError(for error: EditorError) -> ProjectControllerError {
        if error.code == .documentTransactionRevisionMismatch {
            return ProjectControllerError(code: .revisionConflict, message: error.message)
        }
        return ProjectControllerError(code: .transactionInvalid, message: error.message)
    }

    private static func makePackage(
        document: DesignDocument,
        projector: any ProjectSourceProjecting,
        cadSourceCodec: any ProjectCADSourceCoding
    ) throws -> ProjectPackageDocument {
        do {
            _ = try document.validate()
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "Initial CAD document validation failed: \(error)."
            )
        }
        let source: ProjectSourceModel
        do {
            source = try projector.project(document)
            try source.validate()
        } catch {
            throw ProjectControllerError(
                code: .projectionFailed,
                message: "Initial project source projection failed: \(error)."
            )
        }
        let cadSource: ProjectPackageCADSource
        do {
            cadSource = try cadSourceCodec.encode(document)
        } catch {
            throw ProjectControllerError(
                code: .cadSourceFailed,
                message: "Initial CAD source encoding failed: \(error)."
            )
        }
        do {
            return try ProjectPackageDocument(source: source, cadSource: cadSource)
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Initial project package creation failed: \(error)."
            )
        }
    }

    private static func decodeAndValidate(
        package: ProjectPackageDocument,
        projector: any ProjectSourceProjecting,
        cadSourceCodec: any ProjectCADSourceCoding
    ) throws -> DesignDocument {
        let document: DesignDocument
        do {
            document = try cadSourceCodec.decode(package.cadSource)
            _ = try document.validate()
        } catch {
            throw ProjectControllerError(
                code: .cadSourceFailed,
                message: "Initial CAD source decoding failed: \(error)."
            )
        }
        let projectedSource: ProjectSourceModel
        do {
            projectedSource = try projector.project(document)
            try projectedSource.validate()
        } catch {
            throw ProjectControllerError(
                code: .projectionFailed,
                message: "Initial project source projection failed: \(error)."
            )
        }
        guard projectedSource == package.source else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "CAD and universal project sources do not match."
            )
        }
        return document
    }
}
