import RupaCore
import RupaViewportScene

public struct ViewportSectionMeshClipper: Sendable {
    public init() {}

    public func includedTriangleCount(
        mesh: ViewportBodyMesh,
        item: ViewportSceneItem,
        plane: SectionAnalysisResult.Plane,
        retaining retainedSide: SectionAnalysisRetainedSide,
        toleranceMeters: Double
    ) -> Int {
        var count = 0
        var index = 0
        while index + 2 < mesh.indices.count {
            let firstIndex = Int(mesh.indices[index])
            let secondIndex = Int(mesh.indices[index + 1])
            let thirdIndex = Int(mesh.indices[index + 2])
            if firstIndex < mesh.positions.count,
               secondIndex < mesh.positions.count,
               thirdIndex < mesh.positions.count,
               includesTriangle(
                   first: mesh.positions[firstIndex],
                   second: mesh.positions[secondIndex],
                   third: mesh.positions[thirdIndex],
                   item: item,
                   plane: plane,
                   retaining: retainedSide,
                   toleranceMeters: toleranceMeters
               ) {
                count += 1
            }
            index += 3
        }
        return count
    }

    public func includesTriangle(
        first: Point3D,
        second: Point3D,
        third: Point3D,
        item: ViewportSceneItem,
        plane: SectionAnalysisResult.Plane,
        retaining retainedSide: SectionAnalysisRetainedSide,
        toleranceMeters: Double
    ) -> Bool {
        let tolerance = max(toleranceMeters, 0.0)
        let distances = [
            signedDistance(
                ViewportLayout.transformedPoint(first, by: item.modelTransform),
                to: plane
            ),
            signedDistance(
                ViewportLayout.transformedPoint(second, by: item.modelTransform),
                to: plane
            ),
            signedDistance(
                ViewportLayout.transformedPoint(third, by: item.modelTransform),
                to: plane
            ),
        ]

        switch retainedSide {
        case .front:
            return distances.contains { $0 >= -tolerance }
        case .behind:
            return distances.contains { $0 <= tolerance }
        }
    }

    private func signedDistance(
        _ point: Point3D,
        to plane: SectionAnalysisResult.Plane
    ) -> Double {
        let dx = point.x - plane.origin.x
        let dy = point.y - plane.origin.y
        let dz = point.z - plane.origin.z
        return dx * plane.normal.x
            + dy * plane.normal.y
            + dz * plane.normal.z
    }
}
