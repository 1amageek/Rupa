import RupaCoreTypes
import RupaProjectModel

/// Retains the coherent CAD and universal source aggregate plus mapped package
/// ownership needed for adjunct preservation and byte-identical source reuse.
public struct ProjectPackageDocument: Sendable {
    public let source: ProjectSourceModel
    public let cadSource: ProjectPackageCADSource
    public let persistedContentIdentity: DocumentContentIdentity?
    public let loadReport: ProjectPackageIOReport?

    let backing: ProjectPackageArchiveBacking?
    let manifest: ProjectPackageManifest?
    let retainsUnreferencedSourceBlobs: Bool

    public init(
        source: ProjectSourceModel,
        cadSource: ProjectPackageCADSource
    ) throws {
        do {
            try source.validate()
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project source validation failed: \(error)."
            )
        }
        self.source = source
        self.cadSource = cadSource
        persistedContentIdentity = nil
        loadReport = nil
        backing = nil
        manifest = nil
        retainsUnreferencedSourceBlobs = true
    }

    init(
        source: ProjectSourceModel,
        cadSource: ProjectPackageCADSource,
        manifest: ProjectPackageManifest,
        backing: ProjectPackageArchiveBacking,
        loadReport: ProjectPackageIOReport,
        retainsUnreferencedSourceBlobs: Bool = true
    ) {
        self.source = source
        self.cadSource = cadSource
        persistedContentIdentity = manifest.documentContentIdentity
        self.loadReport = loadReport
        self.backing = backing
        self.manifest = manifest
        self.retainsUnreferencedSourceBlobs = retainsUnreferencedSourceBlobs
    }

    public func replacingSources(
        project source: ProjectSourceModel,
        cad cadSource: ProjectPackageCADSource
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
            cadSource: cadSource,
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
            cadSource: cadSource,
            persistedContentIdentity: nil,
            loadReport: loadReport,
            backing: backing,
            manifest: manifest,
            retainsUnreferencedSourceBlobs: false
        )
    }

    private init(
        source: ProjectSourceModel,
        cadSource: ProjectPackageCADSource,
        persistedContentIdentity: DocumentContentIdentity?,
        loadReport: ProjectPackageIOReport?,
        backing: ProjectPackageArchiveBacking?,
        manifest: ProjectPackageManifest?,
        retainsUnreferencedSourceBlobs: Bool
    ) {
        self.source = source
        self.cadSource = cadSource
        self.persistedContentIdentity = persistedContentIdentity
        self.loadReport = loadReport
        self.backing = backing
        self.manifest = manifest
        self.retainsUnreferencedSourceBlobs = retainsUnreferencedSourceBlobs
    }
}
