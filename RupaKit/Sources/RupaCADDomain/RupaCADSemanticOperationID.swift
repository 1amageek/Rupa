import RupaDomainFoundation

public enum RupaCADSemanticOperationID {
  public static let sketchLine: DomainCapabilityID = "cad.sketch.line"
  public static let sketchRectangle: DomainCapabilityID = "cad.sketch.rectangle"
  public static let sketchCircle: DomainCapabilityID = "cad.sketch.circle"
  public static let sketchConstrained: DomainCapabilityID = "cad.sketch.constrained"
  public static let solidBox: DomainCapabilityID = "cad.solid.box"
  public static let solidCylinder: DomainCapabilityID = "cad.solid.cylinder"
  public static let solidExtrude: DomainCapabilityID = "cad.solid.extrude"
  public static let surfaceExtrude: DomainCapabilityID = "cad.surface.extrude"
  public static let surfaceExtrudeCurve: DomainCapabilityID = "cad.surface.extrudeCurve"
  public static let solidRevolve: DomainCapabilityID = "cad.solid.revolve"
  public static let surfaceRevolve: DomainCapabilityID = "cad.surface.revolve"
  public static let surfaceRevolveCurve: DomainCapabilityID = "cad.surface.revolveCurve"
  public static let solidSphere: DomainCapabilityID = "cad.solid.sphere"
  public static let solidLoft: DomainCapabilityID = "cad.solid.loft"
  public static let surfaceLoft: DomainCapabilityID = "cad.surface.loft"
  public static let solidLoftReplace: DomainCapabilityID = "cad.solid.loft.replace"
  public static let surfaceLoftReplace: DomainCapabilityID = "cad.surface.loft.replace"
  public static let sceneTransform: DomainCapabilityID = "cad.scene.transform"
  public static let componentDefine: DomainCapabilityID = "cad.component.define"
  public static let componentInstantiate: DomainCapabilityID = "cad.component.instantiate"
  public static let patternLinear: DomainCapabilityID = "cad.pattern.linear"

  public static let all: [DomainCapabilityID] = [
    sketchLine,
    sketchRectangle,
    sketchCircle,
    sketchConstrained,
    solidBox,
    solidCylinder,
    solidExtrude,
    surfaceExtrude,
    surfaceExtrudeCurve,
    solidRevolve,
    surfaceRevolve,
    surfaceRevolveCurve,
    solidSphere,
    solidLoft,
    surfaceLoft,
    solidLoftReplace,
    surfaceLoftReplace,
    sceneTransform,
    componentDefine,
    componentInstantiate,
    patternLinear,
  ]
}
