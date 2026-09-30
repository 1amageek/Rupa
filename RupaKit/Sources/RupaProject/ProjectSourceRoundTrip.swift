import Foundation
import RupaCore
import RupaCoreTypes
import RupaProjectModel
import RupaProjectPackage
import SwiftCAD

/// The one owner of turning a document into package sources and reading them back.
///
/// Initial documents, source edits and history steps all stage through `stage`: the candidate is
/// projected once, encoded into Product, CAD and Authored-Mesh sources, validated as a package,
/// decoded and assembled back, and the assembled document must equal the candidate. Only then is
/// anything published, so a codec that loses or alters a value refuses the edit instead of writing
/// a package that cannot reopen the document. A package read from disk goes through `read`.
///
/// Each step runs once per candidate. The candidate is validated once (the store's validation
/// when the caller holds it), and since the assembled document must equal it, the assembled
/// document is neither validated nor projected again: the candidate's validation and projection
/// stand for it. Equality is member-wise, so no source fingerprint is computed to prove the round
/// trip.
struct ProjectSourceRoundTrip: Sendable {
    /// Where a candidate comes from, for the messages of its failures.
    enum Context: String, Sendable {
        case initial = "Initial"
        case edit = "Staged"
        case history = "Staged history"
    }

    /// A candidate whose package reproduces it.
    struct Staged: Sendable {
        let package: ProjectPackageDocument
        /// The document assembled from `package`, equal to the candidate.
        let document: DesignDocument
        /// The candidate's one validation (the caller's when given), which also holds for `document`.
        let validatedDocument: ValidatedDesignDocument
        let evaluationSource: ProjectSourceModel
    }

    /// A document read from a package.
    struct Read: Sendable {
        let validatedDocument: ValidatedDesignDocument
        let evaluationSource: ProjectSourceModel
        let retiredObjectProperties: [RetiredObjectProperty]

        var document: DesignDocument { validatedDocument.document }
    }

    let projector: any ProjectSourceProjecting
    let productSourceCodec: any ProjectProductSourceCoding
    let cadSourceCodec: any ProjectCADSourceCoding
    let packageValidator: any ProjectPackageValidating
    let objectRegistry: ObjectTypeRegistry

    /// Stages `document` into package sources and proves they reproduce it.
    ///
    /// `validated` is the caller's validation of `document` (the store's, for an edit); `base` is
    /// the package whose sources are replaced, or nil for a new package. `collectingGarbage` drops
    /// source blobs nothing references any more.
    func stage(
        _ document: DesignDocument,
        validated: ValidatedDesignDocument?,
        into base: ProjectPackageDocument?,
        collectingGarbage: Bool,
        context: Context
    ) throws -> Staged {
        let candidateValidation: ValidatedDesignDocument
        if let validated {
            candidateValidation = validated
        } else {
            do {
                candidateValidation = try document.validate(objectRegistry: objectRegistry)
            } catch {
                throw ProjectControllerError(
                    code: .sourceInvalid,
                    message: "\(context.rawValue) DesignDocument validation failed: \(error)."
                )
            }
        }
        let source = try project(document, context: context)
        if let base {
            guard source.id == base.documentID else {
                throw ProjectControllerError(
                    code: .sourceMismatch,
                    message: "A source transaction cannot change the project identity."
                )
            }
        }
        try Task.checkCancellation()
        let productSource: ProjectPackageProductSource
        do {
            productSource = try productSourceCodec.encode(document)
        } catch {
            throw ProjectControllerError(
                code: .productSourceFailed,
                message: "\(context.rawValue) Product source encoding failed: \(error)."
            )
        }
        let cadSource: ProjectPackageCADSource?
        do {
            cadSource = document.hasAuthoritativeCADSource ? try cadSourceCodec.encode(document.cadDocument) : nil
        } catch {
            throw ProjectControllerError(
                code: .cadSourceFailed,
                message: "\(context.rawValue) CAD source encoding failed: \(error)."
            )
        }
        try Task.checkCancellation()
        let package: ProjectPackageDocument
        do {
            if let base {
                let replaced = try base.replacingSources(
                    documentID: source.id,
                    product: productSource,
                    cad: cadSource,
                    authoredMeshAssets: document.authoredMeshAssets
                )
                package = collectingGarbage ? replaced.garbageCollectingUnreferencedSourceBlobs() : replaced
            } else {
                package = try ProjectPackageDocument(
                    documentID: source.id,
                    productSource: productSource,
                    cadSource: cadSource,
                    authoredMeshAssets: document.authoredMeshAssets
                )
            }
            try packageValidator.validateForSave(package)
        } catch {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "\(context.rawValue) project package validation failed: \(error)."
            )
        }
        try Task.checkCancellation()
        let assembled = try decode(package, context: context)
        // A package this controller just encoded carries no document older than the schema, so a
        // retired value means the encoder and the registry disagree (`RupaProject/DESIGN.md`).
        guard assembled.retiredObjectProperties.isEmpty else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "\(context.rawValue) project sources retired \(assembled.retiredObjectProperties.count) "
                    + "stored object property value(s) the object schema no longer declares."
            )
        }
        try requireReproduces(
            document,
            reconstructed: assembled.document,
            includesCADSource: cadSource != nil,
            context: context
        )
        // Equal to the validated candidate, the assembled document validates as it does. Without a
        // CAD source the assembled CAD document is rebuilt from the Product identity alone, so that
        // document is validated itself.
        if cadSource == nil {
            _ = try validate(assembled.document)
        }
        return Staged(
            package: package,
            document: assembled.document,
            validatedDocument: candidateValidation,
            evaluationSource: source
        )
    }

    /// Decodes, assembles and projects a package, validating the document once.
    func read(_ package: ProjectPackageDocument) throws -> Read {
        let assembled = try decode(package, context: .initial)
        let validatedDocument = try validate(assembled.document)
        let source = try project(validatedDocument.document, context: .initial)
        guard source.id == package.documentID else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "Product identity and evaluation projection differ."
            )
        }
        return Read(
            validatedDocument: validatedDocument,
            evaluationSource: source,
            retiredObjectProperties: assembled.retiredObjectProperties
        )
    }

    private func project(_ document: DesignDocument, context: Context) throws -> ProjectSourceModel {
        do {
            let source = try projector.project(document)
            try source.validate()
            return source
        } catch {
            throw ProjectControllerError(
                code: .projectionFailed,
                message: "\(context.rawValue) project evaluation-source projection failed: \(error)."
            )
        }
    }

    private func decode(
        _ package: ProjectPackageDocument,
        context: Context
    ) throws -> (document: DesignDocument, retiredObjectProperties: [RetiredObjectProperty]) {
        let product: ProjectProductSourceModel
        do {
            product = try productSourceCodec.decode(package.productSource)
        } catch let error as ProjectControllerError {
            throw error
        } catch {
            throw ProjectControllerError(
                code: .productSourceFailed,
                message: "\(context.rawValue) Product source decoding failed: \(error)."
            )
        }
        let cadDocument: CADDocument?
        do {
            cadDocument = try package.cadSource.map(cadSourceCodec.decode)
        } catch {
            throw ProjectControllerError(
                code: .cadSourceFailed,
                message: "\(context.rawValue) CAD source decoding failed: \(error)."
            )
        }
        try Task.checkCancellation()
        return try assemble(package: package, product: product, cadDocument: cadDocument)
    }

    private func assemble(
        package: ProjectPackageDocument,
        product: ProjectProductSourceModel,
        cadDocument: CADDocument?
    ) throws -> (document: DesignDocument, retiredObjectProperties: [RetiredObjectProperty]) {
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
        // A project saved by an earlier object schema can carry a property value the registry no
        // longer declares. That value is stale metadata, not an invalid source, so it is dropped
        // here rather than refused by validation below, and returned for the caller to report.
        var productMetadata = product.productMetadata
        let retired = productMetadata.pruneUndeclaredObjectProperties(objectRegistry: objectRegistry)
        let document = DesignDocument(
            cadDocument: runtimeCADDocument,
            modelingSettings: product.modelingSettings,
            productMetadata: productMetadata,
            authoredMeshAssets: package.authoredMeshAssets
        )
        return (document, retired)
    }

    private func validate(_ document: DesignDocument) throws -> ValidatedDesignDocument {
        do {
            return try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "Decoded project sources are semantically invalid: \(error)."
            )
        }
    }

    /// The assembled document must equal the candidate in every value its sources carry: the
    /// Product model, the CAD document when a CAD source was written (member-wise, envelope and
    /// revisions included), and the Authored-Mesh assets.
    private func requireReproduces(
        _ document: DesignDocument,
        reconstructed: DesignDocument,
        includesCADSource: Bool,
        context: Context
    ) throws {
        let product: ProjectProductSourceModel
        let reconstructedProduct: ProjectProductSourceModel
        do {
            product = try ProjectProductSourceModel(document: document)
            reconstructedProduct = try ProjectProductSourceModel(document: reconstructed)
        } catch {
            throw ProjectControllerError(
                code: .sourceInvalid,
                message: "\(context.rawValue) project Product authority could not be read: \(error)."
            )
        }
        guard product == reconstructedProduct else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "\(context.rawValue) project sources do not reproduce the Product authority."
            )
        }
        guard document.hasAuthoritativeCADSource == includesCADSource,
              !includesCADSource || document.cadDocument == reconstructed.cadDocument else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "\(context.rawValue) project sources do not reproduce the CAD authority."
            )
        }
        guard document.authoredMeshAssets == reconstructed.authoredMeshAssets else {
            throw ProjectControllerError(
                code: .sourceMismatch,
                message: "\(context.rawValue) project sources do not reproduce the Authored-Mesh authority."
            )
        }
    }
}
