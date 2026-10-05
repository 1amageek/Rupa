import Foundation
import RealityKit
import _RealityKit_SwiftUI
import RupaCoreTypes
import SwiftUI
import simd

@MainActor
struct NativeLineCameraProjection {
    let worldFromCamera: simd_float4x4
    let cameraFromWorld: simd_float4x4
    let forward: CGAffineTransform
    let inverseOffset: CGAffineTransform
    let sampleDepth: Float
    let perspective: Bool
    let annotationDepth: Float
    let near: Float
    let far: Float

    func local(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let value = cameraFromWorld * SIMD4(point, 1)
        return SIMD3(value.x, value.y, value.z)
    }

    func depthScale(_ local: SIMD3<Float>) -> Float { perspective ? -local.z / sampleDepth : 1 }

    func project(_ point: SIMD3<Float>) -> CGPoint? {
        let point = local(point)
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite, point.z < 0 else { return nil }
        let scale = depthScale(point)
        let result = CGPoint(x: CGFloat(point.x / scale), y: CGFloat(point.y / scale)).applying(forward)
        return result.x.isFinite && result.y.isFinite ? result : nil
    }

    func point(at screen: CGPoint, depth: Float) -> SIMD3<Float> {
        let offset = CGPoint(x: screen.x - forward.tx, y: screen.y - forward.ty).applying(inverseOffset)
        let scale = perspective ? depth / sampleDepth : 1
        let value = worldFromCamera * SIMD4(Float(offset.x) * scale, Float(offset.y) * scale, -depth, 1)
        return SIMD3(value.x, value.y, value.z)
    }

    func unproject(_ screen: CGPoint, onto plane: ViewportCanvasPlane, origin: Point3D) -> Point3D? {
        guard let normal = plane.normal else { return nil }
        let sample = point(at: screen, depth: sampleDepth)
        let start = perspective ? SIMD3(worldFromCamera.columns.3.x, worldFromCamera.columns.3.y, worldFromCamera.columns.3.z)
            : point(at: screen, depth: 0)
        let direction = SIMD3<Double>(sample - start)
        let worldStart = SIMD3<Double>(start) + SIMD3(origin.x, origin.y, origin.z)
        let n = SIMD3(normal.x, normal.y, normal.z)
        let denominator = simd_dot(direction, n)
        guard denominator.isFinite, abs(denominator) > 1e-12 else { return nil }
        let distance = -simd_dot(worldStart, n) / denominator
        guard distance.isFinite, distance >= 0 else { return nil }
        let result = worldStart + direction * distance
        guard result.x.isFinite, result.y.isFinite, result.z.isFinite else { return nil }
        return Point3D(x: result.x, y: result.y, z: result.z)
    }
    static func capture(camera: Entity, content: RealityViewCameraContent) -> NativeLineCameraProjection? {
        let orthographic = camera.components[OrthographicCameraComponent.self]
        let perspective = camera.components[PerspectiveCameraComponent.self]
        guard (orthographic != nil) != (perspective != nil) else { return nil }
        let near: Float
        let far: Float
        if let orthographic { near = orthographic.near; far = orthographic.far }
        else if let perspective { near = perspective.near; far = perspective.far }
        else { return nil }
        guard near.isFinite, near > 0, far > near,
              orthographic == nil || far.isFinite else { return nil }
        let depth = Float(min((Double(near) + Double(far)) / 2, max(Double(near) * 2, 1)))
        let step = orthographic?.scale ?? depth
        guard depth.isFinite, depth > 0, step.isFinite, step > 0 else { return nil }
        func project(_ local: SIMD3<Float>) -> CGPoint? {
            content.project(point: camera.convert(position: local, to: nil), to: .local)
        }
        guard let a = project([0, 0, -depth]), let b = project([step, 0, -depth]),
              let c = project([0, step, -depth]), a.x.isFinite, a.y.isFinite,
              b.x.isFinite, b.y.isFinite, c.x.isFinite, c.y.isFinite else { return nil }
        let mapping = CGAffineTransform(a: (b.x - a.x) / CGFloat(step), b: (b.y - a.y) / CGFloat(step),
                                        c: (c.x - a.x) / CGFloat(step), d: (c.y - a.y) / CGFloat(step), tx: a.x, ty: a.y)
        let determinant = mapping.a * mapping.d - mapping.b * mapping.c
        guard determinant.isFinite, determinant != 0 else { return nil }
        var offsetMapping = mapping
        offsetMapping.tx = 0; offsetMapping.ty = 0
        let transform = camera.transformMatrix(relativeTo: nil)
        return NativeLineCameraProjection(worldFromCamera: transform, cameraFromWorld: simd_inverse(transform),
                                forward: mapping, inverseOffset: offsetMapping.inverted(),
                                sampleDepth: depth, perspective: perspective != nil, annotationDepth: near * 1.01,
                                near: near, far: far)
    }

}
