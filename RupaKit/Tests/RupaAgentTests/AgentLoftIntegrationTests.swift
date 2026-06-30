import Testing
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentCreatesLoftSourceThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Loft Top",
        width: 6.0,
        height: 3.0,
        z: 10.0
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createLoft(
                name: "Agent Ruled Loft",
                sections: [
                    LoftSectionReference(
                        profile: ProfileReference(featureID: firstProfileID),
                        startSampleIndex: 1
                    ),
                    LoftSectionReference(
                        profile: ProfileReference(featureID: secondProfileID),
                        startSampleIndex: 1
                    ),
                ],
                options: LoftOptions(resultKind: .solid)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a loft command result.")
        return
    }
    let loftID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[loftID])
    guard case .loft(let loft) = feature.operation else {
        Issue.record("Agent must create a loft feature.")
        return
    }

    #expect(result.commandName == "createLoft")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(loft.sections.map(\.featureID) == [firstProfileID, secondProfileID])
    #expect(loft.sections.map(\.startSampleIndex) == [1, 1])
    #expect(loft.options.resultKind == .solid)
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesClosedSectionLoopLoftSheetThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Loop First",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 0.0
    )
    let secondProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Loop Second",
        width: 4.0,
        height: 2.0,
        x: 6.0,
        z: 4.0
    )
    let thirdProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Loop Third",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 8.0
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createLoft(
                name: "Agent Smooth Closed Loop Loft Sheet",
                sections: [
                    LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
                    LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
                    LoftSectionReference(profile: ProfileReference(featureID: thirdProfileID)),
                ],
                options: LoftOptions(
                    resultKind: .sheet,
                    closesSectionLoop: true,
                    surfaceMode: .smooth
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a closed loop loft command result.")
        return
    }
    let loftID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[loftID])
    let evaluated = try #require(session.currentEvaluation?.evaluatedDocument)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)
    let connectorCurves = evaluated.brep.geometry.curves.values.compactMap(\.bSplineCurve)
    guard case .loft(let loft) = feature.operation else {
        Issue.record("Agent must create a closed loop loft feature.")
        return
    }

    #expect(result.commandName == "createLoft")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(loft.options.resultKind == .sheet)
    #expect(loft.options.closesSectionLoop)
    #expect(loft.options.surfaceMode == .smooth)
    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    #expect(sideSurfaces.count == 12)
    #expect(connectorCurves.count == 12)
    #expect(sideSurfaces.allSatisfy { surface in
        surface.uDegree == 1
            && surface.vDegree == 3
            && surface.uControlPointCount == 2
            && surface.vControlPointCount == 4
    })
    #expect(connectorCurves.allSatisfy { curve in
        curve.degree == 3 && curve.controlPointCount == 4
    })
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesSmoothLoftThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Smooth Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let middleProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Smooth Loft Middle",
        width: 5.0,
        height: 2.5,
        x: 3.0,
        z: 5.0
    )
    let lastProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Smooth Loft Top",
        width: 4.0,
        height: 2.0,
        z: 10.0
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createLoft(
                name: "Agent Smooth Loft",
                sections: [
                    LoftSectionReference(
                        profile: ProfileReference(featureID: firstProfileID),
                        smoothTangentScale: 0.25,
                        smoothTangentMode: .zero
                    ),
                    LoftSectionReference(profile: ProfileReference(featureID: middleProfileID)),
                    LoftSectionReference(profile: ProfileReference(featureID: lastProfileID)),
                ],
                options: LoftOptions(
                    resultKind: .solid,
                    surfaceMode: .smooth,
                    smoothTangentScale: 0.5
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a smooth loft command result.")
        return
    }
    let loftID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[loftID])
    let evaluated = try #require(session.currentEvaluation?.evaluatedDocument)
    let sideSurfaces = evaluated.brep.geometry.surfaces.values.compactMap(\.bSplineSurface)
    let connectorCurves = evaluated.brep.geometry.curves.values.compactMap(\.bSplineCurve)
    guard case .loft(let loft) = feature.operation else {
        Issue.record("Agent must create a smooth loft feature.")
        return
    }

    #expect(result.commandName == "createLoft")
    #expect(result.didMutate)
    #expect(loft.options.surfaceMode == .smooth)
    #expect(loft.options.smoothTangentScale == 0.5)
    #expect(loft.sections.map(\.smoothTangentScale) == [0.25, nil, nil])
    #expect(loft.sections.map(\.smoothTangentMode) == [.zero, .automatic, .automatic])
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(sideSurfaces.count == 8)
    #expect(connectorCurves.count == 8)
    #expect(sideSurfaces.allSatisfy { surface in
        surface.uDegree == 1
            && surface.vDegree == 3
            && surface.uControlPointCount == 2
            && surface.vControlPointCount == 4
    })
    #expect(connectorCurves.allSatisfy { curve in
        curve.degree == 3 && curve.controlPointCount == 4
    })
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesGuidedLoftThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let firstProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Guided Loft Bottom",
        width: 4.0,
        height: 2.0,
        z: 0.0
    )
    let secondProfileID = try createAgentLoftProfile(
        in: &document,
        name: "Agent Guided Loft Top",
        width: 4.0,
        height: 2.0,
        z: 10.0
    )
    let guideID = try document.createSketch(
        name: "Agent Guided Loft Seam",
        sketch: agentLoftVerticalGuideSketch(x: 2.0, y: -1.0, zStart: 0.0, zEnd: 10.0),
        geometryRole: .curve
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createLoft(
                name: "Agent Guided Loft",
                sections: [
                    LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
                    LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
                ],
                guides: [
                    LoftGuideReference(featureID: guideID),
                ],
                options: LoftOptions(resultKind: .solid)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a guided loft command result.")
        return
    }
    let loftID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[loftID])
    let evaluated = try #require(session.currentEvaluation?.evaluatedDocument)
    let vertexReference = try #require(evaluated.generatedNames[PersistentName(components: [
        .feature(loftID),
        .generated(GeneratedSubshapeRole.vertex.rawValue),
        .index(0),
    ])])
    guard case .loft(let loft) = feature.operation,
          case .vertex(let vertexID) = vertexReference,
          let vertex = evaluated.brep.vertices[vertexID] else {
        Issue.record("Agent must create a guided loft feature and generated vertex reference.")
        return
    }

    #expect(result.commandName == "createLoft")
    #expect(result.didMutate)
    #expect(loft.guides == [LoftGuideReference(featureID: guideID)])
    #expect(vertex.point.isApproximatelyEqual(to: Point3D(x: 0.002, y: -0.001, z: 0.0), tolerance: 1.0e-12))
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

private func createAgentLoftProfile(
    in document: inout DesignDocument,
    name: String,
    width: Double,
    height: Double,
    x: Double = 0.0,
    z: Double
) throws -> FeatureID {
    try document.createRectangleSketch(
        name: name,
        plane: agentLoftPlane(x: x, z: z),
        width: .length(width, .millimeter),
        height: .length(height, .millimeter)
    )
}

private func agentLoftVerticalGuideSketch(x: Double, y: Double, zStart: Double, zEnd: Double) -> Sketch {
    let lineID = SketchEntityID()
    return Sketch(
        plane: .plane(Plane3D(
            origin: Point3D(x: x / 1000.0, y: y / 1000.0, z: zStart / 1000.0),
            normal: .unitY
        )),
        entities: [
            lineID: .line(SketchLine(
                start: SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
                end: SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length((zEnd - zStart) / 1000.0, unit: .meter)))
            )),
        ],
        constraints: [],
        dimensions: []
    )
}

private func agentLoftPlane(x: Double = 0.0, z: Double) -> SketchPlane {
    if x == 0.0 && z == 0.0 {
        return .xy
    }
    return .plane(Plane3D(
        origin: Point3D(x: x / 1000.0, y: 0.0, z: z / 1000.0),
        normal: .unitZ
    ))
}

private extension Surface3D {
    var bSplineSurface: BSplineSurface3D? {
        if case .bSpline(let surface) = self {
            return surface
        }
        return nil
    }
}

private extension Curve3D {
    var bSplineCurve: BSplineCurve3D? {
        if case .bSpline(let curve) = self {
            return curve
        }
        return nil
    }
}
