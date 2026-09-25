import RupaAutomation
import RupaCore
import RupaDomainFoundation

// FIXME(INCOMPLETE_IMPLEMENTATION): Semantic Loft supports curve intervals but not profile trims.
// Registry invocation reaches Core createLoft/setLoft; profile trim and
// G1/G2 controls must be implemented before claiming the full Loft contract.
struct LoftLowerer: SemanticOperationLowerer {
  enum Variant: Sendable {
    case solid, sheet, replaceSolid, replaceSheet

    var operationID: DomainCapabilityID {
      switch self {
      case .solid: RupaCADSemanticOperationID.solidLoft
      case .sheet: RupaCADSemanticOperationID.surfaceLoft
      case .replaceSolid: RupaCADSemanticOperationID.solidLoftReplace
      case .replaceSheet: RupaCADSemanticOperationID.surfaceLoftReplace
      }
    }

    var resultKind: LoftResultKind { self == .solid || self == .replaceSolid ? .solid : .sheet }
    var replacesSource: Bool { self == .replaceSolid || self == .replaceSheet }
  }

  let variant: Variant
  var operationID: DomainCapabilityID { variant.operationID }
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  static func registration(_ variant: Variant) -> SemanticOperationRegistration {
    let lowerer = LoftLowerer(variant: variant)
    return SemanticOperationRegistration(descriptor: lowerer.descriptor, lowerer: lowerer)
  }

  var descriptor: SemanticOperationDescriptor { SemanticOperationDescriptor(
    operationID: operationID, version: operationVersion,
    inputs: [variant.replacesSource
      ? .init(id: "body", type: .sourceBody(role: variant.resultKind == .solid ? .body : .sheet))
      : .init(id: "name", type: .text),
      .init(id: "sections", type: .array(element: .object)),
      .init(id: "guides", type: .array(element: .feature)),
      .init(id: "surfaceMode", type: .text),
      .init(id: "tangentScale", type: .number(unit: .unitless)),
      .init(id: "closed", type: .boolean)],
    outputs: variant.replacesSource ? [] : [.init(id: "body", type: .sourceBody(role: variant.resultKind == .solid ? .body : .sheet),
      selector: .sourceBody(role: variant.resultKind == .solid ? .body : .sheet, index: 0)),
      .init(id: "scene", type: .sceneNode, selector: .sceneNode(index: 0))],
    route: .source, effect: .sourceMutation,
    estimatedExpandedSourceWork: variant.replacesSource ? 0 : 3, resultEstimate: resultEstimate
  ) }

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let target = variant.replacesSource ? try CADSemanticLoweringSupport.preparedSlot("body", in: request) : nil
    let name = variant.replacesSource ? nil : try CADSemanticLoweringSupport.text("name", in: request)
    var references: Set<SemanticArgument> = []
    let sections = try CADSemanticLoweringSupport.array("sections", in: request).enumerated().map { index, argument in
      let owner = "sections[\(index)]"
      let fields = try CADSemanticLoweringSupport.object(argument, owner: owner)
      guard Set(fields.keys).isSubset(of: ["kind", "source", "tangentScale", "tangentMode", "parameterRange", "reversed", "profileDirection", "profileIndex", "startSampleIndex"]),
        fields["kind"] != nil, fields["source"] != nil else {
        throw CADSemanticLoweringSupport.invalidArgument("\(owner) requires kind and source; optional fields are tangentScale, tangentMode, parameterRange, reversed, profileDirection, profileIndex and startSampleIndex.")
      }
      let kind = try CADSemanticLoweringSupport.literalText("kind", in: fields, owner: owner)
      guard kind == "profile" || (kind == "curve" && variant.resultKind == .sheet), let source = fields["source"] else {
        throw CADSemanticLoweringSupport.invalidArgument("Loft section kind must be profile, or curve for Sheet output.")
      }
      let tangentScale: Double?
      let profileIndex: Int
      if let argument = fields["profileIndex"] {
        guard kind == "profile", case .value(.number(let value, unit: .unitless)) = argument,
          let index = Int(exactly: value), index >= 0 else {
          throw CADSemanticLoweringSupport.invalidArgument("\(owner).profileIndex requires a profile and a nonnegative unitless integer in range.")
        }
        profileIndex = index
      } else {
        profileIndex = 0
      }
      let startSampleIndex: Int?
      if let argument = fields["startSampleIndex"] {
        guard case .value(.number(let value, unit: .unitless)) = argument,
          let index = Int(exactly: value), index >= 0 else {
          throw CADSemanticLoweringSupport.invalidArgument("\(owner).startSampleIndex must be a nonnegative unitless integer in range.")
        }
        startSampleIndex = index
      } else {
        startSampleIndex = nil
      }
      let profileDirection: LoftProfileDirection
      if fields["profileDirection"] != nil {
        let value = try CADSemanticLoweringSupport.literalText("profileDirection", in: fields, owner: owner)
        guard kind == "profile", let direction = LoftProfileDirection(rawValue: value) else {
          throw CADSemanticLoweringSupport.invalidArgument("\(owner).profileDirection requires a profile and automatic, forward or reversed.")
        }
        profileDirection = direction
      } else {
        profileDirection = .automatic
      }
      let reversed: Bool
      if let argument = fields["reversed"] {
        guard kind == "curve", case .value(.boolean(let value)) = argument else {
          throw CADSemanticLoweringSupport.invalidArgument("\(owner).reversed must be a boolean for a curve section.")
        }
        reversed = value
      } else {
        reversed = false
      }
      let domain: ParameterDomain?
      if let argument = fields["parameterRange"] {
        let values: [SemanticResolvedArgument]
        switch argument {
        case .array(let elements): values = elements
        case .value(.array(let elements)): values = elements.map(SemanticResolvedArgument.value)
        default: throw CADSemanticLoweringSupport.invalidArgument("\(owner).parameterRange must be an array.")
        }
        guard kind == "curve", values.count == 2,
          case .value(.number(let lower, unit: .unitless)) = values[0],
          case .value(.number(let upper, unit: .unitless)) = values[1],
          lower.isFinite, upper.isFinite, lower < upper else {
          throw CADSemanticLoweringSupport.invalidArgument("\(owner).parameterRange requires two increasing finite native curve parameters.")
        }
        domain = .closed(lower, upper)
      } else {
        domain = nil
      }
      if let argument = fields["tangentScale"] {
        guard case .value(.number(let value, unit: .unitless)) = argument,
          value.isFinite, value > 0 else {
          throw CADSemanticLoweringSupport.invalidArgument("\(owner).tangentScale must be a finite positive unitless number.")
        }
        tangentScale = value
      } else {
        tangentScale = nil
      }
      let tangentMode: LoftSectionSmoothTangentMode
      if fields["tangentMode"] != nil {
        let value = try CADSemanticLoweringSupport.literalText("tangentMode", in: fields, owner: owner)
        guard let mode = LoftSectionSmoothTangentMode(rawValue: value) else {
          throw CADSemanticLoweringSupport.invalidArgument("\(owner).tangentMode must be automatic or zero.")
        }
        tangentMode = mode
      } else {
        tangentMode = .automatic
      }
      return (slot: try slot(source, owner: owner, references: &references), isCurve: kind == "curve",
        tangentScale: tangentScale, tangentMode: tangentMode, domain: domain, reversed: reversed, profileDirection: profileDirection,
        startSampleIndex: startSampleIndex, profileIndex: profileIndex)
    }
    let guides = try CADSemanticLoweringSupport.array("guides", in: request).enumerated().map { index, argument in
      try slot(argument, owner: "guides[\(index)]", references: &references)
    }
    guard case .value(.boolean(let closed)) = try CADSemanticLoweringSupport.input("closed", in: request),
      let mode = LoftSurfaceMode(rawValue: try CADSemanticLoweringSupport.text("surfaceMode", in: request)) else {
      throw CADSemanticLoweringSupport.invalidArgument("Loft requires a boolean closed flag and ruled or smooth surface mode.")
    }
    let scale = try CADSemanticLoweringSupport.number("tangentScale", unit: .unitless, in: request)
    guard sections.count >= (closed ? 3 : 2), scale > 0,
      !closed || variant.resultKind == .sheet else {
      throw CADSemanticLoweringSupport.invalidArgument("Loft requires distinct ordered sections and guides, positive tension and valid Sheet closure.")
    }
    let options = LoftOptions(resultKind: variant.resultKind, closesSectionLoop: closed,
      surfaceMode: mode, smoothTangentScale: scale)
    return SemanticLoweredOperation(step: PreparedAutomationStep(
      inputs: request.preparedInputs, outputs: request.preparedOutputs,
      estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
      commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { inputs in
        let references: [LoftSectionReference]
        let guideReferences: [LoftGuideReference]
        do {
          references = try sections.map { section in
            let id = try inputs.featureID(for: section.slot)
            return LoftSectionReference(section: section.isCurve
              ? .curve(CurveSectionReference(featureID: id, parameterDomain: section.domain, isReversed: section.reversed))
              : .profile(ProfileReference(featureID: id, profileIndex: section.profileIndex)),
              profileDirection: section.profileDirection,
              startSampleIndex: section.startSampleIndex,
              smoothTangentScale: section.tangentScale, smoothTangentMode: section.tangentMode)
          }
          guideReferences = try guides.map { LoftGuideReference(featureID: try inputs.featureID(for: $0)) }
        } catch {
          throw RupaCADDomainError(code: RupaCADDomainError.invalidReferenceCode,
            message: "A Loft section or guide could not be resolved.")
        }
        if let target {
          let body = try inputs.sourceBody(for: target)
          guard body.role == (variant.resultKind == .solid ? .body : .sheet) else {
            throw CADSemanticLoweringSupport.invalidArgument("Loft replacement must preserve its output role.")
          }
          return try ContextResolvedEditorCommand(validating: .setLoft(featureID: body.featureID,
            loft: LoftFeature(sections: references, guides: guideReferences, options: options)))
        }
        guard let name else {
          throw CADSemanticLoweringSupport.invalidArgument("Loft creation requires a name.")
        }
        return try ContextResolvedEditorCommand(validating: .createLoft(
          name: name, sections: references, guides: guideReferences, options: options))
      }))
  }

  private func slot(_ argument: SemanticResolvedArgument, owner: String,
    references: inout Set<SemanticArgument>
  ) throws -> PreparedAutomationSlotID {
      guard argument.type == .feature else {
        throw CADSemanticLoweringSupport.invalidArgument("\(owner) must reference a feature.")
      }
      let reference: SemanticArgument
      switch argument {
      case .source(let source, _): reference = .existing(source)
      case .local(let local, _): reference = .local(local)
      default: throw CADSemanticLoweringSupport.invalidArgument("Loft inputs must be feature references.")
      }
      guard references.insert(reference).inserted else {
        throw CADSemanticLoweringSupport.invalidArgument("Loft sections and guides must be distinct.")
      }
      return try CADSemanticLoweringSupport.preparedSlot(argument, owner: owner)
  }
}
