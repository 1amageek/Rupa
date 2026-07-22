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
        guard case .face(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology face target."
            )
        }
        let faceReference = try componentID.stableTopologyReference(
            operationName: operationName
        )
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
        guard let entry = topology.entries.first(where: {
            $0.stableReference == faceReference
        }) else {
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

        let faceKnife = FaceKnifeFeature(
            target: FaceKnifeTargetReference(featureID: targetFeatureID),
            face: faceReference,
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
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }

    @discardableResult
    public mutating func projectSketchCurvesToConstructionPlane(
        targets: [SelectionTarget],
        plane: SketchPlane,
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

        var topology: TopologySnapshot?
        return try appendProjectedCurveSketch(
            targets: targets,
            targetPlane: plane,
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
        let evaluatedTopology = try TopologySnapshotService().snapshot(
            document: self,
            objectRegistry: objectRegistry
        )
        var topology: TopologySnapshot? = evaluatedTopology
        let targetPlane = try ConstructionPlaneTargetResolver().planarGeneratedFacePlane(
            alignedTo: face,
            topology: evaluatedTopology,
            operationName: operationName,
            tolerance: modelingSettings.tolerance
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

    mutating func appendProjectedCurveSketch(
        targets: [SelectionTarget],
        targetPlane: SketchPlane,
        operationName: String,
        name: String?,
        defaultName: ([String]) -> String,
        objectRegistry: ObjectTypeRegistry,
        topology: inout TopologySnapshot?
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
        try projectedSketch.validate(tolerance: modelingSettings.tolerance)
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

    func projectedSketchName(from sourceNames: [String]) -> String {
        if sourceNames.count == 1,
           let sourceName = sourceNames.first {
            return "\(sourceName) Projection"
        }
        return "Projected Curves"
    }

    func projectedFaceProjectionName(from sourceNames: [String]) -> String {
        if sourceNames.count == 1,
           let sourceName = sourceNames.first {
            return "\(sourceName) Face Projection"
        }
        return "Projected Face Curves"
    }

    @discardableResult
    public mutating func projectBodyOutlinesToConstructionPlane(
        targets: [SelectionTarget],
        plane: SketchPlane,
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

        let targetSystem = try SketchPlaneCoordinateSystem(plane: plane)
        let topology = try TopologySnapshotService().snapshot(
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
            plane: plane,
            entities: projectedEntities
        )
        try projectedSketch.validate(tolerance: modelingSettings.tolerance)
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

    func projectedOutlineName(from sourceNames: [String]) -> String {
        if sourceNames.count == 1,
           let sourceName = sourceNames.first {
            return "\(sourceName) Outline Projection"
        }
        return "Projected Outlines"
    }
}
