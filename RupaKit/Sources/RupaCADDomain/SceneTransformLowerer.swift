import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct SceneTransformLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.sceneTransform,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "scene", type: .sceneNode),
      .init(id: "translation", type: .point),
      .init(id: "axisPoint", type: .point),
      .init(id: "rotationAxis", type: .direction),
      .init(id: "rotation", type: .number(unit: .degree)),
    ],
    outputs: [],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 0,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  )

  static let registration = SemanticOperationRegistration(
    descriptor: descriptor,
    lowerer: SceneTransformLowerer()
  )

  let operationID = RupaCADSemanticOperationID.sceneTransform
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let sceneSlot = try CADSemanticLoweringSupport.preparedSlot("scene", in: request)
    let transform = try CADSemanticLoweringSupport.coreTransform(
      translation: CADSemanticLoweringSupport.point("translation", in: request),
      axisPoint: CADSemanticLoweringSupport.point("axisPoint", in: request),
      rotationAxis: CADSemanticLoweringSupport.direction("rotationAxis", in: request),
      rotation: CADSemanticLoweringSupport.angle("rotation", in: request)
    )
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { inputs in
          let sceneNodeID: SceneNodeID
          do {
            sceneNodeID = try inputs.sceneNodeID(for: sceneSlot)
          } catch {
            throw RupaCADDomainError(
              code: RupaCADDomainError.invalidReferenceCode,
              message: "Scene transform target could not be resolved."
            )
          }
          return try ContextResolvedEditorCommand(
            validating: .setSceneNodeTransform(
              id: sceneNodeID,
              localTransform: transform
            ))
        }
      ))
  }
}
