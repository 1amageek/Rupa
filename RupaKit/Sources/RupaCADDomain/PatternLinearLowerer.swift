import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct PatternLinearLowerer: SemanticOperationLowerer {
  static let maximumCount = PatternArrayGenerationBudget.standard.maximumOutputInstanceCount

  static let descriptor = SemanticOperationDescriptor(
    operationID: RupaCADSemanticOperationID.patternLinear,
    version: RupaCADDomain.operationVersion,
    inputs: [
      .init(id: "name", type: .text),
      .init(id: "definition", type: .componentDefinition),
      .init(id: "direction", type: .direction),
      .init(id: "distance", type: .number(unit: .meter)),
      .init(id: "count", type: .integer),
    ],
    outputs: [
      .init(
        id: "pattern",
        type: .patternArraySource,
        selector: .patternArraySource(index: 0)
      ),
      .init(id: "rootScene", type: .sceneNode, selector: .sceneNode(index: 0)),
    ],
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: 5,
    resultEstimate: CADSemanticLoweringSupport.resultEstimate
  )

  static let registration = SemanticOperationRegistration(
    descriptor: descriptor,
    lowerer: PatternLinearLowerer()
  )

  let operationID = RupaCADSemanticOperationID.patternLinear
  let operationVersion = RupaCADDomain.operationVersion
  let resultEstimate = CADSemanticLoweringSupport.resultEstimate

  func estimateGeneratedSourceWork(
    for request: SemanticLoweringRequest
  ) throws -> UInt64 {
    try generatedWork(count: validatedCount(in: request))
  }

  private func generatedWork(count: Int) throws -> UInt64 {
    let unsignedCount = UInt64(count)
    let (doubled, multiplyOverflow) = unsignedCount.multipliedReportingOverflow(by: 2)
    let (work, additionOverflow) = doubled.addingReportingOverflow(3)
    guard !multiplyOverflow, !additionOverflow else {
      throw CADSemanticLoweringSupport.invalidArgument(
        "Pattern generated-source work overflowed."
      )
    }
    return work
  }

  func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
    let name = try CADSemanticLoweringSupport.text("name", in: request)
    let definitionSlot = try CADSemanticLoweringSupport.preparedSlot(
      "definition",
      in: request
    )
    let direction = try CADSemanticLoweringSupport.normalizedVector(
      CADSemanticLoweringSupport.direction("direction", in: request)
    )
    let distance = try CADSemanticLoweringSupport.number(
      "distance",
      unit: .meter,
      in: request
    )
    guard distance >= 0 else {
      throw CADSemanticLoweringSupport.invalidArgument(
        "Pattern distance must be nonnegative."
      )
    }
    let count = try validatedCount(in: request)
    let work = try generatedWork(count: count)
    return SemanticLoweredOperation(
      step: PreparedAutomationStep(
        inputs: request.preparedInputs,
        outputs: request.preparedOutputs,
        estimatedGeneratedSourceWork: work,
        commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { inputs in
          let definitionID: ComponentDefinitionID
          do {
            definitionID = try inputs.componentDefinitionID(for: definitionSlot)
          } catch {
            throw RupaCADDomainError(
              code: RupaCADDomainError.invalidReferenceCode,
              message: "Pattern component definition could not be resolved."
            )
          }
          return try ContextResolvedEditorCommand(
            validating: .createPatternArray(
              name: name,
              definitionID: definitionID,
              distribution: .rectangular(
                RectangularPatternArray(
                  firstAxis: PatternArrayLinearAxis(
                    direction: direction,
                    distance: .length(distance, .meter),
                    copyCount: count,
                    distanceMode: .spacing
                  )
                )),
              outputMode: .componentInstance
            ))
        }
      ))
  }

  private func validatedCount(in request: SemanticLoweringRequest) throws -> Int {
    let count = try CADSemanticLoweringSupport.integer("count", in: request)
    guard count > 0 else {
      throw CADSemanticLoweringSupport.degenerateGeometry(
        "Pattern count must be greater than zero."
      )
    }
    guard count <= Self.maximumCount else {
      throw CADSemanticLoweringSupport.invalidArgument(
        "Pattern count exceeds the supported maximum of \(Self.maximumCount)."
      )
    }
    return count
  }
}
