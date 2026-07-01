import Foundation
import SwiftCAD
import RupaCoreTypes

struct ObjectDimensionSourceResolver: Sendable {
    func resolve(
        target: SelectionTarget,
        in document: DesignDocument
    ) throws -> ObjectDimensionSource {
        switch target.component {
        case .object, .face(_):
            break
        case .edge(let componentID):
            guard componentID.generatedTopologyPersistentName != nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Object dimension requires an object, face, or generated extrusion depth edge target."
                )
            }
        case .vertex(_), .sketchEntity(_), .region(_), .constructionPlane(_):
            throw EditorError(
                code: .commandInvalid,
                message: "Object dimension requires an object, face, or generated extrusion depth edge target."
            )
        }

        guard let node = document.productMetadata.sceneNodes[target.sceneNodeID],
              let object = node.object,
              object.category == .body else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object dimension requires a body target."
            )
        }
        guard let featureID = object.sourceFeatureID ?? node.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object dimension requires a body source feature."
            )
        }
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation,
              let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object dimensions require an extruded sketch body."
            )
        }

        let depth = try resolvedLengthValue(
            extrude.distance,
            owner: "Extrude distance",
            document: document
        )
        try validateGeneratedExtrusionDepthEdgeIfNeeded(
            target: target,
            featureID: featureID,
            sketchPlane: sketch.plane,
            document: document
        )
        if let circleEntry = singleCircleEntry(in: sketch) {
            let radius = try resolvedPositiveLengthValue(
                circleEntry.circle.radius,
                owner: "Cylinder radius",
                document: document
            )
            return ObjectDimensionSource(
                target: target,
                featureID: featureID,
                sceneNodeID: target.sceneNodeID,
                shape: .cylinder,
                sizeX: radius * 2.0,
                sizeY: abs(depth),
                sizeZ: radius * 2.0,
                radius: radius,
                radiusExpression: circleEntry.circle.radius,
                depthExpression: extrude.distance
            )
        }

        guard isRectangleProfile(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object dimensions require an editable rectangle or circle profile."
            )
        }
        guard let bounds = try resolvedSketchBounds2D(sketch, document: document) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object dimensions require a finite sketch profile."
            )
        }
        return ObjectDimensionSource(
            target: target,
            featureID: featureID,
            sceneNodeID: target.sceneNodeID,
            shape: .box,
            sizeX: max(bounds.maxX - bounds.minX, 1.0e-9),
            sizeY: abs(depth),
            sizeZ: max(bounds.maxY - bounds.minY, 1.0e-9),
            radius: nil,
            radiusExpression: nil,
            depthExpression: extrude.distance
        )
    }

    private func validateGeneratedExtrusionDepthEdgeIfNeeded(
        target: SelectionTarget,
        featureID: FeatureID,
        sketchPlane: SketchPlane,
        document: DesignDocument
    ) throws {
        guard case .edge(let componentID) = target.component else {
            return
        }
        guard let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "Object dimension requires a generated extrusion depth edge target."
            )
        }
        let topology = try TopologySummaryService().summarize(document: document)
        guard let entry = topology.entries.first(where: {
            $0.kind == .edge &&
                $0.sceneNodeID == target.sceneNodeID.description &&
                $0.persistentName == persistentName
        }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object dimension generated edge target was not found in the current topology."
            )
        }
        guard entry.generatedRole == "edge",
              entry.sourceFeatureID == featureID.description,
              let start = entry.start,
              let end = entry.end else {
            throw EditorError(
                code: .commandInvalid,
                message: "Object dimension requires a generated extrusion depth edge target on the selected body."
            )
        }
        let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketchPlane)
        let startProjection = coordinateSystem.project(
            Point3D(x: start.x, y: start.y, z: start.z)
        )
        let endProjection = coordinateSystem.project(
            Point3D(x: end.x, y: end.y, z: end.z)
        )
        guard nearlyEqual(startProjection.point.x, endProjection.point.x) &&
            nearlyEqual(startProjection.point.y, endProjection.point.y) &&
            !nearlyEqual(startProjection.depth, endProjection.depth) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Object dimension requires a generated extrusion depth edge, not a profile cap edge."
            )
        }
    }

    private func resolvedSketchBounds2D(
        _ sketch: Sketch,
        document: DesignDocument
    ) throws -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var points: [(x: Double, y: Double)] = []
        for entity in sketch.entities.values {
            for point in sketchPoints(in: entity) {
                points.append(
                    (
                        x: try resolvedLengthValue(point.x, owner: "Sketch point x", document: document),
                        y: try resolvedLengthValue(point.y, owner: "Sketch point y", document: document)
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
        return (minX, minY, maxX, maxY)
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

    private func isRectangleProfile(_ sketch: Sketch) -> Bool {
        guard sketch.entities.count == 4 else {
            return false
        }
        return sketch.entities.values.allSatisfy { entity in
            if case .line(_) = entity {
                return true
            }
            return false
        }
    }

    private func singleCircleEntry(in sketch: Sketch) -> (id: SketchEntityID, circle: SketchCircle)? {
        var circleEntry: (id: SketchEntityID, circle: SketchCircle)?
        for (id, entity) in sketch.entities {
            guard case .circle(let circle) = entity else {
                return nil
            }
            guard circleEntry == nil else {
                return nil
            }
            circleEntry = (id, circle)
        }
        return circleEntry
    }

    private func resolvedLengthValue(
        _ expression: CADExpression,
        owner: String,
        document: DesignDocument
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

    private func resolvedPositiveLengthValue(
        _ expression: CADExpression,
        owner: String,
        document: DesignDocument
    ) throws -> Double {
        let value = try resolvedLengthValue(expression, owner: owner, document: document)
        guard value > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be greater than zero."
            )
        }
        return value
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 1.0e-8
    }
}
