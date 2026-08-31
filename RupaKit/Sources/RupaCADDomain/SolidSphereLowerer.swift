import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct SolidSphereLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.solidSphere,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "center", type: .point),
      .init(id: "radius", type: .number(unit: .meter)),
    ],
    outputs: [
      .init(
        id: "body",
        type: .sourceBody(role: .body),
        selector: .sourceBody(role: .body, index: 0)
      ),
      .init(id: "scene", type: .sceneNode, selector: .sceneNode(index: 0)),
    ],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 3,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  )

  static let registration = SemanticOperationRegistration(
    descriptor: descriptor,
    lowerer: SolidSphereLowerer()
  )

  let operationID = RupaCADSemanticOperationID.solidSphere
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let center = CADSemanticLoweringSupport.corePoint(
      try CADSemanticLoweringSupport.point("center", in: request)
    )
    let radius = try CADSemanticLoweringSupport.positiveLength("radius", in: request)
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { _ in
          try ContextResolvedEditorCommand(
            validating: .createAnalyticSphere(
              name: name,
              center: center,
              radius: radius
            ))
        }
      ))
  }
}
