import Foundation
import RupaCoreTypes
import RupaGeometry

struct ProjectPackageSourcePlan: Sendable {
    let manifest: ProjectPackageManifest
    let manifestData: Data
    let sourceData: Data
    let blobs: [ProjectPackageMeshBlobPlan]
    let telemetry: GeometryCopyTelemetry

    var documentContentIdentity: DocumentContentIdentity {
        manifest.documentContentIdentity
    }
}
