import Foundation
import SwiftCAD

public enum ExtendCurveShape: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case natural
    case linear
    case soft
    case reflective
    case arc
}

extension ExtendCurveShape {
    /// The shapes Extend Curve builds on a curve of `entity`'s kind, in the order the dialog offers
    /// them. A line's natural, soft and reflective continuations are straight (its Arc needs the
    /// arc's construction, a point it passes through, which a length does not give); an arc's
    /// natural, soft, reflective and arc continuations all follow its circle (Linear would make it
    /// a line and an arc, which no one sketch curve is). A spline continues its end span's
    /// own polynomial (Natural), its end tangent (Linear), its end curvature held (Arc) or fading
    /// to zero (Soft), or its own end mirrored across the end's normal (Reflective).
    public static func supported(for entity: SketchEntity) -> [ExtendCurveShape] {
        switch entity {
        case .line: [.natural, .linear, .soft, .reflective]
        case .arc: [.natural, .soft, .reflective, .arc]
        case .spline(let spline) where !spline.isClosed: [.natural, .linear, .soft, .reflective, .arc]
        case .spline, .circle, .point: []
        }
    }
}

