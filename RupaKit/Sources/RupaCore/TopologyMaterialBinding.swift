import Foundation
import SwiftCAD

public struct TopologyMaterialBinding: Codable, Hashable, Identifiable, Sendable {
    public struct ID: Codable, Hashable, RawRepresentable, Sendable {
        public var rawValue: UUID

        public init() {
            self.rawValue = UUID()
        }

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public init(_ rawValue: UUID) {
            self.rawValue = rawValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.rawValue = try container.decode(UUID.self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public struct Process: Codable, Hashable, Sendable {
        public var namespace: String
        public var processID: String

        public init(namespace: String, processID: String) {
            self.namespace = namespace
            self.processID = processID
        }

        public func validate() throws {
            guard !namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Topology material process namespace must not be empty."
                )
            }
            guard !processID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Topology material process ID must not be empty."
                )
            }
        }
    }

    public var id: ID
    public var target: SelectionTarget
    public var materialID: MaterialID?
    public var process: Process?

    public init(
        id: ID = ID(),
        target: SelectionTarget,
        materialID: MaterialID?,
        process: Process? = nil
    ) {
        self.id = id
        self.target = target
        self.materialID = materialID
        self.process = process
    }

    public func stableReference() throws -> StableSubshapeReference {
        guard case .face(let componentID) = target.component else {
            throw DocumentValidationError.invalidProductMetadata(
                "Topology material binding must target a stable face."
            )
        }
        return try componentID.stableTopologyReference(
            operationName: "Topology material binding"
        )
    }

    public func validate(metadata: ProductMetadata) throws {
        guard metadata.sceneNodes[target.sceneNodeID] != nil else {
            throw DocumentValidationError.invalidProductMetadata(
                "Topology material binding target references a missing scene node."
            )
        }
        _ = try stableReference()
        if let materialID,
           metadata.materialLibrary.materials[materialID] == nil {
            throw DocumentValidationError.invalidProductMetadata(
                "Topology material binding references a missing material."
            )
        }
        try process?.validate()
    }
}
