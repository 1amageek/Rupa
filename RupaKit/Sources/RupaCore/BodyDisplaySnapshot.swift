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
        public var positions: [Point3D]
        public var indices: [UInt32]

        public init(positions: [Point3D], indices: [UInt32]) {
            self.positions = positions
            self.indices = indices
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
    public var bounds: Bounds
    public var mesh: Mesh
    public var topology: Topology

    public init(
        featureID: FeatureID,
        bounds: Bounds,
        mesh: Mesh,
        topology: Topology
    ) {
        self.featureID = featureID
        self.bounds = bounds
        self.mesh = mesh
        self.topology = topology
    }
}
