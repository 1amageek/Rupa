import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func offsetCurve(
        target: SelectionTarget,
        distance: CADExpression,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        if options.mode == .slot {
            let featureID = try createSlotFromOffsetCurve(
                target: target,
                width: distance,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return [featureID]
        }
        let distanceMeters = try resolvedLengthValue(distance, owner: "Curve offset distance")
        guard abs(distanceMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Curve offset distance must not be zero."
            )
        }
        if options.supportTarget != nil {
            guard case .edge = target.component else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve offset support target is only valid for generated edge Offset Edge dispatch."
                )
            }
        }

        switch target.component {
        case .sketchEntity:
            let selection = try editableSketchEntity(for: target, operationName: "Curve offset")
            if let vertexHandle {
                try validateOffsetCurveVertexOptions(options)
                try offsetSketchVertex(
                    target: target,
                    handle: vertexHandle,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
                return [selection.featureID]
            }
            let name = "\(selection.feature.name ?? "Sketch Curve") Offset"
            switch selection.entity {
            case .line(let line):
                let shiftedLine = try offsetLine(
                    line,
                    distance: distance,
                    owner: "Curve offset"
                )
                if options.isSymmetric {
                    let mirroredLine = try offsetLine(
                        line,
                        distance: negatedExpression(distance),
                        owner: "Curve offset"
                    )
                    let firstID = try createLineSketch(
                        name: "\(name) Positive",
                        plane: selection.sketch.plane,
                        start: shiftedLine.start,
                        end: shiftedLine.end,
                        objectRegistry: objectRegistry
                    )
                    let secondID = try createLineSketch(
                        name: "\(name) Negative",
                        plane: selection.sketch.plane,
                        start: mirroredLine.start,
                        end: mirroredLine.end,
                        objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createLineSketch(
                    name: name,
                    plane: selection.sketch.plane,
                    start: shiftedLine.start,
                    end: shiftedLine.end,
                    objectRegistry: objectRegistry
                )
                return [featureID]
            case .circle(let circle):
                let offsetRadius = try offsetRadiusExpression(
                    circle.radius,
                    distance: distance,
                    resolvedDistance: distanceMeters,
                    owner: "Curve offset circle"
                )
                if options.isSymmetric {
                    let mirroredRadius = try offsetRadiusExpression(
                        circle.radius,
                        distance: negatedExpression(distance),
                        resolvedDistance: -distanceMeters,
                        owner: "Curve offset circle"
                    )
                    let firstID = try createCircleSketch(
                        name: "\(name) Positive",
                        plane: selection.sketch.plane,
                        center: circle.center,
                        radius: offsetRadius,
                        objectRegistry: objectRegistry
                    )
                    let secondID = try createCircleSketch(
                        name: "\(name) Negative",
                        plane: selection.sketch.plane,
                        center: circle.center,
                        radius: mirroredRadius,
                        objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createCircleSketch(
                    name: name,
                    plane: selection.sketch.plane,
                    center: circle.center,
                    radius: offsetRadius,
                    objectRegistry: objectRegistry
                )
                return [featureID]
            case .arc(let arc):
                let offsetRadius = try offsetRadiusExpression(
                    arc.radius,
                    distance: distance,
                    resolvedDistance: distanceMeters,
                    owner: "Curve offset arc"
                )
                if options.isSymmetric {
                    let mirroredRadius = try offsetRadiusExpression(
                        arc.radius,
                        distance: negatedExpression(distance),
                        resolvedDistance: -distanceMeters,
                        owner: "Curve offset arc"
                    )
                    let firstID = try createArcSketch(
                        name: "\(name) Positive",
                        plane: selection.sketch.plane,
                        center: arc.center,
                        radius: offsetRadius,
                        startAngle: arc.startAngle,
                        endAngle: arc.endAngle,
                        objectRegistry: objectRegistry
                    )
                    let secondID = try createArcSketch(
                        name: "\(name) Negative",
                        plane: selection.sketch.plane,
                        center: arc.center,
                        radius: mirroredRadius,
                        startAngle: arc.startAngle,
                        endAngle: arc.endAngle,
                        objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createArcSketch(
                    name: name,
                    plane: selection.sketch.plane,
                    center: arc.center,
                    radius: offsetRadius,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle,
                    objectRegistry: objectRegistry
                )
                return [featureID]
            case .point:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve offset source point entities do not identify the adjacent curve sides required by Offset Vertex. Select a source line or arc endpoint with a vertex handle."
                )
            case .spline:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Offset Planar Curve currently supports source line, circle, and arc sketch targets; spline offsets require joined curve offset support."
                )
            }
        case .region:
            let featureIDs = try offsetProfileRegion(
                target: target,
                distanceMeters: distanceMeters,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return featureIDs
        case .face:
            let featureID = try createFaceLoopOffsetFromOffsetCurve(
                target: target,
                distance: distance,
                distanceMeters: distanceMeters,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return [featureID]
        case .edge:
            let featureID = try createEdgeOffsetFromOffsetCurve(
                target: target,
                distance: distance,
                distanceMeters: distanceMeters,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return [featureID]
        case .vertex:
            guard vertexHandle == nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Generated vertex Offset Vertex dispatch uses the selected generated vertex target and does not accept an additional sketch vertex handle."
                )
            }
            try validateOffsetCurveVertexOptions(options)
            let resolvedTarget = try generatedSketchVertexOffsetTarget(
                for: target,
                objectRegistry: objectRegistry
            )
            try offsetSketchVertex(
                target: resolvedTarget.target,
                handle: resolvedTarget.handle,
                distance: distance,
                objectRegistry: objectRegistry
            )
            return [resolvedTarget.featureID]
        case .object, .constructionPlane:
            throw EditorError(
                code: .referenceUnresolved,
                message: "Curve offset requires a selected curve, region, vertex, face loop, or edge target."
            )
        }
    }

    @discardableResult
    private mutating func createFaceLoopOffsetFromOffsetCurve(
        target: SelectionTarget,
        distance: CADExpression,
        distanceMeters: Double,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        let operationName = "Offset Face Loop"
        guard vertexHandle == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) uses the selected generated face target and does not accept a sketch vertex handle."
            )
        }
        guard options.isSymmetric == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports a single inward distance; symmetric lock-distance face-loop offsets are not implemented."
            )
        }
        guard distanceMeters > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports a positive inward distance."
            )
        }
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

        let topology = try TopologySnapshotService().snapshot(
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
        let featureID = FeatureID()
        let featureName = "\(sceneNode.name) Face Loop Offset"
        let feature = FeatureNode(
            id: featureID,
            name: featureName,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: targetFeatureID),
                    facePersistentName: facePersistentName,
                    distance: distance,
                    gapFill: options.gapFill.faceLoopOffsetGapFill
                )
            ),
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
            name: featureName,
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
        didCommit = true
        return featureID
    }

    @discardableResult
    private mutating func createEdgeOffsetFromOffsetCurve(
        target: SelectionTarget,
        distance: CADExpression,
        distanceMeters: Double,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        let operationName = "Offset Edge"
        guard vertexHandle == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) uses the selected generated edge target and does not accept a sketch vertex handle."
            )
        }
        guard distanceMeters > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports a positive inward distance."
            )
        }
        guard case .edge(let edgeComponentID) = target.component,
              let edgePersistentNameString = edgeComponentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology edge target."
            )
        }
        guard let supportTarget = options.supportTarget else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated support face target in offset options."
            )
        }
        guard case .face(let supportFaceComponentID) = supportTarget.component,
              let supportFacePersistentNameString = supportFaceComponentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology support face target."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        let resolvedSupportTarget = try editableBodyTargetResolution(
            for: supportTarget,
            operationName: operationName
        )
        guard resolvedSupportTarget.sceneNodeID == resolvedTarget.sceneNodeID else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target edge and support face must belong to the same body scene node."
            )
        }
        let sceneNode = resolvedTarget.sceneNode
        let targetFeatureID = resolvedTarget.featureID
        guard let targetFeature = cadDocument.designGraph.nodes[targetFeatureID],
              targetFeature.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body-producing target feature."
            )
        }

        let topology = try TopologySnapshotService().snapshot(
            document: self,
            objectRegistry: objectRegistry
        )
        let evaluatedDocument = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: self,
            objectRegistry: objectRegistry,
            failurePrefix: "\(operationName) requires current generated topology"
        )
        guard let edgeEntry = topology.entries.first(where: { $0.persistentName == edgePersistentNameString }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology edge was not found in the current evaluation."
            )
        }
        guard edgeEntry.kind == .edge,
              edgeEntry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target must reference an edge on the selected body."
            )
        }
        guard let supportFaceEntry = topology.entries.first(where: { $0.persistentName == supportFacePersistentNameString }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology support face was not found in the current evaluation."
            )
        }
        guard supportFaceEntry.kind == .face,
              supportFaceEntry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) support target must reference a face on the selected body."
            )
        }
        try validateEdgeOffsetSupportTopology(
            edgeEntry: edgeEntry,
            supportFaceEntry: supportFaceEntry,
            topology: topology,
            evaluatedDocument: evaluatedDocument,
            isSymmetric: options.isSymmetric,
            operationName: operationName
        )

        let edgePersistentName = try GeneratedTopologyPersistentNameParser().parse(
            edgePersistentNameString,
            operationName: operationName
        )
        let supportFacePersistentName = try GeneratedTopologyPersistentNameParser().parse(
            supportFacePersistentNameString,
            operationName: operationName
        )
        let featureID = FeatureID()
        let featureName = "\(sceneNode.name) Edge Offset"
        let feature = FeatureNode(
            id: featureID,
            name: featureName,
            operation: .edgeOffset(
                EdgeOffsetFeature(
                    target: EdgeOffsetTargetReference(featureID: targetFeatureID),
                    edgePersistentName: edgePersistentName,
                    supportFacePersistentName: supportFacePersistentName,
                    distance: distance,
                    isSymmetric: options.isSymmetric,
                    gapFill: options.gapFill.edgeOffsetGapFill
                )
            ),
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
            name: featureName,
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
        didCommit = true
        return featureID
    }

    private func validateEdgeOffsetSupportTopology(
        edgeEntry: TopologySummaryResult.Entry,
        supportFaceEntry: TopologySummaryResult.Entry,
        topology: TopologySnapshot,
        evaluatedDocument: EvaluatedDocument,
        isSymmetric: Bool,
        operationName: String
    ) throws {
        guard edgeEntry.curveKind == "line",
              edgeEntry.start != nil,
              edgeEntry.end != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports generated line edges with resolvable endpoints."
            )
        }
        let edgeID = try evaluatedEdgeID(
            for: edgeEntry,
            in: evaluatedDocument,
            operationName: operationName
        )
        let supportFaceID = try evaluatedFaceID(
            for: supportFaceEntry,
            in: evaluatedDocument,
            operationName: operationName
        )
        guard face(supportFaceID, containsBoundaryEdge: edgeID, in: evaluatedDocument.brep) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) support face must contain the selected edge."
            )
        }
        guard isSymmetric else {
            return
        }
        let oppositeCandidates = try topology.entries.filter { entry in
            guard entry.kind == .face,
                  entry.sceneNodeID == edgeEntry.sceneNodeID,
                  entry.persistentName != supportFaceEntry.persistentName else {
                return false
            }
            let candidateFaceID = try evaluatedFaceID(
                for: entry,
                in: evaluatedDocument,
                operationName: operationName
            )
            return face(
                candidateFaceID,
                containsBoundaryEdge: edgeID,
                in: evaluatedDocument.brep
            )
        }
        guard oppositeCandidates.count == 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) symmetric mode requires exactly one opposite support face sharing the selected edge."
            )
        }
    }

    private func evaluatedEdgeID(
        for entry: TopologySummaryResult.Entry,
        in evaluatedDocument: EvaluatedDocument,
        operationName: String
    ) throws -> EdgeID {
        let persistentName = try GeneratedTopologyPersistentNameParser().parse(
            entry.persistentName,
            operationName: operationName
        )
        guard case .edge(let edgeID) = evaluatedDocument.generatedNames[persistentName] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) evaluated topology edge was not found."
            )
        }
        return edgeID
    }

    private func evaluatedFaceID(
        for entry: TopologySummaryResult.Entry,
        in evaluatedDocument: EvaluatedDocument,
        operationName: String
    ) throws -> FaceID {
        let persistentName = try GeneratedTopologyPersistentNameParser().parse(
            entry.persistentName,
            operationName: operationName
        )
        guard case .face(let faceID) = evaluatedDocument.generatedNames[persistentName] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) evaluated topology face was not found."
            )
        }
        return faceID
    }

    private func face(
        _ faceID: FaceID,
        containsBoundaryEdge edgeID: EdgeID,
        in model: BRepModel
    ) -> Bool {
        guard let face = model.faces[faceID] else {
            return false
        }
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                continue
            }
            if loop.edges.contains(where: { $0.edgeID == edgeID }) {
                return true
            }
        }
        return false
    }

    private func negatedExpression(_ expression: CADExpression) -> CADExpression {
        .multiply(expression, .constant(.scalar(-1.0)))
    }

    private func offsetLine(
        _ line: SketchLine,
        distance: CADExpression,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) line start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) line start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) line end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) line end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        let normalX = -deltaY / length
        let normalY = deltaX / length
        return SketchLine(
            start: offsetPoint(
                line.start,
                distance: distance,
                normalX: normalX,
                normalY: normalY
            ),
            end: offsetPoint(
                line.end,
                distance: distance,
                normalX: normalX,
                normalY: normalY
            )
        )
    }

    private func offsetPoint(
        _ point: SketchPoint,
        distance: CADExpression,
        normalX: Double,
        normalY: Double
    ) -> SketchPoint {
        SketchPoint(
            x: .add(point.x, .multiply(distance, .scalar(normalX))),
            y: .add(point.y, .multiply(distance, .scalar(normalY)))
        )
    }

    private func validateOffsetCurveVertexOptions(_ options: OffsetCurveOptions) throws {
        guard options.mode == .offset else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode requires a selected open curve target, not a vertex handle."
            )
        }
        guard options == OffsetCurveOptions() else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve vertex dispatch does not accept planar curve options such as symmetric output or gap fill."
            )
        }
    }

    private func offsetRadiusExpression(
        _ radius: CADExpression,
        distance: CADExpression,
        resolvedDistance: Double,
        owner: String
    ) throws -> CADExpression {
        let radiusMeters = try resolvedPositiveLengthValue(radius, owner: "\(owner) radius")
        guard radiusMeters + resolvedDistance > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) offset would collapse the radius."
            )
        }
        return .add(radius, distance)
    }
}

private extension OffsetCurveGapFill {
    var faceLoopOffsetGapFill: FaceLoopOffsetGapFill {
        switch self {
        case .round:
            .round
        case .linear:
            .linear
        case .natural:
            .natural
        }
    }

    var edgeOffsetGapFill: EdgeOffsetGapFill {
        switch self {
        case .round:
            .round
        case .linear:
            .linear
        case .natural:
            .natural
        }
    }
}
