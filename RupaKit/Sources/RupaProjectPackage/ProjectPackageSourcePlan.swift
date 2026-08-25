import Foundation
import RupaCoreTypes
import RupaGeometry

struct ProjectPackageSourcePlan: Sendable {
    let sourceEntry: ProjectPackageSourceEntry
    let sourceData: Data
    let blobs: [ProjectPackageMeshBlobPlan]
    let telemetry: GeometryCopyTelemetry
}
