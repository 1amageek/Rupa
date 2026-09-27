import Foundation
import SwiftCAD
import RupaCoreTypes

public struct TopologySnapshotService: Sendable {
    public enum MetricPolicy: Equatable, Sendable {
        /// Computes optional face-area and edge-length fields.
        case include
        /// Leaves optional metric fields unset while preserving topology and selection geometry.
        case omit
    }

    private let exactEvaluatorOverride: (any ExactDocumentEvaluating)?
    private let edgeLengthEvaluator: any BRepEdgeLengthEvaluating

    public init(
        exactEvaluator: (any ExactDocumentEvaluating)? = nil,
        edgeLengthEvaluator: any BRepEdgeLengthEvaluating = DefaultBRepEdgeLengthEvaluator()
    ) {
        self.exactEvaluatorOverride = exactEvaluator
        self.edgeLengthEvaluator = edgeLengthEvaluator
    }

    private struct CurveSummary {
        var kind: String
        var origin: TopologySummaryResult.Entry.Point?
        var direction: TopologySummaryResult.Entry.Point?
        var center: TopologySummaryResult.Entry.Point?
        var normal: TopologySummaryResult.Entry.Point?
        var radius: Double?
        var parameterXAxis: TopologySummaryResult.Entry.Point?
        var parameterYAxis: TopologySummaryResult.Entry.Point?
        var degree: Int?
        var controlPointCount: Int?
        var isRational: Bool?
    }

    private struct SurfaceSummary {
        var kind: String
        var origin: TopologySummaryResult.Entry.Point?
        var normal: TopologySummaryResult.Entry.Point?
        var axis: TopologySummaryResult.Entry.Point?
        var radius: Double?
        var uDegree: Int?
        var vDegree: Int?
        var uControlPointCount: Int?
        var vControlPointCount: Int?
    }

    public func snapshot(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil,
        metricPolicy: MetricPolicy = .include
    ) throws -> TopologySnapshot {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before topology snapshot: \(String(describing: error))"
            )
        }

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return TopologySnapshot()
        }

        let evaluatedDocument = try DocumentEvaluationContextResolver(
            exactEvaluator: exactEvaluatorOverride
        ).exactEvaluatedDocument(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration,
            failurePrefix: "Document must evaluate successfully before topology snapshot"
        )

        // Entries without a presenting scene node stay in the snapshot as kernel topology, but carry
        // no scene node, so no scene-qualified selection or placement can resolve against them.
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let entries = try evaluatedDocument.subshapes.entries
            .map { subshapeID, reference in
                try topologyEntry(
                    subshapeID: subshapeID,
                    reference: reference,
                    evaluatedDocument: evaluatedDocument,
                    hierarchy: hierarchy,
                    metricPolicy: metricPolicy
                )
            }
            .sorted {
                if $0.kind.rawValue == $1.kind.rawValue {
                    return $0.subshapeID < $1.subshapeID
                }
                return $0.kind.rawValue < $1.kind.rawValue
            }

        return TopologySnapshot(
            counts: TopologySummaryResult.Counts(
                bodyCount: evaluatedDocument.brep.bodies.count,
                faceCount: evaluatedDocument.brep.faces.count,
                edgeCount: evaluatedDocument.brep.edges.count,
                vertexCount: evaluatedDocument.brep.vertices.count
            ),
            entries: entries,
            evaluatedDocument: evaluatedDocument
        )
    }

    /// The exact point halfway along an edge, answered by Swift-CAD's edge query on the curve.
    ///
    /// An edge the query cannot place has no midpoint, so no midpoint snap or anchor is offered
    /// for it rather than a chord midpoint that lies off a curved edge.
    private func edgeMidpoint(
        _ reference: StableSubshapeReference,
        in evaluatedDocument: EvaluatedDocument
    ) -> TopologySummaryResult.Entry.Point? {
        do {
            let frame = try EdgeQueryEvaluator(tolerance: .standard).midpoint(
                of: EdgeReference(subshape: reference),
                in: evaluatedDocument
            )
            return point(frame.point)
        } catch {
            return nil
        }
    }

    private func topologyEntry(
        subshapeID: SubshapeID,
        reference: TopologyReference,
        evaluatedDocument: EvaluatedDocument,
        hierarchy: SceneNodeHierarchy,
        metricPolicy: MetricPolicy
    ) throws -> TopologySummaryResult.Entry {
        let identity = GeneratedSubshapeIdentity.string(for: subshapeID)
        let stableReference = try evaluatedDocument.stableSubshapeReference(for: subshapeID)
        let sceneNodeID = hierarchy.presentingSceneNodeID(for: subshapeID.featureID)?.description
        switch reference {
        case .body(let bodyID):
            let body = evaluatedDocument.brep.bodies[bodyID]
            return TopologySummaryResult.Entry(
                subshapeID: identity,
                stableReference: stableReference,
                kind: .body,
                referenceID: bodyID.description,
                sourceFeatureID: subshapeID.featureID.description,
                sceneNodeID: sceneNodeID,
                generatedRole: subshapeID.role,
                ordinal: subshapeID.ordinal,
                shellCount: body?.shellIDs.count
            )
        case .face(let faceID):
            let face = evaluatedDocument.brep.faces[faceID]
            let edgeCount = face?.loops.reduce(0) { partial, loopID in
                partial + (evaluatedDocument.brep.loops[loopID]?.edges.count ?? 0)
            }
            let surfaceInfo = face.flatMap { face in
                evaluatedDocument.brep.geometry.surfaces[face.surfaceID].map(describeSurface)
            }
            let center = face.flatMap { faceCenter(faceID, $0, in: evaluatedDocument.brep) }
            let normal = face.flatMap { faceNormal($0, reference: stableReference, in: evaluatedDocument) }
            return TopologySummaryResult.Entry(
                subshapeID: identity,
                stableReference: stableReference,
                kind: .face,
                referenceID: faceID.description,
                sourceFeatureID: subshapeID.featureID.description,
                sceneNodeID: sceneNodeID,
                generatedRole: subshapeID.role,
                ordinal: subshapeID.ordinal,
                selectionComponentID: SelectionComponentID.generatedTopology(subshapeID).rawValue,
                surfaceKind: surfaceInfo?.kind,
                surfaceOrigin: surfaceInfo?.origin,
                surfaceNormal: surfaceInfo?.normal,
                surfaceAxis: surfaceInfo?.axis,
                surfaceRadius: surfaceInfo?.radius,
                surfaceUDegree: surfaceInfo?.uDegree,
                surfaceVDegree: surfaceInfo?.vDegree,
                surfaceUControlPointCount: surfaceInfo?.uControlPointCount,
                surfaceVControlPointCount: surfaceInfo?.vControlPointCount,
                areaSquareMeters: metricPolicy == .include
                    ? face.flatMap { _ in faceAreaSquareMeters(faceID, in: evaluatedDocument.brep) }
                    : nil,
                center: center,
                normal: normal,
                loopCount: face?.loops.count,
                edgeCount: edgeCount
            )
        case .edge(let edgeID):
            let edge = evaluatedDocument.brep.edges[edgeID]
            let curveInfo = edge.flatMap { edge in
                evaluatedDocument.brep.geometry.curves[edge.curveID].map(describeCurve)
            }
            let start = edge.flatMap { edge in
                evaluatedDocument.brep.vertices[edge.startVertexID].map { point($0.point) }
            }
            let end = edge.flatMap { edge in
                evaluatedDocument.brep.vertices[edge.endVertexID].map { point($0.point) }
            }
            let edgeParameterRange = edge?.trim.map {
                TopologySummaryResult.Entry.ParameterRange(
                    start: $0.startParameter,
                    end: $0.endParameter
                )
            }
            return TopologySummaryResult.Entry(
                subshapeID: identity,
                stableReference: stableReference,
                kind: .edge,
                referenceID: edgeID.description,
                sourceFeatureID: subshapeID.featureID.description,
                sceneNodeID: sceneNodeID,
                generatedRole: subshapeID.role,
                ordinal: subshapeID.ordinal,
                selectionComponentID: SelectionComponentID.generatedTopology(subshapeID).rawValue,
                curveKind: curveInfo?.kind,
                curveOrigin: curveInfo?.origin,
                curveDirection: curveInfo?.direction,
                curveCenter: curveInfo?.center,
                curveNormal: curveInfo?.normal,
                curveRadius: curveInfo?.radius,
                curveParameterXAxis: curveInfo?.parameterXAxis,
                curveParameterYAxis: curveInfo?.parameterYAxis,
                curveDegree: curveInfo?.degree,
                curveControlPointCount: curveInfo?.controlPointCount,
                curveIsRational: curveInfo?.isRational,
                edgeParameterRange: edgeParameterRange,
                lengthMeters: metricPolicy == .include
                    ? edge.flatMap { edgeLengthMeters($0, in: evaluatedDocument.brep) }
                    : nil,
                start: start,
                end: end,
                midpoint: edgeMidpoint(stableReference, in: evaluatedDocument)
            )
        case .vertex(let vertexID):
            let vertex = evaluatedDocument.brep.vertices[vertexID]
            return TopologySummaryResult.Entry(
                subshapeID: identity,
                stableReference: stableReference,
                kind: .vertex,
                referenceID: vertexID.description,
                sourceFeatureID: subshapeID.featureID.description,
                sceneNodeID: sceneNodeID,
                generatedRole: subshapeID.role,
                ordinal: subshapeID.ordinal,
                selectionComponentID: SelectionComponentID.generatedTopology(subshapeID).rawValue,
                start: vertex.map { point($0.point) }
            )
        }
    }

    private func point(_ point: Point3D) -> TopologySummaryResult.Entry.Point {
        TopologySummaryResult.Entry.Point(
            x: point.x,
            y: point.y,
            z: point.z
        )
    }

    private func point(_ vector: Vector3D) -> TopologySummaryResult.Entry.Point {
        TopologySummaryResult.Entry.Point(
            x: vector.x,
            y: vector.y,
            z: vector.z
        )
    }

    /// The face's area centroid, measured exactly by Swift-CAD.
    private func faceCenter(
        _ faceID: FaceID,
        _ face: Face,
        in model: BRepModel
    ) -> TopologySummaryResult.Entry.Point? {
        do {
            let centroid = try model.faceAreaMeasurement(of: faceID, tolerance: .standard).centroid
            return TopologySummaryResult.Entry.Point(x: centroid.x, y: centroid.y, z: centroid.z)
        } catch let error as KernelError where error.code == .unsupportedCapability {
            return boundaryVertexMean(face, in: model)
        } catch {
            return nil
        }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Swift-CAD measures the area centroid of planar,
    // cylindrical, conical, spherical and toroidal faces; on a B-spline or procedural support, or a
    // boundary it does not cover, the face center is this average of boundary vertices, not the
    // centroid. Production path: topology snapshot face centers used by Face
    // Center snapping, construction-plane and generated-face targets. Completion requires
    // Swift-CAD to measure every support and deleting this Rupa computation.
    private func boundaryVertexMean(
        _ face: Face,
        in model: BRepModel
    ) -> TopologySummaryResult.Entry.Point? {
        var vertexIDs: Set<VertexID> = []
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                continue
            }
            for orientedEdge in loop.edges {
                guard let edge = model.edges[orientedEdge.edgeID] else {
                    continue
                }
                vertexIDs.insert(edge.startVertexID)
                vertexIDs.insert(edge.endVertexID)
            }
        }
        let points = vertexIDs.compactMap { id in
            model.vertices[id]?.point
        }
        guard !points.isEmpty else {
            return nil
        }
        let sum = points.reduce(Vector3D.zero) { partial, point in
            partial + Vector3D(x: point.x, y: point.y, z: point.z)
        }
        let count = Double(points.count)
        return TopologySummaryResult.Entry.Point(
            x: sum.x / count,
            y: sum.y / count,
            z: sum.z / count
        )
    }

    /// The outward normal at the face's representative parameter, oriented by Swift-CAD.
    private func faceNormal(
        _ face: Face,
        reference: StableSubshapeReference?,
        in evaluatedDocument: EvaluatedDocument
    ) -> TopologySummaryResult.Entry.Point? {
        guard let reference,
              let surface = evaluatedDocument.brep.geometry.surfaces[face.surfaceID] else {
            return nil
        }
        do {
            guard let parameter = try representativeParameter(on: face, surface: surface, in: evaluatedDocument.brep) else {
                return nil
            }
            let frame = try SurfaceQueryEvaluator(tolerance: .standard).outwardFrame(
                at: SurfaceParameterReference(
                    surface: SurfaceReference(subshape: reference),
                    u: parameter.u,
                    v: parameter.v
                ),
                in: evaluatedDocument
            )
            return point(frame.outwardNormal)
        } catch {
            return nil
        }
    }

    private func representativeParameter(
        on face: Face,
        surface: Surface3D,
        in model: BRepModel
    ) throws -> SurfaceParameter? {
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else { continue }
            for orientedEdge in loop.edges {
                guard let edge = model.edges[orientedEdge.edgeID],
                      let vertex = model.vertices[edge.startVertexID] else {
                    continue
                }
                if let curve = orientedEdge.surfaceParameterCurve {
                    // Coedge curves follow the oriented use; retain the same
                    // geometric edge-start sample without an inverse search.
                    return try curve.parameter(
                        atNormalizedFraction: orientedEdge.orientation == .forward ? 0 : 1,
                        tolerance: .standard
                    )
                }
                let projection = try surface.parameterProjection(of: vertex.point, tolerance: .standard)
                return SurfaceParameter(u: projection.u, v: projection.v)
            }
        }
        return nil
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Swift-CAD measures the area of planar, cylindrical,
    // conical, spherical and toroidal faces, so the area of a face on a B-spline or procedural
    // support, or with a boundary it does not cover, is nil. Production path: topology
    // snapshot metrics consumed by drawing face-area annotations and inspectors. Completion
    // requires Swift-CAD to measure every support.
    private func faceAreaSquareMeters(
        _ faceID: FaceID,
        in model: BRepModel
    ) -> Double? {
        do {
            return try model.faceAreaMeasurement(of: faceID, tolerance: .standard).area
        } catch {
            return nil
        }
    }

    private func edgeLengthMeters(
        _ edge: Edge,
        in model: BRepModel
    ) -> Double? {
        guard let curve = model.geometry.curves[edge.curveID] else {
            return nil
        }
        do {
            try curve.validate(tolerance: .standard)
            let enclosure = try edgeLengthEvaluator.lengthEnclosure(
                of: edge,
                in: model,
                tolerance: .standard
            )
            return finitePositiveLength(enclosure.midpoint)
        } catch {
            return nil
        }
    }

    private func finitePositiveLength(_ length: Double) -> Double? {
        guard length.isFinite,
              length > ModelingTolerance.standard.distance else {
            return nil
        }
        return length
    }

    private func describeCurve(_ curve: Curve3D) -> CurveSummary {
        switch curve {
        case .line(let line):
            return CurveSummary(
                kind: "line",
                origin: point(line.origin),
                direction: point(line.direction)
            )
        case .circle(let circle):
            let basis = circleBasis(for: circle.normal)
            return CurveSummary(
                kind: "circle",
                center: point(circle.center),
                normal: point(circle.normal),
                radius: circle.radius,
                parameterXAxis: basis.map { point($0.xAxis) },
                parameterYAxis: basis.map { point($0.yAxis) }
            )
        case .bSpline(let curve):
            return CurveSummary(
                kind: "bSpline",
                degree: curve.degree,
                controlPointCount: curve.controlPointCount,
                isRational: curve.isRational
            )
        case .analytic(let analytic):
            switch analytic {
            case .line(let origin, let direction):
                return CurveSummary(
                    kind: "line",
                    origin: point(origin),
                    direction: point(direction)
                )
            case .circle(let center, let normal, let radius),
                 .arc(let center, let normal, let radius, _, _):
                let basis = circleBasis(for: normal)
                return CurveSummary(
                    kind: "circle",
                    center: point(center),
                    normal: point(normal),
                    radius: radius,
                    parameterXAxis: basis.map { point($0.xAxis) },
                    parameterYAxis: basis.map { point($0.yAxis) }
                )
            case .ellipse, .hyperbola, .parabola, .planeTorus:
                return CurveSummary(kind: "analytic")
            }
        case .implicit:
            return CurveSummary(kind: "implicit")
        case .surfaceLift:
            return CurveSummary(kind: "surfaceLift")
        case .certifiedIntersection:
            return CurveSummary(kind: "certifiedIntersection")
        case let .rigidImage(image):
            return transformedCurveSummary(
                describeCurve(image.source),
                by: image.transform
            )
        case .affineImage:
            return CurveSummary(kind: "affineImage")
        }
    }

    private func transformedCurveSummary(
        _ summary: CurveSummary,
        by transform: RigidTransform3D
    ) -> CurveSummary {
        CurveSummary(
            kind: summary.kind,
            origin: summary.origin.map { point(transform.applying(to: point3D($0))) },
            direction: summary.direction.map { point(transform.applying(to: vector3D($0))) },
            center: summary.center.map { point(transform.applying(to: point3D($0))) },
            normal: summary.normal.map {
                let orientation = transform.reversesOrientation ? -1.0 : 1.0
                return point(transform.applying(to: vector3D($0)) * orientation)
            },
            radius: summary.radius,
            parameterXAxis: summary.parameterXAxis.map {
                point(transform.applying(to: vector3D($0)))
            },
            parameterYAxis: summary.parameterYAxis.map {
                point(transform.applying(to: vector3D($0)))
            },
            degree: summary.degree,
            controlPointCount: summary.controlPointCount,
            isRational: summary.isRational
        )
    }

    private func point3D(
        _ point: TopologySummaryResult.Entry.Point
    ) -> Point3D {
        Point3D(x: point.x, y: point.y, z: point.z)
    }

    private func vector3D(
        _ point: TopologySummaryResult.Entry.Point
    ) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private func circleBasis(
        for normal: Vector3D
    ) -> (xAxis: Vector3D, yAxis: Vector3D)? {
        do {
            let normal = try normal.normalized(tolerance: ModelingTolerance.standard.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let xAxis = try helper.cross(normal).normalized(tolerance: ModelingTolerance.standard.distance)
            let yAxis = normal.cross(xAxis)
            return (xAxis, yAxis)
        } catch {
            return nil
        }
    }

    private func describeSurface(_ surface: Surface3D) -> SurfaceSummary {
        switch surface {
        case .plane(let plane):
            return SurfaceSummary(
                kind: "plane",
                origin: point(plane.origin),
                normal: point(plane.normal)
            )
        case .cylinder(let cylinder):
            return SurfaceSummary(
                kind: "cylinder",
                origin: point(cylinder.origin),
                axis: point(cylinder.axis),
                radius: cylinder.radius
            )
        case .bSpline(let surface):
            return SurfaceSummary(
                kind: "bSpline",
                uDegree: surface.uDegree,
                vDegree: surface.vDegree,
                uControlPointCount: surface.uControlPointCount,
                vControlPointCount: surface.vControlPointCount
            )
        case .analytic(let analytic):
            switch analytic {
            case .plane(let origin, let normal):
                return SurfaceSummary(
                    kind: "plane",
                    origin: point(origin),
                    normal: point(normal)
                )
            case .cylinder(let origin, let axis, let radius):
                return SurfaceSummary(
                    kind: "cylinder",
                    origin: point(origin),
                    axis: point(axis),
                    radius: radius
                )
            case .cone, .sphere, .torus:
                return SurfaceSummary(kind: "analytic")
            }
        case let .procedural(procedural):
            switch procedural {
            case .offset:
                return SurfaceSummary(kind: "offset")
            case .ruled:
                return SurfaceSummary(kind: "ruled")
            case .rollingBall:
                return SurfaceSummary(kind: "rollingBall")
            }
        }
    }
}
