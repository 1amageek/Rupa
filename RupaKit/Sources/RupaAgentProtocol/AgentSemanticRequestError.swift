import Foundation

public struct AgentSemanticRequestError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case duplicateArgument
        case duplicateParameter
        case directLocalReference
    }

    public let code: Code
    public let name: String

    public init(code: Code, name: String) {
        self.code = code
        self.name = name
    }

    public var errorDescription: String? {
        switch code {
        case .duplicateArgument:
            "Semantic request contains duplicate argument \(name)."
        case .duplicateParameter:
            "Semantic request contains duplicate parameter \(name)."
        case .directLocalReference:
            "Direct semantic request cannot represent local output reference \(name)."
        }
    }
}
