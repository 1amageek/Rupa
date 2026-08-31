import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct SketchCircleLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.sketchCircle,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "plane", type: .plane),
      .init(id: "center", type: .point),
      .init(id: "radius", type: .number(unit: .meter)),
    ],
    outputs: [
      .init(id: "profile", type: .feature, selector: .feature(index: 0)),
      .init(id: "scene", type: .sceneNode, selector: .sceneNode(index: 0)),
    ],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 2,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  )

  static let registration = SemanticOperationRegistration(
    descriptor: descriptor,
    lowerer: SketchCircleLowerer()
  )

  let operationID = RupaCADSemanticOperationID.sketchCircle
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let plane = try CADSemanticLoweringSupport.corePlane(
      CADSemanticLoweringSupport.plane("plane", in: request)
    )
    let center = try CADSemanticLoweringSupport.sketchPoint(
      CADSemanticLoweringSupport.point("center", in: request),
      on: plane,
      owner: "Circle center"
    )
    let radius = try CADSemanticLoweringSupport.positiveLength("radius", in: request)
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { _ in
          try ContextResolvedEditorCommand(
            validating: .createCircleSketch(
              name: name,
              plane: plane,
              center: center,
              radius: .length(radius, .meter)
            ))
        }
      ))
  }
}
