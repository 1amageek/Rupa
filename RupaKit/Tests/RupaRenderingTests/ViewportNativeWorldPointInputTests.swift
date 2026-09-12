import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// The canvas plane `.axisFront(.z)` displays: world X and world Y, so its
/// normal is world Z and a drag on it moves world Y. The legacy pattern drag
/// applied the canvas plane's second coordinate to world Z regardless of the
/// mode, which pinned Y on exactly this projection.
private let worldPointCanvas = ViewportCanvasPlane.displayed(for: .axisFront(.z))

private let bridgePlacement = Transform3D(matrix: try! Matrix4x4(values: [
    0, 0, -3, 10,
    0, 1, 0, 0,
    2, 0, 0, 20,
    0, 0, 0, 1
]))

private func constructionPlaneRecord(
    handle: ViewportConstructionPlaneHandleKind
) throws -> ViewportSpatialInteractionRecord {
    let origin = Point3D(x: 0.2, y: -0.1, z: 0.4)
    let normal = Vector3D(x: 0, y: 0, z: 1)
    let normalEnd = Point3D(x: 0.2, y: -0.1, z: 0.65)
    return try ViewportSpatialInteractionRecord(target: .constructionPlane(
        identity: .init(
            constructionPlaneID: ConstructionPlaneSourceID(),
            sceneNodeID: SceneNodeID(),
            handle: handle
        ),
        origin: origin,
        normal: normal,
        normalEnd: normalEnd,
        corners: [
            Point3D(x: -0.1, y: -0.1, z: 0.4),
            Point3D(x: 0.5, y: -0.1, z: 0.4),
            Point3D(x: 0.5, y: 0.3, z: 0.4),
            Point3D(x: -0.1, y: 0.3, z: 0.4)
        ]
    ))
}

private let patternPathPoints: [Point3D] = [
    .origin,
    Point3D(x: 0.5, y: 0.25, z: -0.3),
    Point3D(x: 0.9, y: 0.25, z: -0.3)
]

private func patternRecord() throws -> ViewportSpatialInteractionRecord {
    try ViewportSpatialInteractionRecord(target: .patternArrayCurvePathPoint(.init(
        sourceID: PatternArraySourceID(),
        pointIndex: 1,
        title: "Path",
        pathPoints: patternPathPoints,
        activePoint: patternPathPoints[1],
        state: .normal
    )))
}

private func bridgeHandle() -> BridgeCurveEndpointHandle {
    BridgeCurveEndpointHandle(
        sourceID: .init(),
        featureID: .init(),
        bridgeEntityID: .init(),
        role: .first,
        endpoint: .init(reference: .lineEnd(.init())),
        point: .init(x: 1, y: 2),
        outgoingTangent: .init(x: 1, y: 1),
        referenceDescription: "Test",
        pointReference: nil
    )
}

private func bridgeRecord() throws -> ViewportSpatialInteractionRecord {
    try ViewportSpatialInteractionRecord(target: .bridgeCurveEndpoint(
        handle: bridgeHandle(), modelTransform: bridgePlacement
    ))
}

private func sample(from start: Point3D, by delta: Vector3D) -> ViewportNativeWorldPointInput.Sample {
    .init(
        start: start,
        current: Point3D(x: start.x + delta.x, y: start.y + delta.y, z: start.z + delta.z)
    )
}

private let worldPointRuler = RulerConfiguration.standard(for: .millimeter)

@Test func worldPointOwnerClaimsExactlyItsThreePreparedRoutes() throws {
    #expect(ViewportNativeWorldPointInput.claims(try constructionPlaneRecord(handle: .origin).target))
    #expect(ViewportNativeWorldPointInput.claims(try patternRecord().target))
    #expect(ViewportNativeWorldPointInput.claims(try bridgeRecord().target))
    #expect(ViewportNativeWorldPointInput.claims(.patternArrayLinearAxis(.init(
        sourceID: PatternArraySourceID(), axisSlot: .first, title: "Axis",
        basePoint: .origin, direction: Vector3D(x: 1, y: 0, z: 0),
        distanceMeters: 1, displayDistanceMeters: nil, distanceMode: .spacing,
        state: .normal
    ))) == false)
}

@Test func worldPointOwnerAnchorsTheConstructionPlaneQueryAtTheDraggedHandle() throws {
    let originInput = try #require(
        try ViewportNativeWorldPointInput(record: try constructionPlaneRecord(handle: .origin))
    )
    #expect(try originInput.query(displayedCanvas: worldPointCanvas)
        == .viewPlane(anchor: Point3D(x: 0.2, y: -0.1, z: 0.4)))

    let normalInput = try #require(
        try ViewportNativeWorldPointInput(record: try constructionPlaneRecord(handle: .normal))
    )
    #expect(try normalInput.query(displayedCanvas: worldPointCanvas)
        == .viewPlane(anchor: Point3D(x: 0.2, y: -0.1, z: 0.65)))
}

@Test func worldPointOwnerPlacesThePatternPlaneThroughTheDraggedPathPoint() throws {
    let input = try #require(try ViewportNativeWorldPointInput(record: try patternRecord()))
    #expect(try input.query(displayedCanvas: worldPointCanvas)
        == .worldPlane(origin: patternPathPoints[1], normal: Vector3D(x: 0, y: 0, z: 1)))
}

@Test func worldPointOwnerPlacesTheBridgePlaneThroughThePlacedEndpoint() throws {
    let input = try #require(try ViewportNativeWorldPointInput(record: try bridgeRecord()))
    // The authored 2D point (1, 2) becomes (1, 0, 2) in the sketch frame and
    // the placement carries it to (4, 0, 22). A plane through the world origin
    // would answer a different depth under perspective.
    #expect(try input.query(displayedCanvas: worldPointCanvas)
        == .worldPlane(origin: Point3D(x: 4, y: 0, z: 22), normal: Vector3D(x: 0, y: 0, z: 1)))
}

@Test func worldPointOwnerMovesThePatternPointOnEveryWorldAxisThePlaneSpans() throws {
    let input = try #require(try ViewportNativeWorldPointInput(record: try patternRecord()))
    let value = try input.value(
        for: sample(from: patternPathPoints[1], by: Vector3D(x: 0.01, y: 0.02, z: 0)),
        document: .empty(), ruler: worldPointRuler, snapOptions: nil
    )
    guard case .patternArrayCurvePathPoint(let point) = value else {
        Issue.record("The pattern route answered another route's value.")
        return
    }
    #expect(abs(point.x - 0.51) < 1e-12)
    #expect(abs(point.y - 0.27) < 1e-12)
    #expect(abs(point.z + 0.3) < 1e-12)
}

@Test func worldPointOwnerMovesTheConstructionPlaneOriginAndKeepsItsNormal() throws {
    let record = try constructionPlaneRecord(handle: .origin)
    let input = try #require(try ViewportNativeWorldPointInput(record: record))
    let value = try input.value(
        for: sample(from: Point3D(x: 0.2, y: -0.1, z: 0.4),
                    by: Vector3D(x: 0.03, y: 0.05, z: 0)),
        document: .empty(), ruler: worldPointRuler, snapOptions: nil
    )
    guard case .constructionPlane(let origin, let normal) = value else {
        Issue.record("The construction-plane route answered another route's value.")
        return
    }
    #expect(abs(origin.x - 0.23) < 1e-12)
    #expect(abs(origin.y + 0.05) < 1e-12)
    #expect(abs(origin.z - 0.4) < 1e-12)
    #expect(normal == Vector3D(x: 0, y: 0, z: 1))
}

@Test func worldPointOwnerRebuildsTheDraggedNormalFromItsRetainedOrigin() throws {
    let record = try constructionPlaneRecord(handle: .normal)
    let input = try #require(try ViewportNativeWorldPointInput(record: record))
    let delta = Vector3D(x: 0.03, y: 0.05, z: -0.02)
    let value = try input.value(
        for: sample(from: Point3D(x: 0.2, y: -0.1, z: 0.65), by: delta),
        document: .empty(), ruler: worldPointRuler, snapOptions: nil
    )
    guard case .constructionPlane(let origin, let normal) = value else {
        Issue.record("The construction-plane route answered another route's value.")
        return
    }
    // The identity the route owns: the dragged normal is the moved normal end
    // measured from the retained origin, never a re-derived screen direction.
    #expect(origin == Point3D(x: 0.2, y: -0.1, z: 0.4))
    #expect(abs(normal.x - 0.03) < 1e-12)
    #expect(abs(normal.y - 0.05) < 1e-12)
    #expect(abs(normal.z - 0.23) < 1e-12)
}

@Test func worldPointOwnerRefusesANormalHandleCollapsedOntoItsOrigin() throws {
    let input = try #require(
        try ViewportNativeWorldPointInput(record: try constructionPlaneRecord(handle: .normal))
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try input.value(
            for: sample(from: Point3D(x: 0.2, y: -0.1, z: 0.65),
                        by: Vector3D(x: 0, y: 0, z: -0.25)),
            document: .empty(), ruler: worldPointRuler, snapOptions: nil
        )
    }
}

@Test func worldPointOwnerRefusesANonfiniteFrameAnswer() throws {
    let input = try #require(try ViewportNativeWorldPointInput(record: try patternRecord()))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try input.value(
            for: .init(start: patternPathPoints[1],
                       current: Point3D(x: .nan, y: 0, z: 0)),
            document: .empty(), ruler: worldPointRuler, snapOptions: nil
        )
    }
}

@Test func worldPointOwnerWritesNoUndoStepForAReleaseThatMovedNothing() throws {
    let patternInput = try #require(try ViewportNativeWorldPointInput(record: try patternRecord()))
    #expect(try patternInput.commit(
        value: .patternArrayCurvePathPoint(patternPathPoints[1]), document: .empty()
    ) == nil)

    let originInput = try #require(
        try ViewportNativeWorldPointInput(record: try constructionPlaneRecord(handle: .origin))
    )
    #expect(try originInput.commit(
        value: .constructionPlane(origin: Point3D(x: 0.2, y: -0.1, z: 0.4),
                                  normal: Vector3D(x: 0, y: 0, z: 1)),
        document: .empty()
    ) == nil)
}

@Test func worldPointOwnerCommitsTheMovedPatternPoint() throws {
    let patternInput = try #require(try ViewportNativeWorldPointInput(record: try patternRecord()))
    let moved = Point3D(x: 0.51, y: 0.27, z: -0.3)
    let commit = try #require(
        try patternInput.commit(value: .patternArrayCurvePathPoint(moved), document: .empty())
    )
    guard case .patternArrayCurvePathPoint(let target) = commit else {
        Issue.record("The pattern route committed another route's target.")
        return
    }
    #expect(target.pointIndex == 1)
    #expect(target.point == moved)
}

@Test func worldPointOwnerRefusesToCommitAnUnresolvableBridgeBaseline() throws {
    // The legacy path read the baseline parameter with `if let` and committed
    // when it was missing. The owner refuses instead, because a commit without
    // a baseline cannot tell a move from a failed lookup.
    let input = try #require(try ViewportNativeWorldPointInput(record: try bridgeRecord()))
    #expect(throws: (any Error).self) {
        try input.commit(
            value: .bridgeCurveEndpoint(endpoint: bridgeHandle().endpoint, parameter: 0.5),
            document: .empty()
        )
    }
}

@Test func worldPointOwnerRefusesAValueThatAnswersAnotherHandle() throws {
    let input = try #require(try ViewportNativeWorldPointInput(record: try patternRecord()))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try input.commit(
            value: .constructionPlane(origin: .origin, normal: Vector3D(x: 0, y: 0, z: 1)),
            document: .empty()
        )
    }
}
