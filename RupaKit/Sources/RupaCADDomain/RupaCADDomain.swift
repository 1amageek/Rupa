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
      ExtrudeLowerer.registration(.solidProfile),
      ExtrudeLowerer.registration(.sheetProfile),
      ExtrudeLowerer.registration(.sheetCurve),
      RevolveLowerer.registration(.solidProfile),
      RevolveLowerer.registration(.sheetProfile),
      RevolveLowerer.registration(.sheetCurve),
      SolidSphereLowerer.registration,
      LoftLowerer.registration(.solid),
      LoftLowerer.registration(.sheet),
      LoftLowerer.registration(.replaceSolid),
      LoftLowerer.registration(.replaceSheet),
      ConstrainedSurfaceLowerer.registration(replacing: false),
      ConstrainedSurfaceLowerer.registration(replacing: true),
      SceneTransformLowerer.registration,
      ComponentDefineLowerer.registration,
      ComponentInstantiateLowerer.registration,
      PatternLinearLowerer.registration,
    ]
  }

  public static func registry() throws -> SemanticOperationRegistry {
    let registry = try SemanticOperationRegistry(registrations: registrations())
    try registry.validateOperations(
      RupaCADSemanticOperationID.all,
      version: operationVersion
    )
    return registry
  }
}
