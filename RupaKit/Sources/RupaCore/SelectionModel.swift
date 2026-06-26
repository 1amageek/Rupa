import Foundation
import SwiftCAD

public struct SelectionModel: Codable, Equatable, Sendable {
    public private(set) var selectedTargets: [SelectionTarget]
    public private(set) var selectedReferences: [SelectionReference]
    public private(set) var hoveredTarget: SelectionTarget?
    public private(set) var hoveredReference: SelectionReference?

    private enum CodingKeys: String, CodingKey {
        case selectedTargets
        case selectedReferences
        case hoveredTarget
        case hoveredReference
    }

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

    public var primaryReference: SelectionReference? {
        selectedReferences.last
    }

    public init(
        selectedTargets: [SelectionTarget] = [],
        selectedReferences: [SelectionReference] = [],
        hoveredTarget: SelectionTarget? = nil,
        hoveredReference: SelectionReference? = nil
    ) {
        self.selectedTargets = Self.uniqueTargets(selectedTargets)
        self.selectedReferences = Self.uniqueReferences(selectedReferences)
        self.hoveredTarget = hoveredTarget
        self.hoveredReference = hoveredReference
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectedTargets: try container.decodeIfPresent(
                [SelectionTarget].self,
                forKey: .selectedTargets
            ) ?? [],
            selectedReferences: try container.decodeIfPresent(
                [SelectionReference].self,
                forKey: .selectedReferences
            ) ?? [],
            hoveredTarget: try container.decodeIfPresent(
                SelectionTarget.self,
                forKey: .hoveredTarget
            ),
            hoveredReference: try container.decodeIfPresent(
                SelectionReference.self,
                forKey: .hoveredReference
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedTargets, forKey: .selectedTargets)
        try container.encode(selectedReferences, forKey: .selectedReferences)
        try container.encodeIfPresent(hoveredTarget, forKey: .hoveredTarget)
        try container.encodeIfPresent(hoveredReference, forKey: .hoveredReference)
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

    public func containsReference(_ reference: SelectionReference) -> Bool {
        selectedReferences.contains(reference)
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

    public mutating func selectReference(
        _ reference: SelectionReference?,
        in document: DesignDocument
    ) throws {
        guard let reference else {
            clearSelection()
            return
        }
        try selectReferences([reference], in: document)
    }

    public mutating func selectReferences(
        _ references: [SelectionReference],
        in document: DesignDocument
    ) throws {
        let uniqueReferences = Self.uniqueReferences(references)
        for reference in uniqueReferences {
            try validateReference(reference, in: document)
        }
        selectValidatedReferences(uniqueReferences)
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

    public mutating func hoverReference(
        _ reference: SelectionReference?,
        in document: DesignDocument
    ) throws {
        guard let reference else {
            clearHover()
            return
        }
        try validateReference(reference, in: document)
        setValidatedHoverReference(reference)
    }

    public mutating func clearSelection() {
        selectedTargets = []
        selectedReferences = []
    }

    public mutating func clearHover() {
        hoveredTarget = nil
        hoveredReference = nil
    }

    public mutating func pruneMissingReferences(in document: DesignDocument) {
        selectedTargets = selectedTargets.filter { target in
            isTargetValid(target, in: document)
        }
        selectedReferences = selectedReferences.filter { reference in
            isReferenceValid(reference, in: document)
        }
        if let hoveredTarget,
           !isTargetValid(hoveredTarget, in: document) {
            clearHover()
        }
        if let hoveredReference,
           !isReferenceValid(hoveredReference, in: document) {
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

    private func validateReference(
        _ reference: SelectionReference,
        in document: DesignDocument
    ) throws {
        switch reference {
        case .surface(.controlPoint):
            _ = try SurfaceControlPointSelectionTargetResolver()
                .validateDisplayTarget(for: reference, in: document)
        case .sketchPoint(let point):
            try validateSketchPointReference(point, in: document)
        case .topology, .edge, .curve, .surface(_):
            throw EditorError(
                code: .commandInvalid,
                message: "Selection reference is not selectable in the viewport yet."
            )
        }
    }

    private func validateSketchPointReference(
        _ reference: SketchPointSelectionReference,
        in document: DesignDocument
    ) throws {
        guard let feature = document.cadDocument.designGraph.nodes[reference.featureID],
              case let .sketch(sketch) = feature.operation,
              case .point = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection sketch point reference could not resolve its source sketch point."
            )
        }
        let hasSceneNode = document.productMetadata.sceneNodes.values.contains { node in
            node.reference == .sketch(reference.featureID)
        }
        guard hasSceneNode else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection sketch point reference requires a visible source sketch scene node."
            )
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

    private func isReferenceValid(
        _ reference: SelectionReference,
        in document: DesignDocument
    ) -> Bool {
        do {
            try validateReference(reference, in: document)
            return true
        } catch {
            return false
        }
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
        selectedReferences = []
    }

    private mutating func selectValidatedReferences(_ references: [SelectionReference]) {
        selectedTargets = []
        selectedReferences = Self.uniqueReferences(references)
    }

    private mutating func setValidatedHover(_ target: SelectionTarget) {
        hoveredTarget = target
        hoveredReference = nil
    }

    private mutating func setValidatedHoverReference(_ reference: SelectionReference) {
        hoveredTarget = nil
        hoveredReference = reference
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

    private static func uniqueReferences(_ references: [SelectionReference]) -> [SelectionReference] {
        var uniqueReferences: [SelectionReference] = []
        var seenReferences: Set<SelectionReference> = []
        for reference in references {
            guard seenReferences.insert(reference).inserted else {
                continue
            }
            uniqueReferences.append(reference)
        }
        return uniqueReferences
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
