import Testing
import Foundation
import RupaCapabilities
import RupaAgentIntegrationTestFixtures
import RupaAutomation
import RupaCore
import RupaDomainFoundation
@testable import RupaAgent

@Test(.timeLimit(.minutes(1)))
func agentCapabilitiesExposeOnlyTypedAgentRequests() throws {
    let controller = AgentCommandController()
    let descriptors = controller.capabilityDescriptors()
    let names = Set(descriptors.map(\.name))
    let expectedNames: Set<String> = [
        "booleanEvaluationPlan",
        "cadInteractionQualityAssessment",
        "constructionPlaneSummary",
        "curveAnalysis",
        "describeDocument",
        "designDisplaySnapshot",
        "evaluateDocument",
        "exportDocument",
        "listParameters",
        "makeEditable",
        "measureDocument",
        "meshCatalog",
        "meshEditCommit",
        "meshEditPreview",
        "meshNeighborhood",
        "meshPage",
        "meshSummary",
        "movePolySplineSurfaceVertex",
        "objectDimensionSummary",
        "patternArraySummary",
        "polySplineMeshAnalysis",
        "redo",
        "resolveSnap",
        "saveDocument",
        "sceneGraphSnapshot",
        "selectReferences",
        "selectTargets",
        "selectionDimensionEvaluation",
        "selectionMeasurement",
        "setObjectDimensionExpression",
        "setParameterExpression",
        "setSelectionDimensionTargetExpression",
        "setSketchEntityDimensionExpression",
        "setSurfaceFrameDisplay",
        "sketchDimensionSummary",
        "sketchEntitySummary",
        "surfaceAnalysis",
        "surfaceBoundaryContinuityCompatibility",
        "surfaceContinuitySummary",
        "surfaceFrames",
        "surfaceSourceSummary",
        "sweepEvaluationPlan",
        "topologySummary",
        "undo",
        "validateDocument",
        "viewportSnapshot",
    ]

    #expect(names == expectedNames)
    #expect(controller.capabilities() == descriptors.map(\.name))
    #expect(descriptors.allSatisfy { $0.access == .agentRequest })
    #expect(!names.contains("appendFeatureGraph"))
    #expect(!names.contains("createSweep"))
    #expect(!names.contains("setDisplayUnit"))
}

@Test(.timeLimit(.minutes(1)))
func retainedCommandLoweringAdaptersHaveTypedContracts() throws {
    let descriptors = AgentCommandController().capabilityDescriptors()
    let polySplineVertex = try #require(
        descriptors.first { $0.name == "movePolySplineSurfaceVertex" }
    )
    let surfaceFrame = try #require(
        descriptors.first { $0.name == "setSurfaceFrameDisplay" }
    )

    #expect(polySplineVertex.access == .agentRequest)
    #expect(polySplineVertex.stateEffect == .sourceMutation)
    #expect(polySplineVertex.targets == [.vertex])
    #expect(polySplineVertex.discovery.contains(.topologySummary))
    #expect(surfaceFrame.access == .agentRequest)
    #expect(surfaceFrame.stateEffect == .workspaceMutation)
    #expect(surfaceFrame.requiresExpectedWorkspaceRevision)
    #expect(surfaceFrame.targets == [.face, .surfaceControlPoint, .surfaceTrim])
    #expect(surfaceFrame.discovery.contains(.surfaceFrames))
}

@Test(.timeLimit(.minutes(1)))
func agentCapabilityRegistryProjectsTheTypedAgentSurface() throws {
    let controller = AgentCommandController()
    let registry = try controller.capabilityRegistry()

    #expect(registry.descriptors(for: .agent).count == controller.capabilityDescriptors().count)
    #expect(registry.descriptor(for: "agent.describeDocument")?.effect == .query)
    #expect(registry.descriptor(for: "agent.movePolySplineSurfaceVertex")?.effect == .sourceMutation)
    #expect(registry.descriptor(for: "agent.setSurfaceFrameDisplay")?.effect == .workspaceMutation)
    #expect(registry.descriptor(for: "agent.createSweep") == nil)
}

@Test(.timeLimit(.minutes(1)))
func agentProtocolExposesTypedCapabilityRegistryDiscovery() throws {
    let response = AgentCommandController().handle(.capabilityRegistry)
    guard case .capabilityRegistry(let descriptors) = response else {
        Issue.record("Expected the universal capability registry response.")
        return
    }

    #expect(descriptors.contains { $0.id.rawValue == "agent.describeDocument" })
    #expect(descriptors.contains { $0.id.rawValue == "agent.movePolySplineSurfaceVertex" })
    #expect(!descriptors.contains { $0.id.rawValue == "agent.createSweep" })
}

@Test(.timeLimit(.minutes(1)))
func agentCapabilityDescriptorsIncludeInjectedDomainCapabilities() throws {
    let namespace: SemanticNamespaceID = "architecture"
    let capabilityID: DomainCapabilityID = "architecture.createWall"
    let registry = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: namespace,
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: capabilityID,
                namespace: namespace,
                name: "Create Wall",
                summary: "Create a semantic wall projection.",
                effect: .documentMutation,
                resultKind: .documentTransaction,
                supportsDryRun: true,
                targetKinds: ["document", "level", "room"],
                failureMode: "Rejects invalid wall baselines before mutation."
            ),
        ],
        commandLowerings: [
            AgentCapabilityFixtureDomainLowering(capabilityID: capabilityID),
        ]
    )
    let descriptor = try #require(
        AgentCommandController(domainRegistry: registry)
            .capabilityDescriptors()
            .first { $0.name == capabilityID.rawValue }
    )

    #expect(descriptor.category == .domain)
    #expect(descriptor.access == .domainCapability)
    #expect(descriptor.stateEffect == .sourceMutation)
    #expect(descriptor.requiresExpectedSourceGeneration)
    #expect(descriptor.supportsDryRun)
    #expect(descriptor.domainContract?.effect == .documentMutation)
    #expect(descriptor.domainContract?.resultKind == .documentTransaction)
    #expect(descriptor.targets == [.document])
}

private struct AgentCapabilityFixtureDomainLowering: DomainCommandLowering {
    var capabilityID: DomainCapabilityID

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        .automationBatch(
            AutomationBatch(
                commands: [.renameDocument(name: "Agent Capability Fixture")],
                expectedGeneration: request.expectedGeneration
            )
        )
    }
}
