import Foundation
import SwiftCAD
import RupaCoreTypes

public struct DesignDocument: Identifiable, Sendable {
    public var cadDocument: CADDocument
    public var displayUnit: LengthDisplayUnit
    public var ruler: RulerConfiguration
    public var productMetadata: ProductMetadata

    public var id: DocumentID {
        cadDocument.id
    }

    public init(
        cadDocument: CADDocument,
        displayUnit: LengthDisplayUnit,
        ruler: RulerConfiguration,
        productMetadata: ProductMetadata = .empty()
    ) {
        self.cadDocument = cadDocument
        self.displayUnit = displayUnit
        self.ruler = ruler
        self.productMetadata = productMetadata
    }

    public static func empty(named name: String = "Untitled") -> DesignDocument {
        let unit: LengthDisplayUnit = .millimeter
        return DesignDocument(
            cadDocument: CADDocument(
                units: .meters,
                metadata: DocumentMetadata(name: name)
            ),
            displayUnit: unit,
            ruler: .standard(for: unit),
            productMetadata: .empty()
        )
    }

    public func validate(objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        try cadDocument.validate()
        try ruler.validate()
        guard ruler.displayUnit == displayUnit else {
            throw DocumentValidationError.invalidProductMetadata(
                "Document ruler display unit must match the document display unit."
            )
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }
}
