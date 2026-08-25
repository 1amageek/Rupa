import Foundation
import RupaCore
import RupaCoreTypes
import RupaProjectModel
import SwiftCAD

/// Semantic identities for the persisted Product, optional CAD, and Authored-Mesh sources.
struct ProjectSourceAuthoritySnapshot: Equatable, Sendable {
    let product: ProjectProductSourceModel
    let cad: ProjectCADSourceAuthorityIdentity?
    let authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset]

    init(
        document: DesignDocument,
        includesCADSource: Bool
    ) throws {
        product = try ProjectProductSourceModel(document: document)
        cad = includesCADSource
            ? try ProjectCADSourceAuthorityIdentity(document: document)
            : nil
        authoredMeshAssets = document.authoredMeshAssets
    }
}

/// Completes Swift-CAD's semantic content fingerprint with persisted envelope
/// and mutation-revision state that the fingerprint intentionally excludes.
struct ProjectCADSourceAuthorityIdentity: Equatable, Sendable {
    let documentID: DocumentID
    let metadataName: String?
    let metadataCreatedAt: Date
    let metadataUpdatedAt: Date
    let designRevision: DocumentRevision
    let parameterRevision: DocumentRevision
    let selectionDimensionOrder: [SelectionDimensionID]
    let contentFingerprint: CADDocumentSourceFingerprint

    init(document: DesignDocument) throws {
        let cadDocument = document.cadDocument
        documentID = cadDocument.id
        metadataName = cadDocument.metadata.name
        metadataCreatedAt = cadDocument.metadata.createdAt
        metadataUpdatedAt = cadDocument.metadata.updatedAt
        designRevision = cadDocument.designGraph.revision
        parameterRevision = cadDocument.parameters.revision
        selectionDimensionOrder = cadDocument.selectionDimensions.map(\.id)
        contentFingerprint = try cadDocument.sourceFingerprint(
            tolerance: document.modelingSettings.tolerance
        )
    }
}
