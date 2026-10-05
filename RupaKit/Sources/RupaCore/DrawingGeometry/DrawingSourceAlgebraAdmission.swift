import SwiftCAD

/// Exact source preparation composed with the caller's existing live drawing owner.
struct DrawingSourceAlgebraAdmission: RationalAlgebraAdmitting {
    let work: @Sendable (Int) throws -> Void
    let storage: @Sendable (Int) throws -> Void
    let maximumAlgebraicDepth: Int

    init(usage: DrawingExchangeUsage) {
        work = usage.preparationWorkCallback
        storage = usage.preparationStorageCallback
        maximumAlgebraicDepth = usage.maximumAlgebraicDepth
    }
    mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0, depth <= maximumAlgebraicDepth else {
            throw EditorError(code: .evaluationFailed, message: "Original drawing algebra depth is exhausted.")
        }
        try work(1)
    }
    mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
    mutating func consumeExactWork(_ count: Int) throws {
        guard count >= 0 else { throw EditorError(code: .commandInvalid, message: "Original drawing work is negative.") }
        try work(count)
    }
    mutating func retainExactStorage(_ words: Int) throws {
        let bytes = words.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard words >= 0, !bytes.overflow else {
            throw EditorError(code: .evaluationFailed, message: "Original drawing storage overflows bytes.")
        }
        try storage(bytes.partialValue)
    }
}
