import SwiftCAD
import Testing
@testable import RupaCore

/// Booleans combine bodies where they are displayed: the tool's placement relative to the target
/// reaches the kernel and the result is shown where the target is.
@Suite struct PlacedBooleanTests {
    private let tolerance = 1.0e-9
    private let cube = 0.1 * 0.1 * 0.1

    @MainActor
    private func twoCubes() throws -> (EditorSession, target: SceneNodeID, tool: SceneNodeID) {
        let session = EditorSession()
        for name in ["Target", "Tool"] {
            _ = try session.execute(.createExtrudedRectangle(
                name: name, plane: .xy,
                width: .length(0.1, .meter), height: .length(0.1, .meter),
                depth: .length(0.1, .meter), direction: .normal
            ))
        }
        let bodies = session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }
        let target = try #require(bodies.first { $0.name.hasPrefix("Target") }).id
        let tool = try #require(bodies.first { $0.name.hasPrefix("Tool") }).id
        return (session, target, tool)
    }

    private func volume(_ document: DesignDocument) throws -> Double {
        try MeasurementService().measure(document: document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
    }

    @MainActor
    @Test func aBooleanUsesTheDisplayedPlacementOfItsOperands() throws {
        let (session, target, tool) = try twoCubes()
        let parentMove = try Transform3D.translation(Vector3D(x: 1, y: 0, z: 0))
        _ = try session.execute(.setSceneNodeTransform(id: target, localTransform: parentMove))
        _ = try session.execute(.setSceneNodeTransform(
            id: tool, localTransform: try Transform3D.translation(Vector3D(x: 1.05, y: 0, z: 0))
        ))
        let metadata = session.document.productMetadata
        let targetFeature = try #require(metadata.sceneNodes[target]?.reference?.featureID)
        let toolFeature = try #require(metadata.sceneNodes[tool]?.reference?.featureID)

        let result = try session.execute(.createBoolean(
            name: "Union",
            targets: [BooleanTargetReference(featureID: targetFeature)],
            tool: BooleanToolReference(featureID: toolFeature),
            operation: .union,
            keepTools: false
        ))
        #expect(abs(try volume(session.document) - 1.5 * cube) < tolerance)
        let resultFeature = try #require(result.generatedIdentities.featureIDs.last)
        let hierarchy = try SceneNodeHierarchy(metadata: session.document.productMetadata)
        let resultNode = try #require(hierarchy.presentingSceneNodeID(for: resultFeature))
        #expect(try hierarchy.worldTransform(of: resultNode) == parentMove)
    }

    @MainActor
    @Test func placeCombinesEachCopyWithTheBodyItWasPlacedOn() throws {
        let (session, target, tool) = try twoCubes()
        let halfCube = try Transform3D.translation(Vector3D(x: 0.05, y: 0, z: 0))

        _ = try session.execute(.placeSceneNodes(
            ids: [tool],
            placements: [halfCube],
            output: .independentCopy,
            boolean: SceneNodePlacementBoolean(operation: .difference, targetSceneNodeID: target)
        ))
        // The target lost the half the copy overlapped; the original tool is untouched.
        #expect(abs(try volume(session.document) - 1.5 * cube) < tolerance)
        let hidden = session.document.productMetadata.sceneNodes.values.filter {
            $0.reference?.kind == .body && !$0.isVisible
        }
        #expect(hidden.count == 1)
    }

    @MainActor
    @Test func aScaledPlacementCannotBeCombined() throws {
        let (session, target, tool) = try twoCubes()
        let before = session.document
        #expect(throws: (any Error).self) {
            _ = try session.execute(.placeSceneNodes(
                ids: [tool],
                placements: [try Transform3D.scale(Vector3D(x: 2, y: 2, z: 2), about: .origin)],
                output: .independentCopy,
                boolean: SceneNodePlacementBoolean(operation: .union, targetSceneNodeID: target)
            ))
        }
        #expect(session.document.productMetadata == before.productMetadata)
    }
}
