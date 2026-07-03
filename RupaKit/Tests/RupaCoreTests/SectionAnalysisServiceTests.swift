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
    #expect(!result.truncatedIntersectionSegments)
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
