import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func savedViewCommandsPersistScaleMetadataAndUndoRedo() async throws {
    let session = EditorSession()
    _ = try session.execute(.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration))
    _ = try session.execute(.createSectionPlane(name: "Section A"))
    let sectionSceneNodeID = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.name == "Section A"
    }?.id)
    let rootSceneNodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)
    let viewID = SavedViewID()
    let savedView = SavedView(
        id: viewID,
        name: " Site view ",
        camera: SavedViewCamera(
            target: Point3D(x: 12_000.0, y: 200.0, z: 8_000.0),
            distanceMeters: 35_000.0,
            yawRadians: 0.5,
            pitchRadians: -0.6
        ),
        projection: .orthographic(heightMeters: 20_000.0),
        clipping: SavedViewClipping(
            nearDistanceMeters: 10.0,
            farDistanceMeters: 100_000.0
        ),
        visibility: SavedViewVisibility(hiddenSceneNodeIDs: [rootSceneNodeID]),
        sectionState: SavedViewSectionState(sectionSceneNodeIDs: [sectionSceneNodeID]),
        displayScale: SavedViewDisplayScale(
            ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration,
            scaleBarLengthMeters: 1_000.0
        )
    )

    let createResult = try session.execute(.createSavedView(savedView))
    let createdView = try #require(session.document.productMetadata.savedViews[viewID])

    #expect(createResult.commandName == "createSavedView")
    #expect(createdView.name == "Site view")
    #expect(createdView.displayScale.displayUnit == .kilometer)
    #expect(createdView.displayScale.scaleBarLengthMeters == 1_000.0)
    #expect(createdView.displayScale.matchedPreset == .sitePlanning)
    #expect(createdView.sectionState.sectionSceneNodeIDs == [sectionSceneNodeID])
    #expect(createdView.visibility.hiddenSceneNodeIDs == [rootSceneNodeID])

    var updatedView = createdView
    updatedView.name = "Regional view"
    updatedView.projection = .perspective(fieldOfViewRadians: Double.pi / 3.0)
    updatedView.displayScale = SavedViewDisplayScale(
        ruler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration,
        scaleBarLengthMeters: 10_000.0
    )
    let updateResult = try session.execute(.updateSavedView(updatedView))

    #expect(updateResult.commandName == "updateSavedView")
    #expect(session.document.productMetadata.savedViews[viewID]?.name == "Regional view")
    #expect(session.document.productMetadata.savedViews[viewID]?.displayScale.matchedPreset == .regionalPlanning)

    let removeResult = try session.execute(.removeSavedView(id: viewID))

    #expect(removeResult.commandName == "removeSavedView")
    #expect(session.document.productMetadata.savedViews[viewID] == nil)

    _ = try session.undo()
    #expect(session.document.productMetadata.savedViews[viewID]?.name == "Regional view")
    _ = try session.undo()
    #expect(session.document.productMetadata.savedViews[viewID]?.name == "Site view")
    _ = try session.redo()
    #expect(session.document.productMetadata.savedViews[viewID]?.name == "Regional view")
}

@Test func savedViewMetadataDecodesLegacyDocumentsWithoutSavedViews() throws {
    let metadata = ProductMetadata.empty()
    let encoded = try JSONEncoder().encode(metadata)
    let object = try JSONSerialization.jsonObject(with: encoded)
    guard var dictionary = object as? [String: Any] else {
        Issue.record("Encoded ProductMetadata must be a dictionary.")
        return
    }
    dictionary.removeValue(forKey: "savedViews")
    let legacyData = try JSONSerialization.data(withJSONObject: dictionary)
    let decoded = try JSONDecoder().decode(ProductMetadata.self, from: legacyData)

    #expect(decoded.savedViews.isEmpty)
    try decoded.validate(
        against: CADDocument(units: .meters, metadata: DocumentMetadata(name: "Legacy")),
        objectRegistry: .builtIn
    )
}

@Test func savedViewValidationRejectsInvalidScalePresetAndMissingReferences() throws {
    let missingNodeID = SceneNodeID()
    var metadata = ProductMetadata.empty()
    let invalidScaleView = SavedView(
        name: "Invalid scale",
        camera: SavedViewCamera(
            distanceMeters: 10.0,
            yawRadians: 0.0,
            pitchRadians: 0.0
        ),
        projection: .orthographic(heightMeters: 10.0),
        displayScale: SavedViewDisplayScale(
            displayUnit: .kilometer,
            minorTickMeters: 100.0,
            majorTickMeters: 1_000.0,
            visibleSpanMeters: 100_000.0,
            scaleBarLengthMeters: 1_000.0,
            matchedPreset: .regionalPlanning
        )
    )
    metadata.savedViews[invalidScaleView.id] = invalidScaleView

    #expect(throws: DocumentValidationError.self) {
        try metadata.validate(
            against: CADDocument(units: .meters, metadata: DocumentMetadata(name: "Invalid")),
            objectRegistry: .builtIn
        )
    }

    var missingReferenceMetadata = ProductMetadata.empty()
    let missingReferenceView = SavedView(
        name: "Missing scene reference",
        camera: SavedViewCamera(
            distanceMeters: 10.0,
            yawRadians: 0.0,
            pitchRadians: 0.0
        ),
        projection: .orthographic(heightMeters: 10.0),
        visibility: SavedViewVisibility(visibleSceneNodeIDs: [missingNodeID]),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    missingReferenceMetadata.savedViews[missingReferenceView.id] = missingReferenceView

    #expect(throws: DocumentValidationError.self) {
        try missingReferenceMetadata.validate(
            against: CADDocument(units: .meters, metadata: DocumentMetadata(name: "Missing Reference")),
            objectRegistry: .builtIn
        )
    }

    var ambiguousProjectionMetadata = ProductMetadata.empty()
    let ambiguousProjectionView = SavedView(
        name: "Ambiguous projection",
        camera: SavedViewCamera(
            distanceMeters: 10.0,
            yawRadians: 0.0,
            pitchRadians: 0.0
        ),
        projection: SavedViewProjection(
            mode: .orthographic,
            orthographicHeightMeters: 10.0,
            fieldOfViewRadians: Double.pi / 3.0
        ),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    ambiguousProjectionMetadata.savedViews[ambiguousProjectionView.id] = ambiguousProjectionView

    #expect(throws: DocumentValidationError.self) {
        try ambiguousProjectionMetadata.validate(
            against: CADDocument(units: .meters, metadata: DocumentMetadata(name: "Ambiguous Projection")),
            objectRegistry: .builtIn
        )
    }
}
