import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct SolidExtrudeLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.solidExtrude,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "profile", type: .feature),
      .init(id: "distance", type: .number(unit: .meter)),
      .init(id: "direction", type: .direction),
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
    lowerer: SolidExtrudeLowerer()
  )

  let operationID = RupaCADSemanticOperationID.solidExtrude
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let profileSlot = try CADSemanticLoweringSupport.preparedSlot("profile", in: request)
    let distance = try CADSemanticLoweringSupport.nonzeroLength("distance", in: request)
    let direction = try CADSemanticLoweringSupport.normalizedVector(
      CADSemanticLoweringSupport.direction("direction", in: request)
    )
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { inputs in
          let profileID: FeatureID
          do {
            profileID = try inputs.featureID(for: profileSlot)
          } catch {
            throw RupaCADDomainError(
              code: RupaCADDomainError.invalidReferenceCode,
              message: "Extrude profile could not be resolved."
            )
          }
          return try ContextResolvedEditorCommand(
            validating: .extrudeProfile(
              name: name,
              profile: ProfileReference(featureID: profileID),
              distance: .length(distance, .meter),
              direction: .vector(direction)
            ))
        }
      ))
  }
}
