import Foundation
import SwiftCAD
import RupaCoreTypes

public struct ParameterSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: QuantityKind
    public var expression: String
    public var resolvedValue: Double?
    public var resolvedKind: QuantityKind?
    public var dependencyNames: [String]
    public var dependentNames: [String]
    public var sourceUsages: [ParameterSourceUsageSummary]
    public var diagnostics: [EditorDiagnostic]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case expression
        case resolvedValue
        case resolvedKind
        case dependencyNames
        case dependentNames
        case sourceUsages
        case diagnostics
    }

    public init(
        id: String,
        name: String,
        kind: QuantityKind,
        expression: String,
        resolvedValue: Double?,
        resolvedKind: QuantityKind?,
        dependencyNames: [String] = [],
        dependentNames: [String] = [],
        sourceUsages: [ParameterSourceUsageSummary] = [],
        diagnostics: [EditorDiagnostic]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.expression = expression
        self.resolvedValue = resolvedValue
        self.resolvedKind = resolvedKind
        self.dependencyNames = dependencyNames
        self.dependentNames = dependentNames
        self.sourceUsages = sourceUsages
        self.diagnostics = diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            kind: try container.decode(QuantityKind.self, forKey: .kind),
            expression: try container.decode(String.self, forKey: .expression),
            resolvedValue: try container.decodeIfPresent(Double.self, forKey: .resolvedValue),
            resolvedKind: try container.decodeIfPresent(QuantityKind.self, forKey: .resolvedKind),
            dependencyNames: try container.decodeIfPresent([String].self, forKey: .dependencyNames) ?? [],
            dependentNames: try container.decodeIfPresent([String].self, forKey: .dependentNames) ?? [],
            sourceUsages: try container.decodeIfPresent([ParameterSourceUsageSummary].self, forKey: .sourceUsages) ?? [],
            diagnostics: try container.decodeIfPresent([EditorDiagnostic].self, forKey: .diagnostics) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(expression, forKey: .expression)
        try container.encodeIfPresent(resolvedValue, forKey: .resolvedValue)
        try container.encodeIfPresent(resolvedKind, forKey: .resolvedKind)
        try container.encode(dependencyNames, forKey: .dependencyNames)
        try container.encode(dependentNames, forKey: .dependentNames)
        try container.encode(sourceUsages, forKey: .sourceUsages)
        try container.encode(diagnostics, forKey: .diagnostics)
    }

    public init(
        parameter: Parameter,
        table: ParameterTable,
        formatter: ParameterExpressionFormatter,
        sourceUsages: [ParameterSourceUsageSummary] = []
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

        let dependencyNames = Self.parameterNames(
            for: CADExpressionParameterReferenceCollector.parameterIDs(in: parameter.expression),
            table: table
        )
        let dependentNames = Self.dependentNames(
            for: parameter.id,
            table: table
        )

        self.init(
            id: parameter.id.description,
            name: parameter.name,
            kind: parameter.kind,
            expression: formatter.format(parameter.expression, parameters: table),
            resolvedValue: resolved?.value,
            resolvedKind: resolved?.kind,
            dependencyNames: dependencyNames,
            dependentNames: dependentNames,
            sourceUsages: sourceUsages,
            diagnostics: parameterDiagnostics
        )
    }

    private static func dependentNames(
        for id: ParameterID,
        table: ParameterTable
    ) -> [String] {
        table.parameters.values
            .filter { parameter in
                parameter.id != id
                    && CADExpressionParameterReferenceCollector.parameterIDs(in: parameter.expression).contains(id)
            }
            .map(\.name)
            .sorted()
    }

    private static func parameterNames(
        for ids: Set<ParameterID>,
        table: ParameterTable
    ) -> [String] {
        ids.compactMap { table.parameters[$0]?.name }
            .sorted()
    }
}
