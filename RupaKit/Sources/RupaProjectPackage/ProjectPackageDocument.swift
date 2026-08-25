import RupaCoreTypes
import RupaProjectModel

/// Retains disjoint Product, optional CAD, and Authored Mesh sources plus mapped
/// package ownership needed for adjunct preservation and byte-identical reuse.
public struct ProjectPackageDocument: Sendable {
    public let documentID: ProjectID
    public let productSource: ProjectPackageProductSource
    public let cadSource: ProjectPackageCADSource?
    public let authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset]
    public let persistedContentIdentity: DocumentContentIdentity?
    public let loadReport: ProjectPackageIOReport?

    let backing: ProjectPackageArchiveBacking?
    let manifest: ProjectPackageManifest?
    let retainsUnreferencedSourceBlobs: Bool

    public init(
        documentID: ProjectID,
        productSource: ProjectPackageProductSource,
        cadSource: ProjectPackageCADSource?,
        authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset] = [:]
    ) throws {
        try Self.validate(
            documentID: documentID,
            authoredMeshAssets: authoredMeshAssets
        )
        self.documentID = documentID
        self.productSource = productSource
        self.cadSource = cadSource
        self.authoredMeshAssets = authoredMeshAssets
        persistedContentIdentity = nil
        loadReport = nil
        backing = nil
        manifest = nil
        retainsUnreferencedSourceBlobs = true
    }

    init(
        documentID: ProjectID,
        productSource: ProjectPackageProductSource,
        cadSource: ProjectPackageCADSource?,
        authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset],
        manifest: ProjectPackageManifest,
        backing: ProjectPackageArchiveBacking,
        loadReport: ProjectPackageIOReport,
        retainsUnreferencedSourceBlobs: Bool = true
    ) {
        self.documentID = documentID
        self.productSource = productSource
        self.cadSource = cadSource
        self.authoredMeshAssets = authoredMeshAssets
        persistedContentIdentity = manifest.documentContentIdentity
        self.loadReport = loadReport
        self.backing = backing
        self.manifest = manifest
        self.retainsUnreferencedSourceBlobs = retainsUnreferencedSourceBlobs
    }

    public func replacingSources(
        documentID: ProjectID,
        product productSource: ProjectPackageProductSource,
        cad cadSource: ProjectPackageCADSource?,
        authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset]
    ) throws -> ProjectPackageDocument {
        try Self.validate(
            documentID: documentID,
            authoredMeshAssets: authoredMeshAssets
        )
        return ProjectPackageDocument(
            documentID: documentID,
            productSource: productSource,
            cadSource: cadSource,
            authoredMeshAssets: authoredMeshAssets,
            persistedContentIdentity: nil,
            loadReport: loadReport,
            backing: backing,
            manifest: manifest,
            retainsUnreferencedSourceBlobs: retainsUnreferencedSourceBlobs
        )
    }

    public func garbageCollectingUnreferencedSourceBlobs() -> ProjectPackageDocument {
        ProjectPackageDocument(
            documentID: documentID,
            productSource: productSource,
            cadSource: cadSource,
            authoredMeshAssets: authoredMeshAssets,
            persistedContentIdentity: nil,
            loadReport: loadReport,
            backing: backing,
            manifest: manifest,
            retainsUnreferencedSourceBlobs: false
        )
    }

    private init(
        documentID: ProjectID,
        productSource: ProjectPackageProductSource,
        cadSource: ProjectPackageCADSource?,
        authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset],
        persistedContentIdentity: DocumentContentIdentity?,
        loadReport: ProjectPackageIOReport?,
        backing: ProjectPackageArchiveBacking?,
        manifest: ProjectPackageManifest?,
        retainsUnreferencedSourceBlobs: Bool
    ) {
        self.documentID = documentID
        self.productSource = productSource
        self.cadSource = cadSource
        self.authoredMeshAssets = authoredMeshAssets
        self.persistedContentIdentity = persistedContentIdentity
        self.loadReport = loadReport
        self.backing = backing
        self.manifest = manifest
        self.retainsUnreferencedSourceBlobs = retainsUnreferencedSourceBlobs
    }

    private static func validate(
        documentID: ProjectID,
        authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset]
    ) throws {
        do {
            try documentID.validate()
            for (sourceID, asset) in authoredMeshAssets {
                guard sourceID == asset.id else {
                    throw ProjectPackageError(
                        code: .invalidSource,
                        message: "Authored Mesh asset dictionary keys must match asset identities."
                    )
                }
                try asset.validate()
            }
        } catch let error as ProjectPackageError {
            throw error
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project package source validation failed: \(error)."
            )
        }
    }
}
