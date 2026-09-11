/// What one rectangle query resolved about the candidates it examined:
/// `confirmed` selects, and `unconfirmed` is neither selected nor proven
/// absent.
///
/// `RupaRendering/DESIGN.md` owns the rule, the reason a point oracle cannot
/// collapse the two lists into one, and what each consumer may read.
///
/// No production path reaches this type. The region visibility raster answers
/// the selection rectangle from what the mounted frame draws at every device
/// pixel of it, so no candidate is left neither selected nor proven absent and
/// the production rectangle rules return plain arrays. What is left reachable
/// is the two sampling resolvers, which are deprecated with it, and their own
/// tests. RK-4.3.5.6 removes all of them once the region path's replacement
/// evidence passes on the mounted path.
@available(
    *, deprecated,
    message: "The region visibility raster leaves no unconfirmed candidate. Removed with the two sampling resolvers in RK-4.3.5.6."
)
struct ViewportRectangleResolution<Element> {
    /// The candidates a native query confirmed inside the rectangle, in the
    /// order the answering plan holds them.
    let confirmed: [Element]

    /// The candidates whose coverage reached the sampling grid and which no
    /// sample confirmed, in that same order and disjoint from `confirmed`.
    let unconfirmed: [Element]

    init(confirmed: [Element], unconfirmed: [Element]) {
        self.confirmed = confirmed
        self.unconfirmed = unconfirmed
    }
}

@available(
    *, deprecated,
    message: "The region visibility raster leaves no unconfirmed candidate. Removed with the two sampling resolvers in RK-4.3.5.6."
)
extension ViewportRectangleResolution: Sendable where Element: Sendable {}
