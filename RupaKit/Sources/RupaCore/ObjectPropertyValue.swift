import Foundation
import SwiftCAD

public enum ObjectPropertyValue: Codable, Hashable, Sendable {
    public enum ValueKind: String, Codable, Hashable, Sendable {
        case length
        case number
        case integer
        case boolean
        case angle
        case text
        case material
    }

    case length(Double)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case angle(Double)
    case text(String)
    case material(MaterialID?)

    public var valueKind: ValueKind {
        switch self {
        case .length:
            .length
        case .number:
            .number
        case .integer:
            .integer
        case .boolean:
            .boolean
        case .angle:
            .angle
        case .text:
            .text
        case .material:
            .material
        }
    }

    public func validate(id: ObjectPropertyID) throws {
        switch self {
        case .length(let value), .number(let value), .angle(let value):
            guard value.isFinite else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Object property \(id.rawValue) must contain a finite numeric value."
                )
            }
        case .integer, .boolean, .text, .material:
            return
        }
    }
}
