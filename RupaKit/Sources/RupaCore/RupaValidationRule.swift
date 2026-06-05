import Foundation
import SwiftCAD

public struct RupaValidationRule: Codable, Hashable, Identifiable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable {
        case geometry
        case scale
        case manufacturing
        case visualization
        case documentation
        case interoperability
    }

    public var id: RupaValidationRuleID
    public var name: String
    public var category: Category
    public var severity: RupaDiagnostic.Severity
    public var isEnabled: Bool
    public var properties: [String: String]

    public init(
        id: RupaValidationRuleID = RupaValidationRuleID(),
        name: String,
        category: Category,
        severity: RupaDiagnostic.Severity = .warning,
        isEnabled: Bool = true,
        properties: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.severity = severity
        self.isEnabled = isEnabled
        self.properties = properties
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RupaDocumentValidationError.invalidProductMetadata("Validation rule names must not be empty.")
        }
        try validateProperties(properties, owner: "validation rule")
    }
}
