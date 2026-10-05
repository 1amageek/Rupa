import Foundation
import simd

/// Exact immutable camera and shading authority for one mounted optical capture.
struct OpticalVolumeFrameCapture: Equatable, Sendable {
    let worldFromView: simd_float4x4
    let section: SIMD4<Float>
    let background: SIMD4<Float>
    let rotation: Float
    let specular: Bool
    let nativeSurfaceVisible: Bool
    let cameraRevision: UInt64?
    let viewportSize: CGSize?
    let displayScale: CGFloat?

    static func == (lhs: Self, rhs: Self) -> Bool {
        (0..<4).allSatisfy { lhs.worldFromView[$0] == rhs.worldFromView[$0] }
            && lhs.section == rhs.section && lhs.background == rhs.background && lhs.rotation == rhs.rotation
            && lhs.specular == rhs.specular && lhs.nativeSurfaceVisible == rhs.nativeSurfaceVisible
            && lhs.cameraRevision == rhs.cameraRevision
            && lhs.viewportSize == rhs.viewportSize && lhs.displayScale == rhs.displayScale
    }
}
