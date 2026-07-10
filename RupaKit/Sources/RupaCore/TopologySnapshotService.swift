import Foundation
import SwiftCAD
import RupaCoreTypes

public struct TopologySnapshotService: Sendable {
    private static let bSplineLengthAbsoluteTolerance = ModelingTolerance.standard.distance * 0.1
    private static let bSplineLengthRelativeTolerance = 1.0e-6
    private static let maximumBSplineLengthIntegrationDepth = 12

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

    public func snapshot(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
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
            pipeline: pipelineOverride
        ).evaluatedDocument(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration,
            failurePrefix: "Document must evaluate successfully before topology snapshot"
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

        return TopologySnapshot(
            counts: TopologySummaryResult.Counts(
                bodyCount: evaluatedDocument.brep.bodies.count,
                faceCount: evaluatedDocument.brep.faces.count,
                edgeCount: evaluatedDocument.brep.edges.count,
                vertexCount: evaluatedDocument.brep.vertices.count
            ),
            entries: entries
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
                areaSquareMeters: face.flatMap {
                    faceAreaSquareMeters($0, in: evaluatedDocument.brep)
                },
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
                lengthMeters: edge.flatMap {
                    edgeLengthMeters($0, in: evaluatedDocument.brep)
                },
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

    private func faceAreaSquareMeters(
        _ face: Face,
        in model: BRepModel
    ) -> Double? {
        guard let surface = model.geometry.surfaces[face.surfaceID] else {
            return nil
        }
        switch surface {
        case .plane(let plane):
            return planarLineLoopFaceAreaSquareMeters(
                face,
                plane: plane,
                in: model
            )
        case .cylinder, .bSpline:
            return nil
        }
    }

    private func planarLineLoopFaceAreaSquareMeters(
        _ face: Face,
        plane: Plane3D,
        in model: BRepModel
    ) -> Double? {
        do {
            try plane.validate(tolerance: .standard)
            let normal = try plane.normal.normalized(tolerance: ModelingTolerance.standard.distance)
            var totalArea = 0.0
            for loopID in face.loops {
                guard let loop = model.loops[loopID],
                      loop.edges.isEmpty == false,
                      loop.edges.allSatisfy({ orientedEdge in
                          guard let edge = model.edges[orientedEdge.edgeID],
                                let curve = model.geometry.curves[edge.curveID] else {
                              return false
                          }
                          if case .line = curve {
                              return true
                          }
                          return false
                      }) else {
                    return nil
                }
                let points = try model.orderedPoints(for: loopID)
                guard points.count >= 3 else {
                    return nil
                }
                // Rebase to a loop vertex rather than plane.origin, which may sit on
                // a world axis far from the loop and leave the cross-products at
                // ~1e12. A loop vertex is always on the loop, so the relative
                // coordinates stay small; face area is translation invariant.
                let areaOrigin = points[0]
                var signedDoubleArea = 0.0
                for index in points.indices {
                    let current = points[index] - areaOrigin
                    let next = points[(index + 1) % points.count] - areaOrigin
                    signedDoubleArea += current.cross(next).dot(normal)
                }
                let loopArea = abs(signedDoubleArea) * 0.5
                guard loopArea.isFinite,
                      loopArea > ModelingTolerance.standard.distance * ModelingTolerance.standard.distance else {
                    return nil
                }
                switch loop.role {
                case .outer:
                    totalArea += loopArea
                case .inner:
                    totalArea -= loopArea
                }
            }
            guard totalArea.isFinite,
                  totalArea > ModelingTolerance.standard.distance * ModelingTolerance.standard.distance else {
                return nil
            }
            return totalArea
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
        switch curve {
        case .line(let line):
            if let trim = edge.trim {
                let length = abs(trim.endParameter - trim.startParameter) * line.direction.length
                return finitePositiveLength(length)
            }
            guard let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point else {
                return nil
            }
            return finitePositiveLength((end - start).length)
        case .circle(let circle):
            guard let trim = edge.trim else {
                return nil
            }
            let length = abs(trim.endParameter - trim.startParameter) * circle.radius
            return finitePositiveLength(length)
        case .bSpline(let curve):
            return bSplineEdgeLengthMeters(curve, trim: edge.trim)
        }
    }

    private func bSplineEdgeLengthMeters(
        _ curve: BSplineCurve3D,
        trim: CurveTrim?
    ) -> Double? {
        do {
            try curve.validate(tolerance: .standard)
            let bounds = try bSplineIntegrationBounds(for: curve, trim: trim)
            var length = 0.0
            var didIntegrateSpan = false
            for index in 1..<curve.knots.count {
                let spanStart = max(bounds.lower, curve.knots[index - 1])
                let spanEnd = min(bounds.upper, curve.knots[index])
                guard spanEnd - spanStart > ModelingTolerance.standard.distance else {
                    continue
                }
                length += try adaptiveBSplineSpeedIntegral(
                    curve,
                    lower: spanStart,
                    upper: spanEnd,
                    depth: 0
                )
                didIntegrateSpan = true
            }
            if didIntegrateSpan == false {
                length = try adaptiveBSplineSpeedIntegral(
                    curve,
                    lower: bounds.lower,
                    upper: bounds.upper,
                    depth: 0
                )
            }
            return finitePositiveLength(length)
        } catch {
            return nil
        }
    }

    private func bSplineIntegrationBounds(
        for curve: BSplineCurve3D,
        trim: CurveTrim?
    ) throws -> (lower: Double, upper: Double) {
        guard case let .closed(domainLower, domainUpper) = curve.domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        let rawStart = trim?.startParameter ?? domainLower
        let rawEnd = trim?.endParameter ?? domainUpper
        let lower = max(min(rawStart, rawEnd), min(domainLower, domainUpper))
        let upper = min(max(rawStart, rawEnd), max(domainLower, domainUpper))
        guard lower.isFinite,
              upper.isFinite,
              upper - lower > ModelingTolerance.standard.distance else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        return (lower, upper)
    }

    private func adaptiveBSplineSpeedIntegral(
        _ curve: BSplineCurve3D,
        lower: Double,
        upper: Double,
        depth: Int
    ) throws -> Double {
        let whole = try gaussLegendreFivePointSpeedIntegral(curve, lower: lower, upper: upper)
        let midpoint = (lower + upper) * 0.5
        let left = try gaussLegendreFivePointSpeedIntegral(curve, lower: lower, upper: midpoint)
        let right = try gaussLegendreFivePointSpeedIntegral(curve, lower: midpoint, upper: upper)
        let refined = left + right
        guard whole.isFinite,
              refined.isFinite else {
            throw GeometryError.invalidDistance(refined)
        }
        let tolerance = max(
            Self.bSplineLengthAbsoluteTolerance,
            abs(refined) * Self.bSplineLengthRelativeTolerance
        )
        guard depth < Self.maximumBSplineLengthIntegrationDepth,
              abs(refined - whole) > tolerance else {
            return refined
        }
        let refinedLeft = try adaptiveBSplineSpeedIntegral(
            curve,
            lower: lower,
            upper: midpoint,
            depth: depth + 1
        )
        let refinedRight = try adaptiveBSplineSpeedIntegral(
            curve,
            lower: midpoint,
            upper: upper,
            depth: depth + 1
        )
        return refinedLeft + refinedRight
    }

    private func gaussLegendreFivePointSpeedIntegral(
        _ curve: BSplineCurve3D,
        lower: Double,
        upper: Double
    ) throws -> Double {
        let halfSpan = (upper - lower) * 0.5
        guard halfSpan.isFinite,
              halfSpan > 0.0 else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        let center = (lower + upper) * 0.5
        let firstNode = 0.5384693101056831
        let secondNode = 0.9061798459386640
        let centerWeight = 0.5688888888888889
        let firstWeight = 0.47862867049936647
        let secondWeight = 0.23692688505618908
        let centerSpeed = try bSplineSpeed(curve, at: center)
        let firstNegativeSpeed = try bSplineSpeed(curve, at: center - halfSpan * firstNode)
        let firstPositiveSpeed = try bSplineSpeed(curve, at: center + halfSpan * firstNode)
        let secondNegativeSpeed = try bSplineSpeed(curve, at: center - halfSpan * secondNode)
        let secondPositiveSpeed = try bSplineSpeed(curve, at: center + halfSpan * secondNode)
        let weightedSpeed =
            centerWeight * centerSpeed
            + firstWeight * (firstNegativeSpeed + firstPositiveSpeed)
            + secondWeight * (secondNegativeSpeed + secondPositiveSpeed)
        return weightedSpeed * halfSpan
    }

    private func bSplineSpeed(
        _ curve: BSplineCurve3D,
        at parameter: Double
    ) throws -> Double {
        let speed = try curve
            .differentialGeometry(at: parameter, tolerance: .standard)
            .firstDerivative
            .length
        guard speed.isFinite else {
            throw GeometryError.invalidDistance(speed)
        }
        return speed
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
