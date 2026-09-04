import Foundation

/// Every failure this module can report, carrying the stage that failed.
public struct ResponsivenessBaselineError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Equatable, Sendable, Codable {
        case invalidFixtureParameters
        case fixtureConstructionFailed
        case sceneConstructionFailed
        case planPreparationFailed
        case planConsumptionFailed
        case footprintSampleUnavailable
        case invalidMeasurementRequest
        case invalidEnvironmentInput
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String {
        "\(code.rawValue): \(message)"
    }
}
