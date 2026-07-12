import Foundation

public struct NURBSCurveError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case invalidDegree
        case invalidControlPointCount
        case invalidWeight
        case invalidKnotVector
        case parameterOutOfRange
        case invalidSampleCount
        case zeroHomogeneousWeight
    }

    public var code: Code
    public var message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
