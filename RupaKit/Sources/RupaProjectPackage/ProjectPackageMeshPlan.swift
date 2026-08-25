import Foundation
import RupaGeometry

struct ProjectPackageMeshPlan: Sendable {
    let catalogEntry: ProjectPackageSourceEntry?
    let catalogData: Data?
    let blobs: [ProjectPackageMeshBlobPlan]
    let telemetry: GeometryCopyTelemetry
}
