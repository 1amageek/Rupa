import RupaCore

public struct ViewportSurfaceAnalysisOverlay: Equatable {
    public struct Item: Equatable, Identifiable {
        public var id: String
        public var faceID: String
        public var faceSubshapeID: String?
        public var direction: SurfaceAnalysisResult.Direction
        public var position: Point3D
        public var normal: Vector3D
        public var normalChangePerLength: Double
        public var normalCurvature: Double

        public init(
            id: String,
            faceID: String,
            faceSubshapeID: String? = nil,
            direction: SurfaceAnalysisResult.Direction,
            position: Point3D,
            normal: Vector3D,
            normalChangePerLength: Double,
            normalCurvature: Double
        ) {
            self.id = id
            self.faceID = faceID
            self.faceSubshapeID = faceSubshapeID
            self.direction = direction
            self.position = position
            self.normal = normal
            self.normalChangePerLength = normalChangePerLength
            self.normalCurvature = normalCurvature
        }
    }

    public struct PrincipalDirectionItem: Equatable, Identifiable {
        public var id: String
        public var faceID: String
        public var faceSubshapeID: String?
        public var position: Point3D
        public var minimumPrincipalDirection: Vector3D
        public var maximumPrincipalDirection: Vector3D
        public var minimumPrincipalCurvature: Double
        public var maximumPrincipalCurvature: Double

        public init(
            id: String,
            faceID: String,
            faceSubshapeID: String? = nil,
            position: Point3D,
            minimumPrincipalDirection: Vector3D,
            maximumPrincipalDirection: Vector3D,
            minimumPrincipalCurvature: Double,
            maximumPrincipalCurvature: Double
        ) {
            self.id = id
            self.faceID = faceID
            self.faceSubshapeID = faceSubshapeID
            self.position = position
            self.minimumPrincipalDirection = minimumPrincipalDirection
            self.maximumPrincipalDirection = maximumPrincipalDirection
            self.minimumPrincipalCurvature = minimumPrincipalCurvature
            self.maximumPrincipalCurvature = maximumPrincipalCurvature
        }
    }

    public struct BoundaryItem: Equatable, Identifiable {
        public var id: String
        public var faceID: String
        public var faceSubshapeID: String?
        public var loopID: String
        public var role: SurfaceAnalysisResult.TrimBoundaryRole
        public var points: [Point3D]
        public var isClosed: Bool

        public init(
            id: String,
            faceID: String,
            faceSubshapeID: String? = nil,
            loopID: String,
            role: SurfaceAnalysisResult.TrimBoundaryRole,
            points: [Point3D],
            isClosed: Bool
        ) {
            self.id = id
            self.faceID = faceID
            self.faceSubshapeID = faceSubshapeID
            self.loopID = loopID
            self.role = role
            self.points = points
            self.isClosed = isClosed
        }
    }

    public var items: [Item]
    public var principalDirectionItems: [PrincipalDirectionItem]
    public var boundaryItems: [BoundaryItem]

    public init(
        items: [Item] = [],
        principalDirectionItems: [PrincipalDirectionItem] = [],
        boundaryItems: [BoundaryItem] = []
    ) {
        self.items = items
        self.principalDirectionItems = principalDirectionItems
        self.boundaryItems = boundaryItems
    }

    public static func build(
        result: SurfaceAnalysisResult?,
        selection: SelectionModel,
        document: DesignDocument,
        options: ViewportSurfaceAnalysisOptions = ViewportSurfaceAnalysisOptions()
    ) -> ViewportSurfaceAnalysisOverlay {
        build(result: result, selection: selection, document: document, options: options,
              checkpoint: { _, _, _ in })
    }

    static func build(
        result: SurfaceAnalysisResult?,
        selection: SelectionModel,
        document: DesignDocument,
        options: ViewportSurfaceAnalysisOptions = ViewportSurfaceAnalysisOptions(),
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> ViewportSurfaceAnalysisOverlay {
        try checkpoint(0, 0, 0)
        guard options.showsAnyOverlay else {
            return ViewportSurfaceAnalysisOverlay()
        }
        guard let result, result.faces.isEmpty == false else {
            return ViewportSurfaceAnalysisOverlay()
        }

        let selectedGeneratedNames = try generatedTopologySubshapeIDStrings(in: selection.selectedTargets, checkpoint: checkpoint)
        let selectedFeatureIDs = try selectedBodyFeatureIDs(in: selection.selectedTargets, document: document, checkpoint: checkpoint)
        guard selectedGeneratedNames.isEmpty == false || selectedFeatureIDs.isEmpty == false else {
            return ViewportSurfaceAnalysisOverlay()
        }

        var items: [Item] = []
        var principalItems: [PrincipalDirectionItem] = []
        var boundaryOverlayItems: [BoundaryItem] = []
        for face in result.faces {
            try checkpoint(0, 0, 1)
            guard try shouldShow(face, selectedGeneratedNames: selectedGeneratedNames,
                                 selectedFeatureIDs: selectedFeatureIDs, checkpoint: checkpoint) else { continue }
            if options.showsTrimBoundaries {
                boundaryOverlayItems.append(contentsOf: try boundaryItems(for: face, checkpoint: checkpoint))
            }
            if options.showsCurvatureCombs {
                items.append(contentsOf: try overlayItems(for: face, checkpoint: checkpoint))
            }
            if options.showsPrincipalDirections {
                principalItems.append(contentsOf: try principalDirectionItems(for: face, checkpoint: checkpoint))
            }
        }
        return ViewportSurfaceAnalysisOverlay(
            items: items,
            principalDirectionItems: principalItems,
            boundaryItems: boundaryOverlayItems
        )
    }

    private static func selectedBodyFeatureIDs(
        in targets: [SelectionTarget],
        document: DesignDocument,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Set<String> {
        try checkpoint(0, 0, targets.count)
        return Set(try targets.compactMap { target in
            try checkpoint(0, 0, 0)
            guard target.component == .object,
                  let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
                  reference.kind == .body else {
                return nil
            }
            return reference.featureID?.description
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

    private static func shouldShow(
        _ face: SurfaceAnalysisResult.FaceAnalysis,
        selectedGeneratedNames: Set<String>,
        selectedFeatureIDs: Set<String>,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> Bool {
        if let sourceFeatureID = face.sourceFeatureID,
           selectedFeatureIDs.contains(sourceFeatureID) {
            return true
        }
        guard selectedGeneratedNames.isEmpty == false else {
            return false
        }
        if try face.faceSubshapeIDs.contains(where: {
            try checkpoint(0, 0, 1)
            return selectedGeneratedNames.contains($0)
        }) {
            return true
        }
        return try face.edgePersistentNames.contains {
            try checkpoint(0, 0, 1)
            return selectedGeneratedNames.contains($0)
        }
    }

    private static func overlayItems(
        for face: SurfaceAnalysisResult.FaceAnalysis,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [Item] {
        try checkpoint(face.curvatureCombs.count, 0, 0)
        return try face.curvatureCombs.enumerated().map { index, comb in
            try checkpoint(0, 2, 1)
            return Item(
                id: "\(face.faceID):\(comb.direction.rawValue):\(index)",
                faceID: face.faceID,
                faceSubshapeID: face.faceSubshapeIDs.first,
                direction: comb.direction,
                position: Point3D(
                    x: comb.position.x,
                    y: comb.position.y,
                    z: comb.position.z
                ),
                normal: Vector3D(
                    x: comb.normal.x,
                    y: comb.normal.y,
                    z: comb.normal.z
                ),
                normalChangePerLength: comb.normalChangePerLength,
                normalCurvature: comb.normalCurvature
            )
        }
    }

    private static func principalDirectionItems(
        for face: SurfaceAnalysisResult.FaceAnalysis,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [PrincipalDirectionItem] {
        try checkpoint(face.samples.count, 0, 0)
        return try face.samples.enumerated().map { index, sample in
            try checkpoint(1, 4, 1)
            return PrincipalDirectionItem(
                id: "\(face.faceID):principal:\(index)",
                faceID: face.faceID,
                faceSubshapeID: face.faceSubshapeIDs.first,
                position: Point3D(
                    x: sample.position.x,
                    y: sample.position.y,
                    z: sample.position.z
                ),
                minimumPrincipalDirection: Vector3D(
                    x: sample.minimumPrincipalDirection.x,
                    y: sample.minimumPrincipalDirection.y,
                    z: sample.minimumPrincipalDirection.z
                ),
                maximumPrincipalDirection: Vector3D(
                    x: sample.maximumPrincipalDirection.x,
                    y: sample.maximumPrincipalDirection.y,
                    z: sample.maximumPrincipalDirection.z
                ),
                minimumPrincipalCurvature: sample.minimumPrincipalCurvature,
                maximumPrincipalCurvature: sample.maximumPrincipalCurvature
            )
        }
    }

    private static func boundaryItems(
        for face: SurfaceAnalysisResult.FaceAnalysis,
        checkpoint: (Int, Int, Int) throws -> Void
    ) rethrows -> [BoundaryItem] {
        try checkpoint(face.trimBoundaries.count, 0, 0)
        return try face.trimBoundaries.map { boundary in
            try checkpoint(0, boundary.points.count, 1)
            if boundary.isClosed { try checkpoint(0, 1, 0) }
            return BoundaryItem(
                id: "\(face.faceID):trim:\(boundary.loopID)",
                faceID: face.faceID,
                faceSubshapeID: face.faceSubshapeIDs.first,
                loopID: boundary.loopID,
                role: boundary.role,
                points: try boundary.points.map { point in
                    try checkpoint(0, 0, 1)
                    return Point3D(x: point.x, y: point.y, z: point.z)
                },
                isClosed: boundary.isClosed
            )
        }
    }
}
