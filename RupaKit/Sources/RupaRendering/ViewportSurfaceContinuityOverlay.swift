import RupaCore
import RupaViewportScene

public struct ViewportSurfaceContinuityOverlay: Equatable {
    public struct Item: Equatable, Identifiable {
        public var id: String
        public var start: Point3D
        public var end: Point3D
        public var edgePersistentName: String
        public var continuity: RupaCore.SurfaceContinuityResult.ContinuityLevel
        public var requiresCurvatureContinuitySolve: Bool
        public var normalAngle: Double?

        public init(
            id: String,
            start: Point3D,
            end: Point3D,
            edgePersistentName: String,
            continuity: RupaCore.SurfaceContinuityResult.ContinuityLevel,
            requiresCurvatureContinuitySolve: Bool,
            normalAngle: Double? = nil
        ) {
            self.id = id
            self.start = start
            self.end = end
            self.edgePersistentName = edgePersistentName
            self.continuity = continuity
            self.requiresCurvatureContinuitySolve = requiresCurvatureContinuitySolve
            self.normalAngle = normalAngle
        }

        public var midpoint: Point3D {
            Point3D(
                x: (start.x + end.x) * 0.5,
                y: (start.y + end.y) * 0.5,
                z: (start.z + end.z) * 0.5
            )
        }
    }

    public var items: [Item]

    public init(items: [Item] = []) {
        self.items = items
    }

    public static func build(
        result: RupaCore.SurfaceContinuityResult?,
        scene: ViewportScene,
        selection: SelectionModel,
        document: DesignDocument
    ) -> ViewportSurfaceContinuityOverlay {
        guard let result, result.adjacencies.isEmpty == false else {
            return ViewportSurfaceContinuityOverlay()
        }

        let selectedStableKeys = stableTopologyKeys(in: selection.selectedTargets)
        let selectedFeatureIDs = selectedBodyFeatureIDs(in: selection.selectedTargets, document: document)
        guard selectedStableKeys.isEmpty == false || selectedFeatureIDs.isEmpty == false else {
            return ViewportSurfaceContinuityOverlay()
        }

        let edgeLookup = edgeLookup(in: scene, selectedFeatureIDs: selectedFeatureIDs)
        let items = result.adjacencies.compactMap { adjacency -> Item? in
            guard shouldShow(adjacency, selectedStableKeys: selectedStableKeys) else {
                return nil
            }
            guard let edge = resolvedEdge(for: adjacency, edgeLookup: edgeLookup) else {
                return nil
            }
            return Item(
                id: "\(adjacency.edgeID):\(edge.persistentName)",
                start: edge.start,
                end: edge.end,
                edgePersistentName: edge.persistentName,
                continuity: adjacency.continuity,
                requiresCurvatureContinuitySolve: adjacency.requiresCurvatureContinuitySolve,
                normalAngle: adjacency.normalAngle
            )
        }
        return ViewportSurfaceContinuityOverlay(items: items)
    }

    private static func selectedBodyFeatureIDs(
        in targets: [SelectionTarget],
        document: DesignDocument
    ) -> Set<FeatureID> {
        Set(targets.compactMap { target in
            guard target.component == .object,
                  let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
                  reference.kind == .body else {
                return nil
            }
            return reference.featureID
        })
    }

    private static func stableTopologyKeys(
        in targets: [SelectionTarget]
    ) -> Set<String> {
        var keys = Set<String>()
        for target in targets {
            switch target.component {
            case .object, .sketchEntity, .region, .constructionPlane:
                continue
            case .face(let componentID), .edge(let componentID), .vertex(let componentID):
                guard componentID.isStableTopology else {
                    continue
                }
                do {
                    let reference = try componentID.stableTopologyReference(
                        operationName: "Surface continuity overlay"
                    )
                    keys.insert(stableTopologyKey(reference))
                } catch {
                    assertionFailure("Invalid stable topology selection: \(error)")
                }
            }
        }
        return keys
    }

    private static func edgeLookup(
        in scene: ViewportScene,
        selectedFeatureIDs: Set<FeatureID>
    ) -> [String: EdgeRecord] {
        var result: [String: EdgeRecord] = [:]
        for item in scene.items {
            guard selectedFeatureIDs.isEmpty || selectedFeatureIDs.contains(item.featureID),
                  case .body(let component) = item.kind,
                  let topology = component.topology else {
                continue
            }
            for edge in topology.edges {
                guard edge.componentID.isStableTopology else {
                    continue
                }
                do {
                    let reference = try edge.componentID.stableTopologyReference(
                        operationName: "Surface continuity overlay"
                    )
                    let stableKey = stableTopologyKey(reference)
                    result[stableKey] = EdgeRecord(
                        persistentName: stableKey,
                        start: edge.start,
                        end: edge.end
                    )
                } catch {
                    assertionFailure("Invalid stable topology edge: \(error)")
                }
            }
        }
        return result
    }

    private static func shouldShow(
        _ adjacency: RupaCore.SurfaceContinuityResult.Adjacency,
        selectedStableKeys: Set<String>
    ) -> Bool {
        guard selectedStableKeys.isEmpty == false else {
            return true
        }
        if let firstFacePersistentName = adjacency.firstFacePersistentName,
           selectedStableKeys.contains(firstFacePersistentName) {
            return true
        }
        if let secondFacePersistentName = adjacency.secondFacePersistentName,
           selectedStableKeys.contains(secondFacePersistentName) {
            return true
        }
        return adjacency.edgePersistentNames.contains { selectedStableKeys.contains($0) }
    }

    private static func resolvedEdge(
        for adjacency: RupaCore.SurfaceContinuityResult.Adjacency,
        edgeLookup: [String: EdgeRecord]
    ) -> EdgeRecord? {
        for persistentName in adjacency.edgePersistentNames {
            if let edge = edgeLookup[persistentName] {
                return edge
            }
        }
        return nil
    }

    private static func stableTopologyKey(_ reference: StableSubshapeReference) -> String {
        let id = reference.subshapeID
        return "feature:\(id.featureID.description)/role:\(id.role)/ordinal:\(id.ordinal)"
    }

    private struct EdgeRecord: Equatable {
        var persistentName: String
        var start: Point3D
        var end: Point3D
    }
}
