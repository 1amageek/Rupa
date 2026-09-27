import Foundation
import RupaCore

/// A typed value field of the Move, Rotate or Scale dialog.
///
/// A field holds its text until Return; only then does the value become one motion, so the
/// digits of a value on their way in never apply as motions of their own.
enum WorkspaceTransformTypedField: Hashable, Sendable {
    /// Move's distance along a frame axis, in the display unit.
    case distance(SceneTransformAxis)
    /// Rotate's angle about the typed axis, in degrees.
    case angle
    /// Scale's factor along a frame axis.
    case factor(SceneTransformAxis)
    /// Freestyle Scale's ratio, once its axis is picked.
    case ratio
    /// The length freestyle Scale makes its picked axis, in the display unit.
    case length

    var title: String {
        switch self {
        case .distance(let axis), .factor(let axis): axis.rawValue.uppercased()
        case .angle: "Angle"
        case .ratio: "Ratio"
        case .length: "Length"
        }
    }

    /// The number typed as `text`, read in the current locale; nil when nothing is typed.
    func value(of text: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let value: Double
        do {
            value = try FloatingPointFormatStyle<Double>.number.parseStrategy.parse(trimmed)
        } catch {
            throw EditorError(code: .commandInvalid, message: "\(title): \"\(trimmed)\" is not a number.")
        }
        guard value.isFinite else {
            throw EditorError(code: .commandInvalid, message: "\(title) must be finite.")
        }
        return value
    }
}
