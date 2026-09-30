/// A Geometry source command's staged document and result.
public struct GeometrySourceCommandApplication: Sendable {
    /// The staged document, validated once by the applier; the input's own validation when the
    /// command changed nothing.
    public let validatedDocument: ValidatedDesignDocument
    public let result: GeometrySourceCommandResult

    public init(
        validatedDocument: ValidatedDesignDocument,
        result: GeometrySourceCommandResult
    ) {
        self.validatedDocument = validatedDocument
        self.result = result
    }

    public var document: DesignDocument {
        validatedDocument.document
    }
}
