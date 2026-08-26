import RupaCore
import RupaGeometry
import SwiftCAD

struct MeshSourcePresentationSectionGeometryResolver {
    private let plane: SectionAnalysisResult.Plane?
    private let retainedSide: SectionAnalysisRetainedSide
    private let toleranceMeters: Double

    init(
        sectionPlan: SectionAnalysisClippingPlan,
        plane: SectionAnalysisResult.Plane?,
        toleranceMeters: Double?
    ) {
        self.plane = plane
        self.retainedSide = sectionPlan.retainedSide
        self.toleranceMeters = max(toleranceMeters ?? 0.0, 0.0)
    }

    func polygon(
        for triangle: MeshSourcePresentationTriangle
    ) -> ViewportTrianglePolygon? {
        let first = point3D(triangle.firstPosition)
        let second = point3D(triangle.secondPosition)
        let third = point3D(triangle.thirdPosition)
        guard let plane else {
            return ViewportTrianglePolygon(first: first, second: second, third: third)
        }
        return ViewportSectionMeshClipper().clippedWorldTrianglePolygon(
            first: first,
            second: second,
            third: third,
            plane: plane,
            retaining: retainedSide,
            toleranceMeters: toleranceMeters
        )
    }

    private func point3D(_ point: GeometryPoint3D) -> Point3D {
        Point3D(x: point.x, y: point.y, z: point.z)
    }
}
