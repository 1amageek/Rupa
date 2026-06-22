struct ViewportProfileEdgeChamferMapping: Equatable, Sendable {
    static func distance(
        for edge: ViewportBodyEdge,
        xDelta: Double,
        zDelta: Double
    ) -> Double? {
        let inwardX: Double
        let inwardZ: Double
        switch edge {
        case .leftBottom:
            inwardX = xDelta
            inwardZ = zDelta
        case .rightBottom:
            inwardX = -xDelta
            inwardZ = zDelta
        case .rightTop:
            inwardX = -xDelta
            inwardZ = -zDelta
        case .leftTop:
            inwardX = xDelta
            inwardZ = -zDelta
        }

        guard inwardX > 0.0 || inwardZ > 0.0 else {
            return nil
        }
        let distance = (inwardX + inwardZ) / 2.0
        guard distance > 0.0 else {
            return nil
        }
        return distance
    }
}
