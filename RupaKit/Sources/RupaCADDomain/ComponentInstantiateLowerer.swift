import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct ComponentInstantiateLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.componentInstantiate,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "definition", type: .componentDefinition),
      .init(id: "transform", type: .transform),
    ],
    outputs: [
      .init(
        id: "instance",
        type: .componentInstance,
        selector: .componentInstance(index: 0)
      ),
      .init(id: "scene", type: .sceneNode, selector: .sceneNode(index: 0)),
    ],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 2,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  )

  static let registration = SemanticOperationRegistration(
    descriptor: descriptor,
    lowerer: ComponentInstantiateLowerer()
  )

  let operationID = RupaCADSemanticOperationID.componentInstantiate
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let definitionSlot = try CADSemanticLoweringSupport.preparedSlot(
      "definition",
      in: request
    )
    let transform = try CADSemanticLoweringSupport.coreTransform(
      CADSemanticLoweringSupport.transform("transform", in: request)
    )
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { inputs in
          let definitionID: ComponentDefinitionID
          do {
            definitionID = try inputs.componentDefinitionID(for: definitionSlot)
          } catch {
            throw RupaCADDomainError(
              code: RupaCADDomainError.invalidReferenceCode,
              message: "Component definition could not be resolved."
            )
          }
          return try ContextResolvedEditorCommand(
            validating: .createComponentInstance(
              name: name,
              definitionID: definitionID,
              localTransform: transform
            ))
        }
      ))
  }
}
