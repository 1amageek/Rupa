import SwiftCAD

/// A complete sketch request that contains no caller-created persistent identity.
public struct SketchCreationPlan: Codable, Equatable, Hashable, Sendable {
  public let plane: SketchPlane
  public let entities: [SketchCreationEntity]
  public let constraints: [SketchCreationConstraint]

  public init(
    plane: SketchPlane,
    entities: [SketchCreationEntity],
    constraints: [SketchCreationConstraint] = []
  ) {
    self.plane = plane
    self.entities = entities
    self.constraints = constraints
  }
}
