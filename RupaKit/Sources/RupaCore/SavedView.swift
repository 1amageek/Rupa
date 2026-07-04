import Foundation
import SwiftCAD

public struct SavedView: Codable, Hashable, Sendable, Identifiable {
    public var id: SavedViewID
    public var name: String
    public var camera: SavedViewCamera
    public var projection: SavedViewProjection
    public var clipping: SavedViewClipping
    public var visibility: SavedViewVisibility
    public var sectionState: SavedViewSectionState
    public var displayScale: SavedViewDisplayScale

    public init(
        id: SavedViewID = SavedViewID(),
        name: String,
        camera: SavedViewCamera,
        projection: SavedViewProjection,
        clipping: SavedViewClipping = SavedViewClipping(),
        visibility: SavedViewVisibility = SavedViewVisibility(),
        sectionState: SavedViewSectionState = SavedViewSectionState(),
        displayScale: SavedViewDisplayScale
    ) {
        self.id = id
        self.name = name
        self.camera = camera
        self.projection = projection
        self.clipping = clipping
        self.visibility = visibility
        self.sectionState = sectionState
        self.displayScale = displayScale
    }

    public func validate(
        sceneNodes: [SceneNodeID: SceneNode],
        constructionPlanes: [ConstructionPlaneSourceID: ConstructionPlaneSource]
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view names must not be empty."
            )
        }
        try camera.validate()
        try projection.validate()
        try clipping.validate()
        try visibility.validate(sceneNodes: sceneNodes)
        try sectionState.validate(
            sceneNodes: sceneNodes,
            constructionPlanes: constructionPlanes
        )
        try displayScale.validate()
    }
}
