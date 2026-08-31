import Foundation
import RupaCore
import RupaDomainFoundation
import Testing

@testable import RupaAutomation
@testable import RupaCADDomain

@MainActor
@Test(.timeLimit(.minutes(1)))
func profileToExtrudeLocalChainExecutesWithCoreGeneratedIdentities() throws {
  let profileNode = ProgramNodeSymbol("profile")
  let extrudeNode = ProgramNodeSymbol("extrude")
  let program = SemanticProgram(
    schemaVersion: .current,
    nodes: [
      SemanticProgramNode(
        symbol: profileNode,
        invocation: invocation(
          .sketchRectangle,
          arguments: [
            "name": .literal(.text("Chain Profile")),
            "plane": .literal(.plane(defaultPlane())),
            "center": .literal(.point(meterPoint(0, 0, 0))),
            "width": .literal(.number(0.4, unit: .meter)),
            "height": .literal(.number(0.2, unit: .meter)),
          ]
        )
      ),
      SemanticProgramNode(
        symbol: extrudeNode,
        invocation: invocation(
          .solidExtrude,
          arguments: [
            "name": .literal(.text("Chain Body")),
            "profile": .local(
              SemanticOutputReference(
                node: profileNode,
                output: SemanticOutputID("profile"),
                kind: .feature
              )),
            "distance": .literal(.number(0.1, unit: .meter)),
            "direction": .literal(.direction(unitZ())),
          ]
        )
      ),
    ]
  )

  let execution = try execute(program)
  #expect(execution.receipt.stepReceipts.count == 2)
  #expect(
    execution.receipt.stepReceipts.map(\.commandName) == [
      "createSemanticSketch",
      "extrudeProfile",
    ])
  #expect(execution.receipt.outputBindings.count == 4)
  try verifyPersistentBindings(execution.receipt, in: execution.session.document)
  #expect(execution.session.document.cadDocument.designGraph.order.count == 2)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func sceneComponentInstanceAndPatternChainExecutesWithTypedLocalBindings() throws {
  let boxNode = ProgramNodeSymbol("box")
  let definitionNode = ProgramNodeSymbol("definition")
  let instanceNode = ProgramNodeSymbol("instance")
  let patternNode = ProgramNodeSymbol("pattern")
  let identity = SemanticTransform(
    translation: meterPoint(0, 0, 0),
    axisPoint: meterPoint(0, 0, 0),
    rotationAxis: unitZ(),
    rotation: SemanticAngle(value: 0, unit: .degree)
  )
  let program = SemanticProgram(
    schemaVersion: .current,
    nodes: [
      SemanticProgramNode(
        symbol: boxNode,
        invocation: invocation(.solidBox, arguments: boxArguments(name: "Chain Box"))
      ),
      SemanticProgramNode(
        symbol: definitionNode,
        invocation: invocation(
          .componentDefine,
          arguments: [
            "name": .literal(.text("Chain Definition")),
            "rootScenes": .array([
              .local(
                SemanticOutputReference(
                  node: boxNode,
                  output: SemanticOutputID("bodyScene"),
                  kind: .sceneNode
                ))
            ]),
          ]
        )
      ),
      SemanticProgramNode(
        symbol: instanceNode,
        invocation: invocation(
          .componentInstantiate,
          arguments: [
            "name": .literal(.text("Chain Instance")),
            "definition": .local(
              SemanticOutputReference(
                node: definitionNode,
                output: SemanticOutputID("definition"),
                kind: .componentDefinition
              )),
            "transform": .literal(.transform(identity)),
          ]
        )
      ),
      SemanticProgramNode(
        symbol: patternNode,
        invocation: invocation(
          .patternLinear,
          arguments: [
            "name": .literal(.text("Chain Pattern")),
            "definition": .local(
              SemanticOutputReference(
                node: definitionNode,
                output: SemanticOutputID("definition"),
                kind: .componentDefinition
              )),
            "direction": .literal(.direction(SemanticDirection3D(x: 1, y: 0, z: 0))),
            "distance": .literal(.number(0.5, unit: .meter)),
            "count": .literal(.integer(3)),
          ]
        )
      ),
    ]
  )

  let execution = try execute(program)
  #expect(execution.receipt.stepReceipts.count == 4)
  #expect(
    execution.receipt.stepReceipts.map(\.commandName) == [
      "createExtrudedRectangle",
      "createComponentDefinition",
      "createComponentInstance",
      "createPatternArray",
    ])
  try verifyPersistentBindings(execution.receipt, in: execution.session.document)
  #expect(execution.session.document.productMetadata.componentDefinitions.count == 1)
  #expect(execution.session.document.productMetadata.patternArrays.count == 1)
  #expect(execution.session.document.productMetadata.componentInstances.count == 4)
}

@MainActor
private func execute(
  _ program: SemanticProgram
) throws -> (session: EditorSession, receipt: PreparedAutomationExecutionReceipt) {
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
  let compiled = try compiler.compile(
    program,
    context: SemanticCompilationContext(),
    limits: executionLimits()
  )
  let session = EditorSession()
  let receipt = try session.withSourceCommandGroup(named: "CAD semantic execution") { staged in
    try DefaultPreparedAutomationProgramExecutor().execute(
      compiled.preparedProgram,
      in: staged
    )
  }
  return (session, receipt)
}

private func verifyPersistentBindings(
  _ receipt: PreparedAutomationExecutionReceipt,
  in document: DesignDocument,
  caseID: String = "chain"
) throws {
  for binding in receipt.outputBindings {
    switch binding.identity {
    case .feature(let id):
      #expect(document.cadDocument.designGraph.nodes[id] != nil, Comment(rawValue: caseID))
    case .sourceBody(let featureID, _):
      #expect(
        document.cadDocument.designGraph.nodes[featureID] != nil,
        Comment(rawValue: caseID)
      )
    case .sceneNode(let id):
      #expect(document.productMetadata.sceneNodes[id] != nil, Comment(rawValue: caseID))
    case .componentDefinition(let id):
      #expect(
        document.productMetadata.componentDefinitions[id] != nil,
        Comment(rawValue: caseID)
      )
    case .componentInstance(let id):
      #expect(
        document.productMetadata.componentInstances[id] != nil,
        Comment(rawValue: caseID)
      )
    case .patternArraySource(let id):
      #expect(
        document.productMetadata.patternArrays[id] != nil,
        Comment(rawValue: caseID)
      )
    }
  }
}

private func invocation(
  _ operationID: DomainCapabilityID,
  arguments: [String: SemanticArgument]
) -> SemanticOperationInvocation {
  SemanticOperationInvocation(
    operationID: operationID,
    operationVersion: RupaCADDomain.operationVersion,
    arguments: Dictionary(
      uniqueKeysWithValues: arguments.map {
        (SemanticArgumentID($0.key), $0.value)
      })
  )
}

private func boxArguments(
  name: String,
  scale: Double = 1
) -> [String: SemanticArgument] {
  [
    "name": .literal(.text(name)),
    "origin": .literal(.point(meterPoint(0, 0, 0))),
    "width": .literal(.number(0.02 * scale, unit: .meter)),
    "depth": .literal(.number(0.015 * scale, unit: .meter)),
    "height": .literal(.number(0.01 * scale, unit: .meter)),
  ]
}

private func defaultPlane() -> SemanticPlane {
  SemanticPlane(origin: meterPoint(0, 0, 0), normal: unitZ())
}

private func meterPoint(_ x: Double, _ y: Double, _ z: Double) -> SemanticPoint3D {
  SemanticPoint3D(x: x, y: y, z: z, unit: .meter)
}

private func unitZ() -> SemanticDirection3D {
  SemanticDirection3D(x: 0, y: 0, z: 1)
}

private func executionLimits() -> SemanticProgramLimitPolicy {
  SemanticProgramLimitPolicy(
    maximumDecodedValueCount: 1_000,
    maximumDecodedNestingDepth: 20,
    maximumNodeCount: 20,
    maximumEdgeCount: 40,
    maximumParameterCount: 40,
    maximumRequestedOutputCount: 100,
    maximumLocalOutputReferenceCount: 100,
    maximumExpressionCount: 100,
    maximumExpressionDepth: 20,
    maximumExpressionWork: 1_000,
    maximumLoweredCommandCount: 20,
    maximumExpandedSourceWork: 30_000,
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

extension DomainCapabilityID {
  fileprivate static let sketchLine = RupaCADSemanticOperationID.sketchLine
  fileprivate static let sketchRectangle = RupaCADSemanticOperationID.sketchRectangle
  fileprivate static let sketchCircle = RupaCADSemanticOperationID.sketchCircle
  fileprivate static let sketchConstrained = RupaCADSemanticOperationID.sketchConstrained
  fileprivate static let solidBox = RupaCADSemanticOperationID.solidBox
  fileprivate static let solidCylinder = RupaCADSemanticOperationID.solidCylinder
  fileprivate static let solidExtrude = RupaCADSemanticOperationID.solidExtrude
  fileprivate static let solidSphere = RupaCADSemanticOperationID.solidSphere
  fileprivate static let sceneTransform = RupaCADSemanticOperationID.sceneTransform
  fileprivate static let componentDefine = RupaCADSemanticOperationID.componentDefine
  fileprivate static let componentInstantiate = RupaCADSemanticOperationID.componentInstantiate
  fileprivate static let patternLinear = RupaCADSemanticOperationID.patternLinear
}
