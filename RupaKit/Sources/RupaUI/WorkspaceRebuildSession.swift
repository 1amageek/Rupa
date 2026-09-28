import RupaCore

/// Rebuild Curve's dialog while it runs, on the splines selected when it started: its Method and
/// that method's values; OK, Return or right-click rebuilds every curve as one step and Escape
/// ends it without a change.
struct WorkspaceRebuildSession: Equatable {
    enum Method: String, CaseIterable, Equatable {
        case refit
        case points
        case explicitControl

        var title: String {
            switch self {
            case .refit: "Refit"
            case .points: "Points"
            case .explicitControl: "Explicit Control"
            }
        }
    }

    let targets: [SelectionTarget]
    var method: Method
    /// Points: the number of control points, any count a cubic takes.
    var pointCount: Int
    /// Refit: the distance the rebuilt curve may stray, in meters.
    var toleranceMeters: Double
    /// Refit: corners are kept.
    var keepsCorners: Bool
    /// Explicit Control: degree, spans and the weight between a loose curve (0) and the original
    /// shape (1).
    var degree: Int
    var spanCount: Int
    var weight: Double

    static let pointCountRange = 4...512

    /// The dialog for the selected curves, or nil when none is selected.
    init?(
        selectedCurves: [SelectionTarget],
        method: Method,
        pointCount: Int,
        toleranceMeters: Double,
        keepsCorners: Bool,
        degree: Int,
        spanCount: Int,
        weight: Double
    ) {
        guard !selectedCurves.isEmpty else { return nil }
        targets = selectedCurves
        self.method = method
        self.pointCount = pointCount
        self.toleranceMeters = toleranceMeters
        self.keepsCorners = keepsCorners
        self.degree = degree
        self.spanCount = spanCount
        self.weight = weight
    }

    /// The rebuild the dialog asks for, as Core takes it.
    var options: CurveRebuildOptions {
        switch method {
        case .points:
            .points(controlPointCount: pointCount)
        case .refit:
            .refit(tolerance: .length(toleranceMeters, .meter), keepsCorners: keepsCorners)
        case .explicitControl:
            .explicitControl(degree: degree, spanCount: spanCount, weight: min(max(weight, 0), 1))
        }
    }
}
