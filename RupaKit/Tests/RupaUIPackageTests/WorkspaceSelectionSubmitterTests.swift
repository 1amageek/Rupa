import Foundation
import RupaCore
import RupaKit
import SwiftCAD
import Testing
@testable import RupaUI

/// A selection made in a command's completion targets what the command published: the submitter
/// checks it against the workspace's latest view, which the snapshot captured before the command
/// would refuse.
@MainActor
@Test(.timeLimit(.minutes(1)))
func aMovedEdgeIsSelectableRightAfterTheMoveCommits() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    _ = try await workspace.evaluate()
    try await commit([
        .createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
    ], on: workspace)
    let before = try #require(workspace.view)
    let edges = try TopologySnapshotService().snapshot(document: before.document.document)
        .entries.filter { $0.kind == .edge }
    let maxZ = edges.compactMap { $0.midpoint?.z }.max() ?? 0
    let edge = try #require(edges.first { abs(($0.midpoint?.z ?? -1) - maxZ) < 1e-9 }?.selectionTarget())

    try await commit([
        .moveBodyEdges(targets: [edge], direction: Vector3D(x: 0, y: 0, z: 1), distance: .length(0.01, .meter))
    ], on: workspace)
    let after = try #require(workspace.view)
    let featureID = try #require(after.document.document.productMetadata.sceneNodes[edge.sceneNodeID]?.reference?.featureID)
    let moved = try after.document.document.topologyTargets(following: [edge], to: featureID)
    #expect(moved.count == 1)

    // The snapshot captured before the move refuses the moved edge: the node now names the move.
    var stale = before.selection
    #expect(throws: (any Error).self) {
        try stale.selectTargets(moved, in: before.document.document)
    }

    let submitter = WorkspaceSelectionSubmitter(workspace: workspace) { operation in
        Task { @MainActor in try await operation() }
    }
    let published = try await submitter.submit { selection, document in
        try selection.selectTargets(moved, in: document)
    }.value
    #expect(published.selection.selectedTargets == moved)
    #expect(workspace.view?.selection.selectedTargets == moved)
}

/// A change that does not apply to the latest view is refused at once, before anything is queued.
@MainActor
@Test(.timeLimit(.minutes(1)))
func aSelectionTheLatestViewRefusesThrowsBeforeItIsQueued() async throws {
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    _ = try await workspace.evaluate()
    var queued = false
    let submitter = WorkspaceSelectionSubmitter(workspace: workspace) { operation in
        queued = true
        return Task { @MainActor in try await operation() }
    }
    #expect(throws: (any Error).self) {
        try submitter.submit { selection, document in
            try selection.selectSceneNodes([SceneNodeID()], in: document)
        }
    }
    #expect(!queued)
}

@MainActor
private func commit(_ commands: [EditorCommand], on workspace: ProjectWorkspace) async throws {
    let current = try #require(workspace.view)
    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "test", commands: commands, from: current
    )
    _ = try await workspace.perform(action)
}
