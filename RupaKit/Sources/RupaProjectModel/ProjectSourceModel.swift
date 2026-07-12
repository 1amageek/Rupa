import Foundation
import RupaGeometry

public struct ProjectSourceModel: Codable, Equatable, Sendable {
    public var id: ProjectID
    public var name: String
    public var meshSources: [MeshSourceID: MeshSource]
    public var objectDefinitions: [ObjectDefinitionID: ObjectDefinition]
    public var occurrences: [SceneOccurrenceID: SceneOccurrence]
    public var rootOccurrenceIDs: [SceneOccurrenceID]

    public init(
        id: ProjectID,
        name: String,
        meshSources: [MeshSourceID: MeshSource] = [:],
        objectDefinitions: [ObjectDefinitionID: ObjectDefinition] = [:],
        occurrences: [SceneOccurrenceID: SceneOccurrence] = [:],
        rootOccurrenceIDs: [SceneOccurrenceID] = []
    ) throws {
        self.id = id
        self.name = name
        self.meshSources = meshSources
        self.objectDefinitions = objectDefinitions
        self.occurrences = occurrences
        self.rootOccurrenceIDs = rootOccurrenceIDs
        try validate()
    }

    public func validate() throws {
        try id.validate()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectModelError(code: .invalidIdentity, message: "Project names must not be empty.")
        }
        for (sourceID, source) in meshSources {
            guard sourceID == source.identity else {
                throw ProjectModelError(code: .invalidReference, message: "Mesh source dictionary keys must match source identities.")
            }
            try source.validate()
        }
        for (definitionID, definition) in objectDefinitions {
            guard definitionID == definition.id else {
                throw ProjectModelError(code: .invalidReference, message: "Object definition dictionary keys must match identities.")
            }
            try definition.validate()
            if case .mesh(let sourceID) = definition.geometry {
                guard meshSources[sourceID] != nil else {
                    throw ProjectModelError(code: .invalidReference, message: "Object definition references a missing mesh source.")
                }
            }
        }
        for (occurrenceID, occurrence) in occurrences {
            guard occurrenceID == occurrence.id else {
                throw ProjectModelError(code: .invalidReference, message: "Occurrence dictionary keys must match identities.")
            }
            try occurrence.validate()
            guard objectDefinitions[occurrence.definitionID] != nil else {
                throw ProjectModelError(code: .invalidReference, message: "Scene occurrence references a missing object definition.")
            }
            if let parentID = occurrence.parentID {
                guard occurrences[parentID] != nil else {
                    throw ProjectModelError(code: .invalidReference, message: "Scene occurrence references a missing parent.")
                }
            }
        }
        guard Set(rootOccurrenceIDs).count == rootOccurrenceIDs.count else {
            throw ProjectModelError(code: .duplicateRoot, message: "Root occurrence IDs must be unique.")
        }
        for rootID in rootOccurrenceIDs {
            guard let root = occurrences[rootID], root.parentID == nil else {
                throw ProjectModelError(code: .invalidReference, message: "Root occurrence IDs must reference parentless occurrences.")
            }
        }
        let parentlessOccurrenceIDs = Set(
            occurrences.values.compactMap { occurrence in
                occurrence.parentID == nil ? occurrence.id : nil
            }
        )
        guard parentlessOccurrenceIDs == Set(rootOccurrenceIDs) else {
            throw ProjectModelError(
                code: .invalidReference,
                message: "Every parentless occurrence must appear exactly once in the root occurrence list."
            )
        }
        try validateAcyclicHierarchy()
    }

    public func adding(_ source: MeshSource) throws -> ProjectSourceModel {
        var result = self
        result.meshSources[source.identity] = source
        try result.validate()
        return result
    }

    public func adding(_ definition: ObjectDefinition) throws -> ProjectSourceModel {
        var result = self
        result.objectDefinitions[definition.id] = definition
        try result.validate()
        return result
    }

    public func adding(_ occurrence: SceneOccurrence, asRoot: Bool = false) throws -> ProjectSourceModel {
        var result = self
        result.occurrences[occurrence.id] = occurrence
        if asRoot {
            result.rootOccurrenceIDs.append(occurrence.id)
        }
        try result.validate()
        return result
    }

    private func validateAcyclicHierarchy() throws {
        for occurrenceID in occurrences.keys {
            var seen: Set<SceneOccurrenceID> = []
            var currentID: SceneOccurrenceID? = occurrenceID
            while let current = currentID {
                guard seen.insert(current).inserted else {
                    throw ProjectModelError(code: .hierarchyCycle, message: "Scene occurrence hierarchy contains a cycle.")
                }
                currentID = occurrences[current]?.parentID
            }
        }
    }
}
