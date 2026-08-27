import RupaCoreTypes
import RupaGeometry

public struct ProjectMeshVertexRecord: Codable, Equatable, Sendable {
    public let id: MeshVertexID
    public let position: GeometryPoint3D

    public init(id: MeshVertexID, position: GeometryPoint3D) {
        self.id = id
        self.position = position
    }
}

public struct ProjectMeshEdgeRecord: Codable, Equatable, Sendable {
    public let id: MeshEdgeID
    public let endpoints: MeshEdgeEndpoints

    public init(id: MeshEdgeID, endpoints: MeshEdgeEndpoints) {
        self.id = id
        self.endpoints = endpoints
    }
}

public struct ProjectMeshFaceRecord: Codable, Equatable, Sendable {
    public let id: MeshFaceID
    public let cornerIDs: [MeshCornerID]

    public init(id: MeshFaceID, cornerIDs: [MeshCornerID]) {
        self.id = id
        self.cornerIDs = cornerIDs
    }
}

public struct ProjectMeshCornerRecord: Codable, Equatable, Sendable {
    public let id: MeshCornerID
    public let faceID: MeshFaceID
    public let vertexID: MeshVertexID
    public let edgeID: MeshEdgeID
    public let previousID: MeshCornerID
    public let nextID: MeshCornerID

    public init(
        id: MeshCornerID,
        faceID: MeshFaceID,
        vertexID: MeshVertexID,
        edgeID: MeshEdgeID,
        previousID: MeshCornerID,
        nextID: MeshCornerID
    ) {
        self.id = id
        self.faceID = faceID
        self.vertexID = vertexID
        self.edgeID = edgeID
        self.previousID = previousID
        self.nextID = nextID
    }
}

public enum ProjectMeshElementRecord: Codable, Equatable, Sendable {
    case vertex(ProjectMeshVertexRecord)
    case edge(ProjectMeshEdgeRecord)
    case face(ProjectMeshFaceRecord)
    case corner(ProjectMeshCornerRecord)

    public var reference: ProjectMeshElementReference {
        switch self {
        case .vertex(let record):
            .vertex(record.id)
        case .edge(let record):
            .edge(record.id)
        case .face(let record):
            .face(record.id)
        case .corner(let record):
            .corner(record.id)
        }
    }

    public var domain: ProjectMeshElementDomain {
        reference.domain
    }
}
