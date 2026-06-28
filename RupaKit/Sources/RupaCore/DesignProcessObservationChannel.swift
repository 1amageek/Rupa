public enum DesignProcessObservationChannel: String, Codable, Equatable, Sendable {
    case humanReview
    case automatedTest
    case performanceMeasurement
    case runtimeDiagnostic
    case agentReadback
    case userFeedback
}
