import Foundation
import SwiftCAD

public struct GeneratedTopologySelectionResolver: Sendable {
    private let topologyService: TopologySummaryService

    public init(topologyService: TopologySummaryService = TopologySummaryService()) {
        self.topologyService = topologyService
    }

    public func componentID(
        for sceneNodeID: SceneNodeID,
        bodyFace requestedBodyFace: BodyFace,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionComponentID? {
        let resolvedSceneNodeID = try resolvedBodySceneNodeID(
            for: sceneNodeID,
            preferredFeatureID: nil,
            in: document,
            operationName: "Generated topology selection"
        )
        let topology = try topologyService.summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        let context = try rectangleContextIfNeeded(
            for: requestedBodyFace,
            sceneNodeID: resolvedSceneNodeID,
            in: document,
            operationName: "Generated topology selection"
        )
        for entry in topology.entries where entry.kind == .face && entry.sceneNodeID == resolvedSceneNodeID.description {
            let resolvedFace: BodyFace
            if let directFace = directBodyFace(for: entry) {
                resolvedFace = directFace
            } else if let context {
                do {
                    resolvedFace = try bodyFace(
                        for: entry,
                        sceneNodeID: resolvedSceneNodeID,
                        context: context,
                        operationName: "Generated topology selection"
                    )
                } catch {
                    continue
                }
            } else {
                continue
            }
            guard resolvedFace == requestedBodyFace,
                  let selectionComponentID = entry.selectionComponentID else {
                continue
            }
            return SelectionComponentID(rawValue: selectionComponentID)
        }
        return nil
    }

    public func componentID(
        for sceneNodeID: SceneNodeID,
        cornerEdge requestedCornerEdge: BodyCornerEdge,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionComponentID? {
        let resolvedSceneNodeID = try resolvedBodySceneNodeID(
            for: sceneNodeID,
            preferredFeatureID: nil,
            in: document,
            operationName: "Generated topology selection"
        )
        let context = try rectangleExtrudeContext(
            for: resolvedSceneNodeID,
            in: document,
            operationName: "Generated topology selection"
        )
        let topology = try topologyService.summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        for entry in topology.entries where entry.kind == .edge && entry.sceneNodeID == resolvedSceneNodeID.description {
            let resolvedEdge: BodyCornerEdge
            do {
                resolvedEdge = try cornerEdge(
                    for: entry,
                    sceneNodeID: resolvedSceneNodeID,
                    context: context,
                    operationName: "Generated topology selection"
                )
            } catch {
                continue
            }
            guard resolvedEdge == requestedCornerEdge,
                  let selectionComponentID = entry.selectionComponentID else {
                continue
            }
            return SelectionComponentID(rawValue: selectionComponentID)
        }
        return nil
    }

    public func componentID(
        for sceneNodeID: SceneNodeID,
        cornerVertex requestedCornerVertex: BodyCornerVertex,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionComponentID? {
        let resolvedSceneNodeID = try resolvedBodySceneNodeID(
            for: sceneNodeID,
            preferredFeatureID: nil,
            in: document,
            operationName: "Generated topology selection"
        )
        let context = try rectangleExtrudeContext(
            for: resolvedSceneNodeID,
            in: document,
            operationName: "Generated topology selection"
        )
        let topology = try topologyService.summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        for entry in topology.entries where entry.kind == .vertex && entry.sceneNodeID == resolvedSceneNodeID.description {
            let resolvedVertex: BodyCornerVertex
            do {
                resolvedVertex = try cornerVertex(
                    for: entry,
                    sceneNodeID: resolvedSceneNodeID,
                    context: context,
                    operationName: "Generated topology selection"
                )
            } catch {
                continue
            }
            guard resolvedVertex == requestedCornerVertex,
                  let selectionComponentID = entry.selectionComponentID else {
                continue
            }
            return SelectionComponentID(rawValue: selectionComponentID)
        }
        return nil
    }

    public func bodyFace(
        for target: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        operationName: String = "Generated topology face"
    ) throws -> BodyFace {
        guard case .face(let componentID) = target.component,
              let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology face target."
            )
        }
        let topology = try topologyService.summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        let resolvedSceneNodeID = try resolvedBodySceneNodeID(
            for: target.sceneNodeID,
            preferredFeatureID: sourceFeatureID(in: persistentName, operationName: operationName),
            in: document,
            operationName: operationName
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target was not found in the current evaluation."
            )
        }
        if let directFace = directBodyFace(for: entry) {
            guard entry.kind == .face,
                  entry.sceneNodeID == resolvedSceneNodeID.description else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) generated topology target must reference a face on the selected body."
                )
            }
            return directFace
        }
        let context = try rectangleExtrudeContext(
            for: resolvedSceneNodeID,
            in: document,
            operationName: operationName
        )
        return try bodyFace(
            for: entry,
            sceneNodeID: resolvedSceneNodeID,
            context: context,
            operationName: operationName
        )
    }

    public func cornerEdge(
        for target: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        operationName: String = "Generated topology edge"
    ) throws -> BodyCornerEdge {
        guard case .edge(let componentID) = target.component,
              let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology edge target."
            )
        }
        let resolvedSceneNodeID = try resolvedBodySceneNodeID(
            for: target.sceneNodeID,
            preferredFeatureID: sourceFeatureID(in: persistentName, operationName: operationName),
            in: document,
            operationName: operationName
        )
        let context = try rectangleExtrudeContext(
            for: resolvedSceneNodeID,
            in: document,
            operationName: operationName
        )
        let topology = try topologyService.summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target was not found in the current evaluation."
            )
        }
        return try cornerEdge(
            for: entry,
            sceneNodeID: resolvedSceneNodeID,
            context: context,
            operationName: operationName
        )
    }

    public func cornerVertex(
        for target: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        operationName: String = "Generated topology vertex"
    ) throws -> BodyCornerVertex {
        guard case .vertex(let componentID) = target.component,
              let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology vertex target."
            )
        }
        let resolvedSceneNodeID = try resolvedBodySceneNodeID(
            for: target.sceneNodeID,
            preferredFeatureID: sourceFeatureID(in: persistentName, operationName: operationName),
            in: document,
            operationName: operationName
        )
        let context = try rectangleExtrudeContext(
            for: resolvedSceneNodeID,
            in: document,
            operationName: operationName
        )
        let topology = try topologyService.summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target was not found in the current evaluation."
            )
        }
        return try cornerVertex(
            for: entry,
            sceneNodeID: resolvedSceneNodeID,
            context: context,
            operationName: operationName
        )
    }

    private func bodyFace(
        for entry: TopologySummaryResult.Entry,
        sceneNodeID: SceneNodeID,
        context: RectangleExtrudeContext,
        operationName: String
    ) throws -> BodyFace {
        guard entry.kind == .face,
              entry.sceneNodeID == sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference a face on the selected body."
            )
        }
        if entry.generatedRole == "startFace" {
            return .front
        }
        if entry.generatedRole == "endFace" {
            return .back
        }
        if entry.surfaceKind == "cylinder" {
            return .side
        }
        guard let center = entry.center else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology face has no resolved center."
            )
        }
        return try bodyFace(
            center: center,
            sketchPlane: context.sketchPlane,
            bounds: context.bounds,
            operationName: operationName
        )
    }

    private func cornerEdge(
        for entry: TopologySummaryResult.Entry,
        sceneNodeID: SceneNodeID,
        context: RectangleExtrudeContext,
        operationName: String
    ) throws -> BodyCornerEdge {
        guard entry.kind == .edge,
              entry.sceneNodeID == sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference an edge on the selected body."
            )
        }
        guard let start = entry.start,
              let end = entry.end else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology edge has no resolved endpoints."
            )
        }

        return try cornerEdge(
            start: start,
            end: end,
            sketchPlane: context.sketchPlane,
            bounds: context.bounds,
            operationName: operationName
        )
    }

    private func cornerVertex(
        for entry: TopologySummaryResult.Entry,
        sceneNodeID: SceneNodeID,
        context: RectangleExtrudeContext,
        operationName: String
    ) throws -> BodyCornerVertex {
        guard entry.kind == .vertex,
              entry.sceneNodeID == sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference a vertex on the selected body."
            )
        }
        guard let point = entry.start else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology vertex has no resolved point."
            )
        }
        return try cornerVertex(
            point: point,
            sketchPlane: context.sketchPlane,
            bounds: context.bounds,
            depthRange: context.depthRange,
            operationName: operationName
        )
    }

    private func bodyFace(
        center: TopologySummaryResult.Entry.Point,
        sketchPlane: SketchPlane,
        bounds: RectangleBounds,
        operationName: String
    ) throws -> BodyFace {
        let coordinate = try sketchCoordinate(from: center, on: sketchPlane)
        let tolerance = 1.0e-8
        if nearlyEqual(coordinate.x, bounds.minX, tolerance: tolerance) {
            return .left
        }
        if nearlyEqual(coordinate.x, bounds.maxX, tolerance: tolerance) {
            return .right
        }
        if nearlyEqual(coordinate.y, bounds.minY, tolerance: tolerance) {
            return .bottom
        }
        if nearlyEqual(coordinate.y, bounds.maxY, tolerance: tolerance) {
            return .top
        }
        throw EditorError(
            code: .commandInvalid,
            message: "\(operationName) generated topology face is not an editable rectangle face."
        )
    }

    private func resolvedBodySceneNodeID(
        for sceneNodeID: SceneNodeID,
        preferredFeatureID: FeatureID?,
        in document: DesignDocument,
        operationName: String
    ) throws -> SceneNodeID {
        guard let sceneNode = document.productMetadata.sceneNodes[sceneNodeID],
              let reference = sceneNode.reference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target requires a body scene node."
            )
        }
        if reference.kind == .body {
            return sceneNodeID
        }
        guard reference.kind == .componentInstance,
              let componentInstanceID = reference.componentInstanceID,
              let instance = document.productMetadata.componentInstances[componentInstanceID],
              let definition = document.productMetadata.componentDefinitions[instance.definitionID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target requires a body scene node."
            )
        }
        let bodySceneNodeIDs = ComponentDefinitionSceneResolver().bodySceneNodeIDs(
            in: definition,
            preferredFeatureID: preferredFeatureID,
            metadata: document.productMetadata
        )
        guard let resolvedSceneNodeID = bodySceneNodeIDs.first,
              bodySceneNodeIDs.count == 1 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) component instance target must resolve to exactly one source body scene node."
            )
        }
        return resolvedSceneNodeID
    }

    private func sourceFeatureID(
        in persistentNameString: String,
        operationName: String
    ) throws -> FeatureID? {
        let persistentName = try GeneratedTopologyPersistentNameParser().parse(
            persistentNameString,
            operationName: operationName
        )
        for component in persistentName.components {
            if case .feature(let featureID) = component {
                return featureID
            }
        }
        return nil
    }

    private func rectangleExtrudeContext(
        for sceneNodeID: SceneNodeID,
        in document: DesignDocument,
        operationName: String
    ) throws -> RectangleExtrudeContext {
        guard let sceneNode = document.productMetadata.sceneNodes[sceneNodeID],
              sceneNode.reference?.kind == .body,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target requires a body scene node."
            )
        }
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation,
              let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation,
              let bounds = try resolvedSketchBounds2D(sketch, in: document),
              try isAxisAlignedRectangle(sketch, bounds: bounds, in: document) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target requires an editable rectangle extrude body."
            )
        }
        let depthMeters = try resolvedLengthValue(
            extrude.distance,
            in: document,
            owner: "Extrude distance"
        )
        let depthRange = try rectangleDepthRange(
            depthMeters: depthMeters,
            direction: extrude.direction,
            operationName: operationName
        )
        return RectangleExtrudeContext(
            sketchPlane: sketch.plane,
            bounds: bounds,
            depthRange: depthRange
        )
    }

    private func cornerEdge(
        start: TopologySummaryResult.Entry.Point,
        end: TopologySummaryResult.Entry.Point,
        sketchPlane: SketchPlane,
        bounds: RectangleBounds,
        operationName: String
    ) throws -> BodyCornerEdge {
        let tolerance = 1.0e-8
        let startCoordinate = try sketchCoordinate(from: start, on: sketchPlane)
        let endCoordinate = try sketchCoordinate(from: end, on: sketchPlane)
        guard nearlyEqual(startCoordinate.x, endCoordinate.x, tolerance: tolerance),
              nearlyEqual(startCoordinate.y, endCoordinate.y, tolerance: tolerance),
              !nearlyEqual(startCoordinate.depth, endCoordinate.depth, tolerance: tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target is not an editable vertical rectangle edge."
            )
        }

        let x = (startCoordinate.x + endCoordinate.x) / 2.0
        let y = (startCoordinate.y + endCoordinate.y) / 2.0
        if nearlyEqual(x, bounds.minX, tolerance: tolerance),
           nearlyEqual(y, bounds.minY, tolerance: tolerance) {
            return .leftBottom
        }
        if nearlyEqual(x, bounds.maxX, tolerance: tolerance),
           nearlyEqual(y, bounds.minY, tolerance: tolerance) {
            return .rightBottom
        }
        if nearlyEqual(x, bounds.maxX, tolerance: tolerance),
           nearlyEqual(y, bounds.maxY, tolerance: tolerance) {
            return .rightTop
        }
        if nearlyEqual(x, bounds.minX, tolerance: tolerance),
           nearlyEqual(y, bounds.maxY, tolerance: tolerance) {
            return .leftTop
        }

        throw EditorError(
            code: .commandInvalid,
            message: "\(operationName) generated topology edge is not a rectangle corner edge."
        )
    }

    private func cornerVertex(
        point: TopologySummaryResult.Entry.Point,
        sketchPlane: SketchPlane,
        bounds: RectangleBounds,
        depthRange: RectangleDepthRange,
        operationName: String
    ) throws -> BodyCornerVertex {
        let tolerance = 1.0e-8
        let coordinate = try sketchCoordinate(from: point, on: sketchPlane)
        let horizontal: VertexHorizontalSide
        if nearlyEqual(coordinate.x, bounds.minX, tolerance: tolerance) {
            horizontal = .left
        } else if nearlyEqual(coordinate.x, bounds.maxX, tolerance: tolerance) {
            horizontal = .right
        } else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology vertex is not on a rectangle side."
            )
        }

        let vertical: VertexVerticalSide
        if nearlyEqual(coordinate.y, bounds.minY, tolerance: tolerance) {
            vertical = .bottom
        } else if nearlyEqual(coordinate.y, bounds.maxY, tolerance: tolerance) {
            vertical = .top
        } else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology vertex is not on a rectangle height."
            )
        }

        let depth: VertexDepthSide
        if nearlyEqual(coordinate.depth, depthRange.min, tolerance: tolerance) {
            depth = .front
        } else if nearlyEqual(coordinate.depth, depthRange.max, tolerance: tolerance) {
            depth = .back
        } else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology vertex is not on a rectangle depth boundary."
            )
        }

        switch (depth, vertical, horizontal) {
        case (.front, .bottom, .left):
            return .frontBottomLeft
        case (.front, .bottom, .right):
            return .frontBottomRight
        case (.front, .top, .right):
            return .frontTopRight
        case (.front, .top, .left):
            return .frontTopLeft
        case (.back, .bottom, .left):
            return .backBottomLeft
        case (.back, .bottom, .right):
            return .backBottomRight
        case (.back, .top, .right):
            return .backTopRight
        case (.back, .top, .left):
            return .backTopLeft
        }
    }

    private func rectangleContextIfNeeded(
        for bodyFace: BodyFace,
        sceneNodeID: SceneNodeID,
        in document: DesignDocument,
        operationName: String
    ) throws -> RectangleExtrudeContext? {
        switch bodyFace {
        case .front, .back, .side:
            return nil
        case .top, .bottom, .left, .right:
            return try rectangleExtrudeContext(
                for: sceneNodeID,
                in: document,
                operationName: operationName
            )
        }
    }

    private func directBodyFace(for entry: TopologySummaryResult.Entry) -> BodyFace? {
        guard entry.kind == .face else {
            return nil
        }
        if entry.generatedRole == "startFace" {
            return .front
        }
        if entry.generatedRole == "endFace" {
            return .back
        }
        if entry.surfaceKind == "cylinder" {
            return .side
        }
        return nil
    }

    private func rectangleDepthRange(
        depthMeters: Double,
        direction: ExtrudeDirection,
        operationName: String
    ) throws -> RectangleDepthRange {
        let size = abs(depthMeters)
        switch direction {
        case .normal:
            if depthMeters >= 0.0 {
                return RectangleDepthRange(min: 0.0, max: size)
            }
            return RectangleDepthRange(min: -size, max: 0.0)
        case .symmetric:
            return RectangleDepthRange(min: -size / 2.0, max: size / 2.0)
        case .vector:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology selection currently requires a normal or symmetric extrude."
            )
        }
    }

    private func isAxisAlignedRectangle(
        _ sketch: Sketch,
        bounds: RectangleBounds,
        in document: DesignDocument
    ) throws -> Bool {
        var lines: [SketchLine] = []
        for entity in sketch.entities.values {
            guard case .line(let line) = entity else {
                return false
            }
            lines.append(line)
        }
        guard lines.count == 4,
              sketch.entities.count == 4 else {
            return false
        }

        var hasBottom = false
        var hasRight = false
        var hasTop = false
        var hasLeft = false
        let tolerance = 1.0e-9
        for line in lines {
            let startX = try resolvedLengthValue(line.start.x, in: document, owner: "Rectangle line start x")
            let startY = try resolvedLengthValue(line.start.y, in: document, owner: "Rectangle line start y")
            let endX = try resolvedLengthValue(line.end.x, in: document, owner: "Rectangle line end x")
            let endY = try resolvedLengthValue(line.end.y, in: document, owner: "Rectangle line end y")
            if nearlyEqual(startY, bounds.minY, tolerance: tolerance),
               nearlyEqual(endY, bounds.minY, tolerance: tolerance) {
                hasBottom = true
            } else if nearlyEqual(startY, bounds.maxY, tolerance: tolerance),
                      nearlyEqual(endY, bounds.maxY, tolerance: tolerance) {
                hasTop = true
            } else if nearlyEqual(startX, bounds.minX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.minX, tolerance: tolerance) {
                hasLeft = true
            } else if nearlyEqual(startX, bounds.maxX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.maxX, tolerance: tolerance) {
                hasRight = true
            } else {
                return false
            }
        }
        return hasBottom && hasRight && hasTop && hasLeft
    }

    private func resolvedSketchBounds2D(
        _ sketch: Sketch,
        in document: DesignDocument
    ) throws -> RectangleBounds? {
        var points: [(x: Double, y: Double)] = []
        for entity in sketch.entities.values {
            for point in sketchPoints(in: entity) {
                points.append(
                    (
                        x: try resolvedLengthValue(point.x, in: document, owner: "Sketch point x"),
                        y: try resolvedLengthValue(point.y, in: document, owner: "Sketch point y")
                    )
                )
            }
        }
        guard let first = points.first else {
            return nil
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return RectangleBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private func sketchPoints(in entity: SketchEntity) -> [SketchPoint] {
        switch entity {
        case .point(let point):
            [point]
        case .line(let line):
            [line.start, line.end]
        case .circle(let circle):
            [circle.center]
        case .arc(let arc):
            [arc.center]
        case .spline(let spline):
            spline.controlPoints
        }
    }

    private func resolvedLengthValue(
        _ expression: CADExpression,
        in document: DesignDocument,
        owner: String
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite length."
            )
        }
        return quantity.value
    }

    private func sketchCoordinate(
        from point: TopologySummaryResult.Entry.Point,
        on plane: SketchPlane
    ) throws -> (x: Double, y: Double, depth: Double) {
        switch plane {
        case .xy:
            return (x: point.x, y: point.y, depth: point.z)
        case .yz:
            return (x: point.y, y: point.z, depth: point.x)
        case .zx:
            return (x: point.z, y: point.x, depth: point.y)
        case .plane(let plane):
            let normal = try plane.normal.normalized(tolerance: 1.0e-12)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: 1.0e-12)
            let v = normal.cross(u)
            let delta = Point3D(x: point.x, y: point.y, z: point.z) - plane.origin
            return (
                x: delta.dot(u),
                y: delta.dot(v),
                depth: delta.dot(normal)
            )
        }
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}

private struct RectangleExtrudeContext: Sendable {
    var sketchPlane: SketchPlane
    var bounds: RectangleBounds
    var depthRange: RectangleDepthRange
}

private struct RectangleBounds: Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
}

private struct RectangleDepthRange: Sendable {
    var min: Double
    var max: Double
}

private enum VertexHorizontalSide: Sendable {
    case left
    case right
}

private enum VertexVerticalSide: Sendable {
    case bottom
    case top
}

private enum VertexDepthSide: Sendable {
    case front
    case back
}
