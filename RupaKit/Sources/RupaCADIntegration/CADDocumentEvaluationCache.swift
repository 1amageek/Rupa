import RupaCoreTypes
import RupaGeometry
import SwiftCAD
import Synchronization

/// Retains the most recent immutable CAD evaluation per document and configuration.
public final class CADDocumentEvaluationCache: Sendable {
    package struct CachedMeshSource: Sendable {
        package let mesh: Mesh
        package let source: MeshSource
    }

    package struct Publication: Sendable {
        package let documentID: DocumentID
        package let sourceRevision: DocumentTransactionRevision
        /// The CAD document evaluated at `sourceRevision`; a second publication at that revision
        /// must carry an equal document.
        package let sourceDocument: CADDocument
        package let configuration: CADGeometryEvaluationConfiguration
        package let evaluatedDocument: EvaluatedDocument
        package let meshSourcesByBodyID: [BodyID: CachedMeshSource]
    }

    package struct Lookup: Sendable {
        package let evaluatedDocument: EvaluatedDocument?
        package let isExactRevision: Bool
        package let meshSourcesByBodyID: [BodyID: CachedMeshSource]

        package static let empty = Lookup(
            evaluatedDocument: nil,
            isExactRevision: false,
            meshSourcesByBodyID: [:]
        )
    }

    private struct Scope: Hashable, Sendable {
        let documentID: DocumentID
        let configuration: CADGeometryEvaluationConfiguration
    }

    private struct Entry: Sendable {
        let sourceRevision: DocumentTransactionRevision
        let sourceDocument: CADDocument
        let evaluatedDocument: EvaluatedDocument
        var meshSourcesByBodyID: [BodyID: CachedMeshSource]
    }

    private struct State: Sendable {
        var entries: [Scope: Entry] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    /// Seeds the cache with an already validated immutable evaluation.
    public func seed(
        validatedDocument: ValidatedCADDocument,
        evaluatedDocument: EvaluatedDocument,
        sourceRevision: DocumentTransactionRevision,
        configuration: CADGeometryEvaluationConfiguration
    ) throws {
        do {
            try configuration.validate()
        } catch {
            throw CADIntegrationError(
                code: .invalidConfiguration,
                message: "CAD geometry evaluation configuration is invalid: \(error)"
            )
        }
        guard validatedDocument.tolerance == configuration.tolerance,
              evaluatedDocument.document.id == validatedDocument.document.id,
              evaluatedDocument.configuration.tolerance == configuration.tolerance,
              evaluatedDocument.configuration.tessellationOptions
                == configuration.tessellationOptions,
              Set(evaluatedDocument.meshes.keys)
                == Set(evaluatedDocument.brep.bodies.keys) else {
            throw CADIntegrationError(
                code: .invalidEvaluationResult,
                message: "Seeded CAD evaluation does not match the source document or evaluation configuration."
            )
        }

        // The evaluation must be of this very document: compared by value, which a document
        // and the evaluation made from it answer without hashing either.
        guard let evaluatedCache = evaluatedDocument.caches.brep,
              evaluatedCache.tolerance == configuration.tolerance,
              evaluatedDocument.document == validatedDocument.document else {
            throw CADIntegrationError(
                code: .invalidEvaluationResult,
                message: "Seeded CAD evaluation was produced from different source content."
            )
        }

        try publish(
            documentID: validatedDocument.document.id,
            sourceRevision: sourceRevision,
            sourceDocument: validatedDocument.document,
            configuration: configuration,
            evaluatedDocument: evaluatedDocument,
            meshSourcesByBodyID: [:]
        )
    }

    /// The entry for `document`'s scope; one at `sourceRevision` must hold an equal document.
    package func lookup(
        document: CADDocument,
        sourceRevision: DocumentTransactionRevision,
        configuration: CADGeometryEvaluationConfiguration
    ) throws -> Lookup {
        let scope = Scope(
            documentID: document.id,
            configuration: configuration
        )
        guard let entry = state.withLock({ $0.entries[scope] }) else {
            return .empty
        }
        if entry.sourceRevision == sourceRevision {
            guard entry.sourceDocument == document else {
                throw CADIntegrationError(
                    code: .sourceRevisionConflict,
                    message: "CAD document \(document.id.description) revision "
                        + "\(sourceRevision.value) identifies different source content."
                )
            }
            return Lookup(
                evaluatedDocument: entry.evaluatedDocument,
                isExactRevision: true,
                meshSourcesByBodyID: entry.meshSourcesByBodyID
            )
        }
        guard entry.sourceRevision < sourceRevision else {
            return .empty
        }
        return Lookup(
            evaluatedDocument: entry.evaluatedDocument,
            isExactRevision: false,
            meshSourcesByBodyID: entry.meshSourcesByBodyID
        )
    }

    package func publish(
        documentID: DocumentID,
        sourceRevision: DocumentTransactionRevision,
        sourceDocument: CADDocument,
        configuration: CADGeometryEvaluationConfiguration,
        evaluatedDocument: EvaluatedDocument,
        meshSourcesByBodyID: [BodyID: CachedMeshSource]
    ) throws {
        try publish([
            Publication(
                documentID: documentID,
                sourceRevision: sourceRevision,
                sourceDocument: sourceDocument,
                configuration: configuration,
                evaluatedDocument: evaluatedDocument,
                meshSourcesByBodyID: meshSourcesByBodyID
            ),
        ])
    }

    /// Validates and publishes every source from one provider transaction atomically.
    package func publish(_ publications: [Publication]) throws {
        guard !publications.isEmpty else {
            return
        }
        try state.withLock { state in
            var stagedEntries: [Scope: Entry] = [:]
            stagedEntries.reserveCapacity(publications.count)
            for publication in publications {
                let scope = Scope(
                    documentID: publication.documentID,
                    configuration: publication.configuration
                )
                let currentEntry = stagedEntries[scope] ?? state.entries[scope]
                if var currentEntry {
                    guard currentEntry.sourceRevision <= publication.sourceRevision else {
                        continue
                    }
                    if currentEntry.sourceRevision == publication.sourceRevision {
                        guard currentEntry.sourceDocument
                                == publication.sourceDocument else {
                            throw CADIntegrationError(
                                code: .sourceRevisionConflict,
                                message: "CAD document \(publication.documentID.description) revision "
                                    + "\(publication.sourceRevision.value) identifies different source content."
                            )
                        }
                        currentEntry.meshSourcesByBodyID.merge(
                            publication.meshSourcesByBodyID,
                            uniquingKeysWith: { existing, _ in existing }
                        )
                        stagedEntries[scope] = currentEntry
                        continue
                    }
                }
                stagedEntries[scope] = Entry(
                    sourceRevision: publication.sourceRevision,
                    sourceDocument: publication.sourceDocument,
                    evaluatedDocument: publication.evaluatedDocument,
                    meshSourcesByBodyID: publication.meshSourcesByBodyID
                )
            }
            for (scope, entry) in stagedEntries {
                state.entries[scope] = entry
            }
        }
    }
}
