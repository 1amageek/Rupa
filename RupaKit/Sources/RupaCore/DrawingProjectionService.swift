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

    private struct SectionProjectionArtifacts {
        var contours: [DrawingProjectionResult.SectionContour] = []
        var hatches: [DrawingProjectionResult.SectionHatchSegment] = []
        var truncatedHatches = false
        var diagnostics: [EditorDiagnostic] = []
    }

    private struct HatchPlaneSegment {
        var start: Point2D
        var end: Point2D
        var pattern: DrawingProjectionResult.SectionHatchPattern
        var angleDegrees: Double
    }

    private struct CircularHatchProfile {
        var center: Point2D
        var radius: Double
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
        let savedView = try resolvedSavedView(id: query.savedViewID, document: document)
        return try generate(
            document: document,
            savedView: savedView,
            toleranceMeters: query.toleranceMeters,
            maximumStrokeCount: query.maximumStrokeCount,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
    }

    public func generate(
        document: DesignDocument,
        savedView: SavedView,
        toleranceMeters: Double? = nil,
        maximumStrokeCount: Int = 10_000,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> DrawingProjectionResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
            try savedView.validate(
                sceneNodes: document.productMetadata.sceneNodes,
                constructionPlanes: document.productMetadata.constructionPlanes
            )
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document and drawing view must validate before drawing projection: \(String(describing: error))"
            )
        }

        guard maximumStrokeCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Drawing projection maximum stroke count must be positive."
            )
        }
        let tolerance = try resolvedTolerance(toleranceMeters, document: document)
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
        let topologySummary = try topologySummaryForAnnotations(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        let annotations = DrawingAnnotationLayoutService().layout(
            annotations: try drawingAnnotations(
                document: document,
                savedView: savedView,
                basis: basis,
                topology: topologySummary
            ),
            viewFrame: viewFrame
        )

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            var annotationBounds = BoundsAccumulator()
            includeAnnotations(annotations, in: &annotationBounds)
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
                bounds: annotationBounds.bounds,
                strokes: [],
                annotations: annotations,
                diagnostics: [
                    EditorDiagnostic(
                        severity: .info,
                        message: "Drawing projection completed with no generated body meshes."
                    ),
                ] + annotationDiagnostics(annotations)
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
                if strokes.count >= maximumStrokeCount {
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

        let sectionArtifacts = try sectionProjectionArtifacts(
            document: document,
            savedView: savedView,
            basis: basis,
            tolerance: tolerance,
            maximumHatchCount: maximumStrokeCount,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        for contour in sectionArtifacts.contours {
            for point in contour.projectedPoints2D {
                bounds.include(point)
            }
        }
        for hatch in sectionArtifacts.hatches {
            bounds.include(hatch.start2D)
            bounds.include(hatch.end2D)
        }
        includeAnnotations(annotations, in: &bounds)

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
            sectionContours: sectionArtifacts.contours,
            sectionHatches: sectionArtifacts.hatches,
            truncatedSectionHatches: sectionArtifacts.truncatedHatches,
            annotations: annotations,
            diagnostics: diagnostics(
                result: strokes,
                candidateEdgeCount: candidateEdgeCount,
                truncatedStrokes: truncatedStrokes,
                maximumStrokeCount: maximumStrokeCount,
                sectionArtifacts: sectionArtifacts
            ) + sectionArtifacts.diagnostics + annotationDiagnostics(annotations)
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

    private func topologySummaryForAnnotations(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws -> TopologySummaryResult? {
        guard measurementAnnotationsRequireTopology(in: document),
              document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return nil
        }
        return try TopologySummaryService(pipeline: pipelineOverride).summarize(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
    }

    private func measurementAnnotationsRequireTopology(
        in document: DesignDocument
    ) -> Bool {
        document.productMetadata.measurements.values.contains { measurement in
            measurement.anchors.contains { anchor in
                anchor.kind == .topologyReference || anchor.kind == .topologyEdgeParameter
            }
        }
    }

    private func drawingAnnotations(
        document: DesignDocument,
        savedView: SavedView,
        basis: ProjectionBasis,
        topology: TopologySummaryResult?
    ) throws -> [DrawingProjectionResult.Annotation] {
        let resolver = MeasurementAnchorWorldPointResolver()
        let sortedMeasurements = document.productMetadata.measurements.values.sorted {
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.id.description < $1.id.description
        }

        var annotations: [DrawingProjectionResult.Annotation] = []
        annotations.reserveCapacity(sortedMeasurements.count)
        for measurement in sortedMeasurements {
            let anchors = try resolvedAnnotationAnchors(
                measurement.anchors,
                resolver: resolver,
                document: document,
                savedView: savedView,
                basis: basis,
                topology: topology
            )
            guard anchors.isEmpty == false else {
                continue
            }
            let metrics = annotationMetrics(
                measurement: measurement,
                anchors: anchors,
                topology: topology,
                displayUnit: document.displayUnit,
                fallbackName: measurement.name
            )
            let label = annotationLabelPoint(
                measurement: measurement,
                anchors: anchors,
                savedView: savedView,
                basis: basis
            )
            annotations.append(DrawingProjectionResult.Annotation(
                id: "\(measurement.id.description):drawing",
                measurementID: measurement.id,
                sceneNodeID: measurement.sceneNodeID,
                name: measurement.name,
                kind: measurement.kind,
                anchors: anchors,
                labelWorldPoint: measurement.labelPosition,
                labelPoint2D: label,
                measurementMeters: metrics.measurementMeters,
                measurementSquareMeters: metrics.measurementSquareMeters,
                measurementDegrees: metrics.measurementDegrees,
                displayText: metrics.displayText
            ))
        }
        return annotations
    }

    private func resolvedAnnotationAnchors(
        _ sourceAnchors: [MeasurementAnchor],
        resolver: MeasurementAnchorWorldPointResolver,
        document: DesignDocument,
        savedView: SavedView,
        basis: ProjectionBasis,
        topology: TopologySummaryResult?
    ) throws -> [DrawingProjectionResult.AnnotationAnchor] {
        var anchors: [DrawingProjectionResult.AnnotationAnchor] = []
        anchors.reserveCapacity(sourceAnchors.count)
        for sourceAnchor in sourceAnchors {
            guard let resolved = try resolver.resolvedAnchor(
                sourceAnchor,
                in: document,
                topology: topology
            ) else {
                continue
            }
            anchors.append(DrawingProjectionResult.AnnotationAnchor(
                role: resolved.role,
                kind: resolved.kind,
                worldPoint: resolved.worldPoint,
                point2D: project(resolved.worldPoint, savedView: savedView, basis: basis)
            ))
        }
        return anchors
    }

    private func annotationMetrics(
        measurement: MeasurementAnnotation,
        anchors: [DrawingProjectionResult.AnnotationAnchor],
        topology: TopologySummaryResult?,
        displayUnit: LengthDisplayUnit,
        fallbackName: String
    ) -> (
        measurementMeters: Double?,
        measurementSquareMeters: Double?,
        measurementDegrees: Double?,
        displayText: String
    ) {
        switch measurement.kind {
        case .distance:
            guard anchors.count >= 2 else {
                return (nil, nil, nil, fallbackName)
            }
            let endpoints = preferredMeasurementEndpoints(in: anchors)
            let length = distance(endpoints.first.worldPoint, endpoints.second.worldPoint)
            return (
                length,
                nil,
                nil,
                LengthDisplayText.readableLengthString(
                    fromMeters: length,
                    preferredUnit: displayUnit,
                    maximumFractionDigits: 3
                )
            )
        case .perimeter:
            guard let length = perimeterMeters(from: anchors) else {
                return (nil, nil, nil, fallbackName)
            }
            return (
                length,
                nil,
                nil,
                "Perim \(LengthDisplayText.readableLengthString(fromMeters: length, preferredUnit: displayUnit, maximumFractionDigits: 3))"
            )
        case .area:
            guard let area = topologyFaceAreaSquareMeters(
                for: measurement,
                topology: topology
            ) ?? areaSquareMeters(from: anchors) else {
                return (nil, nil, nil, fallbackName)
            }
            return (
                nil,
                area,
                nil,
                "Area \(LengthDisplayText.readableAreaString(fromSquareMeters: area, preferredUnit: displayUnit, maximumFractionDigits: 3))"
            )
        case .edgeLength:
            guard let length = topologyEdgeLengthMeters(
                for: measurement,
                topology: topology
            ) else {
                return (nil, nil, nil, fallbackName)
            }
            return (
                length,
                nil,
                nil,
                "Edge \(LengthDisplayText.readableLengthString(fromMeters: length, preferredUnit: displayUnit, maximumFractionDigits: 3))"
            )
        case .radius:
            guard let radius = radiusMeters(from: anchors) else {
                return (nil, nil, nil, fallbackName)
            }
            return (
                radius,
                nil,
                nil,
                "R \(LengthDisplayText.readableLengthString(fromMeters: radius, preferredUnit: displayUnit, maximumFractionDigits: 3))"
            )
        case .diameter:
            guard let diameter = diameterMeters(from: anchors) else {
                return (nil, nil, nil, fallbackName)
            }
            return (
                diameter,
                nil,
                nil,
                "Dia \(LengthDisplayText.readableLengthString(fromMeters: diameter, preferredUnit: displayUnit, maximumFractionDigits: 3))"
            )
        case .angle:
            guard let degrees = angleDegrees(from: anchors) else {
                return (nil, nil, nil, fallbackName)
            }
            return (
                nil,
                nil,
                degrees,
                "\(LengthDisplayText.numberString(from: degrees, maximumFractionDigits: 2)) deg"
            )
        }
    }

    private func topologyFaceAreaSquareMeters(
        for measurement: MeasurementAnnotation,
        topology: TopologySummaryResult?
    ) -> Double? {
        topologyEntry(
            for: measurement,
            topologyKind: .face,
            topology: topology
        )?.areaSquareMeters
    }

    private func topologyEdgeLengthMeters(
        for measurement: MeasurementAnnotation,
        topology: TopologySummaryResult?
    ) -> Double? {
        topologyEntry(
            for: measurement,
            topologyKind: .edge,
            topology: topology
        )?.lengthMeters
    }

    private func topologyEntry(
        for measurement: MeasurementAnnotation,
        topologyKind: TopologySummaryResult.Entry.Kind,
        topology: TopologySummaryResult?
    ) -> TopologySummaryResult.Entry? {
        guard let topology else {
            return nil
        }
        for anchor in measurement.anchors {
            guard anchor.kind == .topologyReference,
                  let topologyReference = anchor.topologyReference,
                  topologyReference.kind == topologyKind else {
                continue
            }
            if let entry = topology.entries.first(where: { entry in
                guard entry.kind == topologyKind,
                      entry.persistentName == topologyReference.persistentName,
                      let target = entry.selectionTarget() else {
                    return false
                }
                return target.sceneNodeID == topologyReference.sceneNodeID
                    && target.component == topologyReference.component
            }) {
                return entry
            }
        }
        return nil
    }

    private func preferredMeasurementEndpoints(
        in anchors: [DrawingProjectionResult.AnnotationAnchor]
    ) -> (
        first: DrawingProjectionResult.AnnotationAnchor,
        second: DrawingProjectionResult.AnnotationAnchor
    ) {
        let start = anchors.first { $0.role == .start }
        let end = anchors.first { $0.role == .end }
        if let start, let end {
            return (start, end)
        }
        return (anchors[0], anchors[1])
    }

    private func perimeterMeters(
        from anchors: [DrawingProjectionResult.AnnotationAnchor]
    ) -> Double? {
        guard anchors.count >= 3 else {
            return nil
        }
        var total = 0.0
        for index in 1..<anchors.count {
            total += distance(anchors[index - 1].worldPoint, anchors[index].worldPoint)
        }
        if anchors.count >= 3,
           let first = anchors.first,
           let last = anchors.last {
            total += distance(last.worldPoint, first.worldPoint)
        }
        guard total.isFinite, total > 1.0e-12 else {
            return nil
        }
        return total
    }

    private func areaSquareMeters(
        from anchors: [DrawingProjectionResult.AnnotationAnchor]
    ) -> Double? {
        guard anchors.count >= 3 else {
            return nil
        }
        var crossX = 0.0
        var crossY = 0.0
        var crossZ = 0.0
        for index in anchors.indices {
            let current = anchors[index].worldPoint
            let nextIndex = index == anchors.index(before: anchors.endIndex)
                ? anchors.startIndex
                : anchors.index(after: index)
            let next = anchors[nextIndex].worldPoint
            crossX += current.y * next.z - current.z * next.y
            crossY += current.z * next.x - current.x * next.z
            crossZ += current.x * next.y - current.y * next.x
        }
        let area = 0.5 * sqrt(crossX * crossX + crossY * crossY + crossZ * crossZ)
        guard area.isFinite, area > 1.0e-18 else {
            return nil
        }
        return area
    }

    private func radiusMeters(
        from anchors: [DrawingProjectionResult.AnnotationAnchor]
    ) -> Double? {
        guard anchors.count >= 2 else {
            return nil
        }
        if let center = anchors.first(where: { $0.role == .center }),
           let boundary = anchors.first(where: { $0.role != .center }) {
            return distance(center.worldPoint, boundary.worldPoint)
        }
        let endpoints = preferredMeasurementEndpoints(in: anchors)
        return distance(endpoints.first.worldPoint, endpoints.second.worldPoint)
    }

    private func diameterMeters(
        from anchors: [DrawingProjectionResult.AnnotationAnchor]
    ) -> Double? {
        guard anchors.count >= 2 else {
            return nil
        }
        if let center = anchors.first(where: { $0.role == .center }),
           let boundary = anchors.first(where: { $0.role != .center }) {
            return distance(center.worldPoint, boundary.worldPoint) * 2.0
        }
        let endpoints = preferredMeasurementEndpoints(in: anchors)
        return distance(endpoints.first.worldPoint, endpoints.second.worldPoint)
    }

    private func angleDegrees(
        from anchors: [DrawingProjectionResult.AnnotationAnchor]
    ) -> Double? {
        guard anchors.count >= 3 else {
            return nil
        }
        if let center = anchors.first(where: { $0.role == .center }) {
            let sideAnchors = anchors.filter { $0.role != .center }
            guard sideAnchors.count >= 2 else {
                return nil
            }
            return angleDegrees(
                first: sideAnchors[0].worldPoint,
                center: center.worldPoint,
                second: sideAnchors[1].worldPoint
            )
        }
        return angleDegrees(
            first: anchors[0].worldPoint,
            center: anchors[1].worldPoint,
            second: anchors[2].worldPoint
        )
    }

    private func annotationLabelPoint(
        measurement: MeasurementAnnotation,
        anchors: [DrawingProjectionResult.AnnotationAnchor],
        savedView: SavedView,
        basis: ProjectionBasis
    ) -> Point2D {
        if let labelPosition = measurement.labelPosition {
            return project(labelPosition, savedView: savedView, basis: basis)
        }
        let center = centroid(anchors.map(\.point2D))
        let defaultOffset = max(savedView.displayScale.scaleBarLengthMeters * 0.08, 0.01)
        if let placementAxis = measurement.placementAxis,
           let direction = normalizedProjectedDirection(placementAxis, basis: basis) {
            return Point2D(
                x: center.x + direction.x * defaultOffset,
                y: center.y + direction.y * defaultOffset
            )
        }
        return Point2D(x: center.x, y: center.y + defaultOffset)
    }

    private func centroid(_ points: [Point2D]) -> Point2D {
        guard points.isEmpty == false else {
            return Point2D(x: 0.0, y: 0.0)
        }
        let sum = points.reduce(Point2D(x: 0.0, y: 0.0)) { partial, point in
            Point2D(x: partial.x + point.x, y: partial.y + point.y)
        }
        let divisor = Double(points.count)
        return Point2D(x: sum.x / divisor, y: sum.y / divisor)
    }

    private func normalizedProjectedDirection(
        _ vector: Vector3D,
        basis: ProjectionBasis
    ) -> Point2D? {
        let projected = Point2D(
            x: basis.xDirection.x * vector.x
                + basis.yDirection.x * vector.y
                + basis.zDirection.x * vector.z,
            y: basis.xDirection.y * vector.x
                + basis.yDirection.y * vector.y
                + basis.zDirection.y * vector.z
        )
        let length = hypot(projected.x, projected.y)
        guard length > 1.0e-12 else {
            return nil
        }
        return Point2D(x: projected.x / length, y: projected.y / length)
    }

    private func includeAnnotations(
        _ annotations: [DrawingProjectionResult.Annotation],
        in bounds: inout BoundsAccumulator
    ) {
        for annotation in annotations {
            if let labelBounds = annotation.labelLayout?.bounds2D {
                bounds.include(Point2D(x: labelBounds.minX, y: labelBounds.minY))
                bounds.include(Point2D(x: labelBounds.maxX, y: labelBounds.maxY))
            } else {
                bounds.include(annotation.labelPoint2D)
            }
            if let leaderStart = annotation.labelLayout?.leaderStart2D {
                bounds.include(leaderStart)
            }
            if let leaderEnd = annotation.labelLayout?.leaderEnd2D {
                bounds.include(leaderEnd)
            }
            for anchor in annotation.anchors {
                bounds.include(anchor.point2D)
            }
        }
    }

    private func annotationDiagnostics(
        _ annotations: [DrawingProjectionResult.Annotation]
    ) -> [EditorDiagnostic] {
        guard annotations.isEmpty == false else {
            return []
        }
        let baseDiagnostics = [
            EditorDiagnostic(
                severity: .info,
                message: "Drawing projection generated \(annotations.count) drawing annotation(s) from measurement metadata."
            ),
        ]
        let adjustedCount = annotations.filter {
            $0.labelLayout?.placement == .adjusted
        }.count
        guard adjustedCount > 0 else {
            return baseDiagnostics
        }
        return baseDiagnostics + [
            EditorDiagnostic(
                severity: .info,
                message: "Drawing projection adjusted \(adjustedCount) drawing annotation label(s) to reduce label overlap."
            ),
        ]
    }

    private func projectionBasis(
        for savedView: SavedView
    ) throws -> ProjectionBasis {
        let yaw = savedView.camera.yawRadians
        let elevation = savedView.camera.pitchRadians
        let elevationSine = sin(elevation)
        let elevationCosine = cos(elevation)
        let unrolledRight = Vector3D(
            x: cos(yaw),
            y: 0.0,
            z: -sin(yaw)
        )
        let unrolledUp = Vector3D(
            x: elevationSine * sin(yaw),
            y: -elevationCosine,
            z: elevationSine * cos(yaw)
        )
        let roll = savedView.camera.rollRadians
        let rollCosine = cos(roll)
        let rollSine = sin(roll)
        let right = unrolledRight * rollCosine + unrolledUp * rollSine
        let up = -unrolledRight * rollSine + unrolledUp * rollCosine
        let viewNormal = try up.cross(right).normalized(tolerance: 1.0e-12)
        return ProjectionBasis(
            xDirection: Point2D(x: right.x, y: up.x),
            yDirection: Point2D(x: right.y, y: up.y),
            zDirection: Point2D(x: right.z, y: up.z),
            right: right,
            up: up,
            viewNormal: viewNormal
        )
    }

    private func sectionProjectionArtifacts(
        document: DesignDocument,
        savedView: SavedView,
        basis: ProjectionBasis,
        tolerance: Double,
        maximumHatchCount: Int,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws -> SectionProjectionArtifacts {
        guard savedView.sectionState.sectionSceneNodeIDs.isEmpty == false else {
            return SectionProjectionArtifacts()
        }

        var artifacts = SectionProjectionArtifacts()
        let analysisService = SectionAnalysisService(pipeline: pipelineOverride)
        for sectionSceneNodeID in savedView.sectionState.sectionSceneNodeIDs {
            let analysis = try analysisService.analyze(
                document: document,
                query: SectionAnalysisQuery(
                    source: .sceneNode(sectionSceneNodeID),
                    toleranceMeters: tolerance,
                    includesIntersectionSegments: true,
                    maximumIntersectionSegments: max(
                        min(maximumHatchCount, Int.max / 4) * 4,
                        maximumHatchCount
                    )
                ),
                objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation,
                currentGeneration: currentGeneration
            )

            for sourceContour in analysis.intersectionContours where sourceContour.isClosed {
                let contourID = "\(savedView.id.description):section:\(artifacts.contours.count)"
                let projectedPoints = sourceContour.points.map { point in
                    project(point, savedView: savedView, basis: basis)
                }
                artifacts.contours.append(DrawingProjectionResult.SectionContour(
                    id: contourID,
                    sectionSourceID: analysis.plane.sourceID,
                    sectionSourceName: analysis.plane.sourceName,
                    bodyID: sourceContour.bodyID,
                    points: sourceContour.points,
                    sectionPlanePoints2D: sourceContour.points2D,
                    projectedPoints2D: projectedPoints,
                    signedAreaSquareMeters: sourceContour.signedAreaSquareMeters,
                    lengthMeters: sourceContour.lengthMeters,
                    segmentCount: sourceContour.segmentCount
                ))

                let remainingCapacity = max(0, maximumHatchCount - artifacts.hatches.count)
                let hatchResult = sectionHatches(
                    contour: sourceContour,
                    contourID: contourID,
                    plane: analysis.plane,
                    savedView: savedView,
                    basis: basis,
                    tolerance: tolerance,
                    maximumSegmentCount: remainingCapacity
                )
                artifacts.hatches.append(contentsOf: hatchResult.segments)
                artifacts.truncatedHatches = artifacts.truncatedHatches || hatchResult.truncated
            }
        }

        if artifacts.contours.isEmpty == false || artifacts.hatches.isEmpty == false {
            artifacts.diagnostics.append(EditorDiagnostic(
                severity: artifacts.truncatedHatches ? .warning : .info,
                message: "Drawing projection generated \(artifacts.contours.count) closed section contour(s) and \(artifacts.hatches.count) section hatch segment(s)."
            ))
        }
        return artifacts
    }

    private func sectionHatches(
        contour: SectionAnalysisResult.IntersectionContour,
        contourID: String,
        plane: SectionAnalysisResult.Plane,
        savedView: SavedView,
        basis: ProjectionBasis,
        tolerance: Double,
        maximumSegmentCount: Int
    ) -> (segments: [DrawingProjectionResult.SectionHatchSegment], truncated: Bool) {
        guard maximumSegmentCount > 0 else {
            return ([], true)
        }
        let spacing = hatchSpacing(
            for: contour.points2D,
            tolerance: tolerance
        )
        let planeSegments = hatchPlaneSegments(
            polygon: contour.points2D,
            spacing: spacing,
            tolerance: tolerance,
            maximumSegmentCount: maximumSegmentCount
        )

        var hatches: [DrawingProjectionResult.SectionHatchSegment] = []
        hatches.reserveCapacity(planeSegments.segments.count)
        for segment in planeSegments.segments {
            let start = pointOnPlane(segment.start, plane: plane)
            let end = pointOnPlane(segment.end, plane: plane)
            let lengthMeters = distance(start, end)
            guard lengthMeters > tolerance else {
                continue
            }
            hatches.append(DrawingProjectionResult.SectionHatchSegment(
                id: "\(contourID):hatch:\(hatches.count)",
                contourID: contourID,
                sectionSourceID: plane.sourceID,
                sectionSourceName: plane.sourceName,
                bodyID: contour.bodyID,
                start: start,
                end: end,
                start2D: project(start, savedView: savedView, basis: basis),
                end2D: project(end, savedView: savedView, basis: basis),
                pattern: segment.pattern,
                spacingMeters: spacing,
                angleDegrees: segment.angleDegrees,
                lengthMeters: lengthMeters
            ))
        }
        return (hatches, planeSegments.truncated)
    }

    private func hatchSpacing(
        for points: [Point2D],
        tolerance: Double
    ) -> Double {
        guard let bounds = planeBounds(points) else {
            return max(tolerance * 32.0, 1.0e-6)
        }
        let span = max(bounds.maxX - bounds.minX, bounds.maxY - bounds.minY)
        guard span.isFinite, span > tolerance else {
            return max(tolerance * 32.0, 1.0e-6)
        }
        return max(tolerance * 32.0, span / 18.0)
    }

    private func hatchPlaneSegments(
        polygon: [Point2D],
        spacing: Double,
        tolerance: Double,
        maximumSegmentCount: Int
    ) -> (segments: [HatchPlaneSegment], truncated: Bool) {
        guard polygon.count >= 3,
              spacing.isFinite,
              spacing > tolerance,
              maximumSegmentCount > 0 else {
            return ([], false)
        }
        if let circularProfile = circularHatchProfile(
            polygon: polygon,
            tolerance: tolerance
        ) {
            return radialHatchPlaneSegments(
                polygon: polygon,
                profile: circularProfile,
                spacing: spacing,
                tolerance: tolerance,
                maximumSegmentCount: maximumSegmentCount
            )
        }
        let angleDegrees = 45.0
        let angleRadians = angleDegrees * .pi / 180.0
        let cosine = cos(angleRadians)
        let sine = sin(angleRadians)
        let rotated = polygon.map { rotate($0, cosine: cosine, sine: sine) }
        guard let bounds = planeBounds(rotated) else {
            return ([], false)
        }

        var segments: [HatchPlaneSegment] = []
        var scanline = floor(bounds.minY / spacing) * spacing
        let endLine = ceil(bounds.maxY / spacing) * spacing
        var truncated = false
        while scanline <= endLine + tolerance {
            let intersections = scanlineIntersections(
                polygon: rotated,
                y: scanline,
                tolerance: tolerance
            )
            var index = 0
            while index + 1 < intersections.count {
                if segments.count >= maximumSegmentCount {
                    truncated = true
                    return (segments, truncated)
                }
                let start = Point2D(x: intersections[index], y: scanline)
                let end = Point2D(x: intersections[index + 1], y: scanline)
                if hypot(end.x - start.x, end.y - start.y) > tolerance {
                    segments.append(HatchPlaneSegment(
                        start: unrotate(start, cosine: cosine, sine: sine),
                        end: unrotate(end, cosine: cosine, sine: sine),
                        pattern: .linear,
                        angleDegrees: angleDegrees
                    ))
                }
                index += 2
            }
            scanline += spacing
        }
        return (segments, truncated)
    }

    private func circularHatchProfile(
        polygon: [Point2D],
        tolerance: Double
    ) -> CircularHatchProfile? {
        guard polygon.count >= 12,
              let bounds = planeBounds(polygon) else {
            return nil
        }
        let width = bounds.maxX - bounds.minX
        let height = bounds.maxY - bounds.minY
        let largerSpan = max(width, height)
        let smallerSpan = min(width, height)
        guard largerSpan.isFinite,
              smallerSpan.isFinite,
              largerSpan > tolerance * 8.0,
              smallerSpan / largerSpan >= 0.86 else {
            return nil
        }

        let center = polygonAreaCentroid(polygon) ?? centroid(polygon)
        let distances = polygon.map { point in
            hypot(point.x - center.x, point.y - center.y)
        }
        let radius = distances.reduce(0.0, +) / Double(distances.count)
        guard radius.isFinite,
              radius > tolerance * 8.0 else {
            return nil
        }

        let maximumDeviation = distances.reduce(0.0) { current, distance in
            max(current, abs(distance - radius))
        }
        let relativeDeviation = maximumDeviation / radius
        let polygonArea = abs(signedArea(polygon))
        let circleArea = Double.pi * radius * radius
        guard polygonArea.isFinite,
              circleArea.isFinite,
              circleArea > tolerance * tolerance,
              relativeDeviation <= 0.10 else {
            return nil
        }
        let areaRatio = polygonArea / circleArea
        guard areaRatio >= 0.70,
              areaRatio <= 1.08 else {
            return nil
        }

        return CircularHatchProfile(center: center, radius: radius)
    }

    private func radialHatchPlaneSegments(
        polygon: [Point2D],
        profile: CircularHatchProfile,
        spacing: Double,
        tolerance: Double,
        maximumSegmentCount: Int
    ) -> (segments: [HatchPlaneSegment], truncated: Bool) {
        let circumference = 2.0 * Double.pi * profile.radius
        let targetSegmentCount = min(
            max(Int(ceil(circumference / max(spacing * 2.0, tolerance * 32.0))), 8),
            64
        )
        let emittedSegmentCount = min(targetSegmentCount, maximumSegmentCount)
        guard emittedSegmentCount > 0 else {
            return ([], targetSegmentCount > 0)
        }

        var segments: [HatchPlaneSegment] = []
        segments.reserveCapacity(emittedSegmentCount)
        let angleStep = 2.0 * Double.pi / Double(emittedSegmentCount)
        for index in 0..<emittedSegmentCount {
            let angleRadians = Double(index) * angleStep
            let direction = Point2D(x: cos(angleRadians), y: sin(angleRadians))
            guard let boundaryDistance = rayPolygonBoundaryDistance(
                origin: profile.center,
                direction: direction,
                polygon: polygon,
                tolerance: tolerance
            ) else {
                continue
            }
            let end = Point2D(
                x: profile.center.x + direction.x * boundaryDistance,
                y: profile.center.y + direction.y * boundaryDistance
            )
            guard hypot(end.x - profile.center.x, end.y - profile.center.y) > tolerance else {
                continue
            }
            segments.append(HatchPlaneSegment(
                start: profile.center,
                end: end,
                pattern: .radial,
                angleDegrees: normalizedDegrees(angleRadians)
            ))
        }
        return (segments, targetSegmentCount > maximumSegmentCount)
    }

    private func rayPolygonBoundaryDistance(
        origin: Point2D,
        direction: Point2D,
        polygon: [Point2D],
        tolerance: Double
    ) -> Double? {
        var bestDistance = Double.infinity
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let edge = Point2D(x: end.x - start.x, y: end.y - start.y)
            guard hypot(edge.x, edge.y) > tolerance else {
                continue
            }
            let denominator = cross(direction, edge)
            guard abs(denominator) > tolerance else {
                continue
            }
            let delta = Point2D(x: start.x - origin.x, y: start.y - origin.y)
            let rayDistance = cross(delta, edge) / denominator
            let edgeFraction = cross(delta, direction) / denominator
            guard rayDistance > tolerance,
                  edgeFraction >= -tolerance,
                  edgeFraction <= 1.0 + tolerance else {
                continue
            }
            bestDistance = min(bestDistance, rayDistance)
        }
        return bestDistance.isFinite ? bestDistance : nil
    }

    private func polygonAreaCentroid(_ points: [Point2D]) -> Point2D? {
        guard points.count >= 3 else {
            return nil
        }
        var twiceArea = 0.0
        var x = 0.0
        var y = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let crossValue = current.x * next.y - next.x * current.y
            twiceArea += crossValue
            x += (current.x + next.x) * crossValue
            y += (current.y + next.y) * crossValue
        }
        guard abs(twiceArea) > 1.0e-18 else {
            return nil
        }
        let scale = 1.0 / (3.0 * twiceArea)
        return Point2D(x: x * scale, y: y * scale)
    }

    private func signedArea(_ points: [Point2D]) -> Double {
        guard points.count >= 3 else {
            return 0.0
        }
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            twiceArea += current.x * next.y - next.x * current.y
        }
        return twiceArea * 0.5
    }

    private func cross(_ left: Point2D, _ right: Point2D) -> Double {
        left.x * right.y - left.y * right.x
    }

    private func normalizedDegrees(_ radians: Double) -> Double {
        var degrees = radians * 180.0 / Double.pi
        while degrees < 0.0 {
            degrees += 360.0
        }
        while degrees >= 360.0 {
            degrees -= 360.0
        }
        return degrees
    }

    private func scanlineIntersections(
        polygon: [Point2D],
        y: Double,
        tolerance: Double
    ) -> [Double] {
        var intersections: [Double] = []
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let deltaY = end.y - start.y
            guard abs(deltaY) > tolerance else {
                continue
            }
            let crosses = (start.y <= y && end.y > y) || (end.y <= y && start.y > y)
            guard crosses else {
                continue
            }
            let fraction = (y - start.y) / deltaY
            intersections.append(start.x + (end.x - start.x) * fraction)
        }
        return intersections.sorted()
    }

    private func rotate(
        _ point: Point2D,
        cosine: Double,
        sine: Double
    ) -> Point2D {
        Point2D(
            x: point.x * cosine + point.y * sine,
            y: -point.x * sine + point.y * cosine
        )
    }

    private func unrotate(
        _ point: Point2D,
        cosine: Double,
        sine: Double
    ) -> Point2D {
        Point2D(
            x: point.x * cosine - point.y * sine,
            y: point.x * sine + point.y * cosine
        )
    }

    private func planeBounds(
        _ points: [Point2D]
    ) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var bounds = BoundsAccumulator()
        for point in points {
            bounds.include(point)
        }
        guard let result = bounds.bounds else {
            return nil
        }
        return (result.minX, result.minY, result.maxX, result.maxY)
    }

    private func pointOnPlane(
        _ point: Point2D,
        plane: SectionAnalysisResult.Plane
    ) -> Point3D {
        plane.origin + plane.u * point.x + plane.v * point.y
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

    private func angleDegrees(
        first: Point3D,
        center: Point3D,
        second: Point3D
    ) -> Double? {
        let firstVector = Vector3D(
            x: first.x - center.x,
            y: first.y - center.y,
            z: first.z - center.z
        )
        let secondVector = Vector3D(
            x: second.x - center.x,
            y: second.y - center.y,
            z: second.z - center.z
        )
        let firstLength = firstVector.length
        let secondLength = secondVector.length
        guard firstLength > 1.0e-12,
              secondLength > 1.0e-12 else {
            return nil
        }
        let cosine = min(
            max(dot(firstVector, secondVector) / (firstLength * secondLength), -1.0),
            1.0
        )
        return acos(cosine) * 180.0 / .pi
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
        maximumStrokeCount: Int,
        sectionArtifacts: SectionProjectionArtifacts
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
        if sectionArtifacts.truncatedHatches {
            diagnostics.append(
                EditorDiagnostic(
                    severity: .warning,
                    message: "Drawing projection section hatching was truncated at \(maximumStrokeCount) hatch segment(s)."
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
