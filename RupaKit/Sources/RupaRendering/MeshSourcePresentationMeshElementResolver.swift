import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaViewportScene

/// Resolves CAD boundary tolerance from admitted provenance, never source geometry.
enum MeshSourcePresentationMeshElementResolver {
    static func resolve(
        at point: CGPoint,
        domain: GeometryAttributeDomain,
        in plan: MeshSourcePresentationRenderPlan,
        tolerance: CGFloat = 8,
        project: (Point3D) throws -> CGPoint,
        surfaceHit: (CGPoint) throws -> MeshSourcePresentationTriangle?
    ) throws -> ViewportMeshElementHit? {
        guard point.x.isFinite, point.y.isFinite, tolerance.isFinite, tolerance >= 0 else {
            throw MeshSourcePresentationRenderError(code: .invalidSceneItem, message: "Mesh element query coordinates or tolerance are invalid.")
        }
        if domain == .face {
            guard let triangle = try surfaceHit(point),
                  case .authoredMesh(let sourceID) = triangle.sourceReference else { return nil }
            return .init(snapshotID: plan.snapshotID, occurrenceID: triangle.occurrenceID,
                         sourceID: sourceID, element: .face(triangle.faceID))
        }
        guard domain == .vertex || domain == .edge else { return nil }
        var best: (hit: ViewportMeshElementHit, distance: CGFloat)?

        func consider(_ projected: CGPoint, element: MeshSelectionElement,
                      triangle: MeshSourcePresentationTriangle) throws {
            let distance = hypot(point.x - projected.x, point.y - projected.y)
            guard distance <= tolerance, distance < (best?.distance ?? .infinity),
                  case .authoredMesh(let sourceID) = triangle.sourceReference,
                  let visible = try surfaceHit(projected),
                  visible.occurrenceID == triangle.occurrenceID else { return }
            let incident: Bool
            switch element {
            case .vertex(let id):
                incident = visible.firstVertexID == id || visible.secondVertexID == id || visible.thirdVertexID == id
            case .edge(let id):
                incident = visible.firstEdgeID == id || visible.secondEdgeID == id || visible.thirdEdgeID == id
            default:
                incident = false
            }
            guard incident else { return }
            best = (.init(snapshotID: plan.snapshotID, occurrenceID: triangle.occurrenceID,
                          sourceID: sourceID, element: element), distance)
        }

        // Stream the admitted triangle ceiling with constant auxiliary storage.
        // Strict improvements preserve prepared order and deduplicate the result.
        try plan.forEachTriangle { triangle in
            try Task.checkCancellation()
            guard case .authoredMesh = triangle.sourceReference else { return }
            let a = try project(.init(x: triangle.firstPosition.x, y: triangle.firstPosition.y, z: triangle.firstPosition.z))
            let b = try project(.init(x: triangle.secondPosition.x, y: triangle.secondPosition.y, z: triangle.secondPosition.z))
            let c = try project(.init(x: triangle.thirdPosition.x, y: triangle.thirdPosition.y, z: triangle.thirdPosition.z))
            if domain == .vertex {
                try consider(a, element: .vertex(triangle.firstVertexID), triangle: triangle)
                try consider(b, element: .vertex(triangle.secondVertexID), triangle: triangle)
                try consider(c, element: .vertex(triangle.thirdVertexID), triangle: triangle)
            } else {
                if let edge = triangle.firstEdgeID {
                    try consider(nearestPoint(to: point, from: a, to: b), element: .edge(edge), triangle: triangle)
                }
                if let edge = triangle.secondEdgeID {
                    try consider(nearestPoint(to: point, from: b, to: c), element: .edge(edge), triangle: triangle)
                }
                if let edge = triangle.thirdEdgeID {
                    try consider(nearestPoint(to: point, from: c, to: a), element: .edge(edge), triangle: triangle)
                }
            }
        }
        return best?.hit
    }

    private static func nearestPoint(to point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return start }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return CGPoint(x: start.x + dx * t, y: start.y + dy * t)
    }
}
