/// What one rectangle query resolved about the candidates it examined:
/// `confirmed` selects, and `unconfirmed` is neither selected nor proven
/// absent.
///
/// `RupaRendering/DESIGN.md` owns the rule, the reason a point oracle cannot
/// collapse the two lists into one, and what each consumer may read.
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

extension ViewportRectangleResolution: Sendable where Element: Sendable {}
