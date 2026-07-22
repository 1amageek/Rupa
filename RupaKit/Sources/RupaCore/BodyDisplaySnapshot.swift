public struct BodyDisplaySnapshot: Codable, Equatable, Sendable {
    public struct Bounds: Codable, Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var minZ: Double
        public var maxX: Double
        public var maxY: Double
        public var maxZ: Double

        public init(
            minX: Double,
            minY: Double,
            minZ: Double,
            maxX: Double,
            maxY: Double,
            maxZ: Double
        ) {
            self.minX = minX
            self.minY = minY
            self.minZ = minZ
            self.maxX = maxX
            self.maxY = maxY
            self.maxZ = maxZ
        }
    }

    public struct Mesh: Codable, Equatable, Sendable {
        public struct StorageIdentity: Hashable, Sendable {
            fileprivate let value: ObjectIdentifier
        }

        private final class Storage: Sendable {
            let positions: [Point3D]
            let indices: [UInt32]

            init(positions: [Point3D], indices: [UInt32]) {
                self.positions = positions
                self.indices = indices
            }
        }

        private enum CodingKeys: String, CodingKey {
            case positions
            case indices
        }

        private let storage: Storage

        public var positions: [Point3D] {
            storage.positions
        }

        public var indices: [UInt32] {
            storage.indices
        }

        public var storageIdentity: StorageIdentity {
            StorageIdentity(value: ObjectIdentifier(storage))
        }

        public init(positions: [Point3D], indices: [UInt32]) {
            self.storage = Storage(positions: positions, indices: indices)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                positions: try container.decode([Point3D].self, forKey: .positions),
                indices: try container.decode([UInt32].self, forKey: .indices)
            )
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(storage.positions, forKey: .positions)
            try container.encode(storage.indices, forKey: .indices)
        }

        public static func == (lhs: Mesh, rhs: Mesh) -> Bool {
            if lhs.sharesStorage(with: rhs) {
                return true
            }
            return lhs.positions == rhs.positions && lhs.indices == rhs.indices
        }

        public func sharesStorage(with other: Mesh) -> Bool {
            storage === other.storage
        }
    }

    public struct Topology: Codable, Equatable, Sendable {
        public struct Face: Codable, Equatable, Sendable {
            public var componentID: SelectionComponentID
            public var points: [Point3D]

            public init(componentID: SelectionComponentID, points: [Point3D]) {
                self.componentID = componentID
                self.points = points
            }
        }

        public struct Edge: Codable, Equatable, Sendable {
            public var componentID: SelectionComponentID
            public var start: Point3D
            public var end: Point3D

            public init(componentID: SelectionComponentID, start: Point3D, end: Point3D) {
                self.componentID = componentID
                self.start = start
                self.end = end
            }
        }

        public struct Vertex: Codable, Equatable, Sendable {
            public var componentID: SelectionComponentID
            public var point: Point3D

            public init(componentID: SelectionComponentID, point: Point3D) {
                self.componentID = componentID
                self.point = point
            }
        }

        public var faces: [Face]
        public var edges: [Edge]
        public var vertices: [Vertex]

        public init(
            faces: [Face] = [],
            edges: [Edge] = [],
            vertices: [Vertex] = []
        ) {
            self.faces = faces
            self.edges = edges
            self.vertices = vertices
        }
    }

    public var featureID: FeatureID
    public var bodyID: String?
    public var stableReference: StableSubshapeReference?
    public var bounds: Bounds
    public var mesh: Mesh
    public var topology: Topology

    public init(
        featureID: FeatureID,
        bodyID: String? = nil,
        stableReference: StableSubshapeReference? = nil,
        bounds: Bounds,
        mesh: Mesh,
        topology: Topology
    ) {
        self.featureID = featureID
        self.bodyID = bodyID
        self.stableReference = stableReference
        self.bounds = bounds
        self.mesh = mesh
        self.topology = topology
    }
}
