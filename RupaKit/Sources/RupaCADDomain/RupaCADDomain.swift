import RupaDomainFoundation

public enum RupaCADDomain {
  public static let operationVersion = SemanticOperationVersion(
    major: 1,
    minor: 0,
    patch: 0
  )

  public static func registrations() -> [SemanticOperationRegistration] {
    [
      SketchLineLowerer.registration,
      SketchRectangleLowerer.registration,
      SketchCircleLowerer.registration,
      SketchConstrainedLowerer.registration,
      SolidBoxLowerer.registration,
      SolidCylinderLowerer.registration,
      SolidExtrudeLowerer.registration,
      SolidSphereLowerer.registration,
      SceneTransformLowerer.registration,
      ComponentDefineLowerer.registration,
      ComponentInstantiateLowerer.registration,
      PatternLinearLowerer.registration,
    ]
  }

  public static func registry() throws -> SemanticOperationRegistry {
    try SemanticOperationRegistry(registrations: registrations())
  }
}
