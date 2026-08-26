import RupaCore
import RupaViewportScene

public struct ViewportSectionMeshClipper: Sendable {
    private struct ClippedVertexBuffer {
        private var first: Vertex?
        private var second: Vertex?
        private var third: Vertex?
        private var fourth: Vertex?
        private(set) var count = 0

        mutating func append(_ vertex: Vertex) {
            if let last,
               Self.pointsAreEquivalent(last.point, vertex.point) {
                return
            }
            switch count {
            case 0:
                first = vertex
            case 1:
                second = vertex
            case 2:
                third = vertex
            case 3:
                fourth = vertex
            default:
                preconditionFailure("Clipping one triangle by one plane cannot create more than four vertices.")
            }
            count += 1
        }

        var last: Vertex? {
            switch count {
            case 0:
                nil
            case 1:
                first
            case 2:
                second
            case 3:
                third
            default:
                fourth
            }
        }

        var polygon: ViewportTrianglePolygon? {
            guard count >= 3,
                  let first,
                  let second,
                  let third else {
                return nil
            }
            return ViewportTrianglePolygon(
                first: first.point,
                second: second.point,
                third: third.point,
                fourth: fourth?.point
            )
        }

        private static func pointsAreEquivalent(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
            abs(lhs.x - rhs.x) <= 1.0e-12
                && abs(lhs.y - rhs.y) <= 1.0e-12
                && abs(lhs.z - rhs.z) <= 1.0e-12
        }
    }

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
        clippedWorldTrianglePolygon(
            first: ViewportLayout.transformedPoint(first, by: item.modelTransform),
            second: ViewportLayout.transformedPoint(second, by: item.modelTransform),
            third: ViewportLayout.transformedPoint(third, by: item.modelTransform),
            plane: plane,
            retaining: retainedSide,
            toleranceMeters: toleranceMeters
        ) != nil
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
        clippedWorldTriangle(
            first: ViewportLayout.transformedPoint(first, by: item.modelTransform),
            second: ViewportLayout.transformedPoint(second, by: item.modelTransform),
            third: ViewportLayout.transformedPoint(third, by: item.modelTransform),
            plane: plane,
            retaining: retainedSide,
            toleranceMeters: toleranceMeters
        )
    }

    public func clippedWorldTriangle(
        first: Point3D,
        second: Point3D,
        third: Point3D,
        plane: SectionAnalysisResult.Plane,
        retaining retainedSide: SectionAnalysisRetainedSide,
        toleranceMeters: Double
    ) -> [Point3D] {
        clippedWorldTrianglePolygon(
            first: first,
            second: second,
            third: third,
            plane: plane,
            retaining: retainedSide,
            toleranceMeters: toleranceMeters
        )?.points ?? []
    }

    func clippedWorldTrianglePolygon(
        first: Point3D,
        second: Point3D,
        third: Point3D,
        plane: SectionAnalysisResult.Plane,
        retaining retainedSide: SectionAnalysisRetainedSide,
        toleranceMeters: Double
    ) -> ViewportTrianglePolygon? {
        let tolerance = max(toleranceMeters, 0.0)
        let firstVertex = Vertex(point: first, signedDistance: signedDistance(first, to: plane))
        let secondVertex = Vertex(point: second, signedDistance: signedDistance(second, to: plane))
        let thirdVertex = Vertex(point: third, signedDistance: signedDistance(third, to: plane))
        var output = ClippedVertexBuffer()
        var previous = thirdVertex
        var previousInside = isInside(
            previous.signedDistance,
            retaining: retainedSide,
            toleranceMeters: tolerance
        )
        appendClippedEdge(
            current: firstVertex,
            previous: &previous,
            previousInside: &previousInside,
            output: &output,
            retaining: retainedSide,
            toleranceMeters: tolerance
        )
        appendClippedEdge(
            current: secondVertex,
            previous: &previous,
            previousInside: &previousInside,
            output: &output,
            retaining: retainedSide,
            toleranceMeters: tolerance
        )
        appendClippedEdge(
            current: thirdVertex,
            previous: &previous,
            previousInside: &previousInside,
            output: &output,
            retaining: retainedSide,
            toleranceMeters: tolerance
        )
        return output.polygon
    }

    private func appendClippedEdge(
        current: Vertex,
        previous: inout Vertex,
        previousInside: inout Bool,
        output: inout ClippedVertexBuffer,
        retaining retainedSide: SectionAnalysisRetainedSide,
        toleranceMeters: Double
    ) {
        let currentInside = isInside(
            current.signedDistance,
            retaining: retainedSide,
            toleranceMeters: toleranceMeters
        )
        if previousInside, currentInside {
            output.append(current)
        } else if previousInside, !currentInside {
            output.append(
                intersection(
                    from: previous,
                    to: current,
                    retaining: retainedSide,
                    toleranceMeters: toleranceMeters
                )
            )
        } else if !previousInside, currentInside {
            output.append(
                intersection(
                    from: previous,
                    to: current,
                    retaining: retainedSide,
                    toleranceMeters: toleranceMeters
                )
            )
            output.append(current)
        }
        previous = current
        previousInside = currentInside
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
