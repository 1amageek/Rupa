import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct SolidBoxLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.solidBox,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "origin", type: .point),
      .init(id: "width", type: .number(unit: .meter)),
      .init(id: "depth", type: .number(unit: .meter)),
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
    lowerer: SolidBoxLowerer()
  )

  let operationID = RupaCADSemanticOperationID.solidBox
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let origin = CADSemanticLoweringSupport.corePoint(
      try CADSemanticLoweringSupport.point("origin", in: request)
    )
    let width = try CADSemanticLoweringSupport.positiveLength("width", in: request)
    let depth = try CADSemanticLoweringSupport.positiveLength("depth", in: request)
    let height = try CADSemanticLoweringSupport.positiveLength("height", in: request)
    let bottomCenter = Point3D(
      x: origin.x + width / 2,
      y: origin.y + depth / 2,
      z: origin.z
    )
    let plane = SketchPlane.plane(Plane3D(origin: bottomCenter, normal: .unitZ))
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { _ in
          try ContextResolvedEditorCommand(
            validating: .createExtrudedRectangle(
              name: name,
              plane: plane,
              width: .length(width, .meter),
              height: .length(depth, .meter),
              depth: .length(height, .meter),
              direction: .normal
            ))
        }
      ))
  }
}
