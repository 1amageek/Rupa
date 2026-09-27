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
    /// them. A line's natural, soft and reflective continuations are all straight; an arc's
    /// natural, soft, reflective and arc continuations all follow its circle. A spline continues
    /// its end span's own cubic (Natural) or its end tangent (Linear); its Soft, Reflective and Arc
    /// shapes wait for their definitions (SK4.5).
    public static func supported(for entity: SketchEntity) -> [ExtendCurveShape] {
        switch entity {
        case .line: [.natural, .linear, .soft, .reflective]
        case .arc: [.natural, .soft, .reflective, .arc]
        case .spline(let spline) where !spline.isClosed: [.natural, .linear]
        case .spline, .circle, .point: []
        }
    }
}

