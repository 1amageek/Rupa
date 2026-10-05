import simd

/// Shared Swift/Metal value layout; source matrices are captured per native frame.
struct OpticalVolumeParameters: Sendable {
    var worldFromView: simd_float4x4
    var viewFromWorld: simd_float4x4
    var projection: simd_float4x4
    var inverseProjection: simd_float4x4
    var section: SIMD4<Float>
    var frame: SIMD4<UInt32>
    var limits: SIMD4<UInt32>
    var studio: SIMD4<Float>
    var background: SIMD4<Float>
}
