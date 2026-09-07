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
        build(result: result, scene: scene, selection: selection, document: document,
              checkpoint: { _, _, _ in })
    }

    static func build(
        result: RupaCore.SurfaceContinuityResult?,
        scene: ViewportScene,
        selection: SelectionModel,
        document: DesignDocument,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> ViewportSurfaceContinuityOverlay {
        try checkpoint(0, 0, 0)
        guard let result, result.adjacencies.isEmpty == false else {
            return ViewportSurfaceContinuityOverlay()
        }

        let selectedGeneratedNames = try generatedTopologySubshapeIDStrings(in: selection.selectedTargets, checkpoint: checkpoint)
        let selectedFeatureIDs = try selectedBodyFeatureIDs(in: selection.selectedTargets, document: document, checkpoint: checkpoint)
        guard selectedGeneratedNames.isEmpty == false || selectedFeatureIDs.isEmpty == false else {
            return ViewportSurfaceContinuityOverlay()
        }

        let edgeLookup = try edgeLookup(in: scene, selectedFeatureIDs: selectedFeatureIDs, checkpoint: checkpoint)
        var items: [Item] = []
        for adjacency in result.adjacencies {
            try checkpoint(0, 0, 1)
            guard try shouldShow(adjacency, selectedGeneratedNames: selectedGeneratedNames, checkpoint: checkpoint) else {
                continue
            }
            guard let edge = try resolvedEdge(for: adjacency, edgeLookup: edgeLookup, checkpoint: checkpoint) else {
                continue
            }
            try checkpoint(2, 3, 0)
            items.append(Item(
                id: "\(adjacency.edgeID):\(edge.persistentName)",
                start: edge.start,
                end: edge.end,
                edgePersistentName: edge.persistentName,
                continuity: adjacency.continuity,
                requiresCurvatureContinuitySolve: adjacency.requiresCurvatureContinuitySolve,
                normalAngle: adjacency.normalAngle
            ))
        }
        return ViewportSurfaceContinuityOverlay(items: items)
    }

    private static func selectedBodyFeatureIDs(
        in targets: [SelectionTarget],
        document: DesignDocument,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Set<FeatureID> {
        try checkpoint(0, 0, targets.count)
        return Set(try targets.compactMap { target in
            try checkpoint(0, 0, 0)
            guard target.component == .object,
                  let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
                  reference.kind == .body else {
                return nil
            }
            return reference.featureID
        })
    }

    private static func generatedTopologySubshapeIDStrings(
        in targets: [SelectionTarget],
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Set<String> {
        var names = Set<String>()
        for target in targets {
            try checkpoint(0, 0, 1)
            switch target.component {
            case .object, .sketchEntity, .region, .constructionPlane:
                continue
            case .face(let componentID), .edge(let componentID), .vertex(let componentID):
                guard let subshapeID = componentID.generatedTopologySubshapeID else {
                    continue
                }
                names.insert(GeneratedSubshapeIdentity.string(for: subshapeID))
            }
        }
        return names
    }

    private static func edgeLookup(
        in scene: ViewportScene,
        selectedFeatureIDs: Set<FeatureID>,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [String: EdgeRecord] {
        var result: [String: EdgeRecord] = [:]
        for item in scene.items {
            try checkpoint(0, 0, 1)
            guard selectedFeatureIDs.isEmpty || selectedFeatureIDs.contains(item.featureID),
                  case .body(let component) = item.kind,
                  let topology = component.topology else {
                continue
            }
            for edge in topology.edges {
                try checkpoint(0, 0, 1)
                guard let subshapeID = edge.componentID.generatedTopologySubshapeID else {
                    continue
                }
                try checkpoint(0, 2, 0)
                let subshapeIDString = GeneratedSubshapeIdentity.string(for: subshapeID)
                result[subshapeIDString] = EdgeRecord(
                    persistentName: subshapeIDString,
                    start: edge.start,
                    end: edge.end
                )
            }
        }
        return result
    }

    private static func shouldShow(
        _ adjacency: RupaCore.SurfaceContinuityResult.Adjacency,
        selectedGeneratedNames: Set<String>,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Bool {
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
        return try adjacency.edgePersistentNames.contains {
            try checkpoint(0, 0, 1)
            return selectedGeneratedNames.contains($0)
        }
    }

    private static func resolvedEdge(
        for adjacency: RupaCore.SurfaceContinuityResult.Adjacency,
        edgeLookup: [String: EdgeRecord],
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> EdgeRecord? {
        for persistentName in adjacency.edgePersistentNames {
            try checkpoint(0, 0, 1)
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
