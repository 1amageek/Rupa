import RupaAutomation
import RupaCore
import RupaDomainFoundation
import Testing
@testable import RupaUI

@Test(.timeLimit(.minutes(1)))
func workspaceCommandCatalogMapsDomainCapabilitiesInStableOrder() throws {
    let registry = try workspaceCommandCatalogDomainRegistry()
    let catalog = WorkspaceCommandCatalog(domainRegistry: registry)

    #expect(catalog.hasDomainCommands)
    #expect(catalog.domainCommands.map(\.id) == [
        "architecture.createWall",
        "manufacturing.validatePrintability",
    ])

    let wallCommand = try #require(catalog.domainCommands.first)
    #expect(wallCommand.title == "Create Wall")
    #expect(wallCommand.subtitle == "architecture")
    #expect(wallCommand.category == .domain)
    #expect(wallCommand.mutatesDocument)
    #expect(wallCommand.supportsDryRun)
    #expect(wallCommand.targetSummary == "path, level")
    #expect(wallCommand.failureMode == "Rejects missing path or level references before mutation.")
    #expect(wallCommand.domainCapability.parameters.map(\.id) == ["height"])
}

@Test(.timeLimit(.minutes(1)))
func workspaceDomainCommandDraftBuildsGenerationSafeUnitNormalizedRequest() throws {
    let registry = try workspaceCommandCatalogDomainRegistry()
    let catalog = WorkspaceCommandCatalog(domainRegistry: registry)
    let wallCommand = try #require(catalog.domainCommands.first)
    var draft = WorkspaceDomainCommandDraft(descriptor: wallCommand.domainCapability)
    #expect(!draft.hasExplicitValue(for: "height"))
    draft.setValue(.number(3.2), for: "height")
    #expect(draft.hasExplicitValue(for: "height"))

    let request = try draft.request(
        descriptor: wallCommand.domainCapability,
        generation: DocumentGeneration(14),
        dryRun: true
    )

    #expect(request.capabilityID == "architecture.createWall")
    #expect(request.namespace == "architecture")
    #expect(request.expectedGeneration == DocumentGeneration(14))
    #expect(request.dryRun)
    #expect(request.payload == .object(["heightMeters": .number(3.2)]))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func mainViewAcceptsInjectedDomainRegistry() throws {
    let registry = try workspaceCommandCatalogDomainRegistry()
    _ = MainView(
        session: EditorSession(),
        domainRegistry: registry
    )
}

private func workspaceCommandCatalogDomainRegistry() throws -> DomainRegistry {
    try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "manufacturing",
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
            DomainNamespaceRegistration(
                namespace: "architecture",
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: "manufacturing.validatePrintability",
                namespace: "manufacturing",
                name: "Validate Printability",
                summary: "Checks additive manufacturing constraints.",
                effect: .query,
                resultKind: .semanticPayload,
                supportsDryRun: true,
                targetKinds: ["body"],
                failureMode: "Reports typed diagnostics without mutating source."
            ),
            DomainCapabilityDescriptor(
                id: "architecture.createWall",
                namespace: "architecture",
                name: "Create Wall",
                summary: "Creates an architecture wall projection.",
                effect: .documentMutation,
                resultKind: .documentTransaction,
                supportsDryRun: true,
                targetKinds: ["path", "level"],
                parameters: [
                    DomainCommandParameterDescriptor(
                        id: "height",
                        payloadPath: ["heightMeters"],
                        label: "Height",
                        summary: "Wall height in meters.",
                        kind: .length,
                        unit: .meter,
                        isRequired: true,
                        minimumValue: 0.000_001
                    ),
                ],
                failureMode: "Rejects missing path or level references before mutation."
            ),
        ],
        commandLowerings: [
            WorkspaceFixtureDomainLowering(capabilityID: "manufacturing.validatePrintability"),
            WorkspaceFixtureDomainLowering(capabilityID: "architecture.createWall"),
        ]
    )
}

private struct WorkspaceFixtureDomainLowering: DomainCommandLowering {
    var capabilityID: DomainCapabilityID

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        .automationBatch(
            AutomationBatch(
                commands: [.renameDocument(name: "Workspace Fixture")],
                expectedGeneration: request.expectedGeneration
            )
        )
    }
}
