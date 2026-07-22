import Foundation
import SwiftCAD
import CADModeling
import RupaCoreTypes

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
        case .surface(.parameter(let parameterReference)):
            try validateSurfaceParameterReference(parameterReference, in: document)
        case .surface(.span(let spanReference)):
            try validateSurfaceSpanReference(spanReference, in: document)
        case .surface(.knot(let knotReference)):
            try validateSurfaceKnotReference(knotReference, in: document)
        case .surface(.trim(let trimReference)):
            try validateSurfaceTrimReference(trimReference, in: document)
        case .surface(.trimSpan(let trimSpanReference)):
            try validateSurfaceTrimSpanReference(trimSpanReference, in: document)
        case .surface(.trimKnot(let trimKnotReference)):
            try validateSurfaceTrimKnotReference(trimKnotReference, in: document)
        case .sketchPoint(let point):
            try validateSketchPointReference(point, in: document)
        case .subshape, .edge, .curve, .surface(_):
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

    private func validateSurfaceParameterReference(
        _ reference: SurfaceParameterReference,
        in document: DesignDocument
    ) throws {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection surface parameter reference is invalid: \(error)."
            )
        }
        let surface = try directBSplineSurface(
            for: reference.surface,
            in: document,
            owner: "Selection surface parameter reference"
        )
        let uDomain = try bSplineSurfaceParameterDomain(
            knots: surface.uKnots,
            degree: surface.uDegree,
            owner: "Selection surface parameter reference"
        )
        let vDomain = try bSplineSurfaceParameterDomain(
            knots: surface.vKnots,
            degree: surface.vDegree,
            owner: "Selection surface parameter reference"
        )
        guard reference.u >= uDomain.lower - 1.0e-9,
              reference.u <= uDomain.upper + 1.0e-9,
              reference.v >= vDomain.lower - 1.0e-9,
              reference.v <= vDomain.upper + 1.0e-9 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection surface parameter reference is outside the B-spline surface domain."
            )
        }
    }

    private func validateSurfaceSpanReference(
        _ reference: SurfaceSpanReference,
        in document: DesignDocument
    ) throws {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection surface span reference is invalid: \(error)."
            )
        }
        let surface = try directBSplineSurface(
            for: reference.surface,
            in: document,
            owner: "Selection surface span reference"
        )
        let spanCount = bSplineNonDegenerateSpanCount(
            knots: bSplineSurfaceKnots(reference.direction, in: surface),
            degree: bSplineSurfaceDegree(reference.direction, in: surface)
        )
        guard reference.spanIndex < spanCount else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection surface span reference points to a missing B-spline surface span."
            )
        }
    }

    private func validateSurfaceKnotReference(
        _ reference: SurfaceKnotReference,
        in document: DesignDocument
    ) throws {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection surface knot reference is invalid: \(error)."
            )
        }
        let surface = try directBSplineSurface(
            for: reference.surface,
            in: document,
            owner: "Selection surface knot reference"
        )
        let knots = bSplineSurfaceKnots(reference.direction, in: surface)
        guard knots.indices.contains(reference.knotIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection surface knot reference points to a missing B-spline surface knot."
            )
        }
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
        case .constructionPlane(let sourceID):
            guard reference?.kind == .construction,
                  reference?.constructionPlaneID == sourceID else {
                return false
            }
            return document.productMetadata.constructionPlanes[sourceID] != nil
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
        case .object, .sketchEntity, .region, .constructionPlane:
            componentID = nil
        }
        guard let componentID,
              componentID.isStableTopology else {
            return nil
        }
        do {
            return try componentID.stableTopologyReference(
                operationName: "Selection"
            ).subshapeID.featureID
        } catch {
            return nil
        }
    }

    private func validateSurfaceTrimReference(
        _ reference: SurfaceTrimReference,
        in document: DesignDocument
    ) throws {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection surface trim reference is invalid: \(error)."
            )
        }
        let featureID = try surfaceFeatureID(
            from: reference.surface.subshape,
            owner: "Selection surface trim reference"
        )
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .surfaceTrim(surfaceTrimFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection surface trim reference could not resolve its direct B-spline surface feature."
            )
        }
        let trimLoops = surfaceTrimFeature.loops
        guard trimLoops.indices.contains(reference.loopIndex),
              trimLoops[reference.loopIndex].parameterCurves.indices.contains(reference.edgeIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection surface trim reference points to a missing trim edge."
            )
        }
    }

    private func validateSurfaceTrimSpanReference(
        _ reference: SurfaceTrimSpanReference,
        in document: DesignDocument
    ) throws {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection surface trim span reference is invalid: \(error)."
            )
        }
        let curve = try surfaceTrimParameterCurve(
            for: reference.trim,
            in: document,
            owner: "Selection surface trim span reference"
        )
        guard case let .bSpline(bSpline) = curve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection surface trim span reference requires a B-spline trim p-curve."
            )
        }
        let spanCount = bSplineNonDegenerateSpanCount(knots: bSpline.knots, degree: bSpline.degree)
        guard reference.spanIndex < spanCount else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection surface trim span reference points to a missing trim p-curve span."
            )
        }
    }

    private func validateSurfaceTrimKnotReference(
        _ reference: SurfaceTrimKnotReference,
        in document: DesignDocument
    ) throws {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection surface trim knot reference is invalid: \(error)."
            )
        }
        let curve = try surfaceTrimParameterCurve(
            for: reference.trim,
            in: document,
            owner: "Selection surface trim knot reference"
        )
        guard case let .bSpline(bSpline) = curve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection surface trim knot reference requires a B-spline trim p-curve."
            )
        }
        guard bSpline.knots.indices.contains(reference.knotIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection surface trim knot reference points to a missing trim p-curve knot."
            )
        }
    }

    private func surfaceTrimParameterCurve(
        for reference: SurfaceTrimReference,
        in document: DesignDocument,
        owner: String
    ) throws -> SurfaceParameterCurve {
        try validateSurfaceTrimReference(reference, in: document)
        let featureID = try surfaceFeatureID(
            from: reference.surface.subshape,
            owner: owner
        )
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .surfaceTrim(surfaceTrimFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) could not resolve its direct B-spline surface feature."
            )
        }
        return surfaceTrimFeature.loops[reference.loopIndex].parameterCurves[reference.edgeIndex]
    }

    private func bSplineNonDegenerateSpanCount(knots: [Double], degree: Int) -> Int {
        let lowerIndex = degree
        let upperIndex = knots.count - degree - 1
        guard lowerIndex < upperIndex else {
            return 0
        }
        var count = 0
        for index in lowerIndex..<upperIndex where knots[index + 1] > knots[index] {
            count += 1
        }
        return count
    }

    private func directBSplineSurface(
        for reference: SurfaceReference,
        in document: DesignDocument,
        owner: String
    ) throws -> BSplineSurface3D {
        let featureID = try sourceOwnedDirectBSplineSurfaceFeatureID(
            from: reference.subshape,
            owner: owner
        )
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) could not resolve its direct B-spline surface feature."
            )
        }
        return surfaceFeature.surface
    }

    private func bSplineSurfaceKnots(
        _ direction: SurfaceParameterDirection,
        in surface: BSplineSurface3D
    ) -> [Double] {
        switch direction {
        case .u:
            return surface.uKnots
        case .v:
            return surface.vKnots
        }
    }

    private func bSplineSurfaceDegree(
        _ direction: SurfaceParameterDirection,
        in surface: BSplineSurface3D
    ) -> Int {
        switch direction {
        case .u:
            return surface.uDegree
        case .v:
            return surface.vDegree
        }
    }

    private func bSplineSurfaceParameterDomain(
        knots: [Double],
        degree: Int,
        owner: String
    ) throws -> (lower: Double, upper: Double) {
        let lowerIndex = degree
        let upperIndex = knots.count - degree - 1
        guard knots.indices.contains(lowerIndex),
              knots.indices.contains(upperIndex),
              knots[lowerIndex] <= knots[upperIndex] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) could not resolve the B-spline surface parameter domain."
            )
        }
        return (knots[lowerIndex], knots[upperIndex])
    }

    private func sourceOwnedDirectBSplineSurfaceFeatureID(
        from reference: StableSubshapeReference,
        owner: String
    ) throws -> FeatureID {
        let featureID = try surfaceFeatureID(from: reference, owner: owner)
        let subshapeID = reference.subshapeID
        guard subshapeID.role == "bSplineSurface.patch:0:face",
              subshapeID.ordinal == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a source-owned direct B-spline surface face reference."
            )
        }
        return featureID
    }

    private func surfaceFeatureID(
        from reference: StableSubshapeReference,
        owner: String
    ) throws -> FeatureID {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a valid stable surface reference: \(error)."
            )
        }
        guard case .face = reference.geometrySignature else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a stable face reference."
            )
        }
        return reference.subshapeID.featureID
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
            let profiles = try SketchProfileExtractor(
                tolerance: document.modelingSettings.tolerance
            ).extractProfiles(
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
