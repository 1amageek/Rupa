import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

@Test func agentDispatchesModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedRectangle")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@Test func agentDispatchesSelectedObjectDimensionCommand() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })

    let dimensionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setObjectDimension(
                target: SelectionTarget(sceneNodeID: bodyNode.id),
                kind: .sizeX,
                value: .length(36.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = dimensionResponse else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setObjectDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    let editedBodyNode = try #require(session.document.productMetadata.sceneNodes[bodyNode.id])
    guard case .length(let sizeX)? = editedBodyNode.object?.properties["size.x"] else {
        Issue.record("Expected a body size X property.")
        return
    }
    #expect(abs(sizeX - 0.036) < 0.000_000_000_001)
}

@Test func agentDispatchesObjectDimensionCommandFromGeneratedDepthEdge() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Edge Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let depthEdge = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let edgeTarget = try #require(depthEdge.selectionTarget())

    let dimensionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setObjectDimension(
                target: edgeTarget,
                kind: .sizeY,
                value: .length(10.0, .millimeter)
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = dimensionResponse else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setObjectDimension")
    #expect(result.didMutate)
    let editedBodyNode = try #require(session.document.productMetadata.sceneNodes[edgeTarget.sceneNodeID])
    let sizeYValue = editedBodyNode.object?.properties["size.y"]
    guard case .length(let sizeY) = sizeYValue else {
        Issue.record("Expected a body size Y property.")
        return
    }
    #expect(abs(sizeY - 0.010) < 0.000_000_000_001)
}

@Test func agentReturnsSelectedObjectDimensionSummaryWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedCircle(
                name: "Agent Dimension Cylinder",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .meter),
                    y: .length(0.0, .meter)
                ),
                radius: .length(12.0, .millimeter),
                depth: .length(24.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body && $0.object?.typeID == .cylinder
    })
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [
                SelectionTarget(
                    sceneNodeID: bodyNode.id,
                    component: .face(.bodyFaceSide)
                ),
            ],
            expectedGeneration: generation
        )
    )

    guard case .objectDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.entryCount == 3)
    #expect(summary.entries.map(\.kind) == [.diameter, .radius, .sizeY])
    let diameter = try #require(summary.entries.first { $0.kind == .diameter })
    #expect(diameter.isPrimaryForTarget)
    #expect(abs(diameter.resolvedMeters - 0.024) < 0.000_000_000_001)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@Test func agentReturnsObjectDimensionSummaryFromGeneratedDepthEdgeWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Summary Edge Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let depthEdge = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let edgeTarget = try #require(depthEdge.selectionTarget())
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [edgeTarget],
            expectedGeneration: generation
        )
    )

    guard case .objectDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.entryCount == 3)
    let kinds: [ObjectDimensionKind] = summary.entries.map(\.kind)
    #expect(kinds == [.sizeX, .sizeY, .sizeZ])
    let depth = try #require(summary.entries.first { $0.kind == ObjectDimensionKind.sizeY })
    #expect(depth.isPrimaryForTarget)
    #expect(depth.target == edgeTarget)
    #expect(abs(depth.resolvedMeters - 0.006) < 0.000_000_000_001)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@Test func agentInfersObjectDimensionPrimaryFromGeneratedFaceWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Summary Generated Face Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let endFace = try #require(topology.entries.first {
        $0.kind == .face && $0.generatedRole == "endFace"
    })
    let faceTarget = try #require(endFace.selectionTarget())
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [faceTarget],
            expectedGeneration: generation
        )
    )

    guard case .objectDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 3)
    let primary = try #require(summary.entries.first { $0.isPrimaryForTarget })
    #expect(primary.kind == .sizeY)
    #expect(primary.target == faceTarget)
    #expect(abs(primary.resolvedMeters - 0.006) < 1.0e-12)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@Test func agentUsesGeneratedFacePairObjectDimensionSummaryForMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Summary Face Pair Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let facePair = try agentParallelFaceDimensionTargets(in: topology)
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [facePair.first, facePair.second],
            expectedGeneration: generation
        )
    )

    guard case .objectDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.targetCount == 2)
    #expect(summary.counts.entryCount == 1)
    let entry = try #require(summary.entries.first)
    #expect(entry.label == "Face Distance")
    #expect(entry.isPrimaryForTarget)
    #expect(abs(entry.resolvedMeters - facePair.distance) < 1.0e-12)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)

    let targetDistance = facePair.distance + 0.004
    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setObjectDimension(
                target: entry.target,
                kind: entry.kind,
                value: .length(targetDistance, .meter)
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setObjectDimension")
    #expect(setResult.didMutate)

    let updatedResponse = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [facePair.first, facePair.second],
            expectedGeneration: session.generation
        )
    )
    guard case .objectDimensionSummary(let updatedSummary) = updatedResponse else {
        #expect(Bool(false))
        return
    }
    let updatedEntry = try #require(updatedSummary.entries.first)
    #expect(updatedEntry.inputExpression == .length(targetDistance, .meter))
    #expect(abs(updatedEntry.resolvedMeters - targetDistance) < 1.0e-12)
}

@Test func agentReturnsSelectedSketchDimensionSummaryWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createLineSketch(
                name: "Agent Dimension Line",
                plane: .xy,
                start: SketchPoint(
                    x: .length(0.0, .meter),
                    y: .length(0.0, .meter)
                ),
                end: SketchPoint(
                    x: .length(24.0, .millimeter),
                    y: .length(0.0, .meter)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let sketchSummaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .sketchEntitySummary(let sketchSummary) = sketchSummaryResponse else {
        #expect(Bool(false))
        return
    }
    let line = try #require(sketchSummary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .sketchDimensionSummary(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: generation
        )
    )

    guard case .sketchDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.entryCount == 2)
    #expect(summary.entries.map(\.kind) == [.length, .angle])
    let length = try #require(summary.entries.first { $0.kind == .length })
    #expect(length.isPrimaryForTarget)
    #expect(abs(length.resolvedValue - 0.024) < 0.000_000_000_001)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@Test func agentMapsGeneratedEdgeToSketchDimensionSummaryWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Edge Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(8.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let capEdge = try #require(topology.entries.first {
        $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "line" &&
            ($0.index ?? Int.max) < 4
    })
    let edgeTarget = try #require(capEdge.selectionTarget())
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .sketchDimensionSummary(
            sessionID: sessionID,
            targets: [edgeTarget],
            expectedGeneration: generation
        )
    )

    guard case .sketchDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.entryCount == 2)
    #expect(summary.entries.map(\.kind) == [.length, .angle])
    #expect(summary.entries.allSatisfy { $0.requestedTarget == edgeTarget })
    guard case .sketchEntity = summary.entries[0].target.component else {
        Issue.record("Agent sketch dimension summary must return an editable sketch entity target.")
        return
    }
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@Test func agentMapsGeneratedFilletArcEdgeToSketchRadiusDimensionWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Fillet Radius Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(8.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    let filletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = filletResponse else {
        #expect(Bool(false))
        return
    }
    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let filletArcEdge = try #require(topology.entries.first {
        guard let radius = $0.curveRadius else {
            return false
        }
        return $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            abs(radius - 0.001) < 1.0e-12
    })
    let edgeTarget = try #require(filletArcEdge.selectionTarget())
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .sketchDimensionSummary(
            sessionID: sessionID,
            targets: [edgeTarget],
            expectedGeneration: generation
        )
    )

    guard case .sketchDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.entryCount == 3)
    #expect(summary.entries.map(\.kind) == [.diameter, .radius, .angle])
    #expect(summary.entries.allSatisfy { $0.requestedTarget == edgeTarget })
    #expect(summary.entries.allSatisfy { $0.entityKind == "arc" })
    let radius = try #require(summary.entries.first { $0.isPrimaryForTarget })
    #expect(radius.kind == .radius)
    #expect(abs(radius.resolvedValue - 0.001) < 1.0e-12)
    guard case .sketchEntity = radius.target.component else {
        Issue.record("Agent generated fillet arc dimension must return an editable sketch arc target.")
        return
    }
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentEditsGeneratedFilletArcRadiusThroughSourceDimensionTarget() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Editable Fillet Radius Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(8.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let baseSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let bounds = try #require(agentSketchSummaryBounds(baseSummary))
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    let filletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = filletResponse else {
        #expect(Bool(false))
        return
    }

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let filletArcEdge = try #require(topology.entries.first {
        guard let radius = $0.curveRadius else {
            return false
        }
        return $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            abs(radius - 0.001) < 1.0e-12
    })
    let edgeTarget = try #require(filletArcEdge.selectionTarget())
    let dimensionResponse = server.handle(
        .sketchDimensionSummary(
            sessionID: sessionID,
            targets: [edgeTarget],
            expectedGeneration: session.generation
        )
    )
    guard case .sketchDimensionSummary(let dimensionSummary) = dimensionResponse else {
        #expect(Bool(false))
        return
    }
    let editableRadius = try #require(dimensionSummary.entries.first { $0.isPrimaryForTarget })
    #expect(editableRadius.kind == .radius)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: editableRadius.target,
                kind: .radius,
                value: .length(2.0, .millimeter)
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityID == editableRadius.entityID })
    let updatedDimension = try #require(updatedArc.dimensions.first { $0.kind == "radius" })
    let updatedTopology = try TopologySummaryService().summarize(document: session.document)
    let updatedGeneratedArc = try #require(updatedTopology.entries.first {
        guard let radius = $0.curveRadius else {
            return false
        }
        return $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            abs(radius - 0.002) < 1.0e-12
    })

    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(updatedArc.entityKind == "arc")
    #expect(abs((updatedArc.radius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(abs((updatedArc.center?.x ?? -1.0) - (bounds.maxX - 0.002)) < 1.0e-12)
    #expect(abs((updatedArc.center?.y ?? -1.0) - (bounds.maxY - 0.002)) < 1.0e-12)
    #expect(abs(updatedDimension.resolvedValue - 0.002) < 1.0e-12)
    #expect(agentContainsSketchPoint(updatedSummary, x: bounds.maxX, y: bounds.maxY - 0.002))
    #expect(agentContainsSketchPoint(updatedSummary, x: bounds.maxX - 0.002, y: bounds.maxY))
    #expect(abs((updatedGeneratedArc.curveRadius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentEditsGeneratedFilletArcRadiusThroughGeneratedEdgeTarget() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Direct Fillet Radius Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(8.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let baseSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let bounds = try #require(agentSketchSummaryBounds(baseSummary))
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    let filletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = filletResponse else {
        #expect(Bool(false))
        return
    }
    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let filletArcEdge = try #require(topology.entries.first {
        guard let radius = $0.curveRadius else {
            return false
        }
        return $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            abs(radius - 0.001) < 1.0e-12
    })
    let edgeTarget = try #require(filletArcEdge.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: edgeTarget,
                kind: .radius,
                value: .length(2.0, .millimeter)
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first {
        $0.entityKind == "arc" &&
            abs(($0.radius ?? -1.0) - 0.002) < 1.0e-12
    })
    let updatedTopology = try TopologySummaryService().summarize(document: session.document)
    let updatedGeneratedArc = try #require(updatedTopology.entries.first {
        guard let radius = $0.curveRadius else {
            return false
        }
        return $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            abs(radius - 0.002) < 1.0e-12
    })

    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedArc.center?.x ?? -1.0) - (bounds.maxX - 0.002)) < 1.0e-12)
    #expect(abs((updatedArc.center?.y ?? -1.0) - (bounds.maxY - 0.002)) < 1.0e-12)
    #expect(abs((updatedGeneratedArc.curveRadius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(agentContainsSketchPoint(updatedSummary, x: bounds.maxX, y: bounds.maxY - 0.002))
    #expect(agentContainsSketchPoint(updatedSummary, x: bounds.maxX - 0.002, y: bounds.maxY))
    #expect(session.evaluationStatus == .valid)
}
