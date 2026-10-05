import SwiftCAD

/// Existing legacy drawing entry policy: cancellation and no new private ceiling.
struct DrawingLegacyPlacementAdmission: RationalAlgebraAdmitting {
    mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0 else { throw EditorError(code: .commandInvalid, message: "Original drawing depth is negative.") }
        try Task.checkCancellation()
    }
    mutating func consumeExactWork(_ count: Int) throws {
        guard count >= 0 else { throw EditorError(code: .commandInvalid, message: "Original drawing work count is negative.") }
        try Task.checkCancellation()
    }
    mutating func retainExactStorage(_ count: Int) throws {
        guard count >= 0 else { throw EditorError(code: .commandInvalid, message: "Original drawing storage count is negative.") }
        try Task.checkCancellation()
    }
}
