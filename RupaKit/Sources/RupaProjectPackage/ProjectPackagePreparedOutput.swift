import RupaGeometry

struct ProjectPackagePreparedOutput {
    let manifest: ProjectPackageManifest
    let entries: [ProjectPackageOutputEntry]
    let telemetry: GeometryCopyTelemetry
    let encodedBlobCount: Int
    let encodedBlobByteCount: UInt64
    let reusedBlobCount: Int
    let reusedBlobByteCount: UInt64
    let preservedAdjunctCount: Int
    let preservedAdjunctByteCount: UInt64
}
