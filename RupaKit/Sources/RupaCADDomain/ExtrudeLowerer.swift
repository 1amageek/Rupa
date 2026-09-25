import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct ExtrudeLowerer: SemanticOperationLowerer {
  enum Variant: Sendable {
    case solidProfile, sheetProfile, sheetCurve

    var operationID: DomainCapabilityID {
      switch self {
      case .solidProfile: RupaCADSemanticOperationID.solidExtrude
      case .sheetProfile: RupaCADSemanticOperationID.surfaceExtrude
      case .sheetCurve: RupaCADSemanticOperationID.surfaceExtrudeCurve
      }
    }

    var inputID: String { self == .sheetCurve ? "curve" : "profile" }
    var resultKind: ExtrudeResultKind { self == .solidProfile ? .solid : .sheet }
  }

  let variant: Variant

  static func registration(_ variant: Variant) -> SemanticOperationRegistration {
    let lowerer = ExtrudeLowerer(variant: variant)
    return SemanticOperationRegistration(descriptor: lowerer.descriptor, lowerer: lowerer)
  }

  var descriptor: SemanticOperationDescriptor { SemanticOperationDescriptor(
    operationID: operationID,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: variant.inputID, type: .feature),
      .init(id: "distance", type: .number(unit: .meter)),
      .init(id: "start_distance", type: .number(unit: .meter), isRequired: false),
      .init(id: "direction", type: .direction),
    ],
    outputs: [
      .init(
        id: "body",
        type: .sourceBody(role: variant.resultKind == .solid ? .body : .sheet),
        selector: .sourceBody(role: variant.resultKind == .solid ? .body : .sheet, index: 0)
      ),
      .init(id: "scene", type: .sceneNode, selector: .sceneNode(index: 0)),
    ],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 3,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  ) }

  var operationID: DomainCapabilityID { variant.operationID }
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let sectionSlot = try CADSemanticLoweringSupport.preparedSlot(variant.inputID, in: request)
    let distance = try CADSemanticLoweringSupport.number("distance", unit: .meter, in: request)
    let startDistance: Double? = request.arguments[SemanticArgumentID("start_distance")] == nil ? nil
      : try CADSemanticLoweringSupport.number("start_distance", unit: .meter, in: request)
    guard distance != (startDistance ?? 0) else {
      throw CADSemanticLoweringSupport.degenerateGeometry("Extrude endpoints must be distinct.")
    }
    let direction = try CADSemanticLoweringSupport.normalizedVector(
      CADSemanticLoweringSupport.direction("direction", in: request)
    )
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { inputs in
          let sectionID: FeatureID
          do {
            sectionID = try inputs.featureID(for: sectionSlot)
          } catch {
            throw RupaCADDomainError(
              code: RupaCADDomainError.invalidReferenceCode,
              message: "Extrude section could not be resolved."
            )
          }
          return try ContextResolvedEditorCommand(
            validating: .extrudeSection(
              name: name,
              section: variant == .sheetCurve
                ? .curve(CurveSectionReference(featureID: sectionID))
                : .profile(ProfileReference(featureID: sectionID)),
              distance: .length(distance, .meter),
              startDistance: startDistance.map { .length($0, .meter) },
              direction: .vector(direction),
              resultKind: variant.resultKind
            ))
        }
      ))
  }
}
