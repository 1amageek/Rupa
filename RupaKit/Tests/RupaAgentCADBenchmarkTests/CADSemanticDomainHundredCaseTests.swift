import Foundation
import RupaCADDomain
import RupaCore
import RupaDomainFoundation
import RupaKit
import SwiftCAD
import Testing

@testable import RupaAgentCADBenchmark

@MainActor
@Test(.timeLimit(.minutes(5)))
func semanticDomainExecutesTheFixedHundredCasesThroughProjectAuthority() async throws {
    let entries = try CADInternalCatalogStore.entries()
    #expect(entries.count == 100)

    var failures: [String] = []
    for entry in entries {
        do {
            try await executeExactSemanticCase(entry)
        } catch {
            failures.append("\(entry.challenge.id.rawValue): \(error)")
        }
    }

    #expect(
        failures.isEmpty,
        Comment(rawValue: failures.joined(separator: "\n"))
    )
}

@MainActor
private func executeExactSemanticCase(_ entry: CADCatalogEntry) async throws {
    let plan = try exactSemanticPlan(for: entry)
    let compiler = DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
    let compilation = try compiler.compile(
        plan.program,
        context: plan.context,
        limits: exactSemanticLimits()
    )
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(document: plan.document)
    let initial = try await workspace.evaluate()
    let result = try await workspace.executeSemanticProgram(
        ProjectSemanticProgramRequest(
            compilation: compilation,
            authority: initial.authorityCoordinate,
            dryRun: false,
            resultBudget: exactSemanticResultBudget()
        )
    )
    guard case .committed(let commit) = result else {
        throw ExactSemanticCaseError.unexpectedResult
    }
    try validateExactSemanticCase(entry, plan: plan, initial: initial, commit: commit)
}

private struct ExactSemanticCasePlan {
    let document: DesignDocument
    let context: SemanticCompilationContext
    let program: SemanticProgram
    let evidence: ExactSemanticEvidence
}

private enum ExactSemanticEvidence {
    case feature(steps: [ExactSemanticStep], roles: [ExactSemanticRole])
    case transform(sceneNodeID: SceneNodeID, expected: Transform3D)
    case sphere(body: SemanticOutputReference)
}

private struct ExactSemanticStep {
    let operation: String
    let created: [SemanticOutputReference]
    let primary: SemanticOutputReference
}

private struct ExactSemanticRole {
    let name: String
    let stepIndex: Int
}

private enum ExactSemanticCaseError: Error, CustomStringConvertible {
    case unexpectedResult
    case missingOutput(String)
    case invalidCase(String)

    var description: String {
        switch self {
        case .unexpectedResult:
            "The project authority did not return a committed semantic result."
        case .missingOutput(let output):
            "The committed semantic result is missing \(output)."
        case .invalidCase(let reason):
            reason
        }
    }
}

@MainActor
private func exactSemanticPlan(for entry: CADCatalogEntry) throws -> ExactSemanticCasePlan {
    switch entry.input {
    case .line(let input):
        return try linePlan(input, entry: entry)
    case .rectangle(let input):
        return try rectanglePlan(input, entry: entry)
    case .circle(let input):
        return try circlePlan(input, entry: entry)
    case .angle(let input):
        return try anglePlan(input, entry: entry)
    case .box(let input):
        return boxPlan(input, entry: entry)
    case .cylinder(let input):
        return cylinderPlan(input, entry: entry)
    case .constraint(let input):
        return try constraintPlan(input, entry: entry)
    case .transform(let input):
        return try transformPlan(input, entry: entry)
    case .compound(let input):
        return try compoundPlan(input, entry: entry)
    case .sphere(let input):
        return spherePlan(input, entry: entry)
    }
}

private func linePlan(
    _ input: CADLineChallengeInput,
    entry: CADCatalogEntry
) throws -> ExactSemanticCasePlan {
    let symbol = ProgramNodeSymbol("line")
    let curve = output(symbol, "curve", .feature)
    let plane = try CADLineGeometryMapping.sourcePlane(
        orientation: input.plane,
        anchor: input.start,
        modelingTolerance: .standard,
        caseID: entry.challenge.id
    )
    return featurePlan(
        entry: entry,
        nodes: [lineNode(
            symbol: symbol,
            name: entry.challenge.id.rawValue,
            plane: plane,
            start: input.start,
            end: input.end
        )],
        steps: [ExactSemanticStep(
            operation: RupaCADSemanticOperationID.sketchLine.rawValue,
            created: [curve],
            primary: curve
        )],
        roles: [ExactSemanticRole(name: "segment", stepIndex: 0)]
    )
}

private func rectanglePlan(
    _ input: CADRectangleChallengeInput,
    entry: CADCatalogEntry
) throws -> ExactSemanticCasePlan {
    let symbol = ProgramNodeSymbol("rectangle")
    let profile = output(symbol, "profile", .feature)
    let plane = try CADRectangleGeometryMapping.sourcePlane(
        orientation: input.plane,
        targetCenter: input.center,
        submittedCenter: input.center,
        modelingTolerance: .standard,
        caseID: entry.challenge.id
    )
    let node = semanticNode(
        symbol,
        RupaCADSemanticOperationID.sketchRectangle,
        [
            "name": text(entry.challenge.id.rawValue),
            "plane": planeArgument(plane),
            "center": point(input.center),
            "width": length(input.width),
            "height": length(input.height),
        ]
    )
    return featurePlan(
        entry: entry,
        nodes: [node],
        steps: [ExactSemanticStep(
            operation: RupaCADSemanticOperationID.sketchRectangle.rawValue,
            created: [profile],
            primary: profile
        )],
        roles: [ExactSemanticRole(name: "rectangle", stepIndex: 0)]
    )
}

private func circlePlan(
    _ input: CADCircleChallengeInput,
    entry: CADCatalogEntry
) throws -> ExactSemanticCasePlan {
    let symbol = ProgramNodeSymbol("circle")
    let profile = output(symbol, "profile", .feature)
    let plane = try CADCircleGeometryMapping.sourcePlane(
        orientation: input.plane,
        targetCenter: input.center,
        submittedCenter: input.center,
        modelingTolerance: .standard,
        caseID: entry.challenge.id
    )
    let node = semanticNode(
        symbol,
        RupaCADSemanticOperationID.sketchCircle,
        [
            "name": text(entry.challenge.id.rawValue),
            "plane": planeArgument(plane),
            "center": point(input.center),
            "radius": length(input.radius),
        ]
    )
    return featurePlan(
        entry: entry,
        nodes: [node],
        steps: [ExactSemanticStep(
            operation: RupaCADSemanticOperationID.sketchCircle.rawValue,
            created: [profile],
            primary: profile
        )],
        roles: [ExactSemanticRole(name: "circle", stepIndex: 0)]
    )
}

private func anglePlan(
    _ input: CADAngleChallengeInput,
    entry: CADCatalogEntry
) throws -> ExactSemanticCasePlan {
    let firstSymbol = ProgramNodeSymbol("first-line")
    let secondSymbol = ProgramNodeSymbol("second-line")
    let first = output(firstSymbol, "curve", .feature)
    let second = output(secondSymbol, "curve", .feature)
    let plane = try CADAngleGeometryMapping.sourcePlane(
        orientation: input.plane,
        intersection: input.intersection,
        modelingTolerance: .standard,
        caseID: entry.challenge.id
    )
    return featurePlan(
        entry: entry,
        nodes: [
            lineNode(
                symbol: firstSymbol,
                name: "\(entry.challenge.id.rawValue).first-line",
                plane: plane,
                start: input.intersection,
                end: endpoint(
                    from: input.intersection,
                    direction: input.firstDirection,
                    length: input.firstLength
                )
            ),
            lineNode(
                symbol: secondSymbol,
                name: "\(entry.challenge.id.rawValue).second-line",
                plane: plane,
                start: input.intersection,
                end: endpoint(
                    from: input.intersection,
                    direction: input.secondDirection,
                    length: input.secondLength
                )
            ),
        ],
        steps: [
            ExactSemanticStep(
                operation: RupaCADSemanticOperationID.sketchLine.rawValue,
                created: [first],
                primary: first
            ),
            ExactSemanticStep(
                operation: RupaCADSemanticOperationID.sketchLine.rawValue,
                created: [second],
                primary: second
            ),
        ],
        roles: [
            ExactSemanticRole(name: "first-line", stepIndex: 0),
            ExactSemanticRole(name: "second-line", stepIndex: 1),
        ]
    )
}

private func boxPlan(
    _ input: CADBoxChallengeInput,
    entry: CADCatalogEntry
) -> ExactSemanticCasePlan {
    let symbol = ProgramNodeSymbol("box")
    let profile = output(symbol, "profile", .feature)
    let body = output(symbol, "body", .sourceBody(role: .body))
    return featurePlan(
        entry: entry,
        nodes: [boxNode(symbol: symbol, name: entry.challenge.id.rawValue, input: input)],
        steps: [ExactSemanticStep(
            operation: RupaCADSemanticOperationID.solidBox.rawValue,
            created: [profile, body],
            primary: body
        )],
        roles: [ExactSemanticRole(name: "solid", stepIndex: 0)]
    )
}

private func cylinderPlan(
    _ input: CADCylinderChallengeInput,
    entry: CADCatalogEntry
) -> ExactSemanticCasePlan {
    let symbol = ProgramNodeSymbol("cylinder")
    let profile = output(symbol, "profile", .feature)
    let body = output(symbol, "body", .sourceBody(role: .body))
    return featurePlan(
        entry: entry,
        nodes: [cylinderNode(
            symbol: symbol,
            name: entry.challenge.id.rawValue,
            input: input
        )],
        steps: [ExactSemanticStep(
            operation: RupaCADSemanticOperationID.solidCylinder.rawValue,
            created: [profile, body],
            primary: body
        )],
        roles: [ExactSemanticRole(name: "solid", stepIndex: 0)]
    )
}

private func constraintPlan(
    _ input: CADConstraintChallengeInput,
    entry: CADCatalogEntry
) throws -> ExactSemanticCasePlan {
    let symbol = ProgramNodeSymbol("constraint")
    let sketch = output(symbol, "sketch", .feature)
    let (orientation, anchor): (CADSketchPlane, CADPoint3D)
    switch input.first {
    case .line(let line):
        (orientation, anchor) = (line.plane, line.start)
    case .circle(let circle):
        (orientation, anchor) = (circle.plane, circle.center)
    }
    let plane = try CADLineGeometryMapping.sourcePlane(
        orientation: orientation,
        anchor: anchor,
        modelingTolerance: .standard,
        caseID: entry.challenge.id
    )
    var entities = [geometryArgument(input.first)]
    if let second = input.second {
        entities.append(geometryArgument(second))
    }
    let node = semanticNode(
        symbol,
        RupaCADSemanticOperationID.sketchConstrained,
        [
            "name": text(entry.challenge.id.rawValue),
            "plane": planeArgument(plane),
            "entities": .array(entities),
            "relations": .array([try relationArgument(input)]),
        ]
    )
    return featurePlan(
        entry: entry,
        nodes: [node],
        steps: [ExactSemanticStep(
            operation: RupaCADSemanticOperationID.sketchConstrained.rawValue,
            created: [sketch],
            primary: sketch
        )],
        roles: [ExactSemanticRole(name: "relation", stepIndex: 0)]
    )
}

@MainActor
private func transformPlan(
    _ input: CADTransformChallengeInput,
    entry: CADCatalogEntry
) throws -> ExactSemanticCasePlan {
    let seed = try CADTransformGeometryMapping.seed(
        projection: CADTransformChallengeProjection.decode(entry.challenge)
    )
    let symbol = ProgramNodeSymbol("transform")
    let source = SemanticSourceReference.sceneNode(seed.sceneNodeID)
    let node = semanticNode(
        symbol,
        RupaCADSemanticOperationID.sceneTransform,
        [
            "scene": .existing(source),
            "translation": point(input.translation),
            "axisPoint": point(input.axisPoint),
            "rotationAxis": direction(input.rotationAxis),
            "rotation": angle(input.rotation),
        ]
    )
    let expected = try CADTransformGeometryMapping.localTransform(
        submission: CADTransformSubmission(
            translation: input.translation,
            axisPoint: input.axisPoint,
            rotationAxis: input.rotationAxis,
            rotation: input.rotation
        ),
        caseID: entry.challenge.id
    )
    return ExactSemanticCasePlan(
        document: seed.document,
        context: SemanticCompilationContext(existingSourceReferences: [source]),
        program: SemanticProgram(schemaVersion: .current, nodes: [node]),
        evidence: .transform(sceneNodeID: seed.sceneNodeID, expected: expected)
    )
}

private func compoundPlan(
    _ input: CADCompoundChallengeInput,
    entry: CADCatalogEntry
) throws -> ExactSemanticCasePlan {
    var nodes: [SemanticProgramNode] = []
    var steps: [ExactSemanticStep] = []
    var roles: [ExactSemanticRole] = []
    var requested: [SemanticOutputReference] = []
    for (index, member) in input.members.enumerated() {
        let symbol = ProgramNodeSymbol("member-\(index)")
        let profile = output(symbol, "profile", .feature)
        let body = output(symbol, "body", .sourceBody(role: .body))
        switch member.primitive {
        case .box:
            guard let box = member.box else {
                throw ExactSemanticCaseError.invalidCase(
                    "Compound member \(member.role) has no box input."
                )
            }
            nodes.append(boxNode(symbol: symbol, name: member.role, input: box))
        case .cylinder:
            guard let cylinder = member.cylinder else {
                throw ExactSemanticCaseError.invalidCase(
                    "Compound member \(member.role) has no cylinder input."
                )
            }
            nodes.append(cylinderNode(symbol: symbol, name: member.role, input: cylinder))
        }
        steps.append(ExactSemanticStep(
            operation: member.primitive == .box
                ? RupaCADSemanticOperationID.solidBox.rawValue
                : RupaCADSemanticOperationID.solidCylinder.rawValue,
            created: [profile, body],
            primary: body
        ))
        roles.append(ExactSemanticRole(name: member.role, stepIndex: index))
        requested.append(contentsOf: [profile, body])
    }
    return ExactSemanticCasePlan(
        document: .empty(named: entry.challenge.id.rawValue),
        context: SemanticCompilationContext(),
        program: SemanticProgram(
            schemaVersion: .current,
            nodes: nodes,
            requestedOutputs: requested
        ),
        evidence: .feature(steps: steps, roles: roles)
    )
}

private func spherePlan(
    _ input: CADSphereChallengeInput,
    entry: CADCatalogEntry
) -> ExactSemanticCasePlan {
    let symbol = ProgramNodeSymbol("sphere")
    let body = output(symbol, "body", .sourceBody(role: .body))
    let node = semanticNode(
        symbol,
        RupaCADSemanticOperationID.solidSphere,
        [
            "name": text(entry.challenge.id.rawValue),
            "center": point(input.center),
            "radius": length(input.radius),
        ]
    )
    return ExactSemanticCasePlan(
        document: .empty(named: entry.challenge.id.rawValue),
        context: SemanticCompilationContext(),
        program: SemanticProgram(
            schemaVersion: .current,
            nodes: [node],
            requestedOutputs: [body]
        ),
        evidence: .sphere(body: body)
    )
}

private func featurePlan(
    entry: CADCatalogEntry,
    nodes: [SemanticProgramNode],
    steps: [ExactSemanticStep],
    roles: [ExactSemanticRole]
) -> ExactSemanticCasePlan {
    ExactSemanticCasePlan(
        document: .empty(named: entry.challenge.id.rawValue),
        context: SemanticCompilationContext(),
        program: SemanticProgram(
            schemaVersion: .current,
            nodes: nodes,
            requestedOutputs: steps.flatMap(\.created)
        ),
        evidence: .feature(steps: steps, roles: roles)
    )
}

private func validateExactSemanticCase(
    _ entry: CADCatalogEntry,
    plan: ExactSemanticCasePlan,
    initial: ProjectViewSnapshot,
    commit: ProjectSemanticProgramCommit
) throws {
    guard commit.telemetry.execution.stepCount == plan.program.nodes.count else {
        throw ExactSemanticCaseError.invalidCase(
            "The prepared program did not execute every compiled semantic node exactly once."
        )
    }
    switch (entry.input, plan.evidence) {
    case let (.line(expected), .feature(steps, roles)):
        let evidence = try featureEvidence(steps: steps, roles: roles, outputs: commit.outputs)
        _ = try CADLineOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            bindings: evidence.bindings,
            stepResults: evidence.steps,
            snapshot: commit.view
        )
    case let (.rectangle(expected), .feature(steps, roles)):
        let evidence = try featureEvidence(steps: steps, roles: roles, outputs: commit.outputs)
        _ = try CADRectangleOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            bindings: evidence.bindings,
            stepResults: evidence.steps,
            snapshot: commit.view
        )
    case let (.circle(expected), .feature(steps, roles)):
        let evidence = try featureEvidence(steps: steps, roles: roles, outputs: commit.outputs)
        _ = try CADCircleOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            bindings: evidence.bindings,
            stepResults: evidence.steps,
            snapshot: commit.view
        )
    case let (.angle(expected), .feature(steps, roles)):
        let evidence = try featureEvidence(steps: steps, roles: roles, outputs: commit.outputs)
        _ = try CADAngleOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            bindings: evidence.bindings,
            stepResults: evidence.steps,
            snapshot: commit.view
        )
    case let (.box(expected), .feature(steps, roles)):
        let evidence = try featureEvidence(steps: steps, roles: roles, outputs: commit.outputs)
        _ = try CADBoxOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            bindings: evidence.bindings,
            stepResults: evidence.steps,
            snapshot: commit.view
        )
    case let (.cylinder(expected), .feature(steps, roles)):
        let evidence = try featureEvidence(steps: steps, roles: roles, outputs: commit.outputs)
        _ = try CADCylinderOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            bindings: evidence.bindings,
            stepResults: evidence.steps,
            snapshot: commit.view
        )
    case let (.constraint(expected), .feature(steps, roles)):
        let evidence = try featureEvidence(steps: steps, roles: roles, outputs: commit.outputs)
        _ = try CADConstraintOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            bindings: evidence.bindings,
            stepResults: evidence.steps,
            snapshot: commit.view
        )
    case let (.compound(expected), .feature(steps, roles)):
        let evidence = try featureEvidence(steps: steps, roles: roles, outputs: commit.outputs)
        _ = try CADCompoundOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            bindings: evidence.bindings,
            stepResults: evidence.steps,
            snapshot: commit.view
        )
    case let (.transform(expected), .transform(sceneNodeID, transform)):
        _ = try CADTransformOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            sceneNodeID: sceneNodeID,
            expectedTransform: transform,
            initial: initial,
            final: commit.view
        )
    case let (.sphere(expected), .sphere(body)):
        let observed = try observeSphere(body: body, outputs: commit.outputs, snapshot: commit.view)
        _ = try CADSphereOracle.evaluate(
            expected: expected,
            challenge: entry.challenge,
            observed: observed,
            modelingTolerance: commit.view.document.document.modelingSettings.tolerance
        )
    default:
        throw ExactSemanticCaseError.invalidCase(
            "The semantic plan evidence does not match the fixed catalog category."
        )
    }
}

private func featureEvidence(
    steps: [ExactSemanticStep],
    roles: [ExactSemanticRole],
    outputs: [ProjectSemanticOutputBinding]
) throws -> (bindings: CADOutputRoleBindings, steps: [CADCandidateStepResult]) {
    let results = try steps.enumerated().map { index, step in
        let created = try step.created.map { try featureID(for: $0, in: outputs).description }
        let primary = try featureID(for: step.primary, in: outputs).description
        return CADCandidateStepResult(
            stepIndex: index,
            operation: step.operation,
            status: .published,
            primaryFeatureID: primary,
            createdFeatureIDs: created
        )
    }
    let bindings = CADOutputRoleBindings(bindings: roles.map {
        CADOutputRoleBinding(
            role: $0.name,
            stepIndex: $0.stepIndex,
            selector: .primary
        )
    })
    return (bindings, results)
}

private func featureID(
    for reference: SemanticOutputReference,
    in outputs: [ProjectSemanticOutputBinding]
) throws -> FeatureID {
    guard let value = outputs.first(where: { $0.output == reference })?.value else {
        throw ExactSemanticCaseError.missingOutput(
            "\(reference.node.rawValue).\(reference.output.rawValue)"
        )
    }
    switch value {
    case .feature(let featureID):
        return featureID
    case .body(let featureID, _, _):
        return featureID
    case .sceneNode, .componentDefinition, .componentInstance, .patternArraySource:
        throw ExactSemanticCaseError.invalidCase(
            "A feature evidence output resolved to a non-feature identity."
        )
    }
}

private func bodyIdentity(
    for reference: SemanticOutputReference,
    in outputs: [ProjectSemanticOutputBinding]
) throws -> (featureID: FeatureID, bodyID: BodyID) {
    guard let value = outputs.first(where: { $0.output == reference })?.value else {
        throw ExactSemanticCaseError.missingOutput(
            "\(reference.node.rawValue).\(reference.output.rawValue)"
        )
    }
    guard case .body(let featureID, _, let bodyID) = value else {
        throw ExactSemanticCaseError.invalidCase(
            "The sphere output did not resolve to an evaluated source body."
        )
    }
    return (featureID, bodyID)
}

private func observeSphere(
    body reference: SemanticOutputReference,
    outputs: [ProjectSemanticOutputBinding],
    snapshot: ProjectViewSnapshot
) throws -> CADSphereObservedGeometry {
    let identity = try bodyIdentity(for: reference, in: outputs)
    let document = snapshot.document.document
    guard let feature = document.cadDocument.designGraph.nodes[identity.featureID],
          case .primitive(let primitive) = feature.operation,
          case .sphere(let sphere) = primitive.definition else {
        throw ExactSemanticCaseError.invalidCase(
            "The committed sphere body has no analytic sphere source primitive."
        )
    }
    guard let evaluation = snapshot.cadInteraction else {
        throw ExactSemanticCaseError.invalidCase(
            "The committed sphere has no immutable CAD evaluation."
        )
    }
    let brep = evaluation.evaluatedDocument.brep
    guard let body = brep.bodies[identity.bodyID] else {
        throw ExactSemanticCaseError.invalidCase(
            "The committed sphere output points to a missing evaluated body."
        )
    }
    let radius = try document.cadDocument.parameters.resolvedValue(for: sphere.radius)
    let center = sphere.placement.origin
    let analyticSurfaceCount = brep.faces.values.reduce(into: 0) { count, face in
        guard let surface = brep.geometry.surfaces[face.surfaceID],
              case .analytic(.sphere(let surfaceCenter, let surfaceRadius)) = surface,
              surfaceCenter == center,
              surfaceRadius == radius.value else {
            return
        }
        count += 1
    }
    let sourceIsAuthoritative = document.hasAuthoritativeCADSource
        && document.productMetadata.sceneNodes.values.contains { node in
            node.reference == .body(identity.featureID)
                && node.object?.category == .body
                && node.object?.geometryRole == .solid
                && node.object?.typeID == .sphere
        }
    return CADSphereObservedGeometry(
        representation: analyticSurfaceCount == brep.faces.count ? .analyticSphere : .unknown,
        center: CADPoint3D(x: center.x, y: center.y, z: center.z, unit: .meter),
        radiusMeters: radius.value,
        bodyCount: brep.bodies.count,
        faceCount: brep.faces.count,
        edgeCount: brep.edges.count,
        vertexCount: brep.vertices.count,
        analyticSurfaceCount: analyticSurfaceCount,
        featureCount: document.cadDocument.designGraph.nodes.count,
        volumeCubicMeters: try brep.volume(
            of: identity.bodyID,
            tolerance: document.modelingSettings.tolerance
        ),
        isClosed: body.kind == .solid,
        sourceIsAuthoritative: sourceIsAuthoritative
    )
}

private func lineNode(
    symbol: ProgramNodeSymbol,
    name: String,
    plane: SketchPlane,
    start: CADPoint3D,
    end: CADPoint3D
) -> SemanticProgramNode {
    semanticNode(
        symbol,
        RupaCADSemanticOperationID.sketchLine,
        [
            "name": text(name),
            "plane": planeArgument(plane),
            "start": point(start),
            "end": point(end),
        ]
    )
}

private func boxNode(
    symbol: ProgramNodeSymbol,
    name: String,
    input: CADBoxChallengeInput
) -> SemanticProgramNode {
    semanticNode(
        symbol,
        RupaCADSemanticOperationID.solidBox,
        [
            "name": text(name),
            "origin": point(input.origin),
            "width": length(input.width),
            "depth": length(input.depth),
            "height": length(input.height),
        ]
    )
}

private func cylinderNode(
    symbol: ProgramNodeSymbol,
    name: String,
    input: CADCylinderChallengeInput
) -> SemanticProgramNode {
    semanticNode(
        symbol,
        RupaCADSemanticOperationID.solidCylinder,
        [
            "name": text(name),
            "baseCenter": point(input.baseCenter),
            "axis": direction(input.axis),
            "radius": length(input.radius),
            "height": length(input.depth),
        ]
    )
}

private func semanticNode(
    _ symbol: ProgramNodeSymbol,
    _ operation: DomainCapabilityID,
    _ arguments: [String: SemanticArgument]
) -> SemanticProgramNode {
    SemanticProgramNode(
        symbol: symbol,
        invocation: SemanticOperationInvocation(
            operationID: operation,
            operationVersion: RupaCADDomain.operationVersion,
            arguments: Dictionary(uniqueKeysWithValues: arguments.map {
                (SemanticArgumentID($0.key), $0.value)
            })
        )
    )
}

private func output(
    _ node: ProgramNodeSymbol,
    _ name: String,
    _ kind: SemanticReferenceKind
) -> SemanticOutputReference {
    SemanticOutputReference(
        node: node,
        output: SemanticOutputID(name),
        kind: kind
    )
}

private func text(_ value: String) -> SemanticArgument {
    .literal(.text(value))
}

private func point(_ value: CADPoint3D) -> SemanticArgument {
    let meters = value.meters
    return .literal(.point(SemanticPoint3D(
        x: meters.x,
        y: meters.y,
        z: meters.z,
        unit: .meter
    )))
}

private func direction(_ value: CADDirection3D) -> SemanticArgument {
    .literal(.direction(SemanticDirection3D(x: value.x, y: value.y, z: value.z)))
}

private func length(_ value: CADLength) -> SemanticArgument {
    .literal(.number(value.meters, unit: .meter))
}

private func angle(_ value: CADAngle) -> SemanticArgument {
    .literal(.number(value.radians * 180.0 / .pi, unit: .degree))
}

private func integer(_ value: Int) -> SemanticArgument {
    .literal(.integer(Int64(value)))
}

private func planeArgument(_ plane: SketchPlane) -> SemanticArgument {
    let semantic: SemanticPlane
    switch plane {
    case .xy:
        semantic = SemanticPlane(
            origin: SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter),
            normal: SemanticDirection3D(x: 0, y: 0, z: 1)
        )
    case .yz:
        semantic = SemanticPlane(
            origin: SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter),
            normal: SemanticDirection3D(x: 1, y: 0, z: 0)
        )
    case .zx:
        semantic = SemanticPlane(
            origin: SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter),
            normal: SemanticDirection3D(x: 0, y: 1, z: 0)
        )
    case .plane(let value):
        semantic = SemanticPlane(
            origin: SemanticPoint3D(
                x: value.origin.x,
                y: value.origin.y,
                z: value.origin.z,
                unit: .meter
            ),
            normal: SemanticDirection3D(
                x: value.normal.x,
                y: value.normal.y,
                z: value.normal.z
            )
        )
    }
    return .literal(.plane(semantic))
}

private func endpoint(
    from start: CADPoint3D,
    direction: CADDirection3D,
    length: CADLength
) -> CADPoint3D {
    let start = start.meters
    let scale = length.meters / direction.length
    return CADPoint3D(
        x: start.x + direction.x * scale,
        y: start.y + direction.y * scale,
        z: start.z + direction.z * scale,
        unit: .meter
    )
}

private func geometryArgument(_ geometry: CADConstraintGeometryInput) -> SemanticArgument {
    switch geometry {
    case .line(let input):
        return object([
            ("kind", text("line")),
            ("start", point(input.start)),
            ("end", point(input.end)),
        ])
    case .circle(let input):
        return object([
            ("kind", text("circle")),
            ("center", point(input.center)),
            ("radius", length(input.radius)),
        ])
    }
}

private func relationArgument(_ input: CADConstraintChallengeInput) throws -> SemanticArgument {
    switch input.relation {
    case .horizontal, .vertical:
        return object([
            ("kind", text(input.relation.rawValue)),
            ("entity", integer(0)),
        ])
    case .parallel, .perpendicular, .equalLength, .concentric, .equalRadius:
        guard input.second != nil else {
            throw ExactSemanticCaseError.invalidCase(
                "A two-entity relation has no second catalog geometry."
            )
        }
        return object([
            ("kind", text(input.relation.rawValue)),
            ("firstEntity", integer(0)),
            ("secondEntity", integer(1)),
        ])
    case .coincident:
        let endpoints = try coincidentEndpoints(input)
        return object([
            ("kind", text(input.relation.rawValue)),
            ("firstEntity", integer(0)),
            ("firstEndpoint", text(endpoints.first)),
            ("secondEntity", integer(1)),
            ("secondEndpoint", text(endpoints.second)),
        ])
    }
}

private func coincidentEndpoints(
    _ input: CADConstraintChallengeInput
) throws -> (first: String, second: String) {
    guard case .line(let first) = input.first,
          let secondGeometry = input.second,
          case .line(let second) = secondGeometry else {
        throw ExactSemanticCaseError.invalidCase(
            "Coincident catalog input does not contain two lines."
        )
    }
    let firstEndpoints = [("start", first.start), ("end", first.end)]
    let secondEndpoints = [("start", second.start), ("end", second.end)]
    let matches = firstEndpoints.flatMap { firstEndpoint in
        secondEndpoints.compactMap { secondEndpoint -> (String, String)? in
            guard firstEndpoint.1.meters == secondEndpoint.1.meters else { return nil }
            return (firstEndpoint.0, secondEndpoint.0)
        }
    }
    guard matches.count == 1, let match = matches.first else {
        throw ExactSemanticCaseError.invalidCase(
            "Coincident catalog input does not have exactly one shared endpoint pair."
        )
    }
    return match
}

private func object(_ entries: [(String, SemanticArgument)]) -> SemanticArgument {
    .object(entries.sorted { $0.0 < $1.0 }.map {
        SemanticArgumentObjectEntry(key: $0.0, value: $0.1)
    })
}

private func exactSemanticLimits() -> SemanticProgramLimitPolicy {
    SemanticProgramLimitPolicy(
        maximumDecodedValueCount: 4_096,
        maximumDecodedNestingDepth: 32,
        maximumNodeCount: 32,
        maximumEdgeCount: 64,
        maximumParameterCount: 32,
        maximumRequestedOutputCount: 128,
        maximumLocalOutputReferenceCount: 64,
        maximumExpressionCount: 64,
        maximumExpressionDepth: 16,
        maximumExpressionWork: 512,
        maximumLoweredCommandCount: 32,
        maximumExpandedSourceWork: 512,
        maximumPreparedInputSlotCount: 128,
        maximumPreparedOutputSlotCount: 128,
        resultLimits: SemanticResultLimits(
            maximumRequestedOutputCount: 128,
            maximumDiagnosticRecordCount: 128,
            maximumDiagnosticScalarCount: 512,
            maximumDiagnosticStringUTF8ByteCount: 16_384,
            maximumTelemetryRecordCount: 256,
            maximumTelemetryScalarCount: 2_048,
            maximumTelemetryStringUTF8ByteCount: 16_384
        )
    )
}

private func exactSemanticResultBudget() -> ProjectSemanticResultBudget {
    ProjectSemanticResultBudget(
        maximumRequestedOutputCount: 128,
        maximumEvaluatedBodyLookupCount: 128,
        maximumDiagnosticRecordCount: 128,
        maximumDiagnosticScalarCount: 512,
        maximumDiagnosticStringUTF8ByteCount: 16_384,
        maximumTelemetryRecordCount: 256,
        maximumTelemetryScalarCount: 2_048,
        maximumTelemetryStringUTF8ByteCount: 16_384
    )
}
