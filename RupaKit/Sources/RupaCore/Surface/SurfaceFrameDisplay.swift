public struct SurfaceFrameDisplay: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable {
        case visible
        case hidden
    }

    public var id: SurfaceFrameDisplayID
    public var query: SurfaceFrameQuery
    public var mode: Mode

    public var isVisible: Bool {
        mode == .visible
    }

    public init(
        id: SurfaceFrameDisplayID,
        query: SurfaceFrameQuery,
        mode: Mode
    ) {
        self.id = id
        self.query = query
        self.mode = mode
    }

    public init(
        query: SurfaceFrameQuery,
        isVisible: Bool
    ) throws {
        self.init(
            id: try SurfaceFrameDisplayID(query: query),
            query: query,
            mode: isVisible ? .visible : .hidden
        )
    }

    public func validate() throws {
        let expectedID = try SurfaceFrameDisplayID(query: query)
        guard id == expectedID else {
            throw DocumentValidationError.invalidProductMetadata(
                "Surface frame display IDs must match their query targets."
            )
        }
    }
}
