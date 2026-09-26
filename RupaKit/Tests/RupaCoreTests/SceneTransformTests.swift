import SwiftCAD
import Testing
@testable import RupaCore

/// Transform frames, the motions stated in them, and instances held in place.
@Suite struct SceneTransformTests {
    private let tolerance = 1.0e-9

    private func close(_ a: Point3D, _ b: Point3D) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
    }

    private func close(_ a: Vector3D, _ b: Vector3D) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
    }

    /// Two boxes: `first` at (1, 0, 0) and `second` at (3, 0, 0) turned a quarter turn about Z.
    @MainActor
    private func twoBoxes() throws -> (EditorSession, first: SceneNodeID, second: SceneNodeID) {
        let session = EditorSession()
        for name in ["First", "Second"] {
            _ = try session.execute(.createExtrudedRectangle(
                name: name, plane: .xy,
                width: .length(0.1, .meter), height: .length(0.1, .meter),
                depth: .length(0.1, .meter), direction: .normal
            ))
        }
        let bodies = session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }
        let first = try #require(bodies.first { $0.name.hasPrefix("First") }).id
        let second = try #require(bodies.first { $0.name.hasPrefix("Second") }).id
        _ = try session.execute(.setSceneNodeTransform(id: first, localTransform: try .translation(Vector3D(x: 1, y: 0, z: 0))))
        _ = try session.execute(.setSceneNodeTransform(
            id: second,
            localTransform: try Transform3D.translation(Vector3D(x: 3, y: 0, z: 0))
                .composed(with: try .rotation(axis: .unitZ, angleRadians: .pi / 2))
        ))
        return (session, first, second)
    }

    @MainActor
    @Test func pivotsAndOrientationsResolveTheFrame() throws {
        let (session, first, second) = try twoBoxes()
        let metadata = session.document.productMetadata
        let resolver = SceneTransformFrameResolver()
        func frame(_ pivot: SceneTransformPivotMode, _ orientation: SceneTransformOrientation,
                   picked: SceneTransformFrame? = nil, plane: SketchPlane? = nil) throws -> SceneTransformFrame {
            try resolver.frame(.init(
                sceneNodeIDs: [first, second], pivotMode: pivot, orientation: orientation,
                pickedPivot: picked, constructionPlane: plane,
                selectionBounds: MeasurementResult.Bounds(minX: 0, minY: -1, minZ: 0, maxX: 4, maxY: 1, maxZ: 2)
            ), metadata: metadata)
        }
        #expect(close(try frame(.boundingBox, .world).origin, Point3D(x: 2, y: 0, z: 1)))
        #expect(close(try frame(.median, .world).origin, Point3D(x: 2, y: 0, z: 0)))
        #expect(close(try frame(.active, .world).origin, Point3D(x: 3, y: 0, z: 0)))
        let picked = try SceneTransformFrame(origin: Point3D(x: 5, y: 5, z: 5), normal: .unitX)
        let pickedFrame = try frame(.median, .pivot, picked: picked)
        #expect(close(pickedFrame.origin, picked.origin))
        #expect(close(pickedFrame.zAxis, .unitX))
        let normal = try frame(.active, .normal)
        #expect(close(normal.xAxis, .unitY))
        #expect(close(normal.yAxis, Vector3D(x: -1, y: 0, z: 0)))
        let plane = try frame(.active, .constructionPlane, plane: .yz)
        #expect(close(plane.zAxis, .unitX))
        #expect(throws: EditorError.self) { _ = try frame(.active, .pivot) }
        #expect(SceneTransformOrientation.world.next == .normal)
    }

    @Test func motionsAreStatedInTheFrame() throws {
        let frame = try SceneTransformFrame(
            origin: Point3D(x: 1, y: 2, z: 3), xAxis: .unitY, yAxis: Vector3D(x: -1, y: 0, z: 0), zAxis: .unitZ
        )
        let move = try SceneTransformMotion.translation(in: frame, by: Vector3D(x: 2, y: 0, z: 1))
        #expect(close(try move.applied(to: .origin), Point3D(x: 0, y: 2, z: 1)))

        let turn = try SceneTransformMotion.rotation(in: frame, about: .z, angleRadians: .pi / 2)
        #expect(close(try turn.applied(to: frame.origin), frame.origin))
        #expect(close(try turn.applyingLinearPart(to: .unitX), .unitY))

        let stretch = try SceneTransformMotion.scale(in: frame, factors: Vector3D(x: 3, y: 1, z: 1))
        #expect(close(try stretch.applied(to: frame.origin), frame.origin))
        #expect(close(try stretch.applyingLinearPart(to: .unitY), Vector3D(x: 0, y: 3, z: 0)))
        #expect(close(try stretch.applyingLinearPart(to: .unitX), .unitX))
        let uniform = try SceneTransformMotion.uniformScale(in: frame, factor: 2)
        #expect(close(try uniform.applied(to: Point3D(x: 2, y: 2, z: 3)), Point3D(x: 3, y: 2, z: 3)))
        #expect(throws: EditorError.self) {
            _ = try SceneTransformMotion.scale(in: frame, factors: Vector3D(x: 0, y: 1, z: 1))
        }
    }

    @Test func freestyleFormsFollowTheirPoints() throws {
        let move = try SceneTransformMotion.freestyleMove(from: Point3D(x: 1, y: 1, z: 1), to: .origin)
        #expect(close(try move.applied(to: Point3D(x: 1, y: 1, z: 1)), .origin))

        let turn = try SceneTransformMotion.freestyleRotation(
            axisStart: .origin, axisEnd: Point3D(x: 0, y: 0, z: 2),
            reference: Point3D(x: 1, y: 0, z: 5), target: Point3D(x: 0, y: 3, z: -1)
        )
        #expect(close(try turn.applyingLinearPart(to: .unitX), .unitY))

        let ratio = try SceneTransformMotion.freestyleRatio(
            axisStart: .origin, axisEnd: Point3D(x: 2, y: 0, z: 0), length: 5
        )
        #expect(abs(ratio - 2.5) < tolerance)
        #expect(abs(try SceneTransformMotion.freestyleRatio(
            axisStart: .origin, axisEnd: Point3D(x: 2, y: 0, z: 0), toward: Point3D(x: 3, y: 7, z: 0)
        ) - 1.5) < tolerance)
        let scale = try SceneTransformMotion.freestyleScale(
            axisStart: Point3D(x: 1, y: 0, z: 0), axisEnd: Point3D(x: 3, y: 0, z: 0), ratio: 2
        )
        #expect(close(try scale.applied(to: Point3D(x: 3, y: 4, z: 0)), Point3D(x: 5, y: 4, z: 0)))
        #expect(throws: EditorError.self) {
            _ = try SceneTransformMotion.freestyleRotation(
                axisStart: .origin, axisEnd: .origin, reference: .origin, target: .origin
            )
        }
        #expect(throws: EditorError.self) {
            _ = try SceneTransformMotion.freestyleRotation(
                axisStart: .origin, axisEnd: Point3D(x: 0, y: 0, z: 1),
                reference: Point3D(x: 0, y: 0, z: 3), target: Point3D(x: 1, y: 0, z: 0)
            )
        }
    }

    @MainActor
    @Test func instancesCanBeHeldInPlaceWhileTheirSourceMoves() throws {
        let (session, first, _) = try twoBoxes()
        let definition = try session.execute(.createComponentDefinition(name: "Part", rootSceneNodeIDs: [first]))
        let definitionID = try #require(definition.generatedIdentities.componentDefinitionIDs.first)
        _ = try session.execute(.createComponentInstance(
            name: "Copy", definitionID: definitionID, localTransform: try .translation(Vector3D(x: 0, y: 5, z: 0))
        ))
        func instanceWorld() throws -> Transform3D {
            let occurrences = try SceneNodeHierarchy(metadata: session.document.productMetadata).resolvedOccurrences()
            return try #require(occurrences.first { $0.sourceSceneNodeID == first && $0.componentInstanceID != nil }).worldTransform
        }
        let before = try instanceWorld()
        let shift = try Transform3D.translation(Vector3D(x: 0, y: 0, z: 2))

        _ = try session.execute(.transformSceneNodes(ids: [first], worldDelta: shift, compensatingInstances: true))
        #expect(zip(try instanceWorld().matrix.values, before.matrix.values).allSatisfy { abs($0 - $1) < tolerance })

        _ = try session.execute(.transformSceneNodes(ids: [first], worldDelta: shift, compensatingInstances: false))
        let followed = try shift.composed(with: before)
        #expect(zip(try instanceWorld().matrix.values, followed.matrix.values).allSatisfy { abs($0 - $1) < tolerance })
    }
}
