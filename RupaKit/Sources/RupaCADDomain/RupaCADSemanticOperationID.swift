import RupaDomainFoundation

public enum RupaCADSemanticOperationID {
  public static let sketchLine: DomainCapabilityID = "cad.sketch.line"
  public static let sketchRectangle: DomainCapabilityID = "cad.sketch.rectangle"
  public static let sketchCircle: DomainCapabilityID = "cad.sketch.circle"
  public static let sketchConstrained: DomainCapabilityID = "cad.sketch.constrained"
  public static let solidBox: DomainCapabilityID = "cad.solid.box"
  public static let solidCylinder: DomainCapabilityID = "cad.solid.cylinder"
  public static let solidExtrude: DomainCapabilityID = "cad.solid.extrude"
  public static let solidSphere: DomainCapabilityID = "cad.solid.sphere"
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
    solidSphere,
    sceneTransform,
    componentDefine,
    componentInstantiate,
    patternLinear,
  ]
}
