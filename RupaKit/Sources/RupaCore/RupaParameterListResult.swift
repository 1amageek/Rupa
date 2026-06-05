import Foundation
import SwiftCAD

public struct RupaParameterListResult: Codable, Equatable, Sendable {
    public var message: String
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var parameters: [RupaParameterSummary]
    public var diagnostics: [RupaDiagnostic]

    public init(
        message: String,
        generation: DocumentGeneration,
        dirty: Bool,
        parameters: [RupaParameterSummary],
        diagnostics: [RupaDiagnostic]
    ) {
        self.message = message
        self.generation = generation
        self.dirty = dirty
        self.parameters = parameters
        self.diagnostics = diagnostics
    }

    public init(
        document: RupaDocument,
        generation: DocumentGeneration,
        dirty: Bool,
        diagnostics: [RupaDiagnostic]
    ) {
        let table = document.cadDocument.parameters
        let formatter = RupaParameterExpressionFormatter()
        let parameters = table.parameters.values
            .sorted { $0.name < $1.name }
            .map { parameter in
                RupaParameterSummary(
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
