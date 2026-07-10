import SwiftCAD

public enum ValidationRegionTarget: Codable, Equatable, Sendable {
    case body(BodyID)
    case bodyPair(first: BodyID, second: BodyID)
    case generatedTopology(bodyID: BodyID?, persistentNames: [String])
    case meshTriangles(artifact: MeshArtifactReference, selections: [ValidationMeshTriangleSelection])
    case semanticEntities(extensionID: SemanticExtensionID, entityIDs: [SemanticEntityID])
    case sampledArtifact(artifact: MaterializedArtifactReference, ranges: [ValidationElementRange])
    case drawingItems(artifact: MaterializedArtifactReference, itemIDs: [String])
}
