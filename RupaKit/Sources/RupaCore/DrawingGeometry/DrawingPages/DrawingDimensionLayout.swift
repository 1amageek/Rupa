import SwiftCAD

/// Explicit paper presentation bound to one current original measurement.
public struct DrawingDimensionLayout: Codable, Equatable, Sendable {
    public enum Geometry: Codable, Equatable, Sendable {
        case linear(offset: Double)
        case radial(leaderOvershoot: Double)
        case angular(radius: Double)
        case boundary
    }
    public let annotationID: String
    public let geometry: Geometry
    public let style: DrawingDimensionStyle

    public init(annotationID: String, geometry: Geometry, style: DrawingDimensionStyle) throws {
        try style.validate()
        guard !annotationID.isEmpty else { throw EditorError(code: .commandInvalid, message: "Paper dimension needs a source annotation identity.") }
        switch geometry {
        case .linear(let offset):
            guard offset.isFinite else { throw EditorError(code: .commandInvalid, message: "Paper dimension offset is nonfinite.") }
        case .radial(let overshoot):
            guard overshoot.isFinite, overshoot >= 0 else { throw EditorError(code: .commandInvalid, message: "Radial paper overshoot is invalid.") }
        case .angular(let radius):
            guard radius.isFinite, radius > 0 else { throw EditorError(code: .commandInvalid, message: "Angular paper radius must be finite and positive.") }
        case .boundary: break
        }
        self.annotationID = annotationID; self.geometry = geometry; self.style = style
    }
    public func validate() throws {
        _ = try Self(annotationID: annotationID, geometry: geometry, style: style)
    }
}
