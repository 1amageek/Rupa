import RupaCore

/// A dialog's Analysis value drawn beside what it measures (Square's side checks): `text` at
/// `anchor`, coloured by its verdict.
public struct ViewportAnalysisLabel: Equatable, Hashable, Sendable {
    /// How the value stands against the check: within its limit, not asked for (the side's own
    /// continuity is below the check, so nothing holds it), or beyond its limit.
    public enum Verdict: Equatable, Hashable, Sendable {
        case within
        case unconstrained
        case beyond
    }

    public let anchor: Point3D
    public let text: String
    public let verdict: Verdict

    public init(anchor: Point3D, text: String, verdict: Verdict) {
        self.anchor = anchor
        self.text = text
        self.verdict = verdict
    }
}
