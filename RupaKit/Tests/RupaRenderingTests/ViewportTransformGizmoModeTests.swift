import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// A Move, Rotate or Scale mode draws only its own handles in its frame, and every drag is measured
/// in that frame about its pivot.
@MainActor
@Suite struct ViewportTransformGizmoModeTests {
    private let pivot = Point3D(x: 0.5, y: 0.25, z: -0.5)

    private func tiltedFrame() throws -> SceneTransformFrame {
        try SceneTransformFrame(origin: pivot, normal: try Vector3D(x: 0, y: 1, z: 1).normalized(tolerance: 1e-12))
    }

    private func records(
        gizmo: ViewportTransformGizmoConfiguration
    ) throws -> [(ViewportAffordanceAction, ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember)] {
        let featureID = FeatureID()
        let nodeID = SceneNodeID()
        let item = ViewportSceneItem(
            id: "body", featureID: featureID, sceneNodeID: nodeID,
            modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: 2, sizeYMeters: 1, sizeZMeters: 2, yMinMeters: 0, yMaxMeters: 1
            ))
        )
        var raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
            document: bodyTransformTestDocument([item]),
            scene: ViewportScene(items: [item]),
            selection: SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: nodeID)]),
            ruler: .standard(for: .meter),
            enabledRoutes: [.bodyTransform],
            interactiveRoutes: [.bodyTransform]
        )
        raw.transformGizmo = gizmo
        var interactionRecords: [ViewportSpatialInteractionRecord] = []
        _ = try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw, interactionRecords: &interactionRecords, checkpoint: { _, _, _ in }
        )
        return interactionRecords.compactMap { record in
            guard case .affordance(let target, let members, _, _) = record.target else { return nil }
            return (target.action, members[0])
        }
    }

    @Test func moveDrawsAxisPlaneAndScreenHandlesCarryingItsFrame() throws {
        let gizmo = ViewportTransformGizmoConfiguration(mode: .move, frame: try tiltedFrame())
        let found = try records(gizmo: gizmo)
        let actions = found.map(\.0)
        for axis in ViewportCoordinateAxis.allCases {
            #expect(actions.contains(.translate(axis)))
            #expect(actions.contains(.translatePlane(axis)))
            #expect(!actions.contains(.rotate(axis)))
            #expect(!actions.contains(.centerScale(axis)))
        }
        #expect(actions.contains(.translateScreen))
        #expect(actions.count == 7)
        #expect(found.allSatisfy { $0.1.edit.transformGizmo == gizmo })

        let constrained = try records(gizmo: .init(mode: .move, frame: try tiltedFrame(), constraint: .axis(.y)))
        #expect(constrained.map(\.0) == [.translate(.y)])
    }

    @Test func rotateAndScaleDrawTheirOwnHandlesAndConstraints() throws {
        let frame = try tiltedFrame()
        let rotate = try records(gizmo: .init(mode: .rotate, frame: frame)).map(\.0)
        #expect(Set(ViewportCoordinateAxis.allCases.map { "\(ViewportAffordanceAction.rotate($0))" })
            == Set(rotate.map { "\($0)" }))
        #expect(try records(gizmo: .init(mode: .rotate, frame: frame, constraint: .screen)).map(\.0) == [.rotateScreen])

        let scale = try records(gizmo: .init(mode: .scale, frame: frame)).map(\.0)
        #expect(scale.count == 7)
        #expect(scale.contains(.uniformScale))
        #expect(ViewportCoordinateAxis.allCases.allSatisfy { scale.contains(.centerScale($0)) && scale.contains(.scalePlane($0)) })
        #expect(try records(gizmo: .init(mode: .scale, frame: frame, constraint: .uniform)).map(\.0) == [.uniformScale])
        #expect(try records(gizmo: .init(mode: .scale, frame: frame, constraint: .plane(normal: .z))).map(\.0)
            == [.scalePlane(.z)])
    }

    private func input(
        _ action: ViewportAffordanceAction, gizmo: ViewportTransformGizmoConfiguration
    ) throws -> ViewportBodyTransformInput {
        let feature = FeatureID()
        let node = SceneNodeID()
        var bounds = ViewportObjectEditState(xMin: -1, xMax: 1, yMin: -1, yMax: 1, zMin: -1, zMax: 1)
        bounds.transformGizmo = gizmo
        let member = ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
            occurrenceID: "body", featureID: feature, sceneNodeID: node, modelTransform: try ScenePlacement(.identity),
            edit: bounds, placement: .init(featureID: feature, sceneNodeID: node,
                                         baseLocalTransform: .identity, parentWorldTransform: .identity))
        let record = try ViewportSpatialInteractionRecord(target: .affordance(
            target: .init(featureID: feature, action: action), members: [member],
            groupEdit: nil, placement: member.placement), occurrenceID: member.occurrenceID)
        return try #require(try ViewportBodyTransformInput(record: record))
    }

    private func close(_ a: Point3D, _ b: Point3D) -> Bool { (a - b).length < 1e-9 }

    @Test func axisAndPlaneMovesFollowTheFrameAndSnapToWholeSteps() throws {
        let frame = try tiltedFrame()
        let measure = try ViewportOrthographicAffordanceMeasure.isometric(at: pivot)
        let free = ViewportTransformGizmoConfiguration(mode: .move, frame: frame)
        let axis = frame.axis(.z)
        let moved = try input(.translate(.z), gizmo: free).mutation(
            from: measure.projected(pivot), to: measure.projected(pivot + axis * 0.3), measure: measure)
        #expect(try close(moved.applied(to: .origin), .origin + axis * 0.3))

        var snapped = free
        snapped.increments = .init(distanceMeters: 0.25)
        let target = pivot + frame.axis(.x) * 0.3 + frame.axis(.y) * 0.6
        let planar = try input(.translatePlane(.z), gizmo: snapped).mutation(
            from: measure.projected(pivot), to: measure.projected(target), measure: measure)
        #expect(try close(planar.applied(to: .origin), .origin + frame.axis(.x) * 0.25 + frame.axis(.y) * 0.5))

        let screen = try input(.translateScreen, gizmo: free).mutation(
            from: measure.projected(pivot), to: measure.projected(pivot + measure.right * 0.2), measure: measure)
        #expect(try close(screen.applied(to: .origin), .origin + measure.right * 0.2))
    }

    @Test func rotationsTurnAboutThePivotAndSnapToTheAngleStep() throws {
        let frame = try tiltedFrame()
        let measure = try ViewportOrthographicAffordanceMeasure.isometric(at: pivot)
        var gizmo = ViewportTransformGizmoConfiguration(mode: .rotate, frame: frame)
        gizmo.increments = .init(angleRadians: .pi / 4)
        let x = frame.axis(.x), y = frame.axis(.y)
        // A drag of 50° about the frame z axis snaps to 45°.
        let end = pivot + x * cos(50 * .pi / 180) + y * sin(50 * .pi / 180)
        let rotation = try input(.rotate(.z), gizmo: gizmo).mutation(
            from: measure.projected(pivot + x), to: measure.projected(end), measure: measure)
        #expect(try close(rotation.applied(to: pivot), pivot))
        #expect(try close(rotation.applied(to: pivot + x), pivot + (x + y) * (1 / 2.0.squareRoot())))

        gizmo.increments = nil
        let screen = try input(.rotateScreen, gizmo: gizmo).mutation(
            from: measure.projected(pivot + measure.right), to: measure.projected(pivot + measure.up), measure: measure)
        #expect(try close(screen.applied(to: pivot), pivot))
        #expect(try close(screen.applied(to: pivot + measure.right), pivot + measure.up))
    }

    @Test func scalesKeepThePivotAndTheirUnscaledAxes() throws {
        let frame = try tiltedFrame()
        let measure = try ViewportOrthographicAffordanceMeasure.isometric(at: pivot)
        let gizmo = ViewportTransformGizmoConfiguration(mode: .scale, frame: frame)
        // The center box sits on the pivot: dragging one bounds half-diagonal (√3 for the unit
        // box) to the right doubles the size, and the same drag to the left collapses it.
        let uniform = try input(.uniformScale, gizmo: gizmo).mutation(
            from: measure.projected(pivot), to: measure.projected(pivot + measure.right * 3.0.squareRoot()),
            measure: measure)
        #expect(try close(uniform.applied(to: pivot), pivot))
        #expect(try close(uniform.applied(to: pivot + frame.axis(.z)), pivot + frame.axis(.z) * 2))
        let collapsed = try input(.uniformScale, gizmo: gizmo).mutation(
            from: measure.projected(pivot), to: measure.projected(pivot + measure.right * -(3.0.squareRoot())),
            measure: measure)
        #expect(abs(collapsed.matrix.values[0]) < 1e-9, "A drag may preview a collapse; the commit refuses it.")

        let x = frame.axis(.x), z = frame.axis(.z)
        let planar = try input(.scalePlane(.z), gizmo: gizmo).mutation(
            from: measure.projected(pivot + x * 0.1), to: measure.projected(pivot + x * 0.2), measure: measure)
        #expect(try close(planar.applied(to: pivot + x), pivot + x * 2))
        #expect(try close(planar.applied(to: pivot + z), pivot + z))

        let axial = try input(.centerScale(.x), gizmo: gizmo).mutation(
            from: measure.projected(pivot), to: measure.projected(pivot + x * 0.5), measure: measure)
        #expect(try close(axial.applied(to: pivot), pivot))
        #expect(try close(axial.applied(to: pivot + frame.axis(.y)), pivot + frame.axis(.y)))
    }

    @Test func modeLeavesOneSidedAndBoxHandlesToTheCombinedGizmo() throws {
        let gizmo = ViewportTransformGizmoConfiguration(mode: .scale, frame: .world(at: .origin))
        #expect(!gizmo.shows(.oneSidedScale(.x)))
        #expect(!gizmo.shows(.faceMove(.top)))
        #expect(!gizmo.shows(.translate(.x)))
        #expect(gizmo.shows(.centerScale(.x)))
    }
}
