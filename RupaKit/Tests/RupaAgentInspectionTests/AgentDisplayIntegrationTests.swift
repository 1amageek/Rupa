import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
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
    let gridSettings = ViewportGridSettings(visualSpacingMode: .fixed)
    _ = try session.execute(.setViewportGridSettings(gridSettings))
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
    #expect(snapshot.viewportGridSettings == gridSettings)
    #expect(snapshot.viewportGridScale.visualSpacingMode == .fixed)
    #expect(snapshot.viewportGridScale.snapStep.meters == session.document.ruler.minorTickMeters)
    #expect(snapshot.viewportGridScale.configuredMajorStep.meters == session.document.ruler.majorTickMeters)
    #expect(snapshot.viewportGridScale.workspaceSpan.meters == session.document.ruler.visibleSpanMeters)
    #expect(snapshot.viewportGridScale.summary.contains("mode fixed"))
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
