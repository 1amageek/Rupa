import SwiftCAD

/// An ID-free geometric entity accepted by semantic sketch creation.
public enum SketchCreationEntity: Codable, Equatable, Hashable, Sendable {
  case line(start: SketchPoint, end: SketchPoint)
  case circle(center: SketchPoint, radius: CADExpression)
}
