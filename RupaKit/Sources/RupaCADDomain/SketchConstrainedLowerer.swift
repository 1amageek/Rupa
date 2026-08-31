import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct SketchConstrainedLowerer: SemanticOperationLowerer {
  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.sketchConstrained,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "plane", type: .plane),
      .init(id: "entities", type: .array(element: .object)),
      .init(id: "relations", type: .array(element: .object)),
    ],
    outputs: [
      .init(id: "sketch", type: .feature, selector: .feature(index: 0)),
      .init(id: "scene", type: .sceneNode, selector: .sceneNode(index: 0)),
    ],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 2,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  )

  static let registration = SemanticOperationRegistration(
    descriptor: descriptor,
    lowerer: SketchConstrainedLowerer()
  )

  let operationID = RupaCADSemanticOperationID.sketchConstrained
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let plane = try CADSemanticLoweringSupport.canonicalAxisPlane(
      CADSemanticLoweringSupport.plane("plane", in: request)
    )
    let entities = try parseEntities(
      CADSemanticLoweringSupport.array("entities", in: request),
      plane: plane
    )
    guard !entities.isEmpty else {
      throw CADSemanticLoweringSupport.invalidArgument(
        "Constrained sketches require at least one entity."
      )
    }
    let constraints = try parseConstraints(
      CADSemanticLoweringSupport.array("relations", in: request)
    )
    let plan = SketchCreationPlan(
      plane: plane,
      entities: entities,
      constraints: constraints
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
              geometryRole: .curve
            ))
        }
      ))
  }

  private func parseEntities(
    _ values: [SemanticResolvedArgument],
    plane: SketchPlane
  ) throws -> [SketchCreationEntity] {
    try values.enumerated().map { index, value in
      let owner = "entities[\(index)]"
      let object = try CADSemanticLoweringSupport.object(value, owner: owner)
      let kind = try CADSemanticLoweringSupport.literalText(
        "kind",
        in: object,
        owner: owner
      )
      switch kind {
      case "line":
        try CADSemanticLoweringSupport.exactKeys(
          object,
          expected: ["kind", "start", "end"],
          owner: owner
        )
        let start = try CADSemanticLoweringSupport.sketchPoint(
          CADSemanticLoweringSupport.literalPoint("start", in: object, owner: owner),
          on: plane,
          owner: "\(owner).start"
        )
        let end = try CADSemanticLoweringSupport.sketchPoint(
          CADSemanticLoweringSupport.literalPoint("end", in: object, owner: owner),
          on: plane,
          owner: "\(owner).end"
        )
        guard start != end else {
          throw CADSemanticLoweringSupport.degenerateGeometry(
            "\(owner) line endpoints must be distinct."
          )
        }
        return .line(start: start, end: end)
      case "circle":
        try CADSemanticLoweringSupport.exactKeys(
          object,
          expected: ["kind", "center", "radius"],
          owner: owner
        )
        let center = try CADSemanticLoweringSupport.sketchPoint(
          CADSemanticLoweringSupport.literalPoint("center", in: object, owner: owner),
          on: plane,
          owner: "\(owner).center"
        )
        let radius = try CADSemanticLoweringSupport.literalLength(
          "radius",
          in: object,
          owner: owner
        )
        guard radius > 0 else {
          throw CADSemanticLoweringSupport.degenerateGeometry(
            "\(owner).radius must be greater than zero."
          )
        }
        return .circle(center: center, radius: .length(radius, .meter))
      default:
        throw RupaCADDomainError(
          code: RupaCADDomainError.unsupportedValueCode,
          message: "\(owner).kind is unsupported."
        )
      }
    }
  }

  private func parseConstraints(
    _ values: [SemanticResolvedArgument]
  ) throws -> [SketchCreationConstraint] {
    try values.enumerated().map { index, value in
      let owner = "relations[\(index)]"
      let object = try CADSemanticLoweringSupport.object(value, owner: owner)
      let kind = try CADSemanticLoweringSupport.literalText(
        "kind",
        in: object,
        owner: owner
      )
      switch kind {
      case "coincident":
        try CADSemanticLoweringSupport.exactKeys(
          object,
          expected: [
            "kind", "firstEntity", "firstEndpoint",
            "secondEntity", "secondEndpoint",
          ],
          owner: owner
        )
        return .coincident(
          try endpointReference(prefix: "first", in: object, owner: owner),
          try endpointReference(prefix: "second", in: object, owner: owner)
        )
      case "parallel", "perpendicular", "equalLength", "concentric", "equalRadius":
        try CADSemanticLoweringSupport.exactKeys(
          object,
          expected: ["kind", "firstEntity", "secondEntity"],
          owner: owner
        )
        let first = try CADSemanticLoweringSupport.literalInteger(
          "firstEntity",
          in: object,
          owner: owner
        )
        let second = try CADSemanticLoweringSupport.literalInteger(
          "secondEntity",
          in: object,
          owner: owner
        )
        switch kind {
        case "parallel": return .parallel(first, second)
        case "perpendicular": return .perpendicular(first, second)
        case "equalLength": return .equalLength(first, second)
        case "concentric": return .concentric(first, second)
        default: return .equalRadius(first, second)
        }
      case "horizontal", "vertical":
        try CADSemanticLoweringSupport.exactKeys(
          object,
          expected: ["kind", "entity"],
          owner: owner
        )
        let entity = try CADSemanticLoweringSupport.literalInteger(
          "entity",
          in: object,
          owner: owner
        )
        return kind == "horizontal" ? .horizontal(entity) : .vertical(entity)
      default:
        throw RupaCADDomainError(
          code: RupaCADDomainError.unsupportedValueCode,
          message: "\(owner).kind is unsupported."
        )
      }
    }
  }

  private func endpointReference(
    prefix: String,
    in values: [String: SemanticResolvedArgument],
    owner: String
  ) throws -> SketchCreationEndpointReference {
    let entityIndex = try CADSemanticLoweringSupport.literalInteger(
      "\(prefix)Entity",
      in: values,
      owner: owner
    )
    let endpointValue = try CADSemanticLoweringSupport.literalText(
      "\(prefix)Endpoint",
      in: values,
      owner: owner
    )
    guard let endpoint = SketchCreationLineEndpoint(rawValue: endpointValue) else {
      throw RupaCADDomainError(
        code: RupaCADDomainError.unsupportedValueCode,
        message: "\(owner).\(prefix)Endpoint must be 'start' or 'end'."
      )
    }
    return SketchCreationEndpointReference(
      entityIndex: entityIndex,
      endpoint: endpoint
    )
  }
}
