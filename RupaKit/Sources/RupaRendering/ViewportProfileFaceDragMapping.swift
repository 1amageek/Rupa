struct ViewportProfileFaceDragMapping: Equatable, Sendable {
    static func supports(_ face: ViewportBodyFace) -> Bool {
        distance(for: face, xDelta: 1.0, yDelta: 1.0, zDelta: 1.0) != nil
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
