import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SelectionDimensionTargetResolver: Sendable {
    private let topologyService: TopologySummaryService
    private let sketchEntityService: SketchEntitySummaryService
    private let persistentNameParser: GeneratedTopologyPersistentNameParser

    public init(
        topologyService: TopologySummaryService = TopologySummaryService(),
        sketchEntityService: SketchEntitySummaryService = SketchEntitySummaryService()
    ) {
        self.topologyService = topologyService
        self.sketchEntityService = sketchEntityService
        self.persistentNameParser = GeneratedTopologyPersistentNameParser()
    }

    public func reference(
        for target: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionReference {
        guard document.productMetadata.sceneNodes[target.sceneNodeID] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension target requires an existing scene node."
            )
        }

        switch target.component {
        case .object:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension target requires a face, edge, vertex, or sketch curve target."
            )
        case .face(let componentID):
            return try generatedTopologyReference(
                componentID: componentID,
                target: target,
                kind: .face,
                document: document,
                objectRegistry: objectRegistry
            )
        case .edge(let componentID):
            return try generatedTopologyReference(
                componentID: componentID,
                target: target,
                kind: .edge,
                document: document,
                objectRegistry: objectRegistry
            )
        case .vertex(let componentID):
            return try generatedTopologyReference(
                componentID: componentID,
                target: target,
                kind: .vertex,
                document: document,
                objectRegistry: objectRegistry
            )
        case .sketchEntity(let componentID):
            return try sketchReference(
                componentID: componentID,
                target: target,
                document: document,
                objectRegistry: objectRegistry
            )
        case .region:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension target requires a measurable curve or topology target, not a profile region."
            )
        }
    }

    private func generatedTopologyReference(
        componentID: SelectionComponentID,
        target: SelectionTarget,
        kind: TopologySummaryResult.Entry.Kind,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> SelectionReference {
        guard let persistentNameString = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension generated topology target requires a generated topology component ID."
            )
        }
        let topology = try topologyService.summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        guard topology.entries.contains(where: {
            $0.kind == kind &&
                $0.sceneNodeID == target.sceneNodeID.description &&
                $0.persistentName == persistentNameString
        }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension generated topology target was not found in the current evaluation."
            )
        }
        return .topology(try persistentNameParser.parse(
            persistentNameString,
            operationName: "Selection dimension"
        ))
    }

    private func sketchReference(
        componentID: SelectionComponentID,
        target: SelectionTarget,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> SelectionReference {
        if let handle = componentID.sketchPointHandleReference {
            return try sketchPointHandleReference(
                handle,
                target: target,
                document: document,
                objectRegistry: objectRegistry
            )
        }
        if let controlPoint = componentID.sketchControlPointReference {
            return try sketchControlPointReference(
                controlPoint,
                target: target,
                document: document,
                objectRegistry: objectRegistry
            )
        }

        guard let reference = componentID.sketchEntityReference else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension sketch target requires a sketch entity component ID."
            )
        }
        let curveIndex = try curveIndex(
            featureID: reference.featureID,
            entityID: reference.entityID,
            target: target,
            document: document,
            objectRegistry: objectRegistry
        )
        return .curve(.whole(CurveOutputReference(
            featureID: reference.featureID,
            curveIndex: curveIndex
        )))
    }

    private func sketchPointHandleReference(
        _ reference: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            handle: SketchEntityPointHandle
        ),
        target: SelectionTarget,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> SelectionReference {
        guard let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension sketch point target could not resolve its source sketch entity."
            )
        }
        if reference.handle == .point {
            guard case .point = entity else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection dimension sketch point handle requires a source sketch point entity."
                )
            }
            try requireSketchEntityInSummary(
                featureID: reference.featureID,
                entityID: reference.entityID,
                target: target,
                document: document,
                objectRegistry: objectRegistry
            )
            return .sketchPoint(SketchPointSelectionReference(
                featureID: reference.featureID,
                entityID: reference.entityID
            ))
        }
        let curveIndex = try curveIndex(
            featureID: reference.featureID,
            entityID: reference.entityID,
            target: target,
            document: document,
            objectRegistry: objectRegistry
        )
        switch (reference.handle, entity) {
        case (.lineStart, .line):
            return .curve(.parameter(CurveParameterReference(
                curve: CurveOutputReference(featureID: reference.featureID, curveIndex: curveIndex),
                parameter: 0.0
            )))
        case (.lineEnd, .line(let line)):
            return .curve(.parameter(CurveParameterReference(
                curve: CurveOutputReference(featureID: reference.featureID, curveIndex: curveIndex),
                parameter: try lineLength(line, document: document)
            )))
        case (.arcStart, .arc(let arc)):
            let parameters = try SketchArcEndpointParameterResolver().endpointParameters(
                for: arc,
                plane: sketch.plane,
                in: document,
                owner: "Selection dimension"
            )
            return .curve(.parameter(CurveParameterReference(
                curve: CurveOutputReference(featureID: reference.featureID, curveIndex: curveIndex),
                parameter: parameters.start
            )))
        case (.arcEnd, .arc(let arc)):
            let parameters = try SketchArcEndpointParameterResolver().endpointParameters(
                for: arc,
                plane: sketch.plane,
                in: document,
                owner: "Selection dimension"
            )
            return .curve(.parameter(CurveParameterReference(
                curve: CurveOutputReference(featureID: reference.featureID, curveIndex: curveIndex),
                parameter: parameters.end
            )))
        case (.circleCenter, .circle), (.arcCenter, .arc):
            return .curve(.center(CurveCenterReference(
                curve: CurveOutputReference(featureID: reference.featureID, curveIndex: curveIndex)
            )))
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension sketch point targets currently support standalone points, line start/end, circle/arc center, and arc start/end handles."
            )
        }
    }

    private func sketchControlPointReference(
        _ reference: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            index: Int
        ),
        target: SelectionTarget,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> SelectionReference {
        guard let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case let .sketch(sketch) = feature.operation,
              case let .spline(spline) = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension sketch control point target requires an existing source spline entity."
            )
        }
        guard spline.controlPoints.indices.contains(reference.index) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension sketch control point target requires an existing source spline control point."
            )
        }
        let curveIndex = try curveIndex(
            featureID: reference.featureID,
            entityID: reference.entityID,
            target: target,
            document: document,
            objectRegistry: objectRegistry
        )
        return .curve(.controlPoint(CurveControlPointReference(
            curve: CurveOutputReference(featureID: reference.featureID, curveIndex: curveIndex),
            controlPointIndex: reference.index
        )))
    }

    private func curveIndex(
        featureID: FeatureID,
        entityID: SketchEntityID,
        target: SelectionTarget,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> Int {
        let summary = try sketchEntityService.summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        let entries = summary.entries.filter { entry in
            entry.sourceFeatureID == featureID.description &&
                entry.sceneNodeID == target.sceneNodeID.description
        }
        guard entries.contains(where: { $0.entityID == entityID.description }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension sketch target was not found in the current sketch summary."
            )
        }
        let curveEntityIDs = try curveEntityIDs(
            featureID: featureID,
            document: document
        )
        guard let index = curveEntityIDs.firstIndex(of: entityID) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension sketch target must reference a curve entity."
            )
        }
        return index
    }

    private func requireSketchEntityInSummary(
        featureID: FeatureID,
        entityID: SketchEntityID,
        target: SelectionTarget,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let summary = try sketchEntityService.summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        let found = summary.entries.contains { entry in
            entry.sourceFeatureID == featureID.description &&
                entry.sceneNodeID == target.sceneNodeID.description &&
                entry.entityID == entityID.description
        }
        guard found else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension sketch target was not found in the current sketch summary."
            )
        }
    }

    private func curveEntityIDs(
        featureID: FeatureID,
        document: DesignDocument
    ) throws -> [SketchEntityID] {
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension sketch target requires a sketch feature."
            )
        }
        return sketch.entities
            .sorted(by: { $0.key.description < $1.key.description })
            .compactMap { entityID, entity in
                if case .point = entity {
                    return nil
                }
                return entityID
            }
    }

    private func lineLength(
        _ line: SketchLine,
        document: DesignDocument
    ) throws -> Double {
        let start = try resolvedPoint(line.start, document: document, owner: "Selection dimension line start")
        let end = try resolvedPoint(line.end, document: document, owner: "Selection dimension line end")
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        document: DesignDocument,
        owner: String
    ) throws -> Point2D {
        Point2D(
            x: try resolvedLength(point.x, document: document, owner: "\(owner) x"),
            y: try resolvedLength(point.y, document: document, owner: "\(owner) y")
        )
    }

    private func resolvedLength(
        _ expression: CADExpression,
        document: DesignDocument,
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

}
