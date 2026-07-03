import RupaCore
import RupaViewportScene

public struct ViewportSectionMeshClipper: Sendable {
    public struct Vertex: Equatable, Sendable {
        public var point: Point3D
        public var signedDistance: Double

        public init(point: Point3D, signedDistance: Double) {
            self.point = point
            self.signedDistance = signedDistance
        }
    }

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
        clippedTriangle(
            first: first,
            second: second,
            third: third,
            item: item,
            plane: plane,
            retaining: retainedSide,
            toleranceMeters: toleranceMeters
        ).count >= 3
    }

    public func clippedTriangle(
        first: Point3D,
        second: Point3D,
        third: Point3D,
        item: ViewportSceneItem,
        plane: SectionAnalysisResult.Plane,
        retaining retainedSide: SectionAnalysisRetainedSide,
        toleranceMeters: Double
    ) -> [Point3D] {
        let tolerance = max(toleranceMeters, 0.0)
        let points = [
            ViewportLayout.transformedPoint(first, by: item.modelTransform),
            ViewportLayout.transformedPoint(second, by: item.modelTransform),
            ViewportLayout.transformedPoint(third, by: item.modelTransform),
        ]
        let vertices = points.map { point in
            Vertex(point: point, signedDistance: signedDistance(point, to: plane))
        }
        return clippedPolygon(
            vertices,
            retaining: retainedSide,
            toleranceMeters: tolerance
        ).map(\.point)
    }

    private func clippedPolygon(
        _ vertices: [Vertex],
        retaining retainedSide: SectionAnalysisRetainedSide,
        toleranceMeters: Double
    ) -> [Vertex] {
        guard vertices.count >= 3 else {
            return []
        }
        var output: [Vertex] = []
        var previous = vertices[vertices.count - 1]
        var previousInside = isInside(
            previous.signedDistance,
            retaining: retainedSide,
            toleranceMeters: toleranceMeters
        )
        for current in vertices {
            let currentInside = isInside(
                current.signedDistance,
                retaining: retainedSide,
                toleranceMeters: toleranceMeters
            )
            if previousInside, currentInside {
                append(current, to: &output)
            } else if previousInside, !currentInside {
                append(
                    intersection(
                        from: previous,
                        to: current,
                        retaining: retainedSide,
                        toleranceMeters: toleranceMeters
                    ),
                    to: &output
                )
            } else if !previousInside, currentInside {
                append(
                    intersection(
                        from: previous,
                        to: current,
                        retaining: retainedSide,
                        toleranceMeters: toleranceMeters
                    ),
                    to: &output
                )
                append(current, to: &output)
            }
            previous = current
            previousInside = currentInside
        }
        return output.filter { vertex in
            isInside(
                vertex.signedDistance,
                retaining: retainedSide,
                toleranceMeters: toleranceMeters
            )
        }
    }

    private func isInside(
        _ signedDistance: Double,
        retaining retainedSide: SectionAnalysisRetainedSide,
        toleranceMeters: Double
    ) -> Bool {
        switch retainedSide {
        case .front:
            return signedDistance >= -toleranceMeters
        case .behind:
            return signedDistance <= toleranceMeters
        }
    }

    private func intersection(
        from start: Vertex,
        to end: Vertex,
        retaining retainedSide: SectionAnalysisRetainedSide,
        toleranceMeters: Double
    ) -> Vertex {
        let boundary = retainedSide == .front ? -toleranceMeters : toleranceMeters
        let denominator = end.signedDistance - start.signedDistance
        guard abs(denominator) > 1.0e-15 else {
            return start
        }
        let fraction = min(max((boundary - start.signedDistance) / denominator, 0.0), 1.0)
        let point = interpolatedPoint(from: start.point, to: end.point, fraction: fraction)
        return Vertex(point: point, signedDistance: boundary)
    }

    private func append(_ vertex: Vertex, to vertices: inout [Vertex]) {
        guard let last = vertices.last else {
            vertices.append(vertex)
            return
        }
        if pointsAreEquivalent(last.point, vertex.point) {
            return
        }
        vertices.append(vertex)
    }

    private func interpolatedPoint(
        from start: Point3D,
        to end: Point3D,
        fraction: Double
    ) -> Point3D {
        Point3D(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction,
            z: start.z + (end.z - start.z) * fraction
        )
    }

    private func pointsAreEquivalent(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        abs(lhs.x - rhs.x) <= 1.0e-12
            && abs(lhs.y - rhs.y) <= 1.0e-12
            && abs(lhs.z - rhs.z) <= 1.0e-12
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
