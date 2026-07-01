import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

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
