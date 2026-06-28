import RupaCore
import RupaRendering

struct WorkspaceSelectionTargetResolver {
    var document: DesignDocument
    var sceneBrowserRows: [SceneBrowserRow]
    var selectionScope: WorkspaceSelectionScope
    var objectRegistry: ObjectTypeRegistry

    func selectionTarget(for hit: ViewportHit) -> SelectionTarget? {
        guard let sceneNodeID = sceneNodeID(for: hit) else {
            return nil
        }
        if let component = directSelectionComponent(for: hit) {
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        }

        switch selectionScope {
        case .object:
            return SelectionTarget(sceneNodeID: sceneNodeID)
        case .face:
            guard let component = faceSelectionComponent(for: hit, sceneNodeID: sceneNodeID) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        case .edge:
            guard let component = edgeSelectionComponent(for: hit, sceneNodeID: sceneNodeID) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        case .vertex:
            guard let component = vertexSelectionComponent(for: hit, sceneNodeID: sceneNodeID) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        case .region:
            guard let component = directSelectionComponent(for: hit) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        case .sketchEntity:
            guard let component = sketchEntitySelectionComponent(for: hit) else {
                return nil
            }
            return SelectionTarget(sceneNodeID: sceneNodeID, component: component)
        }
    }

    func selectionTargets(for hits: [ViewportHit]) -> [SelectionTarget] {
        switch selectionScope {
        case .object:
            uniqueObjectTargets(for: hits)
        case .sketchEntity:
            uniqueSketchEntityTargets(for: hits)
        case .face,
             .edge,
             .vertex,
             .region:
            uniqueSelectionTargets(for: hits)
        }
    }

    func sceneNodeID(for hit: ViewportHit) -> SceneNodeID? {
        if let sceneNodeID = hit.sceneNodeID,
           document.productMetadata.sceneNodes[sceneNodeID] != nil {
            return sceneNodeID
        }
        let expectedKind: SceneNodeReference.Kind = switch hit.kind {
        case .sketch:
            .sketch
        case .body:
            .body
        }

        for row in sceneBrowserRows {
            guard let reference = document.productMetadata.sceneNodes[row.id]?.reference else {
                continue
            }
            if reference.kind == expectedKind, reference.featureID == hit.featureID {
                return row.id
            }
        }

        for row in sceneBrowserRows {
            guard let reference = document.productMetadata.sceneNodes[row.id]?.reference else {
                continue
            }
            if reference.featureID == hit.featureID {
                return row.id
            }
        }
        return nil
    }

    private func directSelectionComponent(for hit: ViewportHit) -> SelectionComponent? {
        guard let component = hit.selectionComponent else {
            return nil
        }
        switch (selectionScope, component) {
        case (.face, .face(_)),
             (.edge, .edge(_)),
             (.vertex, .vertex(_)),
             (.region, .region(_)),
             (.sketchEntity, .sketchEntity(_)):
            return component
        case (.object, _):
            return nil
        default:
            return nil
        }
    }

    private func sketchEntitySelectionComponent(for hit: ViewportHit) -> SelectionComponent? {
        guard hit.kind == .sketch,
              let sketchEntityID = hit.sketchEntityID else {
            return nil
        }
        if let controlPointIndex = hit.sketchControlPointIndex {
            return .sketchEntity(
                .sketchControlPoint(
                    featureID: hit.featureID,
                    entityID: sketchEntityID,
                    index: controlPointIndex
                )
            )
        }
        if let pointHandle = hit.sketchPointHandle {
            return .sketchEntity(
                .sketchPointHandle(
                    featureID: hit.featureID,
                    entityID: sketchEntityID,
                    handle: pointHandle
                )
            )
        }
        return .sketchEntity(
            .sketchEntity(
                featureID: hit.featureID,
                entityID: sketchEntityID
            )
        )
    }

    private func faceSelectionComponent(
        for hit: ViewportHit,
        sceneNodeID: SceneNodeID
    ) -> SelectionComponent? {
        guard hit.kind == .body,
              let bodyFace = hit.bodyFace else {
            return nil
        }
        if let generatedComponentID = generatedTopologyComponentID(
            for: sceneNodeID,
            bodyFace: bodyFace
        ) {
            return .face(generatedComponentID)
        }
        return .face(selectionFace(for: bodyFace))
    }

    private func generatedTopologyComponentID(
        for sceneNodeID: SceneNodeID,
        bodyFace: ViewportBodyFace
    ) -> SelectionComponentID? {
        let bodyFace = coreBodyFace(for: bodyFace)
        do {
            return try GeneratedTopologySelectionResolver().componentID(
                for: sceneNodeID,
                bodyFace: bodyFace,
                in: document,
                objectRegistry: objectRegistry
            )
        } catch {
            return nil
        }
    }

    private func edgeSelectionComponent(
        for hit: ViewportHit,
        sceneNodeID: SceneNodeID
    ) -> SelectionComponent? {
        guard hit.kind == .body,
              let bodyEdge = hit.bodyEdge else {
            return nil
        }
        if let generatedComponentID = generatedTopologyComponentID(
            for: sceneNodeID,
            bodyEdge: bodyEdge
        ) {
            return .edge(generatedComponentID)
        }
        return .edge(selectionEdge(for: bodyEdge))
    }

    private func generatedTopologyComponentID(
        for sceneNodeID: SceneNodeID,
        bodyEdge: ViewportBodyEdge
    ) -> SelectionComponentID? {
        let cornerEdge = bodyCornerEdge(for: bodyEdge)
        do {
            return try GeneratedTopologySelectionResolver().componentID(
                for: sceneNodeID,
                cornerEdge: cornerEdge,
                in: document,
                objectRegistry: objectRegistry
            )
        } catch {
            return nil
        }
    }

    private func vertexSelectionComponent(
        for hit: ViewportHit,
        sceneNodeID: SceneNodeID
    ) -> SelectionComponent? {
        guard hit.kind == .body,
              let bodyVertex = hit.bodyVertex,
              let generatedComponentID = generatedTopologyComponentID(
                for: sceneNodeID,
                bodyVertex: bodyVertex
              ) else {
            return nil
        }
        return .vertex(generatedComponentID)
    }

    private func generatedTopologyComponentID(
        for sceneNodeID: SceneNodeID,
        bodyVertex: ViewportBodyVertex
    ) -> SelectionComponentID? {
        let cornerVertex = bodyCornerVertex(for: bodyVertex)
        do {
            return try GeneratedTopologySelectionResolver().componentID(
                for: sceneNodeID,
                cornerVertex: cornerVertex,
                in: document,
                objectRegistry: objectRegistry
            )
        } catch {
            return nil
        }
    }

    private func coreBodyFace(for bodyFace: ViewportBodyFace) -> BodyFace {
        switch bodyFace {
        case .front:
            return .front
        case .back:
            return .back
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .left:
            return .left
        case .right:
            return .right
        case .side:
            return .side
        }
    }

    private func bodyCornerEdge(for bodyEdge: ViewportBodyEdge) -> BodyCornerEdge {
        switch bodyEdge {
        case .leftBottom:
            return .leftBottom
        case .rightBottom:
            return .rightBottom
        case .rightTop:
            return .rightTop
        case .leftTop:
            return .leftTop
        }
    }

    private func bodyCornerVertex(for bodyVertex: ViewportBodyVertex) -> BodyCornerVertex {
        switch bodyVertex {
        case .frontBottomLeft:
            return .frontBottomLeft
        case .frontBottomRight:
            return .frontBottomRight
        case .frontTopRight:
            return .frontTopRight
        case .frontTopLeft:
            return .frontTopLeft
        case .backBottomLeft:
            return .backBottomLeft
        case .backBottomRight:
            return .backBottomRight
        case .backTopRight:
            return .backTopRight
        case .backTopLeft:
            return .backTopLeft
        }
    }

    private func selectionFace(for bodyFace: ViewportBodyFace) -> SelectionComponentID {
        switch bodyFace {
        case .front:
            return .bodyFaceFront
        case .back:
            return .bodyFaceBack
        case .top:
            return .bodyFaceTop
        case .bottom:
            return .bodyFaceBottom
        case .left:
            return .bodyFaceLeft
        case .right:
            return .bodyFaceRight
        case .side:
            return .bodyFaceSide
        }
    }

    private func selectionEdge(for bodyEdge: ViewportBodyEdge) -> SelectionComponentID {
        switch bodyEdge {
        case .leftBottom:
            return .bodyEdgeLeftBottom
        case .rightBottom:
            return .bodyEdgeRightBottom
        case .rightTop:
            return .bodyEdgeRightTop
        case .leftTop:
            return .bodyEdgeLeftTop
        }
    }

    private func uniqueObjectTargets(for hits: [ViewportHit]) -> [SelectionTarget] {
        guard selectionScope == .object else {
            return []
        }
        var targets: [SelectionTarget] = []
        var seenTargets: Set<SelectionTarget> = []
        for hit in hits {
            guard let id = sceneNodeID(for: hit) else {
                continue
            }
            let target = SelectionTarget(sceneNodeID: id)
            guard seenTargets.insert(target).inserted else {
                continue
            }
            targets.append(target)
        }
        return targets
    }

    private func uniqueSketchEntityTargets(for hits: [ViewportHit]) -> [SelectionTarget] {
        let targets = uniqueSelectionTargets(for: hits)
        let pointTargets = targets.filter { target in
            guard case .sketchEntity(let componentID) = target.component else {
                return false
            }
            return componentID.sketchPointReference != nil
        }
        return pointTargets.isEmpty ? targets : pointTargets
    }

    private func uniqueSelectionTargets(for hits: [ViewportHit]) -> [SelectionTarget] {
        var targets: [SelectionTarget] = []
        var seenTargets: Set<SelectionTarget> = []
        for hit in hits {
            guard let target = selectionTarget(for: hit),
                  seenTargets.insert(target).inserted else {
                continue
            }
            targets.append(target)
        }
        return targets
    }
}
