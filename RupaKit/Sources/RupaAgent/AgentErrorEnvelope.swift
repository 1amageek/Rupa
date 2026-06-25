import Foundation
import RupaCore

public struct AgentErrorEnvelope: Codable, Equatable, Sendable {
    public var code: EditorError.Code
    public var message: String

    public init(code: EditorError.Code, message: String) {
        self.code = code
        self.message = message
    }

    public init(error: EditorError) {
        self.init(
            code: error.code,
            message: error.message
        )
    }

    public var editorError: EditorError {
        EditorError(code: code, message: message)
    }
}
