import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

struct ProjectPackageSourcePlanner {
    static let sourceMetadataMediaType = "application/vnd.rupa.project-source+json"
    static let sourceMetadataSchemaVersion: UInt32 = 1
    static let sourceMetadataFingerprintAlgorithm = "sha256-rupa-source-json-v1"

    let limits: ProjectPackageResourceLimits

    init(limits: ProjectPackageResourceLimits) {
        self.limits = limits
    }

    func plan(
        _ project: ProjectSourceModel,
        telemetry: GeometryCopyTelemetry = GeometryCopyTelemetry()
    ) throws -> ProjectPackageSourcePlan {
        try limits.validate()
        do {
            try project.validate()
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project source validation failed: \(error)."
            )
        }

        var updatedTelemetry = telemetry
        var blobs: [ProjectPackageMeshBlobPlan] = []
        blobs.reserveCapacity(project.meshSources.count)
        var references: [GeometrySourceID: ProjectSourceBlobReference] = [:]
        for sourceID in project.meshSources.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let source = project.meshSources[sourceID] else {
                throw ProjectPackageError(
                    code: .invalidSource,
                    message: "Project mesh source disappeared while planning the package."
                )
            }
            var sink = ProjectPackageMeshDigestSink(
                maximumByteCount: limits.maximumSourceBlobByteCount
            )
            do {
                try MeshSourceCodec.encode(
                    source,
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
                    message: "Mesh source planning failed: \(error)."
                )
            }
            let reference = try sink.reference()
            references[sourceID] = reference
            blobs.append(
                ProjectPackageMeshBlobPlan(
                    source: source,
                    reference: reference,
                    checksum: sink.checksum,
                    maximumEncodedChunkByteCount: sink.maximumChunkByteCount
                )
            )
        }

        let envelope = try ProjectPackageSourceEnvelope(
            project: project,
            meshBlobs: references
        )
        let sourceData = try ProjectPackageCanonicalJSON.encode(envelope)
        guard sourceData.count <= limits.maximumSourceMetadataByteCount else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project source metadata exceeds its configured limit."
            )
        }
        let sourceFingerprint: ContentFingerprint
        do {
            sourceFingerprint = try .sha256(
                algorithm: Self.sourceMetadataFingerprintAlgorithm,
                data: sourceData
            )
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project source metadata identity is invalid: \(error)."
            )
        }
        let sourceEntry = try ProjectPackageSourceEntry(
            path: ProjectPackageManifest.sourceMetadataPath,
            mediaType: Self.sourceMetadataMediaType,
            schemaVersion: Self.sourceMetadataSchemaVersion,
            byteCount: UInt64(sourceData.count),
            fingerprint: sourceFingerprint
        )
        let requiredEntryCount = blobs.count.addingReportingOverflow(3)
        guard !requiredEntryCount.overflow,
            requiredEntryCount.partialValue <= limits.maximumEntryCount
        else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project source entry count exceeds its configured limit."
            )
        }
        return ProjectPackageSourcePlan(
            sourceEntry: sourceEntry,
            sourceData: sourceData,
            blobs: blobs,
            telemetry: updatedTelemetry
        )
    }
}
