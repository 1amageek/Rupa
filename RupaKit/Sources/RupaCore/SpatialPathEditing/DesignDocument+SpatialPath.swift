import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func convertSketchToSpatialPath(
        featureID: FeatureID, objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "An editable sketch source is required.")
        }
        let system = try SketchPlaneCoordinateSystem(plane: sketch.plane)
        func point(_ source: SketchPoint) throws -> Point3D {
            system.point(from: Point2D(
                x: try resolvedLengthValue(source.x, owner: "Spatial conversion X"),
                y: try resolvedLengthValue(source.y, owner: "Spatial conversion Y")
            ))
        }
        let path: SpatialPathFeature
        if sketch.entities.count == 1, case let .spline(spline)? = sketch.entities.values.first {
            let controls = try spline.controlPoints.map(point)
            guard controls.count >= 4, (controls.count - 1).isMultiple(of: 3) else {
                throw EditorError(code: .commandInvalid, message: "Spatial conversion requires a cubic spline.")
            }
            var knots: [SpatialPathKnot] = []
            for index in stride(from: 0, to: controls.count, by: 3) {
                let position = controls[index]
                let incoming: Vector3D = index > 0 ? controls[index - 1] - position : .zero
                let outgoing: Vector3D = index + 1 < controls.count ? controls[index + 1] - position : .zero
                knots.append(SpatialPathKnot(position: position, incoming: incoming, outgoing: outgoing))
            }
            if spline.isClosed,
               (knots[0].position - knots[knots.count - 1].position).length <= modelingSettings.tolerance.distance {
                knots[0].incoming = knots.removeLast().incoming
            }
            path = SpatialPathFeature(kind: .bezier, knots: knots, isClosed: spline.isClosed)
        } else {
            var segments = try sketch.orderedEntities.map { entry -> (Point3D, Point3D) in
                guard case let .line(line) = entry.entity else {
                    throw EditorError(code: .commandInvalid, message: "Spatial conversion supports a cubic spline or a connected line path.")
                }
                return try (point(line.start), point(line.end))
            }
            guard let first = segments.first else {
                throw EditorError(code: .commandInvalid, message: "An empty sketch cannot become a spatial path.")
            }
            segments.removeFirst()
            var positions = [first.0, first.1]
            let distance = modelingSettings.tolerance.distance
            while !segments.isEmpty {
                let end = positions[positions.count - 1]
                let start = positions[0]
                if let index = segments.firstIndex(where: { ($0.0 - end).length <= distance || ($0.1 - end).length <= distance }) {
                    let segment = segments.remove(at: index)
                    positions.append((segment.0 - end).length <= distance ? segment.1 : segment.0)
                } else if let index = segments.firstIndex(where: { ($0.0 - start).length <= distance || ($0.1 - start).length <= distance }) {
                    let segment = segments.remove(at: index)
                    positions.insert((segment.0 - start).length <= distance ? segment.1 : segment.0, at: 0)
                } else {
                    throw EditorError(code: .commandInvalid, message: "Spatial conversion requires one connected path.")
                }
            }
            let closed = positions.count > 2 && (positions[0] - positions[positions.count - 1]).length <= distance
            if closed { positions.removeLast() }
            path = SpatialPathFeature(kind: .polyline, knots: positions.map { SpatialPathKnot(position: $0) }, isClosed: closed)
        }
        var candidate = self
        feature.operation = .spatialPath(path)
        feature.outputs = [FeatureOutput(role: .curve)]
        try candidate.cadDocument.replaceFeature(feature, tolerance: modelingSettings.tolerance)
        for id in candidate.productMetadata.sceneNodes.keys {
            guard var node = candidate.productMetadata.sceneNodes[id],
                  node.object?.sourceFeatureID == featureID else { continue }
            node.object = .sketch(featureID: featureID, documentID: cadDocument.id,
                                  geometryRole: .curve, objectRegistry: objectRegistry)
            candidate.productMetadata.sceneNodes[id] = node
        }
        try candidate.productMetadata.validate(against: candidate.cadDocument, objectRegistry: objectRegistry)
        self = candidate
    }

    @discardableResult
    public mutating func createSpatialPath(
        name: String, path: SpatialPathFeature, objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        var candidate = self
        let feature = try FeatureNodeFactory.make(
            operation: .spatialPath(path), name: name,
            in: candidate.cadDocument, tolerance: modelingSettings.tolerance
        )
        try candidate.appendFeature(feature)
        _ = try candidate.productMetadata.appendSceneNodeToFirstRoot(
            name: name, reference: .sketch(feature.id),
            object: .sketch(featureID: feature.id, documentID: cadDocument.id,
                            geometryRole: .curve, objectRegistry: objectRegistry)
        )
        try candidate.productMetadata.validate(against: candidate.cadDocument, objectRegistry: objectRegistry)
        self = candidate
        return feature.id
    }

    public mutating func editSpatialPath(
        featureID: FeatureID, edit: SpatialPathEdit, objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case let .spatialPath(path) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "Spatial path source could not be resolved.")
        }
        feature.operation = .spatialPath(try edit.applying(to: path, tolerance: modelingSettings.tolerance))
        var candidate = self
        try candidate.cadDocument.replaceFeature(feature, tolerance: modelingSettings.tolerance)
        try candidate.productMetadata.validate(against: candidate.cadDocument, objectRegistry: objectRegistry)
        self = candidate
    }
}
