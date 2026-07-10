import SwiftCAD

public struct MeshArtifactConfiguration: Codable, Hashable, Sendable {
    public let kernelVersion: SchemaVersion
    public let modelingTolerance: ModelingTolerance
    public let tessellationOptions: TessellationOptions

    public init(
        kernelVersion: SchemaVersion,
        modelingTolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions
    ) throws {
        try kernelVersion.validate()
        try modelingTolerance.validate()
        try tessellationOptions.validate()
        self.kernelVersion = kernelVersion
        self.modelingTolerance = modelingTolerance
        self.tessellationOptions = tessellationOptions
    }

    public func identity() throws -> ArtifactConfigurationIdentity {
        try ArtifactConfigurationIdentity(
            schemaID: "rupa.mesh-artifact-configuration",
            schemaVersion: "1.0.0",
            value: .object([
                "kernelVersion": .object([
                    "major": .number(Double(kernelVersion.major)),
                    "minor": .number(Double(kernelVersion.minor)),
                    "patch": .number(Double(kernelVersion.patch)),
                ]),
                "modelingTolerance": .object([
                    "distance": .number(modelingTolerance.distance),
                    "angle": .number(modelingTolerance.angle),
                ]),
                "tessellationOptions": .object([
                    "linearTolerance": .number(tessellationOptions.linearTolerance),
                    "angularTolerance": .number(tessellationOptions.angularTolerance),
                    "maxEdgeLength": tessellationOptions.maxEdgeLength.map(SemanticJSONValue.number) ?? .null,
                ]),
            ])
        )
    }
}
