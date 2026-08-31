import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct SketchRectangleLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.sketchRectangle,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "plane", type: .plane),
      .init(id: "center", type: .point),
      .init(id: "width", type: .number(unit: .meter)),
      .init(id: "height", type: .number(unit: .meter)),
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
    lowerer: SketchRectangleLowerer()
  )

  let operationID = RupaCADSemanticOperationID.sketchRectangle
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let plane = try CADSemanticLoweringSupport.corePlane(
      CADSemanticLoweringSupport.plane("plane", in: request)
    )
    let center = try CADSemanticLoweringSupport.sketchCoordinates(
      CADSemanticLoweringSupport.point("center", in: request),
      on: plane,
      owner: "Rectangle center"
    )
    let width = try CADSemanticLoweringSupport.positiveLength("width", in: request)
    let height = try CADSemanticLoweringSupport.positiveLength("height", in: request)
    let halfWidth = width / 2
    let halfHeight = height / 2
    let bottomLeft = SketchPoint(
      x: .length(center.x - halfWidth, .meter),
      y: .length(center.y - halfHeight, .meter)
    )
    let bottomRight = SketchPoint(
      x: .length(center.x + halfWidth, .meter),
      y: .length(center.y - halfHeight, .meter)
    )
    let topRight = SketchPoint(
      x: .length(center.x + halfWidth, .meter),
      y: .length(center.y + halfHeight, .meter)
    )
    let topLeft = SketchPoint(
      x: .length(center.x - halfWidth, .meter),
      y: .length(center.y + halfHeight, .meter)
    )
    let plan = SketchCreationPlan(
      plane: plane,
      entities: [
        .line(start: bottomLeft, end: bottomRight),
        .line(start: bottomRight, end: topRight),
        .line(start: topRight, end: topLeft),
        .line(start: topLeft, end: bottomLeft),
      ],
      constraints: []
    )
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { _ in
          try ContextResolvedEditorCommand(
            validating: .createSemanticSketch(
              name: name,
              plan: plan,
              geometryRole: .sketchProfile
            ))
        }
      ))
  }
}
