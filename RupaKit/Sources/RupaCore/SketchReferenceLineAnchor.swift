import Foundation
import SwiftCAD

public struct SketchReferenceLineAnchor: Codable, Equatable, Sendable {
    public var point: Point2D

    public init(point: Point2D) {
        self.point = point
    }
}
