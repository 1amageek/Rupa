import simd

/// A threaded preorder BVH node; escape links require no shader stack.
struct OpticalVolumeNode: Sendable {
    var minimum: SIMD4<Float>
    var maximum: SIMD4<Float>
    /// First triangle, leaf count, first node after this subtree, reserved.
    var indices: SIMD4<UInt32>
}
