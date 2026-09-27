import Foundation
import RupaCore
import RupaRendering
import SwiftCAD
import Testing
@testable import RupaUI

/// Move, Rotate and Scale keep one session whose keys, picks and motions become one
/// `transformSceneNodes` command each.
@Suite struct WorkspaceTransformSessionTests {
    private let pivot = Point3D(x: 1, y: 2, z: 3)

    private func session(_ mode: WorkspaceTransformSession.Mode) -> WorkspaceTransformSession {
        var session = WorkspaceTransformSession(sceneNodeIDs: [SceneNodeID()], mode: mode)
        session.frame = .world(at: pivot)
        return session
    }

    @Test func constraintKeysToggleAndTheModeKeyTogglesItsOwnConstraint() {
        var move = session(.move)
        move.press(axis: .x, plane: false)
        #expect(move.constraint == .axis(.x))
        move.press(axis: .x, plane: false)
        #expect(move.constraint == nil)
        move.press(axis: .z, plane: true)
        #expect(move.constraint == .plane(normal: .z))
        move.press(mode: .move)
        #expect(move.constraint == .screen)

        var scale = session(.scale)
        scale.press(mode: .scale)
        #expect(scale.constraint == .uniform)
        scale.press(mode: .scale)
        #expect(scale.constraint == nil)

        var rotate = session(.rotate)
        rotate.press(axis: .y, plane: true)
        #expect(rotate.constraint == nil, "Rotate has no plane constraint.")
        rotate.press(axis: .y, plane: false)
        rotate.press(mode: .move)
        #expect(rotate.mode == .move)
        #expect(rotate.constraint == nil, "Switching mode clears the previous mode's constraint.")
    }

    @Test func orientationCycleSkipsThePivotOrientationUntilAPivotIsPicked() throws {
        var move = session(.move)
        move.orientation = .normal
        move.cycleOrientation()
        #expect(move.orientation == .constructionPlane)

        try move.pickPivot(at: pivot, normal: .unitX)
        move.orientation = .normal
        move.cycleOrientation()
        #expect(move.orientation == .pivot)
        #expect(move.pickedPivot?.axis(.z) == .unitX)

        move.removePivot()
        #expect(move.pickedPivot == nil)
        #expect(move.orientation == .world)
    }

    @Test func gizmoCarriesModeFrameConstraintAndIncrementsAndHidesDuringPicks() throws {
        var move = session(.move)
        move.press(axis: .y, plane: false)
        let gizmo = try #require(move.gizmo(distanceStepMeters: 0.001))
        #expect(gizmo.mode == .move)
        #expect(gizmo.frame.origin == pivot)
        #expect(gizmo.constraint == .axis(.y))
        #expect(gizmo.increments?.distanceMeters == 0.001)

        move.snapsToIncrements = false
        #expect(move.gizmo(distanceStepMeters: 0.001)?.increments == nil)

        move.beginFreestyle()
        #expect(move.gizmo(distanceStepMeters: 0.001) == nil)
    }

    @Test func freestyleMoveRotateAndScaleCompleteAfterTheirPoints() throws {
        var move = session(.move)
        move.beginFreestyle()
        #expect(try move.addFreestylePoint(.origin) == nil)
        let translation = try #require(try move.addFreestylePoint(Point3D(x: 2, y: 0, z: 0)))
        #expect(try translation.applied(to: pivot) == Point3D(x: 3, y: 2, z: 3))
        #expect(move.pendingPoint == nil)
        #expect(move.freestylePoints.isEmpty)

        var rotate = session(.rotate)
        rotate.beginFreestyle()
        for point in [Point3D.origin, Point3D(x: 0, y: 0, z: 1), Point3D(x: 1, y: 0, z: 0)] {
            #expect(try rotate.addFreestylePoint(point) == nil)
        }
        let rotation = try #require(try rotate.addFreestylePoint(Point3D(x: 0, y: 1, z: 0)))
        let turned = try rotation.applied(to: Point3D(x: 1, y: 0, z: 0))
        #expect((turned - Point3D(x: 0, y: 1, z: 0)).length < 1e-12)

        var scale = session(.scale)
        scale.beginFreestyle()
        #expect(try scale.addFreestylePoint(.origin) == nil)
        #expect(try scale.addFreestylePoint(Point3D(x: 1, y: 0, z: 0)) == nil)
        let scaling = try #require(try scale.addFreestylePoint(Point3D(x: 3, y: 5, z: 0)))
        #expect(try (scaling.applied(to: Point3D(x: 1, y: 1, z: 0)) - Point3D(x: 3, y: 1, z: 0)).length < 1e-12)
    }

    @Test func typedValuesMoveInTheFrameAndRequireIt() throws {
        var move = session(.move)
        move.frame = try SceneTransformFrame(origin: pivot, normal: .unitX)
        let motion = try move.typedMove(Vector3D(x: 0, y: 0, z: 0.5))
        #expect(try (motion.applied(to: .origin) - Point3D(x: 0.5, y: 0, z: 0)).length < 1e-12)
        move.compensatesInstances = true
        guard case .transformSceneNodes(let ids, _, true) = try move.command(worldDelta: motion) else {
            Issue.record("A transform submits transformSceneNodes with its instance option.")
            return
        }
        #expect(ids == move.sceneNodeIDs)

        move.frame = nil
        #expect(throws: EditorError.self) { _ = try move.typedMove(Vector3D(x: 1, y: 0, z: 0)) }
    }

    @Test func dragCommandRecoversTheCommonWorldMotionAndRefusesDivergentOnes() throws {
        let move = session(.move)
        let parent = try Transform3D.translation(Vector3D(x: 10, y: 0, z: 0))
        let delta = try Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 2, about: pivot)
        func target(_ local: Transform3D, delta: Transform3D) throws -> ViewportBodyPlacementDragTarget {
            // The new local frame is the old world frame moved by `delta`, seen from the parent.
            let world = try delta.composed(with: try parent.composed(with: local))
            return ViewportBodyPlacementDragTarget(
                featureID: FeatureID(), sceneNodeID: SceneNodeID(), baseLocalTransform: local,
                localTransform: try (try parent.inverse()).composed(with: world), baseParentWorldTransform: parent
            )
        }
        let first = try target(.identity, delta: delta)
        let second = try target(try Transform3D.translation(.unitY), delta: delta)
        guard case .transformSceneNodes(let ids, let recovered, false) = try move.dragCommand([first, second]) else {
            Issue.record("A drag in a transform commits transformSceneNodes.")
            return
        }
        #expect(ids == [first.sceneNodeID, second.sceneNodeID])
        #expect(zip(recovered.matrix.values, delta.matrix.values).allSatisfy { abs($0 - $1) < 1e-9 })

        let divergent = try target(.identity, delta: try Transform3D.translation(.unitX))
        #expect(throws: EditorError.self) { _ = try move.dragCommand([first, divergent]) }
        #expect(throws: EditorError.self) { _ = try move.dragCommand([]) }
    }

    @Test func dialogRotatesAboutItsTypedAxisAndAnAxisKeySetsIt() throws {
        var rotate = session(.rotate)
        rotate.press(axis: .x, plane: false)
        #expect(rotate.rotationAxis == Vector3D(x: 1, y: 0, z: 0))
        let quarter = try rotate.typedRotation(degrees: 90)
        #expect(try (quarter.applied(to: pivot + Vector3D(x: 0, y: 1, z: 0)) - (pivot + Vector3D(x: 0, y: 0, z: 1))).length < 1e-12)

        rotate.rotationAxis = Vector3D(x: 0, y: 0, z: 0)
        #expect(throws: EditorError.self) { _ = try rotate.typedRotation(degrees: 90) }
        rotate.rotationAxis = Vector3D(x: 1, y: 1, z: 0)
        #expect(throws: EditorError.self) { _ = try rotate.typedRotation(degrees: .infinity) }
    }

    @Test func freestyleScaleTakesATypedRatioOrLengthOnceItsAxisIsPicked() throws {
        var scale = session(.scale)
        #expect(throws: EditorError.self) { _ = try scale.typedFreestyleScale(ratio: 2) }
        scale.beginFreestyle()
        _ = try scale.addFreestylePoint(.origin)
        _ = try scale.addFreestylePoint(Point3D(x: 0.5, y: 0, z: 0))
        #expect(scale.hasFreestyleScaleAxis)
        var byLength = scale
        let ratio = try scale.typedFreestyleScale(ratio: 3)
        #expect(try (ratio.applied(to: Point3D(x: 1, y: 1, z: 0)) - Point3D(x: 3, y: 1, z: 0)).length < 1e-12)
        #expect(!scale.hasFreestyleScaleAxis)
        #expect(scale.pendingPoint == nil)

        byLength.freestyleUniform = true
        let length = try byLength.typedFreestyleScale(length: 1)
        #expect(try (length.applied(to: Point3D(x: 1, y: 1, z: 0)) - Point3D(x: 2, y: 2, z: 0)).length < 1e-12)
    }

    @Test func choosingAPivotModeReplacesAPickedPivot() throws {
        var move = session(.move)
        try move.pickPivot(at: pivot, normal: nil)
        move.orientation = .pivot
        move.choose(pivotMode: .median)
        #expect(move.pivotMode == .median)
        #expect(move.pickedPivot == nil)
        #expect(move.orientation == .world)
    }

    @Test func aTypedFieldReadsItsTextOnceAndMakesItsModesMotion() throws {
        #expect(try WorkspaceTransformTypedField.distance(.x).value(of: "  ") == nil)
        #expect(try WorkspaceTransformTypedField.distance(.x).value(of: "10") == 10)
        #expect(throws: EditorError.self) { _ = try WorkspaceTransformTypedField.angle.value(of: "ten") }

        var move = session(.move)
        let moved = try move.typedMotion(.distance(.y), value: 10, unit: .millimeter)
        #expect(try (moved.applied(to: .origin) - Point3D(x: 0, y: 0.01, z: 0)).length < 1e-12)

        var scale = session(.scale)
        let scaled = try scale.typedMotion(.factor(.z), value: 2, unit: .millimeter)
        #expect(try (scaled.applied(to: Point3D(x: 2, y: 3, z: 4)) - Point3D(x: 2, y: 3, z: 5)).length < 1e-12)

        var rotate = session(.rotate)
        #expect(throws: EditorError.self) { _ = try rotate.typedMotion(.distance(.x), value: 1, unit: .meter) }
        let turned = try rotate.typedMotion(.angle, value: 180, unit: .meter)
        #expect(try (turned.applied(to: Point3D(x: 2, y: 2, z: 3)) - Point3D(x: 0, y: 2, z: 3)).length < 1e-12)
    }
}
