public struct GeometrySourceCommandApplication: Sendable {
    public let document: DesignDocument
    public let result: GeometrySourceCommandResult

    public init(
        document: DesignDocument,
        result: GeometrySourceCommandResult
    ) {
        self.document = document
        self.result = result
    }
}
