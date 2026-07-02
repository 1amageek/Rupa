import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func setDisplayUnit(_ unit: LengthDisplayUnit) {
        displayUnit = unit
        ruler = ruler.replacingDisplayUnit(unit)
    }

    public mutating func setRulerConfiguration(_ configuration: RulerConfiguration) throws {
        try configuration.validate()
        displayUnit = configuration.displayUnit
        ruler = configuration
    }

    public mutating func setViewportGridSettings(_ settings: ViewportGridSettings) {
        productMetadata.viewportGridSettings = settings
    }

    public mutating func rename(_ name: String, updatedAt: Date = Date()) {
        cadDocument.metadata.name = name
        cadDocument.metadata.updatedAt = updatedAt
    }
}
