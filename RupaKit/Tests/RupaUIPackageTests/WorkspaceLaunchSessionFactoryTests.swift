import Testing
import RupaCore
@testable import RupaUI

@MainActor
@Test func workspaceLaunchSessionFactoryCreatesActiveCustomPlaneFixture() throws {
    let session = WorkspaceLaunchSessionFactory.makeSession(
        arguments: [
            WorkspaceLaunchSessionFactory.activeCustomConstructionPlaneFixtureArgument,
        ]
    )
    let activePlane = try #require(session.activeConstructionPlane)

    #expect(activePlane.name == WorkspaceLaunchSessionFactory.activeCustomConstructionPlaneFixtureName)
    #expect(session.document.productMetadata.constructionPlanes.count == 1)
    #expect(session.document.productMetadata.activeConstructionPlaneID == activePlane.id)

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
@Test func workspaceLaunchSessionFactoryLeavesDefaultSessionUnmodified() {
    let session = WorkspaceLaunchSessionFactory.makeSession(arguments: [])

    #expect(session.activeConstructionPlane == nil)
    #expect(session.document.productMetadata.constructionPlanes.isEmpty)
}

@MainActor
@Test func workspaceLaunchSessionFactoryCreatesSelectedCustomPlaneFixture() throws {
    let session = WorkspaceLaunchSessionFactory.makeSession(
        arguments: [
            WorkspaceLaunchSessionFactory.selectedCustomConstructionPlaneFixtureArgument,
        ]
    )
    let activePlane = try #require(session.activeConstructionPlane)
    let selectedTarget = try #require(session.selection.selectedTargets.first)

    #expect(session.selection.selectedTargets.count == 1)
    #expect(activePlane.name == WorkspaceLaunchSessionFactory.activeCustomConstructionPlaneFixtureName)

    guard case .constructionPlane(let selectedPlaneID) = selectedTarget.component else {
        Issue.record("Selected fixture target must be the construction-plane component.")
        return
    }
    #expect(selectedPlaneID == activePlane.id)
}
