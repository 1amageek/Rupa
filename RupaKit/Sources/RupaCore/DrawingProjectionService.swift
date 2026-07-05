import Foundation
import SwiftCAD
import RupaCoreTypes

public struct DrawingProjectionService: Sendable {
    private struct ProjectionBasis {
        var xDirection: Point2D
        var yDirection: Point2D
        var zDirection: Point2D
        var right: Vector3D
        var up: Vector3D
        var viewNormal: Vector3D
    }

    private struct QuantizedPoint: Hashable, Comparable {
        var x: Int64
        var y: Int64
        var z: Int64

        static func < (left: QuantizedPoint, right: QuantizedPoint) -> Bool {
            if left.x != right.x {
                return left.x < right.x
            }
            if left.y != right.y {
                return left.y < right.y
            }
            return left.z < right.z
        }
    }

    private struct EdgeKey: Hashable, Comparable {
        var first: QuantizedPoint
        var second: QuantizedPoint

        init(_ first: QuantizedPoint, _ second: QuantizedPoint) {
            if second < first {
                self.first = second
                self.second = first
            } else {
                self.first = first
                self.second = second
            }
        }

        static func < (left: EdgeKey, right: EdgeKey) -> Bool {
            if left.first != right.first {
                return left.first < right.first
            }
            return left.second < right.second
        }
    }

    private struct EdgeAccumulator {
        var key: EdgeKey
        var start: Point3D
        var end: Point3D
        var normals: [Vector3D]

        mutating func include(normal: Vector3D) {
            normals.append(normal)
        }
    }

    private struct ProjectedTriangle {
        var first2D: Point2D
        var second2D: Point2D
        var third2D: Point2D
        var firstDepth: Double
        var secondDepth: Double
        var thirdDepth: Double
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
    }

    private struct FractionInterval {
        var start: Double
        var end: Double
    }

    private struct BoundsAccumulator {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity

        var bounds: DrawingProjectionResult.Bounds2D? {
            guard minX.isFinite,
                  minY.isFinite,
                  maxX.isFinite,
                  maxY.isFinite else {
                return nil
            }
            return DrawingProjectionResult.Bounds2D(
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY
            )
        }

        mutating func include(_ point: Point2D) {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
    }

    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func generate(
        document: DesignDocument,
        query: DrawingProjectionQuery,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> DrawingProjectionResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before drawing projection: \(String(describing: error))"
            )
        }

        guard query.maximumStrokeCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Drawing projection maximum stroke count must be positive."
            )
        }
        let tolerance = try resolvedTolerance(query.toleranceMeters, document: document)
        let savedView = try resolvedSavedView(id: query.savedViewID, document: document)
        guard savedView.projection.mode == .orthographic else {
            throw EditorError(
                code: .commandInvalid,
                message: "Drawing projection currently requires an orthographic saved view."
            )
        }
        let basis = try projectionBasis(for: savedView)
        let projectionMode = projectionMode(for: savedView.projection.mode)
        let viewFrame = DrawingProjectionResult.ViewFrame(
            target: savedView.camera.target,
            right: basis.right,
            up: basis.up,
            viewNormal: basis.viewNormal,
            visibleHeightMeters: savedView.projection.orthographicHeightMeters
                ?? savedView.camera.distanceMeters,
            scaleBarLengthMeters: savedView.displayScale.scaleBarLengthMeters
        )

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return DrawingProjectionResult(
                displayUnit: document.displayUnit,
                savedViewID: savedView.id,
                savedViewName: savedView.name,
                projectionMode: projectionMode,
                viewFrame: viewFrame,
                bodyCount: 0,
                triangleCount: 0,
                candidateEdgeCount: 0,
                truncatedStrokes: false,
                bounds: nil,
                strokes: [],
                diagnostics: [
                    EditorDiagnostic(
                        severity: .info,
                        message: "Drawing projection completed with no generated body meshes."
                    ),
                ]
            )
        }

        let evaluatedDocument = try DocumentEvaluationContextResolver(
            pipeline: pipelineOverride
        ).evaluatedDocument(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration,
            failurePrefix: "Document must evaluate successfully before drawing projection"
        )

        let sortedMeshes = evaluatedDocument.meshes.sorted {
            $0.key.description < $1.key.description
        }
        var bodyEdges: [(bodyID: BodyID, edges: [EdgeAccumulator])] = []
        var occludingTriangles: [ProjectedTriangle] = []
        var strokes: [DrawingProjectionResult.Stroke] = []
        var bounds = BoundsAccumulator()
        var candidateEdgeCount = 0
        var triangleCount = 0
        var truncatedStrokes = false

        for (bodyID, mesh) in sortedMeshes {
            let edges = try drawingEdges(
                mesh: mesh,
                tolerance: tolerance
            )
            triangleCount += mesh.indices.count / 3
            candidateEdgeCount += edges.count
            bodyEdges.append((bodyID, edges))
            occludingTriangles.append(contentsOf: try projectedTriangles(
                mesh: mesh,
                savedView: savedView,
                basis: basis,
                tolerance: tolerance
            ))
        }

        for (bodyID, edges) in bodyEdges {
            for edge in edges.sorted(by: { $0.key < $1.key }) {
                if strokes.count >= query.maximumStrokeCount {
                    truncatedStrokes = true
                    break
                }
                guard var stroke = stroke(
                    edge: edge,
                    bodyID: bodyID,
                    index: strokes.count,
                    savedView: savedView,
                    basis: basis
                ) else {
                    continue
                }
                stroke.visibilitySegments = visibilitySegments(
                    stroke: stroke,
                    triangles: occludingTriangles,
                    savedView: savedView,
                    basis: basis,
                    tolerance: tolerance
                )
                stroke.visibility = visibility(from: stroke.visibilitySegments)
                bounds.include(stroke.start2D)
                bounds.include(stroke.end2D)
                strokes.append(stroke)
            }

            if truncatedStrokes {
                break
            }
        }

        return DrawingProjectionResult(
            displayUnit: document.displayUnit,
            savedViewID: savedView.id,
            savedViewName: savedView.name,
            projectionMode: projectionMode,
            viewFrame: viewFrame,
            bodyCount: evaluatedDocument.meshes.count,
            triangleCount: triangleCount,
            candidateEdgeCount: candidateEdgeCount,
            truncatedStrokes: truncatedStrokes,
            bounds: bounds.bounds,
            strokes: strokes,
            diagnostics: diagnostics(
                result: strokes,
                candidateEdgeCount: candidateEdgeCount,
                truncatedStrokes: truncatedStrokes,
                maximumStrokeCount: query.maximumStrokeCount
            )
        )
    }

    private func resolvedSavedView(
        id: SavedViewID,
        document: DesignDocument
    ) throws -> SavedView {
        guard let savedView = document.productMetadata.savedViews[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Saved view \(id) does not exist."
            )
        }
        return savedView
    }

    private func resolvedTolerance(
        _ tolerance: Double?,
        document: DesignDocument
    ) throws -> Double {
        let resolved = tolerance ?? ModelingTolerance.workspaceScaleAware(for: document).distance
        guard resolved.isFinite,
              resolved > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Drawing projection tolerance must be finite and positive."
            )
        }
        return resolved
    }

    private func projectionMode(
        for mode: SavedViewProjection.Mode
    ) -> DrawingProjectionResult.ProjectionMode {
        switch mode {
        case .orthographic:
            return .orthographic
        case .perspective:
            return .perspective
        }
    }

    private func projectionBasis(
        for savedView: SavedView
    ) throws -> ProjectionBasis {
        let yaw = savedView.camera.yawRadians
        let elevation = clampedOrbitElevation(savedView.camera.pitchRadians)
        let elevationSine = sin(elevation)
        let elevationCosine = cos(elevation)
        let xDirection = Point2D(x: cos(yaw), y: elevationSine * sin(yaw))
        let yDirection = Point2D(x: 0.0, y: -elevationCosine)
        let zDirection = Point2D(x: -sin(yaw), y: elevationSine * cos(yaw))
        let right = Vector3D(
            x: xDirection.x,
            y: yDirection.x,
            z: zDirection.x
        )
        let up = Vector3D(
            x: xDirection.y,
            y: yDirection.y,
            z: zDirection.y
        )
        let viewNormal = try up.cross(right).normalized(tolerance: 1.0e-12)
        return ProjectionBasis(
            xDirection: xDirection,
            yDirection: yDirection,
            zDirection: zDirection,
            right: right,
            up: up,
            viewNormal: viewNormal
        )
    }

    private func clampedOrbitElevation(_ elevation: Double) -> Double {
        min(max(elevation, 0.08), 1.42)
    }

    private func drawingEdges(
        mesh: Mesh,
        tolerance: Double
    ) throws -> [EdgeAccumulator] {
        guard mesh.indices.count.isMultiple(of: 3) else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Drawing projection requires triangle mesh indices."
            )
        }
        var edges: [EdgeKey: EdgeAccumulator] = [:]
        var triangleStart = 0
        while triangleStart < mesh.indices.count {
            let firstIndex = Int(mesh.indices[triangleStart])
            let secondIndex = Int(mesh.indices[triangleStart + 1])
            let thirdIndex = Int(mesh.indices[triangleStart + 2])
            guard firstIndex < mesh.positions.count,
                  secondIndex < mesh.positions.count,
                  thirdIndex < mesh.positions.count else {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "Drawing projection mesh index is out of range."
                )
            }
            let first = mesh.positions[firstIndex]
            let second = mesh.positions[secondIndex]
            let third = mesh.positions[thirdIndex]
            if let normal = triangleNormal(first, second, third, tolerance: tolerance) {
                includeEdge(start: first, end: second, normal: normal, tolerance: tolerance, edges: &edges)
                includeEdge(start: second, end: third, normal: normal, tolerance: tolerance, edges: &edges)
                includeEdge(start: third, end: first, normal: normal, tolerance: tolerance, edges: &edges)
            }
            triangleStart += 3
        }
        return edges.values.filter { edge in
            shouldEmit(edge)
        }
    }

    private func projectedTriangles(
        mesh: Mesh,
        savedView: SavedView,
        basis: ProjectionBasis,
        tolerance: Double
    ) throws -> [ProjectedTriangle] {
        guard mesh.indices.count.isMultiple(of: 3) else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Drawing projection requires triangle mesh indices."
            )
        }
        var triangles: [ProjectedTriangle] = []
        triangles.reserveCapacity(mesh.indices.count / 3)
        var triangleStart = 0
        while triangleStart < mesh.indices.count {
            let firstIndex = Int(mesh.indices[triangleStart])
            let secondIndex = Int(mesh.indices[triangleStart + 1])
            let thirdIndex = Int(mesh.indices[triangleStart + 2])
            guard firstIndex < mesh.positions.count,
                  secondIndex < mesh.positions.count,
                  thirdIndex < mesh.positions.count else {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "Drawing projection mesh index is out of range."
                )
            }
            let first = mesh.positions[firstIndex]
            let second = mesh.positions[secondIndex]
            let third = mesh.positions[thirdIndex]
            if triangleNormal(first, second, third, tolerance: tolerance) != nil {
                let first2D = project(first, savedView: savedView, basis: basis)
                let second2D = project(second, savedView: savedView, basis: basis)
                let third2D = project(third, savedView: savedView, basis: basis)
                triangles.append(ProjectedTriangle(
                    first2D: first2D,
                    second2D: second2D,
                    third2D: third2D,
                    firstDepth: depth(first, savedView: savedView, basis: basis),
                    secondDepth: depth(second, savedView: savedView, basis: basis),
                    thirdDepth: depth(third, savedView: savedView, basis: basis),
                    minX: min(first2D.x, second2D.x, third2D.x),
                    minY: min(first2D.y, second2D.y, third2D.y),
                    maxX: max(first2D.x, second2D.x, third2D.x),
                    maxY: max(first2D.y, second2D.y, third2D.y)
                ))
            }
            triangleStart += 3
        }
        return triangles
    }

    private func visibilitySegments(
        stroke: DrawingProjectionResult.Stroke,
        triangles: [ProjectedTriangle],
        savedView: SavedView,
        basis: ProjectionBasis,
        tolerance: Double
    ) -> [DrawingProjectionResult.VisibilitySegment] {
        guard triangles.isEmpty == false else {
            return [
                visibilitySegment(
                    stroke: stroke,
                    index: 0,
                    visibility: .visible,
                    startFraction: 0.0,
                    endFraction: 1.0,
                    savedView: savedView,
                    basis: basis
                ),
            ]
        }

        let hiddenIntervals = hiddenFractionIntervals(
            stroke: stroke,
            triangles: triangles,
            savedView: savedView,
            basis: basis,
            tolerance: tolerance
        )
        let fractionTolerance = fractionTolerance(for: stroke, tolerance: tolerance)
        var segments: [DrawingProjectionResult.VisibilitySegment] = []
        var cursor = 0.0

        for interval in hiddenIntervals {
            let hiddenStart = max(cursor, interval.start)
            if hiddenStart > cursor + fractionTolerance {
                segments.append(visibilitySegment(
                    stroke: stroke,
                    index: segments.count,
                    visibility: .visible,
                    startFraction: cursor,
                    endFraction: hiddenStart,
                    savedView: savedView,
                    basis: basis
                ))
            }

            let hiddenEnd = max(hiddenStart, interval.end)
            if hiddenEnd > hiddenStart + fractionTolerance {
                segments.append(visibilitySegment(
                    stroke: stroke,
                    index: segments.count,
                    visibility: .hidden,
                    startFraction: hiddenStart,
                    endFraction: hiddenEnd,
                    savedView: savedView,
                    basis: basis
                ))
            }
            cursor = max(cursor, hiddenEnd)
        }

        if cursor < 1.0 - fractionTolerance {
            segments.append(visibilitySegment(
                stroke: stroke,
                index: segments.count,
                visibility: .visible,
                startFraction: cursor,
                endFraction: 1.0,
                savedView: savedView,
                basis: basis
            ))
        }

        if segments.isEmpty {
            return [
                visibilitySegment(
                    stroke: stroke,
                    index: 0,
                    visibility: .visible,
                    startFraction: 0.0,
                    endFraction: 1.0,
                    savedView: savedView,
                    basis: basis
                ),
            ]
        }
        return segments
    }

    private func hiddenFractionIntervals(
        stroke: DrawingProjectionResult.Stroke,
        triangles: [ProjectedTriangle],
        savedView: SavedView,
        basis: ProjectionBasis,
        tolerance: Double
    ) -> [FractionInterval] {
        var intervals: [FractionInterval] = []
        intervals.reserveCapacity(triangles.count)
        for triangle in triangles {
            if let interval = hiddenFractionInterval(
                stroke: stroke,
                triangle: triangle,
                savedView: savedView,
                basis: basis,
                tolerance: tolerance
            ) {
                intervals.append(interval)
            }
        }
        return mergedIntervals(
            intervals,
            tolerance: fractionTolerance(for: stroke, tolerance: tolerance)
        )
    }

    private func hiddenFractionInterval(
        stroke: DrawingProjectionResult.Stroke,
        triangle: ProjectedTriangle,
        savedView: SavedView,
        basis: ProjectionBasis,
        tolerance: Double
    ) -> FractionInterval? {
        let boundsTolerance = max(tolerance, 1.0e-9)
        let strokeMinX = min(stroke.start2D.x, stroke.end2D.x)
        let strokeMaxX = max(stroke.start2D.x, stroke.end2D.x)
        let strokeMinY = min(stroke.start2D.y, stroke.end2D.y)
        let strokeMaxY = max(stroke.start2D.y, stroke.end2D.y)
        guard strokeMaxX >= triangle.minX - boundsTolerance,
              strokeMinX <= triangle.maxX + boundsTolerance,
              strokeMaxY >= triangle.minY - boundsTolerance,
              strokeMinY <= triangle.maxY + boundsTolerance,
              let startCoordinates = barycentricCoordinates(
                stroke.start2D,
                first: triangle.first2D,
                second: triangle.second2D,
                third: triangle.third2D
              ),
              let endCoordinates = barycentricCoordinates(
                stroke.end2D,
                first: triangle.first2D,
                second: triangle.second2D,
                third: triangle.third2D
              ) else {
            return nil
        }

        var interval = FractionInterval(start: 0.0, end: 1.0)
        let barycentricTolerance = 1.0e-7
        for coordinatePair in [
            (startCoordinates.first, endCoordinates.first),
            (startCoordinates.second, endCoordinates.second),
            (startCoordinates.third, endCoordinates.third),
        ] {
            guard clipLinearLowerBound(
                startValue: coordinatePair.0,
                endValue: coordinatePair.1,
                minimum: -barycentricTolerance,
                interval: &interval
            ),
            clipLinearUpperBound(
                startValue: coordinatePair.0,
                endValue: coordinatePair.1,
                maximum: 1.0 + barycentricTolerance,
                interval: &interval
            ) else {
                return nil
            }
        }

        let strokeStartDepth = depth(stroke.start, savedView: savedView, basis: basis)
        let strokeEndDepth = depth(stroke.end, savedView: savedView, basis: basis)
        let triangleStartDepth = triangleDepth(
            coordinates: startCoordinates,
            triangle: triangle
        )
        let triangleEndDepth = triangleDepth(
            coordinates: endCoordinates,
            triangle: triangle
        )
        let depthTolerance = max(tolerance * 8.0, 1.0e-9)
        guard clipLinearLowerBound(
            startValue: triangleStartDepth - strokeStartDepth,
            endValue: triangleEndDepth - strokeEndDepth,
            minimum: depthTolerance,
            interval: &interval
        ) else {
            return nil
        }

        interval.start = min(max(interval.start, 0.0), 1.0)
        interval.end = min(max(interval.end, 0.0), 1.0)
        guard interval.end > interval.start + fractionTolerance(for: stroke, tolerance: tolerance) else {
            return nil
        }
        return interval
    }

    private func triangleDepth(
        coordinates: (first: Double, second: Double, third: Double),
        triangle: ProjectedTriangle
    ) -> Double {
        coordinates.first * triangle.firstDepth
            + coordinates.second * triangle.secondDepth
            + coordinates.third * triangle.thirdDepth
    }

    private func clipLinearLowerBound(
        startValue: Double,
        endValue: Double,
        minimum: Double,
        interval: inout FractionInterval
    ) -> Bool {
        let slope = endValue - startValue
        guard abs(slope) > 1.0e-18 else {
            return startValue >= minimum
        }
        let crossing = (minimum - startValue) / slope
        if slope > 0.0 {
            interval.start = max(interval.start, crossing)
        } else {
            interval.end = min(interval.end, crossing)
        }
        return interval.end >= interval.start
    }

    private func clipLinearUpperBound(
        startValue: Double,
        endValue: Double,
        maximum: Double,
        interval: inout FractionInterval
    ) -> Bool {
        let slope = endValue - startValue
        guard abs(slope) > 1.0e-18 else {
            return startValue <= maximum
        }
        let crossing = (maximum - startValue) / slope
        if slope > 0.0 {
            interval.end = min(interval.end, crossing)
        } else {
            interval.start = max(interval.start, crossing)
        }
        return interval.end >= interval.start
    }

    private func mergedIntervals(
        _ intervals: [FractionInterval],
        tolerance: Double
    ) -> [FractionInterval] {
        let normalized = intervals
            .map { interval in
                FractionInterval(
                    start: min(max(interval.start, 0.0), 1.0),
                    end: min(max(interval.end, 0.0), 1.0)
                )
            }
            .filter { $0.end > $0.start + tolerance }
            .sorted {
                if $0.start != $1.start {
                    return $0.start < $1.start
                }
                return $0.end < $1.end
            }
        guard var current = normalized.first else {
            return []
        }
        var merged: [FractionInterval] = []
        for interval in normalized.dropFirst() {
            if interval.start <= current.end + tolerance {
                current.end = max(current.end, interval.end)
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    private func visibilitySegment(
        stroke: DrawingProjectionResult.Stroke,
        index: Int,
        visibility: DrawingProjectionResult.Visibility,
        startFraction: Double,
        endFraction: Double,
        savedView: SavedView,
        basis: ProjectionBasis
    ) -> DrawingProjectionResult.VisibilitySegment {
        let clampedStart = min(max(startFraction, 0.0), 1.0)
        let clampedEnd = min(max(endFraction, clampedStart), 1.0)
        let startPoint = interpolate(stroke.start, stroke.end, fraction: clampedStart)
        let endPoint = interpolate(stroke.start, stroke.end, fraction: clampedEnd)
        let startDepth = depth(startPoint, savedView: savedView, basis: basis)
        let endDepth = depth(endPoint, savedView: savedView, basis: basis)
        return DrawingProjectionResult.VisibilitySegment(
            id: "\(stroke.id):segment:\(index)",
            visibility: visibility,
            startFraction: clampedStart,
            endFraction: clampedEnd,
            start2D: interpolate(stroke.start2D, stroke.end2D, fraction: clampedStart),
            end2D: interpolate(stroke.start2D, stroke.end2D, fraction: clampedEnd),
            minimumDepthMeters: min(startDepth, endDepth),
            maximumDepthMeters: max(startDepth, endDepth),
            lengthMeters: distance(startPoint, endPoint)
        )
    }

    private func visibility(
        from segments: [DrawingProjectionResult.VisibilitySegment]
    ) -> DrawingProjectionResult.Visibility {
        let hasVisible = segments.contains { $0.visibility == .visible }
        let hasHidden = segments.contains { $0.visibility == .hidden }
        if hasVisible && hasHidden {
            return .partiallyHidden
        }
        if hasHidden {
            return .hidden
        }
        if hasVisible {
            return .visible
        }
        return .unclassified
    }

    private func fractionTolerance(
        for stroke: DrawingProjectionResult.Stroke,
        tolerance: Double
    ) -> Double {
        min(0.01, max(1.0e-9, tolerance / max(stroke.lengthMeters, tolerance)))
    }

    private func barycentricCoordinates(
        _ point: Point2D,
        first: Point2D,
        second: Point2D,
        third: Point2D
    ) -> (first: Double, second: Double, third: Double)? {
        let denominator = (second.y - third.y) * (first.x - third.x)
            + (third.x - second.x) * (first.y - third.y)
        guard abs(denominator) > 1.0e-18 else {
            return nil
        }
        let firstWeight = ((second.y - third.y) * (point.x - third.x)
            + (third.x - second.x) * (point.y - third.y)) / denominator
        let secondWeight = ((third.y - first.y) * (point.x - third.x)
            + (first.x - third.x) * (point.y - third.y)) / denominator
        let thirdWeight = 1.0 - firstWeight - secondWeight
        return (firstWeight, secondWeight, thirdWeight)
    }

    private func includeEdge(
        start: Point3D,
        end: Point3D,
        normal: Vector3D,
        tolerance: Double,
        edges: inout [EdgeKey: EdgeAccumulator]
    ) {
        let key = EdgeKey(
            quantized(start, tolerance: tolerance),
            quantized(end, tolerance: tolerance)
        )
        if var edge = edges[key] {
            edge.include(normal: normal)
            edges[key] = edge
        } else {
            edges[key] = EdgeAccumulator(
                key: key,
                start: start,
                end: end,
                normals: [normal]
            )
        }
    }

    private func quantized(
        _ point: Point3D,
        tolerance: Double
    ) -> QuantizedPoint {
        QuantizedPoint(
            x: Int64((point.x / tolerance).rounded()),
            y: Int64((point.y / tolerance).rounded()),
            z: Int64((point.z / tolerance).rounded())
        )
    }

    private func triangleNormal(
        _ first: Point3D,
        _ second: Point3D,
        _ third: Point3D,
        tolerance: Double
    ) -> Vector3D? {
        let lhs = Vector3D(
            x: second.x - first.x,
            y: second.y - first.y,
            z: second.z - first.z
        )
        let rhs = Vector3D(
            x: third.x - first.x,
            y: third.y - first.y,
            z: third.z - first.z
        )
        do {
            return try lhs.cross(rhs).normalized(tolerance: tolerance)
        } catch {
            return nil
        }
    }

    private func shouldEmit(_ edge: EdgeAccumulator) -> Bool {
        guard edge.normals.count > 1 else {
            return true
        }
        let reference = edge.normals[0]
        for normal in edge.normals.dropFirst() {
            if abs(dot(reference, normal)) < 0.999_999 {
                return true
            }
        }
        return false
    }

    private func stroke(
        edge: EdgeAccumulator,
        bodyID: BodyID,
        index: Int,
        savedView: SavedView,
        basis: ProjectionBasis
    ) -> DrawingProjectionResult.Stroke? {
        let start2D = project(edge.start, savedView: savedView, basis: basis)
        let end2D = project(edge.end, savedView: savedView, basis: basis)
        let lengthMeters = distance(edge.start, edge.end)
        guard lengthMeters.isFinite,
              lengthMeters > 0.0 else {
            return nil
        }
        let startDepth = depth(edge.start, savedView: savedView, basis: basis)
        let endDepth = depth(edge.end, savedView: savedView, basis: basis)
        let kind: DrawingProjectionResult.StrokeKind = edge.normals.count > 1 ? .crease : .boundary
        return DrawingProjectionResult.Stroke(
            id: "\(savedView.id.description):stroke:\(index)",
            bodyID: bodyID.description,
            kind: kind,
            visibility: .unclassified,
            start: edge.start,
            end: edge.end,
            start2D: start2D,
            end2D: end2D,
            minimumDepthMeters: min(startDepth, endDepth),
            maximumDepthMeters: max(startDepth, endDepth),
            lengthMeters: lengthMeters,
            visibilitySegments: []
        )
    }

    private func project(
        _ point: Point3D,
        savedView: SavedView,
        basis: ProjectionBasis
    ) -> Point2D {
        let x = point.x - savedView.camera.target.x
        let y = point.y - savedView.camera.target.y
        let z = point.z - savedView.camera.target.z
        return Point2D(
            x: basis.xDirection.x * x + basis.yDirection.x * y + basis.zDirection.x * z,
            y: basis.xDirection.y * x + basis.yDirection.y * y + basis.zDirection.y * z
        )
    }

    private func interpolate(
        _ start: Point2D,
        _ end: Point2D,
        fraction: Double
    ) -> Point2D {
        Point2D(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }

    private func interpolate(
        _ start: Point3D,
        _ end: Point3D,
        fraction: Double
    ) -> Point3D {
        Point3D(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction,
            z: start.z + (end.z - start.z) * fraction
        )
    }

    private func depth(
        _ point: Point3D,
        savedView: SavedView,
        basis: ProjectionBasis
    ) -> Double {
        let x = point.x - savedView.camera.target.x
        let y = point.y - savedView.camera.target.y
        let z = point.z - savedView.camera.target.z
        return x * basis.viewNormal.x + y * basis.viewNormal.y + z * basis.viewNormal.z
    }

    private func distance(
        _ start: Point3D,
        _ end: Point3D
    ) -> Double {
        let x = end.x - start.x
        let y = end.y - start.y
        let z = end.z - start.z
        return sqrt(x * x + y * y + z * z)
    }

    private func dot(
        _ lhs: Vector3D,
        _ rhs: Vector3D
    ) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private func diagnostics(
        result strokes: [DrawingProjectionResult.Stroke],
        candidateEdgeCount: Int,
        truncatedStrokes: Bool,
        maximumStrokeCount: Int
    ) -> [EditorDiagnostic] {
        let visibilityCounts = visibilityCounts(strokes)
        let visibilitySegmentCount = strokes.reduce(0) { count, stroke in
            count + stroke.visibilitySegments.count
        }
        var diagnostics = [
            EditorDiagnostic(
                severity: .info,
                message: "Drawing projection generated \(strokes.count) stroke(s) from \(candidateEdgeCount) mesh edge candidate(s)."
            ),
        ]
        if truncatedStrokes {
            diagnostics.append(
                EditorDiagnostic(
                    severity: .warning,
                    message: "Drawing projection was truncated at \(maximumStrokeCount) stroke(s)."
                )
            )
        }
        diagnostics.append(
            EditorDiagnostic(
                severity: .info,
                message: "Drawing projection hidden-line classified \(visibilityCounts.visible) visible, \(visibilityCounts.hidden) hidden, \(visibilityCounts.partiallyHidden) partially hidden, and \(visibilityCounts.unclassified) unclassified stroke(s), split into \(visibilitySegmentCount) visibility segment(s)."
            )
        )
        return diagnostics
    }

    private func visibilityCounts(
        _ strokes: [DrawingProjectionResult.Stroke]
    ) -> (visible: Int, hidden: Int, partiallyHidden: Int, unclassified: Int) {
        var visible = 0
        var hidden = 0
        var partiallyHidden = 0
        var unclassified = 0
        for stroke in strokes {
            switch stroke.visibility {
            case .visible:
                visible += 1
            case .hidden:
                hidden += 1
            case .partiallyHidden:
                partiallyHidden += 1
            case .unclassified:
                unclassified += 1
            }
        }
        return (visible, hidden, partiallyHidden, unclassified)
    }
}
