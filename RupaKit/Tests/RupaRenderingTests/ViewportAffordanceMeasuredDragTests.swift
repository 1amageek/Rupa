import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// What each affordance drag asks the frame that drew its handle, and what it
/// does with the answer.
///
/// The camera here is a closed-form orthographic fake that applies the same
/// ray solve and the same degeneracy guards the mounted frame applies, so a
/// screen point is produced by projecting a world point the test chose and the
/// expected result is stated in world metres. The edit state keeps the identity
/// orientation, under which `worldPoint` is the identity map and the world axes
/// are the standard basis, so a model quantity and a world quantity are the
/// same number and the assertions say what they mean.
@MainActor
@Suite struct ViewportAffordanceMeasuredDragTests {
    private static let tolerance = 1.0e-9

    /// A one-centimetre box centred at `(0, 0.005, 0)`, which is the CAD scale
    /// the legacy one-metre axis probe fell behind the camera at.
    private var state: ViewportObjectEditState {
        ViewportObjectEditState(
            xMin: -0.005,
            xMax: 0.005,
            yMin: 0.0,
            yMax: 0.01,
            zMin: -0.005,
            zMax: 0.005
        )
    }

    private var target: SelectionTarget {
        SelectionTarget(sceneNodeID: SceneNodeID())
    }

    /// A camera every world axis and every axis-aligned plane answers for.
    private func isometric() throws -> ViewportOrthographicAffordanceMeasure {
        try ViewportOrthographicAffordanceMeasure.isometric(at: state.worldPoint(state.centerPoint))
    }

    /// A camera looking along world `-z`, which is the pure form of an
    /// axis-front `z` viewport: the `z` axis projects to a point and the plane
    /// whose normal is world `y` is seen edge-on.
    private func axisFrontZ() throws -> ViewportOrthographicAffordanceMeasure {
        try ViewportOrthographicAffordanceMeasure.looking(
            along: Vector3D(x: 0.0, y: 0.0, z: -1.0),
            at: state.worldPoint(state.centerPoint)
        )
    }

    @Test func translateAndScaleMoveByTheSignedMetresMeasuredOnTheirWorldAxis() throws {
        let measure = try isometric()
        let state = state
        let centre = state.worldPoint(state.centerPoint)
        let amount = 0.002
        let start = measure.projected(centre)
        let current = measure.projected(centre + state.worldAxis(.x) * amount)

        let translated = try #require(try state.applying(
            action: .translate(.x), start: start, current: current, measure: measure
        ))
        #expect(abs(Double(translated.xMin) - (-0.003)) < Self.tolerance)
        #expect(abs(Double(translated.xMax) - 0.007) < Self.tolerance)
        #expect(abs(Double(translated.yMin) - 0.0) < Self.tolerance)
        #expect(abs(Double(translated.zMin) - (-0.005)) < Self.tolerance)

        let oneSided = try #require(try state.applying(
            action: .oneSidedScale(.x), start: start, current: current, measure: measure
        ))
        #expect(abs(Double(oneSided.xMin) - (-0.005)) < Self.tolerance)
        #expect(abs(Double(oneSided.xMax) - 0.007) < Self.tolerance)

        let centred = try #require(try state.applying(
            action: .centerScale(.x), start: start, current: current, measure: measure
        ))
        #expect(abs(Double(centred.xMin) - (-0.007)) < Self.tolerance)
        #expect(abs(Double(centred.xMax) - 0.007) < Self.tolerance)
    }

    @Test func rotateFollowsTheCursorAroundTheMeasuredWorldPlane() throws {
        let measure = try isometric()
        let state = state
        let pivot = state.worldPoint(state.centerPoint)
        let radius = 0.003
        // Two absolute directions from the pivot, a quarter turn apart in the
        // plane the rotation turns: world x to world y for a z rotation.
        let start = measure.projected(pivot + state.worldAxis(.x) * radius)
        let current = measure.projected(pivot + state.worldAxis(.y) * radius)

        let next = try #require(try state.applying(
            action: .rotate(.z), start: start, current: current, measure: measure
        ))

        // The cursor travelled x -> y, so the object's x axis must land on +y
        // and its y axis on -x. A sign inversion spins the object against the
        // cursor and lands x on -y instead.
        #expect(abs(Double(next.orientation.xAxis.y) - 1.0) < Self.tolerance)
        #expect(abs(Double(next.orientation.xAxis.x)) < Self.tolerance)
        #expect(abs(Double(next.orientation.yAxis.x) + 1.0) < Self.tolerance)
    }

    @Test func vertexMoveResolvesOneViewPlaneDisplacementOnTheWorldAxes() throws {
        let measure = try isometric()
        let state = state
        let vertex = ViewportBodyVertex.frontBottomLeft
        let anchor = state.worldPoint(state.position(for: vertex))
        // A displacement inside the view plane, which is what a pointer move
        // can actually name. It is not aligned with any world axis, so each of
        // the three axes takes a share of it.
        let delta = measure.right * 0.002 + measure.up * 0.0015
        let start = measure.projected(anchor)
        let current = measure.projected(anchor + delta)

        let next = try #require(try state.applying(
            action: .vertexMove(vertex), start: start, current: current, measure: measure
        ))

        #expect(abs(Double(next.xMin) - (-0.005 + delta.x)) < Self.tolerance)
        #expect(abs(Double(next.yMin) - (0.0 + delta.y)) < Self.tolerance)
        #expect(abs(Double(next.zMin) - (-0.005 + delta.z)) < Self.tolerance)
        // The moved vertex stays under the pointer. Projecting the screen
        // displacement onto each world axis independently instead cross-bleeds
        // on non-orthogonal projected axes and leaves the vertex behind.
        let moved = measure.projected(next.worldPoint(next.position(for: vertex)))
        #expect(hypot(moved.x - current.x, moved.y - current.y) < 1.0e-6)
    }

    @Test func profileCornerMoveResolvesTheSketchPlaneDisplacementWithoutCrossBleed() throws {
        let measure = try isometric()
        let state = state
        let vertex = ViewportBodyVertex.frontBottomLeft
        let corner = state.worldPoint(state.position(for: vertex))
        let start = measure.projected(corner)
        // Both samples stay in the profile sketch plane, whose normal is world
        // y, so a pure world-x drag must not answer any world z and the other
        // way round.
        let alongX = measure.projected(corner + state.worldAxis(.x) * 0.002)
        let alongZ = measure.projected(corner + state.worldAxis(.z) * 0.003)

        let xDelta = try state.profileCornerDragDelta(
            vertex, start: start, current: alongX, measure: measure
        )
        let zDelta = try state.profileCornerDragDelta(
            vertex, start: start, current: alongZ, measure: measure
        )

        #expect(abs(Double(xDelta.x) - 0.002) < Self.tolerance)
        #expect(abs(Double(xDelta.y)) < Self.tolerance)
        #expect(abs(Double(zDelta.y) - 0.003) < Self.tolerance)
        #expect(abs(Double(zDelta.x)) < Self.tolerance)

        let next = try #require(try state.applying(
            action: .profileCornerMove(target, vertex),
            start: start,
            current: alongX,
            measure: measure
        ))
        #expect(abs(Double(next.xMin) - (-0.003)) < Self.tolerance)
        #expect(abs(Double(next.zMin) - (-0.005)) < Self.tolerance)
    }

    @Test func faceDragsMeasureTheFaceOwnAxisAndCommitThroughTheMapping() throws {
        let measure = try isometric()
        let state = state
        let face = ViewportBodyFace.left
        let anchor = state.worldPoint(state.position(for: face))
        let amount = 0.002
        let start = measure.projected(anchor)
        let current = measure.projected(anchor + state.worldAxis(.x) * amount)

        let moved = try #require(try state.applying(
            action: .faceMove(face), start: start, current: current, measure: measure
        ))
        #expect(abs(Double(moved.xMin) - (-0.003)) < Self.tolerance)
        #expect(abs(Double(moved.xMax) - 0.005) < Self.tolerance)

        let profileMoved = try #require(try state.applying(
            action: .profileFaceMove(target, face),
            start: start,
            current: current,
            measure: measure
        ))
        #expect(abs(Double(profileMoved.xMin) - (-0.003)) < Self.tolerance)

        // The commit distance is the mapping's, which reads the left face as an
        // inward push, so a positive world-x move commits a negative distance.
        let distance = try #require(try state.profileFaceDragDistance(
            face, start: start, current: current, measure: measure
        ))
        #expect(abs(Double(distance) - (-amount)) < Self.tolerance)
    }

    @Test func edgeTreatmentsSolveInwardDragsAndAnswerNothingOutward() throws {
        let measure = try isometric()
        let state = state
        let edge = ViewportBodyEdge.leftBottom
        let anchor = state.worldPoint(state.position(for: edge))
        let start = measure.projected(anchor)
        let inward = measure.projected(
            anchor + state.worldAxis(.x) * 0.002 + state.worldAxis(.z) * 0.004
        )
        let outward = measure.projected(
            anchor + state.worldAxis(.x) * -0.002 + state.worldAxis(.z) * -0.004
        )

        let distance = try #require(try state.profileEdgeChamferDistance(
            edge, start: start, current: inward, measure: measure
        ))
        #expect(abs(Double(distance) - 0.003) < Self.tolerance)

        let radius = try #require(try state.profileEdgeFilletRadius(
            edge, start: start, current: inward, measure: measure
        ))
        #expect(abs(Double(radius) - 0.003) < Self.tolerance)

        // An outward drag is a solved measurement that commits nothing. It is
        // not a refusal, so it must answer nil rather than throw.
        #expect(try state.profileEdgeChamferDistance(
            edge, start: start, current: outward, measure: measure
        ) == nil)
        #expect(try state.profileEdgeFilletRadius(
            edge, start: start, current: outward, measure: measure
        ) == nil)
    }

    @Test func everyAffordanceActionSolvesAgainstTheMeasuringSurface() throws {
        let measure = try isometric()
        let state = state
        let centre = state.worldPoint(state.centerPoint)
        let vertex = ViewportBodyVertex.frontBottomLeft
        let corner = state.worldPoint(state.position(for: vertex))
        let leftFace = state.worldPoint(state.position(for: ViewportBodyFace.left))
        let topFace = state.worldPoint(state.position(for: ViewportBodyFace.top))
        let edge = state.worldPoint(state.position(for: ViewportBodyEdge.leftBottom))
        let viewDelta = measure.right * 0.002 + measure.up * 0.0015
        let planeDelta = state.worldAxis(.x) * 0.002 + state.worldAxis(.z) * 0.002

        let solved: [(ViewportAffordanceAction, CGPoint, CGPoint)] = [
            (.translate(.x), measure.projected(centre),
             measure.projected(centre + state.worldAxis(.x) * 0.002)),
            (.oneSidedScale(.y), measure.projected(centre),
             measure.projected(centre + state.worldAxis(.y) * 0.002)),
            (.centerScale(.z), measure.projected(centre),
             measure.projected(centre + state.worldAxis(.z) * 0.002)),
            (.rotate(.z), measure.projected(centre + state.worldAxis(.x) * 0.003),
             measure.projected(centre + state.worldAxis(.y) * 0.003)),
            (.vertexMove(vertex), measure.projected(corner),
             measure.projected(corner + viewDelta)),
            (.profileCornerMove(target, vertex), measure.projected(corner),
             measure.projected(corner + planeDelta)),
            (.profileFaceMove(target, .left), measure.projected(leftFace),
             measure.projected(leftFace + state.worldAxis(.x) * 0.002)),
            (.faceMove(.top), measure.projected(topFace),
             measure.projected(topFace + state.worldAxis(.z) * 0.002)),
        ]
        for (action, start, current) in solved {
            #expect(throws: Never.self) {
                _ = try state.applying(
                    action: action, start: start, current: current, measure: measure
                )
            }
        }

        // The two edge treatments preview through the drag mapping rather than
        // the ghost edit, so their measurement is the distance and the radius.
        let edgeStart = measure.projected(edge)
        let edgeCurrent = measure.projected(edge + planeDelta)
        #expect(try state.profileEdgeChamferDistance(
            ViewportBodyEdge.leftBottom, start: edgeStart, current: edgeCurrent, measure: measure
        ) != nil)
        #expect(try state.profileEdgeFilletRadius(
            ViewportBodyEdge.leftBottom, start: edgeStart, current: edgeCurrent, measure: measure
        ) != nil)
    }

    @Test func aDegenerateWorldAxisRefusesOnlyTheActionsThatAskForIt() throws {
        let measure = try axisFrontZ()
        let state = state
        let centre = state.worldPoint(state.centerPoint)
        let start = measure.projected(centre)

        // World z runs along the view ray, so nothing can be measured on it.
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.applying(
                action: .translate(.z),
                start: start,
                current: CGPoint(x: start.x + 40.0, y: start.y),
                measure: measure
            )
        }

        // The two axes this camera draws still answer, which is the whole point
        // of scoping the refusal to the axis actually asked for.
        for axis in [ViewportCoordinateAxis.x, .y] {
            let current = measure.projected(centre + state.worldAxis(axis) * 0.002)
            let next = try #require(try state.applying(
                action: .translate(axis), start: start, current: current, measure: measure
            ))
            switch axis {
            case .x:
                #expect(abs(Double(next.xMin) - (-0.003)) < Self.tolerance)
            case .y:
                #expect(abs(Double(next.yMin) - 0.002) < Self.tolerance)
            case .z:
                Issue.record("The degenerate axis must not reach this branch.")
            }
        }

        // A face whose own axis is the degenerate one is refused; a face whose
        // own axis is drawable is solved. Asking for all three deltas made the
        // second case fail with the first, which is the defect this states.
        let leftFace = state.worldPoint(state.position(for: ViewportBodyFace.left))
        let distance = try #require(try state.profileFaceDragDistance(
            .left,
            start: measure.projected(leftFace),
            current: measure.projected(leftFace + state.worldAxis(.x) * 0.002),
            measure: measure
        ))
        #expect(abs(Double(distance) - (-0.002)) < Self.tolerance)

        let topFace = state.worldPoint(state.position(for: ViewportBodyFace.top))
        let topStart = measure.projected(topFace)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.profileFaceDragDistance(
                .top,
                start: topStart,
                current: CGPoint(x: topStart.x, y: topStart.y - 40.0),
                measure: measure
            )
        }
    }

    @Test func anEdgeOnPlaneRefusesOnlyTheActionsThatAskForIt() throws {
        let measure = try axisFrontZ()
        let state = state
        let vertex = ViewportBodyVertex.frontBottomLeft
        let corner = state.worldPoint(state.position(for: vertex))
        let cornerStart = measure.projected(corner)

        // The profile sketch plane's normal is world y, which this camera sees
        // edge-on, so the plane cannot be sampled.
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.profileCornerDragDelta(
                vertex,
                start: cornerStart,
                current: CGPoint(x: cornerStart.x + 40.0, y: cornerStart.y),
                measure: measure
            )
        }

        // The rotation plane whose normal is world z faces this camera, so the
        // same camera still answers the rotation.
        let pivot = state.worldPoint(state.centerPoint)
        let next = try #require(try state.applying(
            action: .rotate(.z),
            start: measure.projected(pivot + state.worldAxis(.x) * 0.003),
            current: measure.projected(pivot + state.worldAxis(.y) * 0.003),
            measure: measure
        ))
        #expect(abs(Double(next.orientation.xAxis.y) - 1.0) < Self.tolerance)
    }

    @Test func aPointerOnThePivotKeepsTheRetainedRotation() throws {
        let measure = try isometric()
        let state = state
        let pivot = measure.projected(state.worldPoint(state.centerPoint))

        // The sample carries no direction, which is not a refusal: the caller
        // keeps the rotation it already had.
        #expect(try state.applying(
            action: .rotate(.z), start: pivot, current: pivot, measure: measure
        ) == nil)
    }

    @Test func aRefusedQueryReachesTheCallerAsAThrownError() throws {
        let state = state
        let measure = ViewportStubAffordanceMeasure.refusesQuery
        let start = CGPoint(x: 100.0, y: 100.0)
        let current = CGPoint(x: 140.0, y: 120.0)

        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.applying(
                action: .translate(.x), start: start, current: current, measure: measure
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.applying(
                action: .vertexMove(.frontBottomLeft), start: start, current: current, measure: measure
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.applying(
                action: .rotate(.z), start: start, current: current, measure: measure
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.profileEdgeChamferDistance(
                .leftBottom, start: start, current: current, measure: measure
            )
        }
    }

    @Test func aNonFiniteAnswerIsRefusedRatherThanUsed() throws {
        let state = state
        let measure = ViewportStubAffordanceMeasure.answersNonFinite
        let start = CGPoint(x: 100.0, y: 100.0)
        let current = CGPoint(x: 140.0, y: 120.0)

        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.applying(
                action: .translate(.x), start: start, current: current, measure: measure
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.applying(
                action: .vertexMove(.frontBottomLeft), start: start, current: current, measure: measure
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.applying(
                action: .rotate(.z), start: start, current: current, measure: measure
            )
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            _ = try state.profileCornerDragDelta(
                .frontBottomLeft, start: start, current: current, measure: measure
            )
        }
    }

    @Test func profileFaceDragMappingReadsOnlyTheAxisItNames() {
        for face in ViewportBodyFace.allCases {
            let axis = ViewportProfileFaceDragMapping.axis(for: face)
            let named = ViewportProfileFaceDragMapping.distance(
                for: face,
                xDelta: axis == .x ? 1.0 : 0.0,
                yDelta: axis == .y ? 1.0 : 0.0,
                zDelta: axis == .z ? 1.0 : 0.0
            )
            let noisy = ViewportProfileFaceDragMapping.distance(
                for: face,
                xDelta: axis == .x ? 1.0 : 7.0,
                yDelta: axis == .y ? 1.0 : -3.0,
                zDelta: axis == .z ? 1.0 : 11.0
            )

            #expect(named != nil)
            #expect(named == noisy)
            #expect(abs((named ?? 0.0).magnitude - 1.0) < Self.tolerance)
        }
    }

    @Test func nativeQueryFailureCallsOnlyAnUnjudgedFrameTransient() {
        let notReady = MeshSourcePresentationRenderError(
            code: .frameNotReady, message: "not yet"
        )
        let refused = MeshSourcePresentationRenderError(code: .failed, message: "no")
        let degenerate = MeshSourcePresentationRenderError(code: .degenerate, message: "no")

        #expect(ViewportNativeQueryFailure.isTransient(notReady))
        #expect(ViewportNativeQueryFailure.transient(notReady) == notReady)
        #expect(ViewportNativeQueryFailure.isTransient(refused) == false)
        #expect(ViewportNativeQueryFailure.transient(refused) == nil)
        #expect(ViewportNativeQueryFailure.isTransient(degenerate) == false)
        #expect(ViewportNativeQueryFailure.isTransient(ViewportAffordanceMeasureTestError()) == false)

        #expect(ViewportNativeQueryFailure.description(refused) == "failed: no")
        #expect(
            ViewportNativeQueryFailure.description(ViewportAffordanceMeasureTestError())
                == String(describing: ViewportAffordanceMeasureTestError())
        )
    }
}

private struct ViewportAffordanceMeasureTestError: Error {}
