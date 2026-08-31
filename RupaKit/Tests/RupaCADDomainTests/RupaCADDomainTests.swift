import RupaCore
import RupaDomainFoundation
import Testing

@testable import RupaAutomation
@testable import RupaCADDomain

@Test(.timeLimit(.minutes(1)))
func registryContainsExactlyTwelveVersionOneCADOperations() throws {
  let registrations = RupaCADDomain.registrations()
  let expectedIDs = Set(RupaCADSemanticOperationID.all)

  #expect(registrations.count == 12)
  #expect(Set(registrations.map(\.descriptor.operationID)) == expectedIDs)
  #expect(Set(registrations.map(\.descriptor.version)) == [RupaCADDomain.operationVersion])
  #expect(registrations.allSatisfy { $0.descriptor.route == .source })
  #expect(registrations.allSatisfy { $0.descriptor.effect == .sourceMutation })
  #expect(try RupaCADDomain.registry().count == 12)
}

@Test(.timeLimit(.minutes(1)))
func registryPublishesTheExactVersionOneCADDescriptorSchemas() {
  let actual = RupaCADDomain.registrations().map(\.descriptor)
  #expect(actual == expectedCADDescriptors())
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
  let sceneID = SceneNodeID()
  let definitionID = ComponentDefinitionID()
  let profile = SemanticSourceReference.feature(profileID)
  let scene = SemanticSourceReference.sceneNode(sceneID)
  let definition = SemanticSourceReference.componentDefinition(definitionID)
  let commonContext = SemanticCompilationContext(
    existingSourceReferences: [profile, scene, definition]
  )
  let identityTransform = SemanticTransform(
    translation: point(0, 0, 0),
    axisPoint: point(0, 0, 0),
    rotationAxis: direction(0, 0, 1),
    rotation: SemanticAngle(value: 0, unit: .degree)
  )

  return [
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
      "cad.solid.extrude", "extrudeProfile",
      [
        "name": .literal(.text("Extrude")),
        "profile": .existing(profile),
        "distance": .literal(.number(1, unit: .meter)),
        "direction": .literal(.direction(direction(0, 0, 1))),
      ], context: commonContext),
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
