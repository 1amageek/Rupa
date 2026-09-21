import RupaCore
import RupaKit
import RupaRendering

struct WorkspaceObjectShapeInspectorStateBuilder {
    let snapshot: ProjectViewSnapshot
    private var document: DesignDocument { snapshot.document.document }

    func shapes(for nodes: [SceneNode]) throws -> [InspectorObjectShape]? {
        guard nodes.allSatisfy({ $0.object?.typeID != nil && $0.reference?.featureID != nil }) else {
            return nil
        }
        return try nodes.map { node in
            guard let object = node.object, let featureID = node.reference?.featureID else {
                throw EditorError(code: .referenceUnresolved,
                    message: "The object source is unavailable.")
            }
            var bounds = snapshot.viewport.items.first {
                snapshot.sceneNodeID(for: $0.id) == node.id
            }?.worldBounds
            for item in snapshot.viewport.items where snapshot.sceneNodeID(for: item.id) == node.id {
                guard var aggregate = bounds else { continue }
                aggregate.minimum.x = min(aggregate.minimum.x, item.worldBounds.minimum.x)
                aggregate.minimum.y = min(aggregate.minimum.y, item.worldBounds.minimum.y)
                aggregate.minimum.z = min(aggregate.minimum.z, item.worldBounds.minimum.z)
                aggregate.maximum.x = max(aggregate.maximum.x, item.worldBounds.maximum.x)
                aggregate.maximum.y = max(aggregate.maximum.y, item.worldBounds.maximum.y)
                aggregate.maximum.z = max(aggregate.maximum.z, item.worldBounds.maximum.z)
                bounds = aggregate
            }
            let size: InspectorVector3D?
            let cornerRadiusLimit: Double?
            var hollowLimit: Double? = nil
            let definition = snapshot.objectRegistry.definition(for: object.typeID)
            var properties = object.properties
            if object.typeID == .cube || object.typeID == .cylinder {
                let source = try ObjectDimensionSourceResolver().resolve(
                    target: SelectionTarget(sceneNodeID: node.id), in: document)
                size = .init(x: source.sizeX, y: source.sizeY, z: source.sizeZ)
                // The bound belongs to the source: a box is bounded by each of its sides and a
                // cylinder by half its own radius, and only the source knows which prism this is.
                cornerRadiusLimit = try document.maximumAllEdgeCornerRadius(
                    featureID: source.featureID)
                // The hollow is bounded by the wall it has to stay inside, which only the circle
                // profile knows, and it publishes zero on a body already carrying a fillet so the
                // two controls collapse each other rather than refusing every drag.
                hollowLimit = try document.maximumCylinderHollow(featureID: source.featureID)
                for property in definition?.properties ?? [] {
                    switch property.renderBinding {
                    case .sizeX: properties[property.id] = .length(source.sizeX)
                    case .sizeY: properties[property.id] = .length(source.sizeY)
                    case .sizeZ: properties[property.id] = .length(source.sizeZ)
                    case .radius:
                        if let radius = source.radius { properties[property.id] = .length(radius) }
                    case .cornerRadius:
                        properties[property.id] = .length(try document.boxCornerRadius(source.featureID))
                    case .hollow:
                        // The hole in the circle profile is the single truth of how hollow the body
                        // is, so the reading comes from it rather than from the stored property.
                        if let hollow = try document.cylinderHollow(featureID: source.featureID) {
                            properties[property.id] = .length(hollow)
                        }
                    default: break
                    }
                }
            } else if definition?.property(for: .bevel) != nil {
                size = nil
                // A profile's `bevel` names the all-edge fillet on the body it extrudes, so the
                // bound is that body's rather than the profile's own extent. A profile nothing has
                // extruded, or one feeding more than one body, names no single body and publishes
                // no bound, which leaves the control on its declared range.
                let bodies = document.extrudedBodyFeatureIDs(forProfile: featureID)
                cornerRadiusLimit = bodies.count == 1
                    ? try document.maximumAllEdgeCornerRadius(featureID: bodies[0])
                    : nil
            } else {
                size = nil
                cornerRadiusLimit = nil
            }
            return InspectorObjectShape(id: node.id, featureID: featureID,
                typeID: object.typeID, definition: definition, properties: properties,
                center: bounds.map { .init(x: ($0.minimum.x + $0.maximum.x) / 2,
                    y: ($0.minimum.y + $0.maximum.y) / 2, z: ($0.minimum.z + $0.maximum.z) / 2) },
                size: size, cornerRadiusLimit: cornerRadiusLimit, hollowLimit: hollowLimit)
        }
    }

    func centerCommands(
        _ axis: InspectorObjectAxis, meters: Double, nodeIDs: [SceneNodeID]
    ) throws -> [EditorCommand] {
        guard meters.isFinite else {
            throw EditorError(code: .commandInvalid, message: "Object center must be finite.")
        }
        let nodes = try nodeIDs.map { id in
            guard let node = document.productMetadata.sceneNodes[id] else {
                throw EditorError(code: .referenceUnresolved, message: "An edited object no longer exists.")
            }
            return node
        }
        guard let shapes = try shapes(for: nodes) else {
            throw EditorError(code: .commandInvalid, message: "The selection has no measurable object center.")
        }
        let parents = try ViewportSceneNodeParentFrames(document: document)
        return try zip(nodes, shapes).compactMap { node, shape in
            guard let center = shape.center,
                  let parent = try parents.parentWorldTransform(of: node.id) else {
                throw EditorError(code: .referenceUnresolved, message: "The object has no current center or parent frame.")
            }
            let delta = Vector3D(x: axis == .x ? meters - center.x : 0,
                y: axis == .y ? meters - center.y : 0,
                z: axis == .z ? meters - center.z : 0)
            let transform = try ViewportWorldTransformAlgebra.localTransform(
                applying: ViewportWorldTransformAlgebra.translation(delta), within: parent,
                to: node.localTransform) ?? node.localTransform
            return try WorkspaceTransformMatrix.command(setting: transform, for: node.id, in: document)
        }
    }

    static func sizeCommands(
        _ axis: InspectorObjectAxis, meters: Double, nodeIDs: [SceneNodeID], in document: DesignDocument
    ) throws -> [EditorCommand] {
        let kind: ObjectDimensionKind = switch axis {
        case .x: .sizeX
        case .y: .sizeY
        case .z: .sizeZ
        }
        return try dimensionCommands(kind, meters: meters, nodeIDs: nodeIDs, in: document)
    }

    static func dimensionCommands(
        _ kind: ObjectDimensionKind, meters: Double, nodeIDs: [SceneNodeID], in document: DesignDocument
    ) throws -> [EditorCommand] {
        guard meters.isFinite, meters > 0 else {
            throw EditorError(code: .commandInvalid, message: "Source size must be finite and positive.")
        }
        var features = Set<FeatureID>()
        return try nodeIDs.compactMap { id in
            guard let node = document.productMetadata.sceneNodes[id] else {
                throw EditorError(code: .referenceUnresolved, message: "An edited object no longer exists.")
            }
            guard !node.isLocked else {
                throw EditorError(code: .commandInvalid, message: "Unlock selected objects before changing their dimensions.")
            }
            let target = SelectionTarget(sceneNodeID: id)
            let source = try ObjectDimensionSourceResolver().resolve(target: target, in: document)
            guard features.insert(source.featureID).inserted else { return nil }
            return .setObjectDimension(target: target, kind: kind, value: .length(meters, .meter))
        }
    }
}
