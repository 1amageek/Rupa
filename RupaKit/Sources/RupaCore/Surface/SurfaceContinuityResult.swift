import RupaCoreTypes
public struct SurfaceContinuityResult: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var bSplineFaceCount: Int
        public var sharedEdgeCount: Int
        public var g0AdjacencyCount: Int
        public var g1AdjacencyCount: Int
        public var g2AdjacencyCount: Int
        public var unresolvedG2AdjacencyCount: Int

        public init(
            bSplineFaceCount: Int = 0,
            sharedEdgeCount: Int = 0,
            g0AdjacencyCount: Int = 0,
            g1AdjacencyCount: Int = 0,
            g2AdjacencyCount: Int = 0,
            unresolvedG2AdjacencyCount: Int = 0
        ) {
            self.bSplineFaceCount = bSplineFaceCount
            self.sharedEdgeCount = sharedEdgeCount
            self.g0AdjacencyCount = g0AdjacencyCount
            self.g1AdjacencyCount = g1AdjacencyCount
            self.g2AdjacencyCount = g2AdjacencyCount
            self.unresolvedG2AdjacencyCount = unresolvedG2AdjacencyCount
        }
    }

    public enum ContinuityLevel: String, Codable, Equatable, Sendable {
        case disconnected
        case g0
        case g1
        case g2
    }

    public struct Adjacency: Codable, Equatable, Sendable {
        public var edgeID: String
        public var edgePersistentNames: [String]
        public var firstFaceID: String
        public var secondFaceID: String
        public var firstFacePersistentName: String?
        public var secondFacePersistentName: String?
        public var continuity: ContinuityLevel
        public var positionGap: Double
        public var normalAngle: Double?
        public var curvatureGap: Double?
        public var requiresCurvatureContinuitySolve: Bool

        public init(
            edgeID: String,
            edgePersistentNames: [String] = [],
            firstFaceID: String,
            secondFaceID: String,
            firstFacePersistentName: String? = nil,
            secondFacePersistentName: String? = nil,
            continuity: ContinuityLevel,
            positionGap: Double,
            normalAngle: Double? = nil,
            curvatureGap: Double? = nil,
            requiresCurvatureContinuitySolve: Bool
        ) {
            self.edgeID = edgeID
            self.edgePersistentNames = edgePersistentNames
            self.firstFaceID = firstFaceID
            self.secondFaceID = secondFaceID
            self.firstFacePersistentName = firstFacePersistentName
            self.secondFacePersistentName = secondFacePersistentName
            self.continuity = continuity
            self.positionGap = positionGap
            self.normalAngle = normalAngle
            self.curvatureGap = curvatureGap
            self.requiresCurvatureContinuitySolve = requiresCurvatureContinuitySolve
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var counts: Counts
    public var adjacencies: [Adjacency]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        adjacencies: [Adjacency] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.counts = counts
        self.adjacencies = adjacencies
        self.diagnostics = diagnostics
    }
}
