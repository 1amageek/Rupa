import ArgumentParser
import Foundation
import RupaCore

enum CLIFeatureReferenceParser {
    static func featureID(_ value: String, valueName: String) throws -> FeatureID {
        guard let uuid = UUID(uuidString: value) else {
            throw ValidationError("\(valueName) must be a UUID.")
        }
        return FeatureID(uuid)
    }
}
