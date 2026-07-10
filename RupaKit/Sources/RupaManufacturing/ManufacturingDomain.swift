import RupaCore
import RupaDomainFoundation

public enum ManufacturingDomain {
    public static let namespace: SemanticNamespaceID = "manufacturing"
    public static let schemaVersion = SemanticSchemaVersion(major: 0, minor: 1, patch: 0)
    public static let validatePrintabilityCapabilityID: DomainCapabilityID = "manufacturing.validatePrintability"

    public static func registry(
        processCatalog: any ManufacturingProcessCatalog = StandardManufacturingProcessCatalog()
    ) throws -> DomainRegistry {
        try processCatalog.validate()
        return try DomainRegistry(
            namespaces: [
                DomainNamespaceRegistration(
                    namespace: namespace,
                    supportedSchemaVersions: [schemaVersion]
                ),
            ],
            capabilityDescriptors: [
                DomainCapabilityDescriptor(
                    id: validatePrintabilityCapabilityID,
                    namespace: namespace,
                    name: "Validate Printability",
                    summary: "Analyzes generated body meshes for manufacturing printability without mutating the document.",
                    effect: .query,
                    resultKind: .validationReport,
                    supportsDryRun: true,
                    resultFidelity: .sampledApproximation,
                    targetKinds: ["document"],
                    parameters: printabilityParameters(processCatalog: processCatalog),
                    knownErrorCodes: [
                        "commandInvalid",
                        "documentGenerationMismatch",
                        "evaluationUnavailable",
                        "unsupportedProcess",
                    ],
                    failureMode: "Rejects invalid manufacturing analysis options before reporting typed printability diagnostics."
                ),
            ],
            commandLowerings: [
                ManufacturingPrintabilityLowering(processCatalog: processCatalog),
            ]
        )
    }

    private static func printabilityParameters(
        processCatalog: any ManufacturingProcessCatalog
    ) -> [DomainCommandParameterDescriptor] {
        let processChoices = processCatalog.profiles
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map { profile in
                DomainCommandParameterChoice(
                    value: profile.id.rawValue,
                    label: profile.name,
                    summary: profile.summary
                )
            }
        return [
        DomainCommandParameterDescriptor(
            id: "processID",
            payloadPath: ["processID"],
            label: "Process",
            summary: "Manufacturing process used to interpret printability requirements.",
            group: "Process",
            kind: .choice,
            defaultValue: .string(processCatalog.defaultProcessID.rawValue),
            choices: processChoices
        ),
        DomainCommandParameterDescriptor(
            id: "buildWidth",
            payloadPath: ["buildVolume", "widthMeters"],
            label: "Build Width",
            summary: "Available build width in meters in the command payload.",
            group: "Build Volume",
            kind: .length,
            unit: .meter,
            defaultValue: .number(0.256),
            minimumValue: 0.000_001
        ),
        DomainCommandParameterDescriptor(
            id: "buildDepth",
            payloadPath: ["buildVolume", "depthMeters"],
            label: "Build Depth",
            summary: "Available build depth in meters in the command payload.",
            group: "Build Volume",
            kind: .length,
            unit: .meter,
            defaultValue: .number(0.256),
            minimumValue: 0.000_001
        ),
        DomainCommandParameterDescriptor(
            id: "buildHeight",
            payloadPath: ["buildVolume", "heightMeters"],
            label: "Build Height",
            summary: "Available build height in meters in the command payload.",
            group: "Build Volume",
            kind: .length,
            unit: .meter,
            defaultValue: .number(0.256),
            minimumValue: 0.000_001
        ),
        DomainCommandParameterDescriptor(
            id: "requireMaterialAssignment",
            payloadPath: ["requireMaterialAssignment"],
            label: "Require Material",
            summary: "Report incomplete material coverage as a manufacturing issue.",
            group: "Requirements",
            kind: .boolean,
            defaultValue: .bool(true)
        ),
        DomainCommandParameterDescriptor(
            id: "requireExportReadyMesh",
            payloadPath: ["requireExportReadyMesh"],
            label: "Require Watertight Mesh",
            summary: "Require solid, watertight, non-degenerate generated meshes.",
            group: "Requirements",
            kind: .boolean,
            defaultValue: .bool(true)
        ),
        DomainCommandParameterDescriptor(
            id: "overhangLimit",
            payloadPath: ["overhangLimitDegrees"],
            label: "Overhang Limit",
            summary: "Maximum self-supporting overhang angle in degrees.",
            group: "Thresholds",
            kind: .angle,
            unit: .degree,
            defaultValue: .number(45.0),
            minimumValue: 0.000_001,
            maximumValue: 90.0
        ),
        DomainCommandParameterDescriptor(
            id: "minimumWallThickness",
            payloadPath: ["minimumWallThicknessMeters"],
            label: "Minimum Wall",
            summary: "Minimum accepted wall thickness in meters, or null to disable the check.",
            group: "Thresholds",
            kind: .length,
            unit: .meter,
            allowsNull: true,
            defaultValue: .number(0.0008),
            minimumValue: 0.000_001
        ),
        DomainCommandParameterDescriptor(
            id: "minimumClearance",
            payloadPath: ["minimumClearanceMeters"],
            label: "Minimum Clearance",
            summary: "Minimum accepted body clearance in meters, or null to disable the check.",
            group: "Thresholds",
            kind: .length,
            unit: .meter,
            allowsNull: true,
            defaultValue: .number(0.0002),
            minimumValue: 0.000_001
        ),
        ]
    }
}
