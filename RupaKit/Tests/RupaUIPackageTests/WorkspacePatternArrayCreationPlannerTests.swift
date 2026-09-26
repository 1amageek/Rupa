import RupaCore
import Testing
@testable import RupaUI

/// New arrays start from values derived from the selection, in the frame Core reads them in.
@Suite struct WorkspacePatternArrayCreationPlannerTests {
    private func nestedBox() throws -> (ProductMetadata, box: SceneNodeID, parentWorld: Transform3D) {
        let box = SceneNode(name: "Box", reference: .body(FeatureID()))
        let parentWorld = try Transform3D.translation(Vector3D(x: 1, y: 2, z: 3))
            .composed(with: try Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 2))
        let parent = SceneNode(name: "Parent", childIDs: [box.id], localTransform: parentWorld)
        let root = SceneNode(name: "Scene", childIDs: [parent.id])
        let existing = PatternArraySource(
            name: "Radial Array",
            definitionID: ComponentDefinitionID(),
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(direction: .unitX, distance: .scalar(1), copyCount: 1)
            )),
            outputMode: .independentCopy,
            rootSceneNodeID: SceneNodeID()
        )
        let metadata = ProductMetadata(
            sceneNodes: [root.id: root, parent.id: parent, box.id: box],
            rootSceneNodeIDs: [root.id],
            patternArrays: [existing.id: existing]
        )
        return (metadata, box.id, parentWorld)
    }

    @Test func namesAreNumberedPastExistingArrays() throws {
        let (metadata, _, _) = try nestedBox()
        let planner = WorkspacePatternArrayCreationPlanner(metadata: metadata)
        #expect(planner.name(for: .rectangular) == "Rectangular Array")
        #expect(planner.name(for: .radial) == "Radial Array 2")
    }

    @Test func rectangularSpacingFollowsTheSelectionWidth() throws {
        let (metadata, box, _) = try nestedBox()
        let command = try WorkspacePatternArrayCreationPlanner(metadata: metadata).rectangular(
            rootSceneNodeIDs: [box],
            selectionBounds: MeasurementResult.Bounds(minX: 0, minY: 0, minZ: 0, maxX: 0.2, maxY: 0.1, maxZ: 0.1)
        )
        guard case .createPatternArrayFromSceneNodes(_, let ids, .rectangular(let rectangular), .independentCopy) = command else {
            Issue.record("Expected a rectangular array command.")
            return
        }
        #expect(ids == [box])
        #expect(rectangular.firstAxis.distance == .length(0.2 * 1.5, .meter))
        #expect(rectangular.firstAxis.copyCount == WorkspacePatternArrayCreationPlanner.initialLinearCopyCount)
        #expect(throws: EditorError.self) {
            _ = try WorkspacePatternArrayCreationPlanner(metadata: metadata).rectangular(
                rootSceneNodeIDs: [box],
                selectionBounds: MeasurementResult.Bounds(minX: 0, minY: 0, minZ: 0, maxX: 0, maxY: 0, maxZ: 0)
            )
        }
    }

    @Test func aRadialCenterAndAxisPickedInTheWorldAreReadInTheParentFrame() throws {
        let (metadata, box, parentWorld) = try nestedBox()
        let center = Point3D(x: 1, y: 3, z: 3)
        let command = try WorkspacePatternArrayCreationPlanner(metadata: metadata).radial(
            rootSceneNodeIDs: [box], centerWorld: center, axisWorld: .unitY
        )
        guard case .createPatternArrayFromSceneNodes(_, _, .radial(let radial), _) = command else {
            Issue.record("Expected a radial array command.")
            return
        }
        let mappedCenter = try parentWorld.applied(to: radial.angularAxis.center)
        let mappedAxis = try parentWorld.applyingLinearPart(to: radial.angularAxis.axis)
        #expect(abs(mappedCenter.x - center.x) < 1.0e-12 && abs(mappedCenter.y - center.y) < 1.0e-12)
        #expect(abs(mappedAxis.y - 1) < 1.0e-12 && abs(mappedAxis.x) < 1.0e-12)
    }
}
