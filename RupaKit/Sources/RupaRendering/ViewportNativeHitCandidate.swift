/// A ranked candidate answered from the mounted native frame.
///
/// Both native hit resolvers produce these and the viewport compares them
/// against each other, so the vocabulary belongs to neither resolver. The rank
/// a family carries is a property of the family — of what the scene draws and
/// what a scope asks for — and not of the resolver that happened to answer for
/// it.
///
/// `rank` keeps the scope order the viewport asks for: a vertex wins over an
/// edge, an edge over a face, and a face over the occurrence carrying it, so a
/// pointer that named a sub-shape never resolves to its whole occurrence.
/// `metric` orders candidates of the same rank: projected point distance for a
/// vertex or edge, and the camera depth of the drawn surface for a face. The
/// caller compares candidates from different bodies through this order, so the
/// nearest projected sub-shape wins across the scene instead of the first body
/// that happens to answer. Only the one body the native frame draws at the
/// pointer is given a surface hit, so at most one face candidate exists per
/// query and the face metric never has to order two bodies against each other.
///
/// A sketch region is the one other family at face rank, and it carries a
/// projected distance where a CAD face carries a depth. The two are never
/// ordered against each other: the `region` scope admits no face, and the
/// `all` scope does not generate a region candidate yet. Giving both families
/// one metric belongs to the seam that makes `all` generate every family.
///
/// An occurrence carries a metric of zero. It is admitted at the pointer's own
/// pixel and has no distance to the pointer to be ordered by, and one query
/// never produces two of them, because one pixel draws one occurrence.
///
/// A candidate carries the order and nothing else. The identity of what was
/// hit stays with the resolver that owns the family, because the families do
/// not share one identity type: a CAD sub-shape is a prepared
/// `SelectionComponent` and a surface handle display is a `SelectionReference`.
/// Each resolver therefore returns the `ViewportHit` it formed alongside the
/// candidate that orders it, and no new family widens this type.
struct ViewportNativeHitCandidate {
    enum Rank: Int {
        case vertex
        case edge
        case face
        case object
    }

    let rank: Rank
    let metric: Double

    func precedes(_ other: ViewportNativeHitCandidate) -> Bool {
        rank == other.rank ? metric < other.metric : rank.rawValue < other.rank.rawValue
    }
}
