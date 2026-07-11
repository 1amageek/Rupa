import SwiftCAD

public struct ValidatedDesignDocument: Sendable {
    public let document: DesignDocument
    public let validatedCADDocument: ValidatedCADDocument

    public init(
        _ document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        try document.modelingSettings.validate()
        let validatedCADDocument = try ValidatedCADDocument(
            document.cadDocument,
            tolerance: document.modelingSettings.tolerance
        )
        try document.productMetadata.validate(
            against: document.cadDocument,
            objectRegistry: objectRegistry
        )
        self.document = document
        self.validatedCADDocument = validatedCADDocument
    }

    package init(
        document: DesignDocument,
        validatedCADDocument: ValidatedCADDocument
    ) {
        self.document = document
        self.validatedCADDocument = validatedCADDocument
    }
}
