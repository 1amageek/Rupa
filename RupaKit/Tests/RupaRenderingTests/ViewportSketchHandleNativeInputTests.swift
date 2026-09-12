import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

// The four sketch handle routes are drawn in the sketch display space the
// prepared record's placement maps into the scene, and the native world-point
// owner answers all four. These tests pin the drag plane each route asks the
// mounted frame for, the arithmetic that carries the frame's answer back into
// sketch display space, and the typed refusals that replaced the legacy
// selectors' silent clamps.

/// A placement that rotates, shears and scales, so a world displacement and
/// its sketch display image share no component. The legacy selectors
/// unprojected the pointer through `ViewportLayout` without passing through
/// this matrix, which the placement makes visible as a wrong display answer.
private let sketchPlacement = Transform3D(matrix: try! Matrix4x4(values: [
    1, -1, 0, 10,
    1, 1, 0, -5,
    0, 1, 2, 3,
    0, 0, 0, 1
]))

/// A placement whose linear part collapses, so no world delta can be carried
/// back into the sketch display plane.
private let sketchFlatPlacement = Transform3D(matrix: try! Matrix4x4(values: [
    1, -1, 0, 10,
    1, 1, 0, -5,
    0, 0, 0, 3,
    0, 0, 0, 1
]))

/// The handle's own point in sketch display space, and the world point
/// `sketchPlacement` draws it at. A display point `(x, y)` lifts to the model
/// point `(x, 0, y)` before the placement carries it into the scene.
private let sketchHandlePoint = CGPoint(x: 1, y: 3)
private let sketchHandleWorldPoint = Point3D(x: 11, y: -4, z: 9)

/// A world displacement lying in the XY canvas plane whose sketch display
/// image is `(2, 1)`, so the drawn handle above is dragged to display `(3, 4)`.
private let sketchWorldDelta = Vector3D(x: 4, y: 0, z: 0)
private let sketchDisplayDelta = CGPoint(x: 2, y: 1)

/// The baseline radius of a handle drawn at `sketchHandlePoint` around the
/// display origin. Dragging it by `sketchWorldDelta` solves to exactly 5.
private let sketchBaselineRadius = 10.0.squareRoot()

private let sketchFeatureID = FeatureID()
private let sketchEntityID = SketchEntityID()
private let sketchSelection = SelectionTarget(sceneNodeID: SceneNodeID())
private let sketchRuler = RulerConfiguration.standard(for: .millimeter)

private func sketchRecord(
    _ target: ViewportSpatialPreparedInteractionTarget,
    modelTransform: Transform3D = sketchPlacement
) throws -> ViewportSpatialInteractionRecord {
    // Production prepares the record and the drawn handle from the same
    // placement, and every sketch route reads that placement off the record.
    try ViewportSpatialInteractionRecord(target: target, modelTransform: modelTransform)
}

private func sketchInput(
    _ target: ViewportSpatialPreparedInteractionTarget
) throws -> ViewportNativeWorldPointInput {
    try #require(try ViewportNativeWorldPointInput(record: try sketchRecord(target)))
}

private func worldSample(by delta: Vector3D) -> ViewportNativeWorldPointInput.Sample {
    .init(
        start: sketchHandleWorldPoint,
        current: Point3D(
            x: sketchHandleWorldPoint.x + delta.x,
            y: sketchHandleWorldPoint.y + delta.y,
            z: sketchHandleWorldPoint.z + delta.z
        )
    )
}

private func sketchValue(
    _ input: ViewportNativeWorldPointInput, by delta: Vector3D
) throws -> ViewportNativeWorldPointInput.Value {
    try input.value(
        for: worldSample(by: delta),
        document: .empty(),
        ruler: sketchRuler,
        snapOptions: nil
    )
}

private func pointHandle(
    handle: SketchEntityPointHandle = .lineStart,
    sketchPlane: SketchPlane = .xy,
    point: CGPoint = sketchHandlePoint
) -> ViewportSketchPointHandleTarget {
    ViewportSketchPointHandleTarget(
        featureID: sketchFeatureID,
        entityID: sketchEntityID,
        target: sketchSelection,
        handle: handle,
        sketchPlane: sketchPlane,
        point: point
    )
}

private func splineControlPointHandle(
    sketchPlane: SketchPlane = .xy,
    controlPointIndex: Int = 2
) -> ViewportSplineControlPointHandleTarget {
    ViewportSplineControlPointHandleTarget(
        featureID: sketchFeatureID,
        entityID: sketchEntityID,
        target: sketchSelection,
        controlPointIndex: controlPointIndex,
        sketchPlane: sketchPlane,
        point: sketchHandlePoint
    )
}

private func curveHandle(
    _ handle: ViewportSketchCurveHandleKind,
    sketchPlane: SketchPlane = .xy,
    center: CGPoint = .zero,
    radiusMeters: Double = sketchBaselineRadius,
    startAngleRadians: Double? = 0.1,
    endAngleRadians: Double? = 0.2
) -> ViewportSketchCurveHandleTarget {
    ViewportSketchCurveHandleTarget(
        featureID: sketchFeatureID,
        entityID: sketchEntityID,
        target: sketchSelection,
        handle: handle,
        sketchPlane: sketchPlane,
        point: sketchHandlePoint,
        center: center,
        radiusMeters: radiusMeters,
        startAngleRadians: startAngleRadians,
        endAngleRadians: endAngleRadians
    )
}

private func dimensionHandle(
    _ kind: SketchEntityDimensionKind,
    sketchPlane: SketchPlane = .xy,
    baselineValue: Double = 1,
    start: CGPoint? = nil,
    end: CGPoint? = nil,
    center: CGPoint? = nil,
    radiusMeters: Double? = nil,
    startAngleRadians: Double? = nil,
    endAngleRadians: Double? = nil
) -> ViewportSketchDimensionTarget {
    ViewportSketchDimensionTarget(
        featureID: sketchFeatureID,
        entityID: sketchEntityID,
        target: sketchSelection,
        kind: kind,
        sketchPlane: sketchPlane,
        point: sketchHandlePoint,
        baselineValue: baselineValue,
        start: start,
        end: end,
        center: center,
        radiusMeters: radiusMeters,
        startAngleRadians: startAngleRadians,
        endAngleRadians: endAngleRadians
    )
}

/// The baseline segment a length or linear angle dimension measures along. Its
/// sketch-local direction is `(0.6, 0.8)` and its length is exactly 1.
private let dimensionSegmentStart = CGPoint(x: 0, y: 0)
private let dimensionSegmentEnd = CGPoint(x: 0.6, y: 0.8)

@Test
func sketchPointHandleDragsOnThePlaneItsPlacementDrewItOn() throws {
    let input = try sketchInput(.sketchPointHandle(pointHandle()))

    // The plane passes through the handle's own world point rather than
    // through the model origin, so the grabbed handle stays under the pointer
    // in perspective as well as in orthographic.
    #expect(try input.query(displayedCanvas: .displayed(for: .axisFront(.z)))
        == .worldPlane(origin: sketchHandleWorldPoint, normal: Vector3D(x: 0, y: 0, z: 1)))
    #expect(try input.query(displayedCanvas: .displayed(for: .axisFront(.x)))
        == .worldPlane(origin: sketchHandleWorldPoint, normal: Vector3D(x: -1, y: 0, z: 0)))

    // World (4, 0, 0) is sketch display (2, 1) through this placement. The
    // legacy route read the canvas coordinates of an unprojected pointer and
    // never inverted the placement at all.
    guard case .sketchDisplayDelta(let delta) = try sketchValue(input, by: sketchWorldDelta) else {
        Issue.record("The sketch point handle route answered another route's value.")
        return
    }
    #expect(abs(delta.x - sketchDisplayDelta.x) < 1e-12)
    #expect(abs(delta.y - sketchDisplayDelta.y) < 1e-12)

    // The ZY canvas puts its second coordinate on world Y, and the same
    // placement carries that displacement to a different display image.
    guard case .sketchDisplayDelta(let zyDelta) = try sketchValue(
        input, by: Vector3D(x: 0, y: 4, z: 0)
    ) else {
        Issue.record("The sketch point handle route answered another route's value.")
        return
    }
    #expect(abs(zyDelta.x - 2) < 1e-12)
    #expect(abs(zyDelta.y + 1) < 1e-12)

    guard case .sketchPointHandle(let commit) = try #require(
        try input.commit(value: .sketchDisplayDelta(sketchDisplayDelta), document: .empty())
    ) else {
        Issue.record("The sketch point handle route committed another route's target.")
        return
    }
    #expect(commit.target == sketchSelection)
    #expect(commit.handle == .lineStart)
    #expect(abs(commit.deltaX - 2) < 1e-12)
    #expect(abs(commit.deltaY - 1) < 1e-12)

    // A press that released without moving writes no undo step.
    #expect(try input.commit(value: .sketchDisplayDelta(.zero), document: .empty()) == nil)
}

@Test
func sketchSplineControlPointCommitsThroughItsOwnSketchPlaneMapper() throws {
    let xyInput = try sketchInput(.splineControlPoint(splineControlPointHandle()))
    #expect(try xyInput.query(displayedCanvas: .displayed(for: .axisFront(.z)))
        == .worldPlane(origin: sketchHandleWorldPoint, normal: Vector3D(x: 0, y: 0, z: 1)))

    let value = try sketchValue(xyInput, by: sketchWorldDelta)
    guard case .sketchDisplayDelta(let delta) = value else {
        Issue.record("The spline control point route answered another route's value.")
        return
    }
    #expect(abs(delta.x - sketchDisplayDelta.x) < 1e-12)
    #expect(abs(delta.y - sketchDisplayDelta.y) < 1e-12)

    guard case .splineControlPoint(let xyCommit) = try #require(
        try xyInput.commit(value: value, document: .empty())
    ) else {
        Issue.record("The spline control point route committed another route's target.")
        return
    }
    #expect(xyCommit.target == sketchSelection)
    #expect(xyCommit.controlPointIndex == 2)
    #expect(abs(xyCommit.deltaX - 2) < 1e-12)
    #expect(abs(xyCommit.deltaY - 1) < 1e-12)

    // The ZX sketch plane swaps the display axes onto the sketch's own axes.
    // The same display displacement therefore commits the swapped pair, which
    // proves the mapper is applied rather than assumed to be the identity.
    let zxInput = try sketchInput(
        .splineControlPoint(splineControlPointHandle(sketchPlane: .zx))
    )
    guard case .splineControlPoint(let zxCommit) = try #require(
        try zxInput.commit(value: value, document: .empty())
    ) else {
        Issue.record("The spline control point route committed another route's target.")
        return
    }
    #expect(abs(zxCommit.deltaX - 1) < 1e-12)
    #expect(abs(zxCommit.deltaY - 2) < 1e-12)

    #expect(try zxInput.commit(value: .sketchDisplayDelta(.zero), document: .empty()) == nil)
}

@Test
func sketchCurveRadiusHandleSolvesFromItsOwnDrawnPoint() throws {
    let input = try sketchInput(.sketchCurveHandle(curveHandle(.circleRadius)))

    // The handle was drawn at display (1, 3) around the display origin, so the
    // drag to (3, 4) names a radius of exactly 5. The legacy route solved the
    // radius from the raw pointer position, which jumped the circle to the
    // press site before the first update moved anything.
    guard case .sketchCurveHandle(let radiusMeters, let startAngle, let endAngle) =
        try sketchValue(input, by: sketchWorldDelta)
    else {
        Issue.record("The sketch curve handle route answered another route's value.")
        return
    }
    #expect(startAngle == nil)
    #expect(endAngle == nil)
    #expect(abs(try #require(radiusMeters) - 5) < 1e-12)

    guard case .sketchCurveHandle(let commit) = try #require(try input.commit(
        value: .sketchCurveHandle(
            radiusMeters: radiusMeters, startAngleRadians: nil, endAngleRadians: nil
        ),
        document: .empty()
    )) else {
        Issue.record("The sketch curve handle route committed another route's target.")
        return
    }
    #expect(commit.target == sketchSelection)
    #expect(commit.handle == .circleRadius)
    #expect(abs(try #require(commit.radiusMeters) - 5) < 1e-12)
    #expect(commit.startAngleRadians == nil)
    #expect(commit.endAngleRadians == nil)

    // A press released without moving solves the baseline radius back, so it
    // commits nothing.
    let unmoved = try sketchValue(input, by: .zero)
    #expect(try input.commit(value: unmoved, document: .empty()) == nil)
}

@Test
func sketchCurveAngleHandleMeasuresInTheSketchPlaneItWasDrawnIn() throws {
    let xyInput = try sketchInput(.sketchCurveHandle(curveHandle(.arcStartAngle)))
    guard case .sketchCurveHandle(_, let xyStartAngle, _) =
        try sketchValue(xyInput, by: sketchWorldDelta)
    else {
        Issue.record("The sketch curve handle route answered another route's value.")
        return
    }
    // Display (3, 4) about the display origin is atan2(4, 3) on the XY plane.
    #expect(abs(try #require(xyStartAngle) - 0.9272952180016122) < 1e-12)

    // The ZX plane swaps the display axes, so the same drag names atan2(3, 4).
    // An angle is the one sketch quantity the swap does not leave invariant.
    let zxInput = try sketchInput(
        .sketchCurveHandle(curveHandle(.arcStartAngle, sketchPlane: .zx))
    )
    guard case .sketchCurveHandle(_, let zxStartAngle, _) =
        try sketchValue(zxInput, by: sketchWorldDelta)
    else {
        Issue.record("The sketch curve handle route answered another route's value.")
        return
    }
    #expect(abs(try #require(zxStartAngle) - 0.6435011087932844) < 1e-12)

    guard case .sketchCurveHandle(let commit) = try #require(try xyInput.commit(
        value: .sketchCurveHandle(
            radiusMeters: nil, startAngleRadians: xyStartAngle, endAngleRadians: nil
        ),
        document: .empty()
    )) else {
        Issue.record("The sketch curve handle route committed another route's target.")
        return
    }
    #expect(commit.handle == .arcStartAngle)
    #expect(commit.radiusMeters == nil)
    #expect(commit.endAngleRadians == nil)
    #expect(abs(try #require(commit.startAngleRadians) - 0.9272952180016122) < 1e-12)
}

@Test
func sketchLengthDimensionProjectsTheDragOntoItsBaselineSegment() throws {
    let input = try sketchInput(.sketchDimension(dimensionHandle(
        .length,
        baselineValue: 1,
        start: dimensionSegmentStart,
        end: dimensionSegmentEnd
    )))
    #expect(try input.query(displayedCanvas: .displayed(for: .axisFront(.z)))
        == .worldPlane(origin: sketchHandleWorldPoint, normal: Vector3D(x: 0, y: 0, z: 1)))

    // Display (2, 1) projected onto the unit direction (0.6, 0.8) adds 2.0 to
    // the retained baseline of 1.0.
    guard case .sketchDimension(let moved) = try sketchValue(input, by: sketchWorldDelta) else {
        Issue.record("The sketch dimension route answered another route's value.")
        return
    }
    #expect(abs(moved - 3) < 1e-12)

    guard case .sketchDimension(let commit) = try #require(
        try input.commit(value: .sketchDimension(moved), document: .empty())
    ) else {
        Issue.record("The sketch dimension route committed another route's target.")
        return
    }
    #expect(commit.target == sketchSelection)
    #expect(commit.kind == .length)
    guard case .constant(let quantity) = commit.value else {
        Issue.record("A sketch length dimension committed a non-constant expression.")
        return
    }
    #expect(quantity.kind == .length)
    #expect(abs(quantity.value - 3) < 1e-12)

    // The opposite drag crosses zero length. The legacy selector clamped it to
    // its floor and kept committing the clamped value, so the drawn dimension
    // stopped following the pointer without reporting anything.
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try sketchValue(input, by: Vector3D(x: -4, y: 0, z: 0))
    }

    #expect(try input.commit(value: .sketchDimension(1), document: .empty()) == nil)
}

@Test
func sketchRadiusDimensionSolvesFromItsOwnDrawnPoint() throws {
    let input = try sketchInput(.sketchDimension(dimensionHandle(
        .radius, baselineValue: sketchBaselineRadius, center: .zero
    )))

    guard case .sketchDimension(let moved) = try sketchValue(input, by: sketchWorldDelta) else {
        Issue.record("The sketch dimension route answered another route's value.")
        return
    }
    #expect(abs(moved - 5) < 1e-12)

    guard case .sketchDimension(let commit) = try #require(
        try input.commit(value: .sketchDimension(moved), document: .empty())
    ) else {
        Issue.record("The sketch dimension route committed another route's target.")
        return
    }
    #expect(commit.kind == .radius)
    guard case .constant(let quantity) = commit.value else {
        Issue.record("A sketch radius dimension committed a non-constant expression.")
        return
    }
    #expect(quantity.kind == .length)
    #expect(abs(quantity.value - 5) < 1e-12)

    // Solving from the handle's own drawn point means an unmoved press solves
    // the retained baseline back rather than jumping to the pointer.
    let unmoved = try sketchValue(input, by: .zero)
    #expect(try input.commit(value: unmoved, document: .empty()) == nil)
}

@Test
func sketchArcAngleDimensionRefusesSpansOutsideAPartialTurn() throws {
    // The arc tangent at end angle 0 is (0, 1), so display (2, 1) contributes a
    // tangential distance of 1, which a radius of 2 turns into half a radian.
    let input = try sketchInput(.sketchDimension(dimensionHandle(
        .angle, baselineValue: 1, radiusMeters: 2, endAngleRadians: 0
    )))
    guard case .sketchDimension(let moved) = try sketchValue(input, by: sketchWorldDelta) else {
        Issue.record("The sketch dimension route answered another route's value.")
        return
    }
    #expect(abs(moved - 1.5) < 1e-12)

    guard case .sketchDimension(let commit) = try #require(
        try input.commit(value: .sketchDimension(moved), document: .empty())
    ) else {
        Issue.record("The sketch dimension route committed another route's target.")
        return
    }
    #expect(commit.kind == .angle)
    guard case .constant(let quantity) = commit.value else {
        Issue.record("A sketch angle dimension committed a non-constant expression.")
        return
    }
    #expect(quantity.kind == .angle)
    #expect(abs(quantity.value - 1.5) < 1e-12)

    // Both ends of the legacy clamp are typed refusals now: a drag that closes
    // the arc onto itself and one that closes it into a full circle each stop
    // the preview instead of committing a span the pointer never named.
    let collapsing = try sketchInput(.sketchDimension(dimensionHandle(
        .angle, baselineValue: -0.5, radiusMeters: 2, endAngleRadians: 0
    )))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try sketchValue(collapsing, by: sketchWorldDelta)
    }

    let closing = try sketchInput(.sketchDimension(dimensionHandle(
        .angle,
        baselineValue: ViewportNativeWorldPointInput.maximumSketchArcSpan - 0.4,
        radiusMeters: 2,
        endAngleRadians: 0
    )))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try sketchValue(closing, by: sketchWorldDelta)
    }
}

@Test
func sketchHandleRoutesAreOwnedByTheWorldPointInput() throws {
    let worldPointOwned: [ViewportSpatialPreparedInteractionTarget] = [
        .sketchCurveHandle(curveHandle(.arcRadius)),
        .sketchDimension(dimensionHandle(.radius, baselineValue: 1, center: .zero)),
        .sketchPointHandle(pointHandle()),
        .splineControlPoint(splineControlPointHandle())
    ]
    for target in worldPointOwned {
        #expect(ViewportNativeWorldPointInput.claims(target))
        #expect(try ViewportNativeWorldPointInput(record: try sketchRecord(target)) != nil)
        #expect(try ViewportNativeAxisInput(record: try sketchRecord(target)) == nil)
    }
}

@Test
func sketchHandlesRefuseIncompleteGeometryAtPress() throws {
    // Each of these left the legacy route drawing a grabbable handle that
    // answered its own baseline for the length of a gesture that committed
    // nothing. The press is refused instead.
    let refused: [ViewportSpatialPreparedInteractionTarget] = [
        .sketchDimension(dimensionHandle(.diameter, baselineValue: 1)),
        .sketchDimension(dimensionHandle(
            .length,
            baselineValue: 1,
            start: dimensionSegmentStart,
            end: dimensionSegmentStart
        )),
        .sketchDimension(dimensionHandle(.radius, baselineValue: 1)),
        .sketchDimension(dimensionHandle(.angle, baselineValue: 1, endAngleRadians: 0)),
        .sketchCurveHandle(curveHandle(.circleRadius, radiusMeters: 0)),
        .sketchCurveHandle(curveHandle(.arcStartAngle, startAngleRadians: nil))
    ]
    for target in refused {
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try ViewportNativeWorldPointInput(record: try sketchRecord(target))
        }
    }

    // A placement that cannot carry a world delta back into the sketch display
    // plane is refused at press too, rather than answering the unmapped world
    // value update by update.
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportNativeWorldPointInput(record: try sketchRecord(
            .sketchPointHandle(pointHandle()), modelTransform: sketchFlatPlacement
        ))
    }
}

@Test
func sketchHandlesRefuseAValueFromAnotherRoute() throws {
    let curve = try sketchInput(.sketchCurveHandle(curveHandle(.circleRadius)))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try curve.commit(value: .sketchDisplayDelta(sketchDisplayDelta), document: .empty())
    }

    let dimension = try sketchInput(.sketchDimension(dimensionHandle(
        .radius, baselineValue: sketchBaselineRadius, center: .zero
    )))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try dimension.commit(
            value: .sketchCurveHandle(
                radiusMeters: 5, startAngleRadians: nil, endAngleRadians: nil
            ),
            document: .empty()
        )
    }

    // A curve handle dragged exactly onto its own centre names no radius and no
    // angle. The legacy route clamped that to a floor and committed it.
    let collapsed = try sketchInput(.sketchCurveHandle(
        curveHandle(.circleRadius, center: CGPoint(x: 3, y: 4))
    ))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try sketchValue(collapsed, by: sketchWorldDelta)
    }
}
