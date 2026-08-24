import RupaGeometry

struct ProjectPackageWriteOutput {
    let archiveByteCount: UInt64
    let maximumWriteChunkByteCount: Int
    let telemetry: GeometryCopyTelemetry
}
