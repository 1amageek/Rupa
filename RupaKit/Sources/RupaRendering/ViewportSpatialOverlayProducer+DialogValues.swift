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
        case let .curveStart(target, offsetMeters):
            guard let item = scene.firstItem(sceneNodeID: target.sceneNodeID) else { return nil }
            let local: [Point3D]
            switch (item.kind, target.component) {
            case (.curve(let component), _):
                local = Array(component.segments.flatMap(\.points).prefix(2))
            case (.body(let component), .edge(let componentID)):
                guard let edge = component.topology?.edges.first(where: { $0.componentID == componentID }) else { return nil }
                local = Array(edge.displayPoints.prefix(2))
            default:
                return nil
            }
            guard local.count == 2 else { return nil }
            let (start, next) = (item.modelTransform.point(local[0]), item.modelTransform.point(local[1]))
            let tangent = try (next - start).normalized(tolerance: 1e-15)
            // Square to the curve: across it from the world's up, or its first axis when the curve
            // runs up.
            let reference: Vector3D = abs(tangent.z) < 0.9 ? .unitZ : .unitX
            let across = try tangent.cross(reference).cross(tangent).normalized(tolerance: 1e-12)
            return (start + across * offsetMeters, across)
        }
    }

    /// Plasticity's yellow for a dialog's handles.
    static let dialogValueColor = SIMD4<Float>(0.98, 0.86, 0.22, 1.0)
}
