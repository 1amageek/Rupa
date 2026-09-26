import AppKit
import Foundation
import RupaCore
import Testing
@testable import RupaUI

/// Place picks its source once and then places at every destination with the session's options.
@Suite struct WorkspacePlaceSessionTests {
    @Test func placementsWaitForTheSourceAndRepeatForConsecutiveCopies() throws {
        let box = SceneNodeID()
        var session = WorkspacePlaceSession(rootSceneNodeIDs: [box])
        let destination = WorkspacePlaceSession.Reference(point: Point3D(x: 1, y: 0, z: 0), normal: nil)
        #expect(throws: EditorError.self) {
            _ = try session.command(destination: destination)
        }

        session.pickSource(WorkspacePlaceSession.Reference(point: .origin, normal: nil))
        session.copyCount = 3
        session.output = .componentInstance
        guard case .placeSceneNodes(let ids, let placements, let output, nil) = try session.command(destination: destination) else {
            Issue.record("Place must submit placeSceneNodes.")
            return
        }
        #expect(ids == [box])
        #expect(output == .componentInstance)
        #expect(placements.count == 3)

        session.booleanOperation = .union
        #expect(throws: EditorError.self) {
            _ = try session.command(destination: destination)
        }
        let target = SceneNodeID()
        var onBody = destination
        onBody.bodySceneNodeID = target
        guard case .placeSceneNodes(_, _, .independentCopy, let boolean?) = try session.command(destination: onBody) else {
            Issue.record("A Boolean placement must place independent copies with the Boolean.")
            return
        }
        #expect(boolean == SceneNodePlacementBoolean(operation: .union, targetSceneNodeID: target))
        for (index, placement) in placements.enumerated() {
            #expect(abs(placement.matrix.values[3] - Double(index + 1)) < 1.0e-12)
        }
    }
}

/// Copy with Placement travels through a pasteboard under Rupa's type and pastes from its reference.
@Suite struct WorkspaceScenePlacementClipboardTests {
    private func payload() throws -> WorkspaceScenePlacementPayload {
        var document = DesignDocument.empty(named: "Source")
        let feature = try document.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        let box = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == feature }).id
        return WorkspaceScenePlacementPayload(
            fragment: try document.sceneFragment(copying: [box]),
            basePoint: Point3D(x: 0.05, y: 0.05, z: 0),
            baseNormal: Vector3D(x: 0, y: 0, z: -1)
        )
    }

    @MainActor
    @Test func thePayloadRoundTripsThroughAPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RupaTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let clipboard = WorkspaceSceneClipboard(pasteboard: pasteboard)
        #expect(try clipboard.read() == nil)
        let copied = try payload()
        try clipboard.write(copied)
        #expect(try clipboard.read() == copied)
    }

    @Test func pastingStartsAtItsReferenceAndInsertsIndependentCopies() throws {
        let copied = try payload()
        var session = WorkspacePlaceSession(pasting: copied)
        #expect(!session.allowsInstances)
        session.output = .componentInstance
        let destination = WorkspacePlaceSession.Reference(point: Point3D(x: 1, y: 2, z: 0), normal: .unitZ)
        guard case .pasteSceneFragment(let fragment, let placements, nil) = try session.command(destination: destination) else {
            Issue.record("Paste with Placement must submit pasteSceneFragment.")
            return
        }
        #expect(fragment == copied.fragment)
        let moved = try #require(placements.first).applied(to: copied.basePoint)
        #expect(abs(moved.x - 1) < 1.0e-12 && abs(moved.y - 2) < 1.0e-12 && abs(moved.z) < 1.0e-12)
    }
}
