import Foundation
import SwiftCAD

public struct ParameterSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: QuantityKind
    public var expression: String
    public var resolvedValue: Double?
    public var resolvedKind: QuantityKind?
    public var diagnostics: [EditorDiagnostic]

    public init(
        id: String,
        name: String,
        kind: QuantityKind,
        expression: String,
        resolvedValue: Double?,
        resolvedKind: QuantityKind?,
        diagnostics: [EditorDiagnostic]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.expression = expression
        self.resolvedValue = resolvedValue
        self.resolvedKind = resolvedKind
        self.diagnostics = diagnostics
    }

    public init(
        parameter: Parameter,
        table: ParameterTable,
        formatter: ParameterExpressionFormatter
    ) {
        let resolved: Quantity?
        let parameterDiagnostics: [EditorDiagnostic]
        do {
            resolved = try table.resolvedValue(for: parameter.expression)
            parameterDiagnostics = []
        } catch {
            resolved = nil
            parameterDiagnostics = [
                EditorDiagnostic(
                    severity: .error,
                    message: "Parameter \(parameter.name) could not be resolved: \(error)."
                ),
            ]
        }

        self.init(
            id: parameter.id.description,
            name: parameter.name,
            kind: parameter.kind,
            expression: formatter.format(parameter.expression, parameters: table),
            resolvedValue: resolved?.value,
            resolvedKind: resolved?.kind,
            diagnostics: parameterDiagnostics
        )
    }
}
