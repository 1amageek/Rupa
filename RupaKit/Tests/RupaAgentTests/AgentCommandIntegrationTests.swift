import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@Test func agentReturnsCADInteractionQualityAssessmentWithoutSession() async throws {
    let response = AgentCommandController().handle(.cadInteractionQualityAssessment)

    guard case .cadInteractionQualityAssessment(let assessment) = response else {
        #expect(Bool(false))
        return
    }

    #expect(assessment.counts.entryCount == assessment.entries.count)
    #expect(assessment.entries.contains { $0.area == .dimensions })
    #expect(assessment.entries.contains { $0.area == .agentOperability })
    let productParityAreas: [CADInteractionQualityArea] = [
        .filletingAndBlending,
        .booleanModeling,
        .directModeling,
        .exchangeAndDrawings,
        .patternsAndArrays,
        .sectionAnalysis,
    ]
    for area in productParityAreas {
        let entry = try #require(assessment.entries.first { $0.area == area })
        #expect(entry.currentRating != .missing)
        #expect(!entry.evidence.isEmpty)
        #expect(!entry.openWork.isEmpty)
        #expect(!entry.nextRequiredResult.isEmpty)
    }
    #expect(assessment.entries.allSatisfy { entry in
        entry.gateAssessments.map(\.gate) == CADInteractionQualityGate.allCases
    })
    #expect(Set(assessment.entries.map(\.area)) == Set(CADInteractionQualityArea.allCases))
    #expect(assessment.entries.map(\.area).count == Set(assessment.entries.map(\.area)).count)
}

@MainActor
@Test func agentReturnsDesignDisplaySnapshotForViewportPlanning() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    guard case .designDisplaySnapshot(let snapshot) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(snapshot.sketches.first)
    let extrude = try #require(snapshot.extrudes.first)
    let body = try #require(snapshot.bodies.first)

    #expect(snapshot.generation == session.generation)
    #expect(snapshot.dirty == session.isDirty)
    #expect(snapshot.sketches.count == 1)
    #expect(snapshot.extrudes.count == 1)
    #expect(snapshot.straightPrismSweeps.isEmpty)
    #expect(snapshot.bodies.count == 1)
    #expect(snapshot.componentDefinitions.isEmpty)
    #expect(snapshot.componentInstances.isEmpty)
    #expect(snapshot.patternArrays.isEmpty)
    #expect(sketch.primitives.count == 4)
    #expect(sketch.regions.count == 1)
    #expect(extrude.profileFeatureID == sketch.featureID)
    #expect(extrude.depthMeters > 0.0)
    #expect(body.mesh.positions.isEmpty == false)
    #expect(body.topology.faces.count == 6)
    #expect(body.topology.edges.count == 12)
    #expect(body.topology.vertices.count == 8)
    #expect(decodedResponse == response)
}

@Test func agentDiscoversPlacedComponentInstancesFromDesignDisplaySnapshot() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Placed Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Placed Source"
    })
    _ = try session.execute(
        .createComponentInstance(
            name: "Agent Placed Instance",
            definitionID: definition.id,
            localTransform: .identity
        )
    )
    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let sceneNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .componentInstance(instance.id)
    })
    server.register(session: session, id: sessionID)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(snapshotResponse))
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        #expect(Bool(false))
        return
    }
    let discoveredInstance = try #require(snapshot.componentInstances.first)

    #expect(snapshot.componentDefinitions.count == 1)
    #expect(snapshot.componentInstances.count == 1)
    #expect(discoveredInstance.instanceID == instance.id)
    #expect(discoveredInstance.name == "Agent Placed Instance")
    #expect(discoveredInstance.definitionID == definition.id)
    #expect(discoveredInstance.definitionName == "Agent Placed Source")
    #expect(discoveredInstance.sceneNodeIDs == [sceneNode.id])
    #expect(discoveredInstance.primarySceneNodeID == sceneNode.id)
    #expect(discoveredInstance.ownership == .document)
    #expect(discoveredInstance.ownership.isDirectlyEditable)
    #expect(decodedResponse == snapshotResponse)
}

@Test func agentDiscoversPatternArraySourceFromDesignDisplaySnapshotForLifecycleCommands() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Snapshot Array Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Snapshot Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Snapshot Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    server.register(session: session, id: sessionID)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(snapshotResponse))
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        #expect(Bool(false))
        return
    }
    let discoveredArray = try #require(snapshot.patternArrays.first)
    let discoveredDefinition = try #require(snapshot.componentDefinitions.first)
    let firstOutput = try #require(discoveredArray.outputs.first)
    let firstOutputInstanceID = try #require(firstOutput.componentInstanceID)
    let discoveredInstance = try #require(snapshot.componentInstances.first {
        $0.instanceID == firstOutputInstanceID
    })

    let updateResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .updatePatternArray(
                id: discoveredArray.sourceID,
                name: "Agent Snapshot Array Updated",
                definitionID: nil,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(16.0, .millimeter),
                        copyCount: 1
                    )
                )),
                outputMode: nil
            ),
            expectedGeneration: snapshot.generation
        )
    )
    guard case .command(let updateResult) = updateResponse else {
        #expect(Bool(false))
        return
    }
    let updatedSource = try #require(session.document.productMetadata.patternArrays[discoveredArray.sourceID])
    #expect(snapshot.patternArrays.count == 1)
    #expect(snapshot.componentDefinitions.count == 1)
    #expect(snapshot.componentInstances.count == 2)
    #expect(discoveredDefinition.definitionID == definition.id)
    #expect(discoveredDefinition.name == "Agent Snapshot Array Source")
    #expect(discoveredDefinition.bodySceneNodeIDs == [bodySceneNodeID])
    #expect(discoveredDefinition.bodyFeatureIDs.contains(bodyFeatureID))
    #expect(discoveredDefinition.featureIDs.contains(bodyFeatureID))
    #expect(discoveredDefinition.isRenderable)
    #expect(discoveredArray.name == "Agent Snapshot Array")
    #expect(discoveredArray.definitionID == definition.id)
    #expect(discoveredArray.definitionName == "Agent Snapshot Array Source")
    #expect(discoveredArray.outputCount == 2)
    #expect(discoveredArray.outputs.count == 2)
    #expect(discoveredArray.diagnostics.isEmpty)
    #expect(firstOutput.componentInstanceID == discoveredArray.outputs[0].componentInstanceID)
    #expect(discoveredInstance.definitionID == definition.id)
    #expect(discoveredInstance.definitionName == "Agent Snapshot Array Source")
    #expect(discoveredInstance.primarySceneNodeID == firstOutput.sceneNodeID)
    #expect(discoveredInstance.ownership.kind == .patternArrayOutput)
    #expect(discoveredInstance.ownership.patternArraySourceID == discoveredArray.sourceID)
    #expect(discoveredInstance.ownership.patternArraySourceName == "Agent Snapshot Array")
    #expect(discoveredInstance.ownership.patternArrayOutputIndex == 0)
    #expect(!discoveredInstance.ownership.isDirectlyEditable)
    #expect(decodedResponse == snapshotResponse)
    #expect(updateResult.commandName == "updatePatternArray")
    #expect(updatedSource.name == "Agent Snapshot Array Updated")
    #expect(updatedSource.outputInstanceIDs == [firstOutputInstanceID])
}

@Test func agentReportsPatternArraySummaryForLifecyclePlanning() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Summary Array Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Summary Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Summary Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Summary Array"
    })
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(summaryResponse))
    guard case .patternArraySummary(let result) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let summary = try #require(result.patternArrays.first)

    #expect(result.generation == session.generation)
    #expect(result.dirty == session.isDirty)
    #expect(summary.sourceID == source.id)
    #expect(summary.definitionID == definition.id)
    #expect(summary.definitionName == "Agent Summary Array Source")
    #expect(summary.outputMode == .componentInstance)
    #expect(summary.outputCount == source.outputInstanceIDs.count)
    #expect(summary.componentInstanceOutputIDs == source.outputInstanceIDs)
    #expect(summary.outputOwnership.kind == .sourceOwnedComponentInstances)
    #expect(!summary.outputOwnership.directOutputEditingAllowed)
    #expect(summary.outputOwnership.sourceEditAction == .updatePatternArray)
    #expect(summary.outputOwnership.detachAction == .explodePatternArray)
    #expect(summary.diagnostics.isEmpty)
    #expect(decodedResponse == summaryResponse)
}

@Test func agentReportsIndependentCopyOutputStatesForLifecyclePlanning() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Independent Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Independent Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Independent Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Independent Array"
    })
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try #require(
        agentFeatureID(
            inSceneSubtreeRootedAt: firstOutputSceneNodeID,
            document: session.document
        )
    )
    _ = try session.execute(
        .setExtrudeDistance(
            featureID: firstCloneBodyFeatureID,
            distance: .length(7.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(summaryResponse))
    guard case .patternArraySummary(let result) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let summary = try #require(result.patternArrays.first)
    let firstOutput = try #require(summary.independentCopyOutputs.first)
    let secondOutput = try #require(summary.independentCopyOutputs.dropFirst().first)

    #expect(summary.sourceID == source.id)
    #expect(summary.outputMode == .independentCopy)
    #expect(summary.outputOwnership.kind == .sourceOwnedIndependentCopies)
    #expect(!summary.outputOwnership.directOutputEditingAllowed)
    #expect(summary.outputOwnership.directFeatureEditingAllowed)
    #expect(firstOutput.sceneNodeID == firstOutputSceneNodeID)
    #expect(firstOutput.featureIDs.contains(firstCloneBodyFeatureID))
    #expect(firstOutput.state == .divergedFromSourceDefinition)
    #expect(firstOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
    #expect(secondOutput.state == .matchesSourceDefinition)
    #expect(secondOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
    #expect(decodedResponse == summaryResponse)
}

@MainActor
@Test func agentSetsIndependentCopyCloneExtrudeDistanceThroughDiscoveredFeatureID() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Clone Edit Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Clone Edit Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Clone Edit Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Clone Edit Array"
    })
    let initialGeneration = session.generation
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: initialGeneration
        )
    )
    guard case .patternArraySummary(let summaryResult) = summaryResponse else {
        Issue.record("Agent must return a pattern array summary.")
        return
    }
    let summary = try #require(summaryResult.patternArrays.first { $0.sourceID == source.id })
    let firstOutput = try #require(summary.independentCopyOutputs.first)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: initialGeneration
        )
    )
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        Issue.record("Agent must return a display snapshot.")
        return
    }
    let extrudeFeatureIDs = Set(snapshot.extrudes.map(\.featureID))
    let cloneExtrudeFeatureID = try #require(firstOutput.featureIDs.first { extrudeFeatureIDs.contains($0) })

    let commandResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setExtrudeDistance(
                featureID: cloneExtrudeFeatureID,
                distance: .length(11.0, .millimeter)
            ),
            expectedGeneration: initialGeneration
        )
    )
    guard case .command(let commandResult) = commandResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let expectedEditedGeneration = try initialGeneration.advanced()

    let updatedSnapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: commandResult.generation
        )
    )
    guard case .designDisplaySnapshot(let updatedSnapshot) = updatedSnapshotResponse else {
        Issue.record("Agent must return an updated display snapshot.")
        return
    }
    let editedExtrude = try #require(updatedSnapshot.extrudes.first { $0.featureID == cloneExtrudeFeatureID })

    let updatedSummaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: commandResult.generation
        )
    )
    guard case .patternArraySummary(let updatedSummaryResult) = updatedSummaryResponse else {
        Issue.record("Agent must return an updated pattern array summary.")
        return
    }
    let updatedSummary = try #require(updatedSummaryResult.patternArrays.first { $0.sourceID == source.id })
    let updatedFirstOutput = try #require(updatedSummary.independentCopyOutputs.first)

    #expect(commandResult.message == "Extrude distance updated.")
    #expect(commandResult.commandName == "setExtrudeDistance")
    #expect(commandResult.didMutate)
    #expect(commandResult.generation == expectedEditedGeneration)
    #expect(abs(editedExtrude.depthMeters - 0.011) < 1.0e-12)
    #expect(updatedFirstOutput.featureIDs.contains(cloneExtrudeFeatureID))
    #expect(updatedFirstOutput.state == .divergedFromSourceDefinition)
    #expect(updatedFirstOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
}

@MainActor
@Test func agentSetsIndependentCopyCloneCubeDimensionsThroughDiscoveredFeatureID() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Clone Cube Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Clone Cube Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Clone Cube Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Clone Cube Array"
    })
    let initialGeneration = session.generation
    server.register(session: session, id: sessionID)

    let clone = try agentIndependentCopyCloneExtrudeFeature(
        server: server,
        sessionID: sessionID,
        sourceID: source.id,
        expectedGeneration: initialGeneration
    )
    let commandResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setCubeDimensions(
                featureID: clone.featureID,
                sizeX: .length(16.0, .millimeter),
                sizeY: .length(9.0, .millimeter),
                sizeZ: .length(12.0, .millimeter)
            ),
            expectedGeneration: initialGeneration
        )
    )
    guard case .command(let commandResult) = commandResponse else {
        Issue.record("Agent must return a command result.")
        return
    }

    let dimensionResponse = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [SelectionTarget(sceneNodeID: clone.output.sceneNodeID)],
            expectedGeneration: commandResult.generation
        )
    )
    guard case .objectDimensionSummary(let dimensionSummary) = dimensionResponse else {
        Issue.record("Agent must return an object dimension summary.")
        return
    }
    let sizeX = try #require(dimensionSummary.entries.first { $0.kind == .sizeX })
    let sizeY = try #require(dimensionSummary.entries.first { $0.kind == .sizeY })
    let sizeZ = try #require(dimensionSummary.entries.first { $0.kind == .sizeZ })

    let updatedSummaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: commandResult.generation
        )
    )
    guard case .patternArraySummary(let updatedSummaryResult) = updatedSummaryResponse else {
        Issue.record("Agent must return an updated pattern array summary.")
        return
    }
    let updatedSummary = try #require(updatedSummaryResult.patternArrays.first { $0.sourceID == source.id })
    let updatedOutput = try #require(updatedSummary.independentCopyOutputs.first)
    let expectedEditedGeneration = try initialGeneration.advanced()

    #expect(commandResult.message == "Cube dimensions updated.")
    #expect(commandResult.commandName == "setCubeDimensions")
    #expect(commandResult.didMutate)
    #expect(commandResult.generation == expectedEditedGeneration)
    #expect(sizeX.sourceKind == .box)
    #expect(abs(sizeX.resolvedMeters - 0.016) < 1.0e-12)
    #expect(abs(sizeY.resolvedMeters - 0.009) < 1.0e-12)
    #expect(abs(sizeZ.resolvedMeters - 0.012) < 1.0e-12)
    #expect(updatedOutput.featureIDs.contains(clone.featureID))
    #expect(updatedOutput.state == .divergedFromSourceDefinition)
    #expect(updatedOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
}

@MainActor
@Test func agentSetsIndependentCopyCloneCylinderDimensionsThroughDiscoveredFeatureID() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedCircle(
            name: "Agent Clone Cylinder",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            depth: .length(8.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Clone Cylinder Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Clone Cylinder Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Clone Cylinder Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Clone Cylinder Array"
    })
    let initialGeneration = session.generation
    server.register(session: session, id: sessionID)

    let clone = try agentIndependentCopyCloneExtrudeFeature(
        server: server,
        sessionID: sessionID,
        sourceID: source.id,
        expectedGeneration: initialGeneration
    )
    let commandResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setCylinderDimensions(
                featureID: clone.featureID,
                radius: .length(7.0, .millimeter),
                sizeY: .length(13.0, .millimeter)
            ),
            expectedGeneration: initialGeneration
        )
    )
    guard case .command(let commandResult) = commandResponse else {
        Issue.record("Agent must return a command result.")
        return
    }

    let dimensionResponse = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [SelectionTarget(sceneNodeID: clone.output.sceneNodeID)],
            expectedGeneration: commandResult.generation
        )
    )
    guard case .objectDimensionSummary(let dimensionSummary) = dimensionResponse else {
        Issue.record("Agent must return an object dimension summary.")
        return
    }
    let radius = try #require(dimensionSummary.entries.first { $0.kind == .radius })
    let sizeY = try #require(dimensionSummary.entries.first { $0.kind == .sizeY })

    let updatedSummaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: commandResult.generation
        )
    )
    guard case .patternArraySummary(let updatedSummaryResult) = updatedSummaryResponse else {
        Issue.record("Agent must return an updated pattern array summary.")
        return
    }
    let updatedSummary = try #require(updatedSummaryResult.patternArrays.first { $0.sourceID == source.id })
    let updatedOutput = try #require(updatedSummary.independentCopyOutputs.first)
    let expectedEditedGeneration = try initialGeneration.advanced()

    #expect(commandResult.message == "Cylinder dimensions updated.")
    #expect(commandResult.commandName == "setCylinderDimensions")
    #expect(commandResult.didMutate)
    #expect(commandResult.generation == expectedEditedGeneration)
    #expect(radius.sourceKind == .cylinder)
    #expect(abs(radius.resolvedMeters - 0.007) < 1.0e-12)
    #expect(abs(sizeY.resolvedMeters - 0.013) < 1.0e-12)
    #expect(updatedOutput.featureIDs.contains(clone.featureID))
    #expect(updatedOutput.state == .divergedFromSourceDefinition)
    #expect(updatedOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
}

@Test func agentListsRegisteredSessions() async throws {
    let server = AgentCommandController(socketPath: "/tmp/rupa.sock")
    let sessionID = UUID()
    server.register(
        session: EditorSession(document: .empty(named: "Open Document")),
        path: URL(fileURLWithPath: "/tmp/open.swcad"),
        id: sessionID
    )

    let response = server.handle(.sessions)

    guard case .sessions(let sessions) = response else {
        #expect(Bool(false))
        return
    }
    #expect(sessions.count == 1)
    #expect(sessions[0].id == sessionID)
    #expect(sessions[0].displayName == "Open Document")
    #expect(sessions[0].generation == DocumentGeneration(0))
}

@Test func agentDispatchesCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Live"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.metadata.name == "Live")
}

@MainActor
@Test func agentProjectsGeneratedEdgeToConstructionPlaneThroughAutomation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Generated Edge Projection Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let supportFace = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.generatedRole == "startFace"
    })
    let supportDepth = try #require(supportFace.center?.z)
    let edge = try #require(topology.entries.first {
        $0.kind == .edge &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.curveKind == "line" &&
            agentTopologyPoint($0.start, isOnDepth: supportDepth) &&
            agentTopologyPoint($0.end, isOnDepth: supportDepth) &&
            $0.selectionTarget() != nil
    })
    let target = try #require(edge.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .projectSketchCurvesToConstructionPlane(
                targets: [target],
                plane: .xy,
                name: "Agent Projected Generated Edge"
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let projected = try #require(summary.entries.first {
        $0.sourceFeatureName == "Agent Projected Generated Edge"
    })

    #expect(result.commandName == "projectSketchCurvesToConstructionPlane")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(projected.entityKind == "line")
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentProjectsBodyOutlineToConstructionPlaneThroughAutomation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Body Outline Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .projectBodyOutlinesToConstructionPlane(
                targets: [SelectionTarget(sceneNodeID: bodyNodeID)],
                plane: .xy,
                name: "Agent Projected Body Outline"
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let projectedEntries = summary.entries.filter {
        $0.sourceFeatureName == "Agent Projected Body Outline"
    }

    #expect(result.commandName == "projectBodyOutlinesToConstructionPlane")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(projectedEntries.count == 4)
    #expect(projectedEntries.allSatisfy { $0.entityKind == "line" })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentProjectsCurvesToGeneratedFaceThroughAutomation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    let lineID = SketchEntityID()
    _ = try session.execute(
        .createSketch(
            name: "Agent Face Projection Source",
            sketch: Sketch(
                plane: .xy,
                entities: [
                    lineID: .line(SketchLine(
                        start: SketchPoint(x: .length(1.0, .millimeter), y: .length(2.0, .millimeter)),
                        end: SketchPoint(x: .length(5.0, .millimeter), y: .length(4.0, .millimeter))
                    )),
                ]
            ),
            geometryRole: .curve
        )
    )
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Face Projection Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(summary.entries.first { $0.entityID == lineID.description })
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let face = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.generatedRole == "endFace" &&
            $0.selectionTarget() != nil
    })
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .projectCurvesToGeneratedFace(
                targets: [try #require(sourceLine.selectionTarget())],
                face: try #require(face.selectionTarget()),
                name: "Agent Face Projected Line"
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let projected = try #require(after.entries.first {
        $0.sourceFeatureName == "Agent Face Projected Line"
    })

    #expect(result.commandName == "projectCurvesToGeneratedFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(projected.entityKind == "line")
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsAndEvaluatesPersistentSelectionDimension() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(16.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let targets = try agentLineEndpointTargets(in: document, featureID: featureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Length",
                kind: .distance,
                first: targets.start,
                second: targets.end,
                target: .length(16.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)
    #expect(addResult.commandName == "addSelectionDimension")
    #expect(addResult.didMutate)
    #expect(session.document.cadDocument.selectionDimensions.map(\.id) == [dimensionID])
    #expect(session.document.productMetadata.measurements.isEmpty)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(evaluation.measurements.count == 1)
    #expect(measurement.dimension.id == dimensionID)
    #expect(measurement.measured == .length(0.016, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(12.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)
    #expect(setResult.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.selectionDimensions.first?.target == .length(12.0, .millimeter))

    let updatedEvaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .selectionDimensionEvaluation(let updatedEvaluation) = updatedEvaluationResponse else {
        #expect(Bool(false))
        return
    }
    let updatedMeasurement = try #require(updatedEvaluation.measurements.first)
    #expect(updatedMeasurement.measured == .length(0.016, unit: .meter))
    #expect(updatedMeasurement.target == .length(0.012, unit: .meter))
    #expect(abs(updatedMeasurement.residual.value - 0.004) <= 1.0e-12)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(applyResult.generation == DocumentGeneration(3))

    let appliedEvaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )

    guard case .selectionDimensionEvaluation(let appliedEvaluation) = appliedEvaluationResponse else {
        #expect(Bool(false))
        return
    }
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    #expect(appliedMeasurement.measured == .length(0.012, unit: .meter))
    #expect(appliedMeasurement.target == .length(0.012, unit: .meter))
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)

    let removeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .removeSelectionDimension(id: dimensionID),
            expectedGeneration: DocumentGeneration(3)
        )
    )

    guard case .command(let removeResult) = removeResponse else {
        #expect(Bool(false))
        return
    }
    #expect(removeResult.commandName == "removeSelectionDimension")
    #expect(removeResult.didMutate)
    #expect(removeResult.generation == DocumentGeneration(4))
    #expect(session.document.cadDocument.selectionDimensions.isEmpty)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToSourcePointDistance() async throws {
    var document = DesignDocument.empty()
    let anchorFeatureID = try document.createLineSketch(
        name: "Agent Anchor Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let editableFeatureID = try document.createLineSketch(
        name: "Agent Editable Point Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let anchorTargets = try agentLineEndpointTargets(in: document, featureID: anchorFeatureID)
    let editableTargets = try agentLineEndpointTargets(in: document, featureID: editableFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Point Distance",
                kind: .distance,
                first: editableTargets.start,
                second: anchorTargets.start,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let editableEndpoints = try agentLineEndpoints(
        in: session.document,
        featureID: editableFeatureID
    )

    #expect(abs(editableEndpoints.start.x - 0.006) <= 1.0e-12)
    #expect(abs(editableEndpoints.start.y) <= 1.0e-12)
    #expect(abs(editableEndpoints.end.x - 0.010) <= 1.0e-12)
    #expect(abs(editableEndpoints.end.y - 0.010) <= 1.0e-12)
    #expect(measurement.measured == .length(0.006, unit: .meter))
    #expect(measurement.target == .length(0.006, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToArcEndpointDistance() async throws {
    var document = DesignDocument.empty()
    let arcFeatureID = try document.createArcSketch(
        name: "Agent Arc Endpoint",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter),
        startAngle: .angle(0.0, .degree),
        endAngle: .angle(90.0, .degree)
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Agent Arc Anchor",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(6.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let arcTargets = try agentArcEndpointTargets(in: document, featureID: arcFeatureID)
    let anchorTargets = try agentLineEndpointTargets(in: document, featureID: anchorFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Arc Endpoint Distance",
                kind: .distance,
                first: arcTargets.start,
                second: anchorTargets.start,
                target: .length(sqrt(72.0), .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)

    #expect(abs(try agentArcStartAngle(in: session.document, featureID: arcFeatureID) - Double.pi / 6.0) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToStandaloneSketchPointDistance() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createAgentStandalonePointSketch(
        in: &document,
        name: "Agent Editable Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Agent Point Anchor",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let pointTarget = try agentStandalonePointTarget(in: document, featureID: pointFeatureID)
    let anchorTargets = try agentLineEndpointTargets(in: document, featureID: anchorFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Standalone Point Distance",
                kind: .distance,
                first: pointTarget,
                second: anchorTargets.start,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let movedPoint = try agentStandalonePoint(in: session.document, featureID: pointFeatureID)

    #expect(abs(movedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(movedPoint.y) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
    guard case .sketchPoint(let point) = measurement.dimension.first else {
        Issue.record("Expected standalone point selection reference")
        return
    }
    #expect(point.featureID == pointFeatureID)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToStandalonePointWholeLineDistance() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createAgentStandalonePointSketch(
        in: &document,
        name: "Agent Editable Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(5.0, .millimeter)
        )
    )
    let lineFeatureID = try document.createLineSketch(
        name: "Agent Reference Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let pointTarget = try agentStandalonePointTarget(in: document, featureID: pointFeatureID)
    let lineTarget = try agentLineCurveTarget(in: document, featureID: lineFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Point To Line Distance",
                kind: .distance,
                first: pointTarget,
                second: lineTarget,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let movedPoint = try agentStandalonePoint(in: session.document, featureID: pointFeatureID)

    #expect(abs(movedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(movedPoint.y - 0.005) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
    guard case .sketchPoint(let point) = measurement.dimension.first,
          case .curve(.whole(let line)) = measurement.dimension.second else {
        Issue.record("Expected standalone point to whole line selection references")
        return
    }
    #expect(point.featureID == pointFeatureID)
    #expect(line.featureID == lineFeatureID)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetByTranslatingLineWhenPointIsFixed() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createAgentStandalonePointSketch(
        in: &document,
        name: "Agent Fixed Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(5.0, .millimeter)
        )
    )
    let lineFeatureID = try document.createLineSketch(
        name: "Agent Movable Reference Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let pointEntityID = try agentStandalonePointEntityID(in: document, featureID: pointFeatureID)
    try document.addSketchConstraint(
        featureID: pointFeatureID,
        constraint: .fixed(.entity(pointEntityID))
    )
    let pointTarget = try agentStandalonePointTarget(in: document, featureID: pointFeatureID)
    let lineTarget = try agentLineCurveTarget(in: document, featureID: lineFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Fixed Point To Line Distance",
                kind: .distance,
                first: pointTarget,
                second: lineTarget,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let fixedPoint = try agentStandalonePoint(in: session.document, featureID: pointFeatureID)
    let movedLine = try agentLineEndpoints(in: session.document, featureID: lineFeatureID)

    #expect(abs(fixedPoint.x - 0.010) <= 1.0e-12)
    #expect(abs(fixedPoint.y - 0.005) <= 1.0e-12)
    #expect(abs(movedLine.start.x - 0.004) <= 1.0e-12)
    #expect(abs(movedLine.start.y) <= 1.0e-12)
    #expect(abs(movedLine.end.x - 0.004) <= 1.0e-12)
    #expect(abs(movedLine.end.y - 0.010) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
    guard case .sketchPoint(let point) = measurement.dimension.first,
          case .curve(.whole(let line)) = measurement.dimension.second else {
        Issue.record("Expected standalone point to whole line selection references")
        return
    }
    #expect(point.featureID == pointFeatureID)
    #expect(line.featureID == lineFeatureID)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToSplineControlPointDistance() async throws {
    var document = DesignDocument.empty()
    let splineFeatureID = try document.createSplineSketch(
        name: "Agent Editable Spline",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
            SketchPoint(x: .length(12.0, .millimeter), y: .length(3.0, .millimeter)),
            SketchPoint(x: .length(14.0, .millimeter), y: .length(3.0, .millimeter)),
            SketchPoint(x: .length(16.0, .millimeter), y: .length(0.0, .millimeter)),
        ])
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Agent Spline Anchor",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let splineTargets = try agentSplineControlPointTargets(in: document, featureID: splineFeatureID)
    let anchorTargets = try agentLineEndpointTargets(in: document, featureID: anchorFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Spline CV Distance",
                kind: .distance,
                first: splineTargets[0],
                second: anchorTargets.start,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let controlPoints = try agentSplineControlPoints(
        in: session.document,
        featureID: splineFeatureID
    )

    #expect(abs(controlPoints[0].x - 0.006) <= 1.0e-12)
    #expect(abs(controlPoints[0].y) <= 1.0e-12)
    #expect(abs(controlPoints[1].x - 0.012) <= 1.0e-12)
    #expect(abs(controlPoints[1].y - 0.003) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToCircleRadius() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createCircleSketch(
        name: "Agent Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter)
    )
    let targets = try agentCircleCenterAndCurveTargets(in: document, featureID: featureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Radius",
                kind: .distance,
                first: targets.center,
                second: targets.curve,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(4.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(abs(try agentCircleRadius(in: session.document, featureID: featureID) - 0.004) <= 1.0e-12)
    #expect(measurement.measured == .length(0.004, unit: .meter))
    #expect(measurement.target == .length(0.004, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToLineRelativeAngle() async throws {
    var document = DesignDocument.empty()
    let referenceFeatureID = try document.createLineSketch(
        name: "Agent Reference Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let editableFeatureID = try document.createLineSketch(
        name: "Agent Editable Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let reference = try agentLineCurveTarget(in: document, featureID: referenceFeatureID)
    let editable = try agentLineCurveTarget(in: document, featureID: editableFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Relative Angle",
                kind: .angle,
                first: editable,
                second: reference,
                target: .angle(90.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .angle(45.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(abs(try agentLineAngle(in: session.document, featureID: editableFeatureID) - Double.pi / 4.0) <= 1.0e-12)
    assertAgentAngleQuantity(measurement.measured, equals: Double.pi / 4.0)
    assertAgentAngleQuantity(measurement.target, equals: Double.pi / 4.0)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAddsAndEvaluatesGeneratedFacePairSelectionDimension() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

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

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Face Distance",
                kind: .distance,
                first: facePair.first,
                second: facePair.second,
                target: .length(facePair.distance, .meter)
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)
    #expect(addResult.commandName == "addSelectionDimension")
    #expect(addResult.didMutate)
    #expect(session.document.cadDocument.selectionDimensions.map(\.id) == [dimensionID])
    #expect(session.document.productMetadata.measurements.isEmpty)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: session.generation
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(evaluation.measurements.count == 1)
    #expect(measurement.dimension.id == dimensionID)
    #expect(abs(measurement.measured.value - facePair.distance) <= 1.0e-12)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesGeneratedFacePairSelectionDimensionTarget() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

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
    let targetDistance = facePair.distance + 0.004

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Editable Face Distance",
                kind: .distance,
                first: facePair.first,
                second: facePair.second,
                target: .length(facePair.distance, .meter)
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(targetDistance, .meter)
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: session.generation
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    assertAgentLengthQuantity(measurement.measured, equals: targetDistance)
    assertAgentLengthQuantity(measurement.target, equals: targetDistance)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@Test func agentCreatesReadsAndActivatesConstructionPlanes() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlane(
                name: "Agent CPlane",
                plane: .yz,
                activates: true
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        #expect(Bool(false))
        return
    }
    #expect(createResult.commandName == "createConstructionPlane")
    #expect(createResult.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first)
    #expect(entry.name == "Agent CPlane")
    #expect(entry.plane == .yz)
    #expect(entry.isActive)
    #expect(summary.activePlaneID == entry.id)
    #expect(entry.sceneNodeID != nil)

    let renameResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameConstructionPlane(
                id: entry.id,
                name: "Agent Renamed CPlane"
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let renameResult) = renameResponse else {
        #expect(Bool(false))
        return
    }
    #expect(renameResult.commandName == "renameConstructionPlane")
    #expect(renameResult.didMutate)

    let renamedSummaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .constructionPlaneSummary(let renamedSummary) = renamedSummaryResponse else {
        #expect(Bool(false))
        return
    }
    let renamedEntry = try #require(renamedSummary.planes.first)
    #expect(renamedEntry.name == "Agent Renamed CPlane")
    let renamedSceneNodeID = try #require(renamedEntry.sceneNodeID)
    #expect(session.document.productMetadata.sceneNodes[renamedSceneNodeID]?.name == "Agent Renamed CPlane")

    let clearResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setActiveConstructionPlane(id: nil),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let clearResult) = clearResponse else {
        #expect(Bool(false))
        return
    }
    #expect(clearResult.commandName == "setActiveConstructionPlane")
    #expect(clearResult.didMutate)
    #expect(session.activeConstructionPlane == nil)
}

@Test func agentCreatesViewAlignedConstructionPlane() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createViewAlignedConstructionPlane(
                name: "Agent View Plane",
                origin: Point3D(x: 0.010, y: 0.020, z: 0.030),
                viewNormal: Vector3D(x: 0.0, y: 3.0, z: 0.0),
                activates: true
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createViewAlignedConstructionPlane")
    #expect(result.didMutate)
    #expect(source.name == "Agent View Plane")
    guard case .plane(let plane) = source.plane else {
        Issue.record("Agent view-aligned construction plane should create a custom plane.")
        return
    }
    #expect(plane.normal == .unitY)
}

@Test func agentCreatesConstructionPlaneFromGeneratedFaceTarget() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let faceTarget = try #require(topology.entries.first {
        $0.kind == .face && $0.center != nil && $0.normal != nil
    }?.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTarget(
                name: "Agent Face CPlane",
                target: faceTarget,
                activates: true
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTarget")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Face CPlane" })
    #expect(entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Generated face target should create a custom construction plane.")
        return
    }
}

@Test func agentCreatesMidplaneConstructionPlaneFromGeneratedFaceTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let targets = try agentParallelFaceTargets(in: topology)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Midplane",
                targets: targets,
                viewNormal: nil,
                activates: true
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Midplane" })
    #expect(entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Parallel generated face targets should create a custom midplane.")
        return
    }
}

@Test func agentCreatesTwoPointConstructionPlaneFromGeneratedVertexTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let targets = try agentTwoPointVertexTargets(in: topology, viewNormal: .unitZ)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Two Point Plane",
                targets: targets,
                viewNormal: .unitZ,
                activates: true
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Two Point Plane" })
    #expect(entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Two generated vertex targets should create a custom construction plane.")
        return
    }
}

@Test func agentCreatesTwoPointConstructionPlaneFromSourcePointTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentSourcePointSession()
    let session = setup.session
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Source Point Plane",
                targets: setup.targets,
                viewNormal: .unitZ,
                activates: true
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Source Point Plane" })
    #expect(entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Two source point targets should create a custom construction plane.")
        return
    }
}

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

@Test func agentDispatchesFaceOffsetCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetBodyFace(
                target: SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceTop)),
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyFaceOffsetCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "sideFace"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetBodyFace(
                target: target,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesFaceKnifeCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createFaceKnife(
                name: "Agent Face Knife",
                target: target,
                loop: [
                    Point3D(x: -0.004, y: -0.002, z: 0.0),
                    Point3D(x: 0.004, y: -0.002, z: 0.0),
                    Point3D(x: 0.004, y: 0.002, z: 0.0),
                    Point3D(x: -0.004, y: 0.002, z: 0.0),
                ]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let faceKnifeFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let faceKnifeSceneNodeID = try #require(agentSceneNodeID(for: faceKnifeFeatureID, in: session.document))
    let feature = try #require(session.document.cadDocument.designGraph.nodes[faceKnifeFeatureID])
    guard case .faceKnife = feature.operation else {
        Issue.record("Agent Face Knife command must create a FaceKnife feature.")
        return
    }
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let faceKnifeFaces = afterTopology.entries.filter {
        $0.kind == .face && $0.sceneNodeID == faceKnifeSceneNodeID.description
    }

    #expect(result.commandName == "createFaceKnife")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(faceKnifeFaces.count == 7)
    #expect(faceKnifeFaces.contains {
        $0.generatedRole == "faceKnife" && $0.subshapeRole == "centerFace"
    })
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyEdgeOffsetCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(
                    gapFill: .linear,
                    supportTarget: supportFaceTarget
                ),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent Offset Curve edge target must create an EdgeOffset feature.")
        return
    }
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = afterTopology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.gapFill == .linear)
    #expect(afterTopology.counts.faceCount == 7)
    #expect(afterTopology.counts.edgeCount == 15)
    #expect(afterTopology.counts.vertexCount == 10)
    #expect(generatedOffsetEdges.count == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesOffsetEdgeUsingSelectedSupportFaceContext() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [supportFaceTarget, edgeTarget],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selectionResult) = selectionResponse else {
        Issue.record("Agent must return a selection result before Offset Edge.")
        return
    }
    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .linear),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent Offset Curve edge target must create an EdgeOffset feature from selection context.")
        return
    }
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = afterTopology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(selectionResult.selectedTargets == [supportFaceTarget, edgeTarget])
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.gapFill == .linear)
    #expect(generatedOffsetEdges.count == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesOffsetEdgeUsingSingleSelectedCapEdgeContext() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [edgeTarget],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selectionResult) = selectionResponse else {
        Issue.record("Agent must return a single edge selection result before Offset Edge.")
        return
    }
    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .linear),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent Offset Curve edge target must create an EdgeOffset feature from cap edge context.")
        return
    }
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = afterTopology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(selectionResult.selectedTargets == [edgeTarget])
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.supportFacePersistentName.components == [
        .feature(bodyFeatureID),
        .generated(GeneratedSubshapeRole.startFace.rawValue),
    ])
    #expect(edgeOffset.gapFill == .linear)
    #expect(generatedOffsetEdges.count == 1)
    #expect(session.evaluationStatus == .valid)
}

@Test func agentOffsetsGeneratedCylinderSideFaceThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let beforeRadius = try agentCylinderRadius(forBody: bodyFeatureID, in: session.document)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.surfaceKind == "cylinder"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetBodyFace(
                target: target,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(nearlyEqualAgent(try agentCylinderRadius(forBody: bodyFeatureID, in: session.document), beforeRadius + 0.001))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesEdgeChamferCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .chamferBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeLeftTop)),
                ],
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesEdgeFilletCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightBottom)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyEdgeFilletCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsLineArcProfileCornerThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcExtrudedSession()
    let session = setup.session
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: 2.0, y: 0.0)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(100.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsArcArcProfileCornerThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentArcArcExtrudedSession()
    let session = setup.session
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: 0.0, y: 0.0)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(100.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsGeneratedEdgeAfterPriorChamferThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let chamferResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .chamferBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let chamferResult) = chamferResponse else {
        #expect(Bool(false))
        return
    }
    #expect(chamferResult.commandName == "chamferBodyEdges")
    #expect(chamferResult.didMutate)
    #expect(chamferResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let filletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(0.25, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let filletResult) = filletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(filletResult.commandName == "filletBodyEdges")
    #expect(filletResult.didMutate)
    #expect(filletResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsSharpGeneratedEdgeAfterPriorFilletThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let firstFilletResponse = server.handle(
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
    guard case .command(let firstFilletResult) = firstFilletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(firstFilletResult.commandName == "filletBodyEdges")
    #expect(firstFilletResult.didMutate)
    #expect(firstFilletResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: -0.020, y: -0.010)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let secondFilletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(0.5, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let secondFilletResult) = secondFilletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(secondFilletResult.commandName == "filletBodyEdges")
    #expect(secondFilletResult.didMutate)
    #expect(secondFilletResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentChamfersArcAdjacentGeneratedEdgeAfterPriorFilletThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let firstFilletResponse = server.handle(
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
    guard case .command(let firstFilletResult) = firstFilletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(firstFilletResult.commandName == "filletBodyEdges")
    #expect(firstFilletResult.didMutate)
    #expect(firstFilletResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: 0.020, y: 0.009)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let chamferResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .chamferBodyEdges(
                targets: [target],
                distance: .length(0.25, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let chamferResult) = chamferResponse else {
        #expect(Bool(false))
        return
    }
    #expect(chamferResult.commandName == "chamferBodyEdges")
    #expect(chamferResult.didMutate)
    #expect(chamferResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyVertexMoveCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first { $0.kind == .vertex })
    let target = try #require(vertexEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveBodyVertex(
                target: target,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(result.commandName == "moveBodyVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentMovesSharpGeneratedVertexAfterPriorFilletThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

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
    guard case .command(let filletResult) = filletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(filletResult.commandName == "filletBodyEdges")
    #expect(filletResult.didMutate)
    #expect(filletResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first {
        isAgentGeneratedVertex($0, x: -0.020, y: -0.010)
    })
    let target = try #require(vertexEntry.selectionTarget())

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveBodyVertex(
                target: target,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.5, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(moveResult.commandName == "moveBodyVertex")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesCornerFootprintModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangleFromCorners(
                name: "Agent Footprint Box",
                plane: .xy,
                firstCorner: SketchPoint(
                    x: .length(1.0, .millimeter),
                    y: .length(2.0, .millimeter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(5.0, .millimeter),
                    y: .length(8.0, .millimeter)
                ),
                depth: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func agentDispatchesComponentCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Component",
                rootSceneNodeIDs: []
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let definitionResult) = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let instanceResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentInstance(
                name: "Agent Component A",
                definitionID: definition.id,
                localTransform: .identity
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let instanceResult) = instanceResponse else {
        #expect(Bool(false))
        return
    }

    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let sceneNode = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .componentInstance(instance.id)
        }
    )
    let sceneNodeTransform = try agentTranslationTransform(x: 0.2, y: 0.0, z: 0.1)
    let transformResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSceneNodeTransform(
                id: sceneNode.id,
                localTransform: sceneNodeTransform
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let transformResult) = transformResponse else {
        #expect(Bool(false))
        return
    }

    #expect(definitionResult.commandName == "createComponentDefinition")
    #expect(instanceResult.commandName == "createComponentInstance")
    #expect(instanceResult.generation == DocumentGeneration(2))
    #expect(transformResult.commandName == "setSceneNodeTransform")
    #expect(transformResult.generation == DocumentGeneration(3))
    #expect(instance.definitionID == definition.id)
    #expect(session.document.productMetadata.sceneNodes[sceneNode.id]?.localTransform == sceneNodeTransform)
}

@MainActor
@Test func agentDispatchesRectangularPatternArrayThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Array Source",
                rootSceneNodeIDs: [bodySceneNodeID]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Rectangular Array",
                definitionID: definition.id,
                distribution: .rectangular(
                    RectangularPatternArray(
                        firstAxis: PatternArrayLinearAxis(
                            direction: .unitX,
                            distance: .length(12.0, .millimeter),
                            copyCount: 3,
                            distanceMode: .spacing
                        ),
                        secondAxis: PatternArrayLinearAxis(
                            direction: .unitZ,
                            distance: .length(30.0, .millimeter),
                            copyCount: 2,
                            distanceMode: .extent
                        )
                    )
                ),
                outputMode: .componentInstance
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let arrayResult) = arrayResponse else {
        #expect(Bool(false))
        return
    }

    let source = try #require(session.document.productMetadata.patternArrays.values.first)
    let firstInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[0]]
    )
    let fourthInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[3]]
    )

    #expect(arrayResult.commandName == "createPatternArray")
    #expect(arrayResult.generation == DocumentGeneration(3))
    #expect(source.outputInstanceIDs.count == 11)
    #expect(firstInstance.localTransform.matrix.values[12] == 0.012)
    #expect(fourthInstance.localTransform.matrix.values[12] == 0.0)
    #expect(fourthInstance.localTransform.matrix.values[14] == 0.015)
}

@Test func agentRejectsDirectEditsToPatternOwnedComponentInstances() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Owned Instance Source",
                rootSceneNodeIDs: [bodySceneNodeID]
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Owned Instance Source"
    })

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Owned Instance Array",
                definitionID: definition.id,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(10.0, .millimeter),
                        copyCount: 1
                    )
                )),
                outputMode: .componentInstance
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command = arrayResponse else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Owned Instance Array"
    })
    let outputInstanceID = try #require(source.outputInstanceIDs.first)
    let generationBeforeRejectedEdits = session.generation
    let rejectedCommands: [(AutomationCommand, String)] = [
        (
            .setComponentInstanceVisibility(id: outputInstanceID, isVisible: false),
            "visibility is controlled by the pattern source"
        ),
        (
            .setComponentInstanceLock(id: outputInstanceID, isLocked: true),
            "locks are controlled by the pattern source"
        ),
        (
            .setComponentInstanceTransform(
                id: outputInstanceID,
                localTransform: try agentTranslationTransform(x: 0.01, y: 0.0, z: 0.0)
            ),
            "transforms are controlled by the pattern source"
        ),
    ]

    for (command, expectedMessageFragment) in rejectedCommands {
        let response = server.handle(
            .execute(
                sessionID: sessionID,
                command: command,
                expectedGeneration: generationBeforeRejectedEdits
            )
        )
        guard case .failure(let error) = response else {
            #expect(Bool(false))
            return
        }
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains(expectedMessageFragment))
        #expect(session.generation == generationBeforeRejectedEdits)
    }
}

@Test func agentDispatchesRadialPatternArrayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Radial Array Body",
                plane: .xy,
                width: .length(10.0, .millimeter),
                height: .length(6.0, .millimeter),
                depth: .length(4.0, .millimeter),
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
    let bodySceneNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Radial Source",
                rootSceneNodeIDs: [bodySceneNode.id]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Radial Array",
                definitionID: definition.id,
                distribution: .radial(
                    RadialPatternArray(
                        angularAxis: PatternArrayAngularAxis(
                            center: .origin,
                            axis: .unitZ,
                            angle: .angle(90.0, .degree),
                            copyCount: 3,
                            angleMode: .spacing
                        )
                    )
                ),
                outputMode: .componentInstance
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let arrayResult) = arrayResponse else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Radial Array"
    })

    #expect(arrayResult.commandName == "createPatternArray")
    #expect(arrayResult.generation == DocumentGeneration(3))
    #expect(source.outputInstanceIDs.count == 3)
}

@Test func agentDispatchesCurvePatternArrayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Curve Array Body",
                plane: .xy,
                width: .length(10.0, .millimeter),
                height: .length(6.0, .millimeter),
                depth: .length(4.0, .millimeter),
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
    let bodySceneNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Curve Source",
                rootSceneNodeIDs: [bodySceneNode.id]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Curve Array",
                definitionID: definition.id,
                distribution: .curve(
                    CurvePatternArray(
                        path: .polyline(
                            points: [
                                .origin,
                                Point3D(x: 0.03, y: 0.0, z: 0.0),
                            ],
                            normal: .unitZ
                        ),
                        copyCount: 3,
                        alignment: .parallel
                    )
                ),
                outputMode: .componentInstance
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let arrayResult) = arrayResponse else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Curve Array"
    })

    #expect(arrayResult.commandName == "createPatternArray")
    #expect(arrayResult.generation == DocumentGeneration(3))
    #expect(source.outputInstanceIDs.count == 3)
}

@Test func agentDispatchesPatternArrayLifecycleCommandsThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Array Lifecycle Body",
                plane: .xy,
                width: .length(10.0, .millimeter),
                height: .length(6.0, .millimeter),
                depth: .length(4.0, .millimeter),
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
    let bodySceneNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Lifecycle Source",
                rootSceneNodeIDs: [bodySceneNode.id]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Lifecycle Array",
                definitionID: definition.id,
                distribution: .rectangular(
                    RectangularPatternArray(
                        firstAxis: PatternArrayLinearAxis(
                            direction: .unitX,
                            distance: .length(6.0, .millimeter),
                            copyCount: 2
                        )
                    )
                ),
                outputMode: .componentInstance
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command = arrayResponse else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Lifecycle Array"
    })
    let firstOutputID = try #require(source.outputInstanceIDs.first)

    let updateResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .updatePatternArray(
                id: source.id,
                name: "Agent Updated Array",
                definitionID: nil,
                distribution: .rectangular(
                    RectangularPatternArray(
                        firstAxis: PatternArrayLinearAxis(
                            direction: .unitX,
                            distance: .length(12.0, .millimeter),
                            copyCount: 1
                        )
                    )
                ),
                outputMode: nil
            ),
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .command(let updateResult) = updateResponse else {
        #expect(Bool(false))
        return
    }
    let updatedSource = try #require(session.document.productMetadata.patternArrays[source.id])

    let explodeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .explodePatternArray(id: source.id),
            expectedGeneration: DocumentGeneration(4)
        )
    )
    guard case .command(let explodeResult) = explodeResponse else {
        #expect(Bool(false))
        return
    }
    let outputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )
    let outputFeatureID = try #require(
        agentFeatureID(
            inSceneSubtreeRootedAt: outputSceneNodeID,
            document: session.document
        )
    )

    #expect(updateResult.commandName == "updatePatternArray")
    #expect(updateResult.generation == DocumentGeneration(4))
    #expect(updatedSource.name == "Agent Updated Array")
    #expect(updatedSource.outputInstanceIDs == [firstOutputID])
    #expect(explodeResult.commandName == "explodePatternArray")
    #expect(explodeResult.generation == DocumentGeneration(5))
    #expect(session.document.productMetadata.patternArrays[source.id] == nil)
    #expect(session.document.productMetadata.componentInstances[firstOutputID] == nil)
    #expect(session.document.cadDocument.designGraph.nodes[outputFeatureID] != nil)
}

@Test func agentDispatchesCircleModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedCircle(
                name: "Agent Cylinder",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(6.0, .millimeter),
                depth: .length(10.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedCircle")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@Test func agentDispatchesSketchPrimitiveCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createCircleSketch(
                name: "Agent Circle",
                plane: .xy,
                center: SketchPoint(
                    x: .length(2.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                radius: .length(4.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createCircleSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@Test func agentDispatchesCurveCurvatureDisplayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createCircleSketch(
                name: "Agent Curvature Display Circle",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(5.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(summary.entries.first { $0.entityKind == "circle" })
    let target = try #require(circle.selectionTarget())
    let componentID = try #require(agentSketchEntityComponentID(from: target))

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setCurveCurvatureDisplay(
                target: target,
                isVisible: true,
                combScale: 0.2
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setCurveCurvatureDisplay")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.curveCurvatureDisplays[componentID]?.combScale == 0.2)
}

@Test func agentDispatchesPointDisplayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Point Display Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                    SketchPoint(x: .length(0.002, .meter), y: .length(0.004, .meter)),
                    SketchPoint(x: .length(0.006, .meter), y: .length(0.004, .meter)),
                    SketchPoint(x: .length(0.008, .meter), y: .length(0.0, .meter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let componentID = try #require(agentSketchEntityComponentID(from: target))

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setPointDisplay(
                target: target,
                isVisible: false
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setPointDisplay")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.pointDisplays[componentID]?.isVisible == false)
}

@Test func agentDispatchesPolygonSketchCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolygonSketch(
                name: "Agent Polygon",
                plane: .xy,
                center: SketchPoint(
                    x: .length(2.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                radius: .length(4.0, .millimeter),
                sides: 5,
                sizingMode: .inradius,
                inclinationMode: .vertical,
                rotationAngle: .angle(0.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createPolygonSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.entities.count == 5)
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    let polygonNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    #expect(polygonNode.object?.properties["radius.is.inradius"] == .boolean(true))
    #expect(polygonNode.object?.properties["inclination.mode"] == .text(PolygonInclinationMode.vertical.rawValue))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@Test func agentDispatchesArcSketchCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createArcSketch(
                name: "Agent Arc",
                plane: .xy,
                center: SketchPoint(
                    x: .length(2.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                radius: .length(4.0, .millimeter),
                startAngle: .angle(0.0, .degree),
                endAngle: .angle(135.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    let entity = try #require(sketch.entities.values.first)
    guard case .arc = entity else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createArcSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@MainActor
@Test func agentDispatchesSketchConstraintCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Constraint Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let lineID = try #require(agentSingleSketchEntityID(in: session.document, featureID: featureID))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: featureID,
                constraint: .horizontal(lineID)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(agentSketchFeature(in: session.document, featureID: featureID))
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityID == lineID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(sketch.constraints == [.horizontal(lineID)])
    #expect(abs((line.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((line.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesSketchConstraintRemovalCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Constraint Removal Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let lineID = try #require(agentSingleSketchEntityID(in: session.document, featureID: featureID))
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(lineID)
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .removeSketchConstraint(
                featureID: featureID,
                constraint: .horizontal(lineID)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(agentSketchFeature(in: session.document, featureID: featureID))
    #expect(result.commandName == "removeSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(sketch.constraints.isEmpty)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesFixedSplineControlPointConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Fixed Spline Point",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: featureID,
                constraint: .fixed(.splineControlPoint(entity: entityID, index: 0))
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: 0,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .failure(let error) = moveResponse else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .commandInvalid)
    #expect(error.message == "Sketch spline control point move cannot move a fixed sketch point.")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSlideSketchSplineControlPointsThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Slide CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .slideSketchSplineControlPoints(
                target: target,
                controlPointIndexes: [1, 2],
                direction: .normal,
                distance: .length(1.5, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    #expect(result.commandName == "slideSketchSplineControlPoints")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(updatedSpline.controlPoints[1].x - 0.002) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].y - 0.0015) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].x - 0.006) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].y - 0.0015) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesCoincidentSplineControlPointConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentSplinePointConstraintDocument(name: "Agent Coincident Spline Point")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .coincident(
                    .splineControlPoint(entity: setup.splineID, index: 0),
                    .entity(setup.pointID)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let point = try #require(summary.entries.first { $0.entityID == setup.pointID.description })
    let center = try #require(point.center)
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs(center.x - 0.0) < 1.0e-12)
    #expect(abs(center.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSmoothSplineControlPointConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Smooth Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(1.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(4.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: featureID,
                constraint: .smoothSplineControlPoint(entity: entityID, index: 3)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    let outgoingHandle = try #require(updatedSpline.controlPoints.dropFirst(4).first)
    let constraint = try #require(updatedSpline.constraints.first { $0.kind == "smoothSplineControlPoint" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(constraint.references == ["splineControlPoint:\(entityID.description):3"])
    #expect(abs(outgoingHandle.x - 0.005) < 1.0e-12)
    #expect(abs(outgoingHandle.y - (-0.001)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSplineEndpointTangentConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentSplineLineTangentSketchDocument(name: "Agent Spline Tangency")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .splineEndpointTangent(
                    spline: setup.splineID,
                    endpoint: .start,
                    line: setup.lineID
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityID == setup.splineID.description })
    let alignedHandle = try #require(spline.controlPoints.dropFirst(1).first)
    let constraint = try #require(spline.constraints.first { $0.kind == "splineEndpointTangent" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.splineID.description):start",
        "entity:\(setup.lineID.description)",
    ])
    #expect(abs(alignedHandle.x - 0.005) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesTangentSplineEndpointsConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoSplineTangentSketchDocument(name: "Agent Spline Endpoint Tangency")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .tangentSplineEndpoints(
                    first: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
                    second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(summary.entries.first { $0.entityID == setup.secondSplineID.description })
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    let constraint = try #require(secondSpline.constraints.first { $0.kind == "tangentSplineEndpoints" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.firstSplineID.description):end",
        "splineEndpoint:\(setup.secondSplineID.description):start",
    ])
    #expect(abs(alignedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSmoothSplineEndpointsConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoSplineTangentSketchDocument(name: "Agent Spline Endpoint Smoothness")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .smoothSplineEndpoints(
                    first: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
                    second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(summary.entries.first { $0.entityID == setup.secondSplineID.description })
    let alignedEndpoint = try #require(secondSpline.controlPoints.first)
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    let constraint = try #require(secondSpline.constraints.first { $0.kind == "smoothSplineEndpoints" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.firstSplineID.description):end",
        "splineEndpoint:\(setup.secondSplineID.description):start",
    ])
    #expect(abs(alignedEndpoint.x - 0.009) < 1.0e-12)
    #expect(abs(alignedEndpoint.y - 0.0) < 1.0e-12)
    #expect(abs(alignedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsParallelConstraintAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Parallel Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .parallel(setup.firstLineID, setup.secondLineID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let first = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let second = try #require(summary.entries.first { $0.entityID == setup.secondLineID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(agentLineEntriesAreParallel(first, second))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsEqualLengthConstraintAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Equal Length Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .equalLength(setup.firstLineID, setup.secondLineID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let first = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let second = try #require(summary.entries.first { $0.entityID == setup.secondLineID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs(agentLineEntryLength(first) - agentLineEntryLength(second)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsTangentConstraintAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineCircleTangentSketchDocument(name: "Agent Tangent Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .tangent(setup.lineID, setup.circleID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(summary.entries.first { $0.entityID == setup.circleID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs((circle.center?.x ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((circle.center?.y ?? -1.0) - (circle.radius ?? -2.0)) < 1.0e-12)
    #expect(abs((circle.radius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsCircularConstraintsAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoCircleSketchDocument(name: "Agent Circular Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let concentricResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .concentric(setup.firstCircleID, setup.secondCircleID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let radiusResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .equalRadius(setup.firstCircleID, setup.secondCircleID)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let concentricResult) = concentricResponse,
          case .command(let radiusResult) = radiusResponse else {
        Issue.record("Agent must return command results.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let first = try #require(summary.entries.first { $0.entityID == setup.firstCircleID.description })
    let second = try #require(summary.entries.first { $0.entityID == setup.secondCircleID.description })
    #expect(concentricResult.commandName == "addSketchConstraint")
    #expect(radiusResult.commandName == "addSketchConstraint")
    #expect(concentricResult.didMutate)
    #expect(radiusResult.didMutate)
    #expect(abs((first.center?.x ?? -1.0) - (second.center?.x ?? -2.0)) < 1.0e-12)
    #expect(abs((first.center?.y ?? -1.0) - (second.center?.y ?? -2.0)) < 1.0e-12)
    #expect(abs((first.radius ?? -1.0) - (second.radius ?? -2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsParameterExpressionAndListsParameters() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, id: sessionID)

    let commandResponse = server.handle(
        .setParameterExpression(
            sessionID: sessionID,
            name: "height",
            expression: "width * 2",
            kind: .length,
            defaults: ParameterExpressionDefaults(),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let result) = commandResponse else {
        #expect(Bool(false))
        return
    }

    let listResponse = server.handle(
        .parameters(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .parameters(let parameterList) = listResponse else {
        #expect(Bool(false))
        return
    }
    let height = try #require(parameterList.parameters.first { $0.name == "height" })

    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(parameterList.parameters.count == 2)
    #expect(height.expression == "(width * 2)")
    #expect(abs((height.resolvedValue ?? 0.0) - 0.02) < 0.000_000_000_001)
}

@MainActor
@Test func agentDeletesParameterThroughAutomationCommand() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .deleteParameter(name: "width"),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }

    #expect(result.commandName == "deleteParameter")
    #expect(result.message == "Parameter width deleted.")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.parameters.parameters.isEmpty)
}

@MainActor
@Test func agentEvaluatesOpenSessionWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Eval Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .evaluate(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .evaluation(let snapshot) = response else {
        #expect(Bool(false))
        return
    }
    #expect(snapshot.status == .valid)
    #expect(snapshot.evaluatedGeneration == DocumentGeneration(1))
    #expect(snapshot.bodyCount == 1)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentMeasuresOpenSessionWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Measure Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .measurement(let measurement) = response else {
        #expect(Bool(false))
        return
    }
    #expect(measurement.counts.sourceFeatures == 2)
    #expect(measurement.counts.solids == 1)
    #expect(abs(measurement.totals.profileAreaSquareMeters - 0.0002) < 0.000_000_000_001)
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.000006) < 0.000_000_000_001)
    let solid = try #require(measurement.solids.first)
    let height = try #require(solid.linearDimensions.first { $0.kind == .extrusionHeight })
    #expect(abs(height.meters - 0.03) < 0.000_000_000_001)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentMeasuresGeneratedEdgeOffsetDirectEditSolidWithoutDoubleCountingSourceBody() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(
                    gapFill: .linear,
                    supportTarget: supportFaceTarget
                ),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let offsetResult) = offsetResponse else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let measureResponse = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .measurement(let measurement) = measureResponse else {
        #expect(Bool(false))
        return
    }
    let solid = try #require(measurement.solids.first)
    let surfaceArea = try #require(solid.surfaceAreaSquareMeters)
    #expect(offsetResult.didMutate)
    #expect(offsetResult.generation == DocumentGeneration(2))
    #expect(measurement.counts.sourceFeatures == 3)
    #expect(measurement.counts.solids == 1)
    #expect(solid.featureID == offsetFeatureID.description)
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.000008) < 1.0e-12)
    #expect(surfaceArea > 0.0)
    #expect(measurement.diagnostics.contains { $0.message.contains("Offset Edge") } == false)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentExecutesSymmetricGeneratedEdgeOffsetDirectEditSolid() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(
                    isSymmetric: true,
                    gapFill: .linear,
                    supportTarget: supportFaceTarget
                ),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let offsetResult) = offsetResponse else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent symmetric Offset Edge must create an EdgeOffset feature.")
        return
    }

    let measuredResponse = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .measurement(let measurement) = measuredResponse else {
        #expect(Bool(false))
        return
    }
    let evaluatedTopology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = evaluatedTopology.entries.filter { entry in
        entry.kind == .edge &&
            entry.sourceFeatureID == offsetFeatureID.description &&
            entry.generatedRole == "edgeOffset" &&
            entry.subshapeRole == "offsetEdge"
    }

    #expect(offsetResult.didMutate)
    #expect(offsetResult.generation == DocumentGeneration(2))
    #expect(edgeOffset.isSymmetric)
    #expect(measurement.counts.sourceFeatures == 3)
    #expect(measurement.counts.solids == 1)
    #expect(measurement.diagnostics.contains { $0.message.contains("Offset Edge") } == false)
    #expect(generatedOffsetEdges.count == 2)
    #expect(evaluatedTopology.counts.faceCount == 8)
    #expect(evaluatedTopology.counts.edgeCount == 18)
    #expect(evaluatedTopology.counts.vertexCount == 12)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func agentMeasuresSelectedOpenSessionBodyWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Selected Measure Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    #expect(session.selectSceneNode(bodyNodeID))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .measurement(let measurement) = response else {
        #expect(Bool(false))
        return
    }
    #expect(measurement.scope == .selection)
    #expect(measurement.counts.sourceFeatures == 2)
    #expect(measurement.counts.solids == 1)
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.000006) < 0.000_000_000_001)
    let solid = try #require(measurement.solids.first)
    let height = try #require(solid.linearDimensions.first { $0.kind == .extrusionHeight })
    #expect(abs(height.meters - 0.03) < 0.000_000_000_001)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesOpenSessionMeshesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Mesh Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .meshSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .meshSummary(let meshSummary) = response else {
        #expect(Bool(false))
        return
    }
    let bounds = try #require(meshSummary.bounds)
    #expect(meshSummary.bodyCount == 1)
    #expect(meshSummary.vertexCount > 0)
    #expect(meshSummary.triangleCount > 0)
    #expect(meshSummary.indexedElementCount == meshSummary.triangleCount * 3)
    #expect(abs(bounds.sizeX - 0.01) < 0.000_000_000_001)
    #expect(abs(bounds.sizeY - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeZ - 0.03) < 0.000_000_000_001)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesOpenSessionSketchEntitiesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Guide Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(8.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .sketchEntitySummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.sketchCount == 1)
    #expect(summary.counts.entityCount == 1)
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    #expect(abs((arc.radius ?? -1.0) - 0.008) < 0.000_000_001)
    #expect(abs((arc.end?.y ?? -1.0) - 0.008) < 0.000_000_001)
    let target = try #require(arc.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selection) = selectionResponse else {
        #expect(Bool(false))
        return
    }
    #expect(selection.selectedTargets == [target])
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesSelectsAndOffsetsRoundRegionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Agent Selectable Region",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch summary containing regions.")
        return
    }
    #expect(summary.counts.regionCount == 1)
    let region = try #require(summary.regions.first)
    #expect(abs(region.areaSquareMeters - 0.000_06) < 1.0e-12)
    let target = try #require(region.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selection) = selectionResponse else {
        Issue.record("Agent must select a region target.")
        return
    }
    #expect(selection.selectedTargets == [target])

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for a round region offset.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != region.sourceFeatureID })
    let offsetEntries = after.entries.filter { $0.sourceFeatureID == offsetRegion.sourceFeatureID }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.areaSquareMeters > 0.000_095)
    #expect(offsetRegion.areaSquareMeters < 0.000_096)
    #expect(offsetEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(offsetEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSymmetricNaturalRegionOffset() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Agent Round Region Gap Fill",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let region = try #require(summary.regions.first)
    let target = try #require(region.selectionTarget())
    server.register(session: session, id: sessionID)

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(isSymmetric: true, gapFill: .natural),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for symmetric Offset Region.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegions = after.regions.filter { $0.sourceFeatureID != region.sourceFeatureID }
    let areas = offsetRegions.map(\.areaSquareMeters).sorted()
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(after.counts.regionCount == 3)
    #expect(abs((areas.first ?? 0.0) - 0.000_032) < 1.0e-12)
    #expect(abs((areas.last ?? 0.0) - 0.000_096) < 1.0e-12)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesNaturalOffsetForConcaveSourceRegion() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentConcaveLineLoopDocument())
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch summary containing a concave region.")
        return
    }
    let region = try #require(summary.regions.first)
    let target = try #require(region.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .natural),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for a concave region offset.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != region.sourceFeatureID })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.boundaryPointCount == 6)
    #expect(offsetRegion.boundarySegmentCount == 6)
    #expect(abs(offsetRegion.areaSquareMeters - 0.000_108) < 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesRoundOffsetForConcaveSourceRegion() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentConcaveLineLoopDocument())
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch summary containing a concave region.")
        return
    }
    let region = try #require(summary.regions.first)
    let target = try #require(region.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for a round concave region offset.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != region.sourceFeatureID })
    let offsetEntries = after.entries.filter { $0.sourceFeatureID == offsetRegion.sourceFeatureID }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.boundaryPointCount > 11)
    #expect(offsetRegion.boundarySegmentCount == 11)
    #expect(offsetRegion.areaSquareMeters > 0.000_105_5)
    #expect(offsetRegion.areaSquareMeters < 0.000_108)
    #expect(offsetEntries.filter { $0.entityKind == "line" }.count == 6)
    #expect(offsetEntries.filter { $0.entityKind == "arc" }.count == 5)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesCombinedOffsetRegions() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Combined Region A",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Combined Region B",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(11.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(21.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targets = try before.regions.map { region in
        try #require(region.selectionTarget())
    }
    server.register(session: session, id: sessionID)

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetRegions(
                targets: targets,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .natural),
                combinesRegions: true
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetRegions command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let newSketches = after.sketches.filter { sketch in
        before.sketches.contains { $0.sourceFeatureID == sketch.sourceFeatureID } == false
    }
    let newRegions = after.regions.filter { region in
        before.regions.contains { $0.sourceFeatureID == region.sourceFeatureID } == false
    }
    #expect(result.commandName == "offsetRegions")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(newSketches.count == 1)
    #expect(newRegions.count == 1)
    let unionRegion = try #require(newRegions.first)
    #expect(unionRegion.boundaryPointCount == 4)
    #expect(unionRegion.boundarySegmentCount == 4)
    #expect(abs(unionRegion.areaSquareMeters - 0.000_184) < 1.0e-12)
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.3, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.01031, y: 0.00002),
            options: SnapResolutionOptions(
                usesGrid: true,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 4
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .lineEnd)
    #expect(result.selectedCandidate?.source?.selectionTarget != nil)
    #expect(abs(result.resolvedPoint.x - 0.0103) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(result.candidates.contains { $0.kind == .grid })
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesMeasurementSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    var document = DesignDocument.empty()
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Agent Measured Gap",
            kind: .distance,
            anchors: [
                .worldPoint(Point3D(x: 0.002, y: 0.003, z: 0.0), role: .start),
                .worldPoint(Point3D(x: 0.009, y: 0.003, z: 0.0), role: .end),
            ]
        )
    )
    let measurement = try #require(document.productMetadata.measurements[measurementID])
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00201, y: 0.00301),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a measurement snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(result.selectedCandidate?.kind == .measurementPoint)
    #expect(candidate.measurementSource?.sceneNodeID == measurement.sceneNodeID)
    #expect(candidate.measurementSource?.name == "Agent Measured Gap")
    #expect(candidate.measurementSource?.role == .start)
    #expect(abs(result.resolvedPoint.x - 0.002) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.003) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.canUndo == false)
}

@MainActor
@Test func agentResolvesSketchReferenceMeasurementSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Measured Source Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation,
          let lineEntry = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          }) else {
        Issue.record("Agent measurement snap test requires a line sketch.")
        return
    }
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Agent Source Measurement",
            kind: .distance,
            anchors: [
                .sketchReference(featureID: featureID, reference: .lineEnd(lineEntry.key), role: .end),
                .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .start),
            ]
        )
    )
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.01001, y: 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 12
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a sketch-reference measurement snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(candidate.measurementSource?.anchorKind == .sketchReference)
    #expect(candidate.measurementSource?.sketchReference?.featureID == featureID)
    #expect(candidate.measurementSource?.sketchReference?.reference == .lineEnd(lineEntry.key))
    #expect(abs((candidate.measurementSource?.worldPoint.x ?? 0.0) - 0.010) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.canUndo == false)
}

@MainActor
@Test func agentResolvesSketchCurveParameterMeasurementSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Measured Source Curve Parameter",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation,
          let lineEntry = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          }) else {
        Issue.record("Agent measurement snap test requires a line sketch.")
        return
    }
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Agent Source Curve Parameter Measurement",
            kind: .distance,
            anchors: [
                .sketchCurveParameter(featureID: featureID, entityID: lineEntry.key, parameter: 0.5, role: .point),
                .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .start),
            ]
        )
    )
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00501, y: 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 12
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a sketch-curve-parameter measurement snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(candidate.measurementSource?.anchorKind == .sketchCurveParameter)
    #expect(candidate.measurementSource?.sketchCurveParameter?.featureID == featureID)
    #expect(candidate.measurementSource?.sketchCurveParameter?.entityID == lineEntry.key)
    #expect(candidate.measurementSource?.sketchCurveParameter?.parameter == 0.5)
    #expect(abs((candidate.measurementSource?.worldPoint.x ?? 0.0) - 0.005) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.canUndo == false)
}

@MainActor
@Test func agentResolvesSnapProjectedOntoActiveConstructionPlane() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Projected Snap Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    _ = try #require(
        session.createConstructionPlane(
            name: "Agent Right CPlane",
            plane: .yz
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.006, y: 0.00005),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                usesConstructionPlaneProjection: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a construction-plane projected snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .lineClosest)
    #expect(abs(result.resolvedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func agentResolvesGeneratedTopologySnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edge = try #require(topology.entries.first { entry in
        entry.kind == .edge && entry.start != nil && entry.end != nil && entry.selectionTarget() != nil
    })
    let start = try #require(edge.start)
    let end = try #require(edge.end)
    let midpoint = CADCore.Point2D(
        x: (start.x + end.x) * 0.5,
        y: (start.y + end.y) * 0.5
    )
    let edgeTarget = try #require(edge.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: midpoint.x + 0.00001, y: midpoint.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 32
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a generated topology snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .edgeMidpoint &&
            candidate.topologySource?.persistentName == edge.persistentName
    })
    #expect(candidate.topologySource?.selectionTarget == edgeTarget)
    #expect(abs(candidate.point.x - midpoint.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - midpoint.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesPolySplineSurfaceCVSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createPolySplineSurface(
        name: "Agent Surface CV Snap PolySpline",
        sourceMesh: agentPolySplineQuadMesh()
    ))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertex = try #require(topology.entries.first { entry in
        entry.kind == .vertex
            && PolySplineSurfaceVertexTarget.canParsePersistentName(entry.persistentName)
            && entry.start != nil
            && entry.selectionTarget() != nil
    })
    let point = try #require(vertex.start)
    let vertexTarget = try #require(vertex.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: point.x + 0.00001, y: point.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 32
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a PolySpline Surface CV snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceControlVertex
            && candidate.topologySource?.persistentName == vertex.persistentName
    })
    #expect(result.selectedCandidate?.kind == .surfaceControlVertex)
    #expect(candidate.label == "Surface CV")
    #expect(candidate.topologySource?.selectionTarget == vertexTarget)
    #expect(candidate.topologySource?.worldPoint == point)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesRegionCenterSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Agent Region Snap Rectangle",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00002, y: -0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a region snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .regionCenter)
    #expect(result.selectedCandidate?.regionSource?.featureID == featureID)
    #expect(result.selectedCandidate?.regionSource?.sceneNodeID != nil)
    #expect(abs(result.resolvedPoint.x) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesCurveIntersectionSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Horizontal",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(4.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(4.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Vertical",
            plane: .xy,
            start: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00604, y: 0.00403),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return an intersection snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveIntersection)
    #expect(result.selectedCandidate?.source != nil)
    #expect(result.selectedCandidate?.relatedSource != nil)
    #expect(abs(result.resolvedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesTangentSnapWithReferencePointWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Agent Snap Tangent Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let expected = CADCore.Point2D(
        x: cos(Double.pi / 6.0) * 0.004,
        y: sin(Double.pi / 6.0) * 0.004
    )
    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: expected.x + 0.00002, y: expected.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8,
                referencePoint: CADCore.Point2D(x: 0.0, y: 0.008)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a tangent snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveTangent)
    #expect(abs(result.resolvedPoint.x - expected.x) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - expected.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesCurveAxisSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Axis Line",
            plane: .yz,
            start: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let referencePoint = CADCore.Point2D(x: 0.0, y: 0.004)
    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00502, y: 0.00401),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8,
                referencePoint: referencePoint
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return an axis snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveAxis)
    #expect(result.selectedCandidate?.label == "Y")
    #expect(result.selectedCandidate?.axisSource?.kind == .y)
    #expect(result.selectedCandidate?.axisSource?.referencePoint == referencePoint)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesCurveCoordinatePlaneSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap YZ Plane Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(4.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(4.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let referencePoint = CADCore.Point2D(x: 0.005, y: 0.0)
    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00502, y: 0.00401),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                suppressedCandidateKinds: [.curveAxis],
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8,
                referencePoint: referencePoint
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a coordinate-plane snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveCoordinatePlane)
    #expect(result.selectedCandidate?.label == "YZ")
    #expect(result.selectedCandidate?.coordinatePlaneSource?.kind == .yz)
    #expect(result.selectedCandidate?.coordinatePlaneSource?.referencePoint == referencePoint)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesControlVertexSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Snap CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00202, y: 0.00301),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a CV snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .controlVertex)
    #expect(result.selectedCandidate?.label == "CV")
    #expect(result.selectedCandidate?.source?.controlPointIndex == 1)
    #expect(abs(result.resolvedPoint.x - 0.002) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.003) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentOffsetsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Offset Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.entityKind == "line" }
    let offset = try #require(lines.first { entry in
        abs((entry.start?.y ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 2)
    #expect(offset.sourceFeatureID != sourceLine.sourceFeatureID)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentOffsetsSketchVertexThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Offset Vertex Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetSketchVertex(
                target: target,
                handle: .lineEnd,
                distance: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetSketchVertex command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.commandName == "offsetSketchVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 6)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesOffsetCurveVertexBranchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Offset Curve Vertex Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: .lineEnd
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve vertex branch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 6)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesOffsetCurveArcEndpointVertexBranchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceArc.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: .arcStart
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve arc vertex branch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(sourceEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesOffsetCurveArcArcEndpointVertexBranchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentArcArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.upperArcID.description })
    let target = try #require(sourceArc.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: .arcEnd
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve arc-arc vertex branch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(sourceEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Slot Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Line Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromOpenLineChainAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentOpenLineChainSlotDocument(name: "Agent Slot Source Chain")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineIDs[0].description })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for an open line-chain.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Chain Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Slot Chain",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for a line-chain Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromSourceArcAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Slot Source Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(sourceArc.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for a source arc.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Arc Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Arc Slot",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for an arc Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromSourceSplineAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Slot Source Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceSpline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(sourceSpline.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for a source spline.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Spline Slot" }
    )
    let slotObject = try #require(
        session.document.productMetadata.sceneNodes.values.compactMap(\.object).first { object in
            object.sourceFeatureID == slotFeature.id
        }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotObject.properties["source.kind"] == .text("spline"))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == SlotProfileBuilder.defaultSplineSamplesPerSegment * 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Spline Slot",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for a spline Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromOpenLineArcChainAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentOpenLineArcChainSlotDocument(name: "Agent Slot Source Line Arc Chain")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for an open line-arc chain.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Line Arc Chain Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Line Arc Slot",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for a line-arc Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentActivatesSlotModeThroughOffsetCurve() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Offset Slot Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(mode: .slot),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve Slot mode command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Offset Slot Source Line Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentAnalyzesOpenSessionCurvesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Analysis Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .curveAnalysis(let analysis) = response else {
        #expect(Bool(false))
        return
    }
    #expect(analysis.counts.curveCount == 1)
    let spline = try #require(analysis.curves.first { $0.curveKind == .spline })
    #expect(spline.samples.count == 17)
    #expect(spline.maxAbsCurvature > 1.0)
    #expect(spline.selectionComponentID?.hasPrefix(SelectionComponentID.sketchEntityPrefix) == true)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentAnalyzesConstrainedEndpointContinuityWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Curve Continuity")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let constraintResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .coincident(.lineEnd(setup.firstLineID), .lineStart(setup.secondLineID))
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = constraintResponse else {
        #expect(Bool(false))
        return
    }

    let response = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .curveAnalysis(let analysis) = response else {
        #expect(Bool(false))
        return
    }
    #expect(analysis.counts.curveCount == 2)
    #expect(analysis.counts.continuityJoinCount == 1)
    let join = try #require(analysis.continuityJoins.first)
    #expect(join.joinKind == .constrainedEndpoint)
    #expect(join.constraintKinds == ["coincident"])
    #expect(join.requiredContinuity == .g0)
    #expect(join.firstReference == "lineEnd:\(setup.firstLineID.description)")
    #expect(join.secondReference == "lineStart:\(setup.secondLineID.description)")
    #expect(join.continuity == .g0)
    #expect(abs(join.positionGap) < 1.0e-12)
    #expect((join.tangentAngle ?? 0.0) > 1.0e-4)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesBridgeCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Bridge Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBridgeCurve(
                featureID: setup.featureID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: .lineEnd(setup.firstLineID)
                ),
                secondEndpoint: BridgeCurveEndpoint(
                    reference: .lineStart(setup.secondLineID)
                ),
                continuity: .g1
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(agentSketchFeature(in: session.document, featureID: setup.featureID))
    let bridgeID = try #require(sketch.entities.first { _, entity in
        if case .spline = entity {
            return true
        }
        return false
    }?.key)
    let source = try #require(session.document.productMetadata.bridgeCurveSources.values.first)
    let analysisResponse = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .curveAnalysis(let analysis) = analysisResponse else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createBridgeCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.entities.count == 3)
    #expect(source.featureID == setup.featureID)
    #expect(source.entityID == bridgeID)
    #expect(source.firstEndpoint.reference == .lineEnd(setup.firstLineID))
    #expect(source.secondEndpoint.reference == .lineStart(setup.secondLineID))
    #expect(source.continuity == .g1)
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 0),
        .lineEnd(setup.firstLineID)
    )))
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 6),
        .lineStart(setup.secondLineID)
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        spline: bridgeID,
        endpoint: .start,
        line: setup.firstLineID
    )))
    let bridgeCurve = try #require(analysis.curves.first { $0.entityID == bridgeID.description })
    #expect(bridgeCurve.curveKind == .spline)
    #expect(analysis.continuityJoins.contains { join in
        join.firstEntityID == bridgeID.description || join.secondEntityID == bridgeID.description
    })

    let updateResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setBridgeCurveParameters(
                sourceID: source.id,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: .entity(setup.firstLineID),
                    parameter: .scalar(0.5),
                    reversesSense: true
                ),
                secondEndpoint: BridgeCurveEndpoint(
                    reference: .entity(setup.secondLineID),
                    parameter: .scalar(0.25)
                ),
                continuity: .g1,
                trimsSourceCurves: true
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let updateResult) = updateResponse else {
        #expect(Bool(false))
        return
    }
    let updatedSketch = try #require(agentSketchFeature(in: session.document, featureID: setup.featureID))
    let updatedSource = try #require(session.document.productMetadata.bridgeCurveSources[source.id])
    let updatedEntity = try #require(updatedSketch.entities[bridgeID])
    guard case .spline(let updatedSpline) = updatedEntity else {
        #expect(Bool(false))
        return
    }
    let updatedControlPoints = try updatedSpline.controlPoints.map { point in
        try agentResolvedSketchPoint(point, in: session.document)
    }

    #expect(updateResult.commandName == "setBridgeCurveParameters")
    #expect(updateResult.didMutate)
    #expect(updateResult.generation == DocumentGeneration(2))
    #expect(updatedSketch.entities.count == 3)
    #expect(updatedSource.entityID == bridgeID)
    #expect(updatedSource.trimsSourceCurves)
    #expect(updatedSource.firstEndpoint.reference == .lineStart(setup.firstLineID))
    #expect(updatedSource.firstEndpoint.parameter == nil)
    #expect(updatedSource.firstEndpoint.reversesSense == false)
    #expect(updatedSource.secondEndpoint.reference == .lineEnd(setup.secondLineID))
    #expect(updatedSource.secondEndpoint.parameter == nil)
    #expect(updatedSource.continuity == .g1)
    #expect(updatedSketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 0),
        .lineStart(setup.firstLineID)
    )))
    #expect(updatedSketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 6),
        .lineEnd(setup.secondLineID)
    )))
    #expect(updatedSketch.constraints.contains(.splineEndpointTangent(
        spline: bridgeID,
        endpoint: .start,
        line: setup.firstLineID
    )))
    #expect(updatedSketch.constraints.contains(.splineEndpointTangent(
        spline: bridgeID,
        endpoint: .end,
        line: setup.secondLineID
    )))
    #expect(updatedControlPoints.count == 7)
    #expect(nearlyEqualAgent(updatedControlPoints[0].x, 0.0025))
    #expect(nearlyEqualAgent(updatedControlPoints[0].y, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[1].x, 0.001182384266129633))
    #expect(nearlyEqualAgent(updatedControlPoints[1].y, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[2].x, 0.0016666666666666668))
    #expect(nearlyEqualAgent(updatedControlPoints[2].y, 0.0025))
    #expect(nearlyEqualAgent(updatedControlPoints[3].x, 0.00125))
    #expect(nearlyEqualAgent(updatedControlPoints[3].y, 0.00375))
    #expect(nearlyEqualAgent(updatedControlPoints[4].x, 0.0008333333333333334))
    #expect(nearlyEqualAgent(updatedControlPoints[4].y, 0.005))
    #expect(nearlyEqualAgent(updatedControlPoints[5].x, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[5].y, 0.008817615733870367))
    #expect(nearlyEqualAgent(updatedControlPoints[6].x, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[6].y, 0.0075))
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesSketchEntityEditCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Editable Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchArcParameters(
                target: target,
                center: nil,
                radius: .length(6.0, .millimeter),
                startAngle: nil,
                endAngle: .angle(120.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityKind == "arc" })
    #expect(result.commandName == "setSketchArcParameters")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedArc.radius ?? -1.0) - 0.006) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (Double.pi * 2.0 / 3.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsSketchEntityDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Dimensioned Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .length,
                value: .length(25.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "distance" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.025) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsSketchArcAngleDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Angle Dimensioned Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(120.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedArc.startAngle ?? -1.0) - (10.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (130.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsFixedEndSketchArcAngleDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Fixed End Span Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        )
    )
    let createdSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let createdArc = try #require(createdSummary.entries.first { $0.entityKind == "arc" })
    let featureID = try #require(UUID(uuidString: createdArc.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: createdArc.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.arcEnd(entityID))
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let arc = try #require(summary.entries.first { $0.entityID == createdArc.entityID })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(120.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedArc.startAngle ?? -1.0) - (-40.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (80.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsSketchLineAngleDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Angled Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(90.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((updatedLine.end?.y ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsFixedEndLineDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Fixed End Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let createdSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(createdSummary.entries.first { $0.entityKind == "line" })
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineEnd(entityID))
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let fixedLine = try #require(summary.entries.first { $0.entityID == line.entityID })
    let target = try #require(fixedLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .length,
                value: .length(25.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "distance" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedLine.start?.x ?? -1.0) - (-0.015)) < 1.0e-12)
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCreatesAndMovesSplineControlPointThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                    SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                    SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must return a spline creation command result.")
        return
    }
    #expect(createResult.commandName == "createSplineSketch")
    #expect(createResult.generation == DocumentGeneration(1))

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    #expect(spline.controlPoints.count == 4)

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: 1,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must return a spline edit command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityKind == "spline" })

    #expect(moveResult.commandName == "moveSketchSplineControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(abs(updatedSpline.controlPoints[1].x - 0.003) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].y - 0.004) < 1.0e-12)

    let insertResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .insertSketchSplineControlPoint(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let insertResult) = insertResponse else {
        Issue.record("Agent must return a spline control-point insertion command result.")
        return
    }
    let insertedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let insertedSpline = try #require(insertedSummary.entries.first { $0.entityKind == "spline" })
    #expect(insertResult.commandName == "insertSketchSplineControlPoint")
    #expect(insertResult.didMutate)
    #expect(insertResult.generation == DocumentGeneration(3))
    #expect(insertedSpline.controlPoints.count == 7)

    let rebuildResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .rebuildSketchCurve(
                target: target,
                options: .points(controlPointCount: 4)
            ),
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .command(let rebuildResult) = rebuildResponse else {
        Issue.record("Agent must return a sketch curve rebuild command result.")
        return
    }
    let rebuiltSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(rebuiltSummary.entries.first { $0.entityKind == "spline" })
    #expect(rebuildResult.commandName == "rebuildSketchCurve")
    #expect(rebuildResult.didMutate)
    #expect(rebuildResult.generation == DocumentGeneration(4))
    #expect(rebuiltSpline.entityID == insertedSpline.entityID)
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentRefitsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Refit Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(1.0, .millimeter), y: .length(1.0, .millimeter)),
                    SketchPoint(x: .length(2.0, .millimeter), y: .length(1.0, .millimeter)),
                    SketchPoint(x: .length(3.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(4.0, .millimeter), y: .length(-1.0, .millimeter)),
                    SketchPoint(x: .length(6.0, .millimeter), y: .length(-1.0, .millimeter)),
                    SketchPoint(x: .length(7.0, .millimeter), y: .length(0.0, .millimeter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must return a spline creation command result.")
        return
    }
    #expect(createResult.commandName == "createSplineSketch")
    #expect(createResult.generation == DocumentGeneration(1))

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let rebuildResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .rebuildSketchCurve(
                target: target,
                options: .refit(
                    tolerance: .length(20.0, .millimeter),
                    keepsCorners: false
                )
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let rebuildResult) = rebuildResponse else {
        Issue.record("Agent must return a sketch curve refit command result.")
        return
    }

    let rebuiltSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(rebuiltSummary.entries.first { $0.entityID == spline.entityID })
    #expect(rebuildResult.commandName == "rebuildSketchCurve")
    #expect(rebuildResult.didMutate)
    #expect(rebuildResult.generation == DocumentGeneration(2))
    let report = try #require(rebuildResult.curveRebuildReport)
    #expect(report.method == .refit)
    #expect(report.sourceFeatureID == spline.sourceFeatureID)
    #expect(report.entityID == spline.entityID)
    #expect(report.originalControlPointCount == 7)
    #expect(report.rebuiltControlPointCount == 4)
    #expect(report.originalSpanCount == 2)
    #expect(report.rebuiltSpanCount == 1)
    #expect(report.deviationMeasurement == .analyticCubicBezier)
    #expect(report.evaluatedIntervalCount == 2)
    #expect(report.criticalPointCount >= 0)
    #expect(report.maximumDeviationMeters >= report.rootMeanSquareDeviationMeters)
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(abs((rebuiltSpline.controlPoints.first?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuiltSpline.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentExplicitlyRebuildsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Explicit Rebuild Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(1.0, .millimeter), y: .length(2.0, .millimeter)),
                    SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                    SketchPoint(x: .length(3.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(4.0, .millimeter), y: .length(-3.0, .millimeter)),
                    SketchPoint(x: .length(6.0, .millimeter), y: .length(-3.0, .millimeter)),
                    SketchPoint(x: .length(7.0, .millimeter), y: .length(0.0, .millimeter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must return a spline creation command result.")
        return
    }
    #expect(createResult.commandName == "createSplineSketch")
    #expect(createResult.generation == DocumentGeneration(1))

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let rebuildResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .rebuildSketchCurve(
                target: target,
                options: .explicitControl(
                    degree: 3,
                    spanCount: 1,
                    weight: 0.5
                )
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let rebuildResult) = rebuildResponse else {
        Issue.record("Agent must return a sketch curve Explicit Control command result.")
        return
    }

    let rebuiltSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(rebuiltSummary.entries.first { $0.entityID == spline.entityID })
    #expect(rebuildResult.commandName == "rebuildSketchCurve")
    #expect(rebuildResult.didMutate)
    #expect(rebuildResult.generation == DocumentGeneration(2))
    let report = try #require(rebuildResult.curveRebuildReport)
    #expect(report.method == .explicitControl)
    #expect(report.sourceFeatureID == spline.sourceFeatureID)
    #expect(report.entityID == spline.entityID)
    #expect(report.originalControlPointCount == 7)
    #expect(report.rebuiltControlPointCount == 4)
    #expect(report.originalSpanCount == 2)
    #expect(report.rebuiltSpanCount == 1)
    #expect(report.deviationMeasurement == .analyticCubicBezier)
    #expect(report.evaluatedIntervalCount == 2)
    #expect(report.criticalPointCount >= 0)
    #expect(report.maximumDeviationMeters >= report.rootMeanSquareDeviationMeters)
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(abs((rebuiltSpline.controlPoints.first?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuiltSpline.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentExtrudesClosedSplineProfileThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Spline Profile",
                plane: .xy,
                spline: agentClosedBezierCircleSpline(radius: 0.01)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a closed spline profile.")
        return
    }
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Spline Body",
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .length(0.005, .meter),
                direction: .normal
            ),
            expectedGeneration: createResult.generation
        )
    )
    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must extrude the closed spline profile.")
        return
    }

    #expect(createResult.commandName == "createSplineSketch")
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func agentCreatesSweepSourceThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Agent Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Agent Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSweep(
                name: "Agent Sweep",
                sections: [.profile(ProfileReference(featureID: profileID))],
                path: SweepPathReference(featureID: pathID),
                guides: [],
                targets: [],
                options: SweepOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a sweep command result.")
        return
    }
    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Agent must create a sweep feature.")
        return
    }

    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sweep.sections == [.profile(ProfileReference(featureID: profileID))])
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesCurveSectionSheetSweepThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let sectionID = try document.createLineSketch(
        name: "Agent Curve Sheet Section",
        plane: .xy,
        start: agentSketchPoint(x: -0.002, y: 0.0),
        end: agentSketchPoint(x: 0.002, y: 0.0)
    )
    let pathID = try document.createLineSketch(
        name: "Agent Curve Sheet Path",
        plane: .yz,
        start: agentSketchPoint(x: 0.0, y: 0.0),
        end: agentSketchPoint(x: 0.0, y: 0.020)
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSweep(
                name: "Agent Curve Sheet Sweep",
                sections: [.curve(SweepCurveSectionReference(featureID: sectionID))],
                path: SweepPathReference(featureID: pathID),
                guides: [],
                targets: [],
                options: SweepOptions(resultKind: .sheet)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a curve-section sheet sweep command result.")
        return
    }
    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])
    let evaluated = try CADPipeline.modelingDefault(for: session.document).evaluate(
        session.document.cadDocument
    )
    let body = try #require(evaluated.brep.bodies.values.first)

    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Agent must create a sweep feature.")
        return
    }
    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(sweep.sections == [.curve(SweepCurveSectionReference(featureID: sectionID))])
    #expect(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(sweepID)
    }?.object?.sourceSection == .curve(sectionID))
    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    #expect(body.kind == .sheet)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesRevolveSourceThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Agent Revolve Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(4.0, .millimeter),
            y: .length(14.0, .millimeter)
        )
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createRevolve(
                name: "Agent Revolved Body",
                profile: ProfileReference(featureID: profileID),
                axis: RevolveAxis(origin: .origin, direction: .unitY),
                angle: .angle(180.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a revolve command result.")
        return
    }
    let revolveID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[revolveID])
    guard case .revolve(let revolve) = feature.operation else {
        Issue.record("Agent must create a revolve feature.")
        return
    }

    #expect(result.commandName == "createRevolve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(revolve.profile == ProfileReference(featureID: profileID))
    #expect(revolve.axis == RevolveAxis(origin: .origin, direction: .unitY))
    #expect(revolve.angle == .angle(180.0, .degree))
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesConnectedMultiEntitySweepPathAndSweepThroughAutomation() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Agent Connected Sweep Profile",
        plane: .xy,
        width: .length(2.0, .millimeter),
        height: .length(1.0, .millimeter)
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let pathResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSketch(
                name: "Agent Connected Sweep Path",
                sketch: Sketch(
                    plane: .yz,
                    entities: [
                        SketchEntityID(): .line(SketchLine(
                            start: SketchPoint(
                                x: .length(0.0, .millimeter),
                                y: .length(0.0, .millimeter)
                            ),
                            end: SketchPoint(
                                x: .length(0.0, .millimeter),
                                y: .length(15.0, .millimeter)
                            )
                        )),
                        SketchEntityID(): .line(SketchLine(
                            start: SketchPoint(
                                x: .length(0.0, .millimeter),
                                y: .length(15.0, .millimeter)
                            ),
                            end: SketchPoint(
                                x: .length(8.0, .millimeter),
                                y: .length(25.0, .millimeter)
                            )
                        )),
                    ]
                ),
                geometryRole: .curve
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let pathResult) = pathResponse else {
        Issue.record("Agent must return a createSketch command result.")
        return
    }
    let pathID = try #require(session.document.cadDocument.designGraph.order.last)

    let sweepResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSweep(
                name: "Agent Connected Multi-Path Sweep",
                sections: [.profile(ProfileReference(featureID: profileID))],
                path: SweepPathReference(featureID: pathID),
                guides: [],
                targets: [],
                options: SweepOptions(cornerStyle: .mitre)
            ),
            expectedGeneration: pathResult.generation
        )
    )
    guard case .command(let sweepResult) = sweepResponse else {
        Issue.record("Agent must return a connected sweep command result.")
        return
    }
    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let pathFeature = try #require(session.document.cadDocument.designGraph.nodes[pathID])
    let sweepFeature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])

    guard case .sketch(let pathSketch) = pathFeature.operation,
          case .sweep(let sweep) = sweepFeature.operation else {
        Issue.record("Agent must create a sketch path and a sweep feature.")
        return
    }
    #expect(pathResult.commandName == "createSketch")
    #expect(pathSketch.entities.count == 2)
    #expect(sweepResult.commandName == "createSweep")
    #expect(sweepResult.generation == DocumentGeneration(2))
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(sweepResult.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentMovesParallelLineAngleThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineConstrainedSketchDocument(
        name: "Agent Parallel Line Pair",
        constraint: { .parallel($0, $1) }
    )
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let sourceLine = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchEntityPoint(
                target: target,
                handle: .lineEnd,
                deltaX: .length(0.0, .meter),
                deltaY: .length(0.010, .meter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSource = try #require(updatedSummary.entries.first { $0.entityID == setup.firstLineID.description })
    let movedFollower = try #require(updatedSummary.entries.first { $0.entityID == setup.secondLineID.description })
    let expectedFollowerEndOffset = 0.005 / sqrt(2.0)
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(agentLineEntriesAreParallel(movedSource, movedFollower))
    #expect(abs((movedFollower.end?.x ?? -1.0) - expectedFollowerEndOffset) < 1.0e-12)
    #expect(abs((movedFollower.end?.y ?? -1.0) - (0.005 + expectedFollowerEndOffset)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentMovesConstrainedRectanglePointThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Move Constrained Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let bottomLine = try #require(summary.entries.first { entry in
        agentIsHorizontalLine(entry, y: 0.0)
    })
    let target = try #require(bottomLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchEntityPoint(
                target: target,
                handle: .lineEnd,
                deltaX: .length(2.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let movedBottom = try #require(updatedSummary.entries.first { $0.entityID == bottomLine.entityID })
    let bodyNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((movedBottom.end?.x ?? -1.0) - 0.012) < 1.0e-12)
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.012, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.012, y: 0.005))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.005))
    #expect(abs((bodyNode.object?.properties["size.x"]?.lengthValue ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.z"]?.lengthValue ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsConstrainedRectangleSideDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Dimensioned Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let bottomLine = try #require(summary.entries.first { entry in
        agentIsHorizontalLine(entry, y: 0.0)
    })
    let target = try #require(bottomLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .length,
                value: .length(25.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedBottom = try #require(updatedSummary.entries.first { $0.entityID == bottomLine.entityID })
    let dimension = try #require(updatedBottom.dimensions.first { $0.kind == "distance" })
    let bodyNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.025, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.025, y: 0.005))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.005))
    #expect(abs((bodyNode.object?.properties["size.x"]?.lengthValue ?? -1.0) - 0.025) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.z"]?.lengthValue ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentConvertsSketchLineToArcThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Bendable Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .convertSketchLineToArc(
                target: target,
                sagitta: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "convertSketchLineToArc")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arc.entityKind == "arc")
    #expect(abs((arc.radius ?? -1.0) - 0.00725) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentConvertsSketchLineToSplineThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Spline Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(9.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .convertSketchLineToSpline(target: target),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let firstHandle = try #require(spline.controlPoints.dropFirst(1).first)
    let secondHandle = try #require(spline.controlPoints.dropFirst(2).first)
    #expect(result.commandName == "convertSketchLineToSpline")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(spline.entityKind == "spline")
    #expect(spline.controlPoints.count == 4)
    #expect(abs(firstHandle.x - 0.003) < 1.0e-12)
    #expect(abs(secondHandle.x - 0.006) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentReversesSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Reverse Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(7.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .reverseSketchCurve(target: target),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let reversedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "reverseSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((reversedLine.start?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(abs((reversedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentExtendsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Extend Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(7.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try agentPointHandleSelectionTarget(line, handle: .lineEnd)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extendSketchCurve(
                target: target,
                distance: .length(3.0, .millimeter),
                shape: .natural
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let extendedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "extendSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((extendedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((extendedLine.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentJoinsSketchCurvesThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentCollinearLineChainSketchDocument(name: "Agent Join Source Lines")
    let session = EditorSession(document: setup.document)
    let firstLineID = setup.lineIDs[0]
    let secondLineID = setup.lineIDs[1]
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let firstLine = try #require(summary.entries.first { $0.entityID == firstLineID.description })
    let secondLine = try #require(summary.entries.first { $0.entityID == secondLineID.description })

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .joinSketchCurves(
                target: try #require(firstLine.selectionTarget()),
                adjacentTarget: try #require(secondLine.selectionTarget())
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let joinedLine = try #require(updatedSummary.entries.first { $0.entityID == firstLineID.description })
    #expect(result.commandName == "joinSketchCurves")
    #expect(result.didMutate)
    #expect(result.generation == session.generation)
    #expect(updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Join Source Lines" }.count == 1)
    #expect(joinedLine.entityKind == "line")
    #expect(abs((joinedLine.start?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((joinedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentUnjoinsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentCollinearLineChainSketchDocument(name: "Agent Unjoin Source Lines")
    let session = EditorSession(document: setup.document)
    let firstLineID = setup.lineIDs[0]
    let secondLineID = setup.lineIDs[1]
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let firstLine = try #require(summary.entries.first { $0.entityID == firstLineID.description })
    let secondLine = try #require(summary.entries.first { $0.entityID == secondLineID.description })

    let joinResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .joinSketchCurves(
                target: try #require(firstLine.selectionTarget()),
                adjacentTarget: try #require(secondLine.selectionTarget())
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let joinResult) = joinResponse else {
        Issue.record("Agent must return a join command result.")
        return
    }
    let joinedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let joinedLine = try #require(joinedSummary.entries.first { $0.entityID == firstLineID.description })

    let unjoinResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .unjoinSketchCurve(target: try #require(joinedLine.selectionTarget())),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let unjoinResult) = unjoinResponse else {
        Issue.record("Agent must return an unjoin command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let retainedLine = try #require(updatedSummary.entries.first { $0.entityID == firstLineID.description })
    let restoredLine = try #require(updatedSummary.entries.first { $0.entityID == secondLineID.description })
    #expect(joinResult.commandName == "joinSketchCurves")
    #expect(unjoinResult.commandName == "unjoinSketchCurve")
    #expect(unjoinResult.didMutate)
    #expect(updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Unjoin Source Lines" }.count == 2)
    #expect(retainedLine.entityKind == "line")
    #expect(restoredLine.entityKind == "line")
    #expect(abs((retainedLine.end?.x ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((restoredLine.start?.x ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.document.productMetadata.joinedCurveSources.isEmpty)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAppliesSketchCornerTreatmentThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Source Fillet Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let bottomLine = try #require(agentBottomRectangleLine(in: summary))
    let target = try agentPointHandleSelectionTarget(bottomLine, handle: .lineEnd)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySketchCornerTreatment(
                target: target,
                adjacentTarget: nil,
                distance: .length(2.0, .millimeter),
                treatment: .fillet
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arcs = updatedSummary.entries.filter {
        $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "arc"
    }
    let filletArc = try #require(arcs.first)
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arcs.count == 1)
    #expect(abs((filletArc.center?.x ?? -1.0) - 0.008) < 1.0e-12)
    #expect(abs((filletArc.center?.y ?? -1.0) - 0.002) < 1.0e-12)
    #expect(abs((filletArc.radius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAppliesSketchCornerTreatmentToLineArcCornerThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let sourceLine = try #require(summary.entries.first { $0.entityID == setup.lineID.description })
    let target = try agentPointHandleSelectionTarget(sourceLine, handle: .lineEnd)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySketchCornerTreatment(
                target: target,
                adjacentTarget: nil,
                distance: .length(0.001, .meter),
                treatment: .fillet
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = updatedSummary.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.001) < 1.0e-12 })
    let sourceArc = try #require(arcs.first { $0.entityID == setup.arcID.description })
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(insertedArc.center != nil)
    #expect((sourceArc.startAngle ?? 0.0) > 0.0)
    #expect(abs((sourceArc.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAppliesSketchCornerTreatmentToCurvePairThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let sourceLine = try #require(summary.entries.first { $0.entityID == setup.lineID.description })
    let sourceArc = try #require(summary.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceLine.selectionTarget())
    let adjacentTarget = try #require(sourceArc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySketchCornerTreatment(
                target: target,
                adjacentTarget: adjacentTarget,
                distance: .length(0.001, .meter),
                treatment: .fillet
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = updatedSummary.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.001) < 1.0e-12 })
    let sourceArcAfter = try #require(arcs.first { $0.entityID == setup.arcID.description })
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(insertedArc.center != nil)
    #expect((sourceArcAfter.startAngle ?? 0.0) > 0.0)
    #expect(abs((sourceArcAfter.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSplitsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Split Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSketchCurve(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = updatedSummary.entries.filter { $0.entityKind == "line" }
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 2)
    #expect(lines.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.003) < 1.0e-12
    })
    #expect(lines.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.003) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.006) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSplitsSketchArcCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Split Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(120.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSketchCurve(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arcs = updatedSummary.entries.filter { $0.entityKind == "arc" }
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arcs.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentTrimsSketchCurveSegmentThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Trim Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let splitResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSketchCurve(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = splitResponse else {
        Issue.record("Agent must split the sketch curve before trimming.")
        return
    }
    let splitSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let trimmedLine = try #require(splitSummary.entries.first { entry in
        entry.entityKind == "line" && entry.entityID != line.entityID
    })
    let trimmedTarget = try #require(trimmedLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .trimSketchCurveSegment(target: trimmedTarget),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = updatedSummary.entries.filter { $0.entityKind == "line" }
    #expect(result.commandName == "trimSketchCurveSegment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(lines.count == 1)
    #expect(lines.first?.entityID == line.entityID)
    #expect(abs((lines.first?.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((lines.first?.end?.x ?? -1.0) - 0.003) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(2.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Cut Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.006) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCurveWithCircleCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Circle Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createCircleSketch(
            name: "Agent Circle Cut Cutter",
            plane: .xy,
            center: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(2.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Cut Target" })
    let cutterCircle = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Cut Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterCircle.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Circle Cut Target" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 3)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.003) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.003) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.007) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.007) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCurveWithSplineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Spline Cutter Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Spline Cutter",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(5.0, .millimeter), y: .length(-2.0, .millimeter)),
                SketchPoint(x: .length(5.0, .millimeter), y: .length(-2.0 / 3.0, .millimeter)),
                SketchPoint(x: .length(5.0, .millimeter), y: .length(2.0 / 3.0, .millimeter)),
                SketchPoint(x: .length(5.0, .millimeter), y: .length(2.0, .millimeter)),
            ])
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Spline Cutter Target" })
    let cutterSpline = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Spline Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterSpline.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Spline Cutter Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Spline Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.005) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.005) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchSplineTargetWithLineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Spline Cut Target",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Spline Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(-1.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(5.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetSpline = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Spline Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Spline Cut Cutter" })
    let target = try #require(targetSpline.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Spline Cut Target" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.allSatisfy { $0.entityKind == "spline" })
    #expect(targetSegments.contains { entry in
        guard let start = entry.controlPoints.first,
              let end = entry.controlPoints.last else {
            return false
        }
        return abs(start.x - 0.0) < 1.0e-9 &&
            abs(start.y - 0.0) < 1.0e-9 &&
            abs(end.x - 0.005) < 1.0e-9 &&
            abs(end.y - 0.003) < 1.0e-9
    })
    #expect(targetSegments.contains { entry in
        guard let start = entry.controlPoints.first,
              let end = entry.controlPoints.last else {
            return false
        }
        return abs(start.x - 0.005) < 1.0e-9 &&
            abs(start.y - 0.003) < 1.0e-9 &&
            abs(end.x - 0.010) < 1.0e-9 &&
            abs(end.y - 0.0) < 1.0e-9
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCircleTargetWithLineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Agent Circle Target Cut Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Circle Target Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-6.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetCircle = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Target Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Target Cut Cutter" })
    let target = try #require(targetCircle.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Circle Target Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Circle Target Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.allSatisfy { $0.entityKind == "arc" })
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi * 1.5) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - Double.pi * 1.5) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchArcCurveWithLineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Arc Cut Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi, .radian)
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Arc Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetArc = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Arc Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Arc Cut Cutter" })
    let target = try #require(targetArc.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Arc Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Arc Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSummarizesOpenSessionTopologyWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedCircle(
            name: "Agent Topology Cylinder",
            plane: .xy,
            center: .init(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(10.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .topologySummary(let topologySummary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(topologySummary.counts.bodyCount == 1)
    #expect(topologySummary.counts.faceCount == 6)
    #expect(topologySummary.counts.edgeCount == 12)
    #expect(topologySummary.counts.vertexCount == 8)
    let cylinderFaces = topologySummary.entries.filter { $0.kind == .face && $0.surfaceKind == "cylinder" }
    let circularEdges = topologySummary.entries.filter { $0.kind == .edge && $0.curveKind == "circle" }
    #expect(cylinderFaces.count == 4)
    #expect(circularEdges.count == 8)
    #expect(cylinderFaces.allSatisfy(hasExpectedAgentCylinderDefinition))
    #expect(circularEdges.allSatisfy(hasExpectedAgentCircularEdgeDefinition))
    #expect(topologySummary.entries.allSatisfy { $0.sceneNodeID != nil })
    let vertexEntry = try #require(topologySummary.entries.first { $0.kind == .vertex })
    let vertexTarget = try #require(vertexEntry.selectionTarget())
    guard case .vertex(let vertexComponentID) = vertexTarget.component else {
        Issue.record("Agent topology summary must expose vertex selection targets.")
        return
    }
    #expect(vertexComponentID.generatedTopologyPersistentName == vertexEntry.persistentName)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesCellUnionBooleanTopologyWithoutMutation() async throws {
    var document = DesignDocument.empty()
    let targetProfileID = try document.createRectangleSketchFromCorners(
        name: "Agent Cell Union Boolean Target Profile",
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
        name: "Agent Cell Union Boolean Target",
        profile: ProfileReference(featureID: targetProfileID),
        distance: .length(10.0, .millimeter),
        direction: .normal
    )
    let toolProfileID = try document.createRectangleSketchFromCorners(
        name: "Agent Cell Union Boolean Tool Profile",
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
        name: "Agent Cell Union Boolean Sweep Path",
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
        name: "Agent Cell Union Boolean Result Sweep",
        sections: [.profile(ProfileReference(featureID: toolProfileID))],
        path: SweepPathReference(featureID: pathID),
        targets: [SweepTargetReference(featureID: targetBodyID)],
        options: SweepOptions(booleanOperation: .difference)
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .topologySummary(let topologySummary) = response else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let face = try #require(topologySummary.entries.first {
        $0.kind == .face
            && $0.generatedRole == "sideFace"
            && $0.subshapeRole == "cellUnion:component:0:face:maxX:x:maxX:y:minY-y1:z:minZ-maxZ"
    })
    let edge = try #require(topologySummary.entries.first {
        $0.kind == .edge
            && $0.generatedRole == "edge"
            && $0.subshapeRole == "cellUnion:component:0:zEdge:x:x1:y:y1:z:minZ-maxZ"
    })
    let vertex = try #require(topologySummary.entries.first {
        $0.kind == .vertex
            && $0.generatedRole == "vertex"
            && $0.subshapeRole == "cellUnion:component:0:vertex:x:x1:y:y1:z:maxZ"
    })
    #expect(face.selectionTarget() != nil)
    #expect(edge.selectionTarget() != nil)
    #expect(vertex.selectionTarget() != nil)
    #expect(topologySummary.counts.bodyCount == 1)
    #expect(topologySummary.counts.faceCount > 6)
    #expect(topologySummary.counts.edgeCount > 12)
    #expect(topologySummary.counts.vertexCount > 8)
    #expect(session.generation == DocumentGeneration(0))
}

private func hasExpectedAgentCylinderDefinition(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard let radius = entry.surfaceRadius,
          let axis = entry.surfaceAxis else {
        return false
    }
    return abs(radius - 0.01) < 0.000_000_001
        && abs(axis.x) < 0.000_000_001
        && abs(axis.y) < 0.000_000_001
        && abs(abs(axis.z) - 1.0) < 0.000_000_001
}

private func hasExpectedAgentCircularEdgeDefinition(_ entry: TopologySummaryResult.Entry) -> Bool {
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
    return abs(radius - 0.01) < 0.000_000_001
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

@MainActor
@Test func agentSelectsGeneratedTopologyVertexTargetWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let generation = session.generation
    let dirty = session.isDirty
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first { $0.kind == .vertex })
    let target = try #require(vertexEntry.selectionTarget())

    let response = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: generation
        )
    )

    guard case .selection(let result) = response else {
        Issue.record("Agent must return a selection result.")
        return
    }
    #expect(result.selectedTargets == [target])
    #expect(session.selection.selectedTargets == [target])
    #expect(result.generation == generation)
    #expect(session.generation == generation)
    #expect(result.dirty == dirty)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentSelectsSurfaceControlPointReferenceWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createPolySplineSurface(
        name: "Agent Reference Selection Surface",
        sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    ))
    let generation = session.generation
    let dirty = session.isDirty
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })

    let response = server.handle(
        .selectReferences(
            sessionID: sessionID,
            references: [controlPoint.selectionReference],
            expectedGeneration: generation
        )
    )

    guard case .selection(let result) = response else {
        Issue.record("Agent must return a selection result.")
        return
    }
    #expect(result.selectedTargets.isEmpty)
    #expect(result.selectedReferences == [controlPoint.selectionReference])
    #expect(session.selection.selectedReferences == [controlPoint.selectionReference])
    #expect(result.generation == generation)
    #expect(session.generation == generation)
    #expect(result.dirty == dirty)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentSavesOpenFileBackedSessionAndMarksClean() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let url = temporaryDirectory.appendingPathComponent("agent-save.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try DocumentFileService().load(from: url))
    _ = try session.execute(
        .renameDocument(name: "Saved Live"),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, path: url, id: sessionID)

    let response = server.handle(
        .save(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .save(let result) = response else {
        #expect(Bool(false))
        return
    }
    let loaded = try DocumentFileService().load(from: url)
    #expect(result.path == url.path)
    #expect(result.generation == DocumentGeneration(1))
    #expect(!result.dirty)
    #expect(!session.isDirty)
    #expect(loaded.cadDocument.metadata.name == "Saved Live")
}

@Test func agentSaveRejectsPathlessSession() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    server.register(session: EditorSession(document: .empty(named: "Pathless")), id: sessionID)

    let response = server.handle(
        .save(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .commandInvalid)
    #expect(error.message.contains("file path"))
}

@MainActor
@Test func agentExportsOpenSessionWithoutMutation() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let outputURL = temporaryDirectory.appendingPathComponent("agent-box.stl")
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Export Box",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .export(
            sessionID: sessionID,
            outputPath: outputURL.path,
            expectedGeneration: DocumentGeneration(1),
            options: ExportOptions(),
            dryRun: false
        )
    )

    guard case .export(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.format == .stl)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.byteCount == 84 + 12 * 50)
    #expect(session.generation == DocumentGeneration(1))
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func agentRejectsGenerationMismatchBeforeMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = try AutomationRunner().execute(.setDisplayUnit(.meter), in: session)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Rejected"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .documentGenerationMismatch)
    #expect(session.document.cadDocument.metadata.name == "Untitled")
}

@Test func agentReportsSessionNotFoundForUnknownSession() async throws {
    let server = AgentCommandController()
    let response = server.handle(
        .execute(
            sessionID: UUID(),
            command: .validateDocument,
            expectedGeneration: nil
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .sessionNotFound)
}

@MainActor
@Test func mainActorAgentBridgeRoutesSessionMutations() async throws {
    let bridge = MainActorAgentBridge()
    let sessionID = UUID()
    let session = EditorSession()
    bridge.register(session: session, id: sessionID)

    let response = bridge.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Main Actor Live"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.metadata.name == "Main Actor Live")
}

@MainActor
@Test(.timeLimit(.minutes(1))) func agentSocketListenerRoutesCommandThroughMainActorBridge() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let socketPath = AgentSocketPath(socketURL.path)
    let bridge = MainActorAgentBridge()
    let sessionID = UUID()
    let session = EditorSession()
    bridge.register(session: session, id: sessionID)
    let listener = AgentSocketListener(
        mainActorBridge: bridge,
        socketPath: socketPath
    )

    try await listener.start()
    do {
        let request = AgentRequest.execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Socket Main Actor"),
            expectedGeneration: DocumentGeneration(0)
        )
        let response = try await sendThroughDetachedClient(request, socketPath: socketPath)

        guard case .command(let result) = response else {
            #expect(Bool(false))
            await listener.stop()
            return
        }
        #expect(result.didMutate)
        #expect(result.generation == DocumentGeneration(1))
        #expect(session.document.cadDocument.metadata.name == "Socket Main Actor")
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerRoundTripsStatusThroughClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let server = AgentCommandController()
    server.register(session: EditorSession(document: .empty(named: "Open")))

    try await withRunningListener(controller: server, socketURL: socketURL) { listener, client in
        let response = try client.send(.status)

        guard case .status(let status) = response else {
            #expect(Bool(false))
            return
        }
        #expect(await listener.isRunning)
        #expect(status.running)
        #expect(status.socketPath == socketURL.path)
        #expect(status.sessionCount == 1)
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerRoutesCommandThroughClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let sessionID = UUID()
    let server = AgentCommandController()
    server.register(session: EditorSession(), id: sessionID)

    try await withRunningListener(controller: server, socketURL: socketURL) { _, client in
        let response = try client.send(
            .execute(
                sessionID: sessionID,
                command: .renameDocument(name: "Socket Live"),
                expectedGeneration: DocumentGeneration(0)
            )
        )

        guard case .command(let result) = response else {
            #expect(Bool(false))
            return
        }
        #expect(result.didMutate)
        #expect(result.generation == DocumentGeneration(1))

        let sessionsResponse = try client.send(.sessions)
        guard case .sessions(let sessions) = sessionsResponse else {
            #expect(Bool(false))
            return
        }
        #expect(sessions.first?.displayName == "Socket Live")
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerStopRemovesSocketAndRejectsClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let listener = AgentSocketListener(
        controller: AgentCommandController(),
        socketPath: AgentSocketPath(socketURL.path)
    )
    let client = AgentClient(socketPath: AgentSocketPath(socketURL.path))

    try await listener.start()
    #expect(FileManager.default.fileExists(atPath: socketURL.path))
    await listener.stop()
    #expect(!FileManager.default.fileExists(atPath: socketURL.path))

    var caught: EditorError?
    do {
        _ = try client.send(.status)
    } catch let error as EditorError {
        caught = error
    }
    #expect(caught?.code == .agentConnectionFailed)
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerReplacesStaleSocketFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    try Data("stale".utf8).write(to: socketURL)

    try await withRunningListener(
        controller: AgentCommandController(),
        socketURL: socketURL
    ) { _, client in
        let response = try client.send(.status)
        guard case .status(let status) = response else {
            #expect(Bool(false))
            return
        }
        #expect(status.socketPath == socketURL.path)
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerSurvivesMalformedRequest() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")

    try await withRunningListener(
        controller: AgentCommandController(),
        socketURL: socketURL
    ) { _, client in
        let malformedResponseData = try sendRaw(
            Data("not-json".utf8),
            to: socketURL
        )
        let malformedResponse = try AgentMessageCodec()
            .decodeResponse(from: malformedResponseData)

        guard case .failure(let error) = malformedResponse else {
            #expect(Bool(false))
            return
        }
        #expect(error.code == .commandInvalid)

        let response = try client.send(.status)
        guard case .status(let status) = response else {
            #expect(Bool(false))
            return
        }
        #expect(status.running)
    }
}
