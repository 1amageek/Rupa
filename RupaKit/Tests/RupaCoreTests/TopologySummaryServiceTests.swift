import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Test func topologySummaryServiceReportsPersistentGeneratedReferences() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let result = try TopologySummaryService().summarize(
        document: session.document,
        displayUnit: session.workspaceState.displayUnit
    )

    #expect(result.counts.bodyCount == 1)
    #expect(result.counts.faceCount == 6)
    #expect(result.counts.edgeCount == 12)
    #expect(result.counts.vertexCount == 8)
    #expect(result.entries.filter { $0.kind == .body }.count == 1)
    #expect(result.entries.filter { $0.kind == .face }.count == 6)
    #expect(result.entries.filter { $0.kind == .edge }.count == 12)
    #expect(result.entries.filter { $0.kind == .vertex }.count == 8)
    for entry in result.entries {
        try entry.stableReference.validate()
    }
    #expect(Set(result.entries.map(\.stableReference)).count == result.entries.count)
    #expect(result.entries.allSatisfy { $0.referenceID.isEmpty == false })
    #expect(result.entries.allSatisfy { $0.sourceFeatureID != nil })
    #expect(result.entries.allSatisfy { $0.sceneNodeID != nil })
    #expect(result.entries.filter { $0.kind != .body }.allSatisfy { $0.selectionComponentID != nil })
    #expect(result.entries.contains {
        $0.kind == .edge
            && $0.curveKind == "line"
            && $0.curveOrigin != nil
            && $0.curveDirection != nil
            && $0.edgeParameterRange != nil
            && $0.start != nil
            && $0.end != nil
    })
    #expect(result.entries.contains {
        $0.kind == .face
            && $0.surfaceKind == "plane"
            && $0.surfaceOrigin != nil
            && $0.surfaceNormal != nil
            && $0.edgeCount == 4
            && $0.center != nil
            && $0.normal != nil
    })
    let edgeEntry = try #require(result.entries.first { $0.kind == .edge })
    let edgeTarget = try #require(edgeEntry.selectionTarget())
    guard case .edge(let componentID) = edgeTarget.component else {
        Issue.record("Topology edge summary must create an edge selection target.")
        return
    }
    #expect(
        try componentID.stableTopologyReference(operationName: "Topology summary test")
            == edgeEntry.stableReference
    )
    let faceEntry = try #require(result.entries.first { $0.kind == .face })
    let faceTarget = try #require(faceEntry.selectionTarget())
    guard case .face(let faceComponentID) = faceTarget.component else {
        Issue.record("Topology face summary must create a face selection target.")
        return
    }
    #expect(
        try faceComponentID.stableTopologyReference(operationName: "Topology summary test")
            == faceEntry.stableReference
    )
    let vertexEntry = try #require(result.entries.first { $0.kind == .vertex })
    let vertexTarget = try #require(vertexEntry.selectionTarget())
    guard case .vertex(let vertexComponentID) = vertexTarget.component else {
        Issue.record("Topology vertex summary must create a vertex selection target.")
        return
    }
    #expect(
        try vertexComponentID.stableTopologyReference(operationName: "Topology summary test")
            == vertexEntry.stableReference
    )
}

@MainActor
@Test func topologySummaryServiceReportsExactLineLoopFaceAreasAndEdgeLengths() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Metric Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(3.0, .meter),
            depth: .length(4.0, .meter),
            direction: .normal
        )
    )

    let result = try TopologySummaryService().summarize(
        document: session.document,
        displayUnit: session.workspaceState.displayUnit
    )
    let faceAreas = result.entries
        .filter { $0.kind == .face }
        .compactMap(\.areaSquareMeters)
        .sorted()
    let edgeLengths = result.entries
        .filter { $0.kind == .edge }
        .compactMap(\.lengthMeters)
        .sorted()

    #expect(faceAreas.count == 6)
    #expect(edgeLengths.count == 12)
    #expect(metricValuesApproximatelyEqual(faceAreas, [6.0, 6.0, 8.0, 8.0, 12.0, 12.0]))
    #expect(metricValuesApproximatelyEqual(edgeLengths, [2.0, 2.0, 2.0, 2.0, 3.0, 3.0, 3.0, 3.0, 4.0, 4.0, 4.0, 4.0]))
}

@MainActor
@Test func topologySummaryServiceReportsBSplineEdgeLengthsFromSmoothLoft() throws {
    let document = try topologySummarySmoothLoftDocument()

    let result = try TopologySnapshotService().snapshot(document: document)
    let bSplineEdges = result.entries.filter {
        $0.kind == .edge
            && $0.curveKind == "bSpline"
    }

    #expect(bSplineEdges.count == 8)
    #expect(bSplineEdges.allSatisfy {
        $0.curveDegree == 3
            && $0.curveControlPointCount == 4
            && $0.edgeParameterRange != nil
            && ($0.lengthMeters ?? 0.0) > 0.0
    })
    let curvedEdge = try #require(bSplineEdges.first { entry in
        guard let length = entry.lengthMeters,
              let start = entry.start,
              let end = entry.end else {
            return false
        }
        let chord = topologySummaryDistance(from: start, to: end)
        return length > chord + ModelingTolerance.standard.distance
    })
    #expect(curvedEdge.selectionTarget() != nil)
}

@MainActor
@Test func topologySummaryServiceReportsEmptySketchOnlyDocumentWithoutEvaluationFailure() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultCircleSketch())

    let result = try TopologySummaryService().summarize(
        document: session.document,
        displayUnit: session.workspaceState.displayUnit
    )

    #expect(result.counts.bodyCount == 0)
    #expect(result.counts.faceCount == 0)
    #expect(result.counts.edgeCount == 0)
    #expect(result.counts.vertexCount == 0)
    #expect(result.entries.isEmpty)
    #expect(result.diagnostics.first?.message.contains("No generated topology") == true)
}

@MainActor
@Test func topologySummaryServiceReportsCylindricalSurfacesAndCircularEdges() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())

    let result = try TopologySnapshotService().snapshot(document: session.document)

    #expect(result.counts.bodyCount == 1)
    #expect(result.counts.faceCount == 6)
    #expect(result.counts.edgeCount == 12)
    #expect(result.counts.vertexCount == 8)
    let cylinderFaces = result.entries.filter { $0.kind == .face && $0.surfaceKind == "cylinder" }
    let circularEdges = result.entries.filter { $0.kind == .edge && $0.curveKind == "circle" }
    #expect(cylinderFaces.count == 4)
    #expect(circularEdges.count == 8)
    #expect(cylinderFaces.allSatisfy {
        $0.center != nil && $0.normal != nil && $0.selectionComponentID != nil
    })
    #expect(cylinderFaces.allSatisfy(hasExpectedCylinderDefinition))
    #expect(circularEdges.allSatisfy(hasExpectedCircularEdgeDefinition))
}

@MainActor
@Test func topologySummaryServiceReportsSemanticSweepSubshapeRoles() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Semantic Sweep Profile",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(-2.0, .millimeter),
                y: .length(59.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(61.0, .millimeter)
            )
        )
    )
    let profileID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createArcSketch(
            name: "Semantic Sweep Path",
            plane: .yz,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(60.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    let pathID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createSweep(
            name: "Semantic Curved Sweep",
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [],
            targets: [],
            options: SweepOptions()
        )
    )

    let result = try TopologySnapshotService().snapshot(document: session.document)
    let ringVertex = try #require(result.entries.first {
        $0.kind == .vertex
            && $0.generatedRole == "vertex"
            && $0.subshapeRole == "ringVertex:frame:0:profile:0"
    })
    let railEdge = try #require(result.entries.first {
        $0.kind == .edge
            && $0.generatedRole == "edge"
            && $0.subshapeRole == "railEdge:span:0:profile:0"
    })
    let sideTriangle = try #require(result.entries.first {
        $0.kind == .face
            && $0.generatedRole == "sideFace"
            && $0.subshapeRole == "sideTriangle:span:0:profile:0:triangle:0"
    })

    #expect(ringVertex.selectionTarget() != nil)
    #expect(railEdge.selectionTarget() != nil)
    #expect(sideTriangle.selectionTarget() != nil)
    #expect(railEdge.stableReference.subshapeID.role.contains("railEdge:span:0:profile:0"))
    #expect(sideTriangle.stableReference.subshapeID.role.contains("sideTriangle:span:0:profile:0:triangle:0"))
}

@MainActor
@Test func topologySummaryServiceReportsPolySplineBSplineSurface() async throws {
    let session = EditorSession()
    let result = try #require(session.createPolySplineSurface(
        name: "Quad PolySpline",
        sourceMesh: topologySummaryPolySplineQuadMesh()
    ))

    #expect(result.commandName == "createPolySplineSurface")
    #expect(result.didMutate)
    #expect(session.evaluationStatus == .valid)

    let summary = try TopologySnapshotService().snapshot(document: session.document)

    #expect(summary.counts.bodyCount == 1)
    #expect(summary.counts.faceCount == 1)
    #expect(summary.counts.edgeCount == 4)
    #expect(summary.counts.vertexCount == 4)
    let face = try #require(summary.entries.first {
        $0.kind == .face
            && $0.surfaceKind == "bSpline"
            && $0.generatedRole == "polySpline"
            && $0.subshapeRole == "patch:0:face"
    })
    #expect(face.surfaceUDegree == 3)
    #expect(face.surfaceVDegree == 3)
    #expect(face.surfaceUControlPointCount == 4)
    #expect(face.surfaceVControlPointCount == 4)
    #expect(face.selectionTarget() != nil)
    #expect(face.center != nil)
    #expect(face.normal != nil)
    #expect(summary.entries.contains {
        $0.kind == .edge
            && $0.generatedRole == "polySpline"
            && $0.subshapeRole == "patch:0:edge:uMax"
            && $0.selectionTarget() != nil
    })
    #expect(summary.entries.contains {
        $0.kind == .vertex
            && $0.generatedRole == "polySpline"
            && $0.subshapeRole == "patch:0:vertex:uMax:vMax"
            && $0.selectionTarget() != nil
    })
}

@MainActor
@Test func topologySummaryServiceReportsSemanticBooleanResultSubshapeRoles() async throws {
    var document = DesignDocument.empty()
    let targetProfileID = try document.createRectangleSketch(
        name: "Boolean Target Profile",
        plane: .xy,
        width: .length(6.0, .millimeter),
        height: .length(3.0, .millimeter)
    )
    let targetBodyID = try document.extrudeProfile(
        name: "Boolean Target",
        profile: ProfileReference(featureID: targetProfileID),
        distance: .length(10.0, .millimeter),
        direction: .normal
    )
    let toolProfileID = try document.createRectangleSketch(
        name: "Boolean Tool Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Boolean Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    _ = try document.createSweep(
        name: "Boolean Result Sweep",
        sections: [.profile(ProfileReference(featureID: toolProfileID))],
        path: SweepPathReference(featureID: pathID),
        targets: [SweepTargetReference(featureID: targetBodyID)],
        options: SweepOptions(booleanOperation: .union)
    )

    let result = try TopologySnapshotService().snapshot(document: document)
    let boxFace = try #require(result.entries.first {
        $0.kind == .face
            && $0.generatedRole == "sideFace"
            && $0.subshapeRole == "box:0:face:maxX"
    })
    let boxEdge = try #require(result.entries.first {
        $0.kind == .edge
            && $0.generatedRole == "edge"
            && $0.subshapeRole == "box:0:zEdge:x:maxX:y:maxY"
    })
    let boxCorner = try #require(result.entries.first {
        $0.kind == .vertex
            && $0.generatedRole == "vertex"
            && $0.subshapeRole == "box:0:corner:maxX:maxY:maxZ"
    })

    #expect(boxFace.selectionTarget() != nil)
    #expect(boxEdge.selectionTarget() != nil)
    #expect(boxCorner.selectionTarget() != nil)
    #expect(boxFace.stableReference.subshapeID.role.contains("box:0:face:maxX"))
    #expect(boxEdge.stableReference.subshapeID.role.contains("box:0:zEdge:x:maxX:y:maxY"))
}

@MainActor
@Test func topologySummaryServiceReportsSemanticCellUnionBooleanSubshapeRoles() async throws {
    var document = DesignDocument.empty()
    let targetProfileID = try document.createRectangleSketchFromCorners(
        name: "Cell Union Boolean Target Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(-20.0, .millimeter),
            y: .length(-20.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(20.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let targetBodyID = try document.extrudeProfile(
        name: "Cell Union Boolean Target",
        profile: ProfileReference(featureID: targetProfileID),
        distance: .length(10.0, .millimeter),
        direction: .normal
    )
    let toolProfileID = try document.createRectangleSketchFromCorners(
        name: "Cell Union Boolean Tool Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(-5.0, .millimeter),
            y: .length(-5.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(25.0, .millimeter),
            y: .length(25.0, .millimeter)
        )
    )
    let pathID = try document.createLineSketch(
        name: "Cell Union Boolean Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    _ = try document.createSweep(
        name: "Cell Union Boolean Result Sweep",
        sections: [.profile(ProfileReference(featureID: toolProfileID))],
        path: SweepPathReference(featureID: pathID),
        targets: [SweepTargetReference(featureID: targetBodyID)],
        options: SweepOptions(booleanOperation: .difference)
    )

    let result = try TopologySnapshotService().snapshot(document: document)
    let cellUnionFace = try #require(result.entries.first {
        $0.kind == .face
            && $0.generatedRole == "sideFace"
            && $0.subshapeRole == "cellUnion:component:0:face:maxX:x:maxX:y:minY-y1:z:minZ-maxZ"
    })
    let cellUnionEdge = try #require(result.entries.first {
        $0.kind == .edge
            && $0.generatedRole == "edge"
            && $0.subshapeRole == "cellUnion:component:0:zEdge:x:x1:y:y1:z:minZ-maxZ"
    })
    let cellUnionVertex = try #require(result.entries.first {
        $0.kind == .vertex
            && $0.generatedRole == "vertex"
            && $0.subshapeRole == "cellUnion:component:0:vertex:x:x1:y:y1:z:maxZ"
    })

    #expect(cellUnionFace.selectionTarget() != nil)
    #expect(cellUnionEdge.selectionTarget() != nil)
    #expect(cellUnionVertex.selectionTarget() != nil)
    #expect(cellUnionFace.stableReference.subshapeID.role.contains("cellUnion:component:0:face:maxX"))
    #expect(cellUnionEdge.stableReference.subshapeID.role.contains("cellUnion:component:0:zEdge"))
}

private func hasExpectedCylinderDefinition(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard let radius = entry.surfaceRadius,
          let origin = entry.surfaceOrigin,
          let axis = entry.surfaceAxis else {
        return false
    }
    return abs(radius - 0.012) < 0.000_000_001
        && abs(origin.x) < 0.000_000_001
        && abs(origin.y) < 0.000_000_001
        && abs(axis.x) < 0.000_000_001
        && abs(axis.y) < 0.000_000_001
        && abs(abs(axis.z) - 1.0) < 0.000_000_001
}

private func hasExpectedCircularEdgeDefinition(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard let radius = entry.curveRadius,
          let center = entry.curveCenter,
          let normal = entry.curveNormal,
          let xAxis = entry.curveParameterXAxis,
          let yAxis = entry.curveParameterYAxis,
          let parameterRange = entry.edgeParameterRange else {
        return false
    }
    let span = abs(parameterRange.end - parameterRange.start)
    let xLength = sqrt(xAxis.x * xAxis.x + xAxis.y * xAxis.y + xAxis.z * xAxis.z)
    let yLength = sqrt(yAxis.x * yAxis.x + yAxis.y * yAxis.y + yAxis.z * yAxis.z)
    let xDotY = xAxis.x * yAxis.x + xAxis.y * yAxis.y + xAxis.z * yAxis.z
    let xDotNormal = xAxis.x * normal.x + xAxis.y * normal.y + xAxis.z * normal.z
    let yDotNormal = yAxis.x * normal.x + yAxis.y * normal.y + yAxis.z * normal.z
    return abs(radius - 0.012) < 0.000_000_001
        && abs(center.x) < 0.000_000_001
        && abs(center.y) < 0.000_000_001
        && abs(abs(normal.z) - 1.0) < 0.000_000_001
        && abs(xLength - 1.0) < 0.000_000_001
        && abs(yLength - 1.0) < 0.000_000_001
        && abs(xDotY) < 0.000_000_001
        && abs(xDotNormal) < 0.000_000_001
        && abs(yDotNormal) < 0.000_000_001
        && parameterRange.start.isFinite
        && parameterRange.end.isFinite
        && span > 0.0
        && span < Double.pi * 2.0
}

private func metricValuesApproximatelyEqual(
    _ actual: [Double],
    _ expected: [Double],
    tolerance: Double = 1.0e-9
) -> Bool {
    guard actual.count == expected.count else {
        return false
    }
    return zip(actual, expected).allSatisfy { left, right in
        abs(left - right) <= tolerance
    }
}

private func topologySummarySmoothLoftDocument() throws -> DesignDocument {
    var document = DesignDocument.empty()
    let firstProfileID = try topologySummaryCreateLoftProfile(
        in: &document,
        name: "Length Loft Bottom",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 0.0
    )
    let middleProfileID = try topologySummaryCreateLoftProfile(
        in: &document,
        name: "Length Loft Middle",
        width: 5.0,
        height: 2.5,
        x: 3.0,
        z: 5.0
    )
    let lastProfileID = try topologySummaryCreateLoftProfile(
        in: &document,
        name: "Length Loft Top",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 10.0
    )
    _ = try document.createLoft(
        name: "Length Smooth Loft",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: middleProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: lastProfileID)),
        ],
        options: LoftOptions(resultKind: .solid, surfaceMode: .smooth)
    )
    return document
}

private func topologySummaryCreateLoftProfile(
    in document: inout DesignDocument,
    name: String,
    width: Double,
    height: Double,
    x: Double,
    z: Double
) throws -> FeatureID {
    try document.createRectangleSketch(
        name: name,
        plane: topologySummaryLoftPlane(x: x, z: z),
        width: .length(width, .millimeter),
        height: .length(height, .millimeter)
    )
}

private func topologySummaryLoftPlane(x: Double, z: Double) -> SketchPlane {
    if x == 0.0 && z == 0.0 {
        return .xy
    }
    return .plane(Plane3D(
        origin: Point3D(x: x / 1000.0, y: 0.0, z: z / 1000.0),
        normal: .unitZ
    ))
}

private func topologySummaryDistance(
    from first: TopologySummaryResult.Entry.Point,
    to second: TopologySummaryResult.Entry.Point
) -> Double {
    let x = second.x - first.x
    let y = second.y - first.y
    let z = second.z - first.z
    return (x * x + y * y + z * z).squareRoot()
}

private func topologySummaryPolySplineQuadMesh() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.02, z: 0.004),
            Point3D(x: 0.0, y: 0.02, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}
