import Foundation
import SwiftCAD

public struct ProductMetadata: Codable, Hashable, Sendable {
    public var sceneNodes: [SceneNodeID: SceneNode]
    public var rootSceneNodeIDs: [SceneNodeID]
    public var componentDefinitions: [ComponentDefinitionID: ComponentDefinition]
    public var componentInstances: [ComponentInstanceID: ComponentInstance]
    public var patternArrays: [PatternArraySourceID: PatternArraySource]
    public var materialLibrary: MaterialLibrary
    public var validationRules: [ValidationRuleID: ValidationRule]
    public var exportPresets: [ExportPresetID: ExportPreset]
    public var bridgeCurveSources: [BridgeCurveSourceID: BridgeCurveSource]
    public var joinedCurveSources: [JoinedCurveSourceID: JoinedCurveSource]
    public var joinedCurveGroupSources: [JoinedCurveGroupSourceID: JoinedCurveGroupSource]
    public var constructionPlanes: [ConstructionPlaneSourceID: ConstructionPlaneSource]
    public var activeConstructionPlaneID: ConstructionPlaneSourceID?
    public var curveCurvatureDisplays: [SelectionComponentID: CurveCurvatureDisplay]
    public var pointDisplays: [SelectionComponentID: PointDisplay]
    public var surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
    public var measurements: [MeasurementAnnotationID: MeasurementAnnotation]
    public var templateDefaults: TemplateDefaults

    public init(
        sceneNodes: [SceneNodeID: SceneNode],
        rootSceneNodeIDs: [SceneNodeID],
        componentDefinitions: [ComponentDefinitionID: ComponentDefinition] = [:],
        componentInstances: [ComponentInstanceID: ComponentInstance] = [:],
        patternArrays: [PatternArraySourceID: PatternArraySource] = [:],
        materialLibrary: MaterialLibrary = MaterialLibrary(),
        validationRules: [ValidationRuleID: ValidationRule] = [:],
        exportPresets: [ExportPresetID: ExportPreset] = [:],
        bridgeCurveSources: [BridgeCurveSourceID: BridgeCurveSource] = [:],
        joinedCurveSources: [JoinedCurveSourceID: JoinedCurveSource] = [:],
        joinedCurveGroupSources: [JoinedCurveGroupSourceID: JoinedCurveGroupSource] = [:],
        constructionPlanes: [ConstructionPlaneSourceID: ConstructionPlaneSource] = [:],
        activeConstructionPlaneID: ConstructionPlaneSourceID? = nil,
        curveCurvatureDisplays: [SelectionComponentID: CurveCurvatureDisplay] = [:],
        pointDisplays: [SelectionComponentID: PointDisplay] = [:],
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay] = [:],
        measurements: [MeasurementAnnotationID: MeasurementAnnotation] = [:],
        templateDefaults: TemplateDefaults = TemplateDefaults()
    ) {
        self.sceneNodes = sceneNodes
        self.rootSceneNodeIDs = rootSceneNodeIDs
        self.componentDefinitions = componentDefinitions
        self.componentInstances = componentInstances
        self.patternArrays = patternArrays
        self.materialLibrary = materialLibrary
        self.validationRules = validationRules
        self.exportPresets = exportPresets
        self.bridgeCurveSources = bridgeCurveSources
        self.joinedCurveSources = joinedCurveSources
        self.joinedCurveGroupSources = joinedCurveGroupSources
        self.constructionPlanes = constructionPlanes
        self.activeConstructionPlaneID = activeConstructionPlaneID
        self.curveCurvatureDisplays = curveCurvatureDisplays
        self.pointDisplays = pointDisplays
        self.surfaceControlPointDisplays = surfaceControlPointDisplays
        self.measurements = measurements
        self.templateDefaults = templateDefaults
    }

    private enum CodingKeys: String, CodingKey {
        case sceneNodes
        case rootSceneNodeIDs
        case componentDefinitions
        case componentInstances
        case patternArrays
        case materialLibrary
        case validationRules
        case exportPresets
        case bridgeCurveSources
        case joinedCurveSources
        case joinedCurveGroupSources
        case constructionPlanes
        case activeConstructionPlaneID
        case curveCurvatureDisplays
        case pointDisplays
        case surfaceControlPointDisplays
        case measurements
        case templateDefaults
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sceneNodes: try container.decode([SceneNodeID: SceneNode].self, forKey: .sceneNodes),
            rootSceneNodeIDs: try container.decode([SceneNodeID].self, forKey: .rootSceneNodeIDs),
            componentDefinitions: try container.decodeIfPresent(
                [ComponentDefinitionID: ComponentDefinition].self,
                forKey: .componentDefinitions
            ) ?? [:],
            componentInstances: try container.decodeIfPresent(
                [ComponentInstanceID: ComponentInstance].self,
                forKey: .componentInstances
            ) ?? [:],
            patternArrays: try container.decodeIfPresent(
                [PatternArraySourceID: PatternArraySource].self,
                forKey: .patternArrays
            ) ?? [:],
            materialLibrary: try container.decodeIfPresent(
                MaterialLibrary.self,
                forKey: .materialLibrary
            ) ?? MaterialLibrary(),
            validationRules: try container.decodeIfPresent(
                [ValidationRuleID: ValidationRule].self,
                forKey: .validationRules
            ) ?? [:],
            exportPresets: try container.decodeIfPresent(
                [ExportPresetID: ExportPreset].self,
                forKey: .exportPresets
            ) ?? [:],
            bridgeCurveSources: try container.decodeIfPresent(
                [BridgeCurveSourceID: BridgeCurveSource].self,
                forKey: .bridgeCurveSources
            ) ?? [:],
            joinedCurveSources: try container.decodeIfPresent(
                [JoinedCurveSourceID: JoinedCurveSource].self,
                forKey: .joinedCurveSources
            ) ?? [:],
            joinedCurveGroupSources: try container.decodeIfPresent(
                [JoinedCurveGroupSourceID: JoinedCurveGroupSource].self,
                forKey: .joinedCurveGroupSources
            ) ?? [:],
            constructionPlanes: try container.decodeIfPresent(
                [ConstructionPlaneSourceID: ConstructionPlaneSource].self,
                forKey: .constructionPlanes
            ) ?? [:],
            activeConstructionPlaneID: try container.decodeIfPresent(
                ConstructionPlaneSourceID.self,
                forKey: .activeConstructionPlaneID
            ),
            curveCurvatureDisplays: try container.decodeIfPresent(
                [SelectionComponentID: CurveCurvatureDisplay].self,
                forKey: .curveCurvatureDisplays
            ) ?? [:],
            pointDisplays: try container.decodeIfPresent(
                [SelectionComponentID: PointDisplay].self,
                forKey: .pointDisplays
            ) ?? [:],
            surfaceControlPointDisplays: try container.decodeIfPresent(
                [SurfaceControlPointDisplayID: SurfaceControlPointDisplay].self,
                forKey: .surfaceControlPointDisplays
            ) ?? [:],
            measurements: try container.decodeIfPresent(
                [MeasurementAnnotationID: MeasurementAnnotation].self,
                forKey: .measurements
            ) ?? [:],
            templateDefaults: try container.decodeIfPresent(
                TemplateDefaults.self,
                forKey: .templateDefaults
            ) ?? TemplateDefaults()
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sceneNodes, forKey: .sceneNodes)
        try container.encode(rootSceneNodeIDs, forKey: .rootSceneNodeIDs)
        try container.encode(componentDefinitions, forKey: .componentDefinitions)
        try container.encode(componentInstances, forKey: .componentInstances)
        try container.encode(patternArrays, forKey: .patternArrays)
        try container.encode(materialLibrary, forKey: .materialLibrary)
        try container.encode(validationRules, forKey: .validationRules)
        try container.encode(exportPresets, forKey: .exportPresets)
        try container.encode(bridgeCurveSources, forKey: .bridgeCurveSources)
        try container.encode(joinedCurveSources, forKey: .joinedCurveSources)
        try container.encode(joinedCurveGroupSources, forKey: .joinedCurveGroupSources)
        try container.encode(constructionPlanes, forKey: .constructionPlanes)
        try container.encodeIfPresent(activeConstructionPlaneID, forKey: .activeConstructionPlaneID)
        try container.encode(curveCurvatureDisplays, forKey: .curveCurvatureDisplays)
        try container.encode(pointDisplays, forKey: .pointDisplays)
        try container.encode(surfaceControlPointDisplays, forKey: .surfaceControlPointDisplays)
        try container.encode(measurements, forKey: .measurements)
        try container.encode(templateDefaults, forKey: .templateDefaults)
    }

    public static func empty() -> ProductMetadata {
        let root = SceneNode(name: "Scene")
        return ProductMetadata(
            sceneNodes: [root.id: root],
            rootSceneNodeIDs: [root.id]
        )
    }

    public func validate(
        against cadDocument: CADDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        try validatePatternArrayOutputOwnership()
        try validateSceneNodes(against: cadDocument, objectRegistry: objectRegistry)
        try validateComponentDefinitions()
        try validateComponentInstances()
        try validatePatternArrays(against: cadDocument)
        try materialLibrary.validate()
        try validateValidationRules()
        try validateExportPresets()
        try validateBridgeCurveSources(against: cadDocument)
        try validateJoinedCurveSources(against: cadDocument)
        try validateJoinedCurveGroupSources(against: cadDocument)
        try validateConstructionPlanes()
        try validateCurveCurvatureDisplays(against: cadDocument)
        try validatePointDisplays(against: cadDocument)
        try validateSurfaceControlPointDisplays(against: cadDocument)
        try validateMeasurements()
        try validateTemplateDefaults()
    }

    public mutating func appendSceneNodeToFirstRoot(
        name: String,
        reference: SceneNodeReference?,
        object: ObjectDescriptor? = nil
    ) throws -> SceneNodeID {
        guard let rootSceneNodeID = rootSceneNodeIDs.first else {
            throw DocumentValidationError.invalidProductMetadata("A document must contain at least one root scene node.")
        }
        guard sceneNodes[rootSceneNodeID] != nil else {
            throw DocumentValidationError.invalidProductMetadata("Root scene node references a missing node.")
        }

        let sceneNode = SceneNode(
            name: name,
            reference: reference,
            object: object
        )
        sceneNodes[sceneNode.id] = sceneNode
        sceneNodes[rootSceneNodeID]?.childIDs.append(sceneNode.id)
        return sceneNode.id
    }

    private func validateSceneNodes(
        against cadDocument: CADDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard !rootSceneNodeIDs.isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("A document must contain at least one root scene node.")
        }
        guard Set(rootSceneNodeIDs).count == rootSceneNodeIDs.count else {
            throw DocumentValidationError.invalidProductMetadata("Root scene node references must be unique.")
        }

        for rootSceneNodeID in rootSceneNodeIDs {
            guard sceneNodes[rootSceneNodeID] != nil else {
                throw DocumentValidationError.invalidProductMetadata("Root scene node references a missing node.")
            }
        }

        for (sceneNodeID, sceneNode) in sceneNodes {
            guard sceneNode.id == sceneNodeID else {
                throw DocumentValidationError.invalidProductMetadata("Scene node keys must match scene node IDs.")
            }
            try sceneNode.validate()
            if let materialID = sceneNode.materialID,
               materialLibrary.materials[materialID] == nil {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node material references a missing material."
                )
            }
            for childID in sceneNode.childIDs {
                guard sceneNodes[childID] != nil else {
                    throw DocumentValidationError.invalidProductMetadata("Scene node child references a missing node.")
                }
            }
            try validateSceneReference(sceneNode.reference, against: cadDocument)
            try validateObjectDescriptor(
                sceneNode.object,
                reference: sceneNode.reference,
                against: cadDocument,
                objectRegistry: objectRegistry
            )
        }

        try validateSceneHierarchy()
    }

    private func validateSceneReference(
        _ reference: SceneNodeReference?,
        against cadDocument: CADDocument
    ) throws {
        guard let reference else {
            return
        }
        switch reference.kind {
        case .feature:
            guard let featureID = reference.featureID,
                  cadDocument.designGraph.nodes[featureID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node feature references must point to an existing CAD feature."
                )
            }
        case .body:
            guard let featureID = reference.featureID,
                  let feature = cadDocument.designGraph.nodes[featureID],
                  feature.producesSceneGeometry else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node body references must point to an existing CAD geometry-producing feature."
                )
            }
        case .sketch:
            guard let featureID = reference.featureID,
                  let feature = cadDocument.designGraph.nodes[featureID],
                  feature.outputs.contains(where: { $0.role == .profile || $0.role == .curve }) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node sketch references must point to an existing CAD sketch profile or curve feature."
                )
            }
        case .componentInstance:
            guard let componentInstanceID = reference.componentInstanceID,
                  componentInstances[componentInstanceID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node component references must point to an existing component instance."
                )
            }
        case .construction:
            if let constructionPlaneID = reference.constructionPlaneID,
               constructionPlanes[constructionPlaneID] == nil {
                throw DocumentValidationError.invalidProductMetadata(
                    "Construction plane scene references must point to an existing construction plane source."
                )
            }
            return
        }
    }

    private func validateObjectDescriptor(
        _ object: ObjectDescriptor?,
        reference: SceneNodeReference?,
        against cadDocument: CADDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let object else {
            return
        }
        try object.validate()
        let definition = try object.typeID.map { typeID in
            try objectRegistry.requireDefinition(for: typeID)
        }
        if let definition {
            guard object.category == definition.category else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Object category must match object type \(definition.id.rawValue)."
                )
            }
            if let geometryRole = definition.geometryRole {
                guard object.geometryRole == geometryRole else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Object geometry role must match object type \(definition.id.rawValue)."
                    )
                }
            }
        }
        switch object.category {
        case .group:
            guard reference == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Group objects must not point to CAD source references."
                )
            }
        case .body:
            guard reference?.kind == .body,
                  reference?.featureID == object.sourceFeatureID,
                  let sourceFeatureID = object.sourceFeatureID,
                  let feature = cadDocument.designGraph.nodes[sourceFeatureID],
                  feature.producesSceneGeometry else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Body objects must point to a geometry-producing CAD feature."
                )
            }
            if object.geometryRole == .solid {
                guard feature.outputs.contains(where: { $0.role == .body }) else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Solid body objects must point to a solid-producing CAD feature."
                    )
                }
            }
            if object.geometryRole == .surface {
                guard feature.outputs.contains(where: { $0.role == .sheet }) else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Surface body objects must point to a sheet-producing CAD feature."
                    )
                }
            }
            if let sourceSection = object.sourceSection {
                guard let sourceSectionFeature = cadDocument.designGraph.nodes[sourceSection.featureID],
                      sourceSectionFeature.outputs.contains(where: { $0.role == sourceSection.requiredOutputRole }) else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Body object source sections must point to CAD sketch profile or curve features."
                    )
                }
            }
        case .sketch:
            guard reference?.kind == .sketch,
                  reference?.featureID == object.sourceFeatureID,
                  let sourceFeatureID = object.sourceFeatureID,
                  let feature = cadDocument.designGraph.nodes[sourceFeatureID],
                  feature.outputs.contains(where: { $0.role == .profile || $0.role == .curve }) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Sketch objects must point to a CAD sketch profile or curve feature."
                )
            }
        case .componentInstance:
            guard reference?.kind == .componentInstance,
                  reference?.componentInstanceID == object.componentInstanceID,
                  let componentInstanceID = object.componentInstanceID,
                  componentInstances[componentInstanceID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component instance objects must point to an existing component instance."
                )
            }
        case .construction:
            guard reference?.kind == .construction else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Construction objects must use construction scene references."
                )
            }
        case .annotation:
            break
        case .camera, .light:
            return
        }
        if let definition {
            try object.properties.validate(
                against: definition,
                materialLibrary: materialLibrary
            )
        }
    }

    private func validateSceneHierarchy() throws {
        var visited: Set<SceneNodeID> = []
        var visiting: Set<SceneNodeID> = []
        var parentByChild: [SceneNodeID: SceneNodeID] = [:]

        for rootSceneNodeID in rootSceneNodeIDs {
            try visitSceneNode(
                rootSceneNodeID,
                visited: &visited,
                visiting: &visiting,
                parentByChild: &parentByChild
            )
        }

        guard visited == Set(sceneNodes.keys) else {
            throw DocumentValidationError.invalidProductMetadata(
                "Every scene node must be reachable from the root scene nodes."
            )
        }
    }

    private func validateBridgeCurveSources(against cadDocument: CADDocument) throws {
        for (sourceID, source) in bridgeCurveSources {
            guard source.id == sourceID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Bridge curve source keys must match bridge curve source IDs."
                )
            }
            guard let feature = cadDocument.designGraph.nodes[source.featureID],
                  case .sketch(let sketch) = feature.operation else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Bridge curve sources must point to existing sketch features."
                )
            }
            guard case .spline(let spline) = sketch.entities[source.entityID] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Bridge curve source entities must point to spline sketch entities."
                )
            }
            guard spline.controlPoints.count >= 7,
                  (spline.controlPoints.count - 1).isMultiple(of: 3) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Bridge curve source entities must be multi-span cubic Bezier splines with 3n + 1 control points."
                )
            }
            guard bridgeEndpointLocationSignature(source.firstEndpoint) !=
                bridgeEndpointLocationSignature(source.secondEndpoint) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Bridge curve source endpoints must be distinct."
                )
            }
            let firstEndpointKind = try validateBridgeEndpoint(
                source.firstEndpoint,
                source: source,
                sketch: sketch,
                cadDocument: cadDocument
            )
            let secondEndpointKind = try validateBridgeEndpoint(
                source.secondEndpoint,
                source: source,
                sketch: sketch,
                cadDocument: cadDocument
            )
            try validateBridgeEndpointContinuity(
                source.continuity.first,
                endpointKind: firstEndpointKind,
                owner: "Bridge curve first continuity"
            )
            try validateBridgeEndpointContinuity(
                source.continuity.second,
                endpointKind: secondEndpointKind,
                owner: "Bridge curve second continuity"
            )
            try validateBridgeTension(
                source.firstEndpoint.tension,
                owner: "Bridge curve first tension",
                cadDocument: cadDocument
            )
            try validateBridgeTension(
                source.secondEndpoint.tension,
                owner: "Bridge curve second tension",
                cadDocument: cadDocument
            )
        }
    }

    private func validateJoinedCurveSources(against cadDocument: CADDocument) throws {
        var retainedKeys: Set<String> = []
        for (sourceID, source) in joinedCurveSources {
            guard source.id == sourceID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve source keys must match joined curve source IDs."
                )
            }
            guard source.retainedEntityID != source.restoredEntityID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve sources must store distinct retained and restored entity IDs."
                )
            }
            let retainedKey = "\(source.featureID):\(source.retainedEntityID)"
            guard retainedKeys.insert(retainedKey).inserted else {
                throw DocumentValidationError.invalidProductMetadata(
                    "A joined curve source target can only be owned by one joined source."
                )
            }
            guard let feature = cadDocument.designGraph.nodes[source.featureID],
                  case .sketch(let sketch) = feature.operation else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve sources must point to existing sketch features."
                )
            }
            guard case .line = sketch.entities[source.retainedEntityID] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve sources must point to retained source line entities."
                )
            }
            guard sketch.entities[source.restoredEntityID] == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve restored entities must not exist while the source remains joined."
                )
            }
            guard joinedCurveReference(
                source.retainedSharedReference,
                references: source.retainedEntityID,
                allowed: [.lineStart, .lineEnd]
            ),
            joinedCurveReference(
                source.migratedRestoredOuterReference,
                references: source.retainedEntityID,
                allowed: [.lineStart, .lineEnd]
            ),
            joinedCurveReference(
                source.restoredSharedReference,
                references: source.restoredEntityID,
                allowed: [.lineStart, .lineEnd]
            ),
            joinedCurveReference(
                source.restoredOuterReference,
                references: source.restoredEntityID,
                allowed: [.lineStart, .lineEnd]
            ),
            source.restoredSharedReference != source.restoredOuterReference else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve sources must store source line endpoint references."
                )
            }
        }
    }

    private func validateJoinedCurveGroupSources(against cadDocument: CADDocument) throws {
        var ownedKeys: Set<JoinedCurveOwnershipKey> = []
        for source in joinedCurveSources.values {
            ownedKeys.insert(
                JoinedCurveOwnershipKey(featureID: source.featureID, entityID: source.retainedEntityID)
            )
            ownedKeys.insert(
                JoinedCurveOwnershipKey(featureID: source.featureID, entityID: source.restoredEntityID)
            )
        }
        for (sourceID, source) in joinedCurveGroupSources {
            guard source.id == sourceID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve group source keys must match joined curve group source IDs."
                )
            }
            guard source.memberEntityIDs.count >= 2 else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve group sources must contain at least two source entities."
                )
            }
            guard Set(source.memberEntityIDs).count == source.memberEntityIDs.count else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve group source members must be unique."
                )
            }
            guard let feature = cadDocument.designGraph.nodes[source.featureID],
                  case .sketch(let sketch) = feature.operation else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve group sources must point to existing sketch features."
                )
            }
            for entityID in source.memberEntityIDs {
                guard sketch.entities[entityID] != nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Joined curve group source members must exist in the source sketch."
                    )
                }
                let key = JoinedCurveOwnershipKey(featureID: source.featureID, entityID: entityID)
                guard ownedKeys.insert(key).inserted else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "A source curve can only be owned by one joined curve source."
                    )
                }
            }
            guard joinedCurveGroupReference(
                source.firstJoinedReference,
                referencesAnyOf: Set(source.memberEntityIDs),
                in: sketch
            ),
            joinedCurveGroupReference(
                source.secondJoinedReference,
                referencesAnyOf: Set(source.memberEntityIDs),
                in: sketch
            ) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve group sources must store source line or arc endpoint references."
                )
            }
            guard joinedCurveGroupReferenceEntityID(source.firstJoinedReference) !=
                    joinedCurveGroupReferenceEntityID(source.secondJoinedReference) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Joined curve group endpoint references must connect distinct source entities."
                )
            }
        }
    }

    private struct JoinedCurveOwnershipKey: Hashable {
        var featureID: FeatureID
        var entityID: SketchEntityID
    }

    private enum JoinedCurveEndpointKind {
        case lineStart
        case lineEnd
        case arcStart
        case arcEnd
    }

    private func joinedCurveReference(
        _ reference: SketchReference,
        references entityID: SketchEntityID,
        allowed: Set<JoinedCurveEndpointKind>
    ) -> Bool {
        switch reference {
        case .lineStart(let referenceEntityID):
            referenceEntityID == entityID && allowed.contains(.lineStart)
        case .lineEnd(let referenceEntityID):
            referenceEntityID == entityID && allowed.contains(.lineEnd)
        case .arcStart(let referenceEntityID):
            referenceEntityID == entityID && allowed.contains(.arcStart)
        case .arcEnd(let referenceEntityID):
            referenceEntityID == entityID && allowed.contains(.arcEnd)
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            false
        }
    }

    private func joinedCurveGroupReference(
        _ reference: SketchReference,
        referencesAnyOf entityIDs: Set<SketchEntityID>,
        in sketch: Sketch
    ) -> Bool {
        guard let entityID = joinedCurveGroupReferenceEntityID(reference),
              entityIDs.contains(entityID),
              let entity = sketch.entities[entityID] else {
            return false
        }
        switch (reference, entity) {
        case (.lineStart(_), .line),
             (.lineEnd(_), .line),
             (.arcStart(_), .arc),
             (.arcEnd(_), .arc):
            return true
        case (.entity, _),
             (.circleCenter, _),
             (.circleRadius, _),
             (.arcCenter, _),
             (.arcRadius, _),
             (.splineControlPoint, _):
            return false
        case (.lineStart(_), _),
             (.lineEnd(_), _),
             (.arcStart(_), _),
             (.arcEnd(_), _):
            return false
        }
    }

    private func joinedCurveGroupReferenceEntityID(_ reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case .lineStart(let entityID),
             .lineEnd(let entityID),
             .arcStart(let entityID),
             .arcEnd(let entityID):
            return entityID
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            return nil
        }
    }

    private func validateConstructionPlanes() throws {
        var names: Set<String> = []
        for (sourceID, source) in constructionPlanes {
            guard source.id == sourceID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Construction plane source keys must match source IDs."
                )
            }
            try source.validate()
            let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Construction plane names must be unique."
                )
            }
        }
        if let activeConstructionPlaneID,
           constructionPlanes[activeConstructionPlaneID] == nil {
            throw DocumentValidationError.invalidProductMetadata(
                "The active construction plane must reference an existing construction plane source."
            )
        }
    }

    private func validateCurveCurvatureDisplays(against cadDocument: CADDocument) throws {
        for (componentID, display) in curveCurvatureDisplays {
            guard componentID == display.componentID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Curve curvature display keys must match display component IDs."
                )
            }
            try display.validate(against: cadDocument)
        }
    }

    private func validatePointDisplays(against cadDocument: CADDocument) throws {
        for (componentID, display) in pointDisplays {
            guard componentID == display.componentID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Point display keys must match display component IDs."
                )
            }
            try display.validate(against: cadDocument)
        }
    }

    private func validateSurfaceControlPointDisplays(against cadDocument: CADDocument) throws {
        for (id, display) in surfaceControlPointDisplays {
            guard id == display.id else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Surface control point display keys must match display IDs."
                )
            }
            try display.validate(against: cadDocument)
        }
    }

    private func validateMeasurements() throws {
        for (measurementID, measurement) in measurements {
            guard measurementID == measurement.id else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Measurement annotation keys must match annotation IDs."
                )
            }
            try measurement.validate()
            if let sceneNodeID = measurement.sceneNodeID {
                guard let sceneNode = sceneNodes[sceneNodeID],
                      sceneNode.object?.category == .annotation else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Measurement annotation scene nodes must point to annotation objects."
                    )
                }
            }
        }
    }

    private enum BridgeEndpointKind {
        case lineEndpoint
        case lineInterior
        case arcEndpoint
        case arcInterior
        case splineEndpoint
        case splineInterior
    }

    private func validateBridgeEndpoint(
        _ endpoint: BridgeCurveEndpoint,
        source: BridgeCurveSource,
        sketch: Sketch,
        cadDocument: CADDocument
    ) throws -> BridgeEndpointKind {
        if let parameter = endpoint.parameter {
            let resolvedParameter = try validateBridgeParameter(
                parameter,
                owner: "Bridge curve endpoint parameter",
                cadDocument: cadDocument
            )
            guard let entityID = bridgeEndpointEntityID(endpoint.reference),
                  entityID != source.entityID,
                  let entity = sketch.entities[entityID] else {
                throw invalidBridgeEndpointReference()
            }
            switch entity {
            case .line:
                return isEndpointParameter(resolvedParameter) ? .lineEndpoint : .lineInterior
            case .arc:
                return isEndpointParameter(resolvedParameter) ? .arcEndpoint : .arcInterior
            case .spline:
                return isEndpointParameter(resolvedParameter) ? .splineEndpoint : .splineInterior
            case .point,
                 .circle:
                throw invalidBridgeEndpointReference()
            }
        } else {
            switch endpoint.reference {
            case let .lineStart(entityID),
                 let .lineEnd(entityID):
                guard entityID != source.entityID,
                      case .line = sketch.entities[entityID] else {
                    throw invalidBridgeEndpointReference()
                }
                return .lineEndpoint
            case let .arcStart(entityID),
                 let .arcEnd(entityID):
                guard entityID != source.entityID,
                      case .arc = sketch.entities[entityID] else {
                    throw invalidBridgeEndpointReference()
                }
                return .arcEndpoint
            case let .splineControlPoint(entityID, index):
                guard entityID != source.entityID,
                      case .spline(let spline) = sketch.entities[entityID],
                      index == 0 || index == spline.controlPoints.count - 1 else {
                    throw invalidBridgeEndpointReference()
                }
                return .splineEndpoint
            case .entity,
                 .circleCenter,
                 .circleRadius,
                 .arcCenter,
                 .arcRadius:
                throw invalidBridgeEndpointReference()
            }
        }
    }

    private func validateBridgeEndpointContinuity(
        _ continuity: BridgeCurveEndpointContinuity,
        endpointKind: BridgeEndpointKind,
        owner: String
    ) throws {
        switch continuity {
        case .g0:
            return
        case .g1:
            guard endpointKind == .lineEndpoint || endpointKind == .splineEndpoint else {
                throw invalidBridgeContinuity(
                    "\(owner) G1 sources must use line or spline endpoints."
                )
            }
        case .g2:
            guard endpointKind == .splineEndpoint else {
                throw invalidBridgeContinuity(
                    "\(owner) G2 sources must use spline endpoints."
                )
            }
        case .g3:
            throw invalidBridgeContinuity(
                "\(owner) G3 is not supported by the current bridge source model."
            )
        }
    }

    private func validateBridgeTension(
        _ tension: BridgeCurveTension,
        owner: String,
        cadDocument: CADDocument
    ) throws {
        try validateBridgeTensionScalar(
            tension.first,
            owner: "\(owner) 1",
            cadDocument: cadDocument
        )
        try validateBridgeTensionScalar(
            tension.second,
            owner: "\(owner) 2",
            cadDocument: cadDocument
        )
        try validateBridgeTensionScalar(
            tension.third,
            owner: "\(owner) 3",
            cadDocument: cadDocument
        )
    }

    private func validateBridgeTensionScalar(
        _ expression: CADExpression,
        owner: String,
        cadDocument: CADDocument
    ) throws {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .scalar,
              quantity.value.isFinite,
              quantity.value > 0.0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "\(owner) must resolve to a positive finite scalar."
            )
        }
    }

    private func validateBridgeParameter(
        _ expression: CADExpression,
        owner: String,
        cadDocument: CADDocument
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .scalar,
              quantity.value.isFinite,
              quantity.value >= 0.0,
              quantity.value <= 1.0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "\(owner) must resolve to a finite scalar from 0 through 1."
            )
        }
        return quantity.value
    }

    private func bridgeEndpointEntityID(_ reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case let .entity(entityID),
             let .lineStart(entityID),
             let .lineEnd(entityID),
             let .arcStart(entityID),
             let .arcEnd(entityID),
             let .splineControlPoint(entityID, _):
            return entityID
        case .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return nil
        }
    }

    private func bridgeEndpointLocationSignature(_ endpoint: BridgeCurveEndpoint) -> String {
        "\(endpoint.reference)|\(String(describing: endpoint.parameter))"
    }

    private func isEndpointParameter(_ parameter: Double) -> Bool {
        parameter <= 1.0e-12 || parameter >= 1.0 - 1.0e-12
    }

    private func invalidBridgeEndpointReference() -> DocumentValidationError {
        DocumentValidationError.invalidProductMetadata(
            "Bridge curve endpoints must reference line, arc, or external spline curve positions in the same sketch."
        )
    }

    private func invalidBridgeContinuity(_ message: String) -> DocumentValidationError {
        DocumentValidationError.invalidProductMetadata(message)
    }

    private func visitSceneNode(
        _ sceneNodeID: SceneNodeID,
        visited: inout Set<SceneNodeID>,
        visiting: inout Set<SceneNodeID>,
        parentByChild: inout [SceneNodeID: SceneNodeID]
    ) throws {
        guard !visiting.contains(sceneNodeID) else {
            throw DocumentValidationError.invalidProductMetadata("Scene node hierarchy must not contain cycles.")
        }
        guard !visited.contains(sceneNodeID) else {
            return
        }
        guard let sceneNode = sceneNodes[sceneNodeID] else {
            throw DocumentValidationError.invalidProductMetadata("Scene node hierarchy references a missing node.")
        }

        visiting.insert(sceneNodeID)
        for childID in sceneNode.childIDs {
            if let existingParentID = parentByChild[childID], existingParentID != sceneNodeID {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene nodes must not have multiple parents."
                )
            }
            parentByChild[childID] = sceneNodeID
            try visitSceneNode(
                childID,
                visited: &visited,
                visiting: &visiting,
                parentByChild: &parentByChild
            )
        }
        visiting.remove(sceneNodeID)
        visited.insert(sceneNodeID)
    }

    private func validateComponentDefinitions() throws {
        var names: Set<String> = []
        for (definitionID, definition) in componentDefinitions {
            guard definition.id == definitionID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component definition keys must match definition IDs."
                )
            }
            let trimmedName = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component definition names must be unique."
                )
            }
            try definition.validate()
            for rootSceneNodeID in definition.rootSceneNodeIDs {
                guard sceneNodes[rootSceneNodeID] != nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Component definition root scene node references a missing node."
                    )
                }
                guard patternArraySourceID(containingOutputSceneNode: rootSceneNodeID) == nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Component definition root scene nodes must not reference source-owned pattern array outputs."
                    )
                }
            }
        }
    }

    private func patternArraySourceID(
        containingOutputSceneNode sceneNodeID: SceneNodeID
    ) -> PatternArraySourceID? {
        patternArrays.first { _, source in
            guard let rootNode = sceneNodes[source.rootSceneNodeID] else {
                return false
            }
            if source.rootSceneNodeID == sceneNodeID {
                return true
            }
            return rootNode.childIDs.contains { outputSceneNodeID in
                sceneSubtree(outputSceneNodeID, contains: sceneNodeID)
            }
        }?.key
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID
    ) -> Bool {
        var visitedSceneNodeIDs: Set<SceneNodeID> = []
        return sceneSubtree(
            rootSceneNodeID,
            contains: targetSceneNodeID,
            visitedSceneNodeIDs: &visitedSceneNodeIDs
        )
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        visitedSceneNodeIDs: inout Set<SceneNodeID>
    ) -> Bool {
        guard visitedSceneNodeIDs.insert(rootSceneNodeID).inserted else {
            return false
        }
        if rootSceneNodeID == targetSceneNodeID {
            return true
        }
        guard let sceneNode = sceneNodes[rootSceneNodeID] else {
            return false
        }
        return sceneNode.childIDs.contains { childID in
            sceneSubtree(
                childID,
                contains: targetSceneNodeID,
                visitedSceneNodeIDs: &visitedSceneNodeIDs
            )
        }
    }

    private func validateComponentInstances() throws {
        var names: Set<String> = []
        for (instanceID, instance) in componentInstances {
            guard instance.id == instanceID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component instance keys must match instance IDs."
                )
            }
            guard componentDefinitions[instance.definitionID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component instances must reference existing component definitions."
                )
            }
            let trimmedName = instance.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata("Component instance names must be unique.")
            }
            try instance.validate()
        }
    }

    private func validatePatternArrays(against cadDocument: CADDocument) throws {
        var names: Set<String> = []
        for (sourceID, source) in patternArrays {
            guard source.id == sourceID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Pattern array source keys must match source IDs."
                )
            }
            let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata("Pattern array source names must be unique.")
            }
            guard componentDefinitions[source.definitionID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Pattern array sources must reference an existing component definition."
                )
            }
            try source.validate()
        }

        for (_, source) in patternArrays {
            let expectedTransforms = try PatternArrayInstancePlanner().transforms(
                for: source.distribution,
                parameters: cadDocument.parameters,
                cadDocument: cadDocument
            )
            let rootSceneNodeID = source.rootSceneNodeID
            guard let rootNode = sceneNodes[rootSceneNodeID],
                  rootNode.reference == nil,
                  rootNode.object?.category == .group else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Pattern array root scene node must be a group node."
                )
            }
            switch source.outputMode {
            case .componentInstance:
                try validateComponentInstancePatternArray(
                    source: source,
                    rootNode: rootNode,
                    expectedTransforms: expectedTransforms
                )
            case .independentCopy:
                try validateIndependentCopyPatternArray(
                    source: source,
                    rootNode: rootNode,
                    expectedTransforms: expectedTransforms,
                    cadDocument: cadDocument
                )
            }
        }
    }

    private func validatePatternArrayOutputOwnership() throws {
        var sourceIDByOutputInstanceID: [ComponentInstanceID: PatternArraySourceID] = [:]
        var sourceIDByOutputSceneNodeID: [SceneNodeID: PatternArraySourceID] = [:]
        var sourceIDByOutputFeatureID: [FeatureID: PatternArraySourceID] = [:]
        for source in patternArrays.values {
            try validatePatternArrayOutputOwnership(
                source: source,
                sourceIDByOutputInstanceID: &sourceIDByOutputInstanceID,
                sourceIDByOutputSceneNodeID: &sourceIDByOutputSceneNodeID,
                sourceIDByOutputFeatureID: &sourceIDByOutputFeatureID
            )
        }
    }

    private func validatePatternArrayOutputOwnership(
        source: PatternArraySource,
        sourceIDByOutputInstanceID: inout [ComponentInstanceID: PatternArraySourceID],
        sourceIDByOutputSceneNodeID: inout [SceneNodeID: PatternArraySourceID],
        sourceIDByOutputFeatureID: inout [FeatureID: PatternArraySourceID]
    ) throws {
        switch source.outputMode {
        case .componentInstance:
            for instanceID in source.outputInstanceIDs {
                if let existingSourceID = sourceIDByOutputInstanceID[instanceID] {
                    throw DocumentValidationError.invalidProductMetadata(
                        """
                        Pattern array output component instances must be owned by exactly one pattern source; \
                        instance \(instanceID) is referenced by \(existingSourceID) and \(source.id).
                        """
                    )
                }
                sourceIDByOutputInstanceID[instanceID] = source.id
            }
        case .independentCopy:
            for sceneNodeID in source.outputSceneNodeIDs {
                if let existingSourceID = sourceIDByOutputSceneNodeID[sceneNodeID] {
                    throw DocumentValidationError.invalidProductMetadata(
                        """
                        Independent-copy pattern array output scene nodes must be owned by exactly one pattern source; \
                        scene node \(sceneNodeID) is referenced by \(existingSourceID) and \(source.id).
                        """
                    )
                }
                sourceIDByOutputSceneNodeID[sceneNodeID] = source.id
            }
            for featureID in source.outputFeatureIDs {
                if let existingSourceID = sourceIDByOutputFeatureID[featureID] {
                    throw DocumentValidationError.invalidProductMetadata(
                        """
                        Independent-copy pattern array output features must be owned by exactly one pattern source; \
                        feature \(featureID) is referenced by \(existingSourceID) and \(source.id).
                        """
                    )
                }
                sourceIDByOutputFeatureID[featureID] = source.id
            }
        }
    }

    private func validateComponentInstancePatternArray(
        source: PatternArraySource,
        rootNode: SceneNode,
        expectedTransforms: [Transform3D]
    ) throws {
        guard expectedTransforms.count == source.outputInstanceIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array output instances must match the source distribution count."
            )
        }
        for instanceID in source.outputInstanceIDs {
            guard let instance = componentInstances[instanceID] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Pattern array output instances must exist."
                )
            }
            guard instance.definitionID == source.definitionID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Pattern array output instances must use the source component definition."
                )
            }
        }
        for (index, instanceID) in source.outputInstanceIDs.enumerated() {
            guard let instance = componentInstances[instanceID],
                  transform(instance.localTransform, approximatelyEquals: expectedTransforms[index]) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Pattern array output instance transforms must match the source distribution."
                )
            }
        }
        guard rootNode.childIDs.count == source.outputInstanceIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array root scene node must contain exactly its output instance scene nodes."
            )
        }
        let outputInstanceIDs = Set(source.outputInstanceIDs)
        var childInstanceIDs: [ComponentInstanceID] = []
        childInstanceIDs.reserveCapacity(rootNode.childIDs.count)
        for childID in rootNode.childIDs {
            guard let childNode = sceneNodes[childID],
                  childNode.reference?.kind == .componentInstance,
                  let componentInstanceID = childNode.reference?.componentInstanceID,
                  outputInstanceIDs.contains(componentInstanceID) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Pattern array root scene node children must be output component instance nodes."
                )
            }
            guard transform(childNode.localTransform, approximatelyEquals: .identity) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Pattern array output scene node transforms must be identity."
                )
            }
            childInstanceIDs.append(componentInstanceID)
        }
        guard Set(childInstanceIDs) == outputInstanceIDs,
              childInstanceIDs.count == outputInstanceIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array root scene node must map one child to each output instance."
            )
        }
    }

    private func validateIndependentCopyPatternArray(
        source: PatternArraySource,
        rootNode: SceneNode,
        expectedTransforms: [Transform3D],
        cadDocument: CADDocument
    ) throws {
        guard expectedTransforms.count == source.outputSceneNodeIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Independent-copy pattern array output scene nodes must match the source distribution count."
            )
        }
        guard rootNode.childIDs == source.outputSceneNodeIDs else {
            throw DocumentValidationError.invalidProductMetadata(
                "Independent-copy pattern array root scene node must contain exactly its output scene nodes."
            )
        }
        let ownedFeatureIDs = Set(source.outputFeatureIDs)
        var outputReferencedFeatureIDs: Set<FeatureID> = []
        for featureID in source.outputFeatureIDs {
            guard cadDocument.designGraph.nodes[featureID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Independent-copy pattern array output features must exist."
                )
            }
        }
        for (index, outputSceneNodeID) in source.outputSceneNodeIDs.enumerated() {
            guard let outputNode = sceneNodes[outputSceneNodeID],
                  outputNode.reference == nil,
                  outputNode.object?.category == .group else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Independent-copy pattern array outputs must be group scene nodes."
                )
            }
            guard transform(outputNode.localTransform, approximatelyEquals: expectedTransforms[index]) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Independent-copy pattern array output transforms must match the source distribution."
                )
            }
            let descendantFeatureIDs = referencedFeatureIDs(inSceneSubtreeRootedAt: outputSceneNodeID)
            guard !descendantFeatureIDs.isEmpty,
                  descendantFeatureIDs.isSubset(of: ownedFeatureIDs) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Independent-copy pattern array output scene nodes must reference only owned cloned features."
                )
            }
            outputReferencedFeatureIDs.formUnion(descendantFeatureIDs)
        }
        guard dependencyFeatureClosure(
            from: outputReferencedFeatureIDs,
            cadDocument: cadDocument
        ) == ownedFeatureIDs else {
            throw DocumentValidationError.invalidProductMetadata(
                "Independent-copy pattern array output features must exactly match generated output dependencies."
            )
        }
    }

    private func dependencyFeatureClosure(
        from seedFeatureIDs: Set<FeatureID>,
        cadDocument: CADDocument
    ) -> Set<FeatureID> {
        var featureIDs = seedFeatureIDs
        var pendingFeatureIDs = Array(seedFeatureIDs)
        while let featureID = pendingFeatureIDs.popLast() {
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                continue
            }
            for input in feature.inputs where featureIDs.insert(input.featureID).inserted {
                pendingFeatureIDs.append(input.featureID)
            }
        }
        return featureIDs
    }

    private func referencedFeatureIDs(inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID) -> Set<FeatureID> {
        var featureIDs: Set<FeatureID> = []
        collectReferencedFeatureIDs(rootSceneNodeID, featureIDs: &featureIDs)
        return featureIDs
    }

    private func collectReferencedFeatureIDs(
        _ sceneNodeID: SceneNodeID,
        featureIDs: inout Set<FeatureID>
    ) {
        guard let sceneNode = sceneNodes[sceneNodeID] else {
            return
        }
        if let featureID = sceneNode.reference?.featureID {
            featureIDs.insert(featureID)
        }
        if let featureID = sceneNode.object?.sourceFeatureID {
            featureIDs.insert(featureID)
        }
        if let featureID = sceneNode.object?.sourceSection?.featureID {
            featureIDs.insert(featureID)
        }
        for childID in sceneNode.childIDs {
            collectReferencedFeatureIDs(childID, featureIDs: &featureIDs)
        }
    }

    private func transform(
        _ lhs: Transform3D,
        approximatelyEquals rhs: Transform3D
    ) -> Bool {
        let left = lhs.matrix.values
        let right = rhs.matrix.values
        guard left.count == right.count else {
            return false
        }
        for index in left.indices {
            guard abs(left[index] - right[index]) <= 1.0e-9 else {
                return false
            }
        }
        return true
    }

    private func validateValidationRules() throws {
        var names: Set<String> = []
        for (ruleID, rule) in validationRules {
            guard rule.id == ruleID else {
                throw DocumentValidationError.invalidProductMetadata("Validation rule keys must match rule IDs.")
            }
            let trimmedName = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata("Validation rule names must be unique.")
            }
            try rule.validate()
        }
    }

    private func validateExportPresets() throws {
        var names: Set<String> = []
        for (presetID, preset) in exportPresets {
            guard preset.id == presetID else {
                throw DocumentValidationError.invalidProductMetadata("Export preset keys must match preset IDs.")
            }
            let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata("Export preset names must be unique.")
            }
            try preset.validate()
            for ruleID in preset.validationRuleIDs {
                guard validationRules[ruleID] != nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Export presets must reference existing validation rules."
                    )
                }
            }
        }
    }

    private func validateTemplateDefaults() throws {
        try templateDefaults.validate()
        if let defaultMaterialID = templateDefaults.defaultMaterialID {
            guard materialLibrary.materials[defaultMaterialID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Template default material must exist in the material library."
                )
            }
        }
        for ruleID in templateDefaults.validationRuleIDs {
            guard validationRules[ruleID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Template defaults must reference existing validation rules."
                )
            }
        }
        for presetID in templateDefaults.exportPresetIDs {
            guard exportPresets[presetID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Template defaults must reference existing export presets."
                )
            }
        }
    }
}

private extension FeatureNode {
    var producesSceneGeometry: Bool {
        outputs.contains { output in
            output.role == .body || output.role == .sheet
        }
    }
}
