import Foundation
import SwiftCAD

public struct SectionAnalysisService: Sendable {
    private struct ResolvedPlane {
        var resultPlane: SectionAnalysisResult.Plane
        var coordinateSystem: SketchPlaneCoordinateSystem
    }

    private struct BodyAnalysis {
        var body: SectionAnalysisResult.Body
        var segments: [SectionAnalysisResult.IntersectionSegment]
        var truncatedSegments: Bool
    }

    private enum SignedSide {
        case front
        case behind
        case coplanar
    }

    private let pipelineOverride: CADPipeline?
    private let identityResolver = GeneratedBodyIdentityResolver()

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func analyze(
        document: DesignDocument,
        query: SectionAnalysisQuery,
        activeConstructionPlaneID: ConstructionPlaneSourceID?,
        displayUnit: LengthDisplayUnit,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> SectionAnalysisResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before section analysis: \(String(describing: error))"
            )
        }

        let tolerance = try resolvedTolerance(query.toleranceMeters, document: document)
        let maximumSegments = try resolvedMaximumSegments(query.maximumIntersectionSegments)
        let offsetMeters = try resolvedOffset(query.offsetMeters)
        let plane = try resolvedPlane(
            source: query.source,
            offsetMeters: offsetMeters,
            flipsNormal: query.flipsNormal,
            document: document,
            activeConstructionPlaneID: activeConstructionPlaneID
        )

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return SectionAnalysisResult(
                displayUnit: displayUnit,
                plane: plane.resultPlane,
                toleranceMeters: tolerance,
                bodies: [],
                intersectionSegments: [],
                truncatedIntersectionSegments: false,
                diagnostics: [
                    EditorDiagnostic(
                        severity: .info,
                        message: "Section analysis completed with no generated body meshes."
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
            failurePrefix: "Document must evaluate successfully before section analysis"
        )

        var bodies: [SectionAnalysisResult.Body] = []
        var segments: [SectionAnalysisResult.IntersectionSegment] = []
        var truncatedSegments = false
        let identitiesByBodyID = identityResolver.bodyIdentityByBodyID(
            in: evaluatedDocument.generatedNames
        )

        for (bodyID, mesh) in evaluatedDocument.meshes.sorted(by: { $0.key.description < $1.key.description }) {
            let body = evaluatedDocument.brep.bodies[bodyID]
            let analysis = analyzeBody(
                bodyID: bodyID,
                identity: identitiesByBodyID[bodyID],
                body: body,
                mesh: mesh,
                plane: plane.coordinateSystem,
                tolerance: tolerance,
                includesIntersectionSegments: query.includesIntersectionSegments,
                remainingSegmentCapacity: max(0, maximumSegments - segments.count)
            )
            bodies.append(analysis.body)
            segments.append(contentsOf: analysis.segments)
            truncatedSegments = truncatedSegments || analysis.truncatedSegments
        }

        let diagnostics = diagnostics(
            resultBodies: bodies,
            truncatedSegments: truncatedSegments,
            maximumSegments: maximumSegments
        )
        let contours = SectionAnalysisContourBuilder(tolerance: tolerance).build(
            segments: segments
        )
        return SectionAnalysisResult(
            displayUnit: displayUnit,
            plane: plane.resultPlane,
            toleranceMeters: tolerance,
            bodies: bodies,
            intersectionSegments: segments,
            intersectionContours: contours,
            truncatedIntersectionSegments: truncatedSegments,
            diagnostics: diagnostics
        )
    }

    private func resolvedTolerance(
        _ tolerance: Double?,
        document: DesignDocument
    ) throws -> Double {
        let resolved = tolerance ?? document.modelingSettings.tolerance.distance
        guard resolved.isFinite, resolved > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Section analysis tolerance must be finite and greater than zero."
            )
        }
        return resolved
    }

    private func resolvedMaximumSegments(_ maximumSegments: Int) throws -> Int {
        guard maximumSegments >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Section analysis maximum intersection segments must be zero or greater."
            )
        }
        return maximumSegments
    }

    private func resolvedOffset(_ offsetMeters: Double) throws -> Double {
        guard offsetMeters.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Section analysis offset must be finite."
            )
        }
        return offsetMeters
    }

    private func resolvedPlane(
        source: SectionAnalysisQuery.Source,
        offsetMeters: Double,
        flipsNormal: Bool,
        document: DesignDocument,
        activeConstructionPlaneID: ConstructionPlaneSourceID?
    ) throws -> ResolvedPlane {
        let basePlane = try resolvePlane(
            source,
            document: document,
            activeConstructionPlaneID: activeConstructionPlaneID
        )
        guard offsetMeters != 0.0 || flipsNormal else {
            return basePlane
        }
        return transformedPlane(
            basePlane,
            offsetMeters: offsetMeters,
            flipsNormal: flipsNormal
        )
    }

    private func resolvePlane(
        _ source: SectionAnalysisQuery.Source,
        document: DesignDocument,
        activeConstructionPlaneID: ConstructionPlaneSourceID?
    ) throws -> ResolvedPlane {
        switch source {
        case .sketchPlane(let plane):
            return try resolvedSketchPlane(
                plane,
                sourceKind: .sketchPlane,
                sourceID: nil,
                sourceName: nil
            )
        case .constructionPlane(let id):
            guard let constructionPlane = document.productMetadata.constructionPlanes[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Section analysis construction plane \(id.description) was not found."
                )
            }
            return try resolvedSketchPlane(
                constructionPlane.plane,
                sourceKind: .constructionPlane,
                sourceID: constructionPlane.id.description,
                sourceName: constructionPlane.name
            )
        case .activeConstructionPlane:
            guard let activeConstructionPlaneID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Section analysis requires an active construction plane."
                )
            }
            guard let constructionPlane = document.productMetadata.constructionPlanes[
                activeConstructionPlaneID
            ] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "The active construction plane no longer exists in the document source."
                )
            }
            return try resolvedSketchPlane(
                constructionPlane.plane,
                sourceKind: .activeConstructionPlane,
                sourceID: constructionPlane.id.description,
                sourceName: constructionPlane.name
            )
        case .sceneNode(let id):
            guard let node = document.productMetadata.sceneNodes[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Section analysis scene node \(id.description) was not found."
                )
            }
            return try resolvedSceneNodePlane(node)
        }
    }

    private func transformedPlane(
        _ plane: ResolvedPlane,
        offsetMeters: Double,
        flipsNormal: Bool
    ) -> ResolvedPlane {
        let source = plane.resultPlane
        let origin = source.origin + source.normal * offsetMeters
        let normal = flipsNormal ? source.normal * -1.0 : source.normal
        let resultPlane = SectionAnalysisResult.Plane(
            sourceKind: source.sourceKind,
            sourceID: source.sourceID,
            sourceName: source.sourceName,
            origin: origin,
            normal: normal,
            u: source.u,
            v: source.v
        )
        return ResolvedPlane(
            resultPlane: resultPlane,
            coordinateSystem: SketchPlaneCoordinateSystem(
                plane: SketchPlane.plane(Plane3D(origin: origin, normal: normal)),
                origin: origin,
                normal: normal,
                u: source.u,
                v: source.v
            )
        )
    }

    private func resolvedSketchPlane(
        _ plane: SketchPlane,
        sourceKind: SectionAnalysisResult.PlaneSourceKind,
        sourceID: String?,
        sourceName: String?
    ) throws -> ResolvedPlane {
        let coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane)
        return ResolvedPlane(
            resultPlane: SectionAnalysisResult.Plane(
                sourceKind: sourceKind,
                sourceID: sourceID,
                sourceName: sourceName,
                origin: coordinateSystem.origin,
                normal: coordinateSystem.normal,
                u: coordinateSystem.u,
                v: coordinateSystem.v
            ),
            coordinateSystem: coordinateSystem
        )
    }

    private func resolvedSceneNodePlane(_ node: SceneNode) throws -> ResolvedPlane {
        let isConstruction = node.reference?.kind == .construction
            || node.object?.category == .construction
        guard isConstruction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Section analysis scene node \(node.id.description) must be a construction or section plane node."
            )
        }

        let values = node.localTransform.matrix.values
        let origin = Point3D(
            x: values[12],
            y: values[13],
            z: values[14]
        )
        let rawNormal = Vector3D(
            x: values[8],
            y: values[9],
            z: values[10]
        )
        let normal = try rawNormal.normalized(tolerance: 1.0e-12)
        let rawU = Vector3D(
            x: values[0],
            y: values[1],
            z: values[2]
        )
        let u = resolvedPlaneUAxis(rawU: rawU, normal: normal)
        let v = normal.cross(u)
        let plane = SketchPlane.plane(Plane3D(origin: origin, normal: normal))

        return ResolvedPlane(
            resultPlane: SectionAnalysisResult.Plane(
                sourceKind: .sceneNode,
                sourceID: node.id.description,
                sourceName: node.name,
                origin: origin,
                normal: normal,
                u: u,
                v: v
            ),
            coordinateSystem: SketchPlaneCoordinateSystem(
                plane: plane,
                origin: origin,
                normal: normal,
                u: u,
                v: v
            )
        )
    }

    private func resolvedPlaneUAxis(rawU: Vector3D, normal: Vector3D) -> Vector3D {
        let projected = rawU - normal * rawU.dot(normal)
        if let normalized = normalizedVector(projected) {
            return normalized
        }
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let fallback = helper.cross(normal)
        if let normalized = normalizedVector(fallback) {
            return normalized
        }
        return Vector3D.unitX
    }

    private func normalizedVector(_ vector: Vector3D) -> Vector3D? {
        let length = vector.length
        guard length.isFinite, length > 1.0e-12 else {
            return nil
        }
        return vector / length
    }

    private func analyzeBody(
        bodyID: BodyID,
        identity: GeneratedBodyIdentityResolver.Identity?,
        body: Body?,
        mesh: Mesh,
        plane: SketchPlaneCoordinateSystem,
        tolerance: Double,
        includesIntersectionSegments: Bool,
        remainingSegmentCapacity: Int
    ) -> BodyAnalysis {
        var frontVertexCount = 0
        var behindVertexCount = 0
        var coplanarVertexCount = 0
        let distances = mesh.positions.map { point in
            let distance = plane.project(point).depth
            switch side(for: distance, tolerance: tolerance) {
            case .front:
                frontVertexCount += 1
            case .behind:
                behindVertexCount += 1
            case .coplanar:
                coplanarVertexCount += 1
            }
            return distance
        }

        var frontTriangleCount = 0
        var behindTriangleCount = 0
        var coplanarTriangleCount = 0
        var touchingTriangleCount = 0
        var intersectingTriangleCount = 0
        var segments: [SectionAnalysisResult.IntersectionSegment] = []
        var totalSegmentCount = 0
        var truncatedSegments = false
        var triangleIndex = 0

        while triangleIndex + 2 < mesh.indices.count {
            let firstIndex = Int(mesh.indices[triangleIndex])
            let secondIndex = Int(mesh.indices[triangleIndex + 1])
            let thirdIndex = Int(mesh.indices[triangleIndex + 2])
            guard firstIndex < mesh.positions.count,
                  secondIndex < mesh.positions.count,
                  thirdIndex < mesh.positions.count else {
                triangleIndex += 3
                continue
            }

            let trianglePoints = [
                mesh.positions[firstIndex],
                mesh.positions[secondIndex],
                mesh.positions[thirdIndex],
            ]
            let triangleDistances = [
                distances[firstIndex],
                distances[secondIndex],
                distances[thirdIndex],
            ]
            let triangleSides = triangleDistances.map { side(for: $0, tolerance: tolerance) }
            let classification = triangleClassification(triangleSides)

            switch classification {
            case .inFront:
                frontTriangleCount += 1
            case .behind:
                behindTriangleCount += 1
            case .coplanar:
                coplanarTriangleCount += 1
            case .touching:
                touchingTriangleCount += 1
            case .intersects:
                intersectingTriangleCount += 1
            case .spansPlane:
                intersectingTriangleCount += 1
            }

            if classification == .intersects || classification == .touching {
                let segment = intersectionSegment(
                    bodyID: bodyID,
                    points: trianglePoints,
                    distances: triangleDistances,
                    plane: plane,
                    tolerance: tolerance
                )
                if let segment {
                    totalSegmentCount += 1
                    if includesIntersectionSegments, segments.count < remainingSegmentCapacity {
                        segments.append(segment)
                    } else if includesIntersectionSegments {
                        truncatedSegments = true
                    }
                }
            }

            triangleIndex += 3
        }

        let triangleCount = mesh.indices.count / 3
        let bodyClassification = bodyClassification(
            triangleCount: triangleCount,
            frontTriangleCount: frontTriangleCount,
            behindTriangleCount: behindTriangleCount,
            coplanarTriangleCount: coplanarTriangleCount,
            touchingTriangleCount: touchingTriangleCount,
            intersectingTriangleCount: intersectingTriangleCount
        )
        let resultBody = SectionAnalysisResult.Body(
            bodyID: bodyID.description,
            sourceFeatureID: identity?.sourceFeatureID.description,
            persistentName: identity?.persistentName,
            name: body?.name,
            kind: body?.kind,
            materialID: mesh.material?.description ?? body?.material?.description,
            classification: bodyClassification,
            vertexCount: mesh.positions.count,
            triangleCount: triangleCount,
            frontVertexCount: frontVertexCount,
            behindVertexCount: behindVertexCount,
            coplanarVertexCount: coplanarVertexCount,
            frontTriangleCount: frontTriangleCount,
            behindTriangleCount: behindTriangleCount,
            coplanarTriangleCount: coplanarTriangleCount,
            touchingTriangleCount: touchingTriangleCount,
            intersectingTriangleCount: intersectingTriangleCount,
            intersectionSegmentCount: totalSegmentCount
        )
        return BodyAnalysis(
            body: resultBody,
            segments: segments,
            truncatedSegments: truncatedSegments
        )
    }

    private func side(for distance: Double, tolerance: Double) -> SignedSide {
        if distance > tolerance {
            return .front
        }
        if distance < -tolerance {
            return .behind
        }
        return .coplanar
    }

    private func triangleClassification(
        _ sides: [SignedSide]
    ) -> SectionAnalysisResult.BodyClassification {
        let hasFront = sides.contains(.front)
        let hasBehind = sides.contains(.behind)
        let hasCoplanar = sides.contains(.coplanar)
        if hasFront && hasBehind {
            return .intersects
        }
        if hasCoplanar && !hasFront && !hasBehind {
            return .coplanar
        }
        if hasCoplanar {
            return .touching
        }
        if hasFront {
            return .inFront
        }
        return .behind
    }

    private func bodyClassification(
        triangleCount: Int,
        frontTriangleCount: Int,
        behindTriangleCount: Int,
        coplanarTriangleCount: Int,
        touchingTriangleCount: Int,
        intersectingTriangleCount: Int
    ) -> SectionAnalysisResult.BodyClassification {
        if intersectingTriangleCount > 0 {
            return .intersects
        }
        if touchingTriangleCount > 0 {
            return .touching
        }
        if triangleCount > 0, coplanarTriangleCount == triangleCount {
            return .coplanar
        }
        if frontTriangleCount > 0, behindTriangleCount > 0 {
            return .spansPlane
        }
        if frontTriangleCount > 0 {
            return .inFront
        }
        return .behind
    }

    private func intersectionSegment(
        bodyID: BodyID,
        points: [Point3D],
        distances: [Double],
        plane: SketchPlaneCoordinateSystem,
        tolerance: Double
    ) -> SectionAnalysisResult.IntersectionSegment? {
        var intersectionPoints: [Point3D] = []
        appendEdgeIntersection(
            start: points[0],
            end: points[1],
            startDistance: distances[0],
            endDistance: distances[1],
            tolerance: tolerance,
            into: &intersectionPoints
        )
        appendEdgeIntersection(
            start: points[1],
            end: points[2],
            startDistance: distances[1],
            endDistance: distances[2],
            tolerance: tolerance,
            into: &intersectionPoints
        )
        appendEdgeIntersection(
            start: points[2],
            end: points[0],
            startDistance: distances[2],
            endDistance: distances[0],
            tolerance: tolerance,
            into: &intersectionPoints
        )

        guard intersectionPoints.count >= 2 else {
            return nil
        }
        let start = intersectionPoints[0]
        let end = intersectionPoints[1]
        guard (end - start).length > tolerance else {
            return nil
        }
        return SectionAnalysisResult.IntersectionSegment(
            bodyID: bodyID.description,
            start: start,
            end: end,
            start2D: plane.project(start).point,
            end2D: plane.project(end).point
        )
    }

    private func appendEdgeIntersection(
        start: Point3D,
        end: Point3D,
        startDistance: Double,
        endDistance: Double,
        tolerance: Double,
        into points: inout [Point3D]
    ) {
        let startIsCoplanar = abs(startDistance) <= tolerance
        let endIsCoplanar = abs(endDistance) <= tolerance
        if startIsCoplanar {
            appendUnique(start, tolerance: tolerance, into: &points)
        }
        if endIsCoplanar {
            appendUnique(end, tolerance: tolerance, into: &points)
        }
        guard !startIsCoplanar,
              !endIsCoplanar,
              (startDistance > 0.0) != (endDistance > 0.0) else {
            return
        }
        let denominator = startDistance - endDistance
        guard denominator.isFinite, abs(denominator) > tolerance else {
            return
        }
        let fraction = startDistance / denominator
        guard fraction.isFinite else {
            return
        }
        let delta = end - start
        appendUnique(
            start + delta * min(max(fraction, 0.0), 1.0),
            tolerance: tolerance,
            into: &points
        )
    }

    private func appendUnique(
        _ point: Point3D,
        tolerance: Double,
        into points: inout [Point3D]
    ) {
        guard points.contains(where: { ($0 - point).length <= tolerance }) == false else {
            return
        }
        points.append(point)
    }

    private func diagnostics(
        resultBodies: [SectionAnalysisResult.Body],
        truncatedSegments: Bool,
        maximumSegments: Int
    ) -> [EditorDiagnostic] {
        var diagnostics = [
            EditorDiagnostic(
                severity: .info,
                message: "Section analysis completed with \(resultBodies.count) generated body mesh(es)."
            ),
        ]
        if truncatedSegments {
            diagnostics.append(
                EditorDiagnostic(
                    severity: .warning,
                    message: "Section analysis intersection segments were truncated at \(maximumSegments)."
                )
            )
        }
        return diagnostics
    }
}

private extension SketchPlaneCoordinateSystem {
    init(
        plane: SketchPlane,
        origin: Point3D,
        normal: Vector3D,
        u: Vector3D,
        v: Vector3D
    ) {
        self.plane = plane
        self.origin = origin
        self.normal = normal
        self.u = u
        self.v = v
    }
}
