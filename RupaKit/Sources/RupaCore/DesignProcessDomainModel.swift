public struct DesignProcessDomainModel: Codable, Equatable, Sendable {
    public var sourceEntities: [String]
    public var targetEntities: [String]
    public var generatedTopology: [String]
    public var units: String
    public var tolerances: [String]
    public var ownershipBoundaries: [String]

    public init(
        sourceEntities: [String] = [],
        targetEntities: [String] = [],
        generatedTopology: [String] = [],
        units: String = "",
        tolerances: [String] = [],
        ownershipBoundaries: [String] = []
    ) {
        self.sourceEntities = sourceEntities
        self.targetEntities = targetEntities
        self.generatedTopology = generatedTopology
        self.units = units
        self.tolerances = tolerances
        self.ownershipBoundaries = ownershipBoundaries
    }
}
