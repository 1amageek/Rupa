import RupaCoreTypes
import RupaProjectModel

/// Retains the editable source plus mapped package ownership needed for opaque
/// adjunct preservation and byte-identical reuse of unchanged source blobs.
public struct ProjectPackageDocument: Sendable {
    public let source: ProjectSourceModel
    public let persistedContentIdentity: DocumentContentIdentity?
    public let loadReport: ProjectPackageIOReport?

    let backing: ProjectPackageArchiveBacking?
    let manifest: ProjectPackageManifest?
    let retainsUnreferencedSourceBlobs: Bool

    public init(source: ProjectSourceModel) throws {
        do {
            try source.validate()
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project source validation failed: \(error)."
            )
        }
        self.source = source
        persistedContentIdentity = nil
        loadReport = nil
        backing = nil
        manifest = nil
        retainsUnreferencedSourceBlobs = true
    }

    init(
        source: ProjectSourceModel,
        manifest: ProjectPackageManifest,
        backing: ProjectPackageArchiveBacking,
        loadReport: ProjectPackageIOReport,
        retainsUnreferencedSourceBlobs: Bool = true
    ) {
        self.source = source
        persistedContentIdentity = manifest.documentContentIdentity
        self.loadReport = loadReport
        self.backing = backing
        self.manifest = manifest
        self.retainsUnreferencedSourceBlobs = retainsUnreferencedSourceBlobs
    }

    public func replacingSource(
        _ source: ProjectSourceModel
    ) throws -> ProjectPackageDocument {
        do {
            try source.validate()
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Replacement project source validation failed: \(error)."
            )
        }
        return ProjectPackageDocument(
            source: source,
            persistedContentIdentity: nil,
            loadReport: loadReport,
            backing: backing,
            manifest: manifest,
            retainsUnreferencedSourceBlobs: retainsUnreferencedSourceBlobs
        )
    }

    public func garbageCollectingUnreferencedSourceBlobs() -> ProjectPackageDocument {
        ProjectPackageDocument(
            source: source,
            persistedContentIdentity: nil,
            loadReport: loadReport,
            backing: backing,
            manifest: manifest,
            retainsUnreferencedSourceBlobs: false
        )
    }

    private init(
        source: ProjectSourceModel,
        persistedContentIdentity: DocumentContentIdentity?,
        loadReport: ProjectPackageIOReport?,
        backing: ProjectPackageArchiveBacking?,
        manifest: ProjectPackageManifest?,
        retainsUnreferencedSourceBlobs: Bool
    ) {
        self.source = source
        self.persistedContentIdentity = persistedContentIdentity
        self.loadReport = loadReport
        self.backing = backing
        self.manifest = manifest
        self.retainsUnreferencedSourceBlobs = retainsUnreferencedSourceBlobs
    }
}
