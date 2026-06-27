import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func offsetBodyFace(
        target: SelectionTarget,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let offsetMeters = try resolvedLengthValue(distance, owner: "Face offset distance")
        guard abs(offsetMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset distance must not be zero."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: "Face offset"
        )
        let face = try editableBodyFace(
            for: resolvedTarget.target,
            objectRegistry: objectRegistry
        )
        let featureID = resolvedTarget.featureID
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case var .extrude(extrude) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset requires an editable extrude body."
            )
        }
        guard var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case var .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset requires an editable sketch profile."
            )
        }
        if let circleEntry = singleCircleEntry(in: sketch) {
            try offsetCylinderFace(
                face: face,
                offsetMeters: offsetMeters,
                circleEntry: circleEntry,
                sketch: &sketch,
                profileFeature: &profileFeature,
                feature: &feature,
                extrude: &extrude,
                featureID: featureID,
                sceneNodeID: resolvedTarget.sceneNodeID,
                objectRegistry: objectRegistry
            )
            return
        }
        guard isRectangleProfile(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset requires an editable rectangle or circle profile."
            )
        }
        guard var bounds = try resolvedSketchBounds2D(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset requires a finite rectangle profile."
            )
        }

        var translationYDelta = 0.0
        var updatesProfile = false
        switch face {
        case .left:
            bounds.minX -= offsetMeters
            updatesProfile = true
        case .right:
            bounds.maxX += offsetMeters
            updatesProfile = true
        case .top:
            bounds.maxY += offsetMeters
            updatesProfile = true
        case .bottom:
            bounds.minY -= offsetMeters
            updatesProfile = true
        case .back, .front:
            let nextDepth = try offsetExtrudeDepth(
                extrude: &extrude,
                face: face,
                offsetMeters: offsetMeters
            )
            if face == .front {
                translationYDelta = -offsetMeters
            }
            extrude.distance = .length(nextDepth, .meter)
            feature.operation = .extrude(extrude)
        case .side:
            throw EditorError(
                code: .commandInvalid,
                message: "Rectangle face offset does not support side faces."
            )
        }

        if updatesProfile {
            guard bounds.maxX - bounds.minX > 1.0e-9,
                  bounds.maxY - bounds.minY > 1.0e-9 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Face offset would collapse the rectangle profile."
                )
            }

            let firstCorner = SketchPoint(
                x: .length(bounds.minX, .meter),
                y: .length(bounds.minY, .meter)
            )
            let oppositeCorner = SketchPoint(
                x: .length(bounds.maxX, .meter),
                y: .length(bounds.maxY, .meter)
            )
            try updateRectangleSketch(
                &sketch,
                firstCorner: firstCorner,
                oppositeCorner: oppositeCorner
            )
            profileFeature.operation = .sketch(sketch)
        }

        var updatedCADDocument = cadDocument
        do {
            if updatesProfile {
                try updatedCADDocument.replaceFeatures([profileFeature, feature])
            } else {
                try updatedCADDocument.replaceFeature(feature)
            }
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        if abs(translationYDelta) > 0.0 {
            try translateSceneNode(resolvedTarget.sceneNodeID, y: translationYDelta)
        }
        try synchronizeObjectPropertiesFromSource(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func chamferBodyEdges(
        targets: [SelectionTarget],
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let chamferMeters = try resolvedPositiveLengthValue(distance, owner: "Edge chamfer distance")
        guard !targets.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge chamfer requires at least one edge selection target."
            )
        }

        let resolvedTargets = try targets.map { target in
            try editableBodyTargetResolution(
                for: target,
                operationName: "Edge chamfer"
            )
        }
        var sceneNodeID: SceneNodeID?
        for target in resolvedTargets.map(\.target) {
            if let resolvedSceneNodeID = sceneNodeID {
                guard resolvedSceneNodeID == target.sceneNodeID else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Edge chamfer currently requires all edge targets to belong to the same body."
                    )
                }
            } else {
                sceneNodeID = target.sceneNodeID
            }
        }

        guard sceneNodeID != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge chamfer requires an editable body edge."
            )
        }
        guard let featureID = resolvedTargets.first?.featureID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge chamfer requires an editable body edge."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge chamfer requires an editable extrude body."
            )
        }
        guard case .normal = extrude.direction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge chamfer currently requires a normal extrude."
            )
        }
        _ = try resolvedPositiveLengthValue(extrude.distance, owner: "Extrude distance")
        guard var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge chamfer requires an editable sketch profile."
            )
        }

        let profileLoop = try EditableExtrudeProfileLoop.editableLoop(
            in: sketch,
            document: self,
            operationName: "Edge chamfer"
        )
        let targetIndices: Set<Int>
        if let bounds = try resolvedSketchBounds2D(sketch),
           try rectangleLineIDs(in: sketch) != nil {
            targetIndices = try rectangleProfileLoopVertexIndices(
                for: resolvedTargets.map(\.target),
                profileLoop: profileLoop,
                bounds: bounds,
                operationName: "Edge chamfer",
                objectRegistry: objectRegistry
            )
        } else {
            targetIndices = try generatedProfileLoopVertexIndices(
                for: resolvedTargets.map(\.target),
                profileLoop: profileLoop,
                sketchPlane: sketch.plane,
                expectedKind: .edge,
                operationName: "Edge chamfer",
                objectRegistry: objectRegistry
            )
        }
        let nextSketch = try profileLoop.chamferedSketch(
            targetVertexIndices: targetIndices,
            distance: chamferMeters,
            operationName: "Edge chamfer"
        )
        profileFeature.operation = .sketch(nextSketch)
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures([profileFeature, feature])
            try validateEditableBodyCandidate(
                updatedCADDocument,
                operationName: "Edge chamfer",
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge chamfer produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try markBodyObjectAsSourceEditedSolid(featureID: featureID)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func filletBodyEdges(
        targets: [SelectionTarget],
        radius: CADExpression,
        segmentCount: Int,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let filletMeters = try resolvedPositiveLengthValue(radius, owner: "Edge fillet radius")
        guard (3 ... 64).contains(segmentCount) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet segment count must be between 3 and 64."
            )
        }
        guard !targets.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet requires at least one edge selection target."
            )
        }

        let resolvedTargets = try targets.map { target in
            try editableBodyTargetResolution(
                for: target,
                operationName: "Edge fillet"
            )
        }
        var sceneNodeID: SceneNodeID?
        for target in resolvedTargets.map(\.target) {
            if let resolvedSceneNodeID = sceneNodeID {
                guard resolvedSceneNodeID == target.sceneNodeID else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Edge fillet currently requires all edge targets to belong to the same body."
                    )
                }
            } else {
                sceneNodeID = target.sceneNodeID
            }
        }

        guard sceneNodeID != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet requires an editable body edge."
            )
        }
        guard let featureID = resolvedTargets.first?.featureID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet requires an editable body edge."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge fillet requires an editable extrude body."
            )
        }
        guard case .normal = extrude.direction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet currently requires a normal extrude."
            )
        }
        _ = try resolvedPositiveLengthValue(extrude.distance, owner: "Extrude distance")
        guard var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge fillet requires an editable sketch profile."
            )
        }

        let profileLoop = try EditableExtrudeProfileLoop.editableLoop(
            in: sketch,
            document: self,
            operationName: "Edge fillet"
        )
        let targetIndices: Set<Int>
        if let bounds = try resolvedSketchBounds2D(sketch),
           try rectangleLineIDs(in: sketch) != nil {
            targetIndices = try rectangleProfileLoopVertexIndices(
                for: resolvedTargets.map(\.target),
                profileLoop: profileLoop,
                bounds: bounds,
                operationName: "Edge fillet",
                objectRegistry: objectRegistry
            )
        } else {
            targetIndices = try generatedProfileLoopVertexIndices(
                for: resolvedTargets.map(\.target),
                profileLoop: profileLoop,
                sketchPlane: sketch.plane,
                expectedKind: .edge,
                operationName: "Edge fillet",
                objectRegistry: objectRegistry
            )
        }
        let nextSketch = try profileLoop.filletedSketch(
            targetVertexIndices: targetIndices,
            radius: filletMeters,
            operationName: "Edge fillet"
        )
        profileFeature.operation = .sketch(nextSketch)
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures([profileFeature, feature])
            try validateEditableBodyCandidate(
                updatedCADDocument,
                operationName: "Edge fillet",
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge fillet produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try markBodyObjectAsSourceEditedSolid(
            featureID: featureID,
            profileArcSegmentCount: segmentCount
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func moveBodyVertex(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Vertex move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Vertex move delta Y")
        guard abs(deltaXMeters) > 1.0e-12 || abs(deltaYMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Vertex move delta must not be zero."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: "Vertex move"
        )
        let featureID = resolvedTarget.featureID
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation,
              var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Vertex move requires an editable sketch profile."
            )
        }

        let nextSketch: Sketch
        let preservesObjectProperties: Bool
        if isRectangleProfile(sketch) {
            let vertex = try editableBodyVertex(
                for: resolvedTarget.target,
                objectRegistry: objectRegistry
            )
            guard var bounds = try resolvedSketchBounds2D(sketch) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Vertex move requires a finite rectangle profile."
                )
            }

            switch vertex {
            case .bottomLeft:
                bounds.minX += deltaXMeters
                bounds.minY += deltaYMeters
            case .bottomRight:
                bounds.maxX += deltaXMeters
                bounds.minY += deltaYMeters
            case .topRight:
                bounds.maxX += deltaXMeters
                bounds.maxY += deltaYMeters
            case .topLeft:
                bounds.minX += deltaXMeters
                bounds.maxY += deltaYMeters
            }

            guard bounds.maxX - bounds.minX > 1.0e-9,
                  bounds.maxY - bounds.minY > 1.0e-9 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Vertex move would collapse the rectangle profile."
                )
            }

            var rectangleSketch = sketch
            try updateRectangleSketch(
                &rectangleSketch,
                firstCorner: sketchPoint(x: bounds.minX, y: bounds.minY),
                oppositeCorner: sketchPoint(x: bounds.maxX, y: bounds.maxY)
            )
            nextSketch = rectangleSketch
            preservesObjectProperties = true
        } else {
            let profileLoop = try EditableExtrudeProfileLoop.editableLoop(
                in: sketch,
                document: self,
                operationName: "Vertex move"
            )
            let index = try profileLoopVertexIndex(
                for: resolvedTarget.target,
                profileLoop: profileLoop,
                sketchPlane: sketch.plane,
                expectedKind: .vertex,
                operationName: "Vertex move",
                objectRegistry: objectRegistry
            )
            nextSketch = try profileLoop.movedVertexSketch(
                targetVertexIndex: index,
                deltaX: deltaXMeters,
                deltaY: deltaYMeters,
                operationName: "Vertex move"
            )
            preservesObjectProperties = false
        }

        profileFeature.operation = .sketch(nextSketch)
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures([profileFeature, feature])
            try validateEditableBodyCandidate(
                updatedCADDocument,
                operationName: "Vertex move",
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Vertex move produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        if preservesObjectProperties {
            try synchronizeObjectPropertiesFromSource(
                featureID: featureID,
                objectRegistry: objectRegistry
            )
        } else {
            try markBodyObjectAsSourceEditedSolid(featureID: featureID)
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    private func editableBodyFace(
        for target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EditableBodyFace {
        guard case .face(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset requires a face selection target."
            )
        }
        if componentID.generatedTopologyPersistentName != nil {
            let bodyFace = try GeneratedTopologySelectionResolver().bodyFace(
                for: target,
                in: self,
                objectRegistry: objectRegistry,
                operationName: "Face offset"
            )
            return editableBodyFace(for: bodyFace)
        }
        switch componentID {
        case .bodyFaceFront:
            return .front
        case .bodyFaceBack:
            return .back
        case .bodyFaceTop:
            return .top
        case .bodyFaceBottom:
            return .bottom
        case .bodyFaceLeft:
            return .left
        case .bodyFaceRight:
            return .right
        case .bodyFaceSide:
            return .side
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset target is not an editable body face."
            )
        }
    }

    private func editableBodyFace(for bodyFace: BodyFace) -> EditableBodyFace {
        switch bodyFace {
        case .front:
            return .front
        case .back:
            return .back
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .left:
            return .left
        case .right:
            return .right
        case .side:
            return .side
        }
    }

    private func validateEditableBodyCandidate(
        _ updatedCADDocument: CADDocument,
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        do {
            try updatedCADDocument.validate()
            var candidate = self
            candidate.cadDocument = updatedCADDocument
            _ = try CADPipeline
                .modelingDefault(for: candidate, objectRegistry: objectRegistry)
                .evaluate(updatedCADDocument)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) produced invalid geometry: \(error)."
            )
        }
    }

    private func rectangleProfileLoopVertexIndices(
        for targets: [SelectionTarget],
        profileLoop: EditableExtrudeProfileLoop,
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double),
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> Set<Int> {
        var targetIndices = Set<Int>()
        for target in targets {
            let edge = try editableBodyEdge(
                for: target,
                operationName: operationName,
                objectRegistry: objectRegistry
            )
            let vertex = rectangleProfilePoint(for: edge, bounds: bounds)
            guard let index = profileLoop.closestVertexIndex(to: vertex) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(operationName) rectangle edge target does not match an editable profile loop vertex."
                )
            }
            targetIndices.insert(index)
        }
        return targetIndices
    }

    private func rectangleProfilePoint(
        for edge: EditableBodyEdge,
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    ) -> EditableExtrudeProfileLoop.Point {
        switch edge {
        case .leftBottom:
            EditableExtrudeProfileLoop.Point(x: bounds.minX, y: bounds.minY)
        case .rightBottom:
            EditableExtrudeProfileLoop.Point(x: bounds.maxX, y: bounds.minY)
        case .rightTop:
            EditableExtrudeProfileLoop.Point(x: bounds.maxX, y: bounds.maxY)
        case .leftTop:
            EditableExtrudeProfileLoop.Point(x: bounds.minX, y: bounds.maxY)
        }
    }

    private func generatedProfileLoopVertexIndices(
        for targets: [SelectionTarget],
        profileLoop: EditableExtrudeProfileLoop,
        sketchPlane: SketchPlane,
        expectedKind: TopologySummaryResult.Entry.Kind,
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> Set<Int> {
        var targetIndices = Set<Int>()
        for target in targets {
            let index = try profileLoopVertexIndex(
                for: target,
                profileLoop: profileLoop,
                sketchPlane: sketchPlane,
                expectedKind: expectedKind,
                operationName: operationName,
                objectRegistry: objectRegistry
            )
            targetIndices.insert(index)
        }
        return targetIndices
    }

    private func profileLoopVertexIndex(
        for target: SelectionTarget,
        profileLoop: EditableExtrudeProfileLoop,
        sketchPlane: SketchPlane,
        expectedKind: TopologySummaryResult.Entry.Kind,
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> Int {
        let componentID: SelectionComponentID
        switch (expectedKind, target.component) {
        case (.edge, .edge(let edgeComponentID)):
            componentID = edgeComponentID
        case (.vertex, .vertex(let vertexComponentID)):
            componentID = vertexComponentID
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires generated topology \(expectedKind.rawValue) targets for non-rectangle profile loops."
            )
        }
        guard let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires generated topology targets for non-rectangle profile loops."
            )
        }
        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target was not found in the current evaluation."
            )
        }
        guard entry.sceneNodeID == target.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference the selected body."
            )
        }
        guard entry.kind == expectedKind else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference a \(expectedKind.rawValue) on the selected body."
            )
        }
        let tolerance = 1.0e-8
        let point: EditableExtrudeProfileLoop.Point
        switch entry.kind {
        case .edge:
            guard let start = entry.start,
                  let end = entry.end else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) generated topology target must reference an edge on the selected body."
                )
            }
            let startCoordinate = try sketchCoordinate(from: start, on: sketchPlane)
            let endCoordinate = try sketchCoordinate(from: end, on: sketchPlane)
            guard nearlyEqual(startCoordinate.x, endCoordinate.x, tolerance: tolerance),
                  nearlyEqual(startCoordinate.y, endCoordinate.y, tolerance: tolerance),
                  !nearlyEqual(startCoordinate.depth, endCoordinate.depth, tolerance: tolerance) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) generated topology target is not a vertical profile edge."
                )
            }
            point = EditableExtrudeProfileLoop.Point(
                x: (startCoordinate.x + endCoordinate.x) / 2.0,
                y: (startCoordinate.y + endCoordinate.y) / 2.0
            )
        case .vertex:
            guard let start = entry.start else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) generated topology target must reference a vertex on the selected body."
                )
            }
            let coordinate = try sketchCoordinate(from: start, on: sketchPlane)
            point = EditableExtrudeProfileLoop.Point(
                x: coordinate.x,
                y: coordinate.y
            )
        case .body, .face:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference an edge or vertex on the selected body."
            )
        }
        guard let index = profileLoop.closestVertexIndex(to: point, tolerance: tolerance) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology edge does not match an editable profile loop vertex."
            )
        }
        return index
    }

    private func editableBodyEdge(
        for target: SelectionTarget,
        operationName: String = "Edge chamfer",
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EditableBodyEdge {
        guard case .edge(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires edge selection targets."
            )
        }
        if componentID.generatedTopologyPersistentName != nil {
            let cornerEdge = try GeneratedTopologySelectionResolver().cornerEdge(
                for: target,
                in: self,
                objectRegistry: objectRegistry,
                operationName: operationName
            )
            return editableBodyEdge(for: cornerEdge)
        }
        switch componentID {
        case .bodyEdgeLeftBottom:
            return .leftBottom
        case .bodyEdgeRightBottom:
            return .rightBottom
        case .bodyEdgeRightTop:
            return .rightTop
        case .bodyEdgeLeftTop:
            return .leftTop
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target is not an editable body edge."
            )
        }
    }

    private func editableBodyEdge(for cornerEdge: BodyCornerEdge) -> EditableBodyEdge {
        switch cornerEdge {
        case .leftBottom:
            return .leftBottom
        case .rightBottom:
            return .rightBottom
        case .rightTop:
            return .rightTop
        case .leftTop:
            return .leftTop
        }
    }

    private func editableBodyVertex(
        for target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EditableBodyVertex {
        guard case .vertex(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Vertex move requires a vertex selection target."
            )
        }
        if componentID.generatedTopologyPersistentName != nil {
            let cornerVertex = try GeneratedTopologySelectionResolver().cornerVertex(
                for: target,
                in: self,
                objectRegistry: objectRegistry,
                operationName: "Vertex move"
            )
            return editableBodyVertex(for: cornerVertex)
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Vertex move target is not an editable generated body vertex."
        )
    }

    private func editableBodyVertex(for cornerVertex: BodyCornerVertex) -> EditableBodyVertex {
        switch cornerVertex {
        case .frontBottomLeft, .backBottomLeft:
            return .bottomLeft
        case .frontBottomRight, .backBottomRight:
            return .bottomRight
        case .frontTopRight, .backTopRight:
            return .topRight
        case .frontTopLeft, .backTopLeft:
            return .topLeft
        }
    }

    private func offsetExtrudeDepth(
        extrude: inout ExtrudeFeature,
        face: EditableBodyFace,
        offsetMeters: Double
    ) throws -> Double {
        guard face == .front || face == .back else {
            return try resolvedPositiveLengthValue(extrude.distance, owner: "Extrude distance")
        }
        guard case .normal = extrude.direction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Front and back face offset currently requires a normal extrude."
            )
        }
        let depthMeters = try resolvedLengthValue(extrude.distance, owner: "Extrude distance")
        guard depthMeters > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Front and back face offset currently requires a positive extrude distance."
            )
        }
        let nextDepth = depthMeters + offsetMeters
        guard nextDepth > 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset would collapse the extrude body."
            )
        }
        return nextDepth
    }

    private mutating func offsetCylinderFace(
        face: EditableBodyFace,
        offsetMeters: Double,
        circleEntry: (id: SketchEntityID, circle: SketchCircle),
        sketch: inout Sketch,
        profileFeature: inout FeatureNode,
        feature: inout FeatureNode,
        extrude: inout ExtrudeFeature,
        featureID: FeatureID,
        sceneNodeID: SceneNodeID,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        var radiusMeters = try resolvedPositiveLengthValue(
            circleEntry.circle.radius,
            owner: "Cylinder radius"
        )
        var translationYDelta = 0.0
        var updatesProfile = false
        switch face {
        case .side:
            radiusMeters += offsetMeters
            guard radiusMeters > 1.0e-9 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Face offset would collapse the cylinder radius."
                )
            }
            sketch.entities[circleEntry.id] = .circle(
                SketchCircle(
                    center: circleEntry.circle.center,
                    radius: .length(radiusMeters, .meter)
                )
            )
            profileFeature.operation = .sketch(sketch)
            updatesProfile = true
        case .front, .back:
            let nextDepth = try offsetExtrudeDepth(
                extrude: &extrude,
                face: face,
                offsetMeters: offsetMeters
            )
            if face == .front {
                translationYDelta = -offsetMeters
            }
            extrude.distance = .length(nextDepth, .meter)
            feature.operation = .extrude(extrude)
        case .top, .bottom, .left, .right:
            throw EditorError(
                code: .commandInvalid,
                message: "Cylinder face offset supports front, back, and side faces."
            )
        }

        var updatedCADDocument = cadDocument
        do {
            if updatesProfile {
                try updatedCADDocument.replaceFeatures([profileFeature, feature])
            } else {
                try updatedCADDocument.replaceFeature(feature)
            }
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cylinder face offset produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        if abs(translationYDelta) > 0.0 {
            try translateSceneNode(sceneNodeID, y: translationYDelta)
        }
        let sizeY = abs(try resolvedLengthValue(extrude.distance, owner: "Extrude distance"))
        try synchronizeCylinderObjectProperties(
            featureID: featureID,
            radius: radiusMeters,
            sizeY: sizeY,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    private mutating func translateSceneNode(
        _ id: SceneNodeID,
        y delta: Double
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset lost its scene node."
            )
        }
        var values = node.localTransform.matrix.values
        if values.count != 16 {
            values = Matrix4x4.identity.values
        }
        values[13] += delta
        node.localTransform = Transform3D(matrix: try Matrix4x4(values: values))
        productMetadata.sceneNodes[id] = node
    }
}

private enum EditableBodyFace: Equatable {
    case front
    case back
    case top
    case bottom
    case left
    case right
    case side
}

private enum EditableBodyEdge: Equatable, Hashable {
    case leftBottom
    case rightBottom
    case rightTop
    case leftTop
}

private enum EditableBodyVertex: Equatable, Hashable {
    case bottomLeft
    case bottomRight
    case topRight
    case topLeft
}
