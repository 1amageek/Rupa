import RupaCore
import RupaKit
import Testing
@testable import RupaUI

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceLaunchProjectFixtureCreatesActiveCustomPlane() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    _ = try await workspace.evaluate()
    let snapshot = try await WorkspaceLaunchProjectFixture.applyIfRequested(
        arguments: [WorkspaceLaunchProjectFixture.activeCustomConstructionPlaneArgument],
        to: workspace
    )
    let activePlane = try #require(
        ConstructionPlaneSummaryService().summarize(
            document: snapshot.document.document,
            activePlaneID: snapshot.workspaceState.activeConstructionPlaneID
        ).planes.first(where: { $0.isActive })
    )

    #expect(activePlane.name == WorkspaceLaunchProjectFixture.customConstructionPlaneName)
    #expect(snapshot.document.document.productMetadata.constructionPlanes.count == 1)

    guard case .plane(let plane) = activePlane.plane else {
        Issue.record("Fixture must install a custom arbitrary plane.")
        return
    }
    #expect(plane.origin.x == 0.12)
    #expect(plane.origin.y == 0.08)
    #expect(plane.origin.z == -0.06)
    #expect(abs(plane.normal.length - 1.0) < 1.0e-12)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceLaunchProjectFixtureLeavesDefaultProjectUnmodified() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    let initial = try await workspace.evaluate()
    let result = try await WorkspaceLaunchProjectFixture.applyIfRequested(
        arguments: [],
        to: workspace
    )

    #expect(result.publicationSequence == initial.publicationSequence)
    #expect(result.document.document.productMetadata.constructionPlanes.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceLaunchProjectFixtureCreatesSelectedCustomPlane() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    _ = try await workspace.evaluate()
    let snapshot = try await WorkspaceLaunchProjectFixture.applyIfRequested(
        arguments: [WorkspaceLaunchProjectFixture.selectedCustomConstructionPlaneArgument],
        to: workspace
    )
    let selectedTarget = try #require(snapshot.selection.selectedTargets.first)
    let activePlaneID = try #require(snapshot.workspaceState.activeConstructionPlaneID)

    #expect(snapshot.selection.selectedTargets.count == 1)
    guard case .constructionPlane(let selectedPlaneID) = selectedTarget.component else {
        Issue.record("Selected fixture target must be the construction-plane component.")
        return
    }
    #expect(selectedPlaneID == activePlaneID)
}
