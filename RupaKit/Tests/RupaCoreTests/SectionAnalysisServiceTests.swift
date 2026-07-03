import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func sectionAnalysisClassifiesExtrudedMeshAgainstSketchPlane() throws {
    let document = try sectionAnalysisTestDocument()
    let result = try SectionAnalysisService().analyze(
        document: document,
        query: SectionAnalysisQuery(
            source: .sketchPlane(.yz),
            toleranceMeters: 1.0e-8
        )
    )

    let body = try #require(result.bodies.first)
    let segment = try #require(result.intersectionSegments.first)

    #expect(result.plane.sourceKind == .sketchPlane)
    #expect(result.bodyCount == 1)
    #expect(result.intersectingBodyCount == 1)
    #expect(result.triangleCount == body.triangleCount)
    #expect(result.intersectingTriangleCount > 0)
    #expect(result.intersectionSegmentCount == result.intersectionSegments.count)
    #expect(result.closedIntersectionContourCount >= 1)
    #expect(result.intersectionContours.contains { contour in
        contour.isClosed && abs(contour.signedAreaSquareMeters) > result.toleranceMeters
    })
    #expect(body.classification == .intersects)
    #expect(body.frontVertexCount > 0)
    #expect(body.behindVertexCount > 0)
    #expect(body.intersectingTriangleCount > 0)
    #expect(abs(segment.start.x) <= result.toleranceMeters * 10.0)
    #expect(abs(segment.end.x) <= result.toleranceMeters * 10.0)
}

@Test func sectionAnalysisReadsActiveConstructionPlane() throws {
    var document = try sectionAnalysisTestDocument()
    let planeID = try document.createConstructionPlane(
        name: "Active Section",
        plane: .yz,
        activates: true
    )

    let result = try SectionAnalysisService().analyze(
        document: document,
        query: SectionAnalysisQuery(
            source: .activeConstructionPlane,
            toleranceMeters: 1.0e-8
        )
    )

    #expect(result.plane.sourceKind == .activeConstructionPlane)
    #expect(result.plane.sourceID == planeID.description)
    #expect(result.plane.sourceName == "Active Section")
    #expect(result.intersectingBodyCount == 1)
    #expect(result.intersectionSegments.isEmpty == false)
}

@Test func sectionAnalysisReadsSectionSceneNodeTransform() throws {
    var document = try sectionAnalysisTestDocument()
    let nodeID = try document.createSectionPlane(name: "Mid Height Section")
    try document.setSceneNodeTransform(
        id: nodeID,
        localTransform: Transform3D(
            matrix: try Matrix4x4(values: [
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 1.0, 1.0,
            ])
        )
    )

    let result = try SectionAnalysisService().analyze(
        document: document,
        query: SectionAnalysisQuery(
            source: .sceneNode(nodeID),
            toleranceMeters: 1.0e-8
        )
    )

    #expect(result.plane.sourceKind == .sceneNode)
    #expect(result.plane.sourceID == nodeID.description)
    #expect(result.plane.sourceName == "Mid Height Section")
    #expect(result.plane.origin.z == 1.0)
    #expect(result.plane.normal == .unitZ)
    #expect(result.intersectingBodyCount == 1)
    #expect(result.intersectionSegments.allSatisfy { segment in
        abs(segment.start.z - 1.0) <= result.toleranceMeters * 10.0
            && abs(segment.end.z - 1.0) <= result.toleranceMeters * 10.0
    })
}

@Test func sectionAnalysisAppliesOffsetAndFlipWithoutMutatingSourcePlane() throws {
    let document = try sectionAnalysisTestDocument()
    let baseResult = try SectionAnalysisService().analyze(
        document: document,
        query: SectionAnalysisQuery(
            source: .sketchPlane(.xy),
            offsetMeters: 1.0,
            toleranceMeters: 1.0e-8
        )
    )
    let flippedResult = try SectionAnalysisService().analyze(
        document: document,
        query: SectionAnalysisQuery(
            source: .sketchPlane(.xy),
            offsetMeters: 1.0,
            flipsNormal: true,
            toleranceMeters: 1.0e-8
        )
    )
    let baseBody = try #require(baseResult.bodies.first)
    let flippedBody = try #require(flippedResult.bodies.first)

    #expect(baseResult.plane.origin.z == 1.0)
    #expect(baseResult.plane.normal == .unitZ)
    #expect(flippedResult.plane.origin.z == 1.0)
    #expect(flippedResult.plane.normal == Vector3D(x: 0.0, y: 0.0, z: -1.0))
    #expect(flippedResult.plane.u == baseResult.plane.u)
    #expect(flippedResult.plane.v == baseResult.plane.v)
    #expect(baseBody.frontVertexCount == flippedBody.behindVertexCount)
    #expect(baseBody.behindVertexCount == flippedBody.frontVertexCount)
    #expect(baseResult.intersectionContours.map(\.points) == flippedResult.intersectionContours.map(\.points))
    #expect(baseResult.intersectionContours.map(\.points2D) == flippedResult.intersectionContours.map(\.points2D))
    #expect(baseResult.intersectionContours.map(\.signedAreaSquareMeters) == flippedResult.intersectionContours.map(\.signedAreaSquareMeters))
    #expect(baseResult.intersectionContours.map(\.lengthMeters) == flippedResult.intersectionContours.map(\.lengthMeters))
    #expect(baseResult.intersectionSegments.allSatisfy { segment in
        abs(segment.start.z - 1.0) <= baseResult.toleranceMeters * 10.0
            && abs(segment.end.z - 1.0) <= baseResult.toleranceMeters * 10.0
    })
}

@Test func sectionAnalysisRejectsNonFiniteOffset() throws {
    let document = try sectionAnalysisTestDocument()

    #expect(throws: EditorError.self) {
        _ = try SectionAnalysisService().analyze(
            document: document,
            query: SectionAnalysisQuery(
                source: .sketchPlane(.xy),
                offsetMeters: .infinity
            )
        )
    }
}

@Test func sectionAnalysisBoundsReturnedSegmentsWithoutLosingCounts() throws {
    let document = try sectionAnalysisTestDocument()
    let result = try SectionAnalysisService().analyze(
        document: document,
        query: SectionAnalysisQuery(
            source: .sketchPlane(.yz),
            toleranceMeters: 1.0e-8,
            includesIntersectionSegments: true,
            maximumIntersectionSegments: 1
        )
    )

    #expect(result.truncatedIntersectionSegments)
    #expect(result.intersectionSegments.count == 1)
    #expect(result.intersectionSegmentCount > result.intersectionSegments.count)
    #expect(result.diagnostics.contains { diagnostic in
        diagnostic.severity == .warning
            && diagnostic.message.contains("truncated")
    })
}

@Test func sectionAnalysisCanSkipSegmentPayloadForAgentBudgeting() throws {
    let document = try sectionAnalysisTestDocument()
    let result = try SectionAnalysisService().analyze(
        document: document,
        query: SectionAnalysisQuery(
            source: .sketchPlane(.yz),
            toleranceMeters: 1.0e-8,
            includesIntersectionSegments: false
        )
    )

    #expect(result.intersectingBodyCount == 1)
    #expect(result.intersectingTriangleCount > 0)
    #expect(result.intersectionSegmentCount > 0)
    #expect(result.intersectionSegments.isEmpty)
    #expect(result.intersectionContours.isEmpty)
    #expect(!result.truncatedIntersectionSegments)
}

@Test func sectionAnalysisContourBuilderReconstructsClosedLoopFromSegments() throws {
    let segments = [
        sectionAnalysisSegment(start: Point2D(x: 1.0, y: 0.0), end: Point2D(x: 1.0, y: 1.0)),
        sectionAnalysisSegment(start: Point2D(x: 0.0, y: 1.0), end: Point2D(x: 0.0, y: 0.0)),
        sectionAnalysisSegment(start: Point2D(x: 0.0, y: 0.0), end: Point2D(x: 1.0, y: 0.0)),
        sectionAnalysisSegment(start: Point2D(x: 1.0, y: 1.0), end: Point2D(x: 0.0, y: 1.0)),
    ]

    let contours = SectionAnalysisContourBuilder(tolerance: 1.0e-8).build(
        segments: segments
    )

    let contour = try #require(contours.first)
    #expect(contours.count == 1)
    #expect(contour.isClosed)
    #expect(contour.points2D.count == 4)
    #expect(abs(abs(contour.signedAreaSquareMeters) - 1.0) <= 1.0e-8)
    #expect(abs(contour.lengthMeters - 4.0) <= 1.0e-8)
    #expect(contour.segmentCount == 4)
}

@Test func sectionAnalysisContourBuilderPreservesOpenPolylineWhenLoopIsIncomplete() throws {
    let segments = [
        sectionAnalysisSegment(start: Point2D(x: 0.0, y: 0.0), end: Point2D(x: 1.0, y: 0.0)),
        sectionAnalysisSegment(start: Point2D(x: 1.0, y: 0.0), end: Point2D(x: 1.0, y: 1.0)),
    ]

    let contours = SectionAnalysisContourBuilder(tolerance: 1.0e-8).build(
        segments: segments
    )

    let contour = try #require(contours.first)
    #expect(contours.count == 1)
    #expect(!contour.isClosed)
    #expect(contour.points2D.count == 3)
    #expect(contour.signedAreaSquareMeters == 0.0)
    #expect(abs(contour.lengthMeters - 2.0) <= 1.0e-8)
}

private func sectionAnalysisTestDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Section Analysis Fixture")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Section Fixture Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(-1.0, .meter),
            y: .length(-1.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(1.0, .meter),
            y: .length(1.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Section Fixture Body",
        profile: ProfileReference(featureID: profileID),
        distance: .length(2.0, .meter),
        direction: .normal
    )
    return document
}

private func sectionAnalysisSegment(
    start: Point2D,
    end: Point2D,
    bodyID: String = "body-a"
) -> SectionAnalysisResult.IntersectionSegment {
    SectionAnalysisResult.IntersectionSegment(
        bodyID: bodyID,
        start: Point3D(x: start.x, y: 0.0, z: start.y),
        end: Point3D(x: end.x, y: 0.0, z: end.y),
        start2D: start,
        end2D: end
    )
}
