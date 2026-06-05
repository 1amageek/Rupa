import Foundation
import SwiftCAD

public struct ParameterExpressionDefaults: Codable, Equatable, Sendable {
    public var lengthUnit: LengthDisplayUnit
    public var angleUnit: AngleUnit

    public init(
        lengthUnit: LengthDisplayUnit = .meter,
        angleUnit: AngleUnit = .degree
    ) {
        self.lengthUnit = lengthUnit
        self.angleUnit = angleUnit
    }
}
