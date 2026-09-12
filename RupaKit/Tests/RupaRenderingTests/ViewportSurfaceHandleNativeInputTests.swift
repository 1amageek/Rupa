import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

// The four surface handle routes are prepared once and then answered by one of
// the two native input owners. Which owner answers is decided by the drag mode,
// not by the press site, so these tests pin the partition and the arithmetic
// each owner performs on the frame's answer.

/// A placement that rotates, shears and scales, so a world displacement and its
/// model-space image share no component. The legacy screen-chord geometry read
/// the canvas plane's second coordinate as world Z under every projection, which
/// this placement makes visible as a wrong model-space answer.
private let surfacePlacement = Transform3D(matrix: try! Matrix4x4(values: [
    1, -1, 0, 10,
    1, 1, 0, -5,
    0, 1, 2, 3,
    0, 0, 0, 1
]))

/// `surfacePlacement` carries this authored point to `surfaceWorldPoint`.
private let surfaceLocalPoint = Point3D(x: 1, y: 2, z: 3)
private let surfaceWorldPoint = Point3D(x: 9, y: -2, z: 11)

private let surfaceFeatureID = FeatureID()

private let surfaceSubshape = SurfaceReference(subshape: .init(
    subshapeID: SubshapeID(featureID: surfaceFeatureID, role: "surface", ordinal: 0),
    geometrySignature: .vertex(point: .origin)
))

private func controlPointReference(uIndex: Int = 1, vIndex: Int = 2) -> SelectionReference {
    .surface(.controlPoint(.init(surface: surfaceSubshape, uIndex: uIndex, vIndex: vIndex)))
}

private let trimReference = SelectionReference.surface(.trim(SurfaceTrimReference(
    surface: surfaceSubshape, loopIndex: 0, edgeIndex: 1
)))

private func controlPointHandle(
    dragMode: ViewportPolySplineSurfaceVertexDragMode
) -> ViewportSurfaceControlPointHandleTarget {
    ViewportSurfaceControlPointHandleTarget(
        featureID: surfaceFeatureID,
        target: controlPointReference(),
        point: surfaceLocalPoint,
        modelTransform: surfacePlacement,
        dragMode: dragMode
    )
}

private func vertexHandle(
    dragMode: ViewportPolySplineSurfaceVertexDragMode
) -> ViewportPolySplineSurfaceVertexHandleTarget {
    ViewportPolySplineSurfaceVertexHandleTarget(
        featureID: surfaceFeatureID,
        target: SelectionTarget(sceneNodeID: SceneNodeID(), component: .object),
        componentID: SelectionComponentID(rawValue: "poly-spline-surface"),
        point: surfaceLocalPoint,
        modelTransform: surfacePlacement,
        dragMode: dragMode
    )
}

private let trimTangentU = Vector3D(x: 2, y: 0, z: 0)
private let trimTangentV = Vector3D(x: 0, y: 4, z: 0)

private func trimEndpointHandle(
    tangentU: Vector3D = trimTangentU, tangentV: Vector3D = trimTangentV
) -> ViewportSurfaceTrimEndpointHandleTarget {
    ViewportSurfaceTrimEndpointHandleTarget(
        featureID: surfaceFeatureID,
        target: trimReference,
        endpoint: .end,
        point: surfaceLocalPoint,
        u: 0.3,
        v: 0.7,
        tangentU: tangentU,
        tangentV: tangentV,
        modelTransform: surfacePlacement
    )
}

private func trimControlPointHandle(
    tangentU: Vector3D = trimTangentU, tangentV: Vector3D = trimTangentV
) -> ViewportSurfaceTrimControlPointHandleTarget {
    ViewportSurfaceTrimControlPointHandleTarget(
        featureID: surfaceFeatureID,
        target: trimReference,
        controlPointIndex: 2,
        point: surfaceLocalPoint,
        u: 0.3,
        v: 0.7,
        tangentU: tangentU,
        tangentV: tangentV,
        modelTransform: surfacePlacement
    )
}

private func surfaceRecord(
    _ target: ViewportSpatialPreparedInteractionTarget
) throws -> ViewportSpatialInteractionRecord {
    // Production prepares the record and the handle payload from the same
    // placement, and the axis owner reads the source scale from the record.
    try ViewportSpatialInteractionRecord(target: target, modelTransform: surfacePlacement)
}

private func worldSample(by delta: Vector3D) -> ViewportNativeWorldPointInput.Sample {
    .init(
        start: surfaceWorldPoint,
        current: Point3D(
            x: surfaceWorldPoint.x + delta.x,
            y: surfaceWorldPoint.y + delta.y,
            z: surfaceWorldPoint.z + delta.z
        )
    )
}

private func expectClose(
    _ value: Vector3D, _ expected: Vector3D,
    _ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(abs(value.x - expected.x) < 1e-12, comment, sourceLocation: sourceLocation)
    #expect(abs(value.y - expected.y) < 1e-12, comment, sourceLocation: sourceLocation)
    #expect(abs(value.z - expected.z) < 1e-12, comment, sourceLocation: sourceLocation)
}

private let surfaceRuler = RulerConfiguration.standard(for: .millimeter)

@Test
func planarSurfaceHandleCarriesTheFrameDeltaThroughItsOwnPlacement() throws {
    let record = try surfaceRecord(.surfaceControlPoint(controlPointHandle(dragMode: .planar)))
    let input = try #require(try ViewportNativeWorldPointInput(record: record))

    // The drag plane passes through the handle's own world point, not through
    // the world origin, so the grabbed handle stays under the pointer in
    // perspective as well as in orthographic.
    #expect(try input.query(displayedCanvas: .displayed(for: .axisFront(.z)))
        == .worldPlane(origin: surfaceWorldPoint, normal: Vector3D(x: 0, y: 0, z: 1)))

    // World (0.3, 0.5, 0) on the XY canvas is model (0.4, 0.1, -0.05) here. The
    // legacy geometry answered (0.3, 0, 0.5) in world space for the same drag.
    let xyValue = try input.value(
        for: worldSample(by: Vector3D(x: 0.3, y: 0.5, z: 0)),
        document: .empty(), ruler: surfaceRuler, snapOptions: nil
    )
    guard case .surfaceHandleLocalDelta(let xyDelta) = xyValue else {
        Issue.record("The planar surface route answered another route's value.")
        return
    }
    expectClose(xyDelta, Vector3D(x: 0.4, y: 0.1, z: -0.05),
                "The planar route did not invert its placement.")

    // The ZY canvas puts its second coordinate on world Y. The legacy geometry
    // applied that coordinate to world Z under every projection mode.
    #expect(try input.query(displayedCanvas: .displayed(for: .axisFront(.x)))
        == .worldPlane(origin: surfaceWorldPoint, normal: Vector3D(x: -1, y: 0, z: 0)))
    let zyValue = try input.value(
        for: worldSample(by: Vector3D(x: 0, y: 0.5, z: 0.3)),
        document: .empty(), ruler: surfaceRuler, snapOptions: nil
    )
    guard case .surfaceHandleLocalDelta(let zyDelta) = zyValue else {
        Issue.record("The planar surface route answered another route's value.")
        return
    }
    expectClose(zyDelta, Vector3D(x: 0.25, y: 0.25, z: 0.025),
                "The planar route did not invert its placement.")

    guard case .surfaceControlPoint(let commit) = try #require(
        try input.commit(value: xyValue, document: .empty())
    ) else {
        Issue.record("The planar surface route committed another route's target.")
        return
    }
    #expect(commit.target == controlPointReference())
    expectClose(Vector3D(x: commit.deltaX, y: commit.deltaY, z: commit.deltaZ),
                Vector3D(x: 0.4, y: 0.1, z: -0.05),
                "The committed displacement is not the previewed one.")
    #expect(try input.commit(
        value: .surfaceHandleLocalDelta(.zero), document: .empty()
    ) == nil)
}

@Test
func axisSurfaceHandleMeasuresAlongItsOwnModelDirection() throws {
    let record = try surfaceRecord(.polySplineSurfaceVertex(vertexHandle(dragMode: .axis(.y))))
    let input = try #require(try ViewportNativeAxisInput(record: record))

    // The axis is the model Y direction traced through the handle's placement,
    // anchored at the handle rather than at the model origin.
    #expect(input.axis.origin == surfaceWorldPoint)
    expectClose(input.axis.direction, Vector3D(x: -1, y: 1, z: 1),
                "The handle axis is not the placed model direction.")
    #expect(input.axis.baseValue == 0)

    // One world metre along that axis is 1/sqrt(3) model units.
    let scale = 1.0 / 3.0.squareRoot()
    #expect(abs(input.sourceUnitsPerWorldMetre - scale) < 1e-12)
    let value = try input.value(forWorldDelta: 0.6)
    #expect(abs(value - 0.6 * scale) < 1e-12)

    let delta = try #require(input.localDelta(for: value))
    expectClose(delta, Vector3D(x: 0, y: 0.6 * scale, z: 0),
                "The axis route left the model direction it was prepared on.")

    guard case .polySplineSurfaceVertex(let commit) = try #require(try input.commit(value: value))
    else {
        Issue.record("The axis surface route committed another route's target.")
        return
    }
    expectClose(Vector3D(x: commit.deltaX, y: commit.deltaY, z: commit.deltaZ), delta,
                "The committed displacement is not the measured one.")
    #expect(try input.commit(value: 0) == nil)
}

@Test
func localAxisSurfaceHandleMeasuresAlongItsAuthoredDirection() throws {
    let handle = controlPointHandle(dragMode: .localAxis(.u, direction: .unitZ))
    let input = try #require(
        try ViewportNativeAxisInput(record: try surfaceRecord(.surfaceControlPoint(handle)))
    )
    #expect(input.axis.origin == surfaceWorldPoint)
    expectClose(input.axis.direction, Vector3D(x: 0, y: 0, z: 2),
                "The local-axis handle axis is not the placed authored direction.")
    #expect(abs(input.sourceUnitsPerWorldMetre - 0.5) < 1e-12)

    let value = try input.value(forWorldDelta: 1)
    #expect(abs(value - 0.5) < 1e-12)
    guard case .surfaceControlPoint(let commit) = try #require(try input.commit(value: value))
    else {
        Issue.record("The local-axis surface route committed another route's target.")
        return
    }
    expectClose(Vector3D(x: commit.deltaX, y: commit.deltaY, z: commit.deltaZ),
                Vector3D(x: 0, y: 0, z: 0.5),
                "The local-axis route left the authored direction.")
}

@Test
func surfaceHandleRoutesPartitionBetweenTheTwoNativeOwners() throws {
    let axisOwned: [ViewportSpatialPreparedInteractionTarget] = [
        .polySplineSurfaceVertex(vertexHandle(dragMode: .axis(.y))),
        .polySplineSurfaceVertex(vertexHandle(dragMode: .localAxis(.u, direction: .unitZ))),
        .surfaceControlPoint(controlPointHandle(dragMode: .axis(.x))),
        .surfaceControlPoint(controlPointHandle(dragMode: .localAxis(.v, direction: .unitY)))
    ]
    for target in axisOwned {
        #expect(ViewportNativeWorldPointInput.claims(target) == false)
        #expect(try ViewportNativeWorldPointInput(record: try surfaceRecord(target)) == nil)
        #expect(try ViewportNativeAxisInput(record: try surfaceRecord(target)) != nil)
    }

    let worldPointOwned: [ViewportSpatialPreparedInteractionTarget] = [
        .polySplineSurfaceVertex(vertexHandle(dragMode: .planar)),
        .surfaceControlPoint(controlPointHandle(dragMode: .planar)),
        .surfaceTrimEndpoint(trimEndpointHandle()),
        .surfaceTrimControlPoint(trimControlPointHandle())
    ]
    for target in worldPointOwned {
        #expect(ViewportNativeWorldPointInput.claims(target))
        #expect(try ViewportNativeWorldPointInput(record: try surfaceRecord(target)) != nil)
        #expect(try ViewportNativeAxisInput(record: try surfaceRecord(target)) == nil)
    }
}

@Test
func surfaceTrimHandleSolvesItsParameterPairFromTheRetainedTangentBasis() throws {
    let endpoint = try #require(try ViewportNativeWorldPointInput(
        record: try surfaceRecord(.surfaceTrimEndpoint(trimEndpointHandle()))
    ))
    #expect(try endpoint.query(displayedCanvas: .displayed(for: .axisFront(.z)))
        == .worldPlane(origin: surfaceWorldPoint, normal: Vector3D(x: 0, y: 0, z: 1)))

    // Model (0.4, 0.1, -0.05) against tangents (2, 0, 0) and (0, 4, 0) solves to
    // (0.2, 0.025), so the retained (0.3, 0.7) becomes (0.5, 0.725).
    let value = try endpoint.value(
        for: worldSample(by: Vector3D(x: 0.3, y: 0.5, z: 0)),
        document: .empty(), ruler: surfaceRuler, snapOptions: nil
    )
    guard case .surfaceTrimEndpoint(let endpointCommit) = try #require(
        try endpoint.commit(value: value, document: .empty())
    ) else {
        Issue.record("The trim endpoint route committed another route's target.")
        return
    }
    #expect(endpointCommit.target == trimReference)
    #expect(endpointCommit.endpoint == .end)
    #expect(abs(endpointCommit.u - 0.5) < 1e-12)
    #expect(abs(endpointCommit.v - 0.725) < 1e-12)

    let controlPoint = try #require(try ViewportNativeWorldPointInput(
        record: try surfaceRecord(.surfaceTrimControlPoint(trimControlPointHandle()))
    ))
    guard case .surfaceTrimControlPoint(let controlPointCommit) = try #require(
        try controlPoint.commit(value: value, document: .empty())
    ) else {
        Issue.record("The trim control point route committed another route's target.")
        return
    }
    #expect(controlPointCommit.controlPointIndex == 2)
    #expect(abs(controlPointCommit.u - 0.5) < 1e-12)
    #expect(abs(controlPointCommit.v - 0.725) < 1e-12)

    // A drag off the tangent plane moves the handle in world space but names no
    // parameter change, so the release writes no undo step.
    let offPatch = try endpoint.value(
        for: worldSample(by: Vector3D(x: 0, y: 0, z: 0.2)),
        document: .empty(), ruler: surfaceRuler, snapOptions: nil
    )
    guard case .surfaceHandleLocalDelta(let offPatchDelta) = offPatch else {
        Issue.record("The trim endpoint route answered another route's value.")
        return
    }
    expectClose(offPatchDelta, Vector3D(x: 0, y: 0, z: 0.1),
                "The off-patch drag did not reach model space.")
    #expect(try endpoint.commit(value: offPatch, document: .empty()) == nil)
}

@Test
func surfaceTrimHandleRefusesADegenerateTangentBasisAtPress() throws {
    // A handle whose tangents span no patch can never resolve. It is refused at
    // press rather than dropped update by update, so it never stays drawn and
    // grabbable for the length of a gesture that commits nothing.
    let parallelU = Vector3D(x: 2, y: 0, z: 0)
    let parallelV = Vector3D(x: 4, y: 0, z: 0)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportNativeWorldPointInput(record: try surfaceRecord(.surfaceTrimEndpoint(
            trimEndpointHandle(tangentU: parallelU, tangentV: parallelV)
        )))
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportNativeWorldPointInput(record: try surfaceRecord(.surfaceTrimControlPoint(
            trimControlPointHandle(tangentU: parallelU, tangentV: .zero)
        )))
    }
}
