import Foundation
import RupaCore

struct WorkspaceParameterInspectorState: Equatable, Sendable {
    struct Row: Equatable, Identifiable, Sendable {
        var id: String
        var name: String
        var kind: QuantityKind
        var kindTitle: String
        var expression: String
        var resolvedTitle: String
        var dependencyTitle: String
        var dependentTitle: String
        var sourceUsageTitle: String
        var diagnosticTitle: String
        var hasDiagnostics: Bool

        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.id == rhs.id
                && lhs.name == rhs.name
                && lhs.kind.rawValue == rhs.kind.rawValue
                && lhs.kindTitle == rhs.kindTitle
                && lhs.expression == rhs.expression
                && lhs.resolvedTitle == rhs.resolvedTitle
                && lhs.dependencyTitle == rhs.dependencyTitle
                && lhs.dependentTitle == rhs.dependentTitle
                && lhs.sourceUsageTitle == rhs.sourceUsageTitle
                && lhs.diagnosticTitle == rhs.diagnosticTitle
                && lhs.hasDiagnostics == rhs.hasDiagnostics
        }
    }

    var rows: [Row]
    var summaryTitle: String
    var diagnosticTitle: String
    var hasDiagnostics: Bool

    init(
        result: ParameterListResult,
        displayUnit: LengthDisplayUnit
    ) {
        self.rows = result.parameters.map { parameter in
            Row(
                id: parameter.id,
                name: parameter.name,
                kind: parameter.kind,
                kindTitle: Self.kindTitle(parameter.kind),
                expression: parameter.expression,
                resolvedTitle: Self.resolvedTitle(
                    value: parameter.resolvedValue,
                    kind: parameter.resolvedKind,
                    displayUnit: displayUnit
                ),
                dependencyTitle: Self.nameListTitle(parameter.dependencyNames),
                dependentTitle: Self.nameListTitle(parameter.dependentNames),
                sourceUsageTitle: Self.sourceUsageTitle(parameter.sourceUsages),
                diagnosticTitle: Self.diagnosticTitle(parameter.diagnostics),
                hasDiagnostics: parameter.diagnostics.isEmpty == false
            )
        }
        self.summaryTitle = result.message
        self.diagnosticTitle = Self.diagnosticTitle(result.diagnostics)
        self.hasDiagnostics = result.diagnostics.isEmpty == false
    }

    private static func kindTitle(_ kind: QuantityKind) -> String {
        switch kind {
        case .length:
            "Length"
        case .angle:
            "Angle"
        case .scalar:
            "Scalar"
        }
    }

    private static func resolvedTitle(
        value: Double?,
        kind: QuantityKind?,
        displayUnit: LengthDisplayUnit
    ) -> String {
        guard let value,
              let kind else {
            return "Unresolved"
        }
        switch kind {
        case .length:
            let unit = displayUnit.readableUnit(forMeters: value)
            return LengthDisplayText.lengthString(
                fromMeters: value,
                unit: unit,
                maximumFractionDigits: 6
            )
        case .angle:
            let degrees = value * 180.0 / Double.pi
            return "\(WorkspaceInspectorNumberText.string(from: degrees)) deg"
        case .scalar:
            return WorkspaceInspectorNumberText.string(from: value)
        }
    }

    private static func nameListTitle(_ names: [String]) -> String {
        guard names.isEmpty == false else {
            return "None"
        }
        return names.joined(separator: ", ")
    }

    private static func sourceUsageTitle(
        _ usages: [ParameterSourceUsageSummary]
    ) -> String {
        guard usages.isEmpty == false else {
            return "None"
        }
        return usages.map { usage in
            let feature = usage.featureName ?? usage.operation
            return "\(feature): \(usage.expressionPath)"
        }
        .joined(separator: ", ")
    }

    private static func diagnosticTitle(_ diagnostics: [EditorDiagnostic]) -> String {
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        let info = diagnostics.filter { $0.severity == .info }.count
        return "\(errors) errors, \(warnings) warnings, \(info) info"
    }
}
