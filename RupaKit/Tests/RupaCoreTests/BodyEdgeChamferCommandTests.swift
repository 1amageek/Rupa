import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func chamferBodyEdgesCommandRewritesRectangleProfileCorner() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeBounds = try chamferProfileBounds(forBody: bodyFeatureID, in: session.document)
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop))

    let result = try session.execute(
        .chamferBodyEdges(
            targets: [target],
            distance: .length(1.0, .millimeter)
        )
    )

    let lines = try chamferProfileLines(forBody: bodyFeatureID, in: session.document)
    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(lines.count == 5)
    #expect(
        lines.containsLine(
            from: (beforeBounds.maxX, beforeBounds.maxY - 0.001),
            to: (beforeBounds.maxX - 0.001, beforeBounds.maxY)
        )
    )
    #expect(chamferBodyObject(for: bodyFeatureID, in: session.document)?.typeID == nil)
    #expect(session.evaluationStatus == .valid)

    _ = try session.undo()
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 4)
    #expect(chamferBodyObject(for: bodyFeatureID, in: session.document)?.typeID == .cube)
}

@MainActor
@Test func chamferBodyEdgesCommandRejectsCollapsedProfile() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeLeftBottom))

    do {
        _ = try session.execute(
            .chamferBodyEdges(
                targets: [target],
                distance: .length(100.0, .millimeter)
            )
        )
        Issue.record("An edge chamfer that collapses the profile must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == DocumentGeneration(1))
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 4)
}

@MainActor
@Test func chamferBodyEdgesCommandAcceptsGeneratedTopologyEdgeReference() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first(where: isVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())
    let beforeBounds = try chamferProfileBounds(forBody: bodyFeatureID, in: session.document)

    let result = try session.execute(
        .chamferBodyEdges(
            targets: [target],
            distance: .length(1.0, .millimeter)
        )
    )

    let lines = try chamferProfileLines(forBody: bodyFeatureID, in: session.document)
    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(lines.count == 5)
    #expect(
        lines.containsLine(
            from: (beforeBounds.minX + 0.001, beforeBounds.minY),
            to: (beforeBounds.minX, beforeBounds.minY + 0.001)
        )
        || lines.containsLine(
            from: (beforeBounds.maxX, beforeBounds.minY + 0.001),
            to: (beforeBounds.maxX - 0.001, beforeBounds.minY)
        )
        || lines.containsLine(
            from: (beforeBounds.maxX, beforeBounds.maxY - 0.001),
            to: (beforeBounds.maxX - 0.001, beforeBounds.maxY)
        )
        || lines.containsLine(
            from: (beforeBounds.minX + 0.001, beforeBounds.maxY),
            to: (beforeBounds.minX, beforeBounds.maxY - 0.001)
        )
    )
}

@MainActor
@Test func chamferBodyEdgesCommandCanEditGeneratedEdgeAfterPriorChamfer() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))

    _ = try session.execute(
        .chamferBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            distance: .length(1.0, .millimeter)
        )
    )
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 5)

    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first(where: isVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let result = try session.execute(
        .chamferBodyEdges(
            targets: [target],
            distance: .length(0.5, .millimeter)
        )
    )

    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 6)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func filletBodyEdgesCommandRewritesRectangleProfileCornerWithArcEntity() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))
    let beforeBounds = try chamferProfileBounds(forBody: bodyFeatureID, in: session.document)
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop))

    let result = try session.execute(
        .filletBodyEdges(
            targets: [target],
            radius: .length(1.0, .millimeter),
            segmentCount: 6
        )
    )

    let lines = try chamferProfileLines(forBody: bodyFeatureID, in: session.document)
    let arcs = try chamferProfileArcs(forBody: bodyFeatureID, in: session.document)
    let arc = try #require(arcs.first)
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(lines.count == 4)
    #expect(arcs.count == 1)
    #expect(abs(arc.center.x - (beforeBounds.maxX - 0.001)) <= 1.0e-9)
    #expect(abs(arc.center.y - (beforeBounds.maxY - 0.001)) <= 1.0e-9)
    #expect(abs(arc.radius - 0.001) <= 1.0e-9)
    #expect(abs(arc.startAngle - 0.0) <= 1.0e-9)
    #expect(abs(arc.endAngle - Double.pi / 2.0) <= 1.0e-9)
    #expect(chamferBodyObject(for: bodyFeatureID, in: session.document)?.typeID == nil)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func filletBodyEdgesCommandAcceptsGeneratedTopologyEdgeReference() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first(where: isVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let result = try session.execute(
        .filletBodyEdges(
            targets: [target],
            radius: .length(1.0, .millimeter),
            segmentCount: 6
        )
    )

    let lines = try chamferProfileLines(forBody: bodyFeatureID, in: session.document)
    let arcs = try chamferProfileArcs(forBody: bodyFeatureID, in: session.document)
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(2))
    #expect(lines.count == 4)
    #expect(arcs.count == 1)
}

@MainActor
@Test func filletBodyEdgesCommandCanEditGeneratedEdgeAfterPriorChamfer() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))

    _ = try session.execute(
        .chamferBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            distance: .length(1.0, .millimeter)
        )
    )
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 5)

    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first(where: isVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let result = try session.execute(
        .filletBodyEdges(
            targets: [target],
            radius: .length(0.25, .millimeter),
            segmentCount: 8
        )
    )

    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 5)
    #expect(try chamferProfileArcs(forBody: bodyFeatureID, in: session.document).count == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func filletBodyEdgesCommandCanEditSharpGeneratedEdgeAfterPriorFillet() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))

    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 4)
    #expect(try chamferProfileArcs(forBody: bodyFeatureID, in: session.document).count == 1)

    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first {
        isVerticalGeneratedEdge($0, x: -0.020, y: -0.010)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let result = try session.execute(
        .filletBodyEdges(
            targets: [target],
            radius: .length(0.5, .millimeter),
            segmentCount: 8
        )
    )

    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 4)
    #expect(try chamferProfileArcs(forBody: bodyFeatureID, in: session.document).count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func filletBodyEdgesCommandCanEditLineArcProfileCorner() async throws {
    let setup = try lineArcExtrudedSession()
    let session = setup.session
    let bodyFeatureID = setup.bodyFeatureID
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first {
        isVerticalGeneratedEdge($0, x: 2.0, y: 0.0)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let result = try session.execute(
        .filletBodyEdges(
            targets: [target],
            radius: .length(100.0, .millimeter),
            segmentCount: 8
        )
    )

    let lines = try chamferProfileLines(forBody: bodyFeatureID, in: session.document)
    let arcs = try chamferProfileArcs(forBody: bodyFeatureID, in: session.document)
    let insertedArc = try #require(arcs.first { arc in
        abs(arc.radius - 0.1) <= 1.0e-12
    })
    let sourceArc = try #require(arcs.first { arc in
        abs(arc.radius - 1.0) <= 1.0e-12
    })
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(abs(insertedArc.center.x - (1.0 + sqrt(0.8))) <= 1.0e-12)
    #expect(abs(insertedArc.center.y - 0.1) <= 1.0e-12)
    #expect(sourceArc.startAngle > 0.0)
    #expect(abs(sourceArc.endAngle - Double.pi / 2.0) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func filletBodyEdgesCommandCanEditArcArcProfileCorner() async throws {
    let setup = try arcArcExtrudedSession()
    let session = setup.session
    let bodyFeatureID = setup.bodyFeatureID
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first {
        isVerticalGeneratedEdge($0, x: 0.0, y: 0.0)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let result = try session.execute(
        .filletBodyEdges(
            targets: [target],
            radius: .length(100.0, .millimeter),
            segmentCount: 8
        )
    )

    let lines = try chamferProfileLines(forBody: bodyFeatureID, in: session.document)
    let arcs = try chamferProfileArcs(forBody: bodyFeatureID, in: session.document)
    let insertedArc = try #require(arcs.first { arc in
        abs(arc.radius - 0.1) <= 1.0e-12
    })
    let previousSourceArc = try #require(arcs.first { arc in
        abs(arc.radius - 1.0) <= 1.0e-12
    })
    let currentSourceArc = try #require(arcs.first { arc in
        abs(arc.radius - 2.0) <= 1.0e-12
    })

    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(lines.count == 1)
    #expect(arcs.count == 3)
    #expect(abs(insertedArc.center.x + 0.10295400907294588) <= 1.0e-12)
    #expect(abs(insertedArc.center.y - 0.10590801814589135) <= 1.0e-12)
    #expect(abs(previousSourceArc.startAngle - Double.pi) <= 1.0e-12)
    #expect(previousSourceArc.endAngle > Double.pi)
    #expect(previousSourceArc.endAngle < Double.pi * 1.5)
    #expect(currentSourceArc.startAngle > 0.0)
    #expect(abs(currentSourceArc.endAngle - Double.pi / 3.0) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func chamferBodyEdgesCommandCanEditSharpGeneratedEdgeAfterPriorFillet() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))

    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )

    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first {
        isVerticalGeneratedEdge($0, x: -0.020, y: -0.010)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let result = try session.execute(
        .chamferBodyEdges(
            targets: [target],
            distance: .length(0.5, .millimeter)
        )
    )

    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 5)
    #expect(try chamferProfileArcs(forBody: bodyFeatureID, in: session.document).count == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func chamferBodyEdgesCommandCanEditArcAdjacentGeneratedEdgeAfterPriorFillet() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))

    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )

    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first {
        isVerticalGeneratedEdge($0, x: 0.020, y: 0.009)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let result = try session.execute(
        .chamferBodyEdges(
            targets: [target],
            distance: .length(0.25, .millimeter)
        )
    )

    let arcs = try chamferProfileArcs(forBody: bodyFeatureID, in: session.document)
    let arc = try #require(arcs.first)
    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(session.generation == DocumentGeneration(3))
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 5)
    #expect(arcs.count == 1)
    #expect(abs(arc.startAngle - 0.25) <= 1.0e-9)
    #expect(abs(arc.endAngle - Double.pi / 2.0) <= 1.0e-9)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func filletBodyEdgesCommandRejectsArcAdjacentGeneratedEdgeAfterPriorFillet() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))

    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )

    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first {
        isVerticalGeneratedEdge($0, x: 0.020, y: 0.009)
    })
    let target = try #require(edgeEntry.selectionTarget())

    do {
        _ = try session.execute(
            .filletBodyEdges(
                targets: [target],
                radius: .length(0.25, .millimeter),
                segmentCount: 8
            )
        )
        Issue.record("Arc-adjacent generated edge fillet must fail until tangent-continuous curve blending is supported.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == DocumentGeneration(2))
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 4)
    #expect(try chamferProfileArcs(forBody: bodyFeatureID, in: session.document).count == 1)
}

@MainActor
@Test func edgeEditCommandsRejectGeneratedVertexTargetsAfterPriorFillet() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))

    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )

    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertexEntry = try #require(topology.entries.first {
        isGeneratedVertex($0, x: -0.020, y: -0.010)
    })
    let target = try #require(vertexEntry.selectionTarget())

    do {
        _ = try session.execute(
            .filletBodyEdges(
                targets: [target],
                radius: .length(0.25, .millimeter),
                segmentCount: 8
            )
        )
        Issue.record("Edge fillet must reject generated vertex targets.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    do {
        _ = try session.execute(
            .chamferBodyEdges(
                targets: [target],
                distance: .length(0.25, .millimeter)
            )
        )
        Issue.record("Edge chamfer must reject generated vertex targets.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == DocumentGeneration(2))
    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: session.document).count == 4)
    #expect(try chamferProfileArcs(forBody: bodyFeatureID, in: session.document).count == 1)
}

@MainActor
@Test func filletBodyEdgesCommandRejectsInvalidSegmentCount() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeLeftTop))

    do {
        _ = try session.execute(
            .filletBodyEdges(
                targets: [target],
                radius: .length(1.0, .millimeter),
                segmentCount: 2
            )
        )
        Issue.record("An edge fillet with too few arc segments must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == DocumentGeneration(1))
}

@MainActor
@Test func initialRectangleEdgeEditsRejectDimensionedProfileBeforeRewrite() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))
    var document = session.document
    try appendDistanceDimensionToFirstProfileLine(
        forBody: bodyFeatureID,
        in: &document
    )
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop))

    do {
        try document.chamferBodyEdges(
            targets: [target],
            distance: .length(1.0, .millimeter)
        )
        Issue.record("Initial rectangle edge chamfer must reject dimensioned profile loops before rewriting source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    do {
        try document.filletBodyEdges(
            targets: [target],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
        Issue.record("Initial rectangle edge fillet must reject dimensioned profile loops before rewriting source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: document).count == 4)
    #expect(try chamferProfileArcs(forBody: bodyFeatureID, in: document).isEmpty)
}

@MainActor
@Test func initialRectangleEdgeEditsRejectReferencedExpressionBeforeRewrite() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))
    var document = session.document
    document.upsertParameter(
        name: "cornerX",
        expression: .constant(.length(-20.0, unit: .millimeter)),
        kind: .length
    )
    let parameter = try #require(
        document.cadDocument.parameters.parameters.values.first { $0.name == "cornerX" }
    )
    try replaceFirstProfilePointX(
        forBody: bodyFeatureID,
        with: .reference(parameter.id),
        in: &document
    )
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop))

    do {
        try document.chamferBodyEdges(
            targets: [target],
            distance: .length(1.0, .millimeter)
        )
        Issue.record("Initial rectangle edge chamfer must reject referenced profile expressions before rewriting source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    do {
        try document.filletBodyEdges(
            targets: [target],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
        Issue.record("Initial rectangle edge fillet must reject referenced profile expressions before rewriting source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: document).count == 4)
    #expect(try chamferProfileArcs(forBody: bodyFeatureID, in: document).isEmpty)
}

@MainActor
@Test func generatedEdgeEditRejectsDimensionedCurveProfileBeforeRewrite() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(chamferSceneNodeID(for: bodyFeatureID, in: session.document))

    _ = try session.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        )
    )

    var document = session.document
    try appendDistanceDimensionToFirstProfileLine(
        forBody: bodyFeatureID,
        in: &document
    )
    let topology = try TopologySummaryService().summarize(document: document)
    let edgeEntry = try #require(topology.entries.first {
        isVerticalGeneratedEdge($0, x: -0.020, y: -0.010)
    })
    let target = try #require(edgeEntry.selectionTarget())

    do {
        try document.filletBodyEdges(
            targets: [target],
            radius: .length(0.5, .millimeter),
            segmentCount: 8
        )
        Issue.record("Generated edge edit must reject dimensioned profile loops before rewriting source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(try chamferProfileLines(forBody: bodyFeatureID, in: document).count == 4)
    #expect(try chamferProfileArcs(forBody: bodyFeatureID, in: document).count == 1)
}

private func chamferSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func lineArcExtrudedSession() throws -> (session: EditorSession, bodyFeatureID: FeatureID) {
    var document = DesignDocument.empty()
    let sketchFeatureID = FeatureID()
    document.cadDocument.designGraph.nodes[sketchFeatureID] = FeatureNode(
        id: sketchFeatureID,
        name: "Line Arc Profile",
        operation: .sketch(chamferLineArcProfileSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    document.cadDocument.designGraph.order.append(sketchFeatureID)
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    let bodyFeatureID = try document.extrudeProfile(
        name: "Line Arc Body",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(500.0, .millimeter),
        direction: .normal
    )
    return (EditorSession(document: document), bodyFeatureID)
}

private func arcArcExtrudedSession() throws -> (session: EditorSession, bodyFeatureID: FeatureID) {
    var document = DesignDocument.empty()
    let sketchFeatureID = FeatureID()
    document.cadDocument.designGraph.nodes[sketchFeatureID] = FeatureNode(
        id: sketchFeatureID,
        name: "Arc Arc Profile",
        operation: .sketch(chamferArcArcProfileSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    document.cadDocument.designGraph.order.append(sketchFeatureID)
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    let bodyFeatureID = try document.extrudeProfile(
        name: "Arc Arc Body",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(500.0, .millimeter),
        direction: .normal
    )
    return (EditorSession(document: document), bodyFeatureID)
}

private func chamferLineArcProfileSketch() -> Sketch {
    let arcID = SketchEntityID()
    let bottomID = SketchEntityID()
    let diagonalID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            arcID: .arc(
                SketchArc(
                    center: chamferSketchPoint(x: 1.0, y: 0.0),
                    radius: .length(1.0, .meter),
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 2.0, .radian)
                )
            ),
            bottomID: .line(
                SketchLine(
                    start: chamferSketchPoint(x: 0.0, y: 0.0),
                    end: chamferSketchPoint(x: 2.0, y: 0.0)
                )
            ),
            diagonalID: .line(
                SketchLine(
                    start: chamferSketchPoint(x: 1.0, y: 1.0),
                    end: chamferSketchPoint(x: 0.0, y: 0.5)
                )
            ),
            leftID: .line(
                SketchLine(
                    start: chamferSketchPoint(x: 0.0, y: 0.5),
                    end: chamferSketchPoint(x: 0.0, y: 0.0)
                )
            ),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .arcStart(arcID)),
            .coincident(.arcEnd(arcID), .lineStart(diagonalID)),
            .coincident(.lineEnd(diagonalID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ]
    )
}

private func chamferArcArcProfileSketch() -> Sketch {
    let previousArcID = SketchEntityID()
    let currentArcID = SketchEntityID()
    let lineID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            previousArcID: .arc(
                SketchArc(
                    center: chamferSketchPoint(x: 0.0, y: 1.0),
                    radius: .length(1.0, .meter),
                    startAngle: .angle(Double.pi, .radian),
                    endAngle: .angle(Double.pi * 1.5, .radian)
                )
            ),
            currentArcID: .arc(
                SketchArc(
                    center: chamferSketchPoint(x: -2.0, y: 0.0),
                    radius: .length(2.0, .meter),
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 3.0, .radian)
                )
            ),
            lineID: .line(
                SketchLine(
                    start: chamferSketchPoint(x: -1.0, y: sqrt(3.0)),
                    end: chamferSketchPoint(x: -1.0, y: 1.0)
                )
            ),
        ],
        constraints: [
            .coincident(.arcEnd(previousArcID), .arcStart(currentArcID)),
            .coincident(.arcEnd(currentArcID), .lineStart(lineID)),
            .coincident(.lineEnd(lineID), .arcStart(previousArcID)),
        ]
    )
}

private func chamferSketchPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

private func chamferProfileBounds(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let lines = try chamferProfileLines(forBody: featureID, in: document)
    var points: [(x: Double, y: Double)] = []
    for line in lines {
        points.append(line.start)
        points.append(line.end)
    }
    let first = try #require(points.first)
    return points.dropFirst().reduce(
        (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
    ) { bounds, point in
        (
            minX: min(bounds.minX, point.x),
            minY: min(bounds.minY, point.y),
            maxX: max(bounds.maxX, point.x),
            maxY: max(bounds.maxY, point.y)
        )
    }
}

private func chamferProfileLines(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> [(start: (x: Double, y: Double), end: (x: Double, y: Double))] {
    let extrude = try chamferExtrudeFeature(for: featureID, in: document)
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case .sketch(let sketch) = profileFeature.operation else {
        Issue.record("Body profile must be a sketch.")
        return []
    }
    var lines: [(start: (x: Double, y: Double), end: (x: Double, y: Double))] = []
    for entity in sketch.entities.values {
        guard case .line(let line) = entity else {
            continue
        }
        lines.append(
            (
                start: (
                    x: try chamferLength(line.start.x, in: document),
                    y: try chamferLength(line.start.y, in: document)
                ),
                end: (
                    x: try chamferLength(line.end.x, in: document),
                    y: try chamferLength(line.end.y, in: document)
                )
            )
        )
    }
    return lines
}

private func appendDistanceDimensionToFirstProfileLine(
    forBody featureID: FeatureID,
    in document: inout DesignDocument
) throws {
    let extrude = try chamferExtrudeFeature(for: featureID, in: document)
    guard var profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case var .sketch(sketch) = profileFeature.operation,
          let lineID = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          })?.key else {
        Issue.record("Dimension setup requires a profile line.")
        return
    }
    sketch.dimensions.append(
        .distance(
            from: .lineStart(lineID),
            to: .lineEnd(lineID),
            value: .length(1.0, .millimeter)
        )
    )
    profileFeature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[extrude.profile.featureID] = profileFeature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
}

private func replaceFirstProfilePointX(
    forBody featureID: FeatureID,
    with expression: CADExpression,
    in document: inout DesignDocument
) throws {
    let extrude = try chamferExtrudeFeature(for: featureID, in: document)
    guard var profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case var .sketch(sketch) = profileFeature.operation,
          let lineID = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          })?.key,
          case var .line(line) = sketch.entities[lineID] else {
        Issue.record("Expression setup requires a profile line.")
        return
    }
    line.start.x = expression
    sketch.entities[lineID] = .line(line)
    profileFeature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[extrude.profile.featureID] = profileFeature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
}

private func chamferProfileArcs(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> [(center: (x: Double, y: Double), radius: Double, startAngle: Double, endAngle: Double)] {
    let extrude = try chamferExtrudeFeature(for: featureID, in: document)
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case .sketch(let sketch) = profileFeature.operation else {
        Issue.record("Body profile must be a sketch.")
        return []
    }
    var arcs: [(center: (x: Double, y: Double), radius: Double, startAngle: Double, endAngle: Double)] = []
    for entity in sketch.entities.values {
        guard case .arc(let arc) = entity else {
            continue
        }
        arcs.append(
            (
                center: (
                    x: try chamferLength(arc.center.x, in: document),
                    y: try chamferLength(arc.center.y, in: document)
                ),
                radius: try chamferLength(arc.radius, in: document),
                startAngle: try chamferAngle(arc.startAngle, in: document),
                endAngle: try chamferAngle(arc.endAngle, in: document)
            )
        )
    }
    return arcs
}

private func chamferExtrudeFeature(
    for featureID: FeatureID,
    in document: DesignDocument
) throws -> ExtrudeFeature {
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .extrude(let extrude) = feature.operation else {
        Issue.record("Feature must be an extrude.")
        return ExtrudeFeature(profile: ProfileReference(featureID: FeatureID()), distance: .length(1.0, .meter))
    }
    return extrude
}

private func chamferLength(
    _ expression: CADExpression,
    in document: DesignDocument
) throws -> Double {
    let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}

private func chamferAngle(
    _ expression: CADExpression,
    in document: DesignDocument
) throws -> Double {
    let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .angle)
    return quantity.value
}

private func chamferBodyObject(
    for featureID: FeatureID,
    in document: DesignDocument
) -> ObjectDescriptor? {
    document.productMetadata.sceneNodes.values.first { node in
        node.object?.sourceFeatureID == featureID || node.reference == .body(featureID)
    }?.object
}

private func isVerticalGeneratedEdge(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard entry.kind == .edge,
          let start = entry.start,
          let end = entry.end else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(start.x - end.x) <= tolerance
        && abs(start.y - end.y) <= tolerance
        && abs(start.z - end.z) > tolerance
}

private func isVerticalGeneratedEdge(
    _ entry: TopologySummaryResult.Entry,
    x: Double,
    y: Double
) -> Bool {
    guard isVerticalGeneratedEdge(entry),
          let start = entry.start,
          let end = entry.end else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(((start.x + end.x) / 2.0) - x) <= tolerance
        && abs(((start.y + end.y) / 2.0) - y) <= tolerance
}

private func isGeneratedVertex(
    _ entry: TopologySummaryResult.Entry,
    x: Double,
    y: Double
) -> Bool {
    guard entry.kind == .vertex,
          let point = entry.start else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(point.x - x) <= tolerance
        && abs(point.y - y) <= tolerance
}

private extension Array where Element == (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
    func containsLine(
        from start: (x: Double, y: Double),
        to end: (x: Double, y: Double),
        tolerance: Double = 1.0e-9
    ) -> Bool {
        contains { line in
            pointsMatch(line.start, start, tolerance: tolerance)
                && pointsMatch(line.end, end, tolerance: tolerance)
                || pointsMatch(line.start, end, tolerance: tolerance)
                && pointsMatch(line.end, start, tolerance: tolerance)
        }
    }

    private func pointsMatch(
        _ lhs: (x: Double, y: Double),
        _ rhs: (x: Double, y: Double),
        tolerance: Double
    ) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
    }
}
