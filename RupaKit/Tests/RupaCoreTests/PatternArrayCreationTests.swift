import SwiftCAD
import Testing
@testable import RupaCore

/// Arrays made from selected objects in one step keep the objects' placement.
@Suite struct PatternArrayCreationTests {
    @MainActor
    @Test func anArrayOfNestedObjectsIsPlacedInTheirParentFrameAndIsOneUndoStep() throws {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        ))
        let box = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body }).id
        let group = try session.execute(.groupSceneNodes(name: "Parent", memberIDs: [box], origin: nil))
        let parent = try #require(group.generatedIdentities.sceneNodeIDs.first)
        _ = try session.execute(.setSceneNodeTransform(
            id: parent,
            localTransform: try Transform3D.translation(Vector3D(x: 2, y: 0, z: 0))
                .composed(with: try Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 2))
        ))
        let before = session.document

        let result = try session.execute(.createPatternArrayFromSceneNodes(
            name: "Row", rootSceneNodeIDs: [box],
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(direction: .unitX, distance: .length(0.25, .meter), copyCount: 2)
            )),
            outputMode: .independentCopy
        ))
        let document = session.document
        let sourceID = try #require(result.generatedIdentities.patternArraySourceIDs.first)
        let source = try #require(document.productMetadata.patternArrays[sourceID])
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        #expect(hierarchy.parentID(of: source.rootSceneNodeID) == parent)
        #expect(document.productMetadata.componentDefinitions[source.definitionID]?.rootSceneNodeIDs == [box])

        // The parent turns +X into world +Y, so each copy steps along world Y.
        let boxWorld = try hierarchy.worldTransform(of: box)
        let copies = try source.outputSceneNodeIDs.map { output -> Transform3D in
            let copiedRoot = try #require(document.productMetadata.sceneNodes[output]?.childIDs.first)
            return try hierarchy.worldTransform(of: copiedRoot)
        }
        #expect(copies.count == 2)
        for (index, copy) in copies.enumerated() {
            let step = 0.25 * Double(index + 1)
            #expect(abs(copy.matrix.values[3] - boxWorld.matrix.values[3]) < 1.0e-12)
            #expect(abs(copy.matrix.values[7] - boxWorld.matrix.values[7] - step) < 1.0e-12)
        }
        let volume = try MeasurementService().measure(document: document, ruler: .standard(for: .meter))
            .totals.solidVolumeCubicMeters
        #expect(abs(volume - 3 * 0.001) < 1.0e-12)

        _ = try session.undo()
        #expect(session.document.productMetadata == before.productMetadata)
    }

    @MainActor
    @Test func aSelectionCoreCannotCopyIsRefusedWithoutMutation() throws {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        ))
        let root = try #require(session.document.productMetadata.rootSceneNodeIDs.first)
        let before = session.document
        #expect(throws: (any Error).self) {
            _ = try session.execute(.createPatternArrayFromSceneNodes(
                name: "Row", rootSceneNodeIDs: [root],
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(direction: .unitX, distance: .length(0.25, .meter), copyCount: 2)
                )),
                outputMode: .independentCopy
            ))
        }
        #expect(session.document.productMetadata == before.productMetadata)
    }
}
