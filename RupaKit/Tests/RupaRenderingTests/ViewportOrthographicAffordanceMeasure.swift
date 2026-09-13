import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
@testable import RupaRendering

/// An orthographic camera that answers the three affordance drag queries in
/// closed form, under the same degeneracy contract the mounted frame states.
///
/// The frame solves every query from a screen ray. This fake builds the same
/// ray from an orthonormal basis and applies the same closed-form solve, so a
/// drag measured here resolves exactly as the frame resolves it, and the
/// expected value of a test can be stated in world metres rather than read back
/// out of a projection. Its refusals carry
/// `MeshSourcePresentationRenderError.Code.failed`, which is the code
/// `RealityViewport.queryFailure` answers a geometric degeneracy with.
@MainActor
struct ViewportOrthographicAffordanceMeasure: ViewportAffordanceMeasuring {
    /// Where the camera plane sits. Every ray starts on this plane.
    let eye: Point3D
    /// The world direction screen `x` grows along.
    let right: Vector3D
    /// The world direction screen `y` shrinks along; screen `y` grows downward.
    let up: Vector3D
    /// The world direction the camera looks along.
    let forward: Vector3D
    /// Screen points per world metre.
    let scale: Double
    /// The screen point `eye` projects to.
    let center: CGPoint

    /// A camera looking along `direction`, standing `distance` metres behind
    /// `target` so everything near the target lies in front of the ray origin.
    static func looking(
        along direction: Vector3D,
        approximateUp: Vector3D = Vector3D(x: 0.0, y: 1.0, z: 0.0),
        at target: Point3D,
        distance: Double = 1.0,
        scale: Double = 20_000.0,
        center: CGPoint = CGPoint(x: 400.0, y: 300.0)
    ) throws -> Self {
        let forward = try direction.normalized(tolerance: 1.0e-12)
        let right = try forward.cross(approximateUp).normalized(tolerance: 1.0e-12)
        return Self(
            eye: target + forward * -distance,
            right: right,
            up: right.cross(forward),
            forward: forward,
            scale: scale,
            center: center
        )
    }

    /// A camera every world axis and every axis-aligned world plane answers
    /// for, and whose projected world `x` and world `z` are not orthogonal on
    /// screen, which is the condition a per-axis screen decomposition
    /// cross-bleeds under.
    static func isometric(
        at target: Point3D,
        scale: Double = 20_000.0
    ) throws -> Self {
        try looking(
            along: Vector3D(x: -1.0, y: -1.0, z: -1.0),
            at: target,
            scale: scale
        )
    }

    /// Where a world point lands on screen. The exact inverse of
    /// `ray(through:)` in the two screen directions.
    func projected(_ point: Point3D) -> CGPoint {
        let delta = point - eye
        return CGPoint(
            x: center.x + CGFloat(delta.dot(right) * scale),
            y: center.y - CGFloat(delta.dot(up) * scale)
        )
    }

    /// The world ray a screen point names. Parallel projection, so every ray
    /// shares one direction and differs only in origin.
    func ray(through point: CGPoint) -> (origin: Point3D, direction: Vector3D) {
        let horizontal = Double(point.x - center.x) / scale
        let vertical = -Double(point.y - center.y) / scale
        return (eye + right * horizontal + up * vertical, forward)
    }

    func worldAxisDelta(
        from start: CGPoint,
        to end: CGPoint,
        axisOrigin: Point3D,
        axisDirection: Vector3D
    ) throws -> Double {
        let first = try worldAxisParameter(
            at: start,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection
        )
        let second = try worldAxisParameter(
            at: end,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection
        )
        let delta = second - first
        guard delta.isFinite else {
            throw Self.failure("The fake world-axis delta is not finite.")
        }
        return delta
    }

    /// The signed metres along a retained world axis from its origin to the
    /// closest point represented by the screen ray, solved the way the frame
    /// solves it.
    func worldAxisParameter(
        at point: CGPoint,
        axisOrigin: Point3D,
        axisDirection: Vector3D
    ) throws -> Double {
        let axisLength = axisDirection.length
        guard axisDirection.isFinite, axisOrigin.isFinite,
              axisLength.isFinite, axisLength > 0.0 else {
            throw Self.failure("The fake world axis is not finite and valid.")
        }
        let axis = axisDirection / axisLength
        let ray = ray(through: point)
        let offset = ray.origin - axisOrigin
        let alignment = ray.direction.dot(axis)
        let denominator = 1.0 - alignment * alignment
        guard alignment.isFinite, denominator.isFinite, denominator > 1.0e-12 else {
            throw Self.failure("The fake camera ray is parallel to the requested world axis.")
        }
        let rayParameter = ray.direction.dot(offset)
        let axisParameter = axis.dot(offset)
        let rayDistance = (alignment * axisParameter - rayParameter) / denominator
        let parameter = (axisParameter - alignment * rayParameter) / denominator
        guard rayDistance.isFinite, rayDistance >= 0.0, parameter.isFinite else {
            throw Self.failure("The requested world axis lies behind the fake camera ray.")
        }
        return parameter
    }

    func worldPlanePoint(
        at point: CGPoint,
        planeOrigin: Point3D,
        planeNormal: Vector3D
    ) throws -> Point3D {
        let normalLength = planeNormal.length
        guard planeNormal.isFinite, normalLength.isFinite, normalLength > 0.0 else {
            throw Self.failure("The fake camera plane is not finite and valid.")
        }
        return try planeIntersection(
            at: point,
            planeOrigin: planeOrigin,
            unitNormal: planeNormal / normalLength
        )
    }

    func viewPlanePoint(at point: CGPoint, through anchor: Point3D) throws -> Point3D {
        // The frame states the view direction from the camera it installed, and
        // so does this fake: `forward` is never accepted from a caller.
        try planeIntersection(at: point, planeOrigin: anchor, unitNormal: forward)
    }

    private func planeIntersection(
        at point: CGPoint,
        planeOrigin: Point3D,
        unitNormal: Vector3D
    ) throws -> Point3D {
        guard planeOrigin.isFinite else {
            throw Self.failure("The fake camera plane is not finite and valid.")
        }
        let ray = ray(through: point)
        let denominator = ray.direction.dot(unitNormal)
        guard denominator.isFinite, abs(denominator) > 1.0e-12 else {
            throw Self.failure("The fake camera ray is parallel to the requested plane.")
        }
        let distance = (planeOrigin - ray.origin).dot(unitNormal) / denominator
        guard distance.isFinite, distance >= 0.0 else {
            throw Self.failure("The requested plane lies behind the fake camera ray.")
        }
        let result = ray.origin + ray.direction * distance
        guard result.isFinite else {
            throw Self.failure("The fake plane intersection is not finite.")
        }
        return result
    }

    static func failure(_ message: String) -> MeshSourcePresentationRenderError {
        MeshSourcePresentationRenderError(code: .failed, message: message)
    }
}
