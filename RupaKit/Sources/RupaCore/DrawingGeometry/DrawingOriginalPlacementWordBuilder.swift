import SwiftCAD

/// Extracts the original source factors; no derived matrix is an input authority.
struct DrawingOriginalPlacementWordBuilder {
    func word<B: RationalAlgebraAdmitting>(from occurrence: SceneNodeHierarchy.Occurrence,
        usage: inout B) throws -> OriginalAffineOperationWord {
        try word(factors: occurrence.originalTransformFactors, usage: &usage)
    }

    func word<B: RationalAlgebraAdmitting>(factors originals: [Transform3D],
        usage: inout B) throws -> OriginalAffineOperationWord {
        guard !originals.isEmpty else {
            throw EditorError(code: .referenceUnresolved, message: "Drawing occurrence has no retained original placement factors.")
        }
        let count = originals.count
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<OriginalAffineOperation>.stride)
        let rounded = bytes.partialValue.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
        guard !bytes.overflow, !rounded.overflow else {
            throw EditorError(code: .commandInvalid, message: "Original drawing placement word storage overflowed.")
        }
        try usage.retainExactStorage(rounded.partialValue / MemoryLayout<UInt32>.stride)
        var factors: [OriginalAffineOperation] = []; factors.reserveCapacity(count)
        for raw in originals {
            try usage.consumeExactWork(1)
            try raw.validateAffinePlacement()
            let m = raw.matrix.values
            factors.append(.forward(try AffineTransform3D(
                basisX: Vector3D(x: m[0], y: m[4], z: m[8]),
                basisY: Vector3D(x: m[1], y: m[5], z: m[9]),
                basisZ: Vector3D(x: m[2], y: m[6], z: m[10]),
                translation: Vector3D(x: m[3], y: m[7], z: m[11]))))
        }
        return try OriginalAffineOperationWord(factors: factors, usage: &usage)
    }
}
