import Foundation
import SwiftCAD
import RupaCoreTypes

public struct TopologySummaryService: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
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

    public func summarize(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> TopologySummaryResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before topology summary: \(String(describing: error))"
            )
        }

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return TopologySummaryResult(
                displayUnit: document.displayUnit,
                diagnostics: [
                    EditorDiagnostic(
                        severity: .info,
                        message: "Document source is valid. No generated topology."
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
            failurePrefix: "Document must evaluate successfully before topology summary"
        )

        let sceneNodeIDsByFeatureID = sceneNodeIDsByFeatureID(in: document)
        let entries = evaluatedDocument.generatedNames
            .map { name, reference in
                topologyEntry(
                    name: name,
                    reference: reference,
                    evaluatedDocument: evaluatedDocument,
                    sceneNodeIDsByFeatureID: sceneNodeIDsByFeatureID
                )
            }
            .sorted {
                if $0.kind.rawValue == $1.kind.rawValue {
                    return $0.persistentName < $1.persistentName
                }
                return $0.kind.rawValue < $1.kind.rawValue
            }

        return TopologySummaryResult(
            displayUnit: document.displayUnit,
            counts: TopologySummaryResult.Counts(
                bodyCount: evaluatedDocument.brep.bodies.count,
                faceCount: evaluatedDocument.brep.faces.count,
                edgeCount: evaluatedDocument.brep.edges.count,
                vertexCount: evaluatedDocument.brep.vertices.count
            ),
            entries: entries,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Topology summary completed with \(entries.count) generated persistent references."
                ),
            ]
        )
    }

    private func topologyEntry(
        name: PersistentName,
        reference: TopologyReference,
        evaluatedDocument: EvaluatedDocument,
        sceneNodeIDsByFeatureID: [FeatureID: SceneNodeID]
    ) -> TopologySummaryResult.Entry {
        let components = parsedComponents(from: name)
        let sceneNodeID = components.sourceFeatureID.flatMap { sceneNodeIDsByFeatureID[$0]?.description }
        switch reference {
        case .body(let bodyID):
            let body = evaluatedDocument.brep.bodies[bodyID]
            return TopologySummaryResult.Entry(
                persistentName: persistentNameString(name),
                kind: .body,
                referenceID: bodyID.description,
                sourceFeatureID: components.sourceFeatureID?.description,
                sceneNodeID: sceneNodeID,
                generatedRole: components.generatedRole,
                subshapeRole: components.subshapeRole,
                index: components.index,
                shellCount: body?.shellIDs.count
            )
        case .face(let faceID):
            let persistentName = persistentNameString(name)
            let face = evaluatedDocument.brep.faces[faceID]
            let edgeCount = face?.loops.reduce(0) { partial, loopID in
                partial + (evaluatedDocument.brep.loops[loopID]?.edges.count ?? 0)
            }
            let surfaceInfo = face.flatMap { face in
                evaluatedDocument.brep.geometry.surfaces[face.surfaceID].map(describeSurface)
            }
            let center = face.flatMap { faceCenter($0, in: evaluatedDocument.brep) }
            let normal = face.flatMap { faceNormal($0, in: evaluatedDocument.brep) }
            return TopologySummaryResult.Entry(
                persistentName: persistentName,
                kind: .face,
                referenceID: faceID.description,
                sourceFeatureID: components.sourceFeatureID?.description,
                sceneNodeID: sceneNodeID,
                generatedRole: components.generatedRole,
                subshapeRole: components.subshapeRole,
                index: components.index,
                selectionComponentID: SelectionComponentID.generatedTopology(persistentName).rawValue,
                surfaceKind: surfaceInfo?.kind,
                surfaceOrigin: surfaceInfo?.origin,
                surfaceNormal: surfaceInfo?.normal,
                surfaceAxis: surfaceInfo?.axis,
                surfaceRadius: surfaceInfo?.radius,
                surfaceUDegree: surfaceInfo?.uDegree,
                surfaceVDegree: surfaceInfo?.vDegree,
                surfaceUControlPointCount: surfaceInfo?.uControlPointCount,
                surfaceVControlPointCount: surfaceInfo?.vControlPointCount,
                center: center,
                normal: normal,
                loopCount: face?.loops.count,
                edgeCount: edgeCount
            )
        case .edge(let edgeID):
            let persistentName = persistentNameString(name)
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
                persistentName: persistentName,
                kind: .edge,
                referenceID: edgeID.description,
                sourceFeatureID: components.sourceFeatureID?.description,
                sceneNodeID: sceneNodeID,
                generatedRole: components.generatedRole,
                subshapeRole: components.subshapeRole,
                index: components.index,
                selectionComponentID: SelectionComponentID.generatedTopology(persistentName).rawValue,
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
                start: start,
                end: end
            )
        case .vertex(let vertexID):
            let persistentName = persistentNameString(name)
            let vertex = evaluatedDocument.brep.vertices[vertexID]
            return TopologySummaryResult.Entry(
                persistentName: persistentName,
                kind: .vertex,
                referenceID: vertexID.description,
                sourceFeatureID: components.sourceFeatureID?.description,
                sceneNodeID: sceneNodeID,
                generatedRole: components.generatedRole,
                subshapeRole: components.subshapeRole,
                index: components.index,
                selectionComponentID: SelectionComponentID.generatedTopology(persistentName).rawValue,
                start: vertex.map { point($0.point) }
            )
        }
    }

    private func sceneNodeIDsByFeatureID(in document: DesignDocument) -> [FeatureID: SceneNodeID] {
        var mapping: [FeatureID: SceneNodeID] = [:]
        for (sceneNodeID, sceneNode) in document.productMetadata.sceneNodes {
            guard let featureID = sceneNode.reference?.featureID else {
                continue
            }
            mapping[featureID] = sceneNodeID
        }
        return mapping
    }

    private func parsedComponents(
        from name: PersistentName
    ) -> (sourceFeatureID: FeatureID?, generatedRole: String?, subshapeRole: String?, index: Int?) {
        var sourceFeatureID: FeatureID?
        var generatedRole: String?
        var subshapeRole: String?
        var index: Int?
        for component in name.components {
            switch component {
            case .feature(let featureID):
                sourceFeatureID = featureID
            case .generated(let value):
                generatedRole = value
            case .subshape(let value):
                subshapeRole = value
            case .index(let value):
                index = value
            }
        }
        return (sourceFeatureID, generatedRole, subshapeRole, index)
    }

    private func persistentNameString(_ name: PersistentName) -> String {
        name.components.map { component in
            switch component {
            case .feature(let featureID):
                return "feature:\(featureID.description)"
            case .generated(let value):
                return "generated:\(value)"
            case .subshape(let value):
                return "subshape:\(value)"
            case .index(let index):
                return "index:\(index)"
            }
        }
        .joined(separator: "/")
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

    private func faceCenter(
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

    private func faceNormal(
        _ face: Face,
        in model: BRepModel
    ) -> TopologySummaryResult.Entry.Point? {
        guard let surface = model.geometry.surfaces[face.surfaceID] else {
            return nil
        }
        switch surface {
        case .plane(let plane):
            let normal = face.orientation == .forward ? plane.normal : -plane.normal
            return point(normal)
        case .cylinder(let cylinder):
            guard let center = faceCenter(face, in: model) else {
                return nil
            }
            let offset = Vector3D(
                x: center.x - cylinder.origin.x,
                y: center.y - cylinder.origin.y,
                z: center.z - cylinder.origin.z
            )
            do {
                let axis = try cylinder.axis.normalized(tolerance: ModelingTolerance.standard.distance)
                let radial = offset - axis * offset.dot(axis)
                let normal = try radial.normalized(tolerance: ModelingTolerance.standard.distance)
                return point(face.orientation == .forward ? normal : -normal)
            } catch {
                return nil
            }
        case .bSpline(let surface):
            do {
                let normal = try surface.normal(u: 0.5, v: 0.5)
                return point(face.orientation == .forward ? normal : -normal)
            } catch {
                return nil
            }
        }
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
        }
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
        }
    }
}
