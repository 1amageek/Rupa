import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD

extension ViewportSpatialOverlayProducer {
    /// A running dialog's value handle with its anchor resolved in the scene: the origin and unit
    /// direction the value is measured along, and the value a drag in progress shows.
    struct DialogValueSource: Sendable {
        let handle: ViewportDialogValueHandle
        let origin: Point3D
        let direction: Vector3D
        let activeValueMeters: Double?

        func point(for value: Double) -> Point3D {
            origin + direction * (value * handle.worldMetresPerValue)
        }
    }

    /// The running dialog's value handles: each a guide line from its origin through the handle
    /// and on past it, and the handle itself — a dot, or a square for a second value — at the
    /// value a drag in progress shows, which the native axis input drags along the guide.
    static func appendDialogValues(
        _ dialogValues: [DialogValueSource],
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard dialogValues.isEmpty == false else { return }
        for source in dialogValues {
            try Task.checkCancellation()
            let handle = source.handle
            guard handle.worldMetresPerValue.isFinite, handle.worldMetresPerValue > 0 else {
                throw RealityViewportSpatialBatch.invalid("A dialog value handle moves no distance per value.")
            }
            let index = try handleIndex(
                for: .dialogValue(id: handle.id, axis: .init(
                    origin: source.origin, direction: source.direction, baseValue: handle.valueMeters,
                    sourceUnitsPerWorldMetre: 1 / handle.worldMetresPerValue
                )),
                in: &interactionRecords
            )
            let shown = source.point(for: source.activeValueMeters ?? handle.valueMeters)
            // The guide runs from the origin through the handle and as far again, so a drag has
            // somewhere to go both ways; a value at the origin still shows a short guide.
            let reach = max((shown - source.origin).length, 0.001)
            let ends = [source.origin + source.direction * (-0.25 * reach), source.origin + source.direction * (2 * reach)]
            meshes.append(.init(family: .transform, value: try line(ends, color: dialogValueColor, depth: .annotation)))
            var value = marker(handle.shape == .square ? .box : .sphere, anchor: shown, diameterPoints: 9, color: dialogValueColor)
            value.handleIndex = index
            value.hitTolerancePoints = 10
            markers.append(.init(family: .transform, value: value))
        }
        activeFamilies.insert(.transform)
    }

    /// Where `handle`'s value is measured from in `scene`, and along which unit direction; nil when
    /// the scene does not draw what it is anchored to.
    static func resolvedDialogValueAnchor(
        _ handle: ViewportDialogValueHandle, in scene: ViewportScene
    ) throws -> (origin: Point3D, direction: Vector3D)? {
        switch handle.anchor {
        case let .point(origin, direction):
            return (origin, try direction.normalized(tolerance: 1e-12))
        case let .curveStart(target, offsetMeters), let .curveEnd(target, offsetMeters):
            guard let frame = try dialogCurveFrame(handle.anchor, target: target, in: scene) else { return nil }
            return (frame.point + frame.across * offsetMeters, frame.across)
        }
    }

    /// A curve anchor's frame as the scene draws the curve: the point at its start or end, the
    /// tangent running on from there into the curve (out of it at the end), the direction square
    /// to it from the world's up (or its first axis when the curve runs up), and its drawn length.
    static func dialogCurveFrame(
        _ anchor: ViewportDialogValueHandle.Anchor, target: SelectionTarget, in scene: ViewportScene
    ) throws -> (point: Point3D, tangent: Vector3D, across: Vector3D, length: Double)? {
        guard let item = scene.firstItem(sceneNodeID: target.sceneNodeID) else { return nil }
        var local: [Point3D]
        switch (item.kind, target.component) {
        case (.curve(let component), _):
            local = component.segments.flatMap(\.points)
        case (.body(let component), .edge(let componentID)):
            guard let edge = component.topology?.edges.first(where: { $0.componentID == componentID }) else { return nil }
            local = edge.displayPoints
        default:
            return nil
        }
        guard local.count >= 2 else { return nil }
        if case .curveEnd = anchor { local.reverse() }
        let points = local.map(item.modelTransform.point)
        let length = zip(points, points.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
        var tangent = try (points[1] - points[0]).normalized(tolerance: 1e-15)
        if case .curveEnd = anchor { tangent = tangent * -1 }
        let reference: Vector3D = abs(tangent.z) < 0.9 ? .unitZ : .unitX
        let across = try tangent.cross(reference).cross(tangent).normalized(tolerance: 1e-12)
        return (points[0], tangent, across, length)
    }

    /// A running dialog's angle handle with its curve frame resolved: the circle's centre, the axis
    /// it turns about, the direction the angle is measured from, its radius, and the angle a drag
    /// in progress shows.
    struct DialogAngleSource: Sendable {
        let handle: ViewportDialogAngleHandle
        let center: Point3D
        let axis: Vector3D
        let reference: Vector3D
        let radius: Double
        let activeAngleRadians: Double?

        func point(at angle: Double) -> Point3D {
            center + (reference * cos(angle) + axis.cross(reference) * sin(angle)) * radius
        }
    }

    /// `handle`'s source in `scene`; nil when the scene does not draw its curve.
    static func resolvedDialogAngle(
        _ handle: ViewportDialogAngleHandle, active: Double?, in scene: ViewportScene
    ) throws -> DialogAngleSource? {
        let target: SelectionTarget
        switch handle.anchor {
        case let .curveStart(value, _), let .curveEnd(value, _): target = value
        case .point:
            throw RealityViewportSpatialBatch.invalid("A dialog angle turns about a curve.")
        }
        guard let frame = try dialogCurveFrame(handle.anchor, target: target, in: scene) else { return nil }
        let radius = handle.radiusMeters ?? frame.length / 10
        guard radius.isFinite, radius > 0 else {
            throw RealityViewportSpatialBatch.invalid("A dialog angle's circle has no radius.")
        }
        return DialogAngleSource(handle: handle, center: frame.point, axis: frame.tangent, reference: frame.across,
                                 radius: radius, activeAngleRadians: active)
    }

    /// The running dialog's angle handles: each a circle about its curve's tangent and a dot on it
    /// at the angle a drag in progress shows, which the native pattern input turns about the axis.
    static func appendDialogAngles(
        _ dialogAngles: [DialogAngleSource],
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        interactionRecords: inout [ViewportSpatialInteractionRecord],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>
    ) throws {
        guard dialogAngles.isEmpty == false else { return }
        for source in dialogAngles {
            try Task.checkCancellation()
            let index = try handleIndex(
                for: .dialogAngle(.init(id: source.handle.id, center: source.center, axis: source.axis,
                                        referencePoint: source.center + source.reference * source.radius,
                                        angleRadians: source.handle.angleRadians)),
                in: &interactionRecords
            )
            let circle = (0...48).map { source.point(at: 2 * Double.pi * Double($0) / 48) }
            meshes.append(.init(family: .transform, value: try line(circle, color: dialogAngleColor, depth: .annotation)))
            var value = marker(.sphere, anchor: source.point(at: source.activeAngleRadians ?? source.handle.angleRadians),
                               diameterPoints: 9, color: dialogAngleColor)
            value.handleIndex = index
            value.hitTolerancePoints = 10
            markers.append(.init(family: .transform, value: value))
        }
        activeFamilies.insert(.transform)
    }

    /// Plasticity's white for an angle's circle.
    static let dialogAngleColor = SIMD4<Float>(0.96, 0.96, 0.96, 1.0)

    /// Plasticity's yellow for a dialog's handles.
    static let dialogValueColor = SIMD4<Float>(0.98, 0.86, 0.22, 1.0)
}
