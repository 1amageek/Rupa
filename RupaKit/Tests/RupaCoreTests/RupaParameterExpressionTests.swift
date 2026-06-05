import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func parameterExpressionParserResolvesReferencesAndMixedUnits() throws {
    var document = RupaDocument.empty(named: "Parameters")
    document.upsertParameter(
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length
    )

    let expression = try RupaParameterExpressionParser().parse(
        "width * 2 + 5mm",
        parameters: document.cadDocument.parameters,
        targetKind: .length
    )
    let resolved = try document.cadDocument.parameters.resolvedValue(for: expression)

    #expect(resolved.kind == .length)
    #expect(abs(resolved.value - 0.025) < 0.000_000_000_001)
}

@Test func parameterExpressionParserAppliesDefaultUnitToSingleBareLiteral() throws {
    let expression = try RupaParameterExpressionParser().parse(
        "25",
        parameters: ParameterTable(),
        targetKind: .length,
        defaults: RupaParameterExpressionDefaults(lengthUnit: .millimeter)
    )
    let resolved = try ParameterTable().resolvedValue(for: expression)

    #expect(resolved.kind == .length)
    #expect(abs(resolved.value - 0.025) < 0.000_000_000_001)
}

@Test func parameterExpressionParserRejectsUnknownParameterBeforeMutation() throws {
    var caught: RupaError?

    do {
        _ = try RupaParameterExpressionParser().parse(
            "missing * 2",
            parameters: ParameterTable(),
            targetKind: .length
        )
    } catch let error as RupaError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func parameterExpressionParserRejectsSelfReferenceBeforeMutation() throws {
    var document = RupaDocument.empty(named: "Parameters")
    document.upsertParameter(
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length
    )
    var caught: RupaError?

    do {
        _ = try RupaParameterExpressionParser().parseForUpsert(
            "width + 1mm",
            parameterName: "width",
            parameters: document.cadDocument.parameters,
            targetKind: .length
        )
    } catch let error as RupaError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func parameterListResultReportsFormattedExpressionAndResolvedValue() throws {
    var document = RupaDocument.empty(named: "Parameters")
    document.upsertParameter(
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length
    )
    let width = try #require(
        document.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    document.upsertParameter(
        name: "doubleWidth",
        expression: .multiply(
            .reference(width.id),
            .constant(.scalar(2.0))
        ),
        kind: .length
    )

    let result = RupaParameterListResult(
        document: document,
        generation: DocumentGeneration(2),
        dirty: true,
        diagnostics: []
    )
    let summary = try #require(result.parameters.first { $0.name == "doubleWidth" })

    #expect(result.message == "2 parameters.")
    #expect(summary.expression == "(width * 2)")
    #expect(summary.resolvedKind == .length)
    #expect(abs((summary.resolvedValue ?? 0.0) - 0.02) < 0.000_000_000_001)
}
