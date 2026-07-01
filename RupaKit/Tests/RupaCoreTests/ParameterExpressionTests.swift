import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func parameterExpressionParserResolvesReferencesAndMixedUnits() throws {
    var document = DesignDocument.empty(named: "Parameters")
    try document.upsertParameter(
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length
    )

    let expression = try ParameterExpressionParser().parse(
        "width * 2 + 5mm",
        parameters: document.cadDocument.parameters,
        targetKind: .length
    )
    let resolved = try document.cadDocument.parameters.resolvedValue(for: expression)

    #expect(resolved.kind == .length)
    #expect(abs(resolved.value - 0.025) < 0.000_000_000_001)
}

@Test func parameterExpressionParserAppliesDefaultUnitToSingleBareLiteral() throws {
    let expression = try ParameterExpressionParser().parse(
        "25",
        parameters: ParameterTable(),
        targetKind: .length,
        defaults: ParameterExpressionDefaults(lengthUnit: .millimeter)
    )
    let resolved = try ParameterTable().resolvedValue(for: expression)

    #expect(resolved.kind == .length)
    #expect(abs(resolved.value - 0.025) < 0.000_000_000_001)
}

@Test func lengthInputParserResolvesExplicitUnitsAndGroupedValues() throws {
    let parser = LengthInputParser()
    let siteMeters = try parser.parseMeters(
        from: "1,000 km",
        defaultUnit: .millimeter
    )
    let detailMeters = try parser.parseMeters(
        from: "250 μm",
        defaultUnit: .meter
    )
    let expressionMeters = try parser.parseMeters(
        from: "1km / 2",
        defaultUnit: .millimeter
    )

    #expect(abs(siteMeters - 1_000_000.0) < 0.000_000_000_001)
    #expect(abs(detailMeters - 0.000_25) < 0.000_000_000_001)
    #expect(abs(expressionMeters - 500.0) < 0.000_000_000_001)
}

@Test func lengthInputParserResolvesArchitecturalFeetAndInches() throws {
    let parser = LengthInputParser()
    let markedMeters = try parser.parseMeters(
        from: "6' 4\"",
        defaultUnit: .millimeter
    )
    let wordMeters = try parser.parseMeters(
        from: "6 ft 4 1/2 in",
        defaultUnit: .millimeter
    )
    let fractionalMeters = try parser.parseMeters(
        from: "1/2 in",
        defaultUnit: .meter
    )
    let expectedMarkedMeters = LengthDisplayUnit.foot.meters(from: 6.0)
        + LengthDisplayUnit.inch.meters(from: 4.0)
    let expectedWordMeters = LengthDisplayUnit.foot.meters(from: 6.0)
        + LengthDisplayUnit.inch.meters(from: 4.5)

    #expect(abs(markedMeters - expectedMarkedMeters) < 0.000_000_000_001)
    #expect(abs(wordMeters - expectedWordMeters) < 0.000_000_000_001)
    #expect(abs(fractionalMeters - LengthDisplayUnit.inch.meters(from: 0.5)) < 0.000_000_000_001)
}

@Test func lengthInputParserResolvesDocumentParameterExpressions() throws {
    var document = DesignDocument.empty(named: "Length Input Parameters")
    try document.upsertParameter(
        name: "siteWidth",
        expression: .constant(.length(1.0, unit: .kilometer)),
        kind: .length
    )

    let expression = try LengthInputParser().parseExpression(
        from: "siteWidth + 250m",
        defaultUnit: .millimeter,
        parameters: document.cadDocument.parameters
    )
    let resolved = try document.cadDocument.parameters.resolvedValue(for: expression)

    #expect(resolved.kind == .length)
    #expect(abs(resolved.value - 1_250.0) < 0.000_000_000_001)
}

@Test func parameterExpressionParserRejectsUnknownParameterBeforeMutation() throws {
    var caught: EditorError?

    do {
        _ = try ParameterExpressionParser().parse(
            "missing * 2",
            parameters: ParameterTable(),
            targetKind: .length
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func parameterExpressionParserRejectsSelfReferenceBeforeMutation() throws {
    var document = DesignDocument.empty(named: "Parameters")
    try document.upsertParameter(
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length
    )
    var caught: EditorError?

    do {
        _ = try ParameterExpressionParser().parseForUpsert(
            "width + 1mm",
            parameterName: "width",
            parameters: document.cadDocument.parameters,
            targetKind: .length
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func parameterListResultReportsFormattedExpressionAndResolvedValue() throws {
    var document = DesignDocument.empty(named: "Parameters")
    try document.upsertParameter(
        name: "width",
        expression: .constant(.length(10.0, unit: .millimeter)),
        kind: .length
    )
    let width = try #require(
        document.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    try document.upsertParameter(
        name: "doubleWidth",
        expression: .multiply(
            .reference(width.id),
            .constant(.scalar(2.0))
        ),
        kind: .length
    )

    let result = ParameterListResult(
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
