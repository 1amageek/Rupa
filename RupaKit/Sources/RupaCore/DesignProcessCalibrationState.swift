public enum DesignProcessCalibrationState: String, Codable, Equatable, Sendable {
    case uncalibrated
    case humanAnchored
    case agentReadable
    case measurementCalibrated

    public var multiplier: Double {
        switch self {
        case .uncalibrated:
            0.5
        case .humanAnchored:
            0.75
        case .agentReadable:
            0.9
        case .measurementCalibrated:
            1.0
        }
    }
}
