import Foundation
import SwiftCAD

public struct ConstructionPlaneSource: Codable, Hashable, Sendable, Identifiable {
    public var id: ConstructionPlaneSourceID
    public var name: String
    public var plane: SketchPlane

    public init(
        id: ConstructionPlaneSourceID = ConstructionPlaneSourceID(),
        name: String,
        plane: SketchPlane
    ) {
        self.id = id
        self.name = name
        self.plane = plane
    }

    public func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DocumentValidationError.invalidProductMetadata(
                "Construction plane names must not be empty."
            )
        }
        try Self.validatePlane(plane)
    }

    public static func validatePlane(_ plane: SketchPlane) throws {
        switch plane {
        case .xy, .yz, .zx:
            return
        case .plane(let plane):
            guard plane.origin.x.isFinite,
                  plane.origin.y.isFinite,
                  plane.origin.z.isFinite,
                  plane.normal.x.isFinite,
                  plane.normal.y.isFinite,
                  plane.normal.z.isFinite else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Construction plane origin and normal must be finite."
                )
            }
            _ = try plane.normal.normalized(tolerance: 1.0e-12)
        }
    }
}

public struct ConstructionPlaneSummaryResult: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var id: ConstructionPlaneSourceID
        public var name: String
        public var plane: SketchPlane
        public var sceneNodeID: SceneNodeID?
        public var isActive: Bool

        public init(
            id: ConstructionPlaneSourceID,
            name: String,
            plane: SketchPlane,
            sceneNodeID: SceneNodeID?,
            isActive: Bool
        ) {
            self.id = id
            self.name = name
            self.plane = plane
            self.sceneNodeID = sceneNodeID
            self.isActive = isActive
        }

        public func selectionTarget() -> SelectionTarget? {
            guard let sceneNodeID else {
                return nil
            }
            return SelectionTarget(
                sceneNodeID: sceneNodeID,
                component: .constructionPlane(id)
            )
        }
    }

    public var activePlaneID: ConstructionPlaneSourceID?
    public var planes: [Entry]

    public init(
        activePlaneID: ConstructionPlaneSourceID?,
        planes: [Entry]
    ) {
        self.activePlaneID = activePlaneID
        self.planes = planes
    }
}

public struct ConstructionPlaneSummaryService: Sendable {
    public init() {}

    public func summarize(document: DesignDocument) -> ConstructionPlaneSummaryResult {
        var sceneNodeByPlaneID: [ConstructionPlaneSourceID: SceneNodeID] = [:]
        for node in document.productMetadata.sceneNodes.values {
            guard let constructionPlaneID = node.reference?.constructionPlaneID,
                  sceneNodeByPlaneID[constructionPlaneID] == nil else {
                continue
            }
            sceneNodeByPlaneID[constructionPlaneID] = node.id
        }
        let activePlaneID = document.productMetadata.activeConstructionPlaneID
        let entries = document.productMetadata.constructionPlanes.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { source in
                ConstructionPlaneSummaryResult.Entry(
                    id: source.id,
                    name: source.name,
                    plane: source.plane,
                    sceneNodeID: sceneNodeByPlaneID[source.id],
                    isActive: source.id == activePlaneID
                )
            }
        return ConstructionPlaneSummaryResult(
            activePlaneID: activePlaneID,
            planes: entries
        )
    }
}
