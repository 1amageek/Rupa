import RupaViewportScene
struct ViewportProfileFaceDragMapping: Equatable, Sendable {
    static func supports(_ face: ViewportBodyFace) -> Bool {
        distance(for: face, xDelta: 1.0, yDelta: 1.0, zDelta: 1.0) != nil
    }

    /// The one model axis a face's distance is read from.
    ///
    /// `distance` uses exactly one of the three deltas per face, so a caller
    /// measures that axis and leaves the other two at zero rather than asking
    /// the frame for three answers and refusing unless all three resolve. Every
    /// axis-front camera has one axis that projects to a point, and requiring
    /// all three made a face solvable along its own axis unsolvable whenever a
    /// different axis was the degenerate one.
    static func axis(for face: ViewportBodyFace) -> ViewportCoordinateAxis {
        switch face {
        case .front, .back:
            return .y
        case .right, .side, .left:
            return .x
        case .top, .bottom:
            return .z
        }
    }

    static func distance(
        for face: ViewportBodyFace,
        xDelta: Double,
        yDelta: Double,
        zDelta: Double
    ) -> Double? {
        switch face {
        case .front:
            return -yDelta
        case .back:
            return yDelta
        case .right, .side:
            return xDelta
        case .left:
            return -xDelta
        case .top:
            return zDelta
        case .bottom:
            return -zDelta
        }
    }
}
