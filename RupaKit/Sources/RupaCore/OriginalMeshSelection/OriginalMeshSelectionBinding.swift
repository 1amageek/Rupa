import SwiftCAD

public final class OriginalMeshSelectionBinding: Equatable, Sendable {
    public let bodyID: BodyID
    private let snapshot: EvaluatedMeshSelectionSnapshot
    private let evaluated: EvaluatedDocument

    public init(bodyID: BodyID, evaluated: EvaluatedDocument) throws {
        self.bodyID = bodyID
        self.snapshot = try EvaluatedMeshSelectionSnapshot(bodyID: bodyID, evaluated: evaluated)
        self.evaluated = evaluated
    }

    public func validateCurrentEvaluation(_ current: EvaluatedDocument) throws {
        try snapshot.validateCurrent(current)
    }

    public func componentID(forTriangle triangle: Int) throws -> SelectionComponentID {
        .generatedTopology(try snapshot.subshapeID(forTriangle: triangle, in: evaluated))
    }

    public static func == (lhs: OriginalMeshSelectionBinding, rhs: OriginalMeshSelectionBinding) -> Bool {
        lhs === rhs || (lhs.bodyID == rhs.bodyID
            && lhs.evaluated.document == rhs.evaluated.document
            && lhs.evaluated.brep == rhs.evaluated.brep
            && lhs.evaluated.configuration == rhs.evaluated.configuration
            && lhs.evaluated.meshes[lhs.bodyID] == rhs.evaluated.meshes[rhs.bodyID]
            && lhs.evaluated.subshapes.entries == rhs.evaluated.subshapes.entries)
    }
}
