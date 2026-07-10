public struct MeshSnapshot: Equatable, Sendable {
    public var bodyCount: Int
    public var vertexCount: Int
    public var normalCount: Int
    public var triangleCount: Int
    public var indexedElementCount: Int
    public var bounds: MeasurementResult.Bounds?
    public var bodies: [MeshSummaryResult.Body]

    public init(
        bodyCount: Int = 0,
        vertexCount: Int = 0,
        normalCount: Int = 0,
        triangleCount: Int = 0,
        indexedElementCount: Int = 0,
        bounds: MeasurementResult.Bounds? = nil,
        bodies: [MeshSummaryResult.Body] = []
    ) {
        self.bodyCount = bodyCount
        self.vertexCount = vertexCount
        self.normalCount = normalCount
        self.triangleCount = triangleCount
        self.indexedElementCount = indexedElementCount
        self.bounds = bounds
        self.bodies = bodies
    }
}
