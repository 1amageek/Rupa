import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct ComponentDefineLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.componentDefine,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "rootScenes", type: .array(element: .sceneNode)),
    ],
    outputs: [
      .init(
        id: "definition",
        type: .componentDefinition,
        selector: .componentDefinition(index: 0)
      )
    ],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 1,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  )

  static let registration = SemanticOperationRegistration(
    descriptor: descriptor,
    lowerer: ComponentDefineLowerer()
  )

  let operationID = RupaCADSemanticOperationID.componentDefine
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let rootArguments = try CADSemanticLoweringSupport.array("rootScenes", in: request)
    guard !rootArguments.isEmpty else {
      throw CADSemanticLoweringSupport.invalidArgument(
        "Component definitions require at least one root scene."
      )
    }
    let rootSlots = try rootArguments.enumerated().map { index, argument in
      try CADSemanticLoweringSupport.preparedSlot(
        argument,
        owner: "rootScenes[\(index)]"
      )
    }
    guard Set(rootSlots).count == rootSlots.count else {
      throw CADSemanticLoweringSupport.invalidArgument(
        "Component root scenes must be unique."
      )
    }
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { inputs in
          do {
            let roots = try rootSlots.map { try inputs.sceneNodeID(for: $0) }
            return try ContextResolvedEditorCommand(
              validating: .createComponentDefinition(
                name: name,
                rootSceneNodeIDs: roots
              ))
          } catch let error as RupaCADDomainError {
            throw error
          } catch {
            throw RupaCADDomainError(
              code: RupaCADDomainError.invalidReferenceCode,
              message: "A component root scene could not be resolved."
            )
          }
        }
      ))
  }
}
