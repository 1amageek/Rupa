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
