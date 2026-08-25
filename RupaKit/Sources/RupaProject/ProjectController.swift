import Foundation
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaProjectPackage
import SwiftCAD

public actor ProjectController {
    private var session: EditorSession
    private var packageDocument: ProjectPackageDocument
    private var evaluationSource: ProjectSourceModel
    private var evaluation: EvaluatedProjectSnapshot?
    private let evaluator: any ProjectEvaluating
    private let projector: any ProjectSourceProjecting
    private let productSourceCodec: any ProjectProductSourceCoding
    private let cadSourceCodec: any ProjectCADSourceCoding
    private let packageReader: any ProjectPackageReading
    private let packageWriter: any ProjectPackageWriting
    private let packageValidator: any ProjectPackageValidating

    public init(
        document: DesignDocument,
        evaluator: any ProjectEvaluating,
        projector: any ProjectSourceProjecting,
        productSourceCodec: any ProjectProductSourceCoding = JSONProjectProductSourceCodec(),
        cadSourceCodec: any ProjectCADSourceCoding = JSONProjectCADSourceCodec(),
        packageReader: any ProjectPackageReading = ProjectPackageStore(),
        packageWriter: any ProjectPackageWriting = ProjectPackageStore(),
        packageValidator: any ProjectPackageValidating = ProjectPackageStore()
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
        self.evaluator = evaluator
        self.projector = projector
        self.productSourceCodec = productSourceCodec
        self.cadSourceCodec = cadSourceCodec
        self.packageReader = packageReader
        self.packageWriter = packageWriter
        self.packageValidator = packageValidator
    }

    public init(
        package: ProjectPackageDocument,
        evaluator: any ProjectEvaluating,
        projector: any ProjectSourceProjecting,
        productSourceCodec: any ProjectProductSourceCoding = JSONProjectProductSourceCodec(),
        cadSourceCodec: any ProjectCADSourceCoding = JSONProjectCADSourceCodec(),
        packageReader: any ProjectPackageReading = ProjectPackageStore(),
        packageWriter: any ProjectPackageWriting = ProjectPackageStore(),
        packageValidator: any ProjectPackageValidating = ProjectPackageStore()
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
        self.evaluator = evaluator
        self.projector = projector
        self.productSourceCodec = productSourceCodec
        self.cadSourceCodec = cadSourceCodec
        self.packageReader = packageReader
        self.packageWriter = packageWriter
        self.packageValidator = packageValidator
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
            transactionRevision: session.transactionRevision,
            evaluation: try currentEvaluation()
        )
    }

    public func evaluateCurrent() async throws -> EvaluatedProjectSnapshot {
        let baseRevision = session.transactionRevision
        let stagedEvaluation = try await evaluate(
            source: evaluationSource,
            revision: baseRevision
        )
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
            stagedPackage = try packageDocument.replacingSources(
                documentID: stagedEvaluationSource.id,
                product: stagedProductSource,
                cad: stagedCADSource,
                authoredMeshAssets: prepared.stagedDocument.authoredMeshAssets
            )
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
            source: reconstructed.evaluationSource,
            revision: prepared.proposedTransactionRevision
        )

        do {
            try requireTransactionRevision(prepared.baseTransactionRevision)
            try session.commitPreparedSourceTransaction(prepared)
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
            source: reconstructed.evaluationSource,
            revision: loadedRevision
        )
        try requireTransactionRevision(expectedTransactionRevision)

        session = EditorSession(
            document: reconstructed.document,
            transactionRevision: loadedRevision
        )
        packageDocument = loadedPackage
        evaluationSource = reconstructed.evaluationSource
        evaluation = loadedEvaluation
        return ProjectStateSnapshot(
            document: reconstructed.document,
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
        source: ProjectSourceModel,
        revision: DocumentTransactionRevision
    ) async throws -> EvaluatedProjectSnapshot {
        let evaluator = self.evaluator
        do {
            return try await Self.performDetached {
                try Task.checkCancellation()
                let result = try evaluator.evaluate(
                    project: source,
                    purpose: .presentation,
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

    private func projectError(for error: EditorError) -> ProjectControllerError {
        if error.code == .documentTransactionRevisionMismatch {
            return ProjectControllerError(code: .revisionConflict, message: error.message)
        }
        return ProjectControllerError(code: .transactionInvalid, message: error.message)
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
