import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

/// Stages one validated file-exchange Mesh as an Authored Mesh Product source.
///
/// File access, exchange parsing, and content provenance are owned by the
/// higher-level adapter. Core allocates the persistent source, representation,
/// and scene identities while applying the command to a staged document.
public struct ImportAuthoredMeshCommand: Codable, Equatable, Sendable {
    public let source: MeshSource
    public let provenance: AuthoredMeshProvenance
    public let name: String

    public init(
        source: MeshSource,
        provenance: AuthoredMeshProvenance,
        name: String
    ) {
        self.source = source
        self.provenance = provenance
        self.name = name
    }

    public func validate() throws {
        do {
            try source.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Imported Authored Mesh source is invalid: \(error)."
            )
        }
        do {
            try provenance.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Imported Authored Mesh provenance is invalid: \(error)."
            )
        }
        guard case .imported = provenance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Imported Authored Mesh commands require imported provenance."
            )
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Imported Authored Mesh names must not be empty."
            )
        }
    }
}
