import Foundation
import RupaCoreTypes
import CADTopology
import SwiftCAD
import RupaGeometry

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
            try document.validate(objectRegistry: objectRegistry, unlessEvaluatedBy: currentEvaluation, generation: currentGeneration)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before section analysis: \(String(describing: error))"
            )
        }

        let tolerance = try resolvedTolerance(query.toleranceMeters, document: document)
        let maximumSegments = try resolvedMaximumSegments(query.maximumIntersectionSegments)
        let offsetMeters = try resolvedOffset(query.offsetMeters)
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let plane = try resolvedPlane(
            source: query.source,
            offsetMeters: offsetMeters,
            flipsNormal: query.flipsNormal,
            document: document,
            hierarchy: hierarchy,
            activeConstructionPlaneID: activeConstructionPlaneID,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )

        var bodies: [SectionAnalysisResult.Body] = []
        var segments: [SectionAnalysisResult.IntersectionSegment] = []
        var truncatedSegments = false
        let occurrences = try hierarchy.resolvedOccurrences()

        if document.cadDocument.hasActiveRenderableTopologyFeatures {
            let evaluatedDocument = try DocumentEvaluationContextResolver(
                pipeline: pipelineOverride
            ).evaluatedDocument(
                document: document, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration,
                failurePrefix: "Document must evaluate successfully before section analysis"
            )
            let identitiesByBodyID = identityResolver.bodyIdentityByBodyID(
                in: evaluatedDocument.subshapes
            )

            for (bodyID, mesh) in evaluatedDocument.meshes.sorted(by: { $0.key.description < $1.key.description }) {
                let body = evaluatedDocument.brep.bodies[bodyID]
                guard let identity = identitiesByBodyID[bodyID] else {
                    throw EditorError(code: .referenceUnresolved, message: "Section analysis cannot identify an evaluated CAD body.")
                }
                let placements = hierarchy.presentationOccurrences(of: identity.sourceFeatureID, in: occurrences)
                    .filter { occurrence in
                        guard occurrence.isVisible,
                              let set = document.productMetadata.sceneNodes[occurrence.sourceSceneNodeID]?.object?.geometryRepresentations,
                              let selected = set.selection,
                              case .cad(_, let outputID) = set.representations[selected.presentation]?.source else { return false }
                        return outputID == identity.sourceFeatureID.description
                    }
                for placement in placements {
                    let sceneNodeID = placement.sceneNodeID
                    let occurrenceID = placement.id
                    let transform = placement.worldTransform
                    let analysis = try analyzeBody(
                        bodyID: bodyID.description,
                        sceneNodeID: sceneNodeID,
                        occurrenceID: occurrenceID,
                        transform: transform,
                        identity: identity,
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
            }
        }

        var authoredMeshes: [GeometrySourceID: Mesh] = [:]
        for occurrence in occurrences where occurrence.isVisible {
            try Task.checkCancellation()
            guard let node = document.productMetadata.sceneNodes[occurrence.sourceSceneNodeID],
                  let set = node.object?.geometryRepresentations, let selected = set.selection,
                  case .authoredMesh(let sourceID) = set.representations[selected.presentation]?.source else { continue }
            let mesh: Mesh
            if let cached = authoredMeshes[sourceID] {
                mesh = cached
            } else {
                guard let source = document.authoredMeshAssets[sourceID]?.source else {
                    throw EditorError(code: .referenceUnresolved, message: "Section analysis cannot resolve mesh \(sourceID.rawValue).")
                }
                mesh = try triangulatedMesh(source)
                authoredMeshes[sourceID] = mesh
            }
            var analysis = try analyzeBody(
                bodyID: "mesh:\(sourceID.rawValue)", sceneNodeID: occurrence.sceneNodeID,
                occurrenceID: occurrence.id, transform: occurrence.worldTransform, identity: nil, body: nil,
                mesh: mesh, plane: plane.coordinateSystem, tolerance: tolerance,
                includesIntersectionSegments: query.includesIntersectionSegments,
                remainingSegmentCapacity: max(maximumSegments - segments.count, 0)
            )
            analysis.body.name = node.name
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
            interferences: SectionAnalysisInterferenceDetector(tolerance: tolerance).interferences(in: contours),
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
        hierarchy: SceneNodeHierarchy,
        activeConstructionPlaneID: ConstructionPlaneSourceID?,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws -> ResolvedPlane {
        let basePlane = try resolvePlane(
            source,
            document: document,
            hierarchy: hierarchy,
            activeConstructionPlaneID: activeConstructionPlaneID,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
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
        hierarchy: SceneNodeHierarchy,
        activeConstructionPlaneID: ConstructionPlaneSourceID?,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws -> ResolvedPlane {
        switch source {
        case .face(let target):
            return try resolvedFacePlane(
                target,
                document: document,
                hierarchy: hierarchy,
                objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation,
                currentGeneration: currentGeneration
            )
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
            return try resolvedConstructionPlane(
                constructionPlane.plane,
                id: constructionPlane.id,
                name: constructionPlane.name,
                sourceKind: .constructionPlane,
                document: document,
                hierarchy: hierarchy
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
            return try resolvedConstructionPlane(
                constructionPlane.plane,
                id: constructionPlane.id,
                name: constructionPlane.name,
                sourceKind: .activeConstructionPlane,
                document: document,
                hierarchy: hierarchy
            )
        case .sceneNode(let id):
            guard let node = document.productMetadata.sceneNodes[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Section analysis scene node \(id.description) was not found."
                )
            }
            return try resolvedSceneNodePlane(node, document: document, hierarchy: hierarchy)
        }
    }

    private func resolvedConstructionPlane(
        _ plane: SketchPlane,
        id: ConstructionPlaneSourceID,
        name: String,
        sourceKind: SectionAnalysisResult.PlaneSourceKind,
        document: DesignDocument,
        hierarchy: SceneNodeHierarchy
    ) throws -> ResolvedPlane {
        let nodeIDs = document.productMetadata.sceneNodes.compactMap { sceneNodeID, node in
            node.reference?.constructionPlaneID == id ? sceneNodeID : nil
        }
        guard nodeIDs.count <= 1 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane \(id.description) has multiple scene placements; select a specific scene node."
            )
        }
        let local = try resolvedSketchPlane(
            plane,
            sourceKind: sourceKind,
            sourceID: id.description,
            sourceName: name
        )
        guard let sceneNodeID = nodeIDs.first else { return local }
        return try placedPlane(local, by: hierarchy.worldTransform(of: sceneNodeID))
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

    /// The plane of a selected planar face, at the occurrence the selection names, facing out of
    /// the body.
    private func resolvedFacePlane(
        _ target: SelectionTarget,
        document: DesignDocument,
        hierarchy: SceneNodeHierarchy,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws -> ResolvedPlane {
        let topology = try TopologySnapshotService().snapshot(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        let facePlane = try ConstructionPlaneTargetResolver().planarGeneratedFacePlane(
            alignedTo: target,
            topology: topology,
            operationName: "Section analysis",
            tolerance: document.modelingSettings.tolerance
        )
        let name = document.productMetadata.sceneNodes[target.sceneNodeID]?.name
        let local = try resolvedSketchPlane(
            facePlane,
            sourceKind: .face,
            sourceID: target.sceneNodeID.description,
            sourceName: name.map { "\($0) face" } ?? "Face"
        )
        return try placedPlane(local, by: hierarchy.worldTransform(of: target.sceneNodeID))
    }

    private func resolvedSceneNodePlane(
        _ node: SceneNode,
        document: DesignDocument,
        hierarchy: SceneNodeHierarchy
    ) throws -> ResolvedPlane {
        let isConstruction = node.reference?.kind == .construction
            || node.object?.category == .construction
        guard isConstruction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Section analysis scene node \(node.id.description) must be a construction or section plane node."
            )
        }

        if let constructionPlaneID = node.reference?.constructionPlaneID,
           let constructionPlane = document.productMetadata.constructionPlanes[constructionPlaneID] {
            let local = try resolvedSketchPlane(
                constructionPlane.plane,
                sourceKind: .sceneNode,
                sourceID: node.id.description,
                sourceName: node.name
            )
            return try placedPlane(local, by: hierarchy.worldTransform(of: node.id))
        }
        let local = try resolvedSketchPlane(
            .xy,
            sourceKind: .sceneNode,
            sourceID: node.id.description,
            sourceName: node.name
        )
        return try placedPlane(local, by: hierarchy.worldTransform(of: node.id))
    }

    private func placedPlane(_ source: ResolvedPlane, by transform: Transform3D) throws -> ResolvedPlane {
        let origin = try transform.applied(to: source.coordinateSystem.origin)
        let normal = try transform.applyingNormal(to: source.coordinateSystem.normal)
        let rawU = try transform.applyingLinearPart(to: source.coordinateSystem.u)
        let projectedU = rawU - normal * rawU.dot(normal)
        let u = try projectedU.normalized(tolerance: 1.0e-12)
        let v = normal.cross(u)
        let resultPlane = SectionAnalysisResult.Plane(
            sourceKind: source.resultPlane.sourceKind,
            sourceID: source.resultPlane.sourceID,
            sourceName: source.resultPlane.sourceName,
            origin: origin,
            normal: normal,
            u: u,
            v: v
        )
        return ResolvedPlane(
            resultPlane: resultPlane,
            coordinateSystem: SketchPlaneCoordinateSystem(
                plane: .plane(Plane3D(origin: origin, normal: normal)),
                origin: origin,
                normal: normal,
                u: u,
                v: v
            )
        )
    }

    /// Adapts source geometry once per asset for the common section triangle classifier.
    /// Triangulation and index validity are owned by the same geometry API used for presentation.
    private func triangulatedMesh(_ source: MeshSource) throws -> Mesh {
        let index = try source.makeTriangulationIndex()
        var indices: [UInt32] = []
        var telemetry = MeshTriangulationTelemetry()
        for face in source.faceIDs.indices {
            for triangle in try source.triangulate(faceIndex: face, using: index, telemetry: &telemetry) {
                for vertex in [triangle.vertexIDs.0, triangle.vertexIDs.1, triangle.vertexIDs.2] {
                    guard let position = index.positionIndex(for: vertex), let value = UInt32(exactly: position) else {
                        throw EditorError(code: .evaluationFailed, message: "Section mesh triangle has an invalid vertex index.")
                    }
                    indices.append(value)
                }
            }
        }
        return Mesh(positions: source.vertexPositions.map { Point3D(x: $0.x, y: $0.y, z: $0.z) }, indices: indices)
    }

    private func analyzeBody(
        bodyID: String,
        sceneNodeID: SceneNodeID?,
        occurrenceID: SceneOccurrenceID?,
        transform: Transform3D,
        identity: GeneratedBodyIdentityResolver.Identity?,
        body: CADTopology.Body?,
        mesh: Mesh,
        plane: SketchPlaneCoordinateSystem,
        tolerance: Double,
        includesIntersectionSegments: Bool,
        remainingSegmentCapacity: Int
    ) throws -> BodyAnalysis {
        var frontVertexCount = 0
        var behindVertexCount = 0
        var coplanarVertexCount = 0
        let positions = try mesh.positions.map { try transform.applied(to: $0) }
        let distances = positions.map { point in
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
                throw EditorError(code: .evaluationFailed, message: "Section mesh triangle references a missing vertex.")
            }

            let trianglePoints = [
                positions[firstIndex],
                positions[secondIndex],
                positions[thirdIndex],
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
                    sceneNodeID: sceneNodeID,
                    occurrenceID: occurrenceID,
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
            bodyID: bodyID,
            sceneNodeID: sceneNodeID,
            occurrenceID: occurrenceID,
            sourceFeatureID: identity?.sourceFeatureID.description,
            subshapeID: identity.map { GeneratedSubshapeIdentity.string(for: $0.subshapeID) },
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
        bodyID: String,
        sceneNodeID: SceneNodeID?,
        occurrenceID: SceneOccurrenceID?,
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
            bodyID: bodyID,
            sceneNodeID: sceneNodeID,
                    occurrenceID: occurrenceID,
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
