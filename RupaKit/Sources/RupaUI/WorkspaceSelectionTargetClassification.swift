import RupaCore

struct WorkspaceSelectionTargetClassification {
    var objectTargets: [SelectionTarget] = []
    var faceTargets: [SelectionTarget] = []
    var edgeTargets: [SelectionTarget] = []
    var vertexTargets: [SelectionTarget] = []
    var sketchEntityTargets: [SelectionTarget] = []
    var regionTargets: [SelectionTarget] = []
    var constructionPlaneTargets: [SelectionTarget] = []
    var objectDimensionTargets: [SelectionTarget] = []
    var sketchDimensionTargets: [SelectionTarget] = []

    init(selection: SelectionModel) {
        self.init(targets: selection.selectedTargets)
    }

    init(targets: [SelectionTarget]) {
        for target in targets {
            switch target.component {
            case .object:
                objectTargets.append(target)
                objectDimensionTargets.append(target)
            case .face:
                faceTargets.append(target)
                objectDimensionTargets.append(target)
            case .edge:
                edgeTargets.append(target)
                if isGeneratedEdge(target) {
                    sketchDimensionTargets.append(target)
                }
            case .vertex:
                vertexTargets.append(target)
            case .sketchEntity:
                sketchEntityTargets.append(target)
                sketchDimensionTargets.append(target)
            case .region:
                regionTargets.append(target)
            case .constructionPlane:
                constructionPlaneTargets.append(target)
            }
        }
    }

    var generatedEdgeTargets: [SelectionTarget] {
        generatedEdgeTargets(from: edgeTargets)
    }

    func generatedEdgeTargets(from targets: [SelectionTarget]) -> [SelectionTarget] {
        var projectedTargets: [SelectionTarget] = []
        var seen = Set<String>()
        for target in targets {
            guard case .edge(let componentID) = target.component,
                  componentID.generatedTopologyPersistentName != nil else {
                continue
            }
            let key = "\(target.sceneNodeID.description):\(String(describing: target.component))"
            if seen.insert(key).inserted {
                projectedTargets.append(target)
            }
        }
        return projectedTargets
    }

    private func isGeneratedEdge(_ target: SelectionTarget) -> Bool {
        guard case .edge(let componentID) = target.component else {
            return false
        }
        return componentID.generatedTopologyPersistentName != nil
    }
}
