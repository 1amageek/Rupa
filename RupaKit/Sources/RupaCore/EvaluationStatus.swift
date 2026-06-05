import Foundation

public enum EvaluationStatus: Codable, Equatable, Sendable {
    case notEvaluated
    case valid
    case failed(message: String)
}
