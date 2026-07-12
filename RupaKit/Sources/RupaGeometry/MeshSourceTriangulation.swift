import Foundation

public extension MeshSource {
    func triangulate(
        faceID: MeshFaceID,
        tolerance: Double = 1e-9
    ) throws -> [MeshTriangle] {
        guard tolerance.isFinite, tolerance > 0 else {
            throw MeshTriangulationError(
                code: .failed,
                message: "Mesh triangulation tolerance must be finite and positive."
            )
        }
        let loop: MeshFaceLoop
        do {
            loop = try faceLoop(for: faceID)
        } catch {
            throw MeshTriangulationError(
                code: .missingFace,
                message: "Mesh face \(faceID.rawValue) is not available for triangulation."
            )
        }
        let vertexIDs = try loop.map { try vertexID(of: $0) }
        guard vertexIDs.count >= 3 else {
            throw MeshTriangulationError(
                code: .degenerate,
                message: "Mesh faces require at least three vertices for triangulation."
            )
        }
        if vertexIDs.count == 3 {
            return [MeshTriangle(faceID: faceID, vertexIDs: (vertexIDs[0], vertexIDs[1], vertexIDs[2]))]
        }
        let points = try vertexIDs.map(position(of:))
        let normal = try polygonNormal(points: points, tolerance: tolerance)
        for point in points.dropFirst() {
            let distance = dot(normal, subtract(point, points[0]))
            guard abs(distance) <= tolerance else {
                throw MeshTriangulationError(
                    code: .nonPlanar,
                    message: "Mesh n-gon faces must be planar before triangulation."
                )
            }
        }
        let projected = points.map { project($0, normal: normal) }
        let area = signedArea(projected)
        guard abs(area) > tolerance else {
            throw MeshTriangulationError(
                code: .degenerate,
                message: "Mesh n-gon faces must enclose a non-zero projected area."
            )
        }
        let orientation = area > 0 ? 1.0 : -1.0
        var remaining = Array(projected.indices)
        var triangles: [MeshTriangle] = []
        triangles.reserveCapacity(vertexIDs.count - 2)
        while remaining.count > 3 {
            var earIndex: Int?
            for candidateOffset in remaining.indices {
                let previousOffset = remaining.index(
                    candidateOffset,
                    offsetBy: -1,
                    limitedBy: remaining.startIndex
                ) ?? remaining.index(before: remaining.endIndex)
                let nextOffset = remaining.index(
                    candidateOffset,
                    offsetBy: 1,
                    limitedBy: remaining.index(before: remaining.endIndex)
                ) ?? remaining.startIndex
                let previous = remaining[previousOffset]
                let current = remaining[candidateOffset]
                let next = remaining[nextOffset]
                let cross = cross(projected[previous], projected[current], projected[next])
                guard orientation * cross > tolerance else {
                    continue
                }
                guard !remaining.contains(where: { index in
                    index != previous && index != current && index != next
                        && pointInTriangle(
                            projected[index],
                            projected[previous],
                            projected[current],
                            projected[next],
                            orientation: orientation,
                            tolerance: tolerance
                        )
                }) else {
                    continue
                }
                earIndex = candidateOffset
                triangles.append(
                    MeshTriangle(
                        faceID: faceID,
                        vertexIDs: (vertexIDs[previous], vertexIDs[current], vertexIDs[next])
                    )
                )
                break
            }
            guard let earIndex else {
                throw MeshTriangulationError(
                    code: .failed,
                    message: "Mesh n-gon ear clipping could not find a valid ear."
                )
            }
            remaining.remove(at: earIndex)
        }
        triangles.append(
            MeshTriangle(
                faceID: faceID,
                vertexIDs: (
                    vertexIDs[remaining[0]],
                    vertexIDs[remaining[1]],
                    vertexIDs[remaining[2]]
                )
            )
        )
        return triangles
    }

    func triangulateAll(tolerance: Double = 1e-9) throws -> [MeshTriangle] {
        try faceIDs.flatMap { try triangulate(faceID: $0, tolerance: tolerance) }
    }
}

private struct ProjectedPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

private func subtract(_ lhs: GeometryPoint3D, _ rhs: GeometryPoint3D) -> GeometryPoint3D {
    GeometryPoint3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
}

private func cross(_ lhs: GeometryPoint3D, _ rhs: GeometryPoint3D) -> GeometryPoint3D {
    GeometryPoint3D(
        x: lhs.y * rhs.z - lhs.z * rhs.y,
        y: lhs.z * rhs.x - lhs.x * rhs.z,
        z: lhs.x * rhs.y - lhs.y * rhs.x
    )
}

private func dot(_ lhs: GeometryPoint3D, _ rhs: GeometryPoint3D) -> Double {
    lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
}

private func polygonNormal(
    points: [GeometryPoint3D],
    tolerance: Double
) throws -> GeometryPoint3D {
    var normal = GeometryPoint3D(x: 0, y: 0, z: 0)
    for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        normal.x += (current.y - next.y) * (current.z + next.z)
        normal.y += (current.z - next.z) * (current.x + next.x)
        normal.z += (current.x - next.x) * (current.y + next.y)
    }
    let length = sqrt(dot(normal, normal))
    guard length.isFinite, length > tolerance else {
        throw MeshTriangulationError(
            code: .degenerate,
            message: "Mesh polygon normal could not be determined."
        )
    }
    return GeometryPoint3D(x: normal.x / length, y: normal.y / length, z: normal.z / length)
}

private func project(_ point: GeometryPoint3D, normal: GeometryPoint3D) -> ProjectedPoint {
    let ax = abs(normal.x)
    let ay = abs(normal.y)
    let az = abs(normal.z)
    if ax >= ay, ax >= az {
        return ProjectedPoint(x: point.y, y: point.z)
    }
    if ay >= ax, ay >= az {
        return ProjectedPoint(x: point.x, y: point.z)
    }
    return ProjectedPoint(x: point.x, y: point.y)
}

private func signedArea(_ points: [ProjectedPoint]) -> Double {
    var area = 0.0
    for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        area += current.x * next.y - next.x * current.y
    }
    return area / 2.0
}

private func cross(
    _ first: ProjectedPoint,
    _ second: ProjectedPoint,
    _ third: ProjectedPoint
) -> Double {
    (second.x - first.x) * (third.y - first.y)
        - (second.y - first.y) * (third.x - first.x)
}

private func pointInTriangle(
    _ point: ProjectedPoint,
    _ first: ProjectedPoint,
    _ second: ProjectedPoint,
    _ third: ProjectedPoint,
    orientation: Double,
    tolerance: Double
) -> Bool {
    let firstCross = orientation * cross(first, second, point)
    let secondCross = orientation * cross(second, third, point)
    let thirdCross = orientation * cross(third, first, point)
    return firstCross >= -tolerance && secondCross >= -tolerance && thirdCross >= -tolerance
}
