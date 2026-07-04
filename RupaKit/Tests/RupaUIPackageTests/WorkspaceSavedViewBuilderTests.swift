import RupaCore
import RupaRendering
import SwiftCAD
import Testing
@testable import RupaUI

@MainActor
@Test func workspaceSavedViewBuilderCapturesCurrentProjectionAndScale() throws {
    let session = EditorSession()
    _ = try session.execute(
        .setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    )
    let basis = ViewportProjectionBasis.orbit(yaw: 0.72, elevation: 0.44)
    let target = Point3D(x: 120.0, y: 35.0, z: -42.0)
    let builder = WorkspaceSavedViewBuilder()

    let savedView = builder.makeSavedView(
        name: "Current",
        document: session.document,
        projectionBasis: basis,
        target: target
    )

    #expect(savedView.name == "Current")
    #expect(savedView.camera.target == target)
    #expect(abs(savedView.camera.yawRadians - Double(basis.orbitYawRadians)) < 1.0e-9)
    #expect(abs(savedView.camera.pitchRadians - Double(basis.orbitElevationRadians)) < 1.0e-9)
    #expect(savedView.projection.mode == .orthographic)
    #expect(savedView.projection.orthographicHeightMeters == session.document.ruler.visibleSpanMeters)
    #expect(savedView.displayScale.matchedPreset == .sitePlanning)
    #expect(savedView.displayScale.scaleBarLengthMeters == session.document.ruler.majorTickMeters)
}

@Test func workspaceSavedViewBuilderRestoresProjectionBasisFromSavedCamera() {
    let savedView = SavedView(
        name: "Restore",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 100.0,
            yawRadians: 0.31,
            pitchRadians: 0.58
        ),
        projection: .orthographic(heightMeters: 40.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    let restored = WorkspaceSavedViewBuilder().projectionBasis(for: savedView)

    #expect(abs(restored.orbitYawRadians - 0.31) < 1.0e-9)
    #expect(abs(restored.orbitElevationRadians - 0.58) < 1.0e-9)
}

@MainActor
@Test func workspaceSavedViewBuilderSortsAndNamesSavedViewsDeterministically() throws {
    let session = EditorSession()
    let builder = WorkspaceSavedViewBuilder()
    let first = builder.makeSavedView(
        name: "B View",
        document: session.document,
        projectionBasis: .isometric
    )
    let second = builder.makeSavedView(
        name: "A View",
        document: session.document,
        projectionBasis: .isometric
    )
    _ = try session.execute(.createSavedView(first))
    _ = try session.execute(.createSavedView(second))

    let sortedViews = builder.sortedSavedViews(in: session.document)

    #expect(sortedViews.map(\.name) == ["A View", "B View"])
    #expect(builder.nextSavedViewName(in: session.document) == "View 3")
}
