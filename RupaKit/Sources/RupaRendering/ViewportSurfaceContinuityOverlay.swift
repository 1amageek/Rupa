import RupaCore
import SwiftCAD

public struct ViewportSurfaceContinuityOverlay: Equatable {
    public struct Item: Equatable, Identifiable {
        public var id: String
        public var start: Point3D
        public var end: Point3D
        public var edgePersistentName: String
        public var continuity: SurfaceContinuityResult.ContinuityLevel
        public var requiresCurvatureContinuitySolve: Bool
        public var normalAngle: Double?

        public init(
            id: String,
            start: Point3D,
            end: Point3D,
            edgePersistentName: String,
            continuity: SurfaceContinuityResult.ContinuityLevel,
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
        result: SurfaceContinuityResult?,
        scene: ViewportScene,
        selection: SelectionModel,
        document: DesignDocument
    ) -> ViewportSurfaceContinuityOverlay {
        guard let result, result.adjacencies.isEmpty == false else {
            return ViewportSurfaceContinuityOverlay()
        }

        let selectedGeneratedNames = generatedTopologyPersistentNames(in: selection.selectedTargets)
        let selectedFeatureIDs = selectedBodyFeatureIDs(in: selection.selectedTargets, document: document)
        guard selectedGeneratedNames.isEmpty == false || selectedFeatureIDs.isEmpty == false else {
            return ViewportSurfaceContinuityOverlay()
        }

        let edgeLookup = edgeLookup(in: scene, selectedFeatureIDs: selectedFeatureIDs)
        let items = result.adjacencies.compactMap { adjacency -> Item? in
            guard shouldShow(adjacency, selectedGeneratedNames: selectedGeneratedNames) else {
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

    private static func generatedTopologyPersistentNames(
        in targets: [SelectionTarget]
    ) -> Set<String> {
        var names = Set<String>()
        for target in targets {
            switch target.component {
            case .object, .sketchEntity, .region:
                continue
            case .face(let componentID), .edge(let componentID), .vertex(let componentID):
                guard let persistentName = componentID.generatedTopologyPersistentName else {
                    continue
                }
                names.insert(persistentName)
            }
        }
        return names
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
                guard let persistentName = edge.componentID.generatedTopologyPersistentName else {
                    continue
                }
                result[persistentName] = EdgeRecord(
                    persistentName: persistentName,
                    start: edge.start,
                    end: edge.end
                )
            }
        }
        return result
    }

    private static func shouldShow(
        _ adjacency: SurfaceContinuityResult.Adjacency,
        selectedGeneratedNames: Set<String>
    ) -> Bool {
        guard selectedGeneratedNames.isEmpty == false else {
            return true
        }
        if let firstFacePersistentName = adjacency.firstFacePersistentName,
           selectedGeneratedNames.contains(firstFacePersistentName) {
            return true
        }
        if let secondFacePersistentName = adjacency.secondFacePersistentName,
           selectedGeneratedNames.contains(secondFacePersistentName) {
            return true
        }
        return adjacency.edgePersistentNames.contains { selectedGeneratedNames.contains($0) }
    }

    private static func resolvedEdge(
        for adjacency: SurfaceContinuityResult.Adjacency,
        edgeLookup: [String: EdgeRecord]
    ) -> EdgeRecord? {
        for persistentName in adjacency.edgePersistentNames {
            if let edge = edgeLookup[persistentName] {
                return edge
            }
        }
        return nil
    }

    private struct EdgeRecord: Equatable {
        var persistentName: String
        var start: Point3D
        var end: Point3D
    }
}
