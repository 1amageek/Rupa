import RupaCoreTypes
import RupaGeometry

/// One occurrence of a render plan, exposed so a consumer can project each
/// retained world position once and then index it per triangle.
///
/// `forEachTriangle` materializes three world positions per triangle, which
/// costs a draw pass one projection per triangle corner. This view exposes the
/// same geometry in its retained shape — a position buffer plus checked
/// indices — so a draw pass projects `positionCount` points instead of
/// `3 * triangleCount`, and resolves interaction state once per occurrence
/// instead of once per triangle.
///
/// The buffers are the plan's own storage. Reading them copies nothing.
public struct MeshSourcePresentationOccurrenceView: Sendable {
    public let occurrenceID: SceneOccurrenceID

    /// World positions, one per source vertex, in the plan's retained order.
    public let positions: [GeometryPoint3D]

    private let occurrence: MeshSourcePresentationRenderPlan.Occurrence

    init(occurrence: MeshSourcePresentationRenderPlan.Occurrence) {
        self.occurrenceID = occurrence.occurrenceID
        self.positions = occurrence.positions
        self.occurrence = occurrence
    }

    public var triangleCount: Int {
        occurrence.triangleCount
    }

    /// The three `positions` offsets of one triangle. Construction validated
    /// every index against the position count, so the result is always in
    /// range.
    public func positionIndices(at index: Int) -> (first: Int, second: Int, third: Int) {
        let base = index * 3
        return (
            Int(occurrence.vertexIndices[base]),
            Int(occurrence.vertexIndices[base + 1]),
            Int(occurrence.vertexIndices[base + 2])
        )
    }

    /// The full triangle, including picking provenance. A consumer that only
    /// draws should index `positions` instead, because materializing a triangle
    /// copies its three positions.
    public func triangle(at index: Int) -> MeshSourcePresentationTriangle {
        occurrence.triangle(at: index)
    }
}
