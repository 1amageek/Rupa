import Foundation
import SwiftCAD

struct GeneratedTopologyPersistentNameParser: Sendable {
    func parse(_ value: String, operationName: String) throws -> PersistentName {
        let components = try value
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { try parseComponent(String($0), operationName: operationName) }
        let name = PersistentName(components: components)
        try name.validate()
        return name
    }

    private func parseComponent(_ value: String, operationName: String) throws -> NameComponent {
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw invalidName(operationName: operationName)
        }
        let kind = String(parts[0])
        let payload = String(parts[1])
        switch kind {
        case "feature":
            guard let uuid = UUID(uuidString: payload) else {
                throw invalidName(operationName: operationName)
            }
            return .feature(FeatureID(uuid))
        case "generated":
            guard !payload.isEmpty else {
                throw invalidName(operationName: operationName)
            }
            return .generated(payload)
        case "subshape":
            guard !payload.isEmpty else {
                throw invalidName(operationName: operationName)
            }
            return .subshape(payload)
        case "index":
            guard let index = Int(payload), index >= 0 else {
                throw invalidName(operationName: operationName)
            }
            return .index(index)
        default:
            throw invalidName(operationName: operationName)
        }
    }

    private func invalidName(operationName: String) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "\(operationName) requires a valid generated topology persistent name."
        )
    }
}
