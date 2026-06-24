import Foundation
import SwiftCAD

public struct SelectionModel: Codable, Equatable, Sendable {
    public private(set) var selectedTargets: [SelectionTarget]
    public private(set) var hoveredTarget: SelectionTarget?

    public var selectedSceneNodeIDs: [SceneNodeID] {
        Self.sceneNodeIDs(from: selectedTargets)
    }

    public var hoveredSceneNodeID: SceneNodeID? {
        hoveredTarget?.sceneNodeID
    }

    public var primarySceneNodeID: SceneNodeID? {
        primaryTarget?.sceneNodeID
    }

    public var primaryTarget: SelectionTarget? {
        selectedTargets.last
    }

    public init(
        selectedTargets: [SelectionTarget] = [],
        hoveredTarget: SelectionTarget? = nil
    ) {
        self.selectedTargets = Self.uniqueTargets(selectedTargets)
        self.hoveredTarget = hoveredTarget
    }

    public static var empty: SelectionModel {
        SelectionModel()
    }

    public func containsSceneNode(_ id: SceneNodeID) -> Bool {
        selectedSceneNodeIDs.contains(id)
    }

    public func containsTarget(_ target: SelectionTarget) -> Bool {
        selectedTargets.contains(target)
    }

    public mutating func selectSceneNode(
        _ id: SceneNodeID?,
        in document: DesignDocument
    ) throws {
        guard let id else {
            clearSelection()
            return
        }
        try validateSceneNode(id, in: document)
        selectValidatedTargets([SelectionTarget(sceneNodeID: id)])
    }

    public mutating func selectSceneNodes(
        _ ids: [SceneNodeID],
        in document: DesignDocument
    ) throws {
        let targets = ids.map { id in
            SelectionTarget(sceneNodeID: id)
        }
        try selectTargets(targets, in: document)
    }

    public mutating func selectTarget(
        _ target: SelectionTarget?,
        in document: DesignDocument
    ) throws {
        guard let target else {
            clearSelection()
            return
        }
        try selectTargets([target], in: document)
    }

    public mutating func selectTargets(
        _ targets: [SelectionTarget],
        in document: DesignDocument
    ) throws {
        let uniqueTargets = Self.uniqueTargets(targets)
        for target in uniqueTargets {
            try validateTarget(target, in: document)
        }
        selectValidatedTargets(uniqueTargets)
    }

    public mutating func hoverSceneNode(
        _ id: SceneNodeID?,
        in document: DesignDocument
    ) throws {
        guard let id else {
            clearHover()
            return
        }
        try validateSceneNode(id, in: document)
        setValidatedHover(SelectionTarget(sceneNodeID: id))
    }

    public mutating func hoverTarget(
        _ target: SelectionTarget?,
        in document: DesignDocument
    ) throws {
        guard let target else {
            clearHover()
            return
        }
        try validateTarget(target, in: document)
        setValidatedHover(target)
    }

    public mutating func clearSelection() {
        selectedTargets = []
    }

    public mutating func clearHover() {
        hoveredTarget = nil
    }

    public mutating func pruneMissingReferences(in document: DesignDocument) {
        selectedTargets = selectedTargets.filter { target in
            isTargetValid(target, in: document)
        }
        if let hoveredTarget,
           !isTargetValid(hoveredTarget, in: document) {
            clearHover()
        }
    }

    public func selectedSceneNodeReferences(in document: DesignDocument) -> [SceneNodeReference] {
        selectedSceneNodeIDs.compactMap { id in
            document.productMetadata.sceneNodes[id]?.reference
        }
    }

    private func validateSceneNode(
        _ id: SceneNodeID,
        in document: DesignDocument
    ) throws {
        guard document.productMetadata.sceneNodes[id] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection references a missing scene node."
            )
        }
    }

    private func validateTarget(
        _ target: SelectionTarget,
        in document: DesignDocument
    ) throws {
        guard let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection references a missing scene node."
            )
        }
        guard isComponent(target.component, compatibleWith: sceneNode.reference, in: document) else {
            throw incompatibleTargetError()
        }
    }

    private func incompatibleTargetError() -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "Selection target is not compatible with the scene node."
        )
    }

    private func isTargetValid(
        _ target: SelectionTarget,
        in document: DesignDocument
    ) -> Bool {
        guard let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID] else {
            return false
        }
        return isComponent(target.component, compatibleWith: sceneNode.reference, in: document)
    }

    private func isComponent(
        _ component: SelectionComponent,
        compatibleWith reference: SceneNodeReference?,
        in document: DesignDocument
    ) -> Bool {
        switch component {
        case .object:
            return true
        case .face, .edge, .vertex:
            if reference?.kind == .body {
                return true
            }
            return isComponentInstanceSubobject(
                component,
                compatibleWith: reference,
                in: document
            )
        case .sketchEntity(let componentID):
            guard reference?.kind == .sketch,
                  let featureID = reference?.featureID,
                  let sketchReference = componentID.sketchEntityBaseReference,
                  sketchReference.featureID == featureID,
                  let feature = document.cadDocument.designGraph.nodes[featureID],
                  case .sketch(let sketch) = feature.operation else {
                return false
            }
            return isSketchComponent(componentID, validIn: sketch)
        case .region(let componentID):
            guard reference?.kind == .sketch,
                  let featureID = reference?.featureID,
                  let regionReference = componentID.profileRegionReference,
                  regionReference.featureID == featureID,
                  let feature = document.cadDocument.designGraph.nodes[featureID],
                  feature.outputs.contains(where: { $0.role == .profile }),
                  case .sketch(let sketch) = feature.operation else {
                return false
            }
            return hasProfileRegion(
                regionReference.profileIndex,
                in: sketch,
                sourceFeatureID: featureID,
                document: document
            )
        }
    }

    private func isComponentInstanceSubobject(
        _ component: SelectionComponent,
        compatibleWith reference: SceneNodeReference?,
        in document: DesignDocument
    ) -> Bool {
        guard reference?.kind == .componentInstance,
              let componentInstanceID = reference?.componentInstanceID,
              let instance = document.productMetadata.componentInstances[componentInstanceID],
              let definition = document.productMetadata.componentDefinitions[instance.definitionID] else {
            return false
        }
        let preferredFeatureID = sourceFeatureID(for: component)
        let bodyFeatureIDs = Set(
            ComponentDefinitionSceneResolver().bodySceneNodeIDs(
                in: definition,
                preferredFeatureID: preferredFeatureID,
                metadata: document.productMetadata
            ).compactMap { sceneNodeID in
                document.productMetadata.sceneNodes[sceneNodeID]?.reference?.featureID
            }
        )
        if bodyFeatureIDs.isEmpty {
            return false
        }
        if let preferredFeatureID {
            return bodyFeatureIDs.contains(preferredFeatureID)
        }
        return bodyFeatureIDs.count == 1
    }

    private func sourceFeatureID(for component: SelectionComponent) -> FeatureID? {
        let componentID: SelectionComponentID?
        switch component {
        case .face(let id), .edge(let id), .vertex(let id):
            componentID = id
        case .object, .sketchEntity, .region:
            componentID = nil
        }
        guard let persistentName = componentID?.generatedTopologyPersistentName else {
            return nil
        }
        let parsedName: PersistentName
        do {
            parsedName = try GeneratedTopologyPersistentNameParser().parse(
                persistentName,
                operationName: "Selection"
            )
        } catch {
            return nil
        }
        for component in parsedName.components {
            if case .feature(let featureID) = component {
                return featureID
            }
        }
        return nil
    }

    private func isSketchComponent(
        _ componentID: SelectionComponentID,
        validIn sketch: Sketch
    ) -> Bool {
        if let reference = componentID.sketchEntityReference {
            return sketch.entities[reference.entityID] != nil
        }
        if let reference = componentID.sketchPointHandleReference,
           let entity = sketch.entities[reference.entityID] {
            return isSketchPointHandle(reference.handle, validFor: entity)
        }
        if let reference = componentID.sketchControlPointReference,
           let entity = sketch.entities[reference.entityID],
           case .spline(let spline) = entity {
            return spline.controlPoints.indices.contains(reference.index)
        }
        return false
    }

    private func isSketchPointHandle(
        _ handle: SketchEntityPointHandle,
        validFor entity: SketchEntity
    ) -> Bool {
        switch (handle, entity) {
        case (.point, .point),
             (.lineStart, .line),
             (.lineEnd, .line),
             (.circleCenter, .circle),
             (.arcCenter, .arc),
             (.arcStart, .arc),
             (.arcEnd, .arc):
            return true
        default:
            return false
        }
    }

    private func hasProfileRegion(
        _ profileIndex: Int,
        in sketch: Sketch,
        sourceFeatureID: FeatureID,
        document: DesignDocument
    ) -> Bool {
        do {
            let resolvedParameters = try ParameterResolver().resolve(document.cadDocument.parameters)
            let profiles = try SketchProfileExtractor().extractProfiles(
                from: sketch,
                sourceFeatureID: sourceFeatureID,
                parameters: resolvedParameters
            )
            return profiles.indices.contains(profileIndex)
        } catch {
            return false
        }
    }

    private mutating func selectValidatedTargets(_ targets: [SelectionTarget]) {
        selectedTargets = Self.uniqueTargets(targets)
    }

    private mutating func setValidatedHover(_ target: SelectionTarget) {
        hoveredTarget = target
    }

    private static func uniqueTargets(_ targets: [SelectionTarget]) -> [SelectionTarget] {
        var uniqueTargets: [SelectionTarget] = []
        var seenTargets: Set<SelectionTarget> = []
        for target in targets {
            guard seenTargets.insert(target).inserted else {
                continue
            }
            uniqueTargets.append(target)
        }
        return uniqueTargets
    }

    private static func sceneNodeIDs(from targets: [SelectionTarget]) -> [SceneNodeID] {
        uniqueSceneNodeIDs(targets.map(\.sceneNodeID))
    }

    private static func uniqueSceneNodeIDs(_ ids: [SceneNodeID]) -> [SceneNodeID] {
        var uniqueIDs: [SceneNodeID] = []
        var seenIDs: Set<SceneNodeID> = []
        for id in ids {
            guard seenIDs.insert(id).inserted else {
                continue
            }
            uniqueIDs.append(id)
        }
        return uniqueIDs
    }
}
