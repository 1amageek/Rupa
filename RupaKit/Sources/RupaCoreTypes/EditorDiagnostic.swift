import Foundation

public struct EditorDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    public enum Code: String, Codable, Sendable {
        case workspacePrecisionNotice
        case workspacePrecisionWarning
        case workspaceScaleRecommendation
        case workspaceScaleWarning
    }

    public let id: UUID
    public var severity: Severity
    public var code: Code?
    public var message: String

    public init(
        id: UUID = UUID(),
        severity: Severity,
        code: Code? = nil,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
    }
}
