import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func validateEditableBodyCandidate(
        _ updatedCADDocument: CADDocument,
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        do {
            try updatedCADDocument.validate()
            var candidate = self
            candidate.cadDocument = updatedCADDocument
            try candidate.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) produced invalid geometry: \(error)."
            )
        }
    }

    func rectangleProfileLoopVertexIndices(
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

    func rectangleProfilePoint(
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

    func generatedProfileLoopVertexIndices(
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

    func profileLoopVertexIndex(
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
        let topology = try TopologySnapshotService().snapshot(
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
}
