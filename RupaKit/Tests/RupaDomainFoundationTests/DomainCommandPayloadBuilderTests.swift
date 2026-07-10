import RupaAutomation
import RupaCore
import Testing
@testable import RupaDomainFoundation

@Test(.timeLimit(.minutes(1)))
func domainCommandPayloadBuilderBuildsNestedPayloadFromDefaultsAndOverrides() throws {
    let descriptor = try parameterizedCapabilityDescriptor()
    let builder = DomainCommandPayloadBuilder()
    var values = builder.defaultValues(for: descriptor)
    values["width"] = .number(0.42)
    values["minimumWall"] = .null

    let payload = try builder.payload(for: descriptor, values: values)

    #expect(payload == .object([
        "buildVolume": .object([
            "widthMeters": .number(0.42),
        ]),
        "minimumWallThicknessMeters": .null,
        "process": .string("additive"),
    ]))
}

@Test(.timeLimit(.minutes(1)))
func domainCommandPayloadBuilderRejectsUnknownAndOutOfRangeValues() throws {
    let descriptor = try parameterizedCapabilityDescriptor()
    let builder = DomainCommandPayloadBuilder()
    var unknownValues = builder.defaultValues(for: descriptor)
    unknownValues["unsupported"] = .bool(true)
    var unknownError: DomainCommandPayloadError?

    do {
        _ = try builder.payload(for: descriptor, values: unknownValues)
    } catch let error as DomainCommandPayloadError {
        unknownError = error
    }

    #expect(unknownError?.code == .unknownParameter)
    #expect(unknownError?.parameterID == "unsupported")

    var outOfRangeValues = builder.defaultValues(for: descriptor)
    outOfRangeValues["width"] = .number(0.0)
    var rangeError: DomainCommandPayloadError?

    do {
        _ = try builder.payload(for: descriptor, values: outOfRangeValues)
    } catch let error as DomainCommandPayloadError {
        rangeError = error
    }

    #expect(rangeError?.code == .invalidValue)
    #expect(rangeError?.parameterID == "width")
}

@Test(.timeLimit(.minutes(1)))
func domainCommandParameterRejectsIntegerOutsidePlatformRange() throws {
    let parameter = DomainCommandParameterDescriptor(
        id: "count",
        payloadPath: ["count"],
        label: "Count",
        summary: "Integer count.",
        kind: .integer,
        defaultValue: .number(1e100)
    )
    var caught: DomainRegistryError?

    do {
        try parameter.validate()
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .invalidRegistration)
    #expect(caught?.message.contains("representable by the current platform") == true)
}

@Test(.timeLimit(.minutes(1)))
func domainCapabilityDescriptorRejectsConflictingPayloadPaths() throws {
    var caught: DomainRegistryError?

    do {
        _ = try DomainRegistry(
            namespaces: [
                DomainNamespaceRegistration(
                    namespace: "manufacturing",
                    supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
                ),
            ],
            capabilityDescriptors: [
                DomainCapabilityDescriptor(
                    id: "manufacturing.invalid",
                    namespace: "manufacturing",
                    name: "Invalid",
                    summary: "Contains conflicting payload paths.",
                    effect: .query,
                    resultKind: .semanticPayload,
                    supportsDryRun: true,
                    parameters: [
                        DomainCommandParameterDescriptor(
                            id: "buildVolume",
                            payloadPath: ["buildVolume"],
                            label: "Build Volume",
                            summary: "Whole build volume value.",
                            kind: .number,
                            defaultValue: .number(1.0)
                        ),
                        DomainCommandParameterDescriptor(
                            id: "buildWidth",
                            payloadPath: ["buildVolume", "widthMeters"],
                            label: "Build Width",
                            summary: "Nested build width value.",
                            kind: .length,
                            unit: .meter,
                            defaultValue: .number(0.2)
                        ),
                    ],
                    failureMode: "Rejects invalid input schemas."
                ),
            ]
        )
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .invalidRegistration)
    #expect(caught?.message.contains("conflicting parameter payload paths") == true)
}

private func parameterizedCapabilityDescriptor() throws -> DomainCapabilityDescriptor {
    let registry = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "manufacturing",
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: "manufacturing.validate",
                namespace: "manufacturing",
                name: "Validate",
                summary: "Validates a manufacturing payload.",
                effect: .query,
                resultKind: .semanticPayload,
                supportsDryRun: true,
                parameters: [
                    DomainCommandParameterDescriptor(
                        id: "process",
                        payloadPath: ["process"],
                        label: "Process",
                        summary: "Selected process.",
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
                    DomainCommandParameterDescriptor(
                        id: "width",
                        payloadPath: ["buildVolume", "widthMeters"],
                        label: "Width",
                        summary: "Build width in meters.",
                        kind: .length,
                        unit: .meter,
                        defaultValue: .number(0.256),
                        minimumValue: 0.000_001
                    ),
                    DomainCommandParameterDescriptor(
                        id: "minimumWall",
                        payloadPath: ["minimumWallThicknessMeters"],
                        label: "Minimum Wall",
                        summary: "Minimum wall thickness in meters.",
                        kind: .length,
                        unit: .meter,
                        allowsNull: true,
                        defaultValue: .number(0.0008),
                        minimumValue: 0.000_001
                    ),
                ],
                failureMode: "Rejects invalid manufacturing values."
            ),
        ],
        commandLowerings: [
            PayloadBuilderFixtureLowering(capabilityID: "manufacturing.validate"),
        ]
    )
    return try #require(registry.capabilityDescriptor(for: "manufacturing.validate"))
}

private struct PayloadBuilderFixtureLowering: DomainCommandLowering {
    var capabilityID: DomainCapabilityID

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        .automationBatch(
            AutomationBatch(
                commands: [.renameDocument(name: "Payload Builder Fixture")],
                expectedGeneration: request.expectedGeneration
            )
        )
    }
}
