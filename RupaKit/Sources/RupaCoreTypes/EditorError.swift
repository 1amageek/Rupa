import Foundation

public struct EditorError: Error, Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case agentUnavailable = "agent.unavailable"
        case agentConnectionFailed = "agent.connectionFailed"
        case documentOpenInApp = "document.openInApp"
        case documentGenerationMismatch = "document.generationMismatch"
        case documentLoadFailed = "document.loadFailed"
        case documentSaveFailed = "document.saveFailed"
        case commandInvalid = "command.invalid"
        case commandFailed = "command.failed"
        case sessionNotFound = "session.notFound"
        case referenceUnresolved = "reference.unresolved"
        case evaluationFailed = "evaluation.failed"
        case exportFailed = "export.failed"
    }

    public var code: Code
    public var message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

extension EditorError: LocalizedError {
    public var errorDescription: String? {
        message
    }
}
