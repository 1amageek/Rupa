import SwiftCAD

struct StableTopologyReferenceParser: Sendable {
    func parse(
        _ componentID: SelectionComponentID,
        operationName: String
    ) throws -> StableSubshapeReference {
        try componentID.stableTopologyReference(operationName: operationName)
    }
}
