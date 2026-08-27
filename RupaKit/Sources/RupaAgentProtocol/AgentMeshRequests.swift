import Foundation
import RupaCore
import RupaGeometry
import RupaKit

/// Bounded catalog inspection request for one registered project session.
public struct AgentMeshCatalogRequest: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let expectedGeneration: DocumentGeneration
    public let limits: ProjectMeshReadLimits

    public init(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration,
        limits: ProjectMeshReadLimits = .standard
    ) {
        self.sessionID = sessionID
        self.expectedGeneration = expectedGeneration
        self.limits = limits
    }

    public func validate() throws {
        try limits.validateForAgentRequest()
    }
}

/// Bounded page inspection request. The handle is an exact source coordinate.
public struct AgentMeshPageRequest: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let expectedGeneration: DocumentGeneration
    public let handle: ProjectMeshSourceHandle
    public let domain: ProjectMeshElementDomain
    public let cursor: ProjectMeshElementCursor?
    public let limits: ProjectMeshReadLimits

    public init(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration,
        handle: ProjectMeshSourceHandle,
        domain: ProjectMeshElementDomain,
        cursor: ProjectMeshElementCursor? = nil,
        limits: ProjectMeshReadLimits = .standard
    ) {
        self.sessionID = sessionID
        self.expectedGeneration = expectedGeneration
        self.handle = handle
        self.domain = domain
        self.cursor = cursor
        self.limits = limits
    }

    public func validate() throws {
        try limits.validateForAgentRequest()
        if let cursor, cursor.domain != domain {
            throw EditorError(
                code: .commandInvalid,
                message: "The Mesh page cursor domain must match the requested domain."
            )
        }
    }
}

/// Bounded neighborhood inspection request. The handle is an exact source coordinate.
public struct AgentMeshNeighborhoodRequest: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let expectedGeneration: DocumentGeneration
    public let handle: ProjectMeshSourceHandle
    public let origin: ProjectMeshElementReference
    public let depth: Int
    public let limits: ProjectMeshReadLimits

    public init(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration,
        handle: ProjectMeshSourceHandle,
        origin: ProjectMeshElementReference,
        depth: Int,
        limits: ProjectMeshReadLimits = .standard
    ) {
        self.sessionID = sessionID
        self.expectedGeneration = expectedGeneration
        self.handle = handle
        self.origin = origin
        self.depth = depth
        self.limits = limits
    }

    public func validate() throws {
        try limits.validateForAgentRequest()
        guard depth >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Mesh neighborhood depth must not be negative."
            )
        }
        guard depth <= limits.maxNeighborhoodDepth else {
            throw EditorError(
                code: .commandInvalid,
                message: "Mesh neighborhood depth exceeds the requested limit."
            )
        }
    }
}

/// Explicitly selects a non-publishing preview or a publishing commit.
public enum AgentMeshEditMode: String, Codable, Equatable, Sendable {
    case preview
    case commit
}

/// A bounded declarative Mesh edit request. Mesh bytes are never carried here.
public struct AgentMeshEditRequest: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let expectedGeneration: DocumentGeneration
    public let handle: ProjectMeshSourceHandle
    public let plan: MeshEditPlan
    public let mode: AgentMeshEditMode
    public let name: String

    public init(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration,
        handle: ProjectMeshSourceHandle,
        plan: MeshEditPlan,
        mode: AgentMeshEditMode,
        name: String = "mesh.edit"
    ) {
        self.sessionID = sessionID
        self.expectedGeneration = expectedGeneration
        self.handle = handle
        self.plan = plan
        self.mode = mode
        self.name = name
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Mesh edit names must not be empty."
            )
        }
    }
}

/// Identity-only CAD Make Editable request. The runtime binds it to one full view.
public struct AgentMakeEditableRequest: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let expectedGeneration: DocumentGeneration
    public let sceneNodeID: SceneNodeID
    public let authoredMeshSourceID: GeometrySourceID
    public let authoredMeshRepresentationID: GeometryRepresentationID
    public let switchesPresentationSelection: Bool
    public let name: String

    public init(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration,
        sceneNodeID: SceneNodeID,
        authoredMeshSourceID: GeometrySourceID,
        authoredMeshRepresentationID: GeometryRepresentationID,
        switchesPresentationSelection: Bool = true,
        name: String = "cad.make-editable"
    ) {
        self.sessionID = sessionID
        self.expectedGeneration = expectedGeneration
        self.sceneNodeID = sceneNodeID
        self.authoredMeshSourceID = authoredMeshSourceID
        self.authoredMeshRepresentationID = authoredMeshRepresentationID
        self.switchesPresentationSelection = switchesPresentationSelection
        self.name = name
    }

    public func validate() throws {
        do {
            try authoredMeshSourceID.validate()
            try authoredMeshRepresentationID.validate()
        } catch let error as EditorError {
            throw error
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable names must not be empty."
            )
        }
    }
}

private extension ProjectMeshReadLimits {
    func validateForAgentRequest() throws {
        let values = [
            (maxSources, ProjectMeshReadLimits.hard.maxSources, "maxSources"),
            (maxPageRecords, ProjectMeshReadLimits.hard.maxPageRecords, "maxPageRecords"),
            (maxNeighborhoodDepth, ProjectMeshReadLimits.hard.maxNeighborhoodDepth, "maxNeighborhoodDepth"),
            (maxScannedRecords, ProjectMeshReadLimits.hard.maxScannedRecords, "maxScannedRecords"),
            (maxOutputRecords, ProjectMeshReadLimits.hard.maxOutputRecords, "maxOutputRecords"),
            (maxReferenceUnits, ProjectMeshReadLimits.hard.maxReferenceUnits, "maxReferenceUnits"),
        ]
        guard values.allSatisfy({ $0.0 > 0 }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent Mesh read limits must be positive."
            )
        }
        guard values.allSatisfy({ $0.0 <= $0.1 }) else {
            let exceeded = values.first(where: { $0.0 > $0.1 })?.2 ?? "value"
            throw EditorError(
                code: .commandInvalid,
                message: "Agent Mesh read limit \(exceeded) exceeds the hard ceiling."
            )
        }
    }
}
