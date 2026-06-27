import RupaViewportScene
struct ViewportProfileEdgeFilletMapping: Equatable, Sendable {
    static func radius(
        for edge: ViewportBodyEdge,
        xDelta: Double,
        zDelta: Double
    ) -> Double? {
        ViewportProfileEdgeChamferMapping.distance(
            for: edge,
            xDelta: xDelta,
            zDelta: zDelta
        )
    }
}
