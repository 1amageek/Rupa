import Foundation
import SwiftCAD

public struct DesignDocument: Identifiable, Sendable {
    public var cadDocument: CADDocument
    public var modelingSettings: DocumentModelingSettings
    public var productMetadata: ProductMetadata

    public var id: DocumentID {
        cadDocument.id
    }

    public init(
        cadDocument: CADDocument,
        modelingSettings: DocumentModelingSettings = .standard,
        productMetadata: ProductMetadata = .empty()
    ) {
        self.cadDocument = cadDocument
        self.modelingSettings = modelingSettings
        self.productMetadata = productMetadata
    }

    public static func empty(named name: String = "Untitled") -> DesignDocument {
        return DesignDocument(
            cadDocument: CADDocument(
                units: .meters,
                metadata: DocumentMetadata(name: name)
            ),
            modelingSettings: .standard,
            productMetadata: .empty()
        )
    }

    @discardableResult
    public func validate(
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ValidatedDesignDocument {
        try ValidatedDesignDocument(self, objectRegistry: objectRegistry)
    }
}
