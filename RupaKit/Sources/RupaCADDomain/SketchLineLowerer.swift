import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct SketchLineLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.sketchLine,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "plane", type: .plane),
      .init(id: "start", type: .point),
      .init(id: "end", type: .point),
    ],
    outputs: [
      .init(id: "curve", type: .feature, selector: .feature(index: 0)),
      .init(id: "scene", type: .sceneNode, selector: .sceneNode(index: 0)),
    ],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 2,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  )

  static let registration = SemanticOperationRegistration(
    descriptor: descriptor,
    lowerer: SketchLineLowerer()
  )

  let operationID = RupaCADSemanticOperationID.sketchLine
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let semanticPlane = try CADSemanticLoweringSupport.plane("plane", in: request)
    let plane = try CADSemanticLoweringSupport.canonicalAxisPlane(semanticPlane)
    let start = try CADSemanticLoweringSupport.sketchPoint(
      CADSemanticLoweringSupport.point("start", in: request),
      on: plane,
      owner: "Line start"
    )
    let end = try CADSemanticLoweringSupport.sketchPoint(
      CADSemanticLoweringSupport.point("end", in: request),
      on: plane,
      owner: "Line end"
    )
    guard start != end else {
      throw CADSemanticLoweringSupport.degenerateGeometry(
        "Line start and end must be distinct."
      )
    }
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { _ in
          try ContextResolvedEditorCommand(
            validating: .createLineSketch(
              name: name,
              plane: plane,
              start: start,
              end: end
            ))
        }
      ))
  }
}
