import RupaCapabilities
import RupaAutomation
import RupaCore
import RupaCoreTypes
import Testing
@testable import RupaDomainFoundation

@Test(.timeLimit(.minutes(1)))
func domainRegistryExportsCapabilitiesToUniversalRegistry() throws {
    let domainRegistry = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "manufacturing",
                supportedSchemaVersions: [
                    SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
                ]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: "manufacturing.validate",
                namespace: "manufacturing",
                name: "Validate",
                summary: "Validates a manufacturing source.",
                effect: .query,
                resultKind: .validationReport,
                supportsDryRun: true,
                resultFidelity: .exact,
                targetKinds: ["document"],
                parameters: [
                    DomainCommandParameterDescriptor(
                        id: "process",
                        payloadPath: ["process"],
                        label: "Process",
                        summary: "Manufacturing process.",
                        kind: .choice,
                        defaultValue: .string("additive"),
                        choices: [
                            DomainCommandParameterChoice(
                                value: "additive",
                                label: "Additive",
                                summary: "Additive manufacturing."
                            ),
                        ]
                    ),
                ],
                failureMode: "Reports exact manufacturing diagnostics."
            ),
        ],
        commandLowerings: [EmptyBridgeLowering(capabilityID: "manufacturing.validate")]
    )

    let registry = try domainRegistry.capabilityRegistry()
    let descriptor = try #require(registry.descriptor(for: "manufacturing.validate"))

    #expect(registry.count == 1)
    #expect(descriptor.category == "manufacturing")
    #expect(descriptor.effect == .query)
    #expect(descriptor.result.kind == .validationReport)
    #expect(descriptor.result.maximumFidelity == ValidationFidelity.exact.rawValue)
    #expect(descriptor.parameters[0].defaultValue == .string("additive"))
    #expect(descriptor.availability.surfaces.contains(.mcp))
}

private struct EmptyBridgeLowering: DomainCommandLowering {
    var capabilityID: DomainCapabilityID

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        .automationBatch(
            AutomationBatch(
                commands: [],
                expectedGeneration: request.expectedGeneration
            )
        )
    }
}
