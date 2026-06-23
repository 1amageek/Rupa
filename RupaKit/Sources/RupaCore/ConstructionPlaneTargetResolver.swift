import Foundation
import SwiftCAD

public struct ConstructionPlaneTargetResolver: Sendable {
    private struct PlaneReference: Sendable {
        var origin: Point3D
        var normal: Vector3D
    }

    private struct EdgeReference: Sendable {
        var center: Point3D
        var direction: Vector3D
    }

    public init() {}

    public func plane(
        alignedTo target: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchPlane {
        switch target.component {
        case .face:
            return try facePlane(
                alignedTo: target,
                in: document,
                objectRegistry: objectRegistry
            )
        case .region(let componentID):
            return try regionPlane(
                componentID: componentID,
                targetSceneNodeID: target.sceneNodeID,
                in: document
            )
        case .object, .edge, .vertex, .sketchEntity:
            throw EditorError(
                code: .commandInvalid,
                message: "Construction plane target must be a generated face or source sketch region."
            )
        }
    }

    public func plane(
        from targets: [SelectionTarget],
        in document: DesignDocument,
        viewNormal: Vector3D? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchPlane {
        let uniqueTargets = uniqueTargets(targets)
        guard uniqueTargets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Construction plane creation requires at least one selection target."
            )
        }
        if uniqueTargets.count == 1, let target = uniqueTargets.first {
            return try plane(
                alignedTo: target,
                in: document,
                objectRegistry: objectRegistry
            )
        }

        let topology = try TopologySummaryService().summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        let pointTargets = uniqueTargets.filter(isPointTarget)
        if pointTargets.count == uniqueTargets.count {
            let points = try pointTargets.map { target in
                try point(
                    for: target,
                    in: document,
                    topology: topology
                )
            }
            return try pointPlane(from: points, viewNormal: viewNormal)
        }
        let faceTargets = uniqueTargets.filter { target in
            if case .face = target.component {
                return true
            }
            return false
        }
        let edgeTargets = uniqueTargets.filter { target in
            if case .edge = target.component {
                return true
            }
            return false
        }
        if uniqueTargets.count == 2,
           faceTargets.count == 1,
           edgeTargets.count == 1,
           let faceTarget = faceTargets.first,
           let edgeTarget = edgeTargets.first {
            return try perpendicularPlane(
                faceTarget: faceTarget,
                edgeTarget: edgeTarget,
                topology: topology
            )
        }

        let planeReferences = try uniqueTargets.map { target in
            try planeReference(
                alignedTo: target,
                in: document,
                topology: topology
            )
        }
        return try midplane(from: planeReferences)
    }

    private func isPointTarget(_ target: SelectionTarget) -> Bool {
        switch target.component {
        case .vertex, .sketchEntity:
            return true
        case .object, .face, .edge, .region:
            return false
        }
    }

    private func facePlane(
        alignedTo target: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> SketchPlane {
        let topology = try TopologySummaryService().summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        let reference = try faceReference(alignedTo: target, topology: topology)
        return try plane(
            origin: reference.origin,
            normal: reference.normal,
            operationName: "Face-aligned construction plane"
        )
    }

    private func faceReference(
        alignedTo target: SelectionTarget,
        topology: TopologySummaryResult
    ) throws -> PlaneReference {
        guard case .face = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Face-aligned construction plane requires a face target."
            )
        }
        guard let entry = topology.entries.first(where: { $0.selectionTarget() == target }),
              entry.kind == .face else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane face target could not be resolved from generated topology."
            )
        }
        guard let center = entry.center else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane face target has no resolved center."
            )
        }
        guard let normal = entry.normal else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane face target has no resolved normal."
            )
        }
        let normalVector = Vector3D(x: normal.x, y: normal.y, z: normal.z)
        let unitNormal = try normalVector.normalized(tolerance: 1.0e-12)
        return PlaneReference(
            origin: Point3D(x: center.x, y: center.y, z: center.z),
            normal: unitNormal
        )
    }

    private func edgeReference(
        for target: SelectionTarget,
        topology: TopologySummaryResult
    ) throws -> EdgeReference {
        guard case .edge = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Perpendicular construction plane requires an edge target."
            )
        }
        guard let entry = topology.entries.first(where: { $0.selectionTarget() == target }),
              entry.kind == .edge else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane edge target could not be resolved from generated topology."
            )
        }
        guard let start = entry.start,
              let end = entry.end else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane edge target has no resolved endpoints."
            )
        }
        let startPoint = Point3D(x: start.x, y: start.y, z: start.z)
        let endPoint = Point3D(x: end.x, y: end.y, z: end.z)
        let direction = try (endPoint - startPoint).normalized(tolerance: 1.0e-12)
        return EdgeReference(
            center: Point3D(
                x: (startPoint.x + endPoint.x) / 2.0,
                y: (startPoint.y + endPoint.y) / 2.0,
                z: (startPoint.z + endPoint.z) / 2.0
            ),
            direction: direction
        )
    }

    private func perpendicularPlane(
        faceTarget: SelectionTarget,
        edgeTarget: SelectionTarget,
        topology: TopologySummaryResult
    ) throws -> SketchPlane {
        let face = try faceReference(alignedTo: faceTarget, topology: topology)
        let edge = try edgeReference(for: edgeTarget, topology: topology)
        let normal = try edge.direction.cross(face.normal).normalized(tolerance: 1.0e-12)
        return try plane(
            origin: edge.center,
            normal: normal,
            operationName: "Face-edge perpendicular construction plane"
        )
    }

    private func point(
        for target: SelectionTarget,
        in document: DesignDocument,
        topology: TopologySummaryResult
    ) throws -> Point3D {
        switch target.component {
        case .vertex:
            return try generatedVertexPoint(for: target, topology: topology)
        case .sketchEntity(let componentID):
            return try sourcePoint(
                componentID: componentID,
                targetSceneNodeID: target.sceneNodeID,
                in: document
            )
        case .object, .face, .edge, .region:
            throw EditorError(
                code: .commandInvalid,
                message: "Point-based construction plane requires generated vertex or source point targets."
            )
        }
    }

    private func generatedVertexPoint(
        for target: SelectionTarget,
        topology: TopologySummaryResult
    ) throws -> Point3D {
        guard case .vertex = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Point-based construction plane requires a vertex target."
            )
        }
        guard let entry = topology.entries.first(where: { $0.selectionTarget() == target }),
              entry.kind == .vertex else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane vertex target could not be resolved from generated topology."
            )
        }
        guard let point = entry.start else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane vertex target has no resolved point."
            )
        }
        return Point3D(x: point.x, y: point.y, z: point.z)
    }

    private func sourcePoint(
        componentID: SelectionComponentID,
        targetSceneNodeID: SceneNodeID,
        in document: DesignDocument
    ) throws -> Point3D {
        if let reference = componentID.sketchPointReference {
            return try sourceSketchPoint(
                featureID: reference.featureID,
                reference: reference.reference,
                targetSceneNodeID: targetSceneNodeID,
                in: document,
                owner: "Construction plane sketch point"
            )
        }
        guard let reference = componentID.sketchEntityReference else {
            throw EditorError(
                code: .commandInvalid,
                message: "Point-based construction plane source target must resolve to a sketch point reference."
            )
        }
        return try sourceSketchPoint(
            featureID: reference.featureID,
            reference: .entity(reference.entityID),
            targetSceneNodeID: targetSceneNodeID,
            in: document,
            owner: "Construction plane source point"
        )
    }

    private func sourceSketchPoint(
        featureID: FeatureID,
        reference: SketchReference,
        targetSceneNodeID: SceneNodeID,
        in document: DesignDocument,
        owner: String
    ) throws -> Point3D {
        if let sceneNode = document.productMetadata.sceneNodes[targetSceneNodeID],
           sceneNode.reference?.featureID != featureID {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Point-based construction plane sketch point does not match its scene node source."
            )
        }
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case .sketch(let sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Point-based construction plane sketch source could not be resolved."
            )
        }
        let point2D = try resolvedSketchPoint(
            reference,
            in: sketch,
            owner: owner,
            document: document
        )
        let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketch.plane)
        return coordinateSystem.point(from: point2D)
    }

    private func resolvedSketchPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String,
        document: DesignDocument
    ) throws -> Point2D {
        switch reference {
        case .entity(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .point(let point) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(point, owner: owner, document: document)
        case .lineStart(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .line(let line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(line.start, owner: owner, document: document)
        case .lineEnd(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .line(let line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(line.end, owner: owner, document: document)
        case .circleCenter(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .circle(let circle) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(circle.center, owner: owner, document: document)
        case .arcCenter(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .arc(let arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(arc.center, owner: owner, document: document)
        case .arcStart(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .arc(let arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(
                arc,
                angle: arc.startAngle,
                owner: owner,
                document: document
            )
        case .arcEnd(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .arc(let arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(
                arc,
                angle: arc.endAngle,
                owner: owner,
                document: document
            )
        case .splineControlPoint(let entityID, let index):
            guard let entity = sketch.entities[entityID],
                  case .spline(let spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedSketchPoint(
                spline.controlPoints[index],
                owner: owner,
                document: document
            )
        case .circleRadius, .arcRadius:
            throw invalidSketchPointReference(owner)
        }
    }

    private func resolvedSketchPoint(
        _ point: SketchPoint,
        owner: String,
        document: DesignDocument
    ) throws -> Point2D {
        Point2D(
            x: try resolvedLengthValue(point.x, owner: "\(owner) x", in: document),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y", in: document)
        )
    }

    private func pointOnArc(
        _ arc: SketchArc,
        angle: CADExpression,
        owner: String,
        document: DesignDocument
    ) throws -> Point2D {
        let center = try resolvedSketchPoint(arc.center, owner: owner, document: document)
        let radius = try resolvedPositiveLengthValue(
            arc.radius,
            owner: "\(owner) radius",
            in: document
        )
        let resolvedAngle = try resolvedAngleValue(
            angle,
            owner: "\(owner) angle",
            in: document
        )
        return Point2D(
            x: center.x + cos(resolvedAngle) * radius,
            y: center.y + sin(resolvedAngle) * radius
        )
    }

    private func invalidSketchPointReference(_ owner: String) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "\(owner) must resolve to a source point, curve endpoint, curve center, or spline control point."
        )
    }

    private func pointPlane(
        from points: [Point3D],
        viewNormal: Vector3D?
    ) throws -> SketchPlane {
        guard points.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Point-based construction plane requires at least two point targets."
            )
        }
        if points.count == 2 {
            return try twoPointPlane(from: points, viewNormal: viewNormal)
        }
        let normal = try nonCollinearNormal(from: points)
        let origin = points.count == 3 ? points[0] : averagePoint(points)
        return try plane(
            origin: origin,
            normal: normal,
            operationName: "Point-based construction plane"
        )
    }

    private func twoPointPlane(
        from points: [Point3D],
        viewNormal: Vector3D?
    ) throws -> SketchPlane {
        guard let viewNormal else {
            throw EditorError(
                code: .commandInvalid,
                message: "Two-point construction plane requires an explicit view normal."
            )
        }
        let direction = try (points[1] - points[0]).normalized(tolerance: 1.0e-12)
        let unitViewNormal = try viewNormal.normalized(tolerance: 1.0e-12)
        let projectedNormal = unitViewNormal - direction * unitViewNormal.dot(direction)
        let normal = try projectedNormal.normalized(tolerance: 1.0e-12)
        return try plane(
            origin: averagePoint(points),
            normal: normal,
            operationName: "Two-point construction plane"
        )
    }

    private func nonCollinearNormal(from points: [Point3D]) throws -> Vector3D {
        for firstIndex in points.indices {
            for secondIndex in points.indices where secondIndex != firstIndex {
                for thirdIndex in points.indices where thirdIndex != firstIndex && thirdIndex != secondIndex {
                    let firstEdge = points[secondIndex] - points[firstIndex]
                    let secondEdge = points[thirdIndex] - points[firstIndex]
                    do {
                        return try firstEdge.cross(secondEdge).normalized(tolerance: 1.0e-12)
                    } catch {
                        continue
                    }
                }
            }
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Point-based construction plane requires at least three non-collinear points, or two points with a view normal."
        )
    }

    private func averagePoint(_ points: [Point3D]) -> Point3D {
        let sum = points.reduce(Vector3D.zero) { partial, point in
            partial + Vector3D(x: point.x, y: point.y, z: point.z)
        }
        let count = Double(points.count)
        return Point3D(
            x: sum.x / count,
            y: sum.y / count,
            z: sum.z / count
        )
    }

    private func resolvedLengthValue(
        _ expression: CADExpression,
        owner: String,
        in document: DesignDocument
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length quantity."
            )
        }
        return quantity.value
    }

    private func resolvedPositiveLengthValue(
        _ expression: CADExpression,
        owner: String,
        in document: DesignDocument
    ) throws -> Double {
        let value = try resolvedLengthValue(expression, owner: owner, in: document)
        guard value > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be greater than zero."
            )
        }
        return value
    }

    private func resolvedAngleValue(
        _ expression: CADExpression,
        owner: String,
        in document: DesignDocument
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to an angle quantity."
            )
        }
        return quantity.value
    }

    private func regionPlane(
        componentID: SelectionComponentID,
        targetSceneNodeID: SceneNodeID,
        in document: DesignDocument
    ) throws -> SketchPlane {
        guard let reference = componentID.profileRegionReference else {
            throw EditorError(
                code: .commandInvalid,
                message: "Region-aligned construction plane requires a source profile region target."
            )
        }
        if let sceneNode = document.productMetadata.sceneNodes[targetSceneNodeID],
           sceneNode.reference?.featureID != reference.featureID {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Region-aligned construction plane target does not match its scene node source."
            )
        }
        guard let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Region-aligned construction plane source sketch could not be resolved."
            )
        }
        let resolvedParameters = try ParameterResolver().resolve(document.cadDocument.parameters)
        let profiles = try SketchProfileExtractor().extractProfiles(
            from: sketch,
            sourceFeatureID: reference.featureID,
            parameters: resolvedParameters
        )
        guard profiles.indices.contains(reference.profileIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Region-aligned construction plane source region no longer exists."
            )
        }
        let profile = profiles[reference.profileIndex]
        guard let summary = ProfileRegionGeometry.summary(for: profile) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Region-aligned construction plane requires a non-degenerate profile region."
            )
        }
        let coordinateSystem = try SketchPlaneCoordinateSystem(plane: profile.plane)
        let origin = coordinateSystem.point(from: summary.center)
        return try plane(
            origin: origin,
            normal: coordinateSystem.normal,
            operationName: "Region-aligned construction plane"
        )
    }

    private func planeReference(
        alignedTo target: SelectionTarget,
        in document: DesignDocument,
        topology: TopologySummaryResult
    ) throws -> PlaneReference {
        switch target.component {
        case .face:
            return try faceReference(alignedTo: target, topology: topology)
        case .region(let componentID):
            return try regionReference(
                componentID: componentID,
                targetSceneNodeID: target.sceneNodeID,
                in: document
            )
        case .object, .edge, .vertex, .sketchEntity:
            throw EditorError(
                code: .commandInvalid,
                message: "Midplane construction requires only face or region targets."
            )
        }
    }

    private func regionReference(
        componentID: SelectionComponentID,
        targetSceneNodeID: SceneNodeID,
        in document: DesignDocument
    ) throws -> PlaneReference {
        guard let reference = componentID.profileRegionReference else {
            throw EditorError(
                code: .commandInvalid,
                message: "Region-aligned construction plane requires a source profile region target."
            )
        }
        if let sceneNode = document.productMetadata.sceneNodes[targetSceneNodeID],
           sceneNode.reference?.featureID != reference.featureID {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Region-aligned construction plane target does not match its scene node source."
            )
        }
        guard let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case .sketch(let sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Region-aligned construction plane source sketch could not be resolved."
            )
        }
        let resolvedParameters = try ParameterResolver().resolve(document.cadDocument.parameters)
        let profiles = try SketchProfileExtractor().extractProfiles(
            from: sketch,
            sourceFeatureID: reference.featureID,
            parameters: resolvedParameters
        )
        guard profiles.indices.contains(reference.profileIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Region-aligned construction plane source region no longer exists."
            )
        }
        let profile = profiles[reference.profileIndex]
        guard let summary = ProfileRegionGeometry.summary(for: profile) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Region-aligned construction plane requires a non-degenerate profile region."
            )
        }
        let coordinateSystem = try SketchPlaneCoordinateSystem(plane: profile.plane)
        return PlaneReference(
            origin: coordinateSystem.point(from: summary.center),
            normal: coordinateSystem.normal
        )
    }

    private func midplane(from references: [PlaneReference]) throws -> SketchPlane {
        guard references.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Midplane construction requires at least two face or region targets."
            )
        }
        let baseNormal = references[0].normal
        for reference in references.dropFirst() {
            guard abs(abs(baseNormal.dot(reference.normal)) - 1.0) <= 1.0e-8 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Midplane construction requires parallel face or region targets."
                )
            }
        }
        let normalSpan = projectionSpan(of: references, along: baseNormal)
        guard normalSpan > 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Midplane construction requires opposing face or region targets separated along the shared normal."
            )
        }
        let originSum = references.reduce(Vector3D.zero) { partial, reference in
            partial + Vector3D(
                x: reference.origin.x,
                y: reference.origin.y,
                z: reference.origin.z
            )
        }
        let count = Double(references.count)
        return try plane(
            origin: Point3D(
                x: originSum.x / count,
                y: originSum.y / count,
                z: originSum.z / count
            ),
            normal: baseNormal,
            operationName: "Midplane construction plane"
        )
    }

    private func uniqueTargets(_ targets: [SelectionTarget]) -> [SelectionTarget] {
        var uniqueTargets: [SelectionTarget] = []
        var seenTargets: Set<SelectionTarget> = []
        for target in targets where !seenTargets.contains(target) {
            uniqueTargets.append(target)
            seenTargets.insert(target)
        }
        return uniqueTargets
    }

    private func projectionSpan(
        of references: [PlaneReference],
        along normal: Vector3D
    ) -> Double {
        let projections = references.map { reference in
            Vector3D(
                x: reference.origin.x,
                y: reference.origin.y,
                z: reference.origin.z
            ).dot(normal)
        }
        guard let minimum = projections.min(),
              let maximum = projections.max() else {
            return 0.0
        }
        return maximum - minimum
    }

    private func plane(
        origin: Point3D,
        normal: Vector3D,
        operationName: String
    ) throws -> SketchPlane {
        let unitNormal = try normal.normalized(tolerance: 1.0e-12)
        let plane = Plane3D(
            origin: origin,
            normal: unitNormal
        )
        do {
            try plane.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) resolved an invalid plane."
            )
        }
        return .plane(plane)
    }
}
