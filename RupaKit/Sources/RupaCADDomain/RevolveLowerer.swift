import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct RevolveLowerer: SemanticOperationLowerer {
  enum Variant: Sendable {
    case solidProfile, sheetProfile, sheetCurve

    var operationID: DomainCapabilityID {
      switch self {
      case .solidProfile: RupaCADSemanticOperationID.solidRevolve
      case .sheetProfile: RupaCADSemanticOperationID.surfaceRevolve
      case .sheetCurve: RupaCADSemanticOperationID.surfaceRevolveCurve
      }
    }

    var inputID: String { self == .sheetCurve ? "curve" : "profile" }
    var resultKind: BodyKind { self == .solidProfile ? .solid : .sheet }
  }

  let variant: Variant
  var operationID: DomainCapabilityID { variant.operationID }
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  static func registration(_ variant: Variant) -> SemanticOperationRegistration {
    let lowerer = RevolveLowerer(variant: variant)
    return SemanticOperationRegistration(descriptor: lowerer.descriptor, lowerer: lowerer)
  }

  var descriptor: SemanticOperationDescriptor { SemanticOperationDescriptor(
    operationID: operationID,
    version: operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: variant.inputID, type: .feature),
      .init(id: "axisOrigin", type: .point),
      .init(id: "axisDirection", type: .direction),
      .init(id: "angle", type: .number(unit: .degree)),
    ],
    outputs: [
      .init(id: "body", type: .sourceBody(role: variant.resultKind == .solid ? .body : .sheet),
        selector: .sourceBody(role: variant.resultKind == .solid ? .body : .sheet, index: 0)),
      .init(id: "scene", type: .sceneNode, selector: .sceneNode(index: 0)),
    ],
    route: .source, effect: .sourceMutation,
    estimatedExpandedSourceWork: 3, resultEstimate: resultEstimate
  ) }

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let sectionSlot = try CADSemanticLoweringSupport.preparedSlot(variant.inputID, in: request)
    let origin = try CADSemanticLoweringSupport.corePoint(
      CADSemanticLoweringSupport.point("axisOrigin", in: request))
    let direction = try CADSemanticLoweringSupport.normalizedVector(
      CADSemanticLoweringSupport.direction("axisDirection", in: request))
    let angle = try CADSemanticLoweringSupport.angle("angle", in: request)
    guard angle.value != 0, abs(angle.value) <= 360 else {
      throw CADSemanticLoweringSupport.degenerateGeometry(
        "Revolve angle must be nonzero and no greater than one turn.")
    }
    return SemanticLoweredOperation(step: PreparedAutomationStep(
      inputs: request.preparedInputs, outputs: request.preparedOutputs,
      estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
      commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { inputs in
        let sectionID: FeatureID
        do {
          sectionID = try inputs.featureID(for: sectionSlot)
        } catch {
          throw RupaCADDomainError(code: RupaCADDomainError.invalidReferenceCode,
            message: "Revolve section could not be resolved.")
        }
        return try ContextResolvedEditorCommand(validating: .revolveSection(
          name: name,
          section: variant == .sheetCurve
            ? .curve(CurveSectionReference(featureID: sectionID))
            : .profile(ProfileReference(featureID: sectionID)),
          axis: RevolveAxis(origin: origin, direction: direction),
          angle: .angle(angle.value, .degree), resultKind: variant.resultKind))
      }))
  }
}
