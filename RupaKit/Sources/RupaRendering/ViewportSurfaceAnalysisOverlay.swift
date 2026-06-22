import RupaCore
import SwiftCAD

public struct ViewportSurfaceAnalysisOverlay: Equatable {
    public struct Item: Equatable, Identifiable {
        public var id: String
        public var faceID: String
        public var facePersistentName: String?
        public var direction: SurfaceAnalysisResult.Direction
        public var position: Point3D
        public var normal: Vector3D
        public var normalChangePerLength: Double
        public var normalCurvature: Double

        public init(
            id: String,
            faceID: String,
            facePersistentName: String? = nil,
            direction: SurfaceAnalysisResult.Direction,
            position: Point3D,
            normal: Vector3D,
            normalChangePerLength: Double,
            normalCurvature: Double
        ) {
            self.id = id
            self.faceID = faceID
            self.facePersistentName = facePersistentName
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
        public var facePersistentName: String?
        public var position: Point3D
        public var minimumPrincipalDirection: Vector3D
        public var maximumPrincipalDirection: Vector3D
        public var minimumPrincipalCurvature: Double
        public var maximumPrincipalCurvature: Double

        public init(
            id: String,
            faceID: String,
            facePersistentName: String? = nil,
            position: Point3D,
            minimumPrincipalDirection: Vector3D,
            maximumPrincipalDirection: Vector3D,
            minimumPrincipalCurvature: Double,
            maximumPrincipalCurvature: Double
        ) {
            self.id = id
            self.faceID = faceID
            self.facePersistentName = facePersistentName
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
        public var facePersistentName: String?
        public var loopID: String
        public var role: SurfaceAnalysisResult.TrimBoundaryRole
        public var points: [Point3D]
        public var isClosed: Bool

        public init(
            id: String,
            faceID: String,
            facePersistentName: String? = nil,
            loopID: String,
            role: SurfaceAnalysisResult.TrimBoundaryRole,
            points: [Point3D],
            isClosed: Bool
        ) {
            self.id = id
            self.faceID = faceID
            self.facePersistentName = facePersistentName
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
        guard options.showsAnyOverlay else {
            return ViewportSurfaceAnalysisOverlay()
        }
        guard let result, result.faces.isEmpty == false else {
            return ViewportSurfaceAnalysisOverlay()
        }

        let selectedGeneratedNames = generatedTopologyPersistentNames(in: selection.selectedTargets)
        let selectedFeatureIDs = selectedBodyFeatureIDs(in: selection.selectedTargets, document: document)
        guard selectedGeneratedNames.isEmpty == false || selectedFeatureIDs.isEmpty == false else {
            return ViewportSurfaceAnalysisOverlay()
        }

        var items: [Item] = []
        var principalItems: [PrincipalDirectionItem] = []
        var boundaryOverlayItems: [BoundaryItem] = []
        for face in result.faces where shouldShow(
            face,
            selectedGeneratedNames: selectedGeneratedNames,
            selectedFeatureIDs: selectedFeatureIDs
        ) {
            if options.showsTrimBoundaries {
                boundaryOverlayItems.append(contentsOf: boundaryItems(for: face))
            }
            if options.showsCurvatureCombs {
                items.append(contentsOf: overlayItems(for: face))
            }
            if options.showsPrincipalDirections {
                principalItems.append(contentsOf: principalDirectionItems(for: face))
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
        document: DesignDocument
    ) -> Set<String> {
        Set(targets.compactMap { target in
            guard target.component == .object,
                  let reference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
                  reference.kind == .body else {
                return nil
            }
            return reference.featureID?.description
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

    private static func shouldShow(
        _ face: SurfaceAnalysisResult.FaceAnalysis,
        selectedGeneratedNames: Set<String>,
        selectedFeatureIDs: Set<String>
    ) -> Bool {
        if let sourceFeatureID = face.sourceFeatureID,
           selectedFeatureIDs.contains(sourceFeatureID) {
            return true
        }
        guard selectedGeneratedNames.isEmpty == false else {
            return false
        }
        if face.facePersistentNames.contains(where: { selectedGeneratedNames.contains($0) }) {
            return true
        }
        return face.edgePersistentNames.contains { selectedGeneratedNames.contains($0) }
    }

    private static func overlayItems(
        for face: SurfaceAnalysisResult.FaceAnalysis
    ) -> [Item] {
        face.curvatureCombs.enumerated().map { index, comb in
            Item(
                id: "\(face.faceID):\(comb.direction.rawValue):\(index)",
                faceID: face.faceID,
                facePersistentName: face.facePersistentNames.first,
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
        for face: SurfaceAnalysisResult.FaceAnalysis
    ) -> [PrincipalDirectionItem] {
        face.samples.enumerated().map { index, sample in
            PrincipalDirectionItem(
                id: "\(face.faceID):principal:\(index)",
                faceID: face.faceID,
                facePersistentName: face.facePersistentNames.first,
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
        for face: SurfaceAnalysisResult.FaceAnalysis
    ) -> [BoundaryItem] {
        face.trimBoundaries.map { boundary in
            BoundaryItem(
                id: "\(face.faceID):trim:\(boundary.loopID)",
                faceID: face.faceID,
                facePersistentName: face.facePersistentNames.first,
                loopID: boundary.loopID,
                role: boundary.role,
                points: boundary.points.map { point in
                    Point3D(x: point.x, y: point.y, z: point.z)
                },
                isClosed: boundary.isClosed
            )
        }
    }
}
