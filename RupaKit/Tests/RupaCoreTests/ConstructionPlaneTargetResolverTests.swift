import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Test func editorSessionCreatesConstructionPlaneAlignedToGeneratedFaceTarget() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let topology = try TopologySummaryService().summarize(document: session.document)
    let faceEntry = try #require(topology.entries.first {
        $0.kind == .face && $0.center != nil && $0.normal != nil && $0.selectionTarget() != nil
    })
    let faceTarget = try #require(faceEntry.selectionTarget())
    let expectedCenter = try #require(faceEntry.center)
    let expectedNormal = try #require(faceEntry.normal)

    let result = try session.execute(
        .createConstructionPlaneFromTarget(
            name: "Face Plane",
            target: faceTarget,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createConstructionPlaneFromTarget")
    #expect(result.didMutate)
    #expect(source.name == "Face Plane")
    assertPlane(
        source.plane,
        hasOrigin: expectedCenter,
        normal: expectedNormal
    )
}

@MainActor
@Test func editorSessionCreatesConstructionPlaneAlignedToSourceRegionTarget() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "YZ Region",
            plane: .yz,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        )
    )

    let sketchSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let region = try #require(sketchSummary.regions.first)
    let regionTarget = try #require(region.selectionTarget())

    let result = try session.execute(
        .createConstructionPlaneFromTarget(
            name: "Region Plane",
            target: regionTarget,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createConstructionPlaneFromTarget")
    #expect(result.didMutate)
    #expect(source.name == "Region Plane")
    assertPlane(
        source.plane,
        hasOrigin: TopologySummaryResult.Entry.Point(x: 0.0, y: 0.0, z: 0.0),
        normal: TopologySummaryResult.Entry.Point(x: 1.0, y: 0.0, z: 0.0)
    )
}

@MainActor
@Test func editorSessionCreatesConstructionPlaneAlignedToSavedConstructionPlaneTarget() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createConstructionPlane(
            name: "Saved Source Plane",
            plane: .yz,
            activates: true
        )
    )
    let summary = ConstructionPlaneSummaryService().summarize(document: session.document)
    let sourceEntry = try #require(summary.planes.first { $0.name == "Saved Source Plane" })
    let sourceTarget = try #require(sourceEntry.selectionTarget())

    let result = try session.execute(
        .createConstructionPlaneFromTarget(
            name: "Copied Saved Plane",
            target: sourceTarget,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createConstructionPlaneFromTarget")
    #expect(result.didMutate)
    #expect(source.name == "Copied Saved Plane")
    assertPlane(
        source.plane,
        hasOrigin: TopologySummaryResult.Entry.Point(x: 0.0, y: 0.0, z: 0.0),
        normal: TopologySummaryResult.Entry.Point(x: 1.0, y: 0.0, z: 0.0)
    )
}

@MainActor
@Test func editorSessionCreatesMidplaneFromSavedConstructionPlaneTargets() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createConstructionPlane(
            name: "First Saved Plane",
            plane: .yz,
            activates: true
        )
    )
    _ = try session.execute(
        .createConstructionPlane(
            name: "Second Saved Plane",
            plane: .plane(Plane3D(
                origin: Point3D(x: 0.020, y: 0.0, z: 0.0),
                normal: .unitX
            )),
            activates: false
        )
    )
    let summary = ConstructionPlaneSummaryService().summarize(document: session.document)
    let firstTarget = try #require(summary.planes.first { $0.name == "First Saved Plane" }?.selectionTarget())
    let secondTarget = try #require(summary.planes.first { $0.name == "Second Saved Plane" }?.selectionTarget())

    let result = try session.execute(
        .createConstructionPlaneFromTargets(
            name: "Saved Midplane",
            targets: [firstTarget, secondTarget],
            viewNormal: nil,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: TopologySummaryResult.Entry.Point(x: 0.010, y: 0.0, z: 0.0),
        normal: TopologySummaryResult.Entry.Point(x: 1.0, y: 0.0, z: 0.0)
    )
}

@MainActor
@Test func editorSessionCreatesPerpendicularConstructionPlaneFromFaceAndEdgeTargets() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let pair = try perpendicularFaceEdgePair(in: topology)

    let result = try session.execute(
        .createConstructionPlaneFromTargets(
            name: "Face Edge Plane",
            targets: [pair.faceTarget, pair.edgeTarget],
            viewNormal: nil,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: point(pair.edgeCenter),
        normal: point(pair.planeNormal)
    )
}

@MainActor
@Test func editorSessionCreatesMidplaneFromParallelGeneratedFaceTargets() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let pair = try parallelFacePair(in: topology)

    let result = try session.execute(
        .createConstructionPlaneFromTargets(
            name: "Generated Midplane",
            targets: [pair.firstTarget, pair.secondTarget],
            viewNormal: nil,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: point(pair.origin),
        normal: point(pair.normal)
    )
}

@MainActor
@Test func editorSessionRejectsCoplanarRegionsForMidplaneConstruction() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "First Region",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .meter),
                y: .length(0.0, .meter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(0.010, .meter),
                y: .length(0.010, .meter)
            )
        )
    )
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Second Region",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.020, .meter),
                y: .length(0.0, .meter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(0.030, .meter),
                y: .length(0.010, .meter)
            )
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let targets = try summary.regions.map { region in
        try #require(region.selectionTarget())
    }
    #expect(targets.count == 2)

    do {
        _ = try session.execute(
            .createConstructionPlaneFromTargets(
                name: "Invalid Coplanar Midplane",
                targets: targets,
                viewNormal: nil,
                activates: true
            )
        )
        Issue.record("Coplanar regions must not produce an opposing midplane.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("opposing"))
    } catch {
        Issue.record("Expected EditorError for coplanar midplane targets.")
    }
}

@MainActor
@Test func editorSessionCreatesTwoPointConstructionPlaneFromGeneratedVerticesAndViewNormal() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let pair = try twoPointVertexPair(in: topology, viewNormal: .unitZ)

    let result = try session.execute(
        .createConstructionPlaneFromTargets(
            name: "Two Point Plane",
            targets: pair.targets,
            viewNormal: .unitZ,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    let expectedNormal = try projectedNormal(viewNormal: .unitZ, along: pair.points[1] - pair.points[0])
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: point(average(pair.points)),
        normal: point(expectedNormal)
    )
    assertPoint(pair.points[0], liesOn: source.plane)
    assertPoint(pair.points[1], liesOn: source.plane)
}

@MainActor
@Test func editorSessionRejectsTwoPointConstructionPlaneWithoutViewNormal() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let pair = try twoPointVertexPair(in: topology, viewNormal: .unitZ)

    do {
        _ = try session.execute(
            .createConstructionPlaneFromTargets(
                name: "Invalid Two Point Plane",
                targets: pair.targets,
                viewNormal: nil,
                activates: true
            )
        )
        Issue.record("Two-point construction planes must require an explicit view normal.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("view normal"))
    } catch {
        Issue.record("Expected EditorError for missing two-point view normal.")
    }
}

@MainActor
@Test func editorSessionCreatesTwoPointConstructionPlaneFromSourcePointTargetsAndViewNormal() async throws {
    let setup = try sourcePointSession()

    let result = try setup.session.execute(
        .createConstructionPlaneFromTargets(
            name: "Source Point Plane",
            targets: setup.targets,
            viewNormal: .unitZ,
            activates: true
        )
    )

    let source = try #require(setup.session.activeConstructionPlane)
    let expectedNormal = try projectedNormal(viewNormal: .unitZ, along: setup.points[1] - setup.points[0])
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: point(average(setup.points)),
        normal: point(expectedNormal)
    )
    assertPoint(setup.points[0], liesOn: source.plane)
    assertPoint(setup.points[1], liesOn: source.plane)
}

@MainActor
@Test func editorSessionCreatesTwoPointConstructionPlaneFromSketchLineEndpointTargetsAndViewNormal() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Line Endpoint Plane Seeds",
        plane: .xy,
        start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        end: SketchPoint(x: .length(0.010, .meter), y: .length(0.004, .meter))
    )
    let setup = try sketchEntityTargetSetup(
        featureID: featureID,
        entityKind: "line",
        document: document
    )
    let targets = [
        sketchPointHandleTarget(
            sceneNodeID: setup.sceneNodeID,
            featureID: featureID,
            entityID: setup.entityID,
            handle: .lineStart
        ),
        sketchPointHandleTarget(
            sceneNodeID: setup.sceneNodeID,
            featureID: featureID,
            entityID: setup.entityID,
            handle: .lineEnd
        ),
    ]
    let expectedPoints = [
        Point3D(x: 0.0, y: 0.0, z: 0.0),
        Point3D(x: 0.010, y: 0.004, z: 0.0),
    ]
    let session = EditorSession(document: document)

    let result = try session.execute(
        .createConstructionPlaneFromTargets(
            name: "Line Endpoint Plane",
            targets: targets,
            viewNormal: .unitZ,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    let expectedNormal = try projectedNormal(
        viewNormal: .unitZ,
        along: expectedPoints[1] - expectedPoints[0]
    )
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: point(average(expectedPoints)),
        normal: point(expectedNormal)
    )
    for expectedPoint in expectedPoints {
        assertPoint(expectedPoint, liesOn: source.plane)
    }
}

@MainActor
@Test func editorSessionCreatesTwoPointConstructionPlaneFromSketchArcEndpointTargetsAndViewNormal() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createArcSketch(
        name: "Arc Endpoint Plane Seeds",
        plane: .xy,
        center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        radius: .length(0.010, .meter),
        startAngle: .angle(0.0, .radian),
        endAngle: .angle(Double.pi / 2.0, .radian)
    )
    let setup = try sketchEntityTargetSetup(
        featureID: featureID,
        entityKind: "arc",
        document: document
    )
    let targets = [
        sketchPointHandleTarget(
            sceneNodeID: setup.sceneNodeID,
            featureID: featureID,
            entityID: setup.entityID,
            handle: .arcStart
        ),
        sketchPointHandleTarget(
            sceneNodeID: setup.sceneNodeID,
            featureID: featureID,
            entityID: setup.entityID,
            handle: .arcEnd
        ),
    ]
    let expectedPoints = [
        Point3D(x: 0.010, y: 0.0, z: 0.0),
        Point3D(x: 0.0, y: 0.010, z: 0.0),
    ]
    let session = EditorSession(document: document)

    let result = try session.execute(
        .createConstructionPlaneFromTargets(
            name: "Arc Endpoint Plane",
            targets: targets,
            viewNormal: .unitZ,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    let expectedNormal = try projectedNormal(
        viewNormal: .unitZ,
        along: expectedPoints[1] - expectedPoints[0]
    )
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: point(average(expectedPoints)),
        normal: point(expectedNormal)
    )
    for expectedPoint in expectedPoints {
        assertPoint(expectedPoint, liesOn: source.plane)
    }
}

@MainActor
@Test func editorSessionCreatesTwoPointConstructionPlaneFromSketchSplineControlPointTargetsAndViewNormal() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: "Spline Control Plane Seeds",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            SketchPoint(x: .length(0.004, .meter), y: .length(0.006, .meter)),
            SketchPoint(x: .length(0.008, .meter), y: .length(-0.002, .meter)),
            SketchPoint(x: .length(0.012, .meter), y: .length(0.004, .meter)),
        ])
    )
    let setup = try sketchEntityTargetSetup(
        featureID: featureID,
        entityKind: "spline",
        document: document
    )
    let targets = [
        sketchControlPointTarget(
            sceneNodeID: setup.sceneNodeID,
            featureID: featureID,
            entityID: setup.entityID,
            index: 0
        ),
        sketchControlPointTarget(
            sceneNodeID: setup.sceneNodeID,
            featureID: featureID,
            entityID: setup.entityID,
            index: 3
        ),
    ]
    let expectedPoints = [
        Point3D(x: 0.0, y: 0.0, z: 0.0),
        Point3D(x: 0.012, y: 0.004, z: 0.0),
    ]
    let session = EditorSession(document: document)

    let result = try session.execute(
        .createConstructionPlaneFromTargets(
            name: "Spline CV Plane",
            targets: targets,
            viewNormal: .unitZ,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    let expectedNormal = try projectedNormal(
        viewNormal: .unitZ,
        along: expectedPoints[1] - expectedPoints[0]
    )
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: point(average(expectedPoints)),
        normal: point(expectedNormal)
    )
    for expectedPoint in expectedPoints {
        assertPoint(expectedPoint, liesOn: source.plane)
    }
}

@MainActor
@Test func editorSessionCreatesThreePointConstructionPlaneFromGeneratedVertices() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let triplet = try threePointVertexTriplet(in: topology)

    let result = try session.execute(
        .createConstructionPlaneFromTargets(
            name: "Three Point Plane",
            targets: triplet.targets,
            viewNormal: nil,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: point(triplet.points[0]),
        normal: point(triplet.normal)
    )
    for point in triplet.points {
        assertPoint(point, liesOn: source.plane)
    }
}

@MainActor
@Test func editorSessionCreatesViewAlignedConstructionPlaneThroughWorldOrigin() async throws {
    let session = EditorSession()

    let result = try session.execute(
        .createViewAlignedConstructionPlane(
            name: "View Origin Plane",
            origin: .origin,
            viewNormal: Vector3D(x: 0.0, y: 0.0, z: 5.0),
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createViewAlignedConstructionPlane")
    #expect(result.didMutate)
    #expect(source.name == "View Origin Plane")
    assertPlane(
        source.plane,
        hasOrigin: point(Point3D.origin),
        normal: point(Vector3D.unitZ)
    )
}

@MainActor
@Test func editorSessionCreatesViewAlignedConstructionPlaneThroughExplicitOrigin() async throws {
    let session = EditorSession()
    let origin = Point3D(x: 0.01, y: 0.02, z: 0.03)
    let viewNormal = Vector3D(x: 0.0, y: 4.0, z: 0.0)

    let result = try session.execute(
        .createViewAlignedConstructionPlane(
            name: "View Pick Plane",
            origin: origin,
            viewNormal: viewNormal,
            activates: true
        )
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createViewAlignedConstructionPlane")
    #expect(result.didMutate)
    assertPlane(
        source.plane,
        hasOrigin: point(origin),
        normal: point(Vector3D.unitY)
    )
}

@MainActor
@Test func editorSessionRejectsViewAlignedConstructionPlaneWithInvalidNormal() async throws {
    let session = EditorSession()

    do {
        _ = try session.execute(
            .createViewAlignedConstructionPlane(
                name: "Invalid View Plane",
                origin: .origin,
                viewNormal: .zero,
                activates: true
            )
        )
        Issue.record("View-aligned construction planes must reject zero view normals.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("view normal"))
    } catch {
        Issue.record("Expected EditorError for invalid view normal.")
    }
}

private func assertPlane(
    _ sketchPlane: SketchPlane,
    hasOrigin expectedOrigin: TopologySummaryResult.Entry.Point,
    normal expectedNormal: TopologySummaryResult.Entry.Point,
    tolerance: Double = 1.0e-9
) {
    guard case .plane(let plane) = sketchPlane else {
        Issue.record("Expected a custom construction plane.")
        return
    }
    #expect(abs(plane.origin.x - expectedOrigin.x) <= tolerance)
    #expect(abs(plane.origin.y - expectedOrigin.y) <= tolerance)
    #expect(abs(plane.origin.z - expectedOrigin.z) <= tolerance)

    let expected = Vector3D(
        x: expectedNormal.x,
        y: expectedNormal.y,
        z: expectedNormal.z
    )
    do {
        let unitExpected = try expected.normalized(tolerance: tolerance)
        #expect(abs(plane.normal.x - unitExpected.x) <= tolerance)
        #expect(abs(plane.normal.y - unitExpected.y) <= tolerance)
        #expect(abs(plane.normal.z - unitExpected.z) <= tolerance)
    } catch {
        Issue.record("Expected normal must be normalizable.")
    }
}

private func assertPoint(
    _ point: Point3D,
    liesOn sketchPlane: SketchPlane,
    tolerance: Double = 1.0e-9
) {
    guard case .plane(let plane) = sketchPlane else {
        Issue.record("Expected a custom construction plane.")
        return
    }
    let delta = point - plane.origin
    #expect(abs(delta.dot(plane.normal)) <= tolerance)
}

private func perpendicularFaceEdgePair(
    in topology: TopologySummaryResult
) throws -> (
    faceTarget: SelectionTarget,
    edgeTarget: SelectionTarget,
    edgeCenter: Point3D,
    planeNormal: Vector3D
) {
    let faces = topology.entries.filter { $0.kind == .face }
    let edges = topology.entries.filter { $0.kind == .edge }
    for face in faces {
        guard let normal = face.normal,
              let faceTarget = face.selectionTarget() else {
            continue
        }
        let faceNormal = try vector(normal).normalized(tolerance: 1.0e-12)
        for edge in edges {
            guard let start = edge.start,
                  let end = edge.end,
                  let edgeTarget = edge.selectionTarget() else {
                continue
            }
            do {
                let startPoint = point3D(start)
                let endPoint = point3D(end)
                let edgeDirection = try (endPoint - startPoint).normalized(tolerance: 1.0e-12)
                let planeNormal = try edgeDirection.cross(faceNormal).normalized(tolerance: 1.0e-12)
                return (
                    faceTarget,
                    edgeTarget,
                    Point3D(
                        x: (startPoint.x + endPoint.x) / 2.0,
                        y: (startPoint.y + endPoint.y) / 2.0,
                        z: (startPoint.z + endPoint.z) / 2.0
                    ),
                    planeNormal
                )
            } catch {
                continue
            }
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Test setup requires a face and nonparallel edge target."
    )
}

private func parallelFacePair(
    in topology: TopologySummaryResult
) throws -> (
    firstTarget: SelectionTarget,
    secondTarget: SelectionTarget,
    origin: Point3D,
    normal: Vector3D
) {
    let faces = topology.entries.filter { $0.kind == .face }
    for firstIndex in faces.indices {
        let first = faces[firstIndex]
        guard let firstCenter = first.center,
              let firstNormalPoint = first.normal,
              let firstTarget = first.selectionTarget() else {
            continue
        }
        let firstNormal = try vector(firstNormalPoint).normalized(tolerance: 1.0e-12)
        for second in faces.dropFirst(firstIndex + 1) {
            guard let secondCenter = second.center,
                  let secondNormalPoint = second.normal,
                  let secondTarget = second.selectionTarget() else {
                continue
            }
            let secondNormal = try vector(secondNormalPoint).normalized(tolerance: 1.0e-12)
            guard abs(abs(firstNormal.dot(secondNormal)) - 1.0) <= 1.0e-8 else {
                continue
            }
            let firstPoint = point3D(firstCenter)
            let secondPoint = point3D(secondCenter)
            let delta = secondPoint - firstPoint
            guard abs(delta.dot(firstNormal)) > 1.0e-9 else {
                continue
            }
            return (
                firstTarget,
                secondTarget,
                Point3D(
                    x: (firstPoint.x + secondPoint.x) / 2.0,
                    y: (firstPoint.y + secondPoint.y) / 2.0,
                    z: (firstPoint.z + secondPoint.z) / 2.0
                ),
                firstNormal
            )
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Test setup requires two parallel face targets."
    )
}

private func twoPointVertexPair(
    in topology: TopologySummaryResult,
    viewNormal: Vector3D
) throws -> (
    targets: [SelectionTarget],
    points: [Point3D]
) {
    let vertices = topology.entries.compactMap(vertexTargetPoint)
    let unitViewNormal = try viewNormal.normalized(tolerance: 1.0e-12)
    for firstIndex in vertices.indices {
        for second in vertices.dropFirst(firstIndex + 1) {
            let first = vertices[firstIndex]
            let direction = second.point - first.point
            do {
                _ = try projectedNormal(viewNormal: unitViewNormal, along: direction)
                return (
                    [first.target, second.target],
                    [first.point, second.point]
                )
            } catch {
                continue
            }
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Test setup requires two generated vertex targets compatible with the view normal."
    )
}

private func threePointVertexTriplet(
    in topology: TopologySummaryResult
) throws -> (
    targets: [SelectionTarget],
    points: [Point3D],
    normal: Vector3D
) {
    let vertices = topology.entries.compactMap(vertexTargetPoint)
    for firstIndex in vertices.indices {
        for secondIndex in vertices.indices where secondIndex != firstIndex {
            for thirdIndex in vertices.indices where thirdIndex != firstIndex && thirdIndex != secondIndex {
                let first = vertices[firstIndex]
                let second = vertices[secondIndex]
                let third = vertices[thirdIndex]
                do {
                    let normal = try (second.point - first.point)
                        .cross(third.point - first.point)
                        .normalized(tolerance: 1.0e-12)
                    return (
                        [first.target, second.target, third.target],
                        [first.point, second.point, third.point],
                        normal
                    )
                } catch {
                    continue
                }
            }
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Test setup requires three non-collinear generated vertex targets."
    )
}

private func sourcePointSession(
) throws -> (
    session: EditorSession,
    targets: [SelectionTarget],
    points: [Point3D]
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Source Point CPlane Seeds",
        plane: .xy,
        start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        end: SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))
    )
    let firstID = SketchEntityID()
    let secondID = SketchEntityID()
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Source point construction-plane test requires a sketch feature."
        )
    }
    sketch.entities = [
        firstID: .point(SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter))),
        secondID: .point(SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()

    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entries = summary.entries.filter { $0.entityKind == "point" }
    #expect(entries.count == 2)
    let targets = try entries.map { entry in
        try #require(entry.selectionTarget())
    }
    let points = try entries.map { entry in
        let center = try #require(entry.center)
        return Point3D(x: center.x, y: center.y, z: 0.0)
    }
    return (EditorSession(document: document), targets, points)
}

private func sketchEntityTargetSetup(
    featureID: FeatureID,
    entityKind: String,
    document: DesignDocument
) throws -> (
    sceneNodeID: SceneNodeID,
    entityID: SketchEntityID
) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first { entry in
        entry.sourceFeatureID == featureID.description && entry.entityKind == entityKind
    })
    let target = try #require(entry.selectionTarget())
    let entityUUID = try #require(UUID(uuidString: entry.entityID))
    return (target.sceneNodeID, SketchEntityID(entityUUID))
}

private func sketchPointHandleTarget(
    sceneNodeID: SceneNodeID,
    featureID: FeatureID,
    entityID: SketchEntityID,
    handle: SketchEntityPointHandle
) -> SelectionTarget {
    SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: entityID,
                handle: handle
            )
        )
    )
}

private func sketchControlPointTarget(
    sceneNodeID: SceneNodeID,
    featureID: FeatureID,
    entityID: SketchEntityID,
    index: Int
) -> SelectionTarget {
    SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchControlPoint(
                featureID: featureID,
                entityID: entityID,
                index: index
            )
        )
    )
}

private func vertexTargetPoint(
    _ entry: TopologySummaryResult.Entry
) -> (target: SelectionTarget, point: Point3D)? {
    guard entry.kind == .vertex,
          let target = entry.selectionTarget(),
          let point = entry.start else {
        return nil
    }
    return (target, point3D(point))
}

private func projectedNormal(
    viewNormal: Vector3D,
    along direction: Vector3D
) throws -> Vector3D {
    let unitDirection = try direction.normalized(tolerance: 1.0e-12)
    let unitViewNormal = try viewNormal.normalized(tolerance: 1.0e-12)
    let projected = unitViewNormal - unitDirection * unitViewNormal.dot(unitDirection)
    return try projected.normalized(tolerance: 1.0e-12)
}

private func average(_ points: [Point3D]) -> Point3D {
    let sum = points.reduce(Vector3D.zero) { partial, point in
        partial + Vector3D(x: point.x, y: point.y, z: point.z)
    }
    let count = Double(points.count)
    return Point3D(
        x: sum.x / count,
        y: sum.y / count,
        z: sum.z / count
    )
}

private func point3D(_ point: TopologySummaryResult.Entry.Point) -> Point3D {
    Point3D(x: point.x, y: point.y, z: point.z)
}

private func vector(_ point: TopologySummaryResult.Entry.Point) -> Vector3D {
    Vector3D(x: point.x, y: point.y, z: point.z)
}

private func point(_ point: Point3D) -> TopologySummaryResult.Entry.Point {
    TopologySummaryResult.Entry.Point(x: point.x, y: point.y, z: point.z)
}

private func point(_ vector: Vector3D) -> TopologySummaryResult.Entry.Point {
    TopologySummaryResult.Entry.Point(x: vector.x, y: vector.y, z: vector.z)
}
