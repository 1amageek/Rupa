import SwiftCAD
import Testing
@testable import RupaCore

@Test func patternArrayExpressionResolverResolvesReferencedValues() throws {
    var document = DesignDocument.empty(named: "Pattern Array Expressions")
    try document.upsertParameter(
        name: "spacing",
        expression: .constant(.length(25.0, unit: .millimeter)),
        kind: .length
    )
    try document.upsertParameter(
        name: "sweepAngle",
        expression: .constant(.angle(45.0, unit: .degree)),
        kind: .angle
    )
    try document.upsertParameter(
        name: "extentRatio",
        expression: .constant(.scalar(0.75)),
        kind: .scalar
    )
    let spacing = try #require(document.cadDocument.parameters.parameters.values.first { $0.name == "spacing" })
    let sweepAngle = try #require(document.cadDocument.parameters.parameters.values.first { $0.name == "sweepAngle" })
    let extentRatio = try #require(document.cadDocument.parameters.parameters.values.first { $0.name == "extentRatio" })
    let resolver = PatternArrayExpressionResolver(parameters: document.cadDocument.parameters)

    #expect(abs(try resolver.lengthMeters(for: .reference(spacing.id)) - 0.025) < 1.0e-12)
    #expect(abs(try resolver.angleRadians(for: .reference(sweepAngle.id)) - Double.pi / 4.0) < 1.0e-12)
    #expect(abs(try resolver.scalarValue(for: .reference(extentRatio.id)) - 0.75) < 1.0e-12)
}

@Test func patternArrayExpressionResolverRejectsWrongQuantityKind() throws {
    var document = DesignDocument.empty(named: "Pattern Array Expressions")
    try document.upsertParameter(
        name: "spacing",
        expression: .constant(.length(25.0, unit: .millimeter)),
        kind: .length
    )
    let spacing = try #require(document.cadDocument.parameters.parameters.values.first { $0.name == "spacing" })
    let resolver = PatternArrayExpressionResolver(parameters: document.cadDocument.parameters)
    var caught: EditorError?

    do {
        _ = try resolver.angleRadians(for: .reference(spacing.id))
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message == "Pattern array angle must resolve to an angle.")
}
