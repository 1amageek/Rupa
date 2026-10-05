import SwiftCAD

/// Caller-authored paper lengths; there are no inferred defaults.
public struct DrawingDimensionStyle: Codable, Equatable, Sendable {
    public enum ArrowKind: String, Codable, Equatable, Sendable { case none, open, closedOutline }
    public let extensionGap: Double
    public let extensionOvershoot: Double
    public let arrowLength: Double
    public let arrowWidth: Double
    public let arrowKind: ArrowKind

    public init(extensionGap: Double, extensionOvershoot: Double, arrowLength: Double,
                arrowWidth: Double, arrowKind: ArrowKind) throws {
        guard extensionGap.isFinite, extensionGap >= 0, extensionOvershoot.isFinite, extensionOvershoot >= 0,
              arrowLength.isFinite, arrowLength >= 0, arrowWidth.isFinite, arrowWidth >= 0 else {
            throw EditorError(code: .commandInvalid, message: "Paper dimension lengths must be finite and nonnegative.")
        }
        switch arrowKind {
        case .none: break
        case .open, .closedOutline:
            guard arrowLength > 0, arrowWidth > 0 else {
                throw EditorError(code: .commandInvalid, message: "Paper arrows require explicit positive length and width.")
            }
        }
        self.extensionGap = extensionGap; self.extensionOvershoot = extensionOvershoot
        self.arrowLength = arrowLength; self.arrowWidth = arrowWidth; self.arrowKind = arrowKind
    }
    public func validate() throws {
        _ = try Self(extensionGap: extensionGap, extensionOvershoot: extensionOvershoot,
            arrowLength: arrowLength, arrowWidth: arrowWidth, arrowKind: arrowKind)
    }
}
