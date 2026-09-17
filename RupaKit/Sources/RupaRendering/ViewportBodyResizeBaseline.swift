import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD

/// The source box frame, independent of its world AABB and of the camera.
struct ViewportBodyResizeBaseline: Sendable {
    let worldFromBox: Transform3D
    let minimum: Point3D
    let maximum: Point3D
    let size: Vector3D
    let documentID: DocumentID
    let designRevision: DocumentRevision
    let parameterRevision: DocumentRevision

    static func resolve(document: DesignDocument, nodeID: SceneNodeID,
                        worldTransform: Transform3D) throws -> Self? {
        guard let node = document.productMetadata.sceneNodes[nodeID],
              let featureID = node.reference?.featureID,
              let feature = document.cadDocument.designGraph.nodes[document.boxExtrusionFeatureID(featureID)],
              case .extrude(let extrude) = feature.operation,
              extrude.direction == .normal,
              let profile = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
              case .sketch(let sketch) = profile.operation,
              sketch.entities.count == 4,
              sketch.entities.values.allSatisfy({ if case .line = $0 { true } else { false } }) else { return nil }
        let source = try ObjectDimensionSourceResolver().resolve(
            target: .init(sceneNodeID: nodeID, component: .object), in: document)
        let depth = try document.cadDocument.parameters.resolvedValue(for: extrude.distance).value
        guard depth > 0 else { return nil }
        var points: [Point2D] = []
        for entity in sketch.entities.values {
            guard case .line(let line) = entity else { return nil }
            for point in [line.start, line.end] {
                points.append(.init(x: try document.cadDocument.parameters.resolvedValue(for: point.x).value,
                                    y: try document.cadDocument.parameters.resolvedValue(for: point.y).value))
            }
        }
        guard let xMin = points.map(\.x).min(), let xMax = points.map(\.x).max(),
              let zMin = points.map(\.y).min(), let zMax = points.map(\.y).max(),
              points.allSatisfy({ ($0.x == xMin || $0.x == xMax) && ($0.y == zMin || $0.y == zMax) }) else { return nil }
        let frame = try SketchPlaneCoordinateSystem(plane: sketch.plane)
        let box = Transform3D(matrix: try Matrix4x4(values: [
            frame.u.x, frame.normal.x, frame.v.x, frame.origin.x,
            frame.u.y, frame.normal.y, frame.v.y, frame.origin.y,
            frame.u.z, frame.normal.z, frame.v.z, frame.origin.z,
            0, 0, 0, 1
        ]))
        let world = try ViewportWorldTransformAlgebra.multiplied(worldTransform, box)
        _ = try ViewportWorldTransformAlgebra.inverted(world)
        return .init(worldFromBox: world, minimum: .init(x: xMin, y: 0, z: zMin),
                     maximum: .init(x: xMax, y: depth, z: zMax),
                     size: .init(x: source.sizeX, y: source.sizeY, z: source.sizeZ),
                     documentID: document.cadDocument.id,
                     designRevision: document.cadDocument.designGraph.revision,
                     parameterRevision: document.cadDocument.parameters.revision)
    }

    func point(for action: ViewportAffordanceAction) throws -> Point3D {
        var point = Point3D(x: (minimum.x + maximum.x) / 2,
                            y: (minimum.y + maximum.y) / 2,
                            z: (minimum.z + maximum.z) / 2)
        for (axis, lower) in try sides(for: action) {
            switch axis {
            case .x: point.x = lower ? minimum.x : maximum.x
            case .y: point.y = lower ? minimum.y : maximum.y
            case .z: point.z = lower ? minimum.z : maximum.z
            }
        }
        return try ViewportWorldTransformAlgebra.transformedPoint(point, by: worldFromBox)
    }

    private func sides(for action: ViewportAffordanceAction) throws -> [(ViewportCoordinateAxis, Bool)] {
        switch action {
        case .vertexMove(let vertex):
            return [(.x, vertex.usesMinX), (.y, vertex.usesMinY), (.z, vertex.usesMinZ)]
        case .faceMove(let face):
            switch face {
            case .left: return [(.x, true)]
            case .right: return [(.x, false)]
            case .front: return [(.y, true)]
            case .back: return [(.y, false)]
            case .bottom: return [(.z, true)]
            case .top: return [(.z, false)]
            case .side: break
            }
        default: break
        }
        throw RealityViewportSpatialBatch.invalid("A box resize requires a face or corner handle.")
    }

    @MainActor
    func mutation(action: ViewportAffordanceAction, from start: CGPoint, to end: CGPoint,
                  measure: some ViewportAffordanceMeasuring) throws -> Transform3D {
        let sides = try sides(for: action)
        let anchor = try point(for: action)
        let delta: Vector3D
        if sides.count == 1 {
            let direction = try ViewportWorldTransformAlgebra.transformedVector(sides[0].0.unitVector, by: worldFromBox)
            let unit = try ViewportWorldTransformAlgebra.normalized(direction, describing: "box face axis")
            delta = unit * (try measure.worldAxisDelta(from: start, to: end, axisOrigin: anchor, axisDirection: unit))
        } else {
            delta = try measure.viewPlanePoint(at: end, through: anchor) - measure.viewPlanePoint(at: start, through: anchor)
        }
        let localDelta = try ViewportWorldTransformAlgebra.transformedVector(delta, by: ViewportWorldTransformAlgebra.inverted(worldFromBox))
        var values = Transform3D.identity.matrix.values
        for (axis, lower) in sides {
            let index: Int
            let shift: Double
            let extent: Double
            let fixed: Double
            switch axis {
            case .x: index = 0; shift = localDelta.x; extent = size.x; fixed = lower ? maximum.x : minimum.x
            case .y: index = 1; shift = localDelta.y; extent = size.y; fixed = lower ? maximum.y : minimum.y
            case .z: index = 2; shift = localDelta.z; extent = size.z; fixed = lower ? maximum.z : minimum.z
            }
            let factor = 1 + (lower ? -shift : shift) / extent
            guard factor.isFinite else {
                throw RealityViewportSpatialBatch.invalid("A box resize factor must be finite.")
            }
            values[index * 4 + index] = factor
            values[index * 4 + 3] = fixed * (1 - factor)
        }
        return try ViewportWorldTransformAlgebra.multiplied(
            ViewportWorldTransformAlgebra.multiplied(worldFromBox, Transform3D(matrix: Matrix4x4(values: values))),
            ViewportWorldTransformAlgebra.inverted(worldFromBox))
    }

    func commit(mutation: Transform3D, member: ViewportObjectTransformMember) throws -> ViewportBodyResizeDragTarget? {
        let local = try ViewportWorldTransformAlgebra.multiplied(
            ViewportWorldTransformAlgebra.multiplied(ViewportWorldTransformAlgebra.inverted(worldFromBox), mutation), worldFromBox)
        let m = local.matrix.values
        _ = try ViewportWorldTransformAlgebra.inverted(mutation)
        let nextSize = Vector3D(x: size.x * abs(m[0]), y: size.y * abs(m[5]), z: size.z * abs(m[10]))
        guard nextSize.isFinite, min(nextSize.x, nextSize.y, nextSize.z) > 0 else {
            throw RealityViewportSpatialBatch.invalid("A box resize has invalid source dimensions.")
        }
        // Core keeps the profile center fixed and extrudes from depth zero.
        // Remove that source-center motion before translating the occurrence.
        let center = Point3D(x: (minimum.x + maximum.x) / 2, y: size.y / 2,
                             z: (minimum.z + maximum.z) / 2)
        let desired = try ViewportWorldTransformAlgebra.transformedPoint(center, by: local)
        let sourceCenter = Point3D(x: center.x, y: nextSize.y / 2, z: center.z)
        let shift = try ViewportWorldTransformAlgebra.transformedVector(desired - sourceCenter, by: worldFromBox)
        let placement = try ViewportWorldTransformAlgebra.localTransform(
            applying: ViewportWorldTransformAlgebra.translation(shift), within: member.parentWorldTransform,
            to: member.baseLocalTransform) ?? member.baseLocalTransform
        guard (nextSize - size).length > 1e-12 || placement != member.baseLocalTransform else { return nil }
        return .init(placement: .init(reference: member.reference, sceneNodeID: member.sceneNodeID,
                                     baseLocalTransform: member.baseLocalTransform, localTransform: placement,
                                     baseParentWorldTransform: member.parentWorldTransform),
                     size: nextSize, documentID: documentID, designRevision: designRevision,
                     parameterRevision: parameterRevision)
    }
}
