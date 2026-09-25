import Foundation
import RupaCore
import RupaDomainFoundation
import Testing
import SwiftCAD

@testable import RupaAutomation
@testable import RupaCADDomain

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [0.0, -0.02, 0.2])
func profileToExtrudeLocalChainExecutesWithCoreGeneratedIdentities(start: Double) throws {
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
            "start_distance": .literal(.number(start, unit: .meter)),
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
      "extrudeSection",
    ])
  #expect(execution.receipt.outputBindings.count == 4)
  try verifyPersistentBindings(execution.receipt, in: execution.session.document)
  #expect(execution.session.document.cadDocument.designGraph.order.count == 2)
  let document = execution.session.document
  let result = try DocumentEvaluator.modelingDefault(for: document).evaluateExact(document.cadDocument)
  #expect(abs(try #require(result.brep.vertices.values.map(\.point.z).min()) - min(start, 0.1)) < 1e-8)
  #expect(abs(try #require(result.brep.vertices.values.map(\.point.z).max()) - max(start, 0.1)) < 1e-8)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func curveToSheetSemanticChainProducesSheetBindingsAndGeometry() throws {
  let source = ProgramNodeSymbol("curve")
  let program = SemanticProgram(schemaVersion: .current, nodes: [
    SemanticProgramNode(symbol: source, invocation: invocation(RupaCADSemanticOperationID.sketchLine,
      arguments: ["name": .literal(.text("Curve")), "plane": .literal(.plane(defaultPlane())),
        "start": .literal(.point(meterPoint(0, 0, 0))), "end": .literal(.point(meterPoint(0, 0.02, 0)))])),
    SemanticProgramNode(symbol: ProgramNodeSymbol("sheet"),
      invocation: invocation(RupaCADSemanticOperationID.surfaceExtrudeCurve, arguments: [
        "name": .literal(.text("Sheet")),
        "curve": .local(SemanticOutputReference(node: source, output: SemanticOutputID("curve"), kind: .feature)),
        "distance": .literal(.number(0.01, unit: .meter)), "direction": .literal(.direction(unitZ()))
      ]))
  ])
  let execution = try execute(program)
  let sheetBindings = execution.receipt.outputBindings.filter {
    if case .sourceBody(_, .sheet) = $0.identity { return true }
    return false
  }
  #expect(sheetBindings.count == 1)
  let document = execution.session.document
  let evaluated = try DocumentEvaluator.modelingDefault(for: document).evaluateExact(document.cadDocument)
  #expect(evaluated.brep.bodies.values.allSatisfy { $0.kind == .sheet })
  #expect(evaluated.brep.faces.count == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: ["solid", "sheet", "curve"])
func revolveSemanticChainPreservesSectionAndOutputKind(kind: String) throws {
  let source = ProgramNodeSymbol("section")
  let isCurve = kind == "curve"
  let isSolid = kind == "solid"
  let inputID = isCurve ? "curve" : "profile"
  let sectionInvocation: SemanticOperationInvocation
  if isCurve {
    sectionInvocation = invocation(RupaCADSemanticOperationID.sketchLine, arguments: [
      "name": .literal(.text("Generator")), "plane": .literal(.plane(defaultPlane())),
      "start": .literal(.point(meterPoint(0.02, 0, 0))),
      "end": .literal(.point(meterPoint(0.02, 0.02, 0)))])
  } else {
    sectionInvocation = invocation(RupaCADSemanticOperationID.sketchRectangle, arguments: [
      "name": .literal(.text("Profile")), "plane": .literal(.plane(defaultPlane())),
      "center": .literal(.point(meterPoint(0.02, 0, 0))),
      "width": .literal(.number(0.01, unit: .meter)),
      "height": .literal(.number(0.02, unit: .meter))])
  }
  let operation = isCurve ? RupaCADSemanticOperationID.surfaceRevolveCurve
    : isSolid ? RupaCADSemanticOperationID.solidRevolve : RupaCADSemanticOperationID.surfaceRevolve
  let program = SemanticProgram(schemaVersion: .current, nodes: [
    SemanticProgramNode(symbol: source, invocation: sectionInvocation),
    SemanticProgramNode(symbol: ProgramNodeSymbol("revolution"), invocation: invocation(operation,
      arguments: ["name": .literal(.text("Revolution")),
        inputID: .local(SemanticOutputReference(node: source,
          output: SemanticOutputID(inputID), kind: .feature)),
        "axisOrigin": .literal(.point(meterPoint(0, 0, 0))),
        "axisDirection": .literal(.direction(SemanticDirection3D(x: 0, y: 2, z: 0))),
        "angle": .literal(.number(-180, unit: .degree))]))
  ])
  let execution = try execute(program)
  #expect(execution.receipt.stepReceipts.last?.commandName == "revolveSection")
  let bindings = execution.receipt.outputBindings.filter {
    if case .sourceBody(_, let role) = $0.identity { return role == (isSolid ? .body : .sheet) }
    return false
  }
  #expect(bindings.count == 1)
  let document = execution.session.document
  let evaluated = try DocumentEvaluator.modelingDefault(for: document).evaluateExact(document.cadDocument)
  #expect(evaluated.brep.bodies.count == 1)
  #expect(evaluated.brep.bodies.values.allSatisfy { $0.kind == (isSolid ? .solid : .sheet) })
  #expect(evaluated.brep.faces.count == (isCurve ? 2 : isSolid ? 10 : 8))
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
  _ program: SemanticProgram,
  session existingSession: EditorSession? = nil
) throws -> (session: EditorSession, receipt: PreparedAutomationExecutionReceipt) {
  let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
  let compiled = try compiler.compile(
    program,
    context: SemanticCompilationContext(),
    limits: executionLimits()
  )
  let session = existingSession ?? EditorSession()
  let receipt = try session.withSourceCommandGroup(named: "CAD semantic execution") { staged in
    try DefaultPreparedAutomationProgramExecutor().execute(
      compiled.preparedProgram,
      in: staged
    )
  }
  return (session, receipt)
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: ["solid", "sheet", "curve", "mixed"], ["ruled", "smooth"])
func loftSemanticChainPreservesOrderOptionsAndOutput(kind: String, mode: String) throws {
  let isCurve = kind == "curve"
  let isSolid = kind == "solid"
  let isMixed = kind == "mixed"
  let output = isCurve ? "curve" : "profile"
  let symbols = [ProgramNodeSymbol("first"), ProgramNodeSymbol("second"), ProgramNodeSymbol("third")]
  var nodes: [SemanticProgramNode] = []
  for (index, symbol) in symbols.enumerated() {
    let z = Double(index) * 0.02
    let plane = SemanticPlane(origin: meterPoint(0, 0, z), normal: unitZ())
    let args: [String: SemanticArgument]
    if isMixed {
      args = ["name": .literal(.text("Circle \(index)")), "plane": .literal(.plane(plane)),
        "center": .literal(.point(meterPoint(0, 0, z))), "radius": .literal(.number(0.02, unit: .meter))]
    } else if isCurve {
      args = ["name": .literal(.text("Curve \(index)")), "plane": .literal(.plane(plane)),
        "start": .literal(.point(meterPoint(0, 0, z))), "end": .literal(.point(meterPoint(0.04, 0, z)))]
    } else {
      args = ["name": .literal(.text("Profile \(index)")), "plane": .literal(.plane(plane)),
        "center": .literal(.point(meterPoint(0, 0, z))), "width": .literal(.number(0.04, unit: .meter)),
        "height": .literal(.number(0.02, unit: .meter))]
    }
    nodes.append(SemanticProgramNode(symbol: symbol, invocation: invocation(
      isMixed ? RupaCADSemanticOperationID.sketchCircle
        : isCurve ? RupaCADSemanticOperationID.sketchLine : RupaCADSemanticOperationID.sketchRectangle, arguments: args)))
  }
  nodes.append(SemanticProgramNode(symbol: ProgramNodeSymbol("loft"), invocation: invocation(
    isSolid ? RupaCADSemanticOperationID.solidLoft : RupaCADSemanticOperationID.surfaceLoft,
    arguments: ["name": .literal(.text("Loft")),
      "sections": .array(symbols.enumerated().map { index, symbol in
        var controls: [String: SemanticArgument] = index == 1 ? [:] : [
            "tangentScale": .literal(.number(index == 0 ? 0.5 : 1.25, unit: .unitless)),
            "tangentMode": .literal(.text("automatic"))]
        if isCurve {
          controls["reversed"] = .literal(.boolean(true))
          controls["parameterRange"] = .array([.literal(.number(0.01, unit: .unitless)),
            .literal(.number(0.03, unit: .unitless))])
        }
        if !isCurve && !isMixed {
          controls["profileDirection"] = .literal(.text("reversed"))
          controls["startSampleIndex"] = .literal(.number(1, unit: .unitless))
        }
        return semanticLoftSection(isCurve || (isMixed && index == 1) ? "curve" : "profile",
          .local(SemanticOutputReference(node: symbol, output: SemanticOutputID(output), kind: .feature)),
          controls: controls) }),
      "guides": .array([]), "surfaceMode": .literal(.text(mode)),
      "tangentScale": .literal(.number(0.75, unit: .unitless)), "closed": .literal(.boolean(false))])))
  let execution = try execute(SemanticProgram(schemaVersion: .current, nodes: nodes))
  let document = execution.session.document
  let graph = document.cadDocument.designGraph
  let featureID = try #require(graph.order.last)
  let feature = try #require(graph.nodes[featureID])
  guard case .loft(let loft) = feature.operation else { Issue.record("Expected Loft source."); return }
  #expect(loft.sections.map(\.featureID) == Array(graph.order.dropLast()))
  if isMixed { #expect(loft.sections.map { $0.section.isProfile } == [true, false, true]) }
  if !isCurve && !isMixed { #expect(loft.sections.allSatisfy { $0.profileDirection == .reversed }) }
  if !isCurve && !isMixed { #expect(loft.sections.allSatisfy { $0.startSampleIndex == 1 }) }
  #expect(loft.options.surfaceMode.rawValue == mode)
  #expect(loft.options.smoothTangentScale == 0.75)
  #expect(loft.sections.map(\.smoothTangentScale) == [0.5, nil, 1.25])
  #expect(loft.sections.allSatisfy { $0.smoothTangentMode == .automatic })
  #expect(execution.receipt.stepReceipts.last?.commandName == "createLoft")
  try verifyPersistentBindings(execution.receipt, in: document)
  let result = try DocumentEvaluator.modelingDefault(for: document).evaluateExact(document.cadDocument)
  #expect(result.brep.bodies.count == 1)
  #expect(result.brep.bodies.values.allSatisfy { $0.kind == (isSolid ? .solid : .sheet) })
  #expect(result.brep.faces.count == (isCurve ? 2 : isSolid ? 10 : 8))
  if isCurve {
    #expect(result.brep.vertices.values.allSatisfy { abs($0.point.x - 0.01) < 1e-10 || abs($0.point.x - 0.03) < 1e-10 })
    for section in loft.sections {
      guard case .curve(let reference) = section.section else { Issue.record("Expected a curve section."); return }
      #expect(reference.parameterDomain == .closed(0.01, 0.03))
      #expect(reference.isReversed)
    }
  }
  if mode == "smooth" {
    let connector = SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.edge.rawValue,
      ordinal: isCurve ? 3 : 12)
    guard case .edge(let edgeID) = result.subshapes[connector] else {
      Issue.record("Expected the first exact Loft connector."); return
    }
    let edge = try #require(result.brep.edges[edgeID])
    guard case .bSpline(let curve) = result.brep.geometry.curves[edge.curveID] else {
      Issue.record("Expected a native B-spline connector."); return
    }
    #expect(curve.controlPointCount == 4)
    if isCurve { #expect(abs(curve.controlPoints[0].x - 0.03) < 1e-10) }
    let startHandle = (curve.controlPoints[1] - curve.controlPoints[0]).length
    let endHandle = (curve.controlPoints[2] - curve.controlPoints[3]).length
    #expect(abs(startHandle - 0.02 * 0.5 / 3) < 1e-10)
    #expect(abs(endHandle - 0.02 * 0.75 / 3) < 1e-10)
  }
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func loftReplacementSemanticChainRetainsIdentityAndRejectsInvalidResult(solid: Bool) throws {
  let symbols = [ProgramNodeSymbol("a"), ProgramNodeSymbol("b")]
  var nodes = symbols.enumerated().map { index, symbol in
    let z = Double(index) * 0.02
    var arguments: [String: SemanticArgument] = ["name": .literal(.text("Section")),
      "plane": .literal(.plane(SemanticPlane(origin: meterPoint(0, 0, z), normal: unitZ())))]
    if solid {
      arguments["center"] = .literal(.point(meterPoint(0, 0, z)))
      arguments["width"] = .literal(.number(0.04, unit: .meter))
      arguments["height"] = .literal(.number(0.02, unit: .meter))
    } else {
      arguments["start"] = .literal(.point(meterPoint(0, 0, z)))
      arguments["end"] = .literal(.point(meterPoint(0.04, 0, z)))
    }
    return SemanticProgramNode(symbol: symbol, invocation: invocation(
      solid ? RupaCADSemanticOperationID.sketchRectangle : RupaCADSemanticOperationID.sketchLine,
      arguments: arguments))
  }
  let sections = symbols.map { symbol in semanticLoftSection(solid ? "profile" : "curve",
    .local(SemanticOutputReference(node: symbol, output: SemanticOutputID(solid ? "profile" : "curve"), kind: .feature))) }
  var arguments: [String: SemanticArgument] = ["name": .literal(.text("Original Loft")),
    "sections": .array(sections), "guides": .array([]), "surfaceMode": .literal(.text("ruled")),
    "tangentScale": .literal(.number(1, unit: .unitless)), "closed": .literal(.boolean(false))]
  nodes.append(SemanticProgramNode(symbol: ProgramNodeSymbol("loft"), invocation: invocation(
    solid ? RupaCADSemanticOperationID.solidLoft : RupaCADSemanticOperationID.surfaceLoft, arguments: arguments)))
  arguments.removeValue(forKey: "name")
  arguments["body"] = .local(SemanticOutputReference(node: ProgramNodeSymbol("loft"), output: SemanticOutputID("body"),
    kind: .sourceBody(role: solid ? .body : .sheet)))
  arguments["sections"] = .array(sections.reversed())
  arguments["surfaceMode"] = .literal(.text("smooth"))
  arguments["tangentScale"] = .literal(.number(0.5, unit: .unitless))
  let operation = solid ? RupaCADSemanticOperationID.solidLoftReplace : RupaCADSemanticOperationID.surfaceLoftReplace
  let edit = SemanticProgramNode(symbol: ProgramNodeSymbol("edit"), invocation: invocation(operation, arguments: arguments))
  let result = try execute(SemanticProgram(schemaVersion: .current, nodes: nodes + [edit]))
  let graph = result.session.document.cadDocument.designGraph
  #expect(graph.order.count == 3)
  let id = try #require(graph.order.last)
  let source = try #require(graph.nodes[id])
  guard case .loft(let loft) = source.operation else { Issue.record("Expected Loft source."); return }
  #expect(source.name == "Original Loft")
  #expect(loft.sections.map(\.featureID) == Array(graph.order.prefix(2).reversed()))
  #expect(loft.options.surfaceMode == .smooth)
  #expect(loft.options.smoothTangentScale == 0.5)
  #expect(result.receipt.stepReceipts.last?.commandName == "setLoft")
  #expect(result.receipt.outputBindings.count == 6)
  try verifyPersistentBindings(result.receipt, in: result.session.document)
  let geometry = try DocumentEvaluator.modelingDefault(for: result.session.document).evaluateExact(result.session.document.cadDocument)
  #expect(geometry.brep.bodies.count == 1)
  #expect(geometry.brep.faces.count == (solid ? 6 : 1))

  // A valid body role does not prove the target is a Loft. Core owns that check.
  let otherBody = SemanticProgramNode(symbol: ProgramNodeSymbol("other"), invocation: solid
    ? invocation(RupaCADSemanticOperationID.solidBox, arguments: boxArguments(name: "Not Loft"))
    : invocation(RupaCADSemanticOperationID.surfaceExtrudeCurve, arguments: [
      "name": .literal(.text("Not Loft")),
      "curve": .local(SemanticOutputReference(node: symbols[0], output: SemanticOutputID("curve"), kind: .feature)),
      "distance": .literal(.number(0.01, unit: .meter)), "direction": .literal(.direction(unitZ()))]))
  arguments["body"] = .local(SemanticOutputReference(node: ProgramNodeSymbol("other"), output: SemanticOutputID("body"),
    kind: .sourceBody(role: solid ? .body : .sheet)))
  let invalid = SemanticProgramNode(symbol: ProgramNodeSymbol("invalid"), invocation: invocation(operation, arguments: arguments))
  let session = EditorSession()
  do {
    _ = try execute(SemanticProgram(schemaVersion: .current, nodes: nodes + [otherBody, invalid]), session: session)
    Issue.record("Replacing a non-Loft body must fail.")
  } catch let error as PreparedAutomationExecutionError {
    guard case .coreCommandFailed(stepIndex: 4, commandName: "setLoft", code: .referenceUnresolved, message: _) = error else {
      Issue.record("Unexpected failure: \(error)"); return
    }
  }
  #expect(session.document.cadDocument.designGraph.order.isEmpty)
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
