import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite struct ExpressionMagnitudeTests {
    @Test func magnitudeRetainsUnitsDependenciesAndBothEvaluators() throws {
        let parameter = Parameter(name: "height", expression: .length(3, .millimeter), kind: .length)
        let table = ParameterTable(parameters: [parameter.id: parameter])
        let expression = CADExpression.hypot(.reference(parameter.id), .length(0.004, .meter))
        #expect(try table.inferredKind(for: expression) == .length)
        #expect(expression.referencedParameterIDs == [parameter.id])
        #expect(CADExpressionParameterReferenceCollector.parameterIDs(in: expression) == [parameter.id])
        #expect(abs(try table.resolvedValue(for: expression).value - 0.005) < 1e-15)
        let resolver = ParameterResolver()
        #expect(abs(try resolver.evaluate(expression, parameters: resolver.resolve(table)).value - 0.005) < 1e-15)
        let data = try JSONEncoder().encode(expression)
        #expect(try JSONDecoder().decode(CADExpression.self, from: data) == expression)
        let text = ParameterExpressionFormatter().format(expression, parameters: table)
        #expect(try ParameterExpressionParser().parse(text, parameters: table, targetKind: .length) == expression)
        let large = CADExpression.hypot(.scalar(1e200), .scalar(1e200))
        #expect(try table.resolvedValue(for: large).value.isFinite)
        #expect(try resolver.evaluate(large, parameters: resolver.resolve(table)).value.isFinite)
    }

    @Test func magnitudeAndNormalizationFailExplicitly() throws {
        let table = ParameterTable()
        let resolver = ParameterResolver()
        let resolved = try resolver.resolve(table)
        let incompatible = CADExpression.hypot(.length(1, .meter), .scalar(1))
        #expect(throws: UnitError.self) { try table.inferredKind(for: incompatible) }
        for expression in [incompatible, .hypot(.scalar(.infinity), .scalar(1)),
                           .divide(.length(1, .meter), .hypot(.length(0, .meter), .length(0, .meter)))] {
            #expect(throws: Error.self) { try table.resolvedValue(for: expression) }
            #expect(throws: Error.self) { try resolver.evaluate(expression, parameters: resolved) }
        }
        #expect(try table.resolvedValue(for: .hypot(.scalar(0), .scalar(0))).value == 0)
        for text in ["hypot(1m)", "hypot(1m,)", "hypot(1m,2m,3m)"] {
            #expect(throws: EditorError.self) { try ParameterExpressionParser().parse(text, parameters: table, targetKind: .length) }
        }
    }
}
