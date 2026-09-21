import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD

/// Source-profile displacement carried by the native handle that draws it.
struct ViewportProfileFaceFrame: Equatable, Sendable {
    let anchor: Point3D
    let direction: Vector3D
    let worldUnitsPerSourceUnit: Double

    static func resolve(item: ViewportSceneItem, face: ViewportBodyFace,
                        componentID: SelectionComponentID? = nil,
                        document: DesignDocument) throws -> Self {
        guard let feature = document.cadDocument.designGraph.nodes[item.featureID],
              case .extrude(let extrusion) = feature.operation,
              let profile = document.cadDocument.designGraph.nodes[extrusion.profile.featureID],
              case .sketch(let sketch) = profile.operation,
              case .body(let body) = item.kind, let mesh = body.mesh,
              let first = mesh.positions.first else {
            throw RealityViewportSpatialBatch.invalid("Face editing requires an evaluated extrusion profile.")
        }
        let frame = try SketchPlaneCoordinateSystem(plane: sketch.plane)
        let initial = frame.project(first)
        var low = Vector3D(x: initial.point.x, y: initial.depth, z: initial.point.y)
        var high = low
        for point in mesh.positions {
            let p = frame.project(point)
            low.x = min(low.x, p.point.x); high.x = max(high.x, p.point.x)
            low.y = min(low.y, p.depth); high.y = max(high.y, p.depth)
            low.z = min(low.z, p.point.y); high.z = max(high.z, p.point.y)
        }
        var center = (low + high) * 0.5
        var axis: Vector3D
        switch face {
        case .left: center.x = low.x; axis = frame.u * -1
        case .right, .side: center.x = high.x; axis = frame.u
        case .front: center.y = low.y; axis = frame.normal * -1
        case .back: center.y = high.y; axis = frame.normal
        case .bottom: center.z = low.z; axis = frame.v * -1
        case .top: center.z = high.z; axis = frame.v
        }
        if face == .side, let componentID,
           let points = body.topology?.faces.first(where: { $0.componentID == componentID })?.points,
           !points.isEmpty {
            let midpoint = (low + high) * 0.5
            var radial = Vector3D(x: 0, y: 0, z: 0)
            for point in points {
                let local = frame.project(point)
                radial.x += local.point.x - midpoint.x
                radial.z += local.point.y - midpoint.z
            }
            // A complete periodic wall has no preferred radial direction; +U is
            // its seam direction. A wall patch places its handle on that patch.
            if radial.length > 1e-12 {
                radial = radial * (1 / radial.length)
                let radius = (high.x - low.x) * 0.5
                center = midpoint + radial * radius
                axis = frame.u * radial.x + frame.v * radial.z
            }
        }
        let point = frame.point(from: .init(x: center.x, y: center.z)) + frame.normal * center.y
        let worldAxis = try ViewportWorldTransformAlgebra.transformedVector(axis, by: item.modelTransform)
        let scale = worldAxis.length
        guard scale.isFinite, scale > 1e-12 else {
            throw RealityViewportSpatialBatch.invalid("Face editing requires a nonsingular source axis.")
        }
        return .init(anchor: try ViewportWorldTransformAlgebra.transformedPoint(point, by: item.modelTransform),
                     direction: worldAxis * (1 / scale), worldUnitsPerSourceUnit: scale)
    }

    @MainActor
    func distance(from start: CGPoint, to end: CGPoint,
                  measure: some ViewportAffordanceMeasuring) throws -> Double {
        try measure.worldAxisDelta(from: start, to: end, axisOrigin: anchor,
                                   axisDirection: direction) / worldUnitsPerSourceUnit
    }
}
