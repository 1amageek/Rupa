import ArgumentParser
import Foundation
import RupaCore

enum CLISelectionDimensionReferenceParser {
    static func dimensionID(_ value: String, valueName: String) throws -> SelectionDimensionID {
        guard let uuid = UUID(uuidString: value) else {
            throw ValidationError("\(valueName) must be a UUID.")
        }
        return SelectionDimensionID(uuid)
    }
}
