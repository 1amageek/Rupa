import ArgumentParser
import Foundation
import RupaCore

public struct CLISketchPointArgument: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func sketchPoint(unit: LengthDisplayUnit) throws -> SketchPoint {
        SketchPoint(
            x: try CLIExpressionParser.length(value: x, unit: unit, valueName: "Sketch point x"),
            y: try CLIExpressionParser.length(value: y, unit: unit, valueName: "Sketch point y")
        )
    }
}

extension CLISketchPointArgument: ExpressibleByArgument {
    public init?(argument: String) {
        let components = argument.split(separator: ",", omittingEmptySubsequences: false)
        guard components.count == 2 else {
            return nil
        }
        let xValue = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let yValue = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let x = Double(xValue),
              let y = Double(yValue) else {
            return nil
        }
        self.init(x: x, y: y)
    }
}
