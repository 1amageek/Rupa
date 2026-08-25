import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

struct ProjectPackageMeshPlanner {
    static let catalogMediaType = "application/vnd.rupa.mesh-asset-catalog+json"
    static let catalogSchemaVersion: UInt32 = 1
    static let catalogFingerprintAlgorithm = "sha256-rupa-mesh-asset-catalog-json-v1"

    let limits: ProjectPackageResourceLimits

    init(limits: ProjectPackageResourceLimits) {
        self.limits = limits
    }

    func plan(
        _ assets: [GeometrySourceID: AuthoredMeshAsset],
        telemetry: GeometryCopyTelemetry = GeometryCopyTelemetry()
    ) throws -> ProjectPackageMeshPlan {
        try limits.validate()
        guard assets.isEmpty == false else {
            return ProjectPackageMeshPlan(
                catalogEntry: nil,
                catalogData: nil,
                blobs: [],
                telemetry: telemetry
            )
        }

        var updatedTelemetry = telemetry
        var blobs: [ProjectPackageMeshBlobPlan] = []
        blobs.reserveCapacity(assets.count)
        var references: [GeometrySourceID: ProjectSourceBlobReference] = [:]
        for sourceID in assets.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let asset = assets[sourceID], asset.id == sourceID else {
                throw ProjectPackageError(
                    code: .invalidSource,
                    message: "Authored Mesh asset identity is inconsistent while planning the package."
                )
            }
            do {
                try asset.validate()
            } catch {
                throw ProjectPackageError(
                    code: .invalidSource,
                    message: "Authored Mesh asset validation failed: \(error)."
                )
            }
            var sink = ProjectPackageMeshDigestSink(
                maximumByteCount: limits.maximumSourceBlobByteCount
            )
            do {
                try MeshSourceCodec.encode(
                    asset.source,
                    to: &sink,
                    limits: limits.meshSource,
                    telemetry: &updatedTelemetry
                )
            } catch let error as ProjectPackageError {
                throw error
            } catch let error as MeshSourceError
            where error.code == .resourceLimitExceeded {
                throw ProjectPackageError(
                    code: .resourceLimitExceeded,
                    message: error.message
                )
            } catch {
                throw ProjectPackageError(
                    code: .invalidSource,
                    message: "Authored Mesh blob planning failed: \(error)."
                )
            }
            let reference = try sink.reference()
            references[sourceID] = reference
            blobs.append(
                ProjectPackageMeshBlobPlan(
                    source: asset.source,
                    reference: reference,
                    checksum: sink.checksum,
                    maximumEncodedChunkByteCount: sink.maximumChunkByteCount
                )
            )
        }

        let catalog = try ProjectPackageMeshAssetCatalog(
            assets: assets,
            blobReferences: references
        )
        let catalogData = try ProjectPackageCanonicalJSON.encode(catalog)
        guard catalogData.count <= limits.maximumMeshCatalogByteCount else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Authored Mesh catalog exceeds its configured limit."
            )
        }
        let fingerprint: ContentFingerprint
        do {
            fingerprint = try .sha256(
                algorithm: Self.catalogFingerprintAlgorithm,
                data: catalogData
            )
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Authored Mesh catalog identity is invalid: \(error)."
            )
        }
        let catalogEntry = try ProjectPackageSourceEntry(
            path: ProjectPackageManifest.meshCatalogPath,
            mediaType: Self.catalogMediaType,
            schemaVersion: Self.catalogSchemaVersion,
            byteCount: UInt64(catalogData.count),
            fingerprint: fingerprint
        )
        return ProjectPackageMeshPlan(
            catalogEntry: catalogEntry,
            catalogData: catalogData,
            blobs: blobs,
            telemetry: updatedTelemetry
        )
    }
}
