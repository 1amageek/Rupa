import Foundation
import RupaCoreTypes

public extension MeshSource {
    /// Builds the one source-bound index used by repeated presentation reads.
    func makeTriangulationIndex() throws -> MeshSourceTriangulationIndex {
        var vertexIndexByID: [MeshVertexID: Int] = [:]
        vertexIndexByID.reserveCapacity(vertexIDs.count)
        for index in vertexIDs.indices {
            let vertexID = vertexIDs[index]
            guard vertexIndexByID.updateValue(index, forKey: vertexID) == nil else {
                throw MeshTriangulationError(
                    code: .invalidReference,
                    message: "Mesh triangulation requires unique vertex IDs."
                )
            }
        }
        return MeshSourceTriangulationIndex(
            sourceIdentity: identity,
            vertexCount: vertexIDs.count,
            sourceVertexStorageIdentity: vertexIDs.storageIdentityToken,
            vertexIndexByID: vertexIndexByID
        )
    }

    func triangulate(
        faceID: MeshFaceID,
        tolerance: Double = 1e-9
    ) throws -> [MeshTriangle] {
        try triangulate(faceID: faceID, tolerance: tolerance, limits: .standard)
    }

    func triangulate(
        faceID: MeshFaceID,
        tolerance: Double,
        limits: MeshTriangulationLimits
    ) throws -> [MeshTriangle] {
        var telemetry = MeshTriangulationTelemetry()
        let index = try makeTriangulationIndex()
        return try triangulate(
            faceID: faceID,
            using: index,
            tolerance: tolerance,
            limits: limits,
            telemetry: &telemetry
        )
    }

    /// Resolves a face ID once and delegates to the source-order face-index path.
    func triangulate(
        faceID: MeshFaceID,
        using index: MeshSourceTriangulationIndex,
        tolerance: Double = 1e-9,
        limits: MeshTriangulationLimits = .standard,
        telemetry: inout MeshTriangulationTelemetry
    ) throws -> [MeshTriangle] {
        try validateTriangulationInputs(
            tolerance: tolerance,
            limits: limits,
            index: index
        )
        guard let faceIndex = faceIDs.firstIndex(of: faceID) else {
            throw MeshTriangulationError(
                code: .missingFace,
                message: "Mesh face \(faceID.rawValue) is not available for triangulation."
            )
        }
        try telemetry.recordGlobalIdentifierScan()
        return try triangulate(
            faceIndex: faceIndex,
            using: index,
            tolerance: tolerance,
            limits: limits,
            telemetry: &telemetry
        )
    }

    /// Triangulates a face using validated source-order indices.
    func triangulate(
        faceIndex: Int,
        using index: MeshSourceTriangulationIndex,
        tolerance: Double = 1e-9,
        limits: MeshTriangulationLimits = .standard,
        telemetry: inout MeshTriangulationTelemetry
    ) throws -> [MeshTriangle] {
        try validateTriangulationInputs(
            tolerance: tolerance,
            limits: limits,
            index: index
        )
        guard faceIDs.indices.contains(faceIndex) else {
            throw MeshTriangulationError(
                code: .missingFace,
                message: "Mesh face index \(faceIndex) is not available for triangulation."
            )
        }
        try telemetry.recordFaceVisit()

        let faceID = faceIDs[faceIndex]
        guard faceIndex < faceCornerRanges.count else {
            throw MeshTriangulationError(
                code: .failed,
                message: "Mesh face \(faceID.rawValue) has no corner range."
            )
        }
        let range = faceCornerRanges[faceIndex]
        let checkedEnd = range.start.addingReportingOverflow(range.count)
        guard !checkedEnd.overflow else {
            throw MeshTriangulationError(
                code: .sizeOverflow,
                message: "Mesh face corner range overflowed during triangulation."
            )
        }
        do {
            try range.validate(upperBound: cornerVertexIDs.count)
        } catch let error as MeshSourceError {
            throw MeshTriangulationError(code: .invalidFaceRange, message: error.message)
        } catch {
            throw MeshTriangulationError(
                code: .invalidFaceRange,
                message: String(describing: error)
            )
        }
        guard range.count >= 3 else {
            throw MeshTriangulationError(
                code: .degenerateFace,
                message: "Mesh faces require at least three vertices for triangulation."
            )
        }
        guard range.count <= limits.maxFaceCornerCount else {
            throw MeshTriangulationError(
                code: .budgetExceeded,
                message: "Mesh face corner count exceeds the triangulation limit."
            )
        }
        guard checkedEnd.partialValue <= cornerVertexIDs.endIndex else {
            throw MeshTriangulationError(
                code: .invalidFaceRange,
                message: "Mesh face corner range exceeds the source buffer."
            )
        }

        var vertexIDs: [MeshVertexID] = []
        var points: [GeometryPoint3D] = []
        vertexIDs.reserveCapacity(range.count)
        points.reserveCapacity(range.count)

        for offset in 0..<range.count {
            let cornerIndex = range.start.addingReportingOverflow(offset)
            guard !cornerIndex.overflow,
                  cornerIndex.partialValue >= cornerIDs.startIndex,
                  cornerIndex.partialValue < cornerIDs.endIndex else {
                throw MeshTriangulationError(
                    code: .invalidReference,
                    message: "Mesh face corner index is outside the source buffer."
                )
            }
            let sourceCornerIndex = cornerIndex.partialValue
            guard sourceCornerIndex < cornerVertexIDs.endIndex else {
                throw MeshTriangulationError(
                    code: .invalidReference,
                    message: "Mesh face corner vertex index is outside the source buffer."
                )
            }
            try telemetry.recordCornerVisit()
            let vertexID = cornerVertexIDs[sourceCornerIndex]
            guard let positionIndex = index.positionIndex(for: vertexID),
                  positionIndex >= self.vertexIDs.startIndex,
                  positionIndex < self.vertexIDs.endIndex,
                  self.vertexIDs[positionIndex] == vertexID else {
                throw MeshTriangulationError(
                    code: .invalidReference,
                    message: "Mesh face corner references a vertex outside the indexed source."
                )
            }
            guard positionIndex < vertexPositions.endIndex else {
                throw MeshTriangulationError(
                    code: .invalidReference,
                    message: "Mesh face vertex position is outside the source buffer."
                )
            }
            try telemetry.recordIndexedVertexLookup()
            try telemetry.recordPositionRead()
            try telemetry.recordScratchPositionValue()
            vertexIDs.append(vertexID)
            points.append(vertexPositions[positionIndex])
        }

        if vertexIDs.count == 3 {
            return [
                MeshTriangle(
                    faceID: faceID,
                    vertexIDs: (vertexIDs[0], vertexIDs[1], vertexIDs[2])
                )
            ]
        }

        let normal = try polygonNormal(points: points, tolerance: tolerance)
        for point in points.dropFirst() {
            let distance = dot(normal, subtract(point, points[0]))
            guard distance.isFinite, abs(distance) <= tolerance else {
                throw MeshTriangulationError(
                    code: .nonPlanar,
                    message: "Mesh n-gon faces must be planar before triangulation."
                )
            }
        }

        let projected = points.map { project($0, normal: normal) }
        let area = signedArea(projected)
        guard area.isFinite else {
            throw MeshTriangulationError(
                code: .failed,
                message: "Mesh n-gon projected area is not finite."
            )
        }
        guard abs(area) > tolerance else {
            throw MeshTriangulationError(
                code: .degenerate,
                message: "Mesh n-gon faces must enclose a non-zero projected area."
            )
        }

        let orientation = area > 0 ? 1.0 : -1.0
        if try isConvexForLinearFan(projected, orientation: orientation) {
            var triangles: [MeshTriangle] = []
            triangles.reserveCapacity(vertexIDs.count - 2)
            for index in 1..<(vertexIDs.count - 1) {
                triangles.append(
                    MeshTriangle(
                        faceID: faceID,
                        vertexIDs: (vertexIDs[0], vertexIDs[index], vertexIDs[index + 1])
                    )
                )
            }
            return triangles
        }

        return try earClip(
            faceID: faceID,
            vertexIDs: vertexIDs,
            projected: projected,
            orientation: orientation,
            tolerance: tolerance,
            limits: limits,
            telemetry: &telemetry
        )
    }

    func triangulateAll(tolerance: Double = 1e-9) throws -> [MeshTriangle] {
        try triangulateAll(tolerance: tolerance, limits: .standard)
    }

    func triangulateAll(
        tolerance: Double,
        limits: MeshTriangulationLimits,
        telemetry: inout MeshTriangulationTelemetry
    ) throws -> [MeshTriangle] {
        try validateTriangulationInputs(
            tolerance: tolerance,
            limits: limits,
            index: nil
        )
        let index = try makeTriangulationIndex()
        var triangles: [MeshTriangle] = []
        for faceIndex in faceIDs.indices {
            let faceTriangles = try triangulate(
                faceIndex: faceIndex,
                using: index,
                tolerance: tolerance,
                limits: limits,
                telemetry: &telemetry
            )
            triangles.append(contentsOf: faceTriangles)
        }
        return triangles
    }

    func triangulateAll(
        tolerance: Double,
        limits: MeshTriangulationLimits
    ) throws -> [MeshTriangle] {
        var telemetry = MeshTriangulationTelemetry()
        return try triangulateAll(
            tolerance: tolerance,
            limits: limits,
            telemetry: &telemetry
        )
    }

    /// Counts only triangles accepted by the presentation triangulation path.
    ///
    /// Each face result is transient and is released before the next face is
    /// visited. The immutable source buffers are borrowed and never replaced.
    func triangulatedTriangleCount(
        tolerance: Double = 1e-9,
        limits: MeshTriangulationLimits = .standard,
        checkCancellation: @escaping @Sendable () throws -> Void = {
            try Task.checkCancellation()
        }
    ) throws -> UInt64 {
        var telemetry = MeshTriangulationTelemetry()
        return try triangulatedTriangleCount(
            tolerance: tolerance,
            limits: limits,
            telemetry: &telemetry,
            checkCancellation: checkCancellation
        )
    }

    /// Counts renderable triangles while reporting the shared triangulation work.
    func triangulatedTriangleCount(
        tolerance: Double = 1e-9,
        limits: MeshTriangulationLimits = .standard,
        telemetry: inout MeshTriangulationTelemetry,
        checkCancellation: @escaping @Sendable () throws -> Void = {
            try Task.checkCancellation()
        }
    ) throws -> UInt64 {
        try checkCancellation()
        try validateTriangulationInputs(
            tolerance: tolerance,
            limits: limits,
            index: nil
        )
        guard vertexIDs.count == vertexPositions.count else {
            throw MeshTriangulationError(
                code: .invalidReference,
                message: "Mesh vertex IDs and positions have different counts."
            )
        }
        guard faceIDs.count == faceCornerRanges.count else {
            throw MeshTriangulationError(
                code: .invalidFaceRange,
                message: "Mesh face IDs and corner ranges have different counts."
            )
        }
        guard cornerIDs.count == cornerVertexIDs.count else {
            throw MeshTriangulationError(
                code: .invalidReference,
                message: "Mesh corner IDs and vertex references have different counts."
            )
        }
        let index = try makeTriangulationIndex()
        try checkCancellation()
        var triangleCount: UInt64 = 0
        for faceIndex in faceCornerRanges.indices {
            try checkCancellation()
            let faceTriangles = try triangulate(
                faceIndex: faceIndex,
                using: index,
                tolerance: tolerance,
                limits: limits,
                telemetry: &telemetry
            )
            guard let faceTriangleCount = UInt64(exactly: faceTriangles.count) else {
                throw MeshTriangulationError(
                    code: .sizeOverflow,
                    message: "Mesh face triangle count exceeds the supported range."
                )
            }
            let addition = triangleCount.addingReportingOverflow(faceTriangleCount)
            guard !addition.overflow else {
                throw MeshTriangulationError(
                    code: .sizeOverflow,
                    message: "Mesh triangle count exceeds the supported range."
                )
            }
            triangleCount = addition.partialValue
        }
        try checkCancellation()
        return triangleCount
    }

    private func validateTriangulationInputs(
        tolerance: Double,
        limits: MeshTriangulationLimits,
        index: MeshSourceTriangulationIndex?
    ) throws {
        guard tolerance.isFinite, tolerance > 0 else {
            throw MeshTriangulationError(
                code: .failed,
                message: "Mesh triangulation tolerance must be finite and positive."
            )
        }
        guard limits.maxFaceCornerCount >= 3,
              limits.maxFaceCornerCount <= MeshTriangulationLimits.hardMaximum.maxFaceCornerCount,
              limits.maxNonConvexWorkUnits >= 0,
              limits.maxNonConvexWorkUnits
                  <= MeshTriangulationLimits.hardMaximum.maxNonConvexWorkUnits else {
            throw MeshTriangulationError(
                code: .invalidLimits,
                message: "Mesh triangulation limits are invalid."
            )
        }
        if let index, !index.isCompatible(with: self) {
            throw MeshTriangulationError(
                code: .invalidReference,
                message: "Mesh triangulation index does not match the source."
            )
        }
    }
}

private struct ProjectedPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

private extension MeshSource {
    func isConvexForLinearFan(
        _ points: [ProjectedPoint],
        orientation: Double
    ) throws -> Bool {
        guard points.count >= 3 else {
            throw MeshTriangulationError(
                code: .degenerate,
                message: "Mesh polygons require at least three projected points."
            )
        }
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let turn = orientation * cross(previous, current, next)
            guard turn.isFinite else {
                throw MeshTriangulationError(
                    code: .failed,
                    message: "Mesh polygon convexity could not be determined."
                )
            }
            let epsilon = try turnEpsilon(
                previous,
                current,
                next
            )
            if turn < -epsilon {
                return false
            }
            if turn <= epsilon {
                return false
            }
        }
        return true
    }

    func earClip(
        faceID: MeshFaceID,
        vertexIDs: [MeshVertexID],
        projected: [ProjectedPoint],
        orientation: Double,
        tolerance: Double,
        limits: MeshTriangulationLimits,
        telemetry: inout MeshTriangulationTelemetry
    ) throws -> [MeshTriangle] {
        var remaining = Array(projected.indices)
        var triangles: [MeshTriangle] = []
        triangles.reserveCapacity(vertexIDs.count - 2)

        while remaining.count > 3 {
            let remainingCount = remaining.count
            var earPosition: Int?
            for candidatePosition in 0..<remainingCount {
                try telemetry.recordNonConvexWork(
                    limit: limits.maxNonConvexWorkUnits
                )
                let previousPosition =
                    (candidatePosition + remainingCount - 1) % remainingCount
                let nextPosition = (candidatePosition + 1) % remainingCount
                let previous = remaining[previousPosition]
                let current = remaining[candidatePosition]
                let next = remaining[nextPosition]
                let turn = orientation * cross(
                    projected[previous],
                    projected[current],
                    projected[next]
                )
                let epsilon = try turnEpsilon(
                    projected[previous],
                    projected[current],
                    projected[next]
                )
                guard turn.isFinite, turn > epsilon else {
                    continue
                }

                var containsOtherPoint = false
                for pointIndex in remaining {
                    guard pointIndex != previous,
                          pointIndex != current,
                          pointIndex != next else {
                        continue
                    }
                    try telemetry.recordNonConvexWork(
                        limit: limits.maxNonConvexWorkUnits
                    )
                    if pointInTriangle(
                        projected[pointIndex],
                        projected[previous],
                        projected[current],
                        projected[next],
                        orientation: orientation,
                        tolerance: tolerance
                    ) {
                        containsOtherPoint = true
                        break
                    }
                }
                guard !containsOtherPoint else {
                    continue
                }

                earPosition = candidatePosition
                triangles.append(
                    MeshTriangle(
                        faceID: faceID,
                        vertexIDs: (
                            vertexIDs[previous],
                            vertexIDs[current],
                            vertexIDs[next]
                        )
                    )
                )
                break
            }

            guard let earPosition else {
                throw MeshTriangulationError(
                    code: .failed,
                    message: "Mesh n-gon ear clipping could not find a valid ear."
                )
            }
            remaining.remove(at: earPosition)
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

/// Returns a translation-invariant signed-turn threshold derived from the local
/// edge scale and representable coordinate precision, independent of the
/// caller's distance/planarity tolerance.
private func turnEpsilon(
    _ previous: ProjectedPoint,
    _ current: ProjectedPoint,
    _ next: ProjectedPoint
) throws -> Double {
    let firstEdgeLength = hypot(
        current.x - previous.x,
        current.y - previous.y
    )
    let secondEdgeLength = hypot(
        next.x - current.x,
        next.y - current.y
    )
    let closingEdgeLength = hypot(
        previous.x - next.x,
        previous.y - next.y
    )
    guard firstEdgeLength.isFinite,
          secondEdgeLength.isFinite,
          closingEdgeLength.isFinite else {
        throw MeshTriangulationError(
            code: .failed,
            message: "Mesh polygon convexity edge scale is not finite."
        )
    }
    let scale = max(firstEdgeLength, max(secondEdgeLength, closingEdgeLength))
    let squaredScale = scale * scale
    guard squaredScale.isFinite else {
        throw MeshTriangulationError(
            code: .failed,
            message: "Mesh polygon convexity scale is not finite."
        )
    }
    return 64.0 * Double.ulpOfOne * squaredScale
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
