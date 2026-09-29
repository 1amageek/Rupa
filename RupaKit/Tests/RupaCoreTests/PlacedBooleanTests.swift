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
            tools: [BooleanToolReference(featureID: toolFeature)],
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
        // The target lost the half the copy overlapped; the original tool is untouched, and the
        // consumed copy has no object left.
        #expect(abs(try volume(session.document) - 1.5 * cube) < tolerance)
        #expect(session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }.count == 2)
        try expectEveryBodyObjectPresentsAnEvaluatedBody(session.document)
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

    @MainActor
    private func cubes(_ names: [String], at xs: [Double]) throws -> (EditorSession, [FeatureID]) {
        let session = EditorSession()
        var features: [FeatureID] = []
        for (name, x) in zip(names, xs) {
            _ = try session.execute(.createExtrudedRectangle(
                name: name, plane: .xy,
                width: .length(0.1, .meter), height: .length(0.1, .meter),
                depth: .length(0.1, .meter), direction: .normal
            ))
            let node = try #require(session.document.productMetadata.sceneNodes.values.first {
                $0.reference?.kind == .body && $0.name.hasPrefix(name)
            })
            _ = try session.execute(.setSceneNodeTransform(id: node.id, localTransform: try Transform3D.translation(Vector3D(x: x, y: 0, z: 0))))
            features.append(try #require(node.reference?.featureID))
        }
        return (session, features)
    }

    /// A kept tool displayed elsewhere stays whole beside the result.
    @MainActor
    @Test func aToolDisplayedElsewhereCanBeKept() throws {
        let (session, features) = try cubes(["Target", "Tool"], at: [0, 0.05])
        _ = try session.execute(.createBoolean(
            name: "Difference", targets: [BooleanTargetReference(featureID: features[0])],
            tools: [BooleanToolReference(featureID: features[1])], operation: .difference, keepTools: true
        ))
        #expect(abs(try volume(session.document) - 1.5 * cube) < tolerance)
    }

    /// Targets displayed at different places combine where they are displayed.
    @MainActor
    @Test func targetsDisplayedApartCombineWhereTheyAre() throws {
        let (session, features) = try cubes(["First", "Second", "Bridge"], at: [0, 0.15, 0.075])
        _ = try session.execute(.createBoolean(
            name: "Union",
            targets: [BooleanTargetReference(featureID: features[0]), BooleanTargetReference(featureID: features[1])],
            tools: [BooleanToolReference(featureID: features[2])], operation: .union, keepTools: false
        ))
        // [0, 0.1] ∪ [0.15, 0.25] ∪ [0.075, 0.175] along x.
        #expect(abs(try volume(session.document) - 2.5 * cube) < tolerance)
    }

    /// Several tools act together: both bites leave the target.
    @MainActor
    @Test func severalToolsSubtractTogether() throws {
        let (session, features) = try cubes(["Target", "Left", "Right"], at: [0, -0.075, 0.075])
        _ = try session.execute(.createBoolean(
            name: "Difference", targets: [BooleanTargetReference(featureID: features[0])],
            tools: [BooleanToolReference(featureID: features[1]), BooleanToolReference(featureID: features[2])],
            operation: .difference, keepTools: false
        ))
        #expect(abs(try volume(session.document) - 0.5 * cube) < tolerance)
    }

    @MainActor
    @Test func aReferenceCarryingAPlacementIsRefused() throws {
        let (session, features) = try cubes(["Target", "Tool"], at: [0, 0.05])
        let before = session.document
        #expect(throws: (any Error).self) {
            _ = try session.execute(.createBoolean(
                name: "Union", targets: [BooleanTargetReference(featureID: features[0])],
                tools: [BooleanToolReference(featureID: features[1], placement: .translated(by: Vector3D(x: 1, y: 0, z: 0)))],
                operation: .union, keepTools: false
            ))
        }
        #expect(session.document.cadDocument.designGraph == before.cadDocument.designGraph)
    }

    /// Placing copies with a slice cuts the target once by all of them, each piece its own object.
    @MainActor
    @Test func placingWithASliceCutsOnceByEveryCopy() throws {
        let (session, target, tool) = try twoCubes()
        _ = try session.execute(.placeSceneNodes(
            ids: [tool],
            placements: [try Transform3D.translation(Vector3D(x: 0.075, y: 0, z: 0)), try Transform3D.translation(Vector3D(x: -0.075, y: 0, z: 0))],
            output: .independentCopy,
            boolean: SceneNodePlacementBoolean(operation: .slice, targetSceneNodeID: target)
        ))
        let pieces = session.document.productMetadata.sceneNodes.values.filter { $0.name.hasPrefix("Placed Slice ") && $0.isVisible }
        #expect(pieces.count == 3)
        // The target's volume is kept, cut into pieces; the original tool is untouched.
        #expect(abs(try volume(session.document) - 2 * cube) < tolerance)
        #expect(session.evaluationStatus == .valid)
    }
}
