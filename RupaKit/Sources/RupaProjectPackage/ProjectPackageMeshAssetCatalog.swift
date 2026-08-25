import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

struct ProjectPackageMeshAssetCatalog: Codable, Equatable, Sendable {
    static let currentSchemaVersion: UInt32 = 1

    struct AssetRecord: Codable, Equatable, Sendable {
        let id: GeometrySourceID
        let provenance: AuthoredMeshProvenance
        let blob: ProjectSourceBlobReference
    }

    let schemaVersion: UInt32
    let assets: [AssetRecord]

    init(
        assets: [GeometrySourceID: AuthoredMeshAsset],
        blobReferences: [GeometrySourceID: ProjectSourceBlobReference]
    ) throws {
        guard assets.isEmpty == false,
              Set(assets.keys) == Set(blobReferences.keys) else {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "A Mesh asset catalog requires exactly one blob for every Authored Mesh asset."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        self.assets = try assets.keys.sorted(by: { $0.rawValue < $1.rawValue }).map { id in
            guard let asset = assets[id],
                  asset.id == id,
                  let blob = blobReferences[id] else {
                throw ProjectPackageError(
                    code: .invalidSource,
                    message: "Authored Mesh asset identity or blob ownership is inconsistent."
                )
            }
            try asset.validate()
            return AssetRecord(
                id: id,
                provenance: asset.provenance,
                blob: blob
            )
        }
    }

    func makeAssets(
        meshSources: [GeometrySourceID: MeshSource]
    ) throws -> [GeometrySourceID: AuthoredMeshAsset] {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ProjectPackageError(
                code: .unsupportedSchema,
                message: "Authored Mesh catalog schema version is unsupported."
            )
        }
        guard assets.isEmpty == false else {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "An empty Authored Mesh catalog must be omitted."
            )
        }
        var decoded: [GeometrySourceID: AuthoredMeshAsset] = [:]
        for record in assets {
            guard let source = meshSources[record.id],
                  source.identity == record.id,
                  decoded[record.id] == nil else {
                throw ProjectPackageError(
                    code: .invalidSource,
                    message: "Authored Mesh catalog identities must be unique and match decoded blobs."
                )
            }
            do {
                decoded[record.id] = try AuthoredMeshAsset(
                    source: source,
                    provenance: record.provenance
                )
            } catch {
                throw ProjectPackageError(
                    code: .invalidSource,
                    message: "Decoded Authored Mesh provenance is invalid: \(error)."
                )
            }
        }
        guard Set(decoded.keys) == Set(meshSources.keys) else {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Decoded Mesh blobs must exactly match the Authored Mesh catalog."
            )
        }
        return decoded
    }
}
