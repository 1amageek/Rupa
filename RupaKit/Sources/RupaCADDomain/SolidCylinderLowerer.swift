import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct SolidCylinderLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.solidCylinder,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "baseCenter", type: .point),
      .init(id: "axis", type: .direction),
      .init(id: "radius", type: .number(unit: .meter)),
      .init(id: "height", type: .number(unit: .meter)),
    ],
    outputs: [
      .init(id: "profile", type: .feature, selector: .feature(index: 0)),
      .init(
        id: "body",
        type: .sourceBody(role: .body),
        selector: .sourceBody(role: .body, index: 0)
      ),
      .init(id: "profileScene", type: .sceneNode, selector: .sceneNode(index: 1)),
      .init(id: "bodyScene", type: .sceneNode, selector: .sceneNode(index: 0)),
    ],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 5,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  )

  static let registration = SemanticOperationRegistration(
    descriptor: descriptor,
    lowerer: SolidCylinderLowerer()
  )

  let operationID = RupaCADSemanticOperationID.solidCylinder
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let baseCenter = CADSemanticLoweringSupport.corePoint(
      try CADSemanticLoweringSupport.point("baseCenter", in: request)
    )
    let axis = try CADSemanticLoweringSupport.normalizedVector(
      CADSemanticLoweringSupport.direction("axis", in: request)
    )
    let radius = try CADSemanticLoweringSupport.positiveLength("radius", in: request)
    let height = try CADSemanticLoweringSupport.positiveLength("height", in: request)
    let plane = SketchPlane.plane(Plane3D(origin: baseCenter, normal: axis))
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { _ in
          try ContextResolvedEditorCommand(
            validating: .createExtrudedCircle(
              name: name,
              plane: plane,
              center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
              radius: .length(radius, .meter),
              depth: .length(height, .meter),
              direction: .normal
            ))
        }
      ))
  }
}
