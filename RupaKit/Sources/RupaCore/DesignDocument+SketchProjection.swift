import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createFaceKnife(
        name: String,
        target: SelectionTarget,
        loop: [Point3D],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Face Knife"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        guard case .face(let componentID) = target.component,
              let persistentNameString = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology face target."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        let sceneNode = resolvedTarget.sceneNode
        let targetFeatureID = resolvedTarget.featureID
        guard let targetFeature = cadDocument.designGraph.nodes[targetFeatureID],
              targetFeature.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body-producing target feature."
            )
        }

        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentNameString }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology face was not found in the current evaluation."
            )
        }
        guard entry.kind == .face,
              entry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target must reference a face on the selected body."
            )
        }

        let facePersistentName = try GeneratedTopologyPersistentNameParser().parse(
            persistentNameString,
            operationName: operationName
        )
        let faceKnife = FaceKnifeFeature(
            target: FaceKnifeTargetReference(featureID: targetFeatureID),
            facePersistentName: facePersistentName,
            loop: loop
        )
        try faceKnife.validate()

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .faceKnife(faceKnife),
            inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: nil,
                geometryRole: sceneNode.object?.geometryRole ?? .solid,
                properties: ObjectPropertySet(),
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        do {
            _ = try CADPipeline
                .modelingDefault(for: self, objectRegistry: objectRegistry)
                .evaluate(cadDocument)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) produced unsupported or invalid geometry: \(error)."
            )
        }
        didCommit = true
        return featureID
    }

    @discardableResult
    public mutating func projectSketchCurvesToConstructionPlane(
        targets: [SelectionTarget],
        plane explicitPlane: SketchPlane? = nil,
        name: String? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Alternative Duplicate"
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires at least one source curve target."
            )
        }

        let targetPlane = explicitPlane ?? activeConstructionPlane?.plane ?? .xy
        var topology: TopologySummaryResult?
        return try appendProjectedCurveSketch(
            targets: targets,
            targetPlane: targetPlane,
            operationName: operationName,
            name: name,
            defaultName: projectedSketchName(from:),
            objectRegistry: objectRegistry,
            topology: &topology
        )
    }

    @discardableResult
    public mutating func projectCurvesToGeneratedFace(
        targets: [SelectionTarget],
        face: SelectionTarget,
        name: String? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Project Curve Body"
        let evaluatedTopology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        var topology: TopologySummaryResult? = evaluatedTopology
        let targetPlane = try ConstructionPlaneTargetResolver().planarGeneratedFacePlane(
            alignedTo: face,
            topology: evaluatedTopology,
            operationName: operationName
        )
        return try appendProjectedCurveSketch(
            targets: targets,
            targetPlane: targetPlane,
            operationName: operationName,
            name: name,
            defaultName: projectedFaceProjectionName(from:),
            objectRegistry: objectRegistry,
            topology: &topology
        )
    }

    private mutating func appendProjectedCurveSketch(
        targets: [SelectionTarget],
        targetPlane: SketchPlane,
        operationName: String,
        name: String?,
        defaultName: ([String]) -> String,
        objectRegistry: ObjectTypeRegistry,
        topology: inout TopologySummaryResult?
    ) throws -> FeatureID {
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires at least one source curve target."
            )
        }
        let targetSystem = try SketchPlaneCoordinateSystem(plane: targetPlane)
        var projectedEntities: [SketchEntityID: SketchEntity] = [:]
        var sourceNames: [String] = []
        var seenTargets = Set<String>()
        for target in targets {
            let targetKey = "\(target.sceneNodeID.description):\(String(describing: target.component))"
            guard seenTargets.insert(targetKey).inserted else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) received the same source curve target more than once."
                )
            }
            let projected = try projectedSketchEntity(
                for: target,
                targetSystem: targetSystem,
                operationName: operationName,
                objectRegistry: objectRegistry,
                topology: &topology
            )
            let projectedEntity = projected.entity
            projectedEntities[SketchEntityID()] = projectedEntity
            sourceNames.append(projected.sourceName)
        }

        let projectedSketch = Sketch(
            plane: targetPlane,
            entities: projectedEntities
        )
        try projectedSketch.validate()
        try projectedSketch.validateExpressions(using: cadDocument.parameters)
        let outputName = try normalizedMetadataName(
            name ?? defaultName(sourceNames),
            owner: operationName
        )
        return try appendSketchFeature(
            name: outputName,
            sketch: projectedSketch,
            geometryRole: .curve,
            objectRegistry: objectRegistry
        )
    }

    private func projectedSketchName(from sourceNames: [String]) -> String {
        if sourceNames.count == 1,
           let sourceName = sourceNames.first {
            return "\(sourceName) Projection"
        }
        return "Projected Curves"
    }

    private func projectedFaceProjectionName(from sourceNames: [String]) -> String {
        if sourceNames.count == 1,
           let sourceName = sourceNames.first {
            return "\(sourceName) Face Projection"
        }
        return "Projected Face Curves"
    }

    @discardableResult
    public mutating func projectBodyOutlinesToConstructionPlane(
        targets: [SelectionTarget],
        plane explicitPlane: SketchPlane? = nil,
        name: String? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Project Outline"
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires at least one body target."
            )
        }

        let targetPlane = explicitPlane ?? activeConstructionPlane?.plane ?? .xy
        let targetSystem = try SketchPlaneCoordinateSystem(plane: targetPlane)
        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        var projectedEntities: [SketchEntityID: SketchEntity] = [:]
        var seenEntities = Set<String>()
        var sourceNames: [String] = []
        var seenTargets = Set<SceneNodeID>()
        for target in targets {
            guard target.component == .object else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) requires body object targets, not subobject targets."
                )
            }
            guard seenTargets.insert(target.sceneNodeID).inserted else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) received the same body target more than once."
                )
            }
            guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
                  sceneNode.reference?.kind == .body else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) target must reference a generated body scene node."
                )
            }
            sourceNames.append(sceneNode.name)
            let bodyEdges = topology.entries.filter {
                $0.kind == .edge &&
                    $0.sceneNodeID == target.sceneNodeID.description
            }
            guard bodyEdges.isEmpty == false else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(operationName) target body has no generated edge topology to outline."
                )
            }
            for edge in bodyEdges {
                guard let entity = try projectedOutlineSketchEntity(
                    edge,
                    to: targetSystem,
                    owner: operationName
                ) else {
                    continue
                }
                let key = try projectedSketchEntityKey(entity)
                if seenEntities.insert(key).inserted {
                    projectedEntities[SketchEntityID()] = entity
                }
            }
        }
        guard projectedEntities.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) found no non-collapsed outline curves on the target construction plane."
            )
        }
        let projectedSketch = Sketch(
            plane: targetPlane,
            entities: projectedEntities
        )
        try projectedSketch.validate()
        try projectedSketch.validateExpressions(using: cadDocument.parameters)
        let outputName = try normalizedMetadataName(
            name ?? projectedOutlineName(from: sourceNames),
            owner: operationName
        )
        return try appendSketchFeature(
            name: outputName,
            sketch: projectedSketch,
            geometryRole: .curve,
            objectRegistry: objectRegistry
        )
    }

    private func projectedOutlineName(from sourceNames: [String]) -> String {
        if sourceNames.count == 1,
           let sourceName = sourceNames.first {
            return "\(sourceName) Outline Projection"
        }
        return "Projected Outlines"
    }

    private func projectedSketchEntity(
        for target: SelectionTarget,
        targetSystem: SketchPlaneCoordinateSystem,
        operationName: String,
        objectRegistry: ObjectTypeRegistry,
        topology: inout TopologySummaryResult?
    ) throws -> (entity: SketchEntity, sourceName: String) {
        if case .sketchEntity = target.component {
            let selection = try editableSketchEntity(
                for: target,
                operationName: "\(operationName) source"
            )
            let sourceSystem = try SketchPlaneCoordinateSystem(plane: selection.sketch.plane)
            return (
                entity: try projectedSketchEntity(
                    selection.entity,
                    from: sourceSystem,
                    to: targetSystem,
                    owner: operationName
                ),
                sourceName: selection.feature.name ?? "Sketch Curve"
            )
        }
        if case .edge(let componentID) = target.component,
           componentID.generatedTopologyPersistentName != nil {
            return (
                entity: try projectedGeneratedEdgeSketchEntity(
                    for: target,
                    targetSystem: targetSystem,
                    operationName: operationName,
                    objectRegistry: objectRegistry,
                    topology: &topology
                ),
                sourceName: "Generated Edge"
            )
        }
        throw EditorError(
            code: .commandInvalid,
            message: "\(operationName) requires source sketch curve or generated edge targets."
        )
    }

    private func projectedSketchEntity(
        _ entity: SketchEntity,
        from sourceSystem: SketchPlaneCoordinateSystem,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity {
        switch entity {
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires curve entities, not source point entities."
            )
        case .line(let line):
            let start = try projectedSketchPoint(
                line.start,
                from: sourceSystem,
                to: targetSystem,
                owner: "\(owner) line start"
            )
            let end = try projectedSketchPoint(
                line.end,
                from: sourceSystem,
                to: targetSystem,
                owner: "\(owner) line end"
            )
            let startPoint = try resolvedProjectionPoint(start, owner: "\(owner) projected line start")
            let endPoint = try resolvedProjectionPoint(end, owner: "\(owner) projected line end")
            guard hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) > 1.0e-12 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) projected line collapsed on the target construction plane."
                )
            }
            return .line(SketchLine(start: start, end: end))
        case .circle(let circle):
            try validateCircularProjection(
                from: sourceSystem,
                to: targetSystem,
                owner: owner
            )
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius")
            return .circle(SketchCircle(
                center: try projectedSketchPoint(
                    circle.center,
                    from: sourceSystem,
                    to: targetSystem,
                    owner: "\(owner) circle center"
                ),
                radius: .length(radius, .meter)
            ))
        case .arc(let arc):
            try validateCircularProjection(
                from: sourceSystem,
                to: targetSystem,
                owner: owner
            )
            return .arc(try projectedSketchArc(
                arc,
                from: sourceSystem,
                to: targetSystem,
                owner: owner
            ))
        case .spline(let spline):
            return .spline(SketchSpline(
                controlPoints: try spline.controlPoints.enumerated().map { index, point in
                    try projectedSketchPoint(
                        point,
                        from: sourceSystem,
                        to: targetSystem,
                        owner: "\(owner) spline control point \(index)"
                    )
                }
            ))
        }
    }

    private func projectedOutlineSketchEntity(
        _ entry: TopologySummaryResult.Entry,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity? {
        switch entry.curveKind {
        case "line":
            return try projectedOutlineLineEdge(
                entry,
                to: targetSystem,
                owner: owner
            )
        case "circle":
            return try projectedGeneratedCircularEdge(
                entry,
                to: targetSystem,
                owner: owner
            )
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) currently supports outline projection for generated line and circular edges; B-spline or unknown edge outlines require exact trim-curve source support."
            )
        }
    }

    private func projectedOutlineLineEdge(
        _ entry: TopologySummaryResult.Entry,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity? {
        guard let start = entry.start,
              let end = entry.end else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) generated line edge has no resolved endpoints."
            )
        }
        let projectedStart = targetSystem.project(point3D(start)).point
        let projectedEnd = targetSystem.project(point3D(end)).point
        guard hypot(projectedEnd.x - projectedStart.x, projectedEnd.y - projectedStart.y) > 1.0e-12 else {
            return nil
        }
        return .line(SketchLine(
            start: sketchPoint(from: projectedStart),
            end: sketchPoint(from: projectedEnd)
        ))
    }

    private func projectedGeneratedEdgeSketchEntity(
        for target: SelectionTarget,
        targetSystem: SketchPlaneCoordinateSystem,
        operationName: String,
        objectRegistry: ObjectTypeRegistry,
        topology: inout TopologySummaryResult?
    ) throws -> SketchEntity {
        guard case .edge(let componentID) = target.component,
              let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated projection requires a generated edge target."
            )
        }
        if topology == nil {
            topology = try TopologySummaryService().summarize(
                document: self,
                objectRegistry: objectRegistry
            )
        }
        guard let topology else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated edge projection could not evaluate topology."
            )
        }
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated edge target was not found in the current evaluation."
            )
        }
        guard entry.kind == .edge,
              entry.sceneNodeID == target.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated edge target must reference an edge on the selected body."
            )
        }
        switch entry.curveKind {
        case "line":
            return try projectedGeneratedLineEdge(
                entry,
                to: targetSystem,
                owner: operationName
            )
        case "circle":
            return try projectedGeneratedCircularEdge(
                entry,
                to: targetSystem,
                owner: operationName
            )
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports generated line and circular edge targets; B-spline or unknown generated edge projection requires exact trim-curve source support."
            )
        }
    }

    private func projectedGeneratedLineEdge(
        _ entry: TopologySummaryResult.Entry,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity {
        guard let start = entry.start,
              let end = entry.end else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) generated line edge has no resolved endpoints."
            )
        }
        let projectedStart = targetSystem.project(point3D(start)).point
        let projectedEnd = targetSystem.project(point3D(end)).point
        guard hypot(projectedEnd.x - projectedStart.x, projectedEnd.y - projectedStart.y) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) projected generated edge collapsed on the target construction plane."
            )
        }
        return .line(SketchLine(
            start: sketchPoint(from: projectedStart),
            end: sketchPoint(from: projectedEnd)
        ))
    }

    private func projectedGeneratedCircularEdge(
        _ entry: TopologySummaryResult.Entry,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity {
        guard let center = entry.curveCenter,
              let normal = entry.curveNormal,
              let xAxis = entry.curveParameterXAxis,
              let yAxis = entry.curveParameterYAxis,
              let radius = entry.curveRadius,
              let range = entry.edgeParameterRange,
              radius.isFinite,
              radius > 1.0e-12,
              range.start.isFinite,
              range.end.isFinite else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) generated circular edge has incomplete curve parameters."
            )
        }
        let circularNormal = try vector3D(normal).normalized(tolerance: 1.0e-12)
        guard abs(abs(circularNormal.dot(targetSystem.normal)) - 1.0) <= 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) can project circular generated edges only onto a parallel construction plane until ellipse or exact conic projection sources exist."
            )
        }
        let projectedCenter = targetSystem.project(point3D(center)).point
        let span = range.end - range.start
        guard abs(span) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) generated circular edge has a collapsed trim range."
            )
        }
        if abs(abs(span) - Double.pi * 2.0) <= 1.0e-7 {
            return .circle(SketchCircle(
                center: sketchPoint(from: projectedCenter),
                radius: .length(radius, .meter)
            ))
        }
        let sourceStart = try circularEdgeWorldPoint(
            center: center,
            xAxis: xAxis,
            yAxis: yAxis,
            radius: radius,
            parameter: range.start,
            owner: owner
        )
        let sourceEnd = try circularEdgeWorldPoint(
            center: center,
            xAxis: xAxis,
            yAxis: yAxis,
            radius: radius,
            parameter: range.end,
            owner: owner
        )
        let sourceMid = try circularEdgeWorldPoint(
            center: center,
            xAxis: xAxis,
            yAxis: yAxis,
            radius: radius,
            parameter: range.start + span / 2.0,
            owner: owner
        )
        let projectedStart = targetSystem.project(sourceStart).point
        let projectedEnd = targetSystem.project(sourceEnd).point
        let projectedMid = targetSystem.project(sourceMid).point
        let startAngle = atan2(projectedStart.y - projectedCenter.y, projectedStart.x - projectedCenter.x)
        let endAngle = atan2(projectedEnd.y - projectedCenter.y, projectedEnd.x - projectedCenter.x)
        let directDistance = projectedArcMidpointDistance(
            center: projectedCenter,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            expected: projectedMid
        )
        let reversedDistance = projectedArcMidpointDistance(
            center: projectedCenter,
            radius: radius,
            startAngle: endAngle,
            endAngle: startAngle,
            expected: projectedMid
        )
        if reversedDistance < directDistance {
            return .arc(SketchArc(
                center: sketchPoint(from: projectedCenter),
                radius: .length(radius, .meter),
                startAngle: .angle(endAngle, .radian),
                endAngle: .angle(startAngle, .radian)
            ))
        }
        return .arc(SketchArc(
            center: sketchPoint(from: projectedCenter),
            radius: .length(radius, .meter),
            startAngle: .angle(startAngle, .radian),
            endAngle: .angle(endAngle, .radian)
        ))
    }

    private func validateCircularProjection(
        from sourceSystem: SketchPlaneCoordinateSystem,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws {
        guard sourceSystem.projectsParallel(to: targetSystem) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) can project circle and arc sources only onto a parallel construction plane until ellipse or exact conic projection sources exist."
            )
        }
    }

    private func projectedSketchArc(
        _ arc: SketchArc,
        from sourceSystem: SketchPlaneCoordinateSystem,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchArc {
        let resolvedCenter = try resolvedProjectionPoint(arc.center, owner: "\(owner) arc center")
        let sourceCenter = Point2D(x: resolvedCenter.x, y: resolvedCenter.y)
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start angle")
        let span = try normalizedPartialArcSpan(
            startAngle: startAngle,
            endAngle: try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end angle")
        )
        let endAngle = startAngle + span
        let sourceStart = Point2D(
            x: sourceCenter.x + cos(startAngle) * radius,
            y: sourceCenter.y + sin(startAngle) * radius
        )
        let sourceEnd = Point2D(
            x: sourceCenter.x + cos(endAngle) * radius,
            y: sourceCenter.y + sin(endAngle) * radius
        )
        let sourceMid = Point2D(
            x: sourceCenter.x + cos(startAngle + span / 2.0) * radius,
            y: sourceCenter.y + sin(startAngle + span / 2.0) * radius
        )
        let center = targetSystem.project(sourceSystem.point(from: sourceCenter)).point
        let projectedStart = targetSystem.project(sourceSystem.point(from: sourceStart)).point
        let projectedEnd = targetSystem.project(sourceSystem.point(from: sourceEnd)).point
        let projectedMid = targetSystem.project(sourceSystem.point(from: sourceMid)).point
        let targetStartAngle = atan2(projectedStart.y - center.y, projectedStart.x - center.x)
        let targetEndAngle = atan2(projectedEnd.y - center.y, projectedEnd.x - center.x)
        let directDistance = projectedArcMidpointDistance(
            center: center,
            radius: radius,
            startAngle: targetStartAngle,
            endAngle: targetEndAngle,
            expected: projectedMid
        )
        let reversedDistance = projectedArcMidpointDistance(
            center: center,
            radius: radius,
            startAngle: targetEndAngle,
            endAngle: targetStartAngle,
            expected: projectedMid
        )
        if reversedDistance < directDistance {
            return SketchArc(
                center: sketchPoint(from: center),
                radius: .length(radius, .meter),
                startAngle: .angle(targetEndAngle, .radian),
                endAngle: .angle(targetStartAngle, .radian)
            )
        }
        return SketchArc(
            center: sketchPoint(from: center),
            radius: .length(radius, .meter),
            startAngle: .angle(targetStartAngle, .radian),
            endAngle: .angle(targetEndAngle, .radian)
        )
    }

    private func projectedArcMidpointDistance(
        center: Point2D,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        expected: Point2D
    ) -> Double {
        let span = (endAngle - startAngle).truncatingRemainder(dividingBy: Double.pi * 2.0)
        let positiveSpan = span > 0.0 ? span : span + Double.pi * 2.0
        let midpointAngle = startAngle + positiveSpan / 2.0
        let midpoint = Point2D(
            x: center.x + cos(midpointAngle) * radius,
            y: center.y + sin(midpointAngle) * radius
        )
        return hypot(midpoint.x - expected.x, midpoint.y - expected.y)
    }

    private func projectedSketchPoint(
        _ point: SketchPoint,
        from sourceSystem: SketchPlaneCoordinateSystem,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchPoint {
        let sourcePoint = try resolvedProjectionPoint(point, owner: owner)
        let projected = targetSystem.project(
            sourceSystem.point(from: Point2D(x: sourcePoint.x, y: sourcePoint.y))
        ).point
        return sketchPoint(from: projected)
    }

    private func resolvedProjectionPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    private func sketchPoint(from point: Point2D) -> SketchPoint {
        SketchPoint(
            x: .length(point.x, .meter),
            y: .length(point.y, .meter)
        )
    }

    private func circularEdgeWorldPoint(
        center: TopologySummaryResult.Entry.Point,
        xAxis: TopologySummaryResult.Entry.Point,
        yAxis: TopologySummaryResult.Entry.Point,
        radius: Double,
        parameter: Double,
        owner: String
    ) throws -> Point3D {
        guard parameter.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) generated circular edge has a non-finite trim parameter."
            )
        }
        let cosine = cos(parameter)
        let sine = sin(parameter)
        return Point3D(
            x: center.x + (xAxis.x * cosine + yAxis.x * sine) * radius,
            y: center.y + (xAxis.y * cosine + yAxis.y * sine) * radius,
            z: center.z + (xAxis.z * cosine + yAxis.z * sine) * radius
        )
    }

    private func point3D(_ point: TopologySummaryResult.Entry.Point) -> Point3D {
        Point3D(x: point.x, y: point.y, z: point.z)
    }

    private func vector3D(_ point: TopologySummaryResult.Entry.Point) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private func projectedSketchEntityKey(_ entity: SketchEntity) throws -> String {
        switch entity {
        case .line(let line):
            let start = try resolvedProjectionPoint(line.start, owner: "Projected outline line start")
            let end = try resolvedProjectionPoint(line.end, owner: "Projected outline line end")
            let first = quantizedPointKey(Point2D(x: start.x, y: start.y))
            let second = quantizedPointKey(Point2D(x: end.x, y: end.y))
            let endpoints = [first, second].sorted()
            return "line:\(endpoints[0]):\(endpoints[1])"
        case .circle(let circle):
            let center = try resolvedProjectionPoint(circle.center, owner: "Projected outline circle center")
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "Projected outline circle radius")
            return "circle:\(quantizedPointKey(Point2D(x: center.x, y: center.y))):\(quantizedValueKey(radius))"
        case .arc(let arc):
            let center = try resolvedProjectionPoint(arc.center, owner: "Projected outline arc center")
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "Projected outline arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "Projected outline arc start angle")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "Projected outline arc end angle")
            let start = Point2D(
                x: center.x + cos(startAngle) * radius,
                y: center.y + sin(startAngle) * radius
            )
            let end = Point2D(
                x: center.x + cos(endAngle) * radius,
                y: center.y + sin(endAngle) * radius
            )
            let endpoints = [quantizedPointKey(start), quantizedPointKey(end)].sorted()
            return "arc:\(quantizedPointKey(Point2D(x: center.x, y: center.y))):\(quantizedValueKey(radius)):\(endpoints[0]):\(endpoints[1])"
        case .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Project Outline cannot deduplicate spline outline curves yet."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Project Outline cannot deduplicate point outline geometry."
            )
        }
    }

    private func quantizedPointKey(_ point: Point2D) -> String {
        "\(quantizedValueKey(point.x)):\(quantizedValueKey(point.y))"
    }

    private func quantizedValueKey(_ value: Double) -> String {
        let scale = 1.0e10
        return String(Int64((value * scale).rounded()))
    }
}
