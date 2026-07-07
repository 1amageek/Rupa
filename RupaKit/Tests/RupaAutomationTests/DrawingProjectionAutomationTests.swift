import SwiftCAD
import Testing
import RupaCore
@testable import RupaAutomation

@MainActor
@Test func automationGeneratesDrawingProjectionFromSavedView() throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Automation Drawing Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(2.0, .meter),
            depth: .length(2.0, .meter),
            direction: .normal
        )
    )
    let savedView = SavedView(
        name: "Automation Drawing View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .orthographic(heightMeters: 6.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try session.execute(.createSavedView(savedView))
    let generation = session.generation

    let result = try runner.execute(
        .generateDrawingProjection(
            query: DrawingProjectionQuery(savedViewID: savedView.id)
        ),
        in: session
    )
    let projection = try #require(result.drawingProjection)

    #expect(result.commandName == "generateDrawingProjection")
    #expect(!result.didMutate)
    #expect(result.generation == generation)
    #expect(result.savedViews?.map(\.id).contains(savedView.id) == true)
    #expect(projection.savedViewID == savedView.id)
    #expect(projection.strokeCount == 12)
    #expect(projection.unclassifiedStrokeCount == 0)
    #expect(projection.visibilitySegmentCount >= projection.strokeCount)
    #expect(projection.visibleSegmentCount > 0)
    #expect(projection.hiddenSegmentCount > 0)
    #expect(projection.unclassifiedSegmentCount == 0)
    #expect(result.message.contains("12 stroke"))
    #expect(result.message.contains("visibility segment"))
}

@MainActor
@Test func automationGeneratesDrawingProjectionFromTransientViewWithoutMutation() throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Transient Drawing Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(2.0, .meter),
            depth: .length(2.0, .meter),
            direction: .normal
        )
    )
    let generation = session.generation
    let savedView = SavedView(
        name: "Transient Drawing View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .orthographic(heightMeters: 6.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )

    let result = try runner.execute(
        .generateDrawingProjectionFromView(
            savedView: savedView,
            toleranceMeters: nil,
            maximumStrokeCount: 100
        ),
        in: session
    )
    let projection = try #require(result.drawingProjection)

    #expect(result.commandName == "generateDrawingProjection")
    #expect(!result.didMutate)
    #expect(result.generation == generation)
    #expect(session.document.productMetadata.savedViews.isEmpty)
    #expect(projection.savedViewID == savedView.id)
    #expect(projection.savedViewName == "Transient Drawing View")
    #expect(projection.strokeCount == 12)
    #expect(projection.visibilitySegmentCount >= projection.strokeCount)
    #expect(projection.visibleSegmentCount > 0)
    #expect(projection.hiddenSegmentCount > 0)
}
