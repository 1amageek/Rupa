import RupaCore
import RupaDomainFoundation
import Testing

@testable import RupaAutomation
@testable import RupaCADDomain

@Test(.timeLimit(.minutes(1)))
func registryContainsExactlyTwentyOneVersionOneCADOperations() throws {
  let registrations = RupaCADDomain.registrations()
  let expectedIDs = Set(RupaCADSemanticOperationID.all)

  #expect(registrations.count == 21)
  #expect(Set(registrations.map(\.descriptor.operationID)) == expectedIDs)
  #expect(Set(registrations.map(\.descriptor.version)) == [RupaCADDomain.operationVersion])
  #expect(registrations.allSatisfy { $0.descriptor.route == .source })
  #expect(registrations.allSatisfy { $0.descriptor.effect == .sourceMutation })
  #expect(try RupaCADDomain.registry().count == 21)
}

@Test(.timeLimit(.minutes(1)))
func registryPublishesTheExactVersionOneCADDescriptorSchemas() {
  let actual = RupaCADDomain.registrations().map(\.descriptor)
  #expect(actual == expectedCADDescriptors())
}

@Test(.timeLimit(.minutes(1)))
func registryRejectsDuplicateMissingAndUnexpectedCADComposition() throws {
  let registrations = RupaCADDomain.registrations()
  let duplicate = registrations + [try #require(registrations.first)]

  #expect(throws: SemanticOperationRegistryError.self) {
    try SemanticOperationRegistry(registrations: duplicate)
  }

  let missing = try SemanticOperationRegistry(registrations: Array(registrations.dropLast()))
  #expect(throws: SemanticOperationRegistryError.self) {
    try missing.validateOperations(
      RupaCADSemanticOperationID.all,
      version: RupaCADDomain.operationVersion
    )
  }

  let complete = try SemanticOperationRegistry(registrations: registrations)
  #expect(throws: SemanticOperationRegistryError.self) {
    try complete.validateOperations(
      Array(RupaCADSemanticOperationID.all.dropLast()),
      version: RupaCADDomain.operationVersion
    )
  }

  #expect(throws: SemanticOperationRegistryError.self) {
    try complete.validateOperations(
      RupaCADSemanticOperationID.all,
      version: SemanticOperationVersion(major: 2, minor: 0, patch: 0)
    )
  }
}

@Test(.timeLimit(.minutes(1)))
func everyCADOperationCompilesIdenticallyAsDirectAndOneNodeProgram() throws {
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())

  for fixture in semanticCADFixtures() {
    let direct = try compiler.compile(
      SemanticDirectRequest(
        schemaVersion: .current,
        invocation: fixture.invocation
      ),
      context: fixture.context,
      limits: semanticCADLimits()
    )
    let program = try compiler.compile(
      SemanticProgram(
        schemaVersion: .current,
        nodes: [
          SemanticProgramNode(
            symbol: ProgramNodeSymbol("operation"),
            invocation: fixture.invocation
          )
        ]
      ),
      context: fixture.context,
      limits: semanticCADLimits()
    )

    let directStep = try #require(direct.preparedProgram.steps.first)
    let programStep = try #require(program.preparedProgram.steps.first)
    #expect(direct.preparedProgram.steps.count == 1)
    #expect(program.preparedProgram.steps.count == 1)
    #expect(
      directStep.outputs.map { $0.selector }
        == programStep.outputs.map { $0.selector }
    )
    #expect(directStep.estimatedGeneratedSourceWork == programStep.estimatedGeneratedSourceWork)
    #expect(directStep.commandBuilder.name == fixture.invocation.operationID.rawValue)
    #expect(programStep.commandBuilder.name == fixture.invocation.operationID.rawValue)

    let directCommand = try buildCommand(from: directStep)
    let programCommand = try buildCommand(from: programStep)
    #expect(directCommand == programCommand)
    #expect(directCommand.command.name == fixture.expectedCommandName)
  }
}

@Test(.timeLimit(.minutes(1)), arguments: [0.0, 361.0, -361.0])
func revolveRejectsInvalidAnglesBeforePreparedMutation(angle: Double) throws {
  let source = SemanticSourceReference.feature(FeatureID())
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
  let invocation = SemanticOperationInvocation(
    operationID: RupaCADSemanticOperationID.surfaceRevolveCurve,
    operationVersion: RupaCADDomain.operationVersion,
    arguments: semanticArguments([
      "name": .literal(.text("Invalid Revolution")), "curve": .existing(source),
      "axisOrigin": .literal(.point(point(0, 0, 0))),
      "axisDirection": .literal(.direction(direction(0, 1, 0))),
      "angle": .literal(.number(angle, unit: .degree)),
    ]))
  do {
    _ = try compiler.compile(SemanticDirectRequest(schemaVersion: .current, invocation: invocation),
      context: SemanticCompilationContext(existingSourceReferences: [source]),
      limits: semanticCADLimits())
    Issue.record("Invalid revolution must fail before command preparation.")
  } catch let error as SemanticCompilationError {
    guard case .loweringFailed(_, RupaCADSemanticOperationID.surfaceRevolveCurve,
      RupaCADDomainError.degenerateGeometryCode, _) = error else {
      Issue.record("Unexpected failure: \(error)")
      return
    }
  }
}

@Test(.timeLimit(.minutes(1)))
func constrainedSketchLowersAllEightRelationFamiliesWithoutPersistentEntityIDs() throws {
  let fixture = try #require(
    semanticCADFixtures().first {
      $0.invocation.operationID == RupaCADSemanticOperationID.sketchConstrained
    }
  )
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
  let compiled = try compiler.compile(
    SemanticDirectRequest(schemaVersion: .current, invocation: fixture.invocation),
    context: fixture.context,
    limits: semanticCADLimits()
  )
  let command = try buildCommand(from: #require(compiled.preparedProgram.steps.first)).command
  guard case .createSemanticSketch(_, let plan, _) = command else {
    Issue.record("Expected createSemanticSketch.")
    return
  }

  #expect(plan.entities.count == 6)
  #expect(plan.constraints.count == 8)
  #expect(plan.constraints.contains { if case .coincident = $0 { true } else { false } })
  #expect(plan.constraints.contains { if case .parallel = $0 { true } else { false } })
  #expect(plan.constraints.contains { if case .perpendicular = $0 { true } else { false } })
  #expect(plan.constraints.contains { if case .horizontal = $0 { true } else { false } })
  #expect(plan.constraints.contains { if case .vertical = $0 { true } else { false } })
  #expect(plan.constraints.contains { if case .equalLength = $0 { true } else { false } })
  #expect(plan.constraints.contains { if case .concentric = $0 { true } else { false } })
  #expect(plan.constraints.contains { if case .equalRadius = $0 { true } else { false } })
}

@Test(.timeLimit(.minutes(1)), arguments: ["missingSection", "duplicate", "overlap", "tension", "mode", "closure"])
func loftRejectsInvalidInputsBeforePreparedMutation(fault: String) throws {
  let first = SemanticSourceReference.feature(FeatureID())
  let second = SemanticSourceReference.feature(FeatureID())
  var args: [String: SemanticArgument] = [
    "name": .literal(.text("Invalid Loft")), "sections": .array([
      semanticLoftSection("curve", .existing(first)), semanticLoftSection("curve", .existing(second))]),
    "guides": .array([]), "surfaceMode": .literal(.text("ruled")),
    "tangentScale": .literal(.number(1, unit: .unitless)), "closed": .literal(.boolean(false))]
  switch fault {
  case "missingSection": args["sections"] = .array([semanticLoftSection("curve", .existing(first))])
  case "duplicate": args["sections"] = .array([
    semanticLoftSection("curve", .existing(first)), semanticLoftSection("profile", .existing(first))])
  case "overlap": args["guides"] = .array([.existing(first)])
  case "tension": args["tangentScale"] = .literal(.number(0, unit: .unitless))
  case "mode": args["surfaceMode"] = .literal(.text("unknown"))
  default: args["closed"] = .literal(.boolean(true))
  }
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
  do {
    _ = try compiler.compile(SemanticDirectRequest(schemaVersion: .current,
      invocation: SemanticOperationInvocation(operationID: RupaCADSemanticOperationID.surfaceLoft,
        operationVersion: RupaCADDomain.operationVersion, arguments: semanticArguments(args))),
      context: SemanticCompilationContext(existingSourceReferences: [first, second]), limits: semanticCADLimits())
    Issue.record("Invalid Loft must fail before command preparation.")
  } catch let error as SemanticCompilationError {
    guard case .loweringFailed(_, RupaCADSemanticOperationID.surfaceLoft,
      RupaCADDomainError.invalidArgumentCode, _) = error else { Issue.record("Unexpected failure: \(error)"); return }
  }
}

@Test(.timeLimit(.minutes(1)))
func linearPatternUsesCheckedArgumentDependentWorkAtBothBounds() throws {
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
  let definitionID = ComponentDefinitionID()
  let reference = SemanticSourceReference.componentDefinition(definitionID)

  func compile(count: Int64) throws -> SemanticCompilationResult {
    try compiler.compile(
      SemanticDirectRequest(
        schemaVersion: .current,
        invocation: patternInvocation(definition: reference, count: count)
      ),
      context: SemanticCompilationContext(existingSourceReferences: [reference]),
      limits: semanticCADLimits(maximumExpandedSourceWork: 30_000)
    )
  }

  #expect(try compile(count: 1).preparedProgram.estimatedGeneratedSourceWork == 5)
  #expect(
    try compile(count: Int64(PatternArrayGenerationBudget.standard.maximumOutputInstanceCount))
      .preparedProgram.estimatedGeneratedSourceWork == 20_003
  )

  do {
    _ = try compile(
      count: Int64(PatternArrayGenerationBudget.standard.maximumOutputInstanceCount + 1)
    )
    Issue.record("Expected the pattern count ceiling to fail.")
  } catch let error as SemanticCompilationError {
    guard
      case .loweringFailed(
        _,
        RupaCADSemanticOperationID.patternLinear,
        RupaCADDomainError.invalidArgumentCode,
        _
      ) = error
    else {
      Issue.record("Unexpected failure: \(error)")
      return
    }
  }
}

@Test(.timeLimit(.minutes(1)), arguments: ["legacyArray", "legacyOperation", "unknownKind", "extraField", "sceneSource", "solidCurve", "zeroTension", "wrongUnit", "wrongMode", "profileRange", "badRange", "rangeUnit", "reverseProfile", "reverseText", "curveProfileDirection", "invalidProfileDirection", "negativeStart", "fractionalStart", "overflowStart", "startUnit"])
func loftTypedSectionsRejectWrongMeaning(fault: String) throws {
  let first = SemanticSourceReference.feature(FeatureID())
  let second = SemanticSourceReference.feature(FeatureID())
  let scene = SemanticSourceReference.sceneNode(SceneNodeID())
  var firstSection = semanticLoftSection("curve", .existing(first))
  if ["negativeStart", "fractionalStart", "overflowStart", "startUnit"].contains(fault) {
    firstSection = semanticLoftSection("curve", .existing(first), controls: ["startSampleIndex":
      .literal(.number(fault == "negativeStart" ? -1 : fault == "fractionalStart" ? 0.5 : fault == "overflowStart" ? 1e100 : 0,
        unit: fault == "startUnit" ? .meter : .unitless))])
  }
  if fault == "unknownKind" { firstSection = semanticLoftSection("mesh", .existing(first)) }
  if fault == "extraField" {
    firstSection = object(["kind": .literal(.text("curve")), "source": .existing(first), "ignored": .literal(.boolean(true))])
  }
  if fault == "sceneSource" { firstSection = semanticLoftSection("curve", .existing(scene)) }
  if fault == "curveProfileDirection" || fault == "invalidProfileDirection" {
    firstSection = semanticLoftSection(fault == "curveProfileDirection" ? "curve" : "profile", .existing(first),
      controls: ["profileDirection": .literal(.text(fault == "curveProfileDirection" ? "automatic" : "backwards"))])
  }
  if fault == "reverseProfile" || fault == "reverseText" {
    firstSection = semanticLoftSection(fault == "reverseProfile" ? "profile" : "curve", .existing(first),
      controls: ["reversed": fault == "reverseText" ? .literal(.text("true")) : .literal(.boolean(true))])
  }
  if fault == "profileRange" || fault == "badRange" || fault == "rangeUnit" {
    firstSection = semanticLoftSection(fault == "profileRange" ? "profile" : "curve", .existing(first),
      controls: ["parameterRange": .array([
        .literal(.number(fault == "badRange" ? 1 : 0, unit: .unitless)),
        .literal(.number(0.5, unit: fault == "rangeUnit" ? .meter : .unitless))])])
  }
  if fault == "zeroTension" || fault == "wrongUnit" || fault == "wrongMode" {
    firstSection = semanticLoftSection("curve", .existing(first), controls: fault == "wrongMode"
      ? ["tangentMode": .literal(.text("G2"))]
      : ["tangentScale": .literal(.number(fault == "zeroTension" ? 0 : 1,
        unit: fault == "wrongUnit" ? .meter : .unitless))])
  }
  let sections: SemanticArgument = fault == "legacyArray" ? .array([.existing(first), .existing(second)])
    : .array([firstSection, semanticLoftSection("profile", .existing(second))])
  let operation: DomainCapabilityID = fault == "legacyOperation" ? "cad.surface.loftCurves"
    : fault == "solidCurve" ? RupaCADSemanticOperationID.solidLoft : RupaCADSemanticOperationID.surfaceLoft
  let request = SemanticDirectRequest(schemaVersion: .current,
    invocation: SemanticOperationInvocation(operationID: operation, operationVersion: RupaCADDomain.operationVersion,
      arguments: semanticArguments(["name": .literal(.text("Rejected Loft")), "sections": sections,
        "guides": .array([]), "surfaceMode": .literal(.text("ruled")),
        "tangentScale": .literal(.number(1, unit: .unitless)), "closed": .literal(.boolean(false))])))
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
  #expect(throws: SemanticCompilationError.self) {
    try compiler.compile(request, context: SemanticCompilationContext(existingSourceReferences: [first, second, scene]),
      limits: semanticCADLimits())
  }
}

@Test(.timeLimit(.minutes(1)))
func loftProfileRegionIndexIsPreservedBySemanticLowering() throws {
  let first = SemanticSourceReference.feature(FeatureID())
  let second = SemanticSourceReference.feature(FeatureID())
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
  for (kind, value, unit) in [("profile", 2.0, SemanticUnit.unitless),
    ("profile", -1.0, .unitless), ("profile", 0.5, .unitless),
    ("profile", 1e100, .unitless), ("profile", 0.0, .meter), ("curve", 0.0, .unitless)] {
    let request = SemanticDirectRequest(schemaVersion: .current, invocation: SemanticOperationInvocation(
      operationID: RupaCADSemanticOperationID.surfaceLoft, operationVersion: RupaCADDomain.operationVersion,
      arguments: semanticArguments(["name": .literal(.text("Indexed Loft")),
        "sections": .array([
          semanticLoftSection(kind, .existing(first), controls: ["profileIndex": .literal(.number(value, unit: unit))]),
          semanticLoftSection("profile", .existing(second))]),
        "guides": .array([]), "surfaceMode": .literal(.text("ruled")),
        "tangentScale": .literal(.number(1, unit: .unitless)), "closed": .literal(.boolean(false))])))
    if value == 2 {
      let compiled = try compiler.compile(request,
        context: SemanticCompilationContext(existingSourceReferences: [first, second]), limits: semanticCADLimits())
      let command = try buildCommand(from: #require(compiled.preparedProgram.steps.first))
      guard case .createLoft(_, let sections, _, _) = command.command,
            case .profile(let profile) = sections[0].section else {
        Issue.record("Expected an indexed profile Loft."); return
      }
      #expect(profile.profileIndex == 2)
    } else {
      #expect(throws: SemanticCompilationError.self) {
        try compiler.compile(request,
          context: SemanticCompilationContext(existingSourceReferences: [first, second]), limits: semanticCADLimits())
      }
    }
  }
}

@Test(.timeLimit(.minutes(1)))
func CADLoweringPreservesStableDomainErrorCodes() throws {
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
  let invalidSphere = SemanticOperationInvocation(
    operationID: RupaCADSemanticOperationID.solidSphere,
    operationVersion: RupaCADDomain.operationVersion,
    arguments: semanticArguments([
      "name": .literal(.text("Invalid Sphere")),
      "center": .literal(.point(point(0, 0, 0))),
      "radius": .literal(.number(0, unit: .meter)),
    ])
  )

  do {
    _ = try compiler.compile(
      SemanticDirectRequest(schemaVersion: .current, invocation: invalidSphere),
      context: SemanticCompilationContext(),
      limits: semanticCADLimits()
    )
    Issue.record("Expected a degenerate sphere failure.")
  } catch let error as SemanticCompilationError {
    guard
      case .loweringFailed(
        _,
        RupaCADSemanticOperationID.solidSphere,
        RupaCADDomainError.degenerateGeometryCode,
        _
      ) = error
    else {
      Issue.record("Unexpected failure: \(error)")
      return
    }
  }
}

private struct SemanticCADFixture {
  let invocation: SemanticOperationInvocation
  let context: SemanticCompilationContext
  let expectedCommandName: String
}

private func expectedCADDescriptors() -> [SemanticOperationDescriptor] {
  [
    descriptor(
      RupaCADSemanticOperationID.sketchLine,
      inputs: [
        input("name", .text),
        input("plane", .plane),
        input("start", .point),
        input("end", .point),
      ],
      outputs: [
        output("curve", .feature, .feature(index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 2
    ),
    descriptor(
      RupaCADSemanticOperationID.sketchRectangle,
      inputs: [
        input("name", .text),
        input("plane", .plane),
        input("center", .point),
        input("width", .number(unit: .meter)),
        input("height", .number(unit: .meter)),
      ],
      outputs: [
        output("profile", .feature, .feature(index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 2
    ),
    descriptor(
      RupaCADSemanticOperationID.sketchCircle,
      inputs: [
        input("name", .text),
        input("plane", .plane),
        input("center", .point),
        input("radius", .number(unit: .meter)),
      ],
      outputs: [
        output("profile", .feature, .feature(index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 2
    ),
    descriptor(
      RupaCADSemanticOperationID.sketchConstrained,
      inputs: [
        input("name", .text),
        input("plane", .plane),
        input("entities", .array(element: .object)),
        input("relations", .array(element: .object)),
      ],
      outputs: [
        output("sketch", .feature, .feature(index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 2
    ),
    descriptor(
      RupaCADSemanticOperationID.solidBox,
      inputs: [
        input("name", .text),
        input("origin", .point),
        input("width", .number(unit: .meter)),
        input("depth", .number(unit: .meter)),
        input("height", .number(unit: .meter)),
      ],
      outputs: solidPrimitiveOutputs,
      work: 5
    ),
    descriptor(
      RupaCADSemanticOperationID.solidCylinder,
      inputs: [
        input("name", .text),
        input("baseCenter", .point),
        input("axis", .direction),
        input("radius", .number(unit: .meter)),
        input("height", .number(unit: .meter)),
      ],
      outputs: solidPrimitiveOutputs,
      work: 5
    ),
    descriptor(
      RupaCADSemanticOperationID.solidExtrude,
      inputs: [
        input("name", .text),
        input("profile", .feature),
        input("distance", .number(unit: .meter)),
        input("direction", .direction),
      ],
      outputs: [
        output(
          "body",
          .sourceBody(role: .body),
          .sourceBody(role: .body, index: 0)
        ),
        output("scene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 3
    ),
    descriptor(
      RupaCADSemanticOperationID.surfaceExtrude,
      inputs: [
        input("name", .text),
        input("profile", .feature),
        input("distance", .number(unit: .meter)),
        input("direction", .direction),
      ],
      outputs: [
        output("body", .sourceBody(role: .sheet), .sourceBody(role: .sheet, index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 3
    ),
    descriptor(
      RupaCADSemanticOperationID.surfaceExtrudeCurve,
      inputs: [
        input("name", .text),
        input("curve", .feature),
        input("distance", .number(unit: .meter)),
        input("direction", .direction),
      ],
      outputs: [
        output("body", .sourceBody(role: .sheet), .sourceBody(role: .sheet, index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 3
    ),
    descriptor(
      RupaCADSemanticOperationID.solidRevolve,
      inputs: [input("name", .text), input("profile", .feature),
        input("axisOrigin", .point), input("axisDirection", .direction),
        input("angle", .number(unit: .degree))],
      outputs: [output("body", .sourceBody(role: .body), .sourceBody(role: .body, index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0))],
      work: 3
    ),
    descriptor(
      RupaCADSemanticOperationID.surfaceRevolve,
      inputs: [input("name", .text), input("profile", .feature),
        input("axisOrigin", .point), input("axisDirection", .direction),
        input("angle", .number(unit: .degree))],
      outputs: [output("body", .sourceBody(role: .sheet), .sourceBody(role: .sheet, index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0))],
      work: 3
    ),
    descriptor(
      RupaCADSemanticOperationID.surfaceRevolveCurve,
      inputs: [input("name", .text), input("curve", .feature),
        input("axisOrigin", .point), input("axisDirection", .direction),
        input("angle", .number(unit: .degree))],
      outputs: [output("body", .sourceBody(role: .sheet), .sourceBody(role: .sheet, index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0))],
      work: 3
    ),
    descriptor(
      RupaCADSemanticOperationID.solidSphere,
      inputs: [
        input("name", .text),
        input("center", .point),
        input("radius", .number(unit: .meter)),
      ],
      outputs: [
        output(
          "body",
          .sourceBody(role: .body),
          .sourceBody(role: .body, index: 0)
        ),
        output("scene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 3
    ),
    loftDescriptor(RupaCADSemanticOperationID.solidLoft, role: .body),
    loftDescriptor(RupaCADSemanticOperationID.surfaceLoft, role: .sheet),
    loftDescriptor(RupaCADSemanticOperationID.solidLoftReplace, role: .body, replacing: true),
    loftDescriptor(RupaCADSemanticOperationID.surfaceLoftReplace, role: .sheet, replacing: true),
    descriptor(
      RupaCADSemanticOperationID.sceneTransform,
      inputs: [
        input("scene", .sceneNode),
        input("translation", .point),
        input("axisPoint", .point),
        input("rotationAxis", .direction),
        input("rotation", .number(unit: .degree)),
      ],
      outputs: [],
      work: 0
    ),
    descriptor(
      RupaCADSemanticOperationID.componentDefine,
      inputs: [
        input("name", .text),
        input("rootScenes", .array(element: .sceneNode)),
      ],
      outputs: [
        output(
          "definition",
          .componentDefinition,
          .componentDefinition(index: 0)
        )
      ],
      work: 1
    ),
    descriptor(
      RupaCADSemanticOperationID.componentInstantiate,
      inputs: [
        input("name", .text),
        input("definition", .componentDefinition),
        input("transform", .transform),
      ],
      outputs: [
        output("instance", .componentInstance, .componentInstance(index: 0)),
        output("scene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 2
    ),
    descriptor(
      RupaCADSemanticOperationID.patternLinear,
      inputs: [
        input("name", .text),
        input("definition", .componentDefinition),
        input("direction", .direction),
        input("distance", .number(unit: .meter)),
        input("count", .integer),
      ],
      outputs: [
        output("pattern", .patternArraySource, .patternArraySource(index: 0)),
        output("rootScene", .sceneNode, .sceneNode(index: 0)),
      ],
      work: 5
    ),
  ]
}

private func loftDescriptor(_ id: DomainCapabilityID, role: SourceBodyOutputRole, replacing: Bool = false) -> SemanticOperationDescriptor {
  descriptor(id, inputs: [replacing ? input("body", .sourceBody(role: role)) : input("name", .text), input("sections", .array(element: .object)),
    input("guides", .array(element: .feature)), input("surfaceMode", .text),
    input("tangentScale", .number(unit: .unitless)), input("closed", .boolean)],
    outputs: replacing ? [] : [output("body", .sourceBody(role: role), .sourceBody(role: role, index: 0)),
      output("scene", .sceneNode, .sceneNode(index: 0))], work: replacing ? 0 : 3)
}

private var solidPrimitiveOutputs: [SemanticOperationOutputDescriptor] {
  [
    output("profile", .feature, .feature(index: 0)),
    output(
      "body",
      .sourceBody(role: .body),
      .sourceBody(role: .body, index: 0)
    ),
    output("profileScene", .sceneNode, .sceneNode(index: 1)),
    output("bodyScene", .sceneNode, .sceneNode(index: 0)),
  ]
}

private func descriptor(
  _ operationID: DomainCapabilityID,
  inputs: [SemanticOperationInputDescriptor],
  outputs: [SemanticOperationOutputDescriptor],
  work: UInt64
) -> SemanticOperationDescriptor {
  SemanticOperationDescriptor(
    operationID: operationID,
    version: RupaCADDomain.operationVersion,
    inputs: inputs,
    outputs: outputs,
    route: .source,
    effect: .sourceMutation,
    estimatedExpandedSourceWork: work,
    resultEstimate: SemanticOperationResultEstimate(
      diagnosticRecordCount: 0,
      diagnosticScalarCount: 0,
      diagnosticStringUTF8ByteCount: 0,
      telemetryRecordCount: 1,
      telemetryScalarCount: 6,
      telemetryStringUTF8ByteCount: 0
    )
  )
}

private func input(
  _ id: String,
  _ type: SemanticValueType
) -> SemanticOperationInputDescriptor {
  SemanticOperationInputDescriptor(
    id: SemanticArgumentID(id),
    type: type,
    isRequired: true
  )
}

private func output(
  _ id: String,
  _ type: SemanticValueType,
  _ selector: SemanticOutputSelector
) -> SemanticOperationOutputDescriptor {
  SemanticOperationOutputDescriptor(
    id: SemanticOutputID(id),
    type: type,
    selector: selector
  )
}

private func semanticCADFixtures() -> [SemanticCADFixture] {
  let planeValue = plane()
  let profileID = FeatureID()
  let secondProfile = SemanticSourceReference.feature(FeatureID())
  let sceneID = SceneNodeID()
  let definitionID = ComponentDefinitionID()
  let profile = SemanticSourceReference.feature(profileID)
  let scene = SemanticSourceReference.sceneNode(sceneID)
  let definition = SemanticSourceReference.componentDefinition(definitionID)
  let solid = SemanticSourceReference.sourceBody(featureID: FeatureID(), role: .body)
  let sheet = SemanticSourceReference.sourceBody(featureID: FeatureID(), role: .sheet)
  let commonContext = SemanticCompilationContext(
    existingSourceReferences: [profile, secondProfile, scene, definition, solid, sheet]
  )
  let identityTransform = SemanticTransform(
    translation: point(0, 0, 0),
    axisPoint: point(0, 0, 0),
    rotationAxis: direction(0, 0, 1),
    rotation: SemanticAngle(value: 0, unit: .degree)
  )

  return [
    fixture("cad.solid.loft.replace", "setLoft", [
      "body": .existing(solid), "sections": .array([
        semanticLoftSection("profile", .existing(profile)), semanticLoftSection("profile", .existing(secondProfile))]),
      "guides": .array([]), "surfaceMode": .literal(.text("ruled")),
      "tangentScale": .literal(.number(1, unit: .unitless)), "closed": .literal(.boolean(false))], context: commonContext),
    fixture("cad.surface.loft.replace", "setLoft", [
      "body": .existing(sheet), "sections": .array([
        semanticLoftSection("curve", .existing(profile)), semanticLoftSection("curve", .existing(secondProfile))]),
      "guides": .array([]), "surfaceMode": .literal(.text("smooth")),
      "tangentScale": .literal(.number(0.7, unit: .unitless)), "closed": .literal(.boolean(false))], context: commonContext),
    fixture("cad.solid.loft", "createLoft", [
      "name": .literal(.text("Solid Loft")), "sections": .array([
        semanticLoftSection("profile", .existing(profile)), semanticLoftSection("profile", .existing(secondProfile))]),
      "guides": .array([]), "surfaceMode": .literal(.text("ruled")),
      "tangentScale": .literal(.number(1, unit: .unitless)), "closed": .literal(.boolean(false))], context: commonContext),
    fixture("cad.surface.loft", "createLoft", [
      "name": .literal(.text("Sheet Loft")), "sections": .array([
        semanticLoftSection("profile", .existing(profile)), semanticLoftSection("curve", .existing(secondProfile))]),
      "guides": .array([]), "surfaceMode": .literal(.text("smooth")),
      "tangentScale": .literal(.number(0.7, unit: .unitless)), "closed": .literal(.boolean(false))], context: commonContext),
    fixture("cad.surface.loft", "createLoft", [
      "name": .literal(.text("Curve Loft")), "sections": .array([
        semanticLoftSection("curve", .existing(profile)), semanticLoftSection("curve", .existing(secondProfile))]),
      "guides": .array([]), "surfaceMode": .literal(.text("smooth")),
      "tangentScale": .literal(.number(1, unit: .unitless)), "closed": .literal(.boolean(false))], context: commonContext),
    fixture(
      "cad.sketch.line", "createLineSketch",
      [
        "name": .literal(.text("Line")),
        "plane": .literal(.plane(planeValue)),
        "start": .literal(.point(point(0, 0, 0))),
        "end": .literal(.point(point(1, 0, 0))),
      ]),
    fixture(
      "cad.sketch.rectangle", "createSemanticSketch",
      [
        "name": .literal(.text("Rectangle")),
        "plane": .literal(.plane(planeValue)),
        "center": .literal(.point(point(0, 0, 0))),
        "width": .literal(.number(2, unit: .meter)),
        "height": .literal(.number(1, unit: .meter)),
      ]),
    fixture(
      "cad.sketch.circle", "createCircleSketch",
      [
        "name": .literal(.text("Circle")),
        "plane": .literal(.plane(planeValue)),
        "center": .literal(.point(point(0, 0, 0))),
        "radius": .literal(.number(0.5, unit: .meter)),
      ]),
    fixture(
      "cad.sketch.constrained",
      "createSemanticSketch",
      constrainedSketchArguments(planeValue),
      context: commonContext
    ),
    fixture(
      "cad.solid.box", "createExtrudedRectangle",
      [
        "name": .literal(.text("Box")),
        "origin": .literal(.point(point(1, 2, 3))),
        "width": .literal(.number(2, unit: .meter)),
        "depth": .literal(.number(3, unit: .meter)),
        "height": .literal(.number(4, unit: .meter)),
      ]),
    fixture(
      "cad.solid.cylinder", "createExtrudedCircle",
      [
        "name": .literal(.text("Cylinder")),
        "baseCenter": .literal(.point(point(1, 2, 3))),
        "axis": .literal(.direction(direction(0, 1, 1))),
        "radius": .literal(.number(0.5, unit: .meter)),
        "height": .literal(.number(2, unit: .meter)),
      ]),
    fixture(
      "cad.solid.extrude", "extrudeSection",
      [
        "name": .literal(.text("Extrude")),
        "profile": .existing(profile),
        "distance": .literal(.number(1, unit: .meter)),
        "direction": .literal(.direction(direction(0, 0, 1))),
      ], context: commonContext),
    fixture(
      "cad.surface.extrude", "extrudeSection",
      [
        "name": .literal(.text("Sheet")),
        "profile": .existing(profile),
        "distance": .literal(.number(1, unit: .meter)),
        "direction": .literal(.direction(direction(0, 0, 1))),
      ], context: commonContext),
    fixture(
      "cad.surface.extrudeCurve", "extrudeSection",
      [
        "name": .literal(.text("Curve Sheet")),
        "curve": .existing(profile),
        "distance": .literal(.number(1, unit: .meter)),
        "direction": .literal(.direction(direction(0, 0, 1))),
      ], context: commonContext),
    fixture(
      "cad.solid.revolve", "revolveSection",
      ["name": .literal(.text("Revolve")), "profile": .existing(profile),
       "axisOrigin": .literal(.point(point(0, 0, 0))),
       "axisDirection": .literal(.direction(direction(0, 1, 0))),
       "angle": .literal(.number(180, unit: .degree))], context: commonContext),
    fixture(
      "cad.surface.revolve", "revolveSection",
      ["name": .literal(.text("Revolve Sheet")), "profile": .existing(profile),
       "axisOrigin": .literal(.point(point(0, 0, 0))),
       "axisDirection": .literal(.direction(direction(0, 1, 0))),
       "angle": .literal(.number(-180, unit: .degree))], context: commonContext),
    fixture(
      "cad.surface.revolveCurve", "revolveSection",
      ["name": .literal(.text("Revolve Curve")), "curve": .existing(profile),
       "axisOrigin": .literal(.point(point(0, 0, 0))),
       "axisDirection": .literal(.direction(direction(0, 1, 0))),
       "angle": .literal(.number(360, unit: .degree))], context: commonContext),
    fixture(
      "cad.solid.sphere", "createAnalyticSphere",
      [
        "name": .literal(.text("Sphere")),
        "center": .literal(.point(point(1, 2, 3))),
        "radius": .literal(.number(0.5, unit: .meter)),
      ]),
    fixture(
      "cad.scene.transform", "setSceneNodeTransform",
      [
        "scene": .existing(scene),
        "translation": .literal(.point(point(1, 2, 3))),
        "axisPoint": .literal(.point(point(0, 0, 0))),
        "rotationAxis": .literal(.direction(direction(0, 0, 1))),
        "rotation": .literal(.number(45, unit: .degree)),
      ], context: commonContext),
    fixture(
      "cad.component.define", "createComponentDefinition",
      [
        "name": .literal(.text("Definition")),
        "rootScenes": .array([.existing(scene)]),
      ], context: commonContext),
    fixture(
      "cad.component.instantiate", "createComponentInstance",
      [
        "name": .literal(.text("Instance")),
        "definition": .existing(definition),
        "transform": .literal(.transform(identityTransform)),
      ], context: commonContext),
    SemanticCADFixture(
      invocation: patternInvocation(definition: definition, count: 3),
      context: commonContext,
      expectedCommandName: "createPatternArray"
    ),
  ]
}

private func fixture(
  _ operationID: DomainCapabilityID,
  _ expectedCommandName: String,
  _ arguments: [String: SemanticArgument],
  context: SemanticCompilationContext = SemanticCompilationContext()
) -> SemanticCADFixture {
  SemanticCADFixture(
    invocation: SemanticOperationInvocation(
      operationID: operationID,
      operationVersion: RupaCADDomain.operationVersion,
      arguments: semanticArguments(arguments)
    ),
    context: context,
    expectedCommandName: expectedCommandName
  )
}

private func patternInvocation(
  definition: SemanticSourceReference,
  count: Int64
) -> SemanticOperationInvocation {
  SemanticOperationInvocation(
    operationID: RupaCADSemanticOperationID.patternLinear,
    operationVersion: RupaCADDomain.operationVersion,
    arguments: semanticArguments([
      "name": .literal(.text("Pattern")),
      "definition": .existing(definition),
      "direction": .literal(.direction(direction(1, 0, 0))),
      "distance": .literal(.number(0.25, unit: .meter)),
      "count": .literal(.integer(count)),
    ])
  )
}

private func constrainedSketchArguments(
  _ sketchPlane: SemanticPlane
) -> [String: SemanticArgument] {
  let entities: [SemanticArgument] = [
    entity(
      "line", ["start": .literal(.point(point(0, 0, 0))), "end": .literal(.point(point(1, 0, 0)))]),
    entity(
      "line", ["start": .literal(.point(point(1, 0, 0))), "end": .literal(.point(point(1, 1, 0)))]),
    entity(
      "line", ["start": .literal(.point(point(0, 1, 0))), "end": .literal(.point(point(1, 1, 0)))]),
    entity(
      "line", ["start": .literal(.point(point(0, 0, 0))), "end": .literal(.point(point(0, 1, 0)))]),
    entity(
      "circle",
      [
        "center": .literal(.point(point(0.25, 0.25, 0))),
        "radius": .literal(.number(0.1, unit: .meter)),
      ]),
    entity(
      "circle",
      [
        "center": .literal(.point(point(0.25, 0.25, 0))),
        "radius": .literal(.number(0.2, unit: .meter)),
      ]),
  ]
  let relations: [SemanticArgument] = [
    relation(
      "coincident",
      [
        "firstEntity": .literal(.integer(0)), "firstEndpoint": .literal(.text("end")),
        "secondEntity": .literal(.integer(1)), "secondEndpoint": .literal(.text("start")),
      ]),
    relation(
      "parallel", ["firstEntity": .literal(.integer(0)), "secondEntity": .literal(.integer(2))]),
    relation(
      "perpendicular",
      ["firstEntity": .literal(.integer(0)), "secondEntity": .literal(.integer(1))]),
    relation("horizontal", ["entity": .literal(.integer(0))]),
    relation("vertical", ["entity": .literal(.integer(1))]),
    relation(
      "equalLength", ["firstEntity": .literal(.integer(0)), "secondEntity": .literal(.integer(2))]),
    relation(
      "concentric", ["firstEntity": .literal(.integer(4)), "secondEntity": .literal(.integer(5))]),
    relation(
      "equalRadius", ["firstEntity": .literal(.integer(4)), "secondEntity": .literal(.integer(5))]),
  ]
  return [
    "name": .literal(.text("Constrained")),
    "plane": .literal(.plane(sketchPlane)),
    "entities": .array(entities),
    "relations": .array(relations),
  ]
}

private func entity(
  _ kind: String,
  _ values: [String: SemanticArgument]
) -> SemanticArgument {
  object(["kind": .literal(.text(kind))].merging(values) { _, new in new })
}

private func relation(
  _ kind: String,
  _ values: [String: SemanticArgument]
) -> SemanticArgument {
  object(["kind": .literal(.text(kind))].merging(values) { _, new in new })
}

func semanticLoftSection(_ kind: String, _ source: SemanticArgument,
  controls: [String: SemanticArgument] = [:]
) -> SemanticArgument {
  object(["kind": .literal(.text(kind)), "source": source].merging(controls) { _, new in new })
}

private func object(_ values: [String: SemanticArgument]) -> SemanticArgument {
  .object(
    values.sorted(by: { $0.key < $1.key }).map {
      SemanticArgumentObjectEntry(key: $0.key, value: $0.value)
    })
}

private func semanticArguments(
  _ values: [String: SemanticArgument]
) -> [SemanticArgumentID: SemanticArgument] {
  Dictionary(
    uniqueKeysWithValues: values.map {
      (SemanticArgumentID($0.key), $0.value)
    })
}

private func buildCommand(
  from step: PreparedAutomationStep
) throws -> ContextResolvedEditorCommand {
  let values: [PreparedAutomationSlotID: PreparedAutomationIdentity] = Dictionary(
    uniqueKeysWithValues: step.inputs.compactMap { input in
      guard case .existing(let identity) = input.reference else { return nil }
      return (input.id, identity)
    }
  )
  return try step.commandBuilder.build(
    from: PreparedAutomationResolvedInputs(values: values)
  )
}

private func point(_ x: Double, _ y: Double, _ z: Double) -> SemanticPoint3D {
  SemanticPoint3D(x: x, y: y, z: z, unit: .meter)
}

private func direction(_ x: Double, _ y: Double, _ z: Double) -> SemanticDirection3D {
  SemanticDirection3D(x: x, y: y, z: z)
}

private func plane() -> SemanticPlane {
  SemanticPlane(origin: point(0, 0, 0), normal: direction(0, 0, 1))
}

private func semanticCADLimits(
  maximumExpandedSourceWork: UInt64 = 30_000
) -> SemanticProgramLimitPolicy {
  SemanticProgramLimitPolicy(
    maximumDecodedValueCount: 1_000,
    maximumDecodedNestingDepth: 20,
    maximumNodeCount: 20,
    maximumEdgeCount: 40,
    maximumParameterCount: 40,
    maximumRequestedOutputCount: 40,
    maximumLocalOutputReferenceCount: 40,
    maximumExpressionCount: 100,
    maximumExpressionDepth: 20,
    maximumExpressionWork: 1_000,
    maximumLoweredCommandCount: 20,
    maximumExpandedSourceWork: maximumExpandedSourceWork,
    maximumPreparedInputSlotCount: 100,
    maximumPreparedOutputSlotCount: 100,
    resultLimits: SemanticResultLimits(
      maximumRequestedOutputCount: 100,
      maximumDiagnosticRecordCount: 100,
      maximumDiagnosticScalarCount: 1_000,
      maximumDiagnosticStringUTF8ByteCount: 100_000,
      maximumTelemetryRecordCount: 100,
      maximumTelemetryScalarCount: 1_000,
      maximumTelemetryStringUTF8ByteCount: 100_000
    )
  )
}
