import Foundation

public struct EditorDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    public let id: UUID
    public var severity: Severity
    public var message: String

    public init(
        id: UUID = UUID(),
        severity: Severity,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}
