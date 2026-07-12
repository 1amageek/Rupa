import Foundation
import RupaCapabilities
import RupaCoreTypes
import Testing

@Test(.timeLimit(.minutes(1)))
func capabilityRegistryIndexesDescriptorsAndMatchesVersions() throws {
    let descriptor = try fixtureDescriptor()
    let registry = try CapabilityRegistry(descriptors: [descriptor])

    #expect(registry.count == 1)
    #expect(registry.descriptor(for: descriptor.id)?.version == descriptor.version)
    #expect(try registry.descriptor(for: descriptor.id, version: descriptor.version) == descriptor)
    #expect(registry.descriptors(for: .agent).map(\.id) == [descriptor.id])
}

@Test(.timeLimit(.minutes(1)))
func capabilityRegistryRejectsDuplicateIDsAndVersionMismatch() throws {
    let descriptor = try fixtureDescriptor()
    var duplicateError: CapabilityRegistryError?

    do {
        _ = try CapabilityRegistry(descriptors: [descriptor, descriptor])
    } catch let error as CapabilityRegistryError {
        duplicateError = error
    }

    #expect(duplicateError?.code == .duplicateCapability)

    let registry = try CapabilityRegistry(descriptors: [descriptor])
    var versionError: CapabilityRegistryError?
    do {
        _ = try registry.descriptor(
            for: descriptor.id,
            version: CapabilityVersion(major: 2, minor: 0, patch: 0)
        )
    } catch let error as CapabilityRegistryError {
        versionError = error
    }

    #expect(versionError?.code == .versionMismatch)
}

@Test(.timeLimit(.minutes(1)))
func capabilityDescriptorRejectsConflictingPayloadPaths() throws {
    let descriptor = CapabilityDescriptor(
        id: "modeling.invalid",
        version: CapabilityVersion(major: 1, minor: 0, patch: 0),
        category: "modeling",
        name: "Invalid",
        summary: "Contains conflicting payload paths.",
        effect: .query,
        result: CapabilityResultDescriptor(kind: .semanticPayload),
        parameters: [
            CapabilityParameterDescriptor(
                id: "volume",
                payloadPath: ["volume"],
                label: "Volume",
                summary: "Whole volume.",
                kind: .number
            ),
            CapabilityParameterDescriptor(
                id: "width",
                payloadPath: ["volume", "width"],
                label: "Width",
                summary: "Volume width.",
                kind: .length,
                unit: .meter
            ),
        ],
        execution: CapabilityExecutionContract(supportsDryRun: true),
        availability: CapabilityAvailability(surfaces: [.agent]),
        failureMode: "Rejects invalid payload schemas."
    )
    var caught: CapabilityRegistryError?

    do {
        try descriptor.validate()
    } catch let error as CapabilityRegistryError {
        caught = error
    }

    #expect(caught?.code == .invalidDescriptor)
    #expect(caught?.message.contains("conflicting parameter payload paths") == true)
}

@Test(.timeLimit(.minutes(1)))
func canonicalValueRoundTripsWithStableObjectOrdering() throws {
    let value: CanonicalValue = .object([
        "z": .number(4),
        "a": .array([.bool(true), .null]),
    ])
    let data = try value.canonicalJSONData()
    #expect(String(decoding: data, as: UTF8.self) == "{\"a\":[true,null],\"z\":4}")

    let decoded = try JSONDecoder().decode(CanonicalValue.self, from: data)
    #expect(decoded == value)
}

private func fixtureDescriptor() throws -> CapabilityDescriptor {
    let descriptor = CapabilityDescriptor(
        id: "modeling.createBox",
        version: CapabilityVersion(major: 1, minor: 0, patch: 0),
        category: "modeling",
        name: "Create Box",
        summary: "Creates a parametric box source feature.",
        effect: .sourceMutation,
        result: CapabilityResultDescriptor(kind: .sourceTransaction),
        targets: [
            CapabilityTargetDescriptor(
                id: "document",
                name: "Document",
                summary: "The active source document."
            ),
        ],
        parameters: [
            CapabilityParameterDescriptor(
                id: "width",
                payloadPath: ["dimensions", "width"],
                label: "Width",
                summary: "Box width.",
                kind: .length,
                unit: .meter,
                isRequired: true,
                defaultValue: .number(1),
                minimumValue: 0.000_001
            ),
        ],
        execution: CapabilityExecutionContract(
            supportsDryRun: true,
            supportsCancellation: true,
            reportsProgress: true,
            requiresTransactionRevision: true
        ),
        availability: CapabilityAvailability(surfaces: [.swiftAPI, .ui, .cli, .agent, .mcp]),
        failureMode: "Rejects non-positive dimensions before source mutation."
    )
    try descriptor.validate()
    return descriptor
}
