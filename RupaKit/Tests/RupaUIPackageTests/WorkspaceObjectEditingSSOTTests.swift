import Foundation
import RupaCore
import RupaKit
import RupaProject
import SwiftCAD
import Testing
@testable import RupaRendering
@testable import RupaUI

@MainActor
@Suite("Object editing SSOT", .serialized, .timeLimit(.minutes(1)))
struct WorkspaceObjectEditingSSOTTests {
    private func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func fixture(cylinder: Bool = false) async throws -> (ProjectWorkspace, SceneNodeID, SceneNodeID) {
        let session = EditorSession()
        _ = try #require(cylinder ? session.createDefaultExtrudedCircle() : session.createDefaultExtrudedRectangle())
        var document = session.document
        var first = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body })
        var second = first
        second.id = SceneNodeID()
        second.name = "Shared source occurrence"
        second.childIDs = []
        second.localTransform = try WorkspaceTransformMatrix.replacing(.translationX, with: 3, in: .identity)
        first.localTransform = try WorkspaceTransformMatrix.transform(from: .init(
            translation: .init(x: 0.2, y: 0.3, z: 0.4), rotationDegrees: .init(x: 20, y: 30, z: 40),
            scale: .init(x: -2, y: 3, z: 4), shear: .init(x: 0.3, y: 0.2, z: -0.1)))
        let parent = SceneNode(name: "Rotated parent", childIDs: [first.id],
            localTransform: try WorkspaceTransformMatrix.transform(from: .init(
                translation: .init(x: 0.5, y: 1, z: 1.5), rotationDegrees: .init(x: 0, y: 0, z: 90),
                scale: .init(x: 2, y: 1, z: 1))))
        for id in Array(document.productMetadata.sceneNodes.keys) {
            document.productMetadata.sceneNodes[id]?.childIDs.removeAll { $0 == first.id }
        }
        document.productMetadata.rootSceneNodeIDs.removeAll { $0 == first.id }
        document.productMetadata.sceneNodes[first.id] = first
        document.productMetadata.sceneNodes[second.id] = second
        document.productMetadata.sceneNodes[parent.id] = parent
        document.productMetadata.rootSceneNodeIDs += [parent.id, second.id]
        let controller = try ProjectController(document: document,
            evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge())
        let workspace = ProjectWorkspace(project: controller)
        _ = try await workspace.evaluate()
        return (workspace, first.id, second.id)
    }

    private func shape(_ id: SceneNodeID, in snapshot: ProjectViewSnapshot) throws -> InspectorObjectShape {
        let node = try #require(snapshot.document.document.productMetadata.sceneNodes[id])
        return try #require(try WorkspaceObjectShapeInspectorStateBuilder(snapshot: snapshot).shapes(for: [node])?.first)
    }

    private func perform(_ commands: [EditorCommand], in workspace: ProjectWorkspace) async throws -> ProjectViewSnapshot {
        let before = try #require(workspace.view)
        _ = try await workspace.perform(DefaultProjectWorkspaceActionPlanner().source(
            name: "SSOT edit", commands: commands, from: before))
        return try #require(workspace.view)
    }

    @Test func canvasAndInspectorSharePlacementAcrossParentShearAndUndo() async throws {
        let (workspace, first, second) = try await fixture()
        let base = try #require(workspace.view)
        let document = base.document.document
        let initial = try shape(first, in: base)
        let other = try shape(second, in: base)
        #expect(initial.center != other.center)
        let node = try #require(document.productMetadata.sceneNodes[first])
        let parent = try #require(try ViewportSceneNodeParentFrames(document: document).parentWorldTransform(of: first))
        let next = try #require(try ViewportWorldTransformAlgebra.localTransform(
            applying: ViewportWorldTransformAlgebra.translation(.init(x: 0, y: 0.25, z: 0)),
            within: parent, to: node.localTransform))
        let target = ViewportBodyPlacementDragTarget(reference: try #require(node.reference), sceneNodeID: first,
            baseLocalTransform: node.localTransform, localTransform: next, baseParentWorldTransform: parent)
        var current = try await perform(WorkspaceTransformMatrix.commands(placements: [target], in: document), in: workspace)
        let moved = try shape(first, in: current)
        let initialCenter = try #require(initial.center)
        let movedCenter = try #require(moved.center)
        #expect(abs(movedCenter.y - initialCenter.y - 0.25) < 1e-8)
        #expect(abs(movedCenter.x - initialCenter.x) < 1e-8)
        #expect(abs(movedCenter.z - initialCenter.z) < 1e-8)
        #expect(moved.size == initial.size)
        #expect(try shape(second, in: current).center == other.center)
        #expect(throws: Error.self) {
            try WorkspaceTransformMatrix.commands(placements: [target], in: current.document.document)
        }
        for axis in [InspectorObjectAxis.x, .y, .z] {
            let before = current
            let center = try #require(try shape(first, in: before).center)
            let value = (axis == .x ? center.x : axis == .y ? center.y : center.z) + 0.1
            let commands = try WorkspaceObjectShapeInspectorStateBuilder(snapshot: before)
                .centerCommands(axis, meters: value, nodeIDs: [first])
            current = try await perform(commands, in: workspace)
            let actual = try #require(try shape(first, in: current).center)
            #expect(abs(actual.x - (axis == .x ? value : center.x)) < 1e-8)
            #expect(abs(actual.y - (axis == .y ? value : center.y)) < 1e-8)
            #expect(abs(actual.z - (axis == .z ? value : center.z)) < 1e-8)
            let transform = try #require(current.document.document.productMetadata.sceneNodes[first]?.localTransform)
            for index in [0, 1, 2, 4, 5, 6, 8, 9, 10] {
                #expect(abs(transform.matrix.values[index] - node.localTransform.matrix.values[index]) < 1e-10)
            }
            #expect(try encoded(current.document.document.cadDocument) == encoded(document.cadDocument))
            #expect(try shape(second, in: current).center == other.center)
            let undone = try await workspace.undo()
            #expect(undone.document.document.productMetadata == before.document.document.productMetadata)
            #expect(try encoded(undone.document.document.cadDocument) == encoded(before.document.document.cadDocument))
            current = try await workspace.redo()
        }
        let commands = try WorkspaceTransformMatrix.commands(replacing: .scaleZ, with: 5,
            nodeIDs: [first], in: current.document.document)
        current = try await perform(commands, in: workspace)
        #expect(try shape(first, in: current).size == initial.size)
    }

    @Test(arguments: [false, true])
    func sourceDimensionsIgnorePlacementAndShareCanvasCommands(cylinder: Bool) async throws {
        let (workspace, first, second) = try await fixture(cylinder: cylinder)
        var current = try #require(workspace.view)
        let transforms = [first, second].map { current.document.document.productMetadata.sceneNodes[$0]?.localTransform }
        for axis in [InspectorObjectAxis.x, .y, .z] {
            let before = current
            let size = try #require(try shape(first, in: before).size)
            #expect(try shape(second, in: before).size == size)
            let meters = (axis == .x ? size.x : axis == .y ? size.y : size.z) * 1.5
            let commands = try WorkspaceObjectShapeInspectorStateBuilder.sizeCommands(axis, meters: meters,
                nodeIDs: [first, second], in: before.document.document)
            #expect(commands.count == 1)
            let kind: ObjectDimensionKind = axis == .x ? .sizeX : axis == .y ? .sizeY : .sizeZ
            #expect(commands == [.setObjectDimension(target: .init(sceneNodeID: first), kind: kind,
                value: .length(meters, .meter))])
            current = try await perform(commands, in: workspace)
            let result = try #require(try shape(first, in: current).size)
            #expect(abs((axis == .x ? result.x : axis == .y ? result.y : result.z) - meters) < 1e-8)
            #expect(abs(result.y - (axis == .y ? meters : size.y)) < 1e-8)
            #expect(abs(result.x - (axis == .x || (cylinder && axis == .z) ? meters : size.x)) < 1e-8)
            #expect(abs(result.z - (axis == .z || (cylinder && axis == .x) ? meters : size.z)) < 1e-8)
            #expect(try shape(second, in: current).size == result)
            #expect([first, second].map { current.document.document.productMetadata.sceneNodes[$0]?.localTransform } == transforms)
            #expect(current.viewport.items != before.viewport.items)
            let undone = try await workspace.undo()
            #expect(undone.document.document.productMetadata == before.document.document.productMetadata)
            #expect(try encoded(undone.document.document.cadDocument) == encoded(before.document.document.cadDocument))
            current = try await workspace.redo()
        }
        if cylinder {
            current = try await perform(WorkspaceObjectShapeInspectorStateBuilder.dimensionCommands(
                .radius, meters: 0.012, nodeIDs: [first], in: current.document.document), in: workspace)
            let result = try shape(first, in: current)
            #expect(abs(try #require(result.size).x - 0.024) < 1e-8)
            let property = try #require(result.definition?.properties.first { $0.renderBinding == .radius })
            #expect(result.properties.value(for: property.id, default: property.defaultValue) == .length(0.012))
        }
    }

    @Test func invalidAndLockedEditsCannotPublishPartialChanges() async throws {
        let (workspace, first, second) = try await fixture()
        let current = try await perform([.setSceneNodeLock(id: second, isLocked: true)], in: workspace)
        for meters in [0, -1, Double.nan, Double.infinity] {
            #expect(throws: Error.self) {
                try WorkspaceObjectShapeInspectorStateBuilder.sizeCommands(.y, meters: meters,
                    nodeIDs: [first], in: current.document.document)
            }
        }
        #expect(throws: Error.self) {
            try WorkspaceObjectShapeInspectorStateBuilder.sizeCommands(.y, meters: 1,
                nodeIDs: [first, second], in: current.document.document)
        }
        #expect(throws: Error.self) {
            try WorkspaceObjectShapeInspectorStateBuilder(snapshot: current)
                .centerCommands(.y, meters: 1, nodeIDs: [first, second])
        }
        #expect(throws: Error.self) {
            try WorkspaceTransformMatrix.commands(replacing: .translationY, with: 1,
                nodeIDs: [first, second], in: current.document.document)
        }
        #expect(workspace.view?.authorityCoordinate == current.authorityCoordinate)
        #expect(throws: Error.self) {
            try WorkspaceObjectShapeInspectorStateBuilder(snapshot: current)
                .centerCommands(.y, meters: 1, nodeIDs: [SceneNodeID()])
        }
        let hidden = try await perform([.setSceneNodeVisibility(id: first, isVisible: false)], in: workspace)
        let hiddenShape = try shape(first, in: hidden)
        #expect(hiddenShape.center == nil)
        #expect(hiddenShape.size != nil)
        #expect(throws: Error.self) {
            try WorkspaceObjectShapeInspectorStateBuilder(snapshot: hidden)
                .centerCommands(.y, meters: 1, nodeIDs: [first])
        }
    }
}
