public struct SurfaceFrameQuery: Codable, Equatable, Sendable {
    public var faceID: String?
    public var facePersistentName: String?
    public var u: Double
    public var v: Double

    public init(
        faceID: String? = nil,
        facePersistentName: String? = nil,
        u: Double,
        v: Double
    ) {
        self.faceID = faceID
        self.facePersistentName = facePersistentName
        self.u = u
        self.v = v
    }
}
