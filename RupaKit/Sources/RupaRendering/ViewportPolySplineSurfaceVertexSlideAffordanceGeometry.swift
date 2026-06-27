import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportPolySplineSurfaceVertexSlideInput: Equatable {
    var target: PolySplineSurfaceVertexTarget
    var selectionTarget: SelectionTarget
    var point: Point3D
    var modelTransform: Transform3D = .identity
}

struct ViewportSurfaceControlPointSlideInput: Equatable {
    var target: SelectionReference
    var featureID: FeatureID
    var patchID: Int
    var point: Point3D
    var modelTransform: Transform3D = .identity
}

struct ViewportPolySplineSurfaceVertexSlidePreviewVertex: Equatable {
    var selectionTarget: SelectionTarget
    var originalPoint: Point3D
    var movedPoint: Point3D
}

struct ViewportSurfaceControlPointSlidePreviewVertex: Equatable {
    var selectionReference: SelectionReference
    var originalPoint: Point3D
    var movedPoint: Point3D
}

struct ViewportPolySplineSurfaceVertexSlidePreviewSurface: Equatable {
    var featureID: FeatureID
    var patchID: Int
    var originalMesh: ViewportBodyMesh
    var movedMesh: ViewportBodyMesh
}

struct ViewportPolySplineSurfaceVertexSlideAffordanceGeometry: Equatable {
    var baseModelPoint: Point3D
    var modelDirection: Vector3D
    var minimumLengthMeters: Double

    init?(
        selectedVertices: [ViewportPolySplineSurfaceVertexSlideInput],
        topologyVertices: [ViewportBodyTopology.Vertex],
        direction: PolySplineSurfaceVertexSlideDirection,
        layout: ViewportLayout,
        viewportLength: CGFloat = 62.0
    ) {
        guard selectedVertices.isEmpty == false else {
            return nil
        }
        let pointsByRole = Self.pointsByRole(in: topologyVertices)
        let directionVectors = selectedVertices.compactMap { vertex -> Vector3D? in
            guard let direction = Self.slideDirection(
                for: vertex.target,
                direction: direction,
                pointsByRole: pointsByRole
            ) else {
                return nil
            }
            return vertex.modelTransform.viewportTransformedVector(direction)
        }
        guard directionVectors.count == selectedVertices.count,
              let averagedDirection = Self.averageVector(directionVectors) else {
            return nil
        }
        let center = Self.averagePoint(selectedVertices.map { vertex in
            vertex.modelTransform.viewportTransformedPoint(vertex.point)
        })
        let projectedUnitLength = Self.projectedLength(
            from: center,
            direction: averagedDirection,
            distanceMeters: 1.0,
            layout: layout
        )
        guard projectedUnitLength > 1.0e-9 else {
            return nil
        }
        self.baseModelPoint = center
        self.modelDirection = averagedDirection
        self.minimumLengthMeters = Double(viewportLength / projectedUnitLength)
    }

    init?(
        selectedControlPoints: [ViewportSurfaceControlPointSlideInput],
        topologyVertices: [ViewportBodyTopology.Vertex],
        direction: PolySplineSurfaceVertexSlideDirection,
        layout: ViewportLayout,
        viewportLength: CGFloat = 62.0
    ) {
        guard selectedControlPoints.isEmpty == false else {
            return nil
        }
        let pointsByRole = Self.pointsByRole(in: topologyVertices)
        let directionVectors = selectedControlPoints.compactMap { controlPoint -> Vector3D? in
            guard let direction = Self.slideDirection(
                featureID: controlPoint.featureID,
                patchID: controlPoint.patchID,
                direction: direction,
                pointsByRole: pointsByRole
            ) else {
                return nil
            }
            return controlPoint.modelTransform.viewportTransformedVector(direction)
        }
        guard directionVectors.count == selectedControlPoints.count,
              let averagedDirection = Self.averageVector(directionVectors) else {
            return nil
        }
        let center = Self.averagePoint(selectedControlPoints.map { controlPoint in
            controlPoint.modelTransform.viewportTransformedPoint(controlPoint.point)
        })
        let projectedUnitLength = Self.projectedLength(
            from: center,
            direction: averagedDirection,
            distanceMeters: 1.0,
            layout: layout
        )
        guard projectedUnitLength > 1.0e-9 else {
            return nil
        }
        self.baseModelPoint = center
        self.modelDirection = averagedDirection
        self.minimumLengthMeters = Double(viewportLength / projectedUnitLength)
    }

    func projectedTip(
        layout: ViewportLayout,
        distanceMeters: Double? = nil
    ) -> CGPoint {
        let distance = distanceMeters ?? minimumLengthMeters
        return layout.project(Self.offset(baseModelPoint, direction: modelDirection, distanceMeters: distance))
    }

    func slideDistance(
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double {
        let projectedVector = projectedUnitVector(layout: layout)
        guard projectedVector.length > 1.0e-9 else {
            return 0.0
        }
        let direction = projectedVector.normalized
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let viewportDistance = delta.dx * direction.dx + delta.dy * direction.dy
        return Double(viewportDistance / projectedVector.length)
    }

    static func previewVertices(
        selectedVertices: [ViewportPolySplineSurfaceVertexSlideInput],
        topologyVertices: [ViewportBodyTopology.Vertex],
        direction: PolySplineSurfaceVertexSlideDirection,
        distanceMeters: Double
    ) -> [ViewportPolySplineSurfaceVertexSlidePreviewVertex]? {
        guard selectedVertices.isEmpty == false else {
            return nil
        }
        let pointsByRole = pointsByRole(in: topologyVertices)
        let previewVertices = selectedVertices.compactMap { vertex -> ViewportPolySplineSurfaceVertexSlidePreviewVertex? in
            guard let direction = slideDirection(
                for: vertex.target,
                direction: direction,
                pointsByRole: pointsByRole
            ) else {
                return nil
            }
            let movedPoint = offset(vertex.point, direction: direction, distanceMeters: distanceMeters)
            return ViewportPolySplineSurfaceVertexSlidePreviewVertex(
                selectionTarget: vertex.selectionTarget,
                originalPoint: vertex.modelTransform.viewportTransformedPoint(vertex.point),
                movedPoint: vertex.modelTransform.viewportTransformedPoint(movedPoint)
            )
        }
        guard previewVertices.count == selectedVertices.count else {
            return nil
        }
        return previewVertices
    }

    static func previewControlPoints(
        selectedControlPoints: [ViewportSurfaceControlPointSlideInput],
        topologyVertices: [ViewportBodyTopology.Vertex],
        direction: PolySplineSurfaceVertexSlideDirection,
        distanceMeters: Double
    ) -> [ViewportSurfaceControlPointSlidePreviewVertex]? {
        guard selectedControlPoints.isEmpty == false else {
            return nil
        }
        let pointsByRole = pointsByRole(in: topologyVertices)
        let previewVertices = selectedControlPoints.compactMap { controlPoint -> ViewportSurfaceControlPointSlidePreviewVertex? in
            guard let direction = slideDirection(
                featureID: controlPoint.featureID,
                patchID: controlPoint.patchID,
                direction: direction,
                pointsByRole: pointsByRole
            ) else {
                return nil
            }
            let movedPoint = offset(controlPoint.point, direction: direction, distanceMeters: distanceMeters)
            return ViewportSurfaceControlPointSlidePreviewVertex(
                selectionReference: controlPoint.target,
                originalPoint: controlPoint.modelTransform.viewportTransformedPoint(controlPoint.point),
                movedPoint: controlPoint.modelTransform.viewportTransformedPoint(movedPoint)
            )
        }
        guard previewVertices.count == selectedControlPoints.count else {
            return nil
        }
        return previewVertices
    }

    static func previewSurfaces(
        selectedVertices: [ViewportPolySplineSurfaceVertexSlideInput],
        topologyVertices: [ViewportBodyTopology.Vertex],
        direction: PolySplineSurfaceVertexSlideDirection,
        distanceMeters: Double,
        sampleSegmentCount: Int = 8
    ) -> [ViewportPolySplineSurfaceVertexSlidePreviewSurface]? {
        guard selectedVertices.isEmpty == false else {
            return nil
        }
        let originalPointsByRole = pointsByRole(in: topologyVertices)
        var movedPointsByRole = originalPointsByRole
        var pendingMovedPoints: [PolySplineSurfaceVertexTarget: Point3D] = [:]
        var transformsByPatch: [PatchKey: Transform3D] = [:]
        var changedPatches: Set<PatchKey> = []
        let movedVertices = selectedVertices.compactMap { vertex -> MovedVertex? in
            guard let direction = slideDirection(
                for: vertex.target,
                direction: direction,
                pointsByRole: originalPointsByRole
            ) else {
                return nil
            }
            return MovedVertex(
                originalPoint: vertex.point,
                movedPoint: offset(vertex.point, direction: direction, distanceMeters: distanceMeters),
                modelTransform: vertex.modelTransform
            )
        }
        guard movedVertices.count == selectedVertices.count else {
            return nil
        }

        for (target, point) in originalPointsByRole {
            for movedVertex in movedVertices where isApproximatelyEqual(point, movedVertex.originalPoint) {
                let delta = vector(from: movedVertex.originalPoint, to: movedVertex.movedPoint)
                let movedPoint = offset(point, by: delta)
                if let existingPoint = pendingMovedPoints[target],
                   !isApproximatelyEqual(existingPoint, movedPoint) {
                    return nil
                }
                pendingMovedPoints[target] = movedPoint
                let patch = PatchKey(featureID: target.featureID, patchID: target.patchID)
                changedPatches.insert(patch)
                transformsByPatch[patch] = movedVertex.modelTransform
            }
        }

        guard changedPatches.isEmpty == false else {
            return nil
        }
        for (target, movedPoint) in pendingMovedPoints {
            movedPointsByRole[target] = movedPoint
        }

        let sortedPatches = changedPatches.sorted {
            if $0.featureID.description == $1.featureID.description {
                return $0.patchID < $1.patchID
            }
            return $0.featureID.description < $1.featureID.description
        }
        let surfaces = sortedPatches.compactMap { patch -> ViewportPolySplineSurfaceVertexSlidePreviewSurface? in
            guard let originalCorners = patchCorners(
                featureID: patch.featureID,
                patchID: patch.patchID,
                pointsByRole: originalPointsByRole
            ),
                  let movedCorners = patchCorners(
                      featureID: patch.featureID,
                      patchID: patch.patchID,
                      pointsByRole: movedPointsByRole
                  ),
                  let originalMesh = surfaceMesh(corners: originalCorners, sampleSegmentCount: sampleSegmentCount),
                  let movedMesh = surfaceMesh(corners: movedCorners, sampleSegmentCount: sampleSegmentCount) else {
                return nil
            }
            let transform = transformsByPatch[patch] ?? .identity
            return ViewportPolySplineSurfaceVertexSlidePreviewSurface(
                featureID: patch.featureID,
                patchID: patch.patchID,
                originalMesh: transformedMesh(originalMesh, transform: transform),
                movedMesh: transformedMesh(movedMesh, transform: transform)
            )
        }
        guard surfaces.count == sortedPatches.count else {
            return nil
        }
        return surfaces
    }

    static func localDirection(
        for target: PolySplineSurfaceVertexTarget,
        direction: PolySplineSurfaceVertexSlideDirection,
        topologyVertices: [ViewportBodyTopology.Vertex]
    ) -> Vector3D? {
        slideDirection(
            for: target,
            direction: direction,
            pointsByRole: pointsByRole(in: topologyVertices)
        )
    }

    private func projectedUnitVector(layout: ViewportLayout) -> CGVector {
        let start = layout.project(baseModelPoint)
        let end = layout.project(Self.offset(baseModelPoint, direction: modelDirection, distanceMeters: 1.0))
        return CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    private static func pointsByRole(
        in topologyVertices: [ViewportBodyTopology.Vertex]
    ) -> [PolySplineSurfaceVertexTarget: Point3D] {
        var points: [PolySplineSurfaceVertexTarget: Point3D] = [:]
        for vertex in topologyVertices {
            guard let target = PolySplineSurfaceVertexTarget.parse(componentID: vertex.componentID) else {
                continue
            }
            points[target] = vertex.point
        }
        return points
    }

    private static func patchCorners(
        featureID: FeatureID,
        patchID: Int,
        pointsByRole: [PolySplineSurfaceVertexTarget: Point3D]
    ) -> (bottomLeft: Point3D, bottomRight: Point3D, topRight: Point3D, topLeft: Point3D)? {
        let uMinVMin = PolySplineSurfaceVertexTarget(
            featureID: featureID,
            patchID: patchID,
            boundaryRole: .uMinVMin
        )
        let uMaxVMin = PolySplineSurfaceVertexTarget(
            featureID: featureID,
            patchID: patchID,
            boundaryRole: .uMaxVMin
        )
        let uMaxVMax = PolySplineSurfaceVertexTarget(
            featureID: featureID,
            patchID: patchID,
            boundaryRole: .uMaxVMax
        )
        let uMinVMax = PolySplineSurfaceVertexTarget(
            featureID: featureID,
            patchID: patchID,
            boundaryRole: .uMinVMax
        )
        guard let bottomLeft = pointsByRole[uMinVMin],
              let bottomRight = pointsByRole[uMaxVMin],
              let topRight = pointsByRole[uMaxVMax],
              let topLeft = pointsByRole[uMinVMax] else {
            return nil
        }
        return (bottomLeft, bottomRight, topRight, topLeft)
    }

    private static func surfaceMesh(
        corners: (bottomLeft: Point3D, bottomRight: Point3D, topRight: Point3D, topLeft: Point3D),
        sampleSegmentCount: Int
    ) -> ViewportBodyMesh? {
        let segmentCount = max(sampleSegmentCount, 1)
        let surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: corners.bottomLeft,
            bottomRight: corners.bottomRight,
            topRight: corners.topRight,
            topLeft: corners.topLeft
        )
        var positions: [Point3D] = []
        positions.reserveCapacity((segmentCount + 1) * (segmentCount + 1))
        do {
            for vIndex in 0...segmentCount {
                let v = Double(vIndex) / Double(segmentCount)
                for uIndex in 0...segmentCount {
                    let u = Double(uIndex) / Double(segmentCount)
                    positions.append(try surface.point(u: u, v: v))
                }
            }
        } catch {
            return nil
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(segmentCount * segmentCount * 6)
        let rowStride = segmentCount + 1
        for vIndex in 0..<segmentCount {
            for uIndex in 0..<segmentCount {
                let lowerLeft = UInt32(vIndex * rowStride + uIndex)
                let lowerRight = UInt32(vIndex * rowStride + uIndex + 1)
                let upperLeft = UInt32((vIndex + 1) * rowStride + uIndex)
                let upperRight = UInt32((vIndex + 1) * rowStride + uIndex + 1)
                indices.append(contentsOf: [
                    lowerLeft,
                    lowerRight,
                    upperRight,
                    lowerLeft,
                    upperRight,
                    upperLeft,
                ])
            }
        }
        return ViewportBodyMesh(positions: positions, indices: indices)
    }

    private static func slideDirection(
        for target: PolySplineSurfaceVertexTarget,
        direction: PolySplineSurfaceVertexSlideDirection,
        pointsByRole: [PolySplineSurfaceVertexTarget: Point3D]
    ) -> Vector3D? {
        let uMinVMin = PolySplineSurfaceVertexTarget(
            featureID: target.featureID,
            patchID: target.patchID,
            boundaryRole: .uMinVMin
        )
        let uMaxVMin = PolySplineSurfaceVertexTarget(
            featureID: target.featureID,
            patchID: target.patchID,
            boundaryRole: .uMaxVMin
        )
        let uMaxVMax = PolySplineSurfaceVertexTarget(
            featureID: target.featureID,
            patchID: target.patchID,
            boundaryRole: .uMaxVMax
        )
        let uMinVMax = PolySplineSurfaceVertexTarget(
            featureID: target.featureID,
            patchID: target.patchID,
            boundaryRole: .uMinVMax
        )
        guard let pointUMinVMin = pointsByRole[uMinVMin],
              let pointUMaxVMin = pointsByRole[uMaxVMin],
              let pointUMaxVMax = pointsByRole[uMaxVMax],
              let pointUMinVMax = pointsByRole[uMinVMax] else {
            return nil
        }

        let positiveURaw: Vector3D
        switch target.boundaryRole {
        case .uMinVMin, .uMaxVMin:
            positiveURaw = vector(from: pointUMinVMin, to: pointUMaxVMin)
        case .uMaxVMax, .uMinVMax:
            positiveURaw = vector(from: pointUMinVMax, to: pointUMaxVMax)
        }

        let positiveVRaw: Vector3D
        switch target.boundaryRole {
        case .uMinVMin, .uMinVMax:
            positiveVRaw = vector(from: pointUMinVMin, to: pointUMinVMax)
        case .uMaxVMin, .uMaxVMax:
            positiveVRaw = vector(from: pointUMaxVMin, to: pointUMaxVMax)
        }

        guard let positiveU = normalized(positiveURaw),
              let positiveV = normalized(positiveVRaw),
              let normal = normalized(positiveU.cross(positiveV)) else {
            return nil
        }

        switch direction {
        case .positiveU:
            return positiveU
        case .negativeU:
            return negated(positiveU)
        case .normal:
            return normal
        case .positiveV:
            return positiveV
        case .negativeV:
            return negated(positiveV)
        }
    }

    private static func slideDirection(
        featureID: FeatureID,
        patchID: Int,
        direction: PolySplineSurfaceVertexSlideDirection,
        pointsByRole: [PolySplineSurfaceVertexTarget: Point3D]
    ) -> Vector3D? {
        guard let corners = patchCorners(
            featureID: featureID,
            patchID: patchID,
            pointsByRole: pointsByRole
        ) else {
            return nil
        }
        guard let bottomU = normalized(vector(from: corners.bottomLeft, to: corners.bottomRight)),
              let topU = normalized(vector(from: corners.topLeft, to: corners.topRight)),
              let leftV = normalized(vector(from: corners.bottomLeft, to: corners.topLeft)),
              let rightV = normalized(vector(from: corners.bottomRight, to: corners.topRight)),
              let positiveU = normalized(Vector3D(
                  x: bottomU.x + topU.x,
                  y: bottomU.y + topU.y,
                  z: bottomU.z + topU.z
              )),
              let positiveV = normalized(Vector3D(
                  x: leftV.x + rightV.x,
                  y: leftV.y + rightV.y,
                  z: leftV.z + rightV.z
              )),
              let normal = normalized(positiveU.cross(positiveV)) else {
            return nil
        }

        switch direction {
        case .positiveU:
            return positiveU
        case .negativeU:
            return negated(positiveU)
        case .normal:
            return normal
        case .positiveV:
            return positiveV
        case .negativeV:
            return negated(positiveV)
        }
    }

    private static func averageVector(_ vectors: [Vector3D]) -> Vector3D? {
        guard vectors.isEmpty == false else {
            return nil
        }
        let sum = vectors.reduce(Vector3D(x: 0.0, y: 0.0, z: 0.0)) { partial, vector in
            Vector3D(
                x: partial.x + vector.x,
                y: partial.y + vector.y,
                z: partial.z + vector.z
            )
        }
        let count = Double(vectors.count)
        let average = Vector3D(
            x: sum.x / count,
            y: sum.y / count,
            z: sum.z / count
        )
        guard average.length > 1.0e-12 else {
            return nil
        }
        return average
    }

    private static func averagePoint(_ points: [Point3D]) -> Point3D {
        guard points.isEmpty == false else {
            return Point3D(x: 0.0, y: 0.0, z: 0.0)
        }
        let sum = points.reduce(Point3D(x: 0.0, y: 0.0, z: 0.0)) { partial, point in
            Point3D(
                x: partial.x + point.x,
                y: partial.y + point.y,
                z: partial.z + point.z
            )
        }
        let count = Double(points.count)
        return Point3D(
            x: sum.x / count,
            y: sum.y / count,
            z: sum.z / count
        )
    }

    private static func projectedLength(
        from point: Point3D,
        direction: Vector3D,
        distanceMeters: Double,
        layout: ViewportLayout
    ) -> CGFloat {
        let start = layout.project(point)
        let end = layout.project(offset(point, direction: direction, distanceMeters: distanceMeters))
        return hypot(end.x - start.x, end.y - start.y)
    }

    private static func offset(
        _ point: Point3D,
        direction: Vector3D,
        distanceMeters: Double
    ) -> Point3D {
        Point3D(
            x: point.x + direction.x * distanceMeters,
            y: point.y + direction.y * distanceMeters,
            z: point.z + direction.z * distanceMeters
        )
    }

    private static func offset(_ point: Point3D, by vector: Vector3D) -> Point3D {
        Point3D(
            x: point.x + vector.x,
            y: point.y + vector.y,
            z: point.z + vector.z
        )
    }

    private static func vector(from start: Point3D, to end: Point3D) -> Vector3D {
        Vector3D(
            x: end.x - start.x,
            y: end.y - start.y,
            z: end.z - start.z
        )
    }

    private static func normalized(_ vector: Vector3D) -> Vector3D? {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        guard length > 1.0e-12 else {
            return nil
        }
        return Vector3D(
            x: vector.x / length,
            y: vector.y / length,
            z: vector.z / length
        )
    }

    private static func negated(_ vector: Vector3D) -> Vector3D {
        Vector3D(x: -vector.x, y: -vector.y, z: -vector.z)
    }

    private static func transformedMesh(
        _ mesh: ViewportBodyMesh,
        transform: Transform3D
    ) -> ViewportBodyMesh {
        ViewportBodyMesh(
            positions: mesh.positions.map { transform.viewportTransformedPoint($0) },
            indices: mesh.indices
        )
    }

    private static func isApproximatelyEqual(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        abs(lhs.x - rhs.x) <= 1.0e-10
            && abs(lhs.y - rhs.y) <= 1.0e-10
            && abs(lhs.z - rhs.z) <= 1.0e-10
    }

    private struct PatchKey: Hashable {
        var featureID: FeatureID
        var patchID: Int
    }

    private struct MovedVertex {
        var originalPoint: Point3D
        var movedPoint: Point3D
        var modelTransform: Transform3D
    }
}
