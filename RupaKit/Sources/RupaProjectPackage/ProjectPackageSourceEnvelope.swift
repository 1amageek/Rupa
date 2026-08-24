import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

struct ProjectPackageSourceEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion: UInt32 = 1

    struct MeshRecord: Codable, Equatable, Sendable {
        let id: GeometrySourceID
        let blob: ProjectSourceBlobReference
    }

    let schemaVersion: UInt32
    let projectID: ProjectID
    let name: String
    let meshes: [MeshRecord]
    let objectDefinitions: [ObjectDefinition]
    let occurrences: [SceneOccurrence]
    let rootOccurrenceIDs: [SceneOccurrenceID]

    init(
        project: ProjectSourceModel,
        meshBlobs: [GeometrySourceID: ProjectSourceBlobReference]
    ) throws {
        do {
            try project.validate()
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project source validation failed: \(error)."
            )
        }
        guard Set(project.meshSources.keys) == Set(meshBlobs.keys) else {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Every mesh source must have exactly one package blob reference."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        projectID = project.id
        name = project.name
        meshes = try project.meshSources.keys.sorted(by: { $0.rawValue < $1.rawValue }).map {
            guard let blob = meshBlobs[$0] else {
                throw ProjectPackageError(
                    code: .missingEntry,
                    message: "Mesh source \($0.rawValue) is missing its blob reference."
                )
            }
            return MeshRecord(id: $0, blob: blob)
        }
        objectDefinitions = project.objectDefinitions.values.sorted {
            $0.id.rawValue < $1.id.rawValue
        }
        occurrences = project.occurrences.values.sorted {
            $0.id.rawValue < $1.id.rawValue
        }
        rootOccurrenceIDs = project.rootOccurrenceIDs
    }

    func makeProject(
        meshSources: [GeometrySourceID: MeshSource]
    ) throws -> ProjectSourceModel {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ProjectPackageError(
                code: .unsupportedVersion,
                message: "Project source metadata schema version is unsupported."
            )
        }
        var blobIDs: Set<GeometrySourceID> = []
        for record in meshes {
            guard blobIDs.insert(record.id).inserted else {
                throw ProjectPackageError(
                    code: .duplicateEntry,
                    message: "Project source metadata contains a duplicate mesh identity."
                )
            }
            guard meshSources[record.id]?.identity == record.id else {
                throw ProjectPackageError(
                    code: .invalidSource,
                    message: "Decoded mesh source identities must match source metadata."
                )
            }
        }
        guard blobIDs == Set(meshSources.keys) else {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Decoded mesh sources must exactly match source metadata."
            )
        }

        var definitions: [ObjectDefinitionID: ObjectDefinition] = [:]
        for definition in objectDefinitions {
            guard definitions.updateValue(definition, forKey: definition.id) == nil else {
                throw ProjectPackageError(
                    code: .duplicateEntry,
                    message: "Project source metadata contains a duplicate object definition."
                )
            }
        }
        var decodedOccurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
        for occurrence in occurrences {
            guard decodedOccurrences.updateValue(occurrence, forKey: occurrence.id) == nil else {
                throw ProjectPackageError(
                    code: .duplicateEntry,
                    message: "Project source metadata contains a duplicate occurrence."
                )
            }
        }
        do {
            return try ProjectSourceModel(
                id: projectID,
                name: name,
                meshSources: meshSources,
                objectDefinitions: definitions,
                occurrences: decodedOccurrences,
                rootOccurrenceIDs: rootOccurrenceIDs
            )
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Decoded project source is invalid: \(error)."
            )
        }
    }
}
