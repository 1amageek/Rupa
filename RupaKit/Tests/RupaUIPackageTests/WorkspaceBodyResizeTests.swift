import CoreGraphics
import RupaCore
import RupaKit
import RupaProject
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering
@testable import RupaUI

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WorkspaceBodyResizeTests {
    @Test func facesAndCornersPreserveOppositeBoundsAndCommitSourceDimensions() async throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        var document = session.document
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body })
        let local = try WorkspaceTransformMatrix.transform(from: .init(
            translation: .init(x: 0.2, y: 0.3, z: -0.1), rotationDegrees: .init(x: 20, y: 30, z: 40),
            scale: .init(x: -2, y: 3, z: 1.5), shear: .init(x: 0.2, y: -0.1, z: 0.3)))
        document.productMetadata.sceneNodes[node.id]?.localTransform = local
        let parent = try #require(try ViewportSceneNodeParentFrames(document: document).parentWorldTransform(of: node.id))
        let base = try #require(try ViewportBodyResizeBaseline.resolve(document: document, nodeID: node.id,
            worldTransform: ViewportWorldTransformAlgebra.multiplied(parent, local)))
        let member = ViewportObjectTransformMember(occurrenceID: "box", reference: try #require(node.reference),
            sceneNodeID: node.id, baseLocalTransform: local, parentWorldTransform: parent,
            bounds: .init(xMin: -1, xMax: 1, yMin: -1, yMax: 1, zMin: -1, zMax: 1), resize: base)
        let actions = ViewportBodyFace.allCases.filter { $0 != .side }.map(ViewportAffordanceAction.faceMove)
            + ViewportBodyVertex.allCases.map(ViewportAffordanceAction.vertexMove)
        var lastTarget: ViewportBodyResizeDragTarget?
        var lastMutation = Transform3D.identity
        for displacement in [Vector3D(x: 0.001, y: -0.002, z: 0.003),
                             try ViewportWorldTransformAlgebra.transformedVector(base.size * 2, by: base.worldFromBox),
                             try ViewportWorldTransformAlgebra.transformedVector(base.size * -2, by: base.worldFromBox)] {
          for action in actions {
            let anchor = try base.point(for: action)
            let measure = ResizeMeasure(displacement: displacement)
            let input = try #require(try ViewportBodyTransformInput(record: .init(target: .objectTransform(
                action: action, members: [member], bounds: member.bounds))))
            let mutation = try input.mutation(from: .zero, to: CGPoint(x: 1, y: 1), measure: measure)
            let target = try #require(try input.resizeCommit(mutation: mutation))
            #expect(try input.commits(mutation: mutation).isEmpty)
            try target.validate(in: document)
            let commands = try WorkspaceBodyResizeCommandPlanner.commands(target, in: document)
            #expect(commands.count >= 1)
            var changed = document
            try changed.setCubeDimensions(featureID: #require(node.reference?.featureID),
                sizeX: .length(target.size.x, .meter), sizeY: .length(target.size.y, .meter),
                sizeZ: .length(target.size.z, .meter))
            changed.productMetadata.sceneNodes[node.id]?.localTransform = target.placement.localTransform
            let next = try #require(try ViewportBodyResizeBaseline.resolve(document: changed, nodeID: node.id,
                worldTransform: ViewportWorldTransformAlgebra.multiplied(parent, target.placement.localTransform)))
            let committedCorners = try ViewportBodyVertex.allCases.map { try next.point(for: .vertexMove($0)) }
            for vertex in ViewportBodyVertex.allCases {
                let before = try base.point(for: .vertexMove(vertex))
                let preview = try ViewportWorldTransformAlgebra.transformedPoint(before, by: mutation)
                #expect(committedCorners.contains { (preview - $0).length < 1e-9 })
            }
            // A diagonal opposite corner is fixed for every face/corner resize.
            let fixedCount = try ViewportBodyVertex.allCases.filter { vertex in
                let before = try base.point(for: .vertexMove(vertex))
                return try (ViewportWorldTransformAlgebra.transformedPoint(before, by: mutation) - before).length < 1e-9
            }.count
            if case .faceMove = action { #expect(fixedCount == 4) } else { #expect(fixedCount >= 1) }
            for index in [0, 1, 2, 4, 5, 6, 8, 9, 10] {
                #expect(abs(target.placement.localTransform.matrix.values[index] - local.matrix.values[index]) < 1e-10)
            }
            #expect((try next.point(for: action) - anchor).length > 0)
            #expect(throws: Error.self) { try target.validate(in: changed) }
            lastTarget = target
            lastMutation = mutation
          }
        }

        let target = try #require(lastTarget)
        let workspace = ProjectWorkspace(project: try ProjectController(document: document,
            evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(), projector: DesignDocumentProjectBridge()))
        let before = try await workspace.evaluate()
        let source = try DefaultProjectWorkspaceActionPlanner().source(name: "resizeBox", commands:
            WorkspaceBodyResizeCommandPlanner.commands(target, in: document), from: before)
        _ = try await workspace.perform(source)
        let after = try #require(workspace.view)
        #expect(after.transactionRevision.value == before.transactionRevision.value + 1)
        let actual = try ObjectDimensionSourceResolver().resolve(target: .init(sceneNodeID: node.id), in: after.document.document)
        #expect(abs(actual.sizeX - target.size.x) < 1e-9)
        #expect(abs(actual.sizeY - target.size.y) < 1e-9)
        #expect(abs(actual.sizeZ - target.size.z) < 1e-9)
        let beforeItem = try #require(before.viewport.items.first { before.sceneNodeID(for: $0.occurrenceID) == node.id })
        let afterItem = try #require(after.viewport.items.first { after.sceneNodeID(for: $0.occurrenceID) == node.id })
        let rendered = try afterItem.mesh.vertexPositions.map { point -> Point3D in
            let world = try afterItem.worldTransform.applying(to: point)
            return .init(x: world.x, y: world.y, z: world.z)
        }
        #expect(!rendered.isEmpty)
        #expect(rendered.count == beforeItem.mesh.vertexPositions.count)
        for point in beforeItem.mesh.vertexPositions {
            let world = try beforeItem.worldTransform.applying(to: point)
            let preview = try ViewportWorldTransformAlgebra.transformedPoint(
                .init(x: world.x, y: world.y, z: world.z), by: lastMutation)
            #expect(rendered.contains { ($0 - preview).length < 1e-8 })
        }
        let undone = try await workspace.undo()
        #expect(!undone.canUndo)
        #expect(undone.document.document.productMetadata == document.productMetadata)
        let redone = try await workspace.redo()
        #expect(redone.document.document.productMetadata == after.document.document.productMetadata)
        #expect(throws: Error.self) { try WorkspaceBodyResizeCommandPlanner.commands(target, in: redone.document.document) }
        #expect(throws: Error.self) {
            try base.mutation(action: .faceMove(.left), from: .zero, to: CGPoint(x: 1, y: 1),
                              measure: ResizeMeasure(displacement: Vector3D(x: .infinity, y: 100, z: 100)))
        }
    }
}

@MainActor
private struct ResizeMeasure: ViewportAffordanceMeasuring {
    let displacement: Vector3D
    func worldAxisDelta(from start: CGPoint, to end: CGPoint, axisOrigin: Point3D, axisDirection: Vector3D) throws -> Double {
        displacement.dot(axisDirection)
    }
    func worldPlanePoint(at point: CGPoint, planeOrigin: Point3D, planeNormal: Vector3D) throws -> Point3D {
        throw EditorError(code: .commandInvalid, message: "Box resizing must not ask for a rotation plane.")
    }
    func viewPlanePoint(at point: CGPoint, through anchor: Point3D) throws -> Point3D {
        point == .zero ? anchor : anchor + displacement
    }
}
