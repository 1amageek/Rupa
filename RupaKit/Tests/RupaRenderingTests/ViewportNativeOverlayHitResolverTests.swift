import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

// MARK: - Drawn frame provenance

private let drawnOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.drawn")
private let undrawnOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.other")
private let drawnSceneNodeID = SceneNodeID()
private let drawnFeatureID = FeatureID()

/// One triangle of the occurrence the frame drew at the pointer.
///
/// The occurrence family reads nothing from this triangle but the occurrence it
/// belongs to. Its source reference is an authored mesh on purpose: an
/// occurrence is what the frame drew, whatever geometry it drew, so a body with
/// no prepared CAD topology must be admitted here exactly as a CAD body is.
private func drawnTriangle(
    occurrenceID: SceneOccurrenceID = drawnOccurrenceID
) -> MeshSourcePresentationTriangle {
    MeshSourcePresentationTriangle(
        occurrenceID: occurrenceID,
        definitionID: ObjectDefinitionID(rawValue: "definition.drawn"),
        representationID: GeometryRepresentationID(rawValue: "representation.drawn"),
        sourceReference: .authoredMesh(GeometrySourceID(rawValue: "mesh.drawn")),
        faceID: MeshFaceID(3),
        firstVertexID: MeshVertexID(0),
        secondVertexID: MeshVertexID(1),
        thirdVertexID: MeshVertexID(2),
        firstPosition: GeometryPoint3D(x: 0, y: 0, z: 0),
        secondPosition: GeometryPoint3D(x: 1, y: 0, z: 0),
        thirdPosition: GeometryPoint3D(x: 1, y: 0, z: 1)
    )
}

/// The scene item carrying the drawn occurrence.
///
/// `modelBounds` is deliberately empty. The replaced rule projected a
/// candidate's bounds and admitted the occurrence wherever that box covered the
/// pointer, so a resolver that still consulted bounds would refuse every case
/// below; admitting them proves the drawn triangle is the whole rule.
private func drawnSceneItems() -> [ViewportSceneItem] {
    [
        ViewportSceneItem(
            id: "body.drawn",
            featureID: drawnFeatureID,
            sceneNodeID: drawnSceneNodeID,
            modelBounds: .zero,
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: 1,
                sizeYMeters: 1,
                sizeZMeters: 1,
                yMinMeters: 0,
                yMaxMeters: 1
            ))
        )
    ]
}

private let drawnNavigation: [SceneOccurrenceID: SceneNodeID] = [
    drawnOccurrenceID: drawnSceneNodeID
]

// MARK: - Occurrence admission

@Test
func nativeOverlayResolverNamesTheOccurrenceTheFrameDrew() throws {
    let answer = try #require(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(),
        navigation: drawnNavigation,
        items: drawnSceneItems(),
        selectionHitPolicy: .object
    ))
    #expect(answer.hit.sceneNodeID == drawnSceneNodeID)
    #expect(answer.hit.featureID == drawnFeatureID)
    #expect(answer.hit.kind == .body)
    #expect(answer.hit.pickingBackend == .native)
    #expect(answer.hit.selectionComponent == .object)
    #expect(answer.candidate.rank == .object)
    #expect(answer.candidate.metric == 0)
}

@Test
func nativeOverlayResolverRefusesAScopeThatAdmitsNoObject() {
    for policy in [ViewportSelectionHitPolicy.face, .edge, .vertex, .region, .sketchEntity] {
        #expect(ViewportNativeOverlayHitResolver.occurrence(
            drawnBy: drawnTriangle(),
            navigation: drawnNavigation,
            items: drawnSceneItems(),
            selectionHitPolicy: policy
        ) == nil, "\(policy) admits no object hit")
    }
}

@Test
func nativeOverlayResolverAdmitsTheOccurrenceUnderTheCombinedScope() throws {
    let answer = try #require(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(),
        navigation: drawnNavigation,
        items: drawnSceneItems(),
        selectionHitPolicy: .all
    ))
    #expect(answer.hit.sceneNodeID == drawnSceneNodeID)
}

/// A drawn occurrence the scene does not navigate is a miss, never a selection
/// named after the renderer's own identifier.
@Test
func nativeOverlayResolverRefusesAnOccurrenceSceneNavigationDoesNotName() {
    #expect(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(occurrenceID: undrawnOccurrenceID),
        navigation: drawnNavigation,
        items: drawnSceneItems(),
        selectionHitPolicy: .object
    ) == nil)
}

@Test
func nativeOverlayResolverRefusesAnOccurrenceNoSceneItemCarries() {
    #expect(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(),
        navigation: drawnNavigation,
        items: [],
        selectionHitPolicy: .object
    ) == nil)
}

// MARK: - Rank order

/// The occurrence is the weakest candidate, so a pointer that also named a
/// sub-shape of the same occurrence resolves to the sub-shape.
@Test
func nativeOverlayOccurrenceLosesToEverySubshapeRank() throws {
    let occurrence = try #require(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(),
        navigation: drawnNavigation,
        items: drawnSceneItems(),
        selectionHitPolicy: .all
    )).candidate
    let subshapes: [ViewportNativeHitCandidate] = [
        // A face metric is a camera depth and a point metric is a screen
        // distance, so each is given a value far worse than the occurrence's
        // zero: rank has to decide these, not metric.
        ViewportNativeHitCandidate(rank: .face, metric: 900),
        ViewportNativeHitCandidate(rank: .edge, metric: 900),
        ViewportNativeHitCandidate(rank: .vertex, metric: 900),
    ]
    for subshape in subshapes {
        #expect(subshape.precedes(occurrence), "\(subshape.rank) outranks the occurrence")
        #expect(occurrence.precedes(subshape) == false)
    }
}

// MARK: - Surface handle displays

/// Thrown by a frame query the surface handle rule must not ask.
///
/// The rule admits a handle from its projection, the tolerance and the section
/// alone. A probe that answered `surfaceHit` would let an occlusion test slip
/// into a family the frame draws at annotation depth, so every case below runs
/// against a probe that fails rather than answers it.
private struct SurfaceHandleQueryNotAsked: Error {}

/// A frame that projects a world point onto its own `x` and `y`, reports `z` as
/// the camera depth, and answers nothing else.
private struct SurfaceHandleFrame: ViewportNativeFrameProbe {
    /// World points the frame's depth interval rejects.
    var depthRejects: [Point3D] = []
    /// World points the active section removed.
    var sectionRemoves: [Point3D] = []

    let usesPerspectiveProjection = false

    func projectedPointWithinDepthRange(
        _ point: Point3D
    ) throws -> (point: CGPoint, depth: Double)? {
        guard depthRejects.contains(point) == false else { return nil }
        return (CGPoint(x: point.x, y: point.y), point.z)
    }

    func retainsSectionedPoint(_ point: Point3D) throws -> Bool {
        sectionRemoves.contains(point) == false
    }

    func projectedPointWithDepth(
        _ point: Point3D
    ) throws -> (point: CGPoint?, depth: Double) {
        throw SurfaceHandleQueryNotAsked()
    }

    func surfaceHit(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        throw SurfaceHandleQueryNotAsked()
    }

    func regionFragment(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, depth: Double)? {
        throw SurfaceHandleQueryNotAsked()
    }

    func cameraDepthInterval() throws -> ClosedRange<Double> {
        throw SurfaceHandleQueryNotAsked()
    }

    func sectionParameterBound(
        from start: Point3D,
        to end: Point3D
    ) throws -> ViewportCameraDepthClip.AffineScalarBound? {
        throw SurfaceHandleQueryNotAsked()
    }

    func regionSegmentProbe(
        from start: CGPoint,
        to end: CGPoint,
        within rect: CGRect,
        startingAt step: Int
    ) throws -> RealityViewportRegionSegmentProbe {
        throw SurfaceHandleQueryNotAsked()
    }
}

private let handleFeatureID = FeatureID()
private let handleSceneNodeID = SceneNodeID()

private let handleSurface = SurfaceReference(subshape: StableSubshapeReference(
    subshapeID: SubshapeID(featureID: handleFeatureID, role: "surface.handle", ordinal: 0),
    geometrySignature: .face(FaceGeometrySignature(
        surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
        orientation: .forward,
        loops: []
    ))
))
private let handleTrim = SurfaceTrimReference(surface: handleSurface, loopIndex: 0, edgeIndex: 0)

private func handleKnot(_ index: Int, at point: Point3D) -> ViewportSurfaceKnotDisplay {
    ViewportSurfaceKnotDisplay(
        selectionReference: .surface(.knot(SurfaceKnotReference(
            surface: handleSurface, direction: .u, knotIndex: index
        ))),
        direction: .u, knotIndex: index, value: 0.5, point: point, u: 0.5, v: 0.5
    )
}

private func handleSpan(_ index: Int, at point: Point3D) -> ViewportSurfaceSpanDisplay {
    ViewportSurfaceSpanDisplay(
        selectionReference: .surface(.span(SurfaceSpanReference(
            surface: handleSurface, direction: .u, spanIndex: index
        ))),
        direction: .u, spanIndex: index, lowerBound: 0, upperBound: 0.5,
        point: point, u: 0.25, v: 0.5
    )
}

private func handleTrimKnot(_ index: Int, at point: Point3D) -> ViewportSurfaceTrimKnotDisplay {
    ViewportSurfaceTrimKnotDisplay(
        selectionReference: .surface(.trimKnot(SurfaceTrimKnotReference(
            trim: handleTrim, knotIndex: index
        ))),
        knotIndex: index, value: 0.5, point: point, u: 0.5, v: 0
    )
}

private func handleTrimSpan(_ index: Int, at point: Point3D) -> ViewportSurfaceTrimSpanDisplay {
    ViewportSurfaceTrimSpanDisplay(
        selectionReference: .surface(.trimSpan(SurfaceTrimSpanReference(
            trim: handleTrim, spanIndex: index
        ))),
        spanIndex: index, lowerBound: 0, upperBound: 0.5, point: point, u: 0.25, v: 0
    )
}

private func handleComponent(
    knots: [ViewportSurfaceKnotDisplay] = [],
    spans: [ViewportSurfaceSpanDisplay] = [],
    trimKnots: [ViewportSurfaceTrimKnotDisplay] = [],
    trimSpans: [ViewportSurfaceTrimSpanDisplay] = []
) -> ViewportBodyComponent {
    ViewportBodyComponent(
        sizeXMeters: 1, sizeYMeters: 1, sizeZMeters: 1, yMinMeters: 0, yMaxMeters: 1,
        surfaceKnotDisplays: knots,
        surfaceSpanDisplays: spans,
        surfaceTrimKnotDisplays: trimKnots,
        surfaceTrimSpanDisplays: trimSpans
    )
}

/// The body the displays hang from.
///
/// `modelBounds` is empty here for the same reason it is empty for the drawn
/// occurrence above: the rule is the projected handle and the pointer, never a
/// projected box.
private func handleItem(
    _ component: ViewportBodyComponent,
    sceneNodeID: SceneNodeID? = handleSceneNodeID
) -> ViewportSceneItem {
    ViewportSceneItem(
        id: "body.handles",
        featureID: handleFeatureID,
        sceneNodeID: sceneNodeID,
        modelBounds: .zero,
        kind: .body(component: component)
    )
}

private func handleAnswer(
    at point: CGPoint,
    component: ViewportBodyComponent,
    selectionHitPolicy: ViewportSelectionHitPolicy = .vertex,
    tolerance: CGFloat = 8,
    probe: SurfaceHandleFrame = SurfaceHandleFrame(),
    sceneNodeID: SceneNodeID? = handleSceneNodeID
) throws -> (hit: ViewportHit, candidate: ViewportNativeHitCandidate)? {
    try ViewportNativeOverlayHitResolver.surfaceHandle(
        at: point,
        item: handleItem(component, sceneNodeID: sceneNodeID),
        component: component,
        selectionHitPolicy: selectionHitPolicy,
        tolerance: tolerance,
        probe: probe
    )
}

// MARK: - Family presence

@Test
func nativeOverlayResolverNamesABodyThatCarriesNoSurfaceHandleDisplays() {
    #expect(ViewportNativeOverlayHitResolver.carriesSurfaceHandleDisplays(
        handleComponent()
    ) == false)
    for component in [
        handleComponent(knots: [handleKnot(0, at: Point3D(x: 0, y: 0, z: 1))]),
        handleComponent(spans: [handleSpan(0, at: Point3D(x: 0, y: 0, z: 1))]),
        handleComponent(trimKnots: [handleTrimKnot(0, at: Point3D(x: 0, y: 0, z: 1))]),
        handleComponent(trimSpans: [handleTrimSpan(0, at: Point3D(x: 0, y: 0, z: 1))]),
    ] {
        #expect(ViewportNativeOverlayHitResolver.carriesSurfaceHandleDisplays(component))
    }
}

// MARK: - Admission

/// The identity a handle answers with is the `SelectionReference` the
/// preparation assigned it, at vertex rank, and it is reached without the
/// resolver asking the frame what it drew at the pointer.
@Test
func nativeOverlaySurfaceHandleNamesThePreparedReferenceAtVertexRank() throws {
    let component = handleComponent(knots: [handleKnot(3, at: Point3D(x: 100, y: 60, z: 5))])
    let answer = try #require(try handleAnswer(
        at: CGPoint(x: 103, y: 64), component: component
    ))
    #expect(answer.hit.sceneNodeID == handleSceneNodeID)
    #expect(answer.hit.featureID == handleFeatureID)
    #expect(answer.hit.kind == .body)
    #expect(answer.hit.pickingBackend == .native)
    #expect(answer.hit.selectionReference == component.surfaceKnotDisplays[0].selectionReference)
    #expect(answer.hit.selectionComponent == nil)
    #expect(answer.candidate.rank == .vertex)
    #expect(answer.candidate.metric == 5)
}

@Test
func nativeOverlaySurfaceHandleRefusesADisplayBeyondTheTolerance() throws {
    let component = handleComponent(knots: [handleKnot(0, at: Point3D(x: 100, y: 60, z: 5))])
    #expect(try handleAnswer(at: CGPoint(x: 108.5, y: 60), component: component) == nil)
    // The boundary itself is admitted, so the refusal above is the distance and
    // not an off-by-one in the comparison.
    #expect(try handleAnswer(at: CGPoint(x: 108, y: 60), component: component) != nil)
}

@Test
func nativeOverlaySurfaceHandleRefusesAScopeThatAdmitsNoVertex() throws {
    let component = handleComponent(knots: [handleKnot(0, at: Point3D(x: 100, y: 60, z: 5))])
    for policy in [ViewportSelectionHitPolicy.face, .edge, .object, .region, .sketchEntity] {
        #expect(
            try handleAnswer(
                at: CGPoint(x: 100, y: 60), component: component, selectionHitPolicy: policy
            ) == nil,
            "\(policy) admits no vertex hit"
        )
    }
    for policy in [ViewportSelectionHitPolicy.vertex, .all] {
        #expect(
            try handleAnswer(
                at: CGPoint(x: 100, y: 60), component: component, selectionHitPolicy: policy
            ) != nil,
            "\(policy) admits a vertex hit"
        )
    }
}

/// A body with no scene node has no selection identity to answer with, so it is
/// a miss rather than a hit named after the feature alone.
@Test
func nativeOverlaySurfaceHandleRefusesABodyWithNoSceneNode() throws {
    let component = handleComponent(knots: [handleKnot(0, at: Point3D(x: 100, y: 60, z: 5))])
    #expect(try handleAnswer(
        at: CGPoint(x: 100, y: 60), component: component, sceneNodeID: nil
    ) == nil)
}

@Test
func nativeOverlaySurfaceHandleRefusesADisplayTheFrameDepthIntervalRejects() throws {
    let point = Point3D(x: 100, y: 60, z: 5)
    let component = handleComponent(knots: [handleKnot(0, at: point)])
    #expect(try handleAnswer(
        at: CGPoint(x: 100, y: 60),
        component: component,
        probe: SurfaceHandleFrame(depthRejects: [point])
    ) == nil)
}

/// The section is the one visibility question this family does ask, because the
/// frame attaches these displays to the sectioned root: a handle the cut
/// removed is not drawn and must not be selectable.
@Test
func nativeOverlaySurfaceHandleRefusesADisplayTheSectionRemoved() throws {
    let point = Point3D(x: 100, y: 60, z: 5)
    let component = handleComponent(knots: [handleKnot(0, at: point)])
    #expect(try handleAnswer(
        at: CGPoint(x: 100, y: 60),
        component: component,
        probe: SurfaceHandleFrame(sectionRemoves: [point])
    ) == nil)
}

/// A removed handle does not shadow the one behind it: the pointer resolves to
/// the nearest handle the section kept, not to nothing.
@Test
func nativeOverlaySurfaceHandleSkipsARemovedDisplayForTheNextNearestOne() throws {
    let removed = Point3D(x: 100, y: 60, z: 5)
    let kept = Point3D(x: 104, y: 60, z: 5)
    let component = handleComponent(knots: [handleKnot(0, at: removed), handleKnot(1, at: kept)])
    let answer = try #require(try handleAnswer(
        at: CGPoint(x: 100, y: 60),
        component: component,
        probe: SurfaceHandleFrame(sectionRemoves: [removed])
    ))
    #expect(answer.hit.selectionReference == component.surfaceKnotDisplays[1].selectionReference)
    #expect(answer.candidate.metric == 4)
}

// MARK: - Nearest and ties

@Test
func nativeOverlaySurfaceHandleNamesTheNearestDisplayOfEveryFamily() throws {
    let component = handleComponent(
        knots: [handleKnot(0, at: Point3D(x: 106, y: 60, z: 5))],
        spans: [handleSpan(0, at: Point3D(x: 102, y: 60, z: 5))],
        trimKnots: [handleTrimKnot(0, at: Point3D(x: 105, y: 60, z: 5))],
        trimSpans: [handleTrimSpan(0, at: Point3D(x: 104, y: 60, z: 5))]
    )
    let answer = try #require(try handleAnswer(
        at: CGPoint(x: 100, y: 60), component: component
    ))
    // The span is nearest even though its family is asked last, so the winner is
    // the distance and not the order.
    #expect(answer.hit.selectionReference == component.surfaceSpanDisplays[0].selectionReference)
    #expect(answer.candidate.metric == 2)
}

/// At a pointer equidistant from one handle of each family, the recorded order
/// decides — trim knots, trim spans, knots, then spans — which is the order the
/// replaced CPU tester asked them in.
@Test
func nativeOverlaySurfaceHandleBreaksATieByTheRecordedFamilyOrder() throws {
    let point = Point3D(x: 104, y: 60, z: 5)
    let pointer = CGPoint(x: 100, y: 60)
    let all = handleComponent(
        knots: [handleKnot(0, at: point)],
        spans: [handleSpan(0, at: point)],
        trimKnots: [handleTrimKnot(0, at: point)],
        trimSpans: [handleTrimSpan(0, at: point)]
    )
    #expect(try #require(try handleAnswer(at: pointer, component: all)).hit.selectionReference
        == all.surfaceTrimKnotDisplays[0].selectionReference)

    let withoutTrimKnots = handleComponent(
        knots: all.surfaceKnotDisplays,
        spans: all.surfaceSpanDisplays,
        trimSpans: all.surfaceTrimSpanDisplays
    )
    #expect(try #require(try handleAnswer(at: pointer, component: withoutTrimKnots)).hit.selectionReference
        == all.surfaceTrimSpanDisplays[0].selectionReference)

    let knotsAndSpans = handleComponent(
        knots: all.surfaceKnotDisplays,
        spans: all.surfaceSpanDisplays
    )
    #expect(try #require(try handleAnswer(at: pointer, component: knotsAndSpans)).hit.selectionReference
        == all.surfaceKnotDisplays[0].selectionReference)
}

/// Two displays of one family at the same projected point keep the first
/// recorded one, which is what makes the `u` and `v` knot a B-spline patch
/// records at its centre resolve to the `u` knot every time.
@Test
func nativeOverlaySurfaceHandleKeepsTheFirstOfTwoCoincidentDisplays() throws {
    let point = Point3D(x: 100, y: 60, z: 5)
    let component = handleComponent(knots: [handleKnot(0, at: point), handleKnot(1, at: point)])
    let answer = try #require(try handleAnswer(at: CGPoint(x: 100, y: 60), component: component))
    #expect(answer.hit.selectionReference == component.surfaceKnotDisplays[0].selectionReference)
}

// MARK: - Rank against the drawn body

/// A handle and the face beneath it are compared by rank, so a pointer that
/// named both resolves to the handle however near the face's own metric is.
@Test
func nativeOverlaySurfaceHandleOutranksTheFaceAndOccurrenceBeneathIt() throws {
    let component = handleComponent(knots: [handleKnot(0, at: Point3D(x: 100, y: 60, z: 5))])
    let handle = try #require(try handleAnswer(
        at: CGPoint(x: 100, y: 60), component: component, selectionHitPolicy: .all
    )).candidate
    let face = ViewportNativeHitCandidate(rank: .face, metric: 0)
    let occurrence = ViewportNativeHitCandidate(rank: .object, metric: 0)
    #expect(handle.precedes(face))
    #expect(face.precedes(handle) == false)
    #expect(handle.precedes(occurrence))
    #expect(occurrence.precedes(handle) == false)
}

// MARK: - Sketch entities and spline control points

/// Thrown by a frame query the sketch families must not ask.
private struct SketchQueryNotAsked: Error {}

/// A top view of the sketch plane.
///
/// The camera looks down `-y`, so a world point projects to
/// `(200 + 100x, 200 - 100z)` at camera depth `y + 10`. The overlay producer
/// places a sketch at `y == 0`, so every point of one sits at depth 10 and a
/// surface the frame draws nearer than that is in front of it.
private struct SketchFrame: ViewportNativeFrameProbe {
    /// Camera depth of the surface the frame draws over every pixel, or nil
    /// when it draws no surface anywhere.
    var surfaceDepth: Double?
    /// The active section keeps world points whose `x` is at most this. The
    /// polyline rule asks the section about a point it interpolated along a
    /// segment rather than about the endpoints, so this is a half-space and
    /// not a list of removed points.
    var sectionKeepsXUpTo = Double.infinity
    /// World points the camera's depth interval rejects.
    var depthRejects: [Point3D] = []

    let usesPerspectiveProjection = false

    func projectedPointWithinDepthRange(
        _ point: Point3D
    ) throws -> (point: CGPoint, depth: Double)? {
        guard depthRejects.contains(point) == false else { return nil }
        return (
            CGPoint(x: 200 + point.x * 100, y: 200 - point.z * 100),
            point.y + 10
        )
    }

    func retainsSectionedPoint(_ point: Point3D) throws -> Bool {
        point.x <= sectionKeepsXUpTo
    }

    func surfaceHit(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        guard let surfaceDepth else { return nil }
        return (drawnTriangle(), Point3D(x: 0, y: surfaceDepth - 10, z: 0))
    }

    func projectedPointWithDepth(
        _ point: Point3D
    ) throws -> (point: CGPoint?, depth: Double) {
        throw SketchQueryNotAsked()
    }

    func regionFragment(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, depth: Double)? {
        throw SketchQueryNotAsked()
    }

    func cameraDepthInterval() throws -> ClosedRange<Double> {
        throw SketchQueryNotAsked()
    }

    func sectionParameterBound(
        from start: Point3D,
        to end: Point3D
    ) throws -> ViewportCameraDepthClip.AffineScalarBound? {
        throw SketchQueryNotAsked()
    }

    func regionSegmentProbe(
        from start: CGPoint,
        to end: CGPoint,
        within rect: CGRect,
        startingAt step: Int
    ) throws -> RealityViewportRegionSegmentProbe {
        throw SketchQueryNotAsked()
    }
}

private let sketchFeatureID = FeatureID()

/// The screen point `SketchFrame` projects a sketch-plane position to.
private func sketchScreen(_ point: CGPoint) -> CGPoint {
    CGPoint(x: 200 + point.x * 100, y: 200 - point.y * 100)
}

/// The sketch scene item the families hang from.
///
/// It carries no scene node, which is what a sketch item is in production, and
/// empty `modelBounds`: the rule is the projected polyline and the pointer,
/// never a projected box.
private func sketchItem(
    _ primitives: [ViewportSketchPrimitive],
    modelTransform: Transform3D = .identity
) -> ViewportSceneItem {
    ViewportSceneItem(
        id: "sketch.native",
        featureID: sketchFeatureID,
        modelTransform: modelTransform,
        modelBounds: .zero,
        kind: .sketch(primitives: primitives)
    )
}

private func sketchAnswer(
    at point: CGPoint,
    primitives: [ViewportSketchPrimitive],
    selectionHitPolicy: ViewportSelectionHitPolicy = .sketchEntity,
    sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy = .all,
    modelTransform: Transform3D = .identity,
    tolerance: CGFloat = 8,
    probe: SketchFrame = SketchFrame()
) throws -> (hit: ViewportHit, candidate: ViewportNativeHitCandidate)? {
    let item = sketchItem(primitives, modelTransform: modelTransform)
    return try ViewportNativeOverlayHitResolver.sketchEntity(
        at: point,
        item: item,
        primitives: primitives,
        selectionHitPolicy: selectionHitPolicy,
        sketchControlPointHitPolicy: sketchControlPointHitPolicy,
        tolerance: tolerance,
        probe: probe
    )
}

private func sketchLine(
    _ entityID: SketchEntityID,
    from start: CGPoint = CGPoint(x: 0, y: 0),
    to end: CGPoint = CGPoint(x: 1, y: 0)
) -> ViewportSketchPrimitive {
    .line(entityID: entityID, start: start, end: end)
}

private func sketchSpline(
    _ entityID: SketchEntityID,
    controlPoints: [CGPoint] = [CGPoint(x: 0.5, y: 0)]
) -> ViewportSketchPrimitive {
    .spline(
        entityID: entityID,
        points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)],
        controlPoints: controlPoints,
        sketchPlane: .xy
    )
}

@Test
func nativeOverlaySketchEntityAnswersTheLineTheFrameDrew() throws {
    let entityID = SketchEntityID()
    let answer = try #require(try sketchAnswer(
        at: CGPoint(x: 250, y: 203),
        primitives: [sketchLine(entityID)]
    ))
    #expect(answer.hit.sketchEntityID == entityID)
    #expect(answer.hit.sketchControlPointIndex == nil)
    #expect(answer.hit.sketchPointHandle == nil)
    #expect(answer.hit.featureID == sketchFeatureID)
    #expect(answer.hit.sceneNodeID == nil)
    #expect(answer.hit.kind == .sketch)
    #expect(answer.hit.pickingBackend == .native)
    #expect(answer.candidate.rank == .edge)
    #expect(abs(answer.candidate.metric - 3) < 1e-9)
}

@Test
func nativeOverlaySketchEntityRefusesAPointerOutsideTheTolerance() throws {
    #expect(try sketchAnswer(
        at: CGPoint(x: 250, y: 209),
        primitives: [sketchLine(SketchEntityID())]
    ) == nil)
}

/// The frame draws a sketch polyline at scene depth, so a body in front of it
/// hides it. The replaced identity buffer recorded sketch geometry with no
/// depth at all and answered through anything drawn over it.
@Test
func nativeOverlaySketchEntityRefusesAPolylineTheFrameDrewASurfaceInFrontOf() throws {
    #expect(try sketchAnswer(
        at: CGPoint(x: 250, y: 200),
        primitives: [sketchLine(SketchEntityID())],
        probe: SketchFrame(surfaceDepth: 9)
    ) == nil)
}

/// A surface the frame drew *behind* the polyline is not an occluder, so the
/// rule is a depth comparison and not the presence of a drawn surface.
@Test
func nativeOverlaySketchEntityAdmitsAPolylineInFrontOfTheDrawnSurface() throws {
    let entityID = SketchEntityID()
    let answer = try #require(try sketchAnswer(
        at: CGPoint(x: 250, y: 200),
        primitives: [sketchLine(entityID)],
        probe: SketchFrame(surfaceDepth: 11)
    ))
    #expect(answer.hit.sketchEntityID == entityID)
}

/// The section is asked about the point on the segment the pointer is nearest
/// to, not about the segment's endpoints: one pointer on this line is kept and
/// another, on the same unclipped segment, is removed.
@Test
func nativeOverlaySketchEntityAsksTheSectionAboutThePointOnTheSegment() throws {
    let entityID = SketchEntityID()
    let probe = SketchFrame(sectionKeepsXUpTo: 0.4)
    let kept = try #require(try sketchAnswer(
        at: CGPoint(x: 220, y: 200),
        primitives: [sketchLine(entityID)],
        probe: probe
    ))
    #expect(kept.hit.sketchEntityID == entityID)
    #expect(try sketchAnswer(
        at: CGPoint(x: 280, y: 200),
        primitives: [sketchLine(entityID)],
        probe: probe
    ) == nil)
}

/// A segment whose endpoint the camera's depth interval rejects is not
/// measured against at all, rather than being measured against a projection the
/// frame does not report.
@Test
func nativeOverlaySketchEntityRefusesASegmentTheDepthIntervalRejects() throws {
    #expect(try sketchAnswer(
        at: CGPoint(x: 250, y: 200),
        primitives: [sketchLine(SketchEntityID())],
        probe: SketchFrame(depthRejects: [Point3D(x: 1, y: 0, z: 0)])
    ) == nil)
}

/// A circle is measured against the forty-nine sample polyline the overlay
/// producer draws, not against the ideal circle.
///
/// The two differ by more than the hit tolerance at this radius: a pointer on
/// the chord between two samples is on the curve the frame drew and is
/// admitted, and a pointer on the ideal arc midway between the same two samples
/// is 8.56 points from it and is refused. A query that idealised the curve
/// would answer these exactly the other way round.
@Test
func nativeOverlaySketchEntityMeasuresACircleAgainstTheDrawnChord() throws {
    let entityID = SketchEntityID()
    let radius = 40.0
    let circle = ViewportSketchPrimitive.circle(
        entityID: entityID, center: CGPoint(x: 0, y: 0), radiusMeters: radius
    )
    // The producer's own sample spacing: forty-eight steps around the circle.
    let step = Double.pi / 24.0
    let first = CGPoint(x: radius, y: 0)
    let second = CGPoint(x: radius * cos(step), y: radius * sin(step))
    let chordMidpoint = CGPoint(
        x: (first.x + second.x) / 2, y: (first.y + second.y) / 2
    )
    let arcMidpoint = CGPoint(
        x: radius * cos(step / 2), y: radius * sin(step / 2)
    )
    let answer = try #require(try sketchAnswer(
        at: sketchScreen(chordMidpoint), primitives: [circle]
    ))
    #expect(answer.hit.sketchEntityID == entityID)
    #expect(answer.candidate.rank == .edge)
    #expect(answer.candidate.metric < 1e-9)
    #expect(try sketchAnswer(
        at: sketchScreen(arcMidpoint), primitives: [circle]
    ) == nil)
}

/// An entity that is a single point is drawn as a marker at annotation depth,
/// so a surface in front of it does not hide it. It enters at edge rank, which
/// is the rank its family has.
@Test
func nativeOverlaySketchEntityAdmitsAPointEntityThroughADrawnSurface() throws {
    let entityID = SketchEntityID()
    let answer = try #require(try sketchAnswer(
        at: CGPoint(x: 202, y: 200),
        primitives: [.point(entityID: entityID, point: CGPoint(x: 0, y: 0))],
        probe: SketchFrame(surfaceDepth: 9)
    ))
    #expect(answer.hit.sketchEntityID == entityID)
    #expect(answer.hit.sketchControlPointIndex == nil)
    #expect(answer.candidate.rank == .edge)
    #expect(abs(answer.candidate.metric - 2) < 1e-9)
}

/// A control point and the polyline under it are compared by rank, so a pointer
/// that named both resolves to the control point.
@Test
func nativeOverlaySketchControlPointOutranksThePolylineUnderIt() throws {
    let entityID = SketchEntityID()
    let answer = try #require(try sketchAnswer(
        at: CGPoint(x: 250, y: 200),
        primitives: [sketchSpline(entityID)]
    ))
    #expect(answer.hit.sketchEntityID == entityID)
    #expect(answer.hit.sketchControlPointIndex == 0)
    #expect(answer.candidate.rank == .vertex)
}

/// Control point admission is the hit policy the replaced pick index was built
/// with, so a policy that admits none leaves the polyline to answer.
@Test
func nativeOverlaySketchControlPointReadsTheControlPointHitPolicy() throws {
    let entityID = SketchEntityID()
    let answer = try #require(try sketchAnswer(
        at: CGPoint(x: 250, y: 200),
        primitives: [sketchSpline(entityID)],
        sketchControlPointHitPolicy: .none
    ))
    #expect(answer.hit.sketchControlPointIndex == nil)
    #expect(answer.candidate.rank == .edge)
    let only = try #require(try sketchAnswer(
        at: CGPoint(x: 250, y: 200),
        primitives: [sketchSpline(entityID)],
        sketchControlPointHitPolicy: .only([.init(
            featureID: sketchFeatureID, entityID: entityID
        )])
    ))
    #expect(only.hit.sketchControlPointIndex == 0)
}

/// A control point is measured where the affordance producer draws it, through
/// the scene item's model transform, while the polyline is measured where the
/// overlay producer draws it. Each family reads the producer that owns what is
/// on screen; production sketch items carry the identity transform, so the two
/// mappings coincide there.
@Test
func nativeOverlaySketchControlPointFollowsTheItemModelTransform() throws {
    let entityID = SketchEntityID()
    let transform = try ViewportWorldTransformAlgebra.translation(
        Vector3D(x: 0, y: 0, z: 0.5)
    )
    let answer = try #require(try sketchAnswer(
        at: sketchScreen(CGPoint(x: 0.5, y: 0.5)),
        primitives: [sketchSpline(entityID)],
        modelTransform: transform
    ))
    #expect(answer.hit.sketchControlPointIndex == 0)
    #expect(answer.candidate.rank == .vertex)
    #expect(answer.candidate.metric < 1e-9)
}

/// `object` and `sketchEntity` both reach an entity and only `sketchEntity`
/// reaches a control point, which is the gate `ViewportSelectionHitPolicy`
/// states, so the scope that reaches a sketch is unchanged by moving the query
/// onto the frame.
@Test
func nativeOverlaySketchFamiliesKeepTheirScopeGates() throws {
    let entityID = SketchEntityID()
    let object = try #require(try sketchAnswer(
        at: CGPoint(x: 250, y: 200),
        primitives: [sketchSpline(entityID)],
        selectionHitPolicy: .object
    ))
    #expect(object.hit.sketchEntityID == entityID)
    #expect(object.hit.sketchControlPointIndex == nil)
    #expect(object.candidate.rank == .edge)
    for policy in [ViewportSelectionHitPolicy.sketchEntity, .all] {
        let answer = try #require(try sketchAnswer(
            at: CGPoint(x: 250, y: 200),
            primitives: [sketchSpline(entityID)],
            selectionHitPolicy: policy
        ), "\(policy) reaches a control point")
        #expect(answer.hit.sketchControlPointIndex == 0)
        #expect(answer.candidate.rank == .vertex)
    }
}

@Test
func nativeOverlaySketchEntityRefusesAScopeThatReachesNoSketch() throws {
    let entityID = SketchEntityID()
    for policy in [ViewportSelectionHitPolicy.face, .edge, .vertex, .region] {
        #expect(try sketchAnswer(
            at: CGPoint(x: 250, y: 200),
            primitives: [sketchSpline(entityID)],
            selectionHitPolicy: policy
        ) == nil, "\(policy) reaches no sketch")
    }
}

/// A pointer on a line's endpoint answers the line at edge rank. No pick index
/// ever recorded an endpoint handle, so this path does not invent a
/// vertex-ranked one for the endpoint to win the pointer with.
@Test
func nativeOverlaySketchEntityInventsNoEndpointHandle() throws {
    let entityID = SketchEntityID()
    let answer = try #require(try sketchAnswer(
        at: sketchScreen(CGPoint(x: 1, y: 0)),
        primitives: [sketchLine(entityID)]
    ))
    #expect(answer.hit.sketchEntityID == entityID)
    #expect(answer.hit.sketchPointHandle == nil)
    #expect(answer.hit.sketchControlPointIndex == nil)
    #expect(answer.candidate.rank == .edge)
}

/// Two entities within the tolerance are ordered by their distance to the
/// pointer, so the nearer polyline answers.
@Test
func nativeOverlaySketchEntityAnswersTheNearerOfTwoEntities() throws {
    let near = SketchEntityID()
    let far = SketchEntityID()
    let answer = try #require(try sketchAnswer(
        at: CGPoint(x: 250, y: 202),
        primitives: [
            sketchLine(far, from: CGPoint(x: 0, y: -0.05), to: CGPoint(x: 1, y: -0.05)),
            sketchLine(near),
        ]
    ))
    #expect(answer.hit.sketchEntityID == near)
    #expect(abs(answer.candidate.metric - 2) < 1e-9)
}

// MARK: - Sketch regions

/// Thrown by a frame query the sketch region rule must not ask.
///
/// The rule clips a world boundary and projects what survives, so a probe that
/// answered `surfaceHit` or `projectedPointWithinDepthRange` would let an
/// occlusion test or a second projection rule slip into a family that has
/// neither. Every case below runs against a probe that fails rather than
/// answers them.
private struct RegionQueryNotAsked: Error {}

/// A top view of the sketch plane that answers the three queries the region
/// rule asks.
///
/// It projects the way `SketchFrame` does — a world point lands at
/// `(200 + 100x, 200 - 100z)` at camera depth `y + 10` — so a region the
/// overlay producer places at `y == 0` is drawn at depth 10.
private struct RegionFrame: ViewportNativeFrameProbe {
    /// The camera's depth interval. The default keeps everything a top view
    /// draws, so a case that removes a region has to say so.
    var depthInterval: ClosedRange<Double> = 0...Double.infinity
    /// The active section keeps world points whose `x` is at most this, in the
    /// shape the mounted frame reports one: a signed distance per endpoint and
    /// a bound the retained side is at least. `nil` is a frame with no cut.
    var sectionKeepsXUpTo: Double?
    /// Sketch-plane positions the frame reports a non-finite depth for.
    var nonFiniteDepths: [CGPoint] = []
    /// Sketch-plane positions the frame cannot project.
    var unprojectable: [CGPoint] = []

    let usesPerspectiveProjection = false

    func projectedPointWithDepth(
        _ point: Point3D
    ) throws -> (point: CGPoint?, depth: Double) {
        let plane = CGPoint(x: point.x, y: point.z)
        let depth = nonFiniteDepths.contains(plane) ? Double.nan : point.y + 10
        guard unprojectable.contains(plane) == false else {
            return (nil, depth)
        }
        return (CGPoint(x: 200 + point.x * 100, y: 200 - point.z * 100), depth)
    }

    func cameraDepthInterval() throws -> ClosedRange<Double> {
        depthInterval
    }

    func sectionParameterBound(
        from start: Point3D,
        to end: Point3D
    ) throws -> ViewportCameraDepthClip.AffineScalarBound? {
        guard let sectionKeepsXUpTo else { return nil }
        return ViewportCameraDepthClip.AffineScalarBound(
            start: sectionKeepsXUpTo - start.x,
            end: sectionKeepsXUpTo - end.x,
            bound: 0,
            retainsValuesAtLeastBound: true
        )
    }

    func projectedPointWithinDepthRange(
        _ point: Point3D
    ) throws -> (point: CGPoint, depth: Double)? {
        throw RegionQueryNotAsked()
    }

    func retainsSectionedPoint(_ point: Point3D) throws -> Bool {
        throw RegionQueryNotAsked()
    }

    func surfaceHit(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        throw RegionQueryNotAsked()
    }

    func regionFragment(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, depth: Double)? {
        throw RegionQueryNotAsked()
    }

    func regionSegmentProbe(
        from start: CGPoint,
        to end: CGPoint,
        within rect: CGRect,
        startingAt step: Int
    ) throws -> RealityViewportRegionSegmentProbe {
        throw RegionQueryNotAsked()
    }
}

/// A unit square on the sketch plane, drawn at `(200, 100)...(300, 200)`.
private let regionSquarePoints = [
    CGPoint(x: 0, y: 0),
    CGPoint(x: 1, y: 0),
    CGPoint(x: 1, y: 1),
    CGPoint(x: 0, y: 1),
]

/// An L with its notch in the `x > 1, y > 1` quadrant, which a convex hull of
/// the same boundary would cover.
private let regionConcavePoints = [
    CGPoint(x: 0, y: 0),
    CGPoint(x: 2, y: 0),
    CGPoint(x: 2, y: 1),
    CGPoint(x: 1, y: 1),
    CGPoint(x: 1, y: 2),
    CGPoint(x: 0, y: 2),
]

private func sketchRegion(
    _ identifier: String,
    points: [CGPoint]
) -> ViewportSketchRegion {
    ViewportSketchRegion(
        componentID: SelectionComponentID(rawValue: identifier),
        points: points
    )
}

private func regionAnswer(
    at point: CGPoint,
    regions: [ViewportSketchRegion],
    selectionHitPolicy: ViewportSelectionHitPolicy = .region,
    probe: RegionFrame = RegionFrame()
) throws -> (hit: ViewportHit, candidate: ViewportNativeHitCandidate)? {
    let item = ViewportSceneItem(
        id: "sketch.native",
        featureID: sketchFeatureID,
        modelBounds: .zero,
        kind: .sketch(primitives: []),
        sketchRegions: regions
    )
    return try ViewportNativeOverlayHitResolver.sketchRegion(
        at: point,
        item: item,
        selectionHitPolicy: selectionHitPolicy,
        probe: probe
    )
}

@Test
func nativeOverlaySketchRegionAnswersAPointerInsideItsDrawnBoundary() throws {
    let answer = try #require(try regionAnswer(
        at: sketchScreen(CGPoint(x: 0.5, y: 0.5)),
        regions: [sketchRegion("region.square", points: regionSquarePoints)]
    ))
    #expect(answer.hit.selectionComponent == .region(
        SelectionComponentID(rawValue: "region.square")
    ))
    #expect(answer.hit.featureID == sketchFeatureID)
    #expect(answer.hit.sceneNodeID == nil)
    #expect(answer.hit.kind == .sketch)
    #expect(answer.hit.pickingBackend == .native)
    #expect(answer.candidate.rank == .face)
    #expect(answer.candidate.metric == 0)
}

/// The rule is containment and not a tolerance, so a pointer just outside the
/// boundary is refused rather than admitted at a small distance.
@Test
func nativeOverlaySketchRegionRefusesAPointerOutsideItsDrawnBoundary() throws {
    #expect(try regionAnswer(
        at: sketchScreen(CGPoint(x: 1.02, y: 0.5)),
        regions: [sketchRegion("region.square", points: regionSquarePoints)]
    ) == nil)
}

/// A concave boundary answers the pointers in both of its arms.
@Test
func nativeOverlaySketchRegionAnswersBothArmsOfAConcaveBoundary() throws {
    for plane in [CGPoint(x: 1.5, y: 0.5), CGPoint(x: 0.5, y: 1.5)] {
        let answer = try #require(try regionAnswer(
            at: sketchScreen(plane),
            regions: [sketchRegion("region.concave", points: regionConcavePoints)]
        ))
        #expect(answer.hit.selectionComponent == .region(
            SelectionComponentID(rawValue: "region.concave")
        ), "\(plane) lies in an arm")
    }
}

/// The notch of the same boundary is refused, which containment of its convex
/// hull would have admitted.
@Test
func nativeOverlaySketchRegionRefusesTheNotchOfAConcaveBoundary() throws {
    #expect(try regionAnswer(
        at: sketchScreen(CGPoint(x: 1.5, y: 1.5)),
        regions: [sketchRegion("region.concave", points: regionConcavePoints)]
    ) == nil)
}

/// The section cuts the boundary before it is projected, so the surviving side
/// answers and the removed side does not — a pointer the whole square would
/// have contained.
@Test
func nativeOverlaySketchRegionAnswersOnlyTheSideTheSectionKeeps() throws {
    let probe = RegionFrame(sectionKeepsXUpTo: 0.5)
    let regions = [sketchRegion("region.square", points: regionSquarePoints)]
    let kept = try #require(try regionAnswer(
        at: sketchScreen(CGPoint(x: 0.25, y: 0.5)),
        regions: regions,
        probe: probe
    ))
    #expect(kept.hit.selectionComponent == .region(
        SelectionComponentID(rawValue: "region.square")
    ))
    #expect(try regionAnswer(
        at: sketchScreen(CGPoint(x: 0.75, y: 0.5)),
        regions: regions,
        probe: probe
    ) == nil)
}

/// A section that removes the whole boundary leaves no area, so the pointer it
/// used to contain answers nothing.
@Test
func nativeOverlaySketchRegionRefusesARegionTheSectionRemovesEntirely() throws {
    #expect(try regionAnswer(
        at: sketchScreen(CGPoint(x: 0.5, y: 0.5)),
        regions: [sketchRegion("region.square", points: regionSquarePoints)],
        probe: RegionFrame(sectionKeepsXUpTo: -1)
    ) == nil)
}

/// The camera's depth interval narrows the same boundary, so a region drawn
/// nearer than the interval starts answers nothing.
@Test
func nativeOverlaySketchRegionRefusesARegionTheCameraDepthIntervalRemoves() throws {
    #expect(try regionAnswer(
        at: sketchScreen(CGPoint(x: 0.5, y: 0.5)),
        regions: [sketchRegion("region.square", points: regionSquarePoints)],
        probe: RegionFrame(depthInterval: 20...Double.infinity)
    ) == nil)
}

/// A boundary vertex the frame answers a non-finite depth for is a typed
/// refusal. Skipping it would answer the pointer over a boundary smaller than
/// the one the region has.
@Test
func nativeOverlaySketchRegionRefusesABoundaryWithANonFiniteDepth() {
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try regionAnswer(
            at: sketchScreen(CGPoint(x: 0.5, y: 0.5)),
            regions: [sketchRegion("region.square", points: regionSquarePoints)],
            probe: RegionFrame(nonFiniteDepths: [CGPoint(x: 1, y: 1)])
        )
    }
}

/// A boundary vertex the clip retained and the frame cannot project is the same
/// typed refusal, and not a boundary quietly closed over the gap.
@Test
func nativeOverlaySketchRegionRefusesABoundaryVertexItCannotProject() {
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try regionAnswer(
            at: sketchScreen(CGPoint(x: 0.5, y: 0.5)),
            regions: [sketchRegion("region.square", points: regionSquarePoints)],
            probe: RegionFrame(unprojectable: [CGPoint(x: 1, y: 1)])
        )
    }
}

/// One profile's boundary can lie inside another's, so a pointer both contain
/// is resolved by the nearer projected centroid and not by scene order.
@Test
func nativeOverlaySketchRegionAnswersTheNearerCentroidOfTwoNestedRegions() throws {
    let outer = sketchRegion("region.outer", points: [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 4, y: 0),
        CGPoint(x: 4, y: 4),
        CGPoint(x: 0, y: 4),
    ])
    let inner = sketchRegion("region.inner", points: [
        CGPoint(x: 1, y: 1),
        CGPoint(x: 2, y: 1),
        CGPoint(x: 2, y: 2),
        CGPoint(x: 1, y: 2),
    ])
    for regions in [[outer, inner], [inner, outer]] {
        let answer = try #require(try regionAnswer(
            at: sketchScreen(CGPoint(x: 1.5, y: 1.5)),
            regions: regions
        ))
        #expect(answer.hit.selectionComponent == .region(
            SelectionComponentID(rawValue: "region.inner")
        ), "the inner centroid is nearer whichever order the scene lists")
        #expect(answer.candidate.metric == 0)
    }
}

/// The scopes that admit a region reach the family; the scopes that do not
/// answer nothing, whatever the frame draws.
@Test
func nativeOverlaySketchRegionAnswersOnlyTheScopesThatAdmitARegion() throws {
    let regions = [sketchRegion("region.square", points: regionSquarePoints)]
    let pointer = sketchScreen(CGPoint(x: 0.5, y: 0.5))
    for policy in [ViewportSelectionHitPolicy.region, .all] {
        #expect(try regionAnswer(
            at: pointer,
            regions: regions,
            selectionHitPolicy: policy
        ) != nil, "\(policy) admits a region hit")
    }
    for policy in [
        ViewportSelectionHitPolicy.object, .face, .edge, .vertex, .sketchEntity,
    ] {
        #expect(try regionAnswer(
            at: pointer,
            regions: regions,
            selectionHitPolicy: policy
        ) == nil, "\(policy) admits no region hit")
    }
}
