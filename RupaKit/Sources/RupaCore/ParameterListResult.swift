import Foundation
import SwiftCAD

public struct ParameterListResult: Codable, Equatable, Sendable {
    public var message: String
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var parameters: [ParameterSummary]
    public var diagnostics: [EditorDiagnostic]

    public init(
        message: String,
        generation: DocumentGeneration,
        dirty: Bool,
        parameters: [ParameterSummary],
        diagnostics: [EditorDiagnostic]
    ) {
        self.message = message
        self.generation = generation
        self.dirty = dirty
        self.parameters = parameters
        self.diagnostics = diagnostics
    }

    public init(
        document: DesignDocument,
        generation: DocumentGeneration,
        dirty: Bool,
        diagnostics: [EditorDiagnostic]
    ) {
        let table = document.cadDocument.parameters
        let formatter = ParameterExpressionFormatter()
        let parameters = table.parameters.values
            .sorted { $0.name < $1.name }
            .map { parameter in
                ParameterSummary(
                    parameter: parameter,
                    table: table,
                    formatter: formatter
                )
            }
        self.init(
            message: "\(parameters.count) parameters.",
            generation: generation,
            dirty: dirty,
            parameters: parameters,
            diagnostics: diagnostics
        )
    }
}
