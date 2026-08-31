import Foundation
import RupaAutomation
import RupaCore
import RupaDomainFoundation
import Synchronization
import Testing

@Test
func semanticCompilerNormalizesDirectAndEquivalentOneNodeProgram() throws {
    let operationID: DomainCapabilityID = "fixture.line"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let lowerer = FixtureLowerer(operationID: operationID, operationVersion: version)
    let registry = try SemanticOperationRegistry(registrations: [
        SemanticOperationRegistration(
            descriptor: fixtureDescriptor(operationID: operationID, version: version),
            lowerer: lowerer
        )
    ])
    let compiler = DefaultSemanticProgramCompiler(registry: registry)
    let invocation = SemanticOperationInvocation(
        operationID: operationID,
        operationVersion: version,
        arguments: [
            SemanticArgumentID("length"): .literal(.number(0.25, unit: .meter))
        ]
    )

    let direct = try compiler.compile(
        SemanticDirectRequest(
            schemaVersion: .current,
            invocation: invocation,
            requestedOutputs: [SemanticOutputID("feature")]
        ),
        context: SemanticCompilationContext(),
        limits: fixtureLimits()
    )
    let program = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("direct"),
                invocation: invocation
            )
        ],
        requestedOutputs: [
            SemanticOutputReference(
                node: ProgramNodeSymbol("direct"),
                output: SemanticOutputID("feature"),
                kind: .feature
            )
        ]
    )
    let composed = try compiler.compile(
        program,
        context: SemanticCompilationContext(),
        limits: fixtureLimits()
    )

    #expect(direct.preparedProgram.steps.count == composed.preparedProgram.steps.count)
    #expect(direct.preparedProgram.steps[0].inputs == composed.preparedProgram.steps[0].inputs)
    #expect(direct.preparedProgram.steps[0].outputs == composed.preparedProgram.steps[0].outputs)
    #expect(direct.telemetry.loweredCommandCount == 1)
    #expect(composed.requestedOutputs.count == 1)
    #expect(direct.requestedOutputs == composed.requestedOutputs)
}

@Test
func semanticCompilerDoesNotInferUnrequestedDirectOutputs() throws {
    let operationID: DomainCapabilityID = "fixture.direct-output-selection"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let compiler = try fixtureCompiler(
        operationID: operationID,
        version: version,
        descriptor: fixtureDescriptor(operationID: operationID, version: version)
    )

    let result = try compiler.compile(
        SemanticDirectRequest(
            schemaVersion: .current,
            invocation: fixtureInvocation(operationID: operationID, version: version),
            requestedOutputs: []
        ),
        context: SemanticCompilationContext(),
        limits: fixtureLimits()
    )

    #expect(result.requestedOutputs.isEmpty)
    #expect(result.resultCharge.requestedOutputCount == 0)
    #expect(result.resultCharge.telemetryRecordCount == 1)
    #expect(result.resultCharge.telemetryScalarCount == 12)
}

@Test
func semanticCompilerRequiresExplicitSupportedSchema() throws {
    let operationID: DomainCapabilityID = "fixture.schema"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let unsupported = SemanticProgramSchemaVersion(major: 2, minor: 0, patch: 0)
    let counter = InvocationCounter()
    let compiler = try fixtureCompiler(
        operationID: operationID,
        version: version,
        descriptor: fixtureDescriptor(operationID: operationID, version: version),
        invocationCount: counter
    )

    do {
        _ = try compiler.compile(
            SemanticDirectRequest(
                schemaVersion: unsupported,
                invocation: fixtureInvocation(operationID: operationID, version: version)
            ),
            context: SemanticCompilationContext(),
            limits: fixtureLimits()
        )
        Issue.record("Unsupported direct schema unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .unsupportedSchema(unsupported))
    }

    do {
        _ = try compiler.compile(
            SemanticProgram(
                schemaVersion: unsupported,
                nodes: [
                    SemanticProgramNode(
                        symbol: ProgramNodeSymbol("node"),
                        invocation: fixtureInvocation(operationID: operationID, version: version)
                    )
                ]
            ),
            context: SemanticCompilationContext(),
            limits: fixtureLimits()
        )
        Issue.record("Unsupported program schema unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .unsupportedSchema(unsupported))
    }
    #expect(counter.value == 0)
}

@Test
func semanticRegistryAcceptsOutputlessZeroWorkAndRejectsInvalidDescriptors() throws {
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let outputlessID: DomainCapabilityID = "fixture.outputless"
    let counter = InvocationCounter()
    let outputlessDescriptor = SemanticOperationDescriptor(
        operationID: outputlessID,
        version: version,
        outputs: [],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 0,
        resultEstimate: .zero
    )
    let compiler = try fixtureCompiler(
        operationID: outputlessID,
        version: version,
        descriptor: outputlessDescriptor,
        invocationCount: counter
    )
    let result = try compiler.compile(
        SemanticDirectRequest(
            schemaVersion: .current,
            invocation: SemanticOperationInvocation(
                operationID: outputlessID,
                operationVersion: version,
                arguments: [:]
            )
        ),
        context: SemanticCompilationContext(),
        limits: fixtureLimits(maximumExpandedSourceWork: 0)
    )
    #expect(counter.value == 1)
    #expect(result.preparedProgram.estimatedGeneratedSourceWork == 0)
    #expect(result.preparedProgram.estimatedOutputSlotCount == 0)

    let invalidWorkID: DomainCapabilityID = "fixture.invalid-zero-work"
    let invalidWorkDescriptor = SemanticOperationDescriptor(
        operationID: invalidWorkID,
        version: version,
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("feature"),
                type: .feature,
                selector: .feature(index: 0)
            )
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 0,
        resultEstimate: .zero
    )
    do {
        _ = try fixtureRegistry(
            descriptor: invalidWorkDescriptor,
            lowerer: FixtureLowerer(
                operationID: invalidWorkID,
                operationVersion: version
            )
        )
        Issue.record("Output-producing zero-work descriptor unexpectedly registered.")
    } catch let error as SemanticOperationRegistryError {
        #expect(error == .invalidSourceWork)
    }

    let duplicateSelectorID: DomainCapabilityID = "fixture.duplicate-selector"
    let duplicateSelectorDescriptor = SemanticOperationDescriptor(
        operationID: duplicateSelectorID,
        version: version,
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("first"),
                type: .feature,
                selector: .feature(index: 0)
            ),
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("second"),
                type: .feature,
                selector: .feature(index: 0)
            )
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 1,
        resultEstimate: .zero
    )
    do {
        _ = try fixtureRegistry(
            descriptor: duplicateSelectorDescriptor,
            lowerer: FixtureLowerer(
                operationID: duplicateSelectorID,
                operationVersion: version
            )
        )
        Issue.record("Duplicate output selector unexpectedly registered.")
    } catch let error as SemanticOperationRegistryError {
        #expect(error == .duplicateOutputSelector(.feature(index: 0)))
    }
}

@Test
func semanticCompilerOrdersReorderedDAGDeterministically() throws {
    let operationID: DomainCapabilityID = "fixture.node"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let registry = try fixtureRegistry(
        descriptor: fixtureGraphDescriptor(operationID: operationID, version: version),
        lowerer: FixtureLowerer(operationID: operationID, operationVersion: version)
    )
    let compiler = DefaultSemanticProgramCompiler(registry: registry)
    let first = SemanticProgramNode(
        symbol: ProgramNodeSymbol("a"),
        invocation: SemanticOperationInvocation(
            operationID: operationID,
            operationVersion: version,
            arguments: [SemanticArgumentID("length"): .literal(.number(1, unit: .meter))]
        )
    )
    let second = SemanticProgramNode(
        symbol: ProgramNodeSymbol("b"),
        invocation: SemanticOperationInvocation(
            operationID: operationID,
            operationVersion: version,
            arguments: [SemanticArgumentID("length"): .literal(.number(2, unit: .meter))]
        )
    )
    let consumer = SemanticProgramNode(
        symbol: ProgramNodeSymbol("c"),
        invocation: SemanticOperationInvocation(
            operationID: operationID,
            operationVersion: version,
            arguments: [
                SemanticArgumentID("length"): .literal(.number(3, unit: .meter)),
                SemanticArgumentID("dependency"): .local(
                    SemanticOutputReference(
                        node: ProgramNodeSymbol("a"),
                        output: SemanticOutputID("feature"),
                        kind: .feature
                    )
                )
            ]
        )
    )
    let outputs = [
        SemanticOutputReference(
            node: ProgramNodeSymbol("c"),
            output: SemanticOutputID("feature"),
            kind: .feature
        )
    ]
    let limits = fixtureLimits()
    let left = try compiler.compile(
        SemanticProgram(schemaVersion: .current, nodes: [consumer, second, first], requestedOutputs: outputs),
        context: SemanticCompilationContext(),
        limits: limits
    )
    let right = try compiler.compile(
        SemanticProgram(schemaVersion: .current, nodes: [first, consumer, second], requestedOutputs: outputs),
        context: SemanticCompilationContext(),
        limits: limits
    )

    #expect(left.orderedNodeSymbols == [ProgramNodeSymbol("a"), ProgramNodeSymbol("b"), ProgramNodeSymbol("c")])
    #expect(left.orderedNodeSymbols == right.orderedNodeSymbols)
    #expect(left.preparedProgram.steps.map(\.estimatedGeneratedSourceWork) == right.preparedProgram.steps.map(\.estimatedGeneratedSourceWork))
    #expect(left.preparedProgram.steps.map(\.outputs).flatMap { $0 }.map(\.id).count == 3)
    #expect(Set(left.preparedProgram.steps.map(\.outputs).flatMap { $0 }.map(\.id)).count == 3)
    guard let dependencyInput = left.preparedProgram.steps[2].inputs.first(where: {
        $0.id == PreparedAutomationSlotID("semantic-slot-v1:8#argument1#c10#dependency")
    }) else {
        Issue.record("Expected dependency input slot.")
        return
    }
    #expect(
        dependencyInput.reference
            == .local(PreparedAutomationSlotID("semantic-slot-v1:6#output1#a7#feature"))
    )
}

@Test
func semanticCompilerRejectsDirectLocalReference() throws {
    let operationID: DomainCapabilityID = "fixture.direct"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let compiler = DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(
            descriptor: fixtureDescriptor(operationID: operationID, version: version),
            lowerer: FixtureLowerer(operationID: operationID, operationVersion: version)
        )
    )
    let invocation = SemanticOperationInvocation(
        operationID: operationID,
        operationVersion: version,
        arguments: [
            SemanticArgumentID("length"): .local(
                SemanticOutputReference(
                    node: ProgramNodeSymbol("other"),
                    output: SemanticOutputID("feature"),
                    kind: .feature
                )
            )
        ]
    )

    do {
        _ = try compiler.compile(
            SemanticDirectRequest(schemaVersion: .current, invocation: invocation),
            context: SemanticCompilationContext(),
            limits: fixtureLimits()
        )
        Issue.record("Direct local reference unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .directLocalReference(SemanticArgumentID("length")))
    }
}

@Test
func semanticCompilerRejectsMalformedGraphBeforeLowering() throws {
    let operationID: DomainCapabilityID = "fixture.graph"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let descriptor = fixtureGraphDescriptor(operationID: operationID, version: version)
    let registry = try fixtureRegistry(
        descriptor: descriptor,
        lowerer: FixtureLowerer(operationID: operationID, operationVersion: version)
    )
    let compiler = DefaultSemanticProgramCompiler(registry: registry)
    let cycle = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            graphNode("a", operationID: operationID, version: version, pointsTo: "b"),
            graphNode("b", operationID: operationID, version: version, pointsTo: "a")
        ]
    )

    do {
        _ = try compiler.compile(cycle, context: SemanticCompilationContext(), limits: fixtureLimits())
        Issue.record("Cyclic graph unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        guard case .graphCycle = error else {
            Issue.record("Unexpected compiler error: \(error)")
            return
        }
    }
}

@Test
func semanticCompilerEnforcesNodeLimitAtBoundaryAndBoundaryPlusOne() throws {
    let operationID: DomainCapabilityID = "fixture.limit"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let compiler = DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(
            descriptor: fixtureDescriptor(operationID: operationID, version: version),
            lowerer: FixtureLowerer(operationID: operationID, operationVersion: version)
        )
    )
    let one = graphNode("a", operationID: operationID, version: version, pointsTo: nil)
    let two = graphNode("b", operationID: operationID, version: version, pointsTo: nil)
    let limits = fixtureLimits(maximumNodeCount: 1, maximumCommandCount: 1)

    _ = try compiler.compile(
        SemanticProgram(schemaVersion: .current, nodes: [one]),
        context: SemanticCompilationContext(),
        limits: limits
    )
    do {
        _ = try compiler.compile(
            SemanticProgram(schemaVersion: .current, nodes: [one, two]),
            context: SemanticCompilationContext(),
            limits: limits
        )
        Issue.record("Node limit boundary plus one unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .limitExceeded(metric: .nodeCount, actual: 2, maximum: 1))
    }
}

@Test
func semanticCompilerRejectsRequestedOutputBeforeLowering() throws {
    let operationID: DomainCapabilityID = "fixture.output"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let counter = InvocationCounter()
    let lowerer = CountingLowerer(
        operationID: operationID,
        operationVersion: version,
        invocationCount: counter
    )
    let compiler = DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(
            descriptor: fixtureDescriptor(operationID: operationID, version: version),
            lowerer: lowerer
        )
    )
    let invocation = fixtureInvocation(operationID: operationID, version: version)

    do {
        _ = try compiler.compile(
            SemanticDirectRequest(
                schemaVersion: .current,
                invocation: invocation,
                requestedOutputs: [SemanticOutputID("missing")]
            ),
            context: SemanticCompilationContext(),
            limits: fixtureLimits()
        )
        Issue.record("Missing direct output unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .directOutputMissing(SemanticOutputID("missing")))
    }
    #expect(counter.value == 0)

    do {
        _ = try compiler.compile(
            SemanticDirectRequest(
                schemaVersion: .current,
                invocation: invocation,
                requestedOutputs: [SemanticOutputID("feature"), SemanticOutputID("feature")]
            ),
            context: SemanticCompilationContext(),
            limits: fixtureLimits()
        )
        Issue.record("Duplicate direct output unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .duplicateDirectOutput(SemanticOutputID("feature")))
    }
    #expect(counter.value == 0)
}

@Test
func semanticCompilerResolvesExistingSourceAndRejectsReferenceFailuresBeforeLowering() throws {
    let operationID: DomainCapabilityID = "fixture.reference"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let featureID = FeatureID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let descriptor = fixtureSourceDescriptor(operationID: operationID, version: version)
    let acceptedCounter = InvocationCounter()
    let acceptedCompiler = DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(
            descriptor: descriptor,
            lowerer: CountingLowerer(
                operationID: operationID,
                operationVersion: version,
                invocationCount: acceptedCounter
            )
        )
    )
    let accepted = try acceptedCompiler.compile(
        SemanticProgram(
            schemaVersion: .current,
            nodes: [
                SemanticProgramNode(
                    symbol: ProgramNodeSymbol("source"),
                    invocation: SemanticOperationInvocation(
                        operationID: operationID,
                        operationVersion: version,
                        arguments: [
                            SemanticArgumentID("source"): .existing(.feature(featureID))
                        ]
                    )
                )
            ],
            requestedOutputs: [
                SemanticOutputReference(
                    node: ProgramNodeSymbol("source"),
                    output: SemanticOutputID("feature"),
                    kind: .feature
                )
            ]
        ),
        context: SemanticCompilationContext(
            existingSourceReferences: [.feature(featureID)]
        ),
        limits: fixtureLimits()
    )
    #expect(acceptedCounter.value == 1)
    #expect(accepted.preparedProgram.steps[0].inputs.count == 1)
    #expect(
        accepted.preparedProgram.steps[0].inputs[0].reference
            == PreparedAutomationInputReference.existing(.feature(featureID))
    )

    let unavailableCounter = InvocationCounter()
    let unavailableCompiler = DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(
            descriptor: descriptor,
            lowerer: CountingLowerer(
                operationID: operationID,
                operationVersion: version,
                invocationCount: unavailableCounter
            )
        )
    )
    let sourceProgram = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("source"),
                invocation: SemanticOperationInvocation(
                    operationID: operationID,
                    operationVersion: version,
                    arguments: [
                        SemanticArgumentID("source"): .existing(.feature(featureID))
                    ]
                )
            )
        ]
    )
    do {
        _ = try unavailableCompiler.compile(
            sourceProgram,
            context: SemanticCompilationContext(),
            limits: fixtureLimits()
        )
        Issue.record("Unavailable source unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .sourceReferenceUnavailable(.feature(featureID)))
    }
    #expect(unavailableCounter.value == 0)

    let wrongTypeCounter = InvocationCounter()
    let wrongTypeCompiler = DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(
            descriptor: descriptor,
            lowerer: CountingLowerer(
                operationID: operationID,
                operationVersion: version,
                invocationCount: wrongTypeCounter
            )
        )
    )
    let sceneID = SceneNodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    let wrongTypeProgram = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("source"),
                invocation: SemanticOperationInvocation(
                    operationID: operationID,
                    operationVersion: version,
                    arguments: [
                        SemanticArgumentID("source"): .existing(.sceneNode(sceneID))
                    ]
                )
            )
        ]
    )
    do {
        _ = try wrongTypeCompiler.compile(
            wrongTypeProgram,
            context: SemanticCompilationContext(
                existingSourceReferences: [.sceneNode(sceneID)]
            ),
            limits: fixtureLimits()
        )
        Issue.record("Wrong source reference type unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(
            error == .sourceReferenceTypeMismatch(
                node: ProgramNodeSymbol("source"),
                argument: SemanticArgumentID("source"),
                expected: .feature,
                actual: .sceneNode
            )
        )
    }
    #expect(wrongTypeCounter.value == 0)
}

@Test
func semanticCompilerValidatesStructuredValuesAndTheirLimits() throws {
    let operationID: DomainCapabilityID = "fixture.structured"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let descriptor = structuredFixtureDescriptor(operationID: operationID, version: version)
    let acceptedArguments = structuredFixtureArguments()
    let program = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("structured"),
                invocation: SemanticOperationInvocation(
                    operationID: operationID,
                    operationVersion: version,
                    arguments: acceptedArguments
                )
            )
        ]
    )
    let accepted = try fixtureCompiler(
        operationID: operationID,
        version: version,
        descriptor: descriptor
    ).compile(
        program,
        context: SemanticCompilationContext(),
        limits: fixtureLimits(
            maximumDecodedValueCount: 11,
            maximumDecodedNestingDepth: 3
        )
    )
    #expect(accepted.telemetry.decodedValueCount == 11)
    #expect(accepted.telemetry.decodedNestingDepth == 3)

    for (metric, actual, maximum, limits) in [
        (
            SemanticProgramLimitMetric.decodedValueCount,
            UInt64(11),
            UInt64(10),
            fixtureLimits(
                maximumDecodedValueCount: 10,
                maximumDecodedNestingDepth: 3
            )
        ),
        (
            SemanticProgramLimitMetric.decodedNestingDepth,
            UInt64(3),
            UInt64(2),
            fixtureLimits(
                maximumDecodedValueCount: 11,
                maximumDecodedNestingDepth: 2
            )
        )
    ] {
        let counter = InvocationCounter()
        let compiler = try fixtureCompiler(
            operationID: operationID,
            version: version,
            descriptor: descriptor,
            invocationCount: counter
        )
        try expectLimitFailure(
            compiler: compiler,
            program: program,
            limits: limits,
            metric: metric,
            actual: actual,
            maximum: maximum
        )
        #expect(counter.value == 0)
    }

    let invalidCases: [(SemanticArgumentID, SemanticArgument)] = [
        (
            SemanticArgumentID("direction"),
            .literal(.direction(SemanticDirection3D(x: 0, y: 0, z: 0)))
        ),
        (
            SemanticArgumentID("plane"),
            .literal(
                .plane(
                    SemanticPlane(
                        origin: SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter),
                        normal: SemanticDirection3D(x: 0, y: 0, z: 0)
                    )
                )
            )
        ),
        (
            SemanticArgumentID("transform"),
            .literal(
                .transform(
                    SemanticTransform(
                        translation: SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter),
                        axisPoint: SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter),
                        rotationAxis: SemanticDirection3D(x: 0, y: 0, z: 0),
                        rotation: SemanticAngle(value: 90, unit: .degree)
                    )
                )
            )
        )
    ]
    for (invalidID, invalidArgument) in invalidCases {
        var arguments = acceptedArguments
        arguments[invalidID] = invalidArgument
        let counter = InvocationCounter()
        let compiler = try fixtureCompiler(
            operationID: operationID,
            version: version,
            descriptor: descriptor,
            invocationCount: counter
        )
        do {
            _ = try compiler.compile(
                SemanticProgram(
                    schemaVersion: .current,
                    nodes: [
                        SemanticProgramNode(
                            symbol: ProgramNodeSymbol("structured"),
                            invocation: SemanticOperationInvocation(
                                operationID: operationID,
                                operationVersion: version,
                                arguments: arguments
                            )
                        )
                    ]
                ),
                context: SemanticCompilationContext(),
                limits: fixtureLimits()
            )
            Issue.record("Invalid structured geometry unexpectedly compiled.")
        } catch let error as SemanticCompilationError {
            #expect(
                error == .invalidArgument(
                    node: ProgramNodeSymbol("structured"),
                    argument: invalidID
                )
            )
        }
        #expect(counter.value == 0)
    }
}

@Test
func semanticCompilerPreservesNestedReferenceSlotsAndEnforcesPreparedSlotLimits() throws {
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let producerID: DomainCapabilityID = "fixture.scene-producer"
    let consumerID: DomainCapabilityID = "fixture.component-consumer"
    let producerDescriptor = sceneProducerFixtureDescriptor(
        operationID: producerID,
        version: version
    )
    let consumerDescriptor = sceneConsumerFixtureDescriptor(
        operationID: consumerID,
        version: version
    )
    let firstRoot = SemanticOutputReference(
        node: ProgramNodeSymbol("root-a"),
        output: SemanticOutputID("scene"),
        kind: .sceneNode
    )
    let secondRoot = SemanticOutputReference(
        node: ProgramNodeSymbol("root-b"),
        output: SemanticOutputID("scene"),
        kind: .sceneNode
    )
    let program = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("assembly"),
                invocation: SemanticOperationInvocation(
                    operationID: consumerID,
                    operationVersion: version,
                    arguments: [
                        SemanticArgumentID("rootScenes"): .array([
                            .local(firstRoot),
                            .local(secondRoot)
                        ])
                    ]
                )
            ),
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("root-b"),
                invocation: SemanticOperationInvocation(
                    operationID: producerID,
                    operationVersion: version,
                    arguments: [:]
                )
            ),
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("root-a"),
                invocation: SemanticOperationInvocation(
                    operationID: producerID,
                    operationVersion: version,
                    arguments: [:]
                )
            )
        ]
    )
    let capture = ResolvedArgumentCapture()
    let compiler = DefaultSemanticProgramCompiler(
        registry: try SemanticOperationRegistry(registrations: [
            SemanticOperationRegistration(
                descriptor: producerDescriptor,
                lowerer: FixtureLowerer(
                    operationID: producerID,
                    operationVersion: version
                )
            ),
            SemanticOperationRegistration(
                descriptor: consumerDescriptor,
                lowerer: CapturingLowerer(
                    operationID: consumerID,
                    operationVersion: version,
                    capture: capture
                )
            )
        ])
    )
    let result = try compiler.compile(
        program,
        context: SemanticCompilationContext(),
        limits: fixtureLimits(
            maximumNodeCount: 3,
            maximumCommandCount: 3,
            maximumPreparedInputSlotCount: 2,
            maximumPreparedOutputSlotCount: 3
        )
    )
    #expect(
        result.orderedNodeSymbols
            == [ProgramNodeSymbol("root-a"), ProgramNodeSymbol("root-b"), ProgramNodeSymbol("assembly")]
    )
    let firstInputSlot = PreparedAutomationSlotID(
        "semantic-slot-v1:8#argument8#assembly10#rootScenes5#index1#0"
    )
    let secondInputSlot = PreparedAutomationSlotID(
        "semantic-slot-v1:8#argument8#assembly10#rootScenes5#index1#1"
    )
    let firstOutputSlot = PreparedAutomationSlotID(
        "semantic-slot-v1:6#output6#root-a5#scene"
    )
    let secondOutputSlot = PreparedAutomationSlotID(
        "semantic-slot-v1:6#output6#root-b5#scene"
    )
    #expect(
        result.preparedProgram.steps[2].inputs
            == [
                PreparedAutomationInputSlot(
                    id: firstInputSlot,
                    expectedKind: .sceneNode,
                    reference: .local(firstOutputSlot)
                ),
                PreparedAutomationInputSlot(
                    id: secondInputSlot,
                    expectedKind: .sceneNode,
                    reference: .local(secondOutputSlot)
                )
            ]
    )
    guard case .array(let capturedRoots)? = capture.arguments?[SemanticArgumentID("rootScenes")],
          capturedRoots.count == 2,
          case .local(let capturedFirst, let capturedFirstSlot) = capturedRoots[0],
          case .local(let capturedSecond, let capturedSecondSlot) = capturedRoots[1] else {
        Issue.record("Expected two captured nested local references.")
        return
    }
    #expect(capturedFirst == firstRoot)
    #expect(capturedSecond == secondRoot)
    #expect(capturedFirstSlot == firstInputSlot)
    #expect(capturedSecondSlot == secondInputSlot)

    func makeCountingCompiler(_ counter: InvocationCounter) throws -> DefaultSemanticProgramCompiler {
        try DefaultSemanticProgramCompiler(
            registry: SemanticOperationRegistry(registrations: [
                SemanticOperationRegistration(
                    descriptor: producerDescriptor,
                    lowerer: CountingLowerer(
                        operationID: producerID,
                        operationVersion: version,
                        invocationCount: counter
                    )
                ),
                SemanticOperationRegistration(
                    descriptor: consumerDescriptor,
                    lowerer: CountingLowerer(
                        operationID: consumerID,
                        operationVersion: version,
                        invocationCount: counter
                    )
                )
            ])
        )
    }

    for (metric, actual, maximum, inputMaximum, outputMaximum) in [
        (SemanticProgramLimitMetric.preparedInputSlotCount, UInt64(2), UInt64(1), 1, 3),
        (SemanticProgramLimitMetric.preparedOutputSlotCount, UInt64(3), UInt64(2), 2, 2)
    ] {
        let counter = InvocationCounter()
        try expectLimitFailure(
            compiler: makeCountingCompiler(counter),
            program: program,
            limits: fixtureLimits(
                maximumNodeCount: 3,
                maximumCommandCount: 3,
                maximumPreparedInputSlotCount: inputMaximum,
                maximumPreparedOutputSlotCount: outputMaximum
            ),
            metric: metric,
            actual: actual,
            maximum: maximum
        )
        #expect(counter.value == 0)
    }
}

@Test
func semanticCompilerUsesCollisionFreeSlotsForOutputsAndNestedObjectPaths() throws {
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let firstID: DomainCapabilityID = "fixture.collision.first"
    let secondID: DomainCapabilityID = "fixture.collision.second"
    let objectID: DomainCapabilityID = "fixture.collision.object"
    let sceneID = SceneNodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000099")!)
    let descriptors = [
        collisionOutputFixtureDescriptor(
            operationID: firstID,
            version: version,
            outputID: SemanticOutputID("b:output:c")
        ),
        collisionOutputFixtureDescriptor(
            operationID: secondID,
            version: version,
            outputID: SemanticOutputID("c")
        ),
        objectReferenceFixtureDescriptor(operationID: objectID, version: version)
    ]
    let registry = try SemanticOperationRegistry(
        registrations: zip(descriptors, [firstID, secondID, objectID]).map { descriptor, operationID in
            SemanticOperationRegistration(
                descriptor: descriptor,
                lowerer: FixtureLowerer(
                    operationID: operationID,
                    operationVersion: version
                )
            )
        }
    )
    let program = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("a"),
                invocation: SemanticOperationInvocation(
                    operationID: firstID,
                    operationVersion: version,
                    arguments: [:]
                )
            ),
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("a:output:b"),
                invocation: SemanticOperationInvocation(
                    operationID: secondID,
                    operationVersion: version,
                    arguments: [:]
                )
            ),
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("object"),
                invocation: SemanticOperationInvocation(
                    operationID: objectID,
                    operationVersion: version,
                    arguments: [
                        SemanticArgumentID("payload"): .object([
                            SemanticArgumentObjectEntry(
                                key: "a:index:0",
                                value: .existing(.sceneNode(sceneID))
                            ),
                            SemanticArgumentObjectEntry(
                                key: "a",
                                value: .array([.existing(.sceneNode(sceneID))])
                            )
                        ])
                    ]
                )
            )
        ]
    )
    let result = try DefaultSemanticProgramCompiler(registry: registry).compile(
        program,
        context: SemanticCompilationContext(
            existingSourceReferences: [.sceneNode(sceneID)]
        ),
        limits: fixtureLimits(
            maximumNodeCount: 3,
            maximumCommandCount: 3,
            maximumPreparedInputSlotCount: 2,
            maximumPreparedOutputSlotCount: 3
        )
    )
    let outputSlotIDs = result.preparedProgram.steps.flatMap(\.outputs).map(\.id)
    #expect(outputSlotIDs.count == 3)
    #expect(Set(outputSlotIDs).count == 3)
    guard let objectStep = result.preparedProgram.steps.first(where: {
        $0.inputs.count == 2
    }) else {
        Issue.record("Expected object-reference prepared step.")
        return
    }
    #expect(Set(objectStep.inputs.map(\.id)).count == 2)
    #expect(objectStep.inputs.allSatisfy { $0.reference == .existing(.sceneNode(sceneID)) })
}

@Test
func semanticCompilerRejectsMalformedLocalReferencesBeforeLowering() throws {
    let operationID: DomainCapabilityID = "fixture.local"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let cases: [(String, SemanticProgram, SemanticCompilationError)] = [
        (
            "missing-node",
            SemanticProgram(schemaVersion: .current, nodes: [graphNode("a", operationID: operationID, version: version, pointsTo: "missing")]),
            .localReferenceNodeMissing(
                node: ProgramNodeSymbol("a"),
                reference: ProgramNodeSymbol("missing")
            )
        ),
        (
            "missing-output",
            SemanticProgram(
                schemaVersion: .current,
                nodes: [
                    SemanticProgramNode(
                        symbol: ProgramNodeSymbol("a"),
                        invocation: SemanticOperationInvocation(
                            operationID: operationID,
                            operationVersion: version,
                            arguments: [
                                SemanticArgumentID("length"): .literal(.number(1, unit: .meter)),
                                SemanticArgumentID("dependency"): .local(
                                    SemanticOutputReference(
                                        node: ProgramNodeSymbol("b"),
                                        output: SemanticOutputID("missing"),
                                        kind: .feature
                                    )
                                )
                            ]
                        )
                    ),
                    graphNode("b", operationID: operationID, version: version, pointsTo: nil)
                ]
            ),
            .localReferenceOutputMissing(
                node: ProgramNodeSymbol("b"),
                output: SemanticOutputID("missing")
            )
        ),
        (
            "self",
            SemanticProgram(schemaVersion: .current, nodes: [graphNode("a", operationID: operationID, version: version, pointsTo: "a")]),
            .localReferenceSelf(node: ProgramNodeSymbol("a"))
        ),
        (
            "wrong-kind",
            SemanticProgram(schemaVersion: .current, nodes: [graphNode("a", operationID: operationID, version: version, pointsTo: "b", kind: .sceneNode), graphNode("b", operationID: operationID, version: version, pointsTo: nil)]),
            .localReferenceKindMismatch(
                node: ProgramNodeSymbol("a"),
                argument: SemanticArgumentID("dependency"),
                expected: .feature,
                actual: .sceneNode
            )
        )
    ]

    for (_, program, expected) in cases {
        let counter = InvocationCounter()
        let compiler = DefaultSemanticProgramCompiler(
            registry: try fixtureRegistry(
                descriptor: fixtureGraphDescriptor(operationID: operationID, version: version),
                lowerer: CountingLowerer(
                    operationID: operationID,
                    operationVersion: version,
                    invocationCount: counter
                )
            )
        )
        do {
            _ = try compiler.compile(program, context: SemanticCompilationContext(), limits: fixtureLimits())
            Issue.record("Malformed local reference unexpectedly compiled.")
        } catch let error as SemanticCompilationError {
            #expect(error == expected)
        }
        #expect(counter.value == 0)
    }
}

@Test
func semanticCompilerRejectsIneligibleRouteAndEffectBeforeLowering() throws {
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let cases: [(DomainCapabilityID, SemanticOperationDescriptor, SemanticCompilationError)] = [
        (
            "fixture.workspace",
            fixtureDescriptor(
                operationID: "fixture.workspace",
                version: version,
                route: .workspace
            ),
            .routeIneligible(node: ProgramNodeSymbol("node"), route: .workspace)
        ),
        (
            "fixture.mesh",
            fixtureDescriptor(
                operationID: "fixture.mesh",
                version: version,
                effect: .meshMutation
            ),
            .effectIneligible(node: ProgramNodeSymbol("node"), effect: .meshMutation)
        )
    ]

    for (operationID, descriptor, expected) in cases {
        let counter = InvocationCounter()
        let compiler = DefaultSemanticProgramCompiler(
            registry: try fixtureRegistry(
                descriptor: descriptor,
                lowerer: CountingLowerer(
                    operationID: operationID,
                    operationVersion: version,
                    invocationCount: counter
                )
            )
        )
        do {
            _ = try compiler.compile(
                SemanticProgram(schemaVersion: .current, nodes: [
                    SemanticProgramNode(
                        symbol: ProgramNodeSymbol("node"),
                        invocation: fixtureInvocation(operationID: operationID, version: version)
                    )
                ]),
                context: SemanticCompilationContext(),
                limits: fixtureLimits()
            )
            Issue.record("Ineligible operation unexpectedly compiled.")
        } catch let error as SemanticCompilationError {
            #expect(error == expected)
        }
        #expect(counter.value == 0)
    }
}

@Test
func semanticCompilerChecksExpressionUnitsAndCancellationWithoutFallback() throws {
    let operationID: DomainCapabilityID = "fixture.expression"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let counter = InvocationCounter()
    let compiler = DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(
            descriptor: fixtureDescriptor(operationID: operationID, version: version),
            lowerer: CountingLowerer(
                operationID: operationID,
                operationVersion: version,
                invocationCount: counter
            )
        )
    )
    let incompatible = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("expression"),
                invocation: SemanticOperationInvocation(
                    operationID: operationID,
                    operationVersion: version,
                    arguments: [
                        SemanticArgumentID("length"): .expression(
                            .add(
                                .literal(.number(1, unit: .meter)),
                                .literal(.number(1, unit: .degree))
                            )
                        )
                    ]
                )
            )
        ]
    )
    do {
        _ = try compiler.compile(incompatible, context: SemanticCompilationContext(), limits: fixtureLimits())
        Issue.record("Incompatible expression units unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .arithmeticInvalid)
    }
    #expect(counter.value == 0)

    let zeroNumerator = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("zero-numerator"),
                invocation: SemanticOperationInvocation(
                    operationID: operationID,
                    operationVersion: version,
                    arguments: [
                        SemanticArgumentID("length"): .expression(
                            .divide(
                                .literal(.number(0, unit: .meter)),
                                .literal(.number(2, unit: .unitless))
                            )
                        )
                    ]
                )
            )
        ]
    )
    _ = try compiler.compile(
        zeroNumerator,
        context: SemanticCompilationContext(),
        limits: fixtureLimits()
    )
    #expect(counter.value == 1)

    let zeroDivisor = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("zero-divisor"),
                invocation: SemanticOperationInvocation(
                    operationID: operationID,
                    operationVersion: version,
                    arguments: [
                        SemanticArgumentID("length"): .expression(
                            .divide(
                                .literal(.number(1, unit: .meter)),
                                .literal(.number(0, unit: .unitless))
                            )
                        )
                    ]
                )
            )
        ]
    )
    do {
        _ = try compiler.compile(
            zeroDivisor,
            context: SemanticCompilationContext(),
            limits: fixtureLimits()
        )
        Issue.record("Division by zero unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .arithmeticInvalid)
    }
    #expect(counter.value == 1)

    let cancelled = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("cancelled"),
                invocation: fixtureInvocation(operationID: operationID, version: version)
            )
        ]
    )
    do {
        _ = try compiler.compile(
            cancelled,
            context: SemanticCompilationContext(),
            limits: fixtureLimits(),
            cancellation: AlwaysCancelled()
        )
        Issue.record("Cancelled program unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .cancelled)
    }
    #expect(counter.value == 1)
}

@Test
func semanticCompilerReportsLoweringFailureWithoutRawAutomationFallback() throws {
    let operationID: DomainCapabilityID = "fixture.lowering-failure"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let counter = InvocationCounter()
    let compiler = DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(
            descriptor: fixtureDescriptor(operationID: operationID, version: version),
            lowerer: ThrowingLowerer(
                operationID: operationID,
                operationVersion: version,
                invocationCount: counter
            )
        )
    )
    do {
        _ = try compiler.compile(
            SemanticProgram(schemaVersion: .current, nodes: [
                SemanticProgramNode(
                    symbol: ProgramNodeSymbol("node"),
                    invocation: fixtureInvocation(operationID: operationID, version: version)
                )
            ]),
            context: SemanticCompilationContext(),
            limits: fixtureLimits()
        )
        Issue.record("Lowering failure unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        guard case .loweringFailed(
            let node,
            let failedOperationID,
            let code,
            let message
        ) = error else {
            Issue.record("Unexpected compiler error: \(error)")
            return
        }
        #expect(node == ProgramNodeSymbol("node"))
        #expect(failedOperationID == operationID)
        #expect(code == "semantic.loweringFailed")
        #expect(message == "failed")
    }
    #expect(counter.value == 1)
}

@Test
func semanticCompilerPreservesTypedLoweringFailureCodeAndMessage() throws {
    let operationID: DomainCapabilityID = "fixture.typed-lowering-failure"
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let compiler = DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(
            descriptor: fixtureDescriptor(operationID: operationID, version: version),
            lowerer: TypedThrowingLowerer(
                operationID: operationID,
                operationVersion: version
            )
        )
    )

    do {
        _ = try compiler.compile(
            SemanticProgram(schemaVersion: .current, nodes: [
                SemanticProgramNode(
                    symbol: ProgramNodeSymbol("node"),
                    invocation: fixtureInvocation(operationID: operationID, version: version)
                )
            ]),
            context: SemanticCompilationContext(),
            limits: fixtureLimits()
        )
        Issue.record("Typed lowering failure unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        guard case .loweringFailed(
            let node,
            let failedOperationID,
            let code,
            let message
        ) = error else {
            Issue.record("Unexpected compiler error: \(error)")
            return
        }
        #expect(node == ProgramNodeSymbol("node"))
        #expect(failedOperationID == operationID)
        #expect(code == "cad.invalidArgument")
        #expect(message == "Fixture argument is invalid.")
    }
}

@Test
func semanticCompilerRejectsAggregateDynamicWorkBeforeAnyLowering() throws {
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let firstID: DomainCapabilityID = "fixture.dynamic-work.first"
    let secondID: DomainCapabilityID = "fixture.dynamic-work.second"
    let firstEstimationCount = InvocationCounter()
    let firstLoweringCount = InvocationCounter()
    let secondEstimationCount = InvocationCounter()
    let secondLoweringCount = InvocationCounter()
    let registry = try SemanticOperationRegistry(registrations: [
        SemanticOperationRegistration(
            descriptor: fixtureDescriptor(operationID: firstID, version: version),
            lowerer: DynamicWorkLowerer(
                operationID: firstID,
                operationVersion: version,
                generatedSourceWork: 2,
                estimationCount: firstEstimationCount,
                loweringCount: firstLoweringCount
            )
        ),
        SemanticOperationRegistration(
            descriptor: fixtureDescriptor(operationID: secondID, version: version),
            lowerer: DynamicWorkLowerer(
                operationID: secondID,
                operationVersion: version,
                generatedSourceWork: 100,
                estimationCount: secondEstimationCount,
                loweringCount: secondLoweringCount
            )
        )
    ])
    let compiler = DefaultSemanticProgramCompiler(registry: registry)
    let program = SemanticProgram(schemaVersion: .current, nodes: [
        SemanticProgramNode(
            symbol: ProgramNodeSymbol("first"),
            invocation: fixtureInvocation(operationID: firstID, version: version)
        ),
        SemanticProgramNode(
            symbol: ProgramNodeSymbol("second"),
            invocation: fixtureInvocation(operationID: secondID, version: version)
        )
    ])

    do {
        _ = try compiler.compile(
            program,
            context: SemanticCompilationContext(),
            limits: fixtureLimits(
                maximumNodeCount: 2,
                maximumCommandCount: 2,
                maximumExpandedSourceWork: 50
            )
        )
        Issue.record("Over-limit dynamic work unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(
            error == .limitExceeded(
                metric: .expandedSourceWork,
                actual: 102,
                maximum: 50
            )
        )
    }
    #expect(firstEstimationCount.value == 1)
    #expect(secondEstimationCount.value == 1)
    #expect(firstLoweringCount.value == 0)
    #expect(secondLoweringCount.value == 0)
}

@Test
func semanticCompilerChecksEverySemanticLimitAtBoundaryAndBoundaryPlusOne() throws {
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let literalOperationID: DomainCapabilityID = "fixture.limit.literal"
    let literalProgram = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("node"),
                invocation: fixtureInvocation(
                    operationID: literalOperationID,
                    version: version
                )
            )
        ],
        requestedOutputs: [
            SemanticOutputReference(
                node: ProgramNodeSymbol("node"),
                output: SemanticOutputID("feature"),
                kind: .feature
            )
        ]
    )

    let literalCases: [
        (SemanticProgramLimitPolicy, SemanticProgramLimitPolicy, SemanticProgramLimitMetric, UInt64, UInt64)
    ] = [
        (
            fixtureLimits(maximumDecodedValueCount: 1),
            fixtureLimits(maximumDecodedValueCount: 0),
            .decodedValueCount,
            1,
            0
        ),
        (
            fixtureLimits(maximumNodeCount: 1),
            fixtureLimits(maximumNodeCount: 0),
            .nodeCount,
            1,
            0
        ),
        (
            fixtureLimits(maximumRequestedOutputCount: 1),
            fixtureLimits(maximumRequestedOutputCount: 0),
            .requestedOutputCount,
            1,
            0
        ),
        (
            fixtureLimits(maximumCommandCount: 1),
            fixtureLimits(maximumCommandCount: 0),
            .loweredCommandCount,
            1,
            0
        ),
        (
            fixtureLimits(maximumExpandedSourceWork: 1),
            fixtureLimits(maximumExpandedSourceWork: 0),
            .expandedSourceWork,
            1,
            0
        )
    ]

    for (boundary, plusOneFailure, metric, actual, maximum) in literalCases {
        let boundaryCounter = InvocationCounter()
        let boundaryCompiler = try fixtureCompiler(
            operationID: literalOperationID,
            version: version,
            descriptor: fixtureDescriptor(operationID: literalOperationID, version: version),
            invocationCount: boundaryCounter
        )
        _ = try boundaryCompiler.compile(
            literalProgram,
            context: SemanticCompilationContext(),
            limits: boundary
        )

        let failureCounter = InvocationCounter()
        let failureCompiler = try fixtureCompiler(
            operationID: literalOperationID,
            version: version,
            descriptor: fixtureDescriptor(operationID: literalOperationID, version: version),
            invocationCount: failureCounter
        )
        try expectLimitFailure(
            compiler: failureCompiler,
            program: literalProgram,
            limits: plusOneFailure,
            metric: metric,
            actual: actual,
            maximum: maximum
        )
        #expect(failureCounter.value == 0)
    }

    let parameterOperationID: DomainCapabilityID = "fixture.limit.parameter"
    let parameterID = ProgramParameterID("length")
    let parameterProgram = SemanticProgram(
        schemaVersion: .current,
        parameters: [parameterID: .number(1, unit: .meter)],
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("node"),
                invocation: SemanticOperationInvocation(
                    operationID: parameterOperationID,
                    operationVersion: version,
                    arguments: [
                        SemanticArgumentID("length"): .parameter(parameterID)
                    ]
                )
            )
        ]
    )
    let parameterBoundary = fixtureLimits(maximumDecodedValueCount: 2, maximumParameterCount: 1)
    _ = try fixtureCompiler(
        operationID: parameterOperationID,
        version: version,
        descriptor: fixtureDescriptor(operationID: parameterOperationID, version: version)
    ).compile(parameterProgram, context: SemanticCompilationContext(), limits: parameterBoundary)
    let parameterCounter = InvocationCounter()
    let parameterCompiler = try fixtureCompiler(
        operationID: parameterOperationID,
        version: version,
        descriptor: fixtureDescriptor(operationID: parameterOperationID, version: version),
        invocationCount: parameterCounter
    )
    try expectLimitFailure(
        compiler: parameterCompiler,
        program: parameterProgram,
        limits: fixtureLimits(maximumDecodedValueCount: 2, maximumParameterCount: 0),
        metric: .parameterCount,
        actual: 1,
        maximum: 0
    )
    #expect(parameterCounter.value == 0)

    let expressionOperationID: DomainCapabilityID = "fixture.limit.expression"
    let expression = BoundedScalarExpression.add(
        .literal(.number(1, unit: .meter)),
        .literal(.number(2, unit: .meter))
    )
    let expressionProgram = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("node"),
                invocation: SemanticOperationInvocation(
                    operationID: expressionOperationID,
                    operationVersion: version,
                    arguments: [
                        SemanticArgumentID("length"): .expression(expression)
                    ]
                )
            )
        ]
    )
    let expressionBoundary = fixtureLimits(
        maximumDecodedValueCount: 4,
        maximumDecodedNestingDepth: 2,
        maximumExpressionCount: 3,
        maximumExpressionDepth: 2,
        maximumExpressionWork: 3
    )
    _ = try fixtureCompiler(
        operationID: expressionOperationID,
        version: version,
        descriptor: fixtureDescriptor(operationID: expressionOperationID, version: version)
    ).compile(expressionProgram, context: SemanticCompilationContext(), limits: expressionBoundary)
    for (metric, actual, maximum, limits) in [
        (
            SemanticProgramLimitMetric.decodedNestingDepth,
            UInt64(2),
            UInt64(1),
            fixtureLimits(maximumDecodedValueCount: 4, maximumDecodedNestingDepth: 1)
        ),
        (
            SemanticProgramLimitMetric.expressionCount,
            UInt64(3),
            UInt64(2),
            fixtureLimits(maximumDecodedValueCount: 4, maximumExpressionCount: 2)
        ),
        (
            SemanticProgramLimitMetric.expressionDepth,
            UInt64(2),
            UInt64(1),
            fixtureLimits(maximumDecodedValueCount: 4, maximumExpressionDepth: 1)
        ),
        (
            SemanticProgramLimitMetric.expressionWork,
            UInt64(3),
            UInt64(2),
            fixtureLimits(maximumDecodedValueCount: 4, maximumExpressionWork: 2)
        )
    ] {
        let counter = InvocationCounter()
        let compiler = try fixtureCompiler(
            operationID: expressionOperationID,
            version: version,
            descriptor: fixtureDescriptor(operationID: expressionOperationID, version: version),
            invocationCount: counter
        )
        try expectLimitFailure(
            compiler: compiler,
            program: expressionProgram,
            limits: limits,
            metric: metric,
            actual: actual,
            maximum: maximum
        )
        #expect(counter.value == 0)
    }

    let graphOperationID: DomainCapabilityID = "fixture.limit.graph"
    let graphProgram = SemanticProgram(
        schemaVersion: .current,
        nodes: [
            graphNode("a", operationID: graphOperationID, version: version, pointsTo: nil),
            graphNode("b", operationID: graphOperationID, version: version, pointsTo: "a")
        ]
    )
    let graphBoundary = fixtureLimits(
        maximumDecodedValueCount: 3,
        maximumNodeCount: 2,
        maximumEdgeCount: 1,
        maximumLocalOutputReferenceCount: 1
    )
    _ = try fixtureCompiler(
        operationID: graphOperationID,
        version: version,
        descriptor: fixtureGraphDescriptor(operationID: graphOperationID, version: version)
    ).compile(graphProgram, context: SemanticCompilationContext(), limits: graphBoundary)
    for (metric, actual, maximum, limits) in [
        (
            SemanticProgramLimitMetric.edgeCount,
            UInt64(1),
            UInt64(0),
            fixtureLimits(maximumDecodedValueCount: 3, maximumNodeCount: 2, maximumEdgeCount: 0)
        ),
        (
            SemanticProgramLimitMetric.localOutputReferenceCount,
            UInt64(1),
            UInt64(0),
            fixtureLimits(maximumDecodedValueCount: 3, maximumNodeCount: 2, maximumLocalOutputReferenceCount: 0)
        )
    ] {
        let counter = InvocationCounter()
        let compiler = try fixtureCompiler(
            operationID: graphOperationID,
            version: version,
            descriptor: fixtureGraphDescriptor(operationID: graphOperationID, version: version),
            invocationCount: counter
        )
        try expectLimitFailure(
            compiler: compiler,
            program: graphProgram,
            limits: limits,
            metric: metric,
            actual: actual,
            maximum: maximum
        )
        #expect(counter.value == 0)
    }
}

@Test
func semanticCompilerChecksEveryResultChargeFieldAndCheckedOverflow() throws {
    let version = SemanticOperationVersion(major: 1, minor: 0, patch: 0)
    let operationID: DomainCapabilityID = "fixture.result-charge"
    let fields: [ResultChargeField] = [
        .requestedOutputCount,
        .diagnosticRecordCount,
        .diagnosticScalarCount,
        .diagnosticStringUTF8ByteCount,
        .telemetryRecordCount,
        .telemetryScalarCount,
        .telemetryStringUTF8ByteCount
    ]

    for field in fields {
        let estimate = resultEstimate(field: field, value: 1)
        let expectedValue = baseResultChargeValue(field) + 1
        let output: [SemanticOutputReference] = field == .requestedOutputCount
            ? [
                SemanticOutputReference(
                    node: ProgramNodeSymbol("node"),
                    output: SemanticOutputID("feature"),
                    kind: .feature
                )
            ]
            : []
        let program = SemanticProgram(
            schemaVersion: .current,
            nodes: [
                SemanticProgramNode(
                    symbol: ProgramNodeSymbol("node"),
                    invocation: fixtureInvocation(
                        operationID: operationID,
                        version: version
                    )
                )
            ],
            requestedOutputs: output
        )
        let boundaryLimits = fixtureLimits(
            resultLimits: resultLimits(field: field, maximum: expectedValue)
        )
        let boundary = try fixtureCompiler(
            operationID: operationID,
            version: version,
            descriptor: fixtureDescriptor(
                operationID: operationID,
                version: version,
                resultEstimate: estimate
            ),
            resultEstimate: estimate
        ).compile(program, context: SemanticCompilationContext(), limits: boundaryLimits)
        #expect(resultChargeValue(boundary.resultCharge, field: field) == expectedValue)

        let counter = InvocationCounter()
        let failureCompiler = try fixtureCompiler(
            operationID: operationID,
            version: version,
            descriptor: fixtureDescriptor(
                operationID: operationID,
                version: version,
                resultEstimate: estimate
            ),
            invocationCount: counter,
            resultEstimate: estimate
        )
        try expectLimitFailure(
            compiler: failureCompiler,
            program: program,
            limits: fixtureLimits(
                resultLimits: resultLimits(field: field, maximum: expectedValue - 1)
            ),
            metric: field.metric,
            actual: expectedValue,
            maximum: expectedValue - 1
        )
        #expect(counter.value == 0)
    }

    // Requested-output count is bounded by the host collection count and is
    // covered by the boundary/+1 loop above. Each additive estimate field is
    // independently checked for UInt64 overflow before any lowerer runs.
    let additiveFields: [ResultChargeField] = [
        .diagnosticRecordCount,
        .diagnosticScalarCount,
        .diagnosticStringUTF8ByteCount,
        .telemetryRecordCount,
        .telemetryScalarCount,
        .telemetryStringUTF8ByteCount
    ]
    for field in additiveFields {
        let overflowEstimate = resultEstimate(field: field, value: UInt64.max)
        let overflowOperationID = DomainCapabilityID(
            rawValue: "fixture.result-overflow.\(String(describing: field))"
        )
        let overflowProgram = SemanticProgram(schemaVersion: .current, nodes: [
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("a"),
                invocation: fixtureInvocation(
                    operationID: overflowOperationID,
                    version: version
                )
            ),
            SemanticProgramNode(
                symbol: ProgramNodeSymbol("b"),
                invocation: fixtureInvocation(
                    operationID: overflowOperationID,
                    version: version
                )
            )
        ])
        let overflowCounter = InvocationCounter()
        let overflowCompiler = try fixtureCompiler(
            operationID: overflowOperationID,
            version: version,
            descriptor: fixtureDescriptor(
                operationID: overflowOperationID,
                version: version,
                resultEstimate: overflowEstimate
            ),
            invocationCount: overflowCounter,
            resultEstimate: overflowEstimate
        )
        try expectLimitFailure(
            compiler: overflowCompiler,
            program: overflowProgram,
            limits: fixtureLimits(
                maximumNodeCount: 2,
                maximumCommandCount: 2,
                resultLimits: resultLimits(
                    field: field,
                    maximum: UInt64.max
                )
            ),
            metric: field.metric,
            actual: UInt64.max,
            maximum: UInt64.max
        )
        #expect(overflowCounter.value == 0)
    }
}

private final class ResolvedArgumentCapture: Sendable {
    private let storage = Mutex<[SemanticArgumentID: SemanticResolvedArgument]?>(nil)

    var arguments: [SemanticArgumentID: SemanticResolvedArgument]? {
        storage.withLock { $0 }
    }

    func record(_ arguments: [SemanticArgumentID: SemanticResolvedArgument]) {
        storage.withLock { $0 = arguments }
    }
}

private struct CapturingLowerer: SemanticOperationLowerer {
    let operationID: DomainCapabilityID
    let operationVersion: SemanticOperationVersion
    let resultEstimate: SemanticOperationResultEstimate = .zero
    let capture: ResolvedArgumentCapture

    func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
        capture.record(request.arguments)
        return fixtureLoweredOperation(request)
    }
}

private final class InvocationCounter: Sendable {
    private let storage = Mutex(0)

    var value: Int {
        storage.withLock { $0 }
    }

    func increment() {
        storage.withLock { $0 += 1 }
    }
}

private enum ResultChargeField: Equatable {
    case requestedOutputCount
    case diagnosticRecordCount
    case diagnosticScalarCount
    case diagnosticStringUTF8ByteCount
    case telemetryRecordCount
    case telemetryScalarCount
    case telemetryStringUTF8ByteCount

    var metric: SemanticProgramLimitMetric {
        switch self {
        case .requestedOutputCount:
            .resultRequestedOutputCount
        case .diagnosticRecordCount:
            .resultDiagnosticRecordCount
        case .diagnosticScalarCount:
            .resultDiagnosticScalarCount
        case .diagnosticStringUTF8ByteCount:
            .resultDiagnosticStringUTF8ByteCount
        case .telemetryRecordCount:
            .resultTelemetryRecordCount
        case .telemetryScalarCount:
            .resultTelemetryScalarCount
        case .telemetryStringUTF8ByteCount:
            .resultTelemetryStringUTF8ByteCount
        }
    }
}

private func resultEstimate(
    field: ResultChargeField,
    value: UInt64
) -> SemanticOperationResultEstimate {
    SemanticOperationResultEstimate(
        diagnosticRecordCount: field == .diagnosticRecordCount ? value : 0,
        diagnosticScalarCount: field == .diagnosticScalarCount ? value : 0,
        diagnosticStringUTF8ByteCount: field == .diagnosticStringUTF8ByteCount ? value : 0,
        telemetryRecordCount: field == .telemetryRecordCount ? value : 0,
        telemetryScalarCount: field == .telemetryScalarCount ? value : 0,
        telemetryStringUTF8ByteCount: field == .telemetryStringUTF8ByteCount ? value : 0
    )
}

private func resultLimits(
    field: ResultChargeField,
    maximum: UInt64
) -> SemanticResultLimits {
    SemanticResultLimits(
        maximumRequestedOutputCount: field == .requestedOutputCount ? maximum : 16,
        maximumDiagnosticRecordCount: field == .diagnosticRecordCount ? maximum : 16,
        maximumDiagnosticScalarCount: field == .diagnosticScalarCount ? maximum : 64,
        maximumDiagnosticStringUTF8ByteCount: field == .diagnosticStringUTF8ByteCount ? maximum : 1024,
        maximumTelemetryRecordCount: field == .telemetryRecordCount ? maximum : 16,
        maximumTelemetryScalarCount: field == .telemetryScalarCount ? maximum : 128,
        maximumTelemetryStringUTF8ByteCount: field == .telemetryStringUTF8ByteCount ? maximum : 1024
    )
}

private func resultChargeValue(
    _ charge: SemanticResultCharge,
    field: ResultChargeField
) -> UInt64 {
    switch field {
    case .requestedOutputCount:
        charge.requestedOutputCount
    case .diagnosticRecordCount:
        charge.diagnosticRecordCount
    case .diagnosticScalarCount:
        charge.diagnosticScalarCount
    case .diagnosticStringUTF8ByteCount:
        charge.diagnosticStringUTF8ByteCount
    case .telemetryRecordCount:
        charge.telemetryRecordCount
    case .telemetryScalarCount:
        charge.telemetryScalarCount
    case .telemetryStringUTF8ByteCount:
        charge.telemetryStringUTF8ByteCount
    }
}

private func baseResultChargeValue(_ field: ResultChargeField) -> UInt64 {
    switch field {
    case .telemetryRecordCount:
        1
    case .telemetryScalarCount:
        12
    case .requestedOutputCount, .diagnosticRecordCount, .diagnosticScalarCount,
         .diagnosticStringUTF8ByteCount, .telemetryStringUTF8ByteCount:
        0
    }
}

private struct CountingLowerer: SemanticOperationLowerer {
    let operationID: DomainCapabilityID
    let operationVersion: SemanticOperationVersion
    let resultEstimate: SemanticOperationResultEstimate
    let invocationCount: InvocationCounter

    init(
        operationID: DomainCapabilityID,
        operationVersion: SemanticOperationVersion,
        resultEstimate: SemanticOperationResultEstimate = .zero,
        invocationCount: InvocationCounter
    ) {
        self.operationID = operationID
        self.operationVersion = operationVersion
        self.resultEstimate = resultEstimate
        self.invocationCount = invocationCount
    }

    func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
        invocationCount.increment()
        return fixtureLoweredOperation(request)
    }
}

private struct ThrowingLowerer: SemanticOperationLowerer {
    let operationID: DomainCapabilityID
    let operationVersion: SemanticOperationVersion
    let resultEstimate: SemanticOperationResultEstimate
    let invocationCount: InvocationCounter

    init(
        operationID: DomainCapabilityID,
        operationVersion: SemanticOperationVersion,
        resultEstimate: SemanticOperationResultEstimate = .zero,
        invocationCount: InvocationCounter
    ) {
        self.operationID = operationID
        self.operationVersion = operationVersion
        self.resultEstimate = resultEstimate
        self.invocationCount = invocationCount
    }

    func lower(_: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
        invocationCount.increment()
        throw FixtureLoweringError.failed
    }
}

private enum FixtureLoweringError: Error {
    case failed
}

private struct TypedThrowingLowerer: SemanticOperationLowerer {
    let operationID: DomainCapabilityID
    let operationVersion: SemanticOperationVersion
    let resultEstimate: SemanticOperationResultEstimate = .zero

    func lower(_: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
        throw TypedFixtureLoweringError()
    }
}

private struct TypedFixtureLoweringError: SemanticOperationLoweringFailure {
    let semanticErrorCode: DomainCapabilityErrorCode = "cad.invalidArgument"
    let semanticErrorMessage = "Fixture argument is invalid."
}

private struct DynamicWorkLowerer: SemanticOperationLowerer {
    let operationID: DomainCapabilityID
    let operationVersion: SemanticOperationVersion
    let resultEstimate: SemanticOperationResultEstimate = .zero
    let generatedSourceWork: UInt64
    let estimationCount: InvocationCounter
    let loweringCount: InvocationCounter

    func estimateGeneratedSourceWork(
        for _: SemanticLoweringRequest
    ) throws -> UInt64 {
        estimationCount.increment()
        return generatedSourceWork
    }

    func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
        loweringCount.increment()
        return fixtureLoweredOperation(
            request,
            estimatedGeneratedSourceWork: generatedSourceWork
        )
    }
}

private struct AlwaysCancelled: SemanticCompilationCancellation {
    let isCancelled = true
}

private func fixtureLoweredOperation(
    _ request: SemanticLoweringRequest,
    estimatedGeneratedSourceWork: UInt64? = nil
) -> SemanticLoweredOperation {
    let builder = PreparedAutomationCommandBuilder(name: "fixture") { _ in
        try ContextResolvedEditorCommand(
            validating: .renameDocument(name: "fixture")
        )
    }
    return SemanticLoweredOperation(
        step: PreparedAutomationStep(
            inputs: request.preparedInputs,
            outputs: request.preparedOutputs,
            estimatedGeneratedSourceWork: estimatedGeneratedSourceWork
                ?? request.descriptor.estimatedExpandedSourceWork,
            commandBuilder: builder
        )
    )
}

private struct FixtureLowerer: SemanticOperationLowerer {
    let operationID: DomainCapabilityID
    let operationVersion: SemanticOperationVersion
    let resultEstimate: SemanticOperationResultEstimate

    init(
        operationID: DomainCapabilityID,
        operationVersion: SemanticOperationVersion,
        resultEstimate: SemanticOperationResultEstimate = .zero
    ) {
        self.operationID = operationID
        self.operationVersion = operationVersion
        self.resultEstimate = resultEstimate
    }

    func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
        fixtureLoweredOperation(request)
    }
}

private func fixtureInvocation(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion
) -> SemanticOperationInvocation {
    SemanticOperationInvocation(
        operationID: operationID,
        operationVersion: version,
        arguments: [
            SemanticArgumentID("length"): .literal(.number(1, unit: .meter))
        ]
    )
}

private func fixtureDescriptor(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion,
    route: SemanticOperationRoute = .source,
    effect: SemanticOperationEffect = .sourceMutation,
    resultEstimate: SemanticOperationResultEstimate = .zero
) -> SemanticOperationDescriptor {
    SemanticOperationDescriptor(
        operationID: operationID,
        version: version,
        inputs: [
            SemanticOperationInputDescriptor(
                id: SemanticArgumentID("length"),
                type: .number(unit: .meter)
            )
        ],
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("feature"),
                type: .feature,
                selector: .feature(index: 0)
            )
        ],
        route: route,
        effect: effect,
        estimatedExpandedSourceWork: 1,
        resultEstimate: resultEstimate
    )
}

private func structuredFixtureDescriptor(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion
) -> SemanticOperationDescriptor {
    SemanticOperationDescriptor(
        operationID: operationID,
        version: version,
        inputs: [
            SemanticOperationInputDescriptor(id: SemanticArgumentID("point"), type: .point),
            SemanticOperationInputDescriptor(id: SemanticArgumentID("direction"), type: .direction),
            SemanticOperationInputDescriptor(id: SemanticArgumentID("plane"), type: .plane),
            SemanticOperationInputDescriptor(id: SemanticArgumentID("transform"), type: .transform),
            SemanticOperationInputDescriptor(
                id: SemanticArgumentID("array"),
                type: .array(element: .number(unit: .meter))
            ),
            SemanticOperationInputDescriptor(id: SemanticArgumentID("object"), type: .object)
        ],
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("feature"),
                type: .feature,
                selector: .feature(index: 0)
            )
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 1,
        resultEstimate: .zero
    )
}

private func structuredFixtureArguments() -> [SemanticArgumentID: SemanticArgument] {
    [
        SemanticArgumentID("point"): .literal(
            .point(SemanticPoint3D(x: 1, y: 2, z: 3, unit: .meter))
        ),
        SemanticArgumentID("direction"): .literal(
            .direction(SemanticDirection3D(x: 0, y: 0, z: 1))
        ),
        SemanticArgumentID("plane"): .literal(
            .plane(
                SemanticPlane(
                    origin: SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter),
                    normal: SemanticDirection3D(x: 0, y: 1, z: 0)
                )
            )
        ),
        SemanticArgumentID("transform"): .literal(
            .transform(
                SemanticTransform(
                    translation: SemanticPoint3D(x: 1, y: 0, z: 0, unit: .meter),
                    axisPoint: SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter),
                    rotationAxis: SemanticDirection3D(x: 0, y: 0, z: 1),
                    rotation: SemanticAngle(value: 90, unit: .degree)
                )
            )
        ),
        SemanticArgumentID("array"): .literal(
            .array([
                .number(1, unit: .meter),
                .number(2, unit: .meter)
            ])
        ),
        SemanticArgumentID("object"): .literal(
            .object([
                SemanticObjectEntry(key: "enabled", value: .boolean(true)),
                SemanticObjectEntry(
                    key: "points",
                    value: .array([
                        .point(SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter))
                    ])
                )
            ])
        )
    ]
}

private func sceneProducerFixtureDescriptor(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion
) -> SemanticOperationDescriptor {
    SemanticOperationDescriptor(
        operationID: operationID,
        version: version,
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("scene"),
                type: .sceneNode,
                selector: .sceneNode(index: 0)
            )
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 1,
        resultEstimate: .zero
    )
}

private func sceneConsumerFixtureDescriptor(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion
) -> SemanticOperationDescriptor {
    SemanticOperationDescriptor(
        operationID: operationID,
        version: version,
        inputs: [
            SemanticOperationInputDescriptor(
                id: SemanticArgumentID("rootScenes"),
                type: .array(element: .sceneNode)
            )
        ],
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("component"),
                type: .componentDefinition,
                selector: .componentDefinition(index: 0)
            )
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 1,
        resultEstimate: .zero
    )
}

private func collisionOutputFixtureDescriptor(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion,
    outputID: SemanticOutputID
) -> SemanticOperationDescriptor {
    SemanticOperationDescriptor(
        operationID: operationID,
        version: version,
        outputs: [
            SemanticOperationOutputDescriptor(
                id: outputID,
                type: .feature,
                selector: .feature(index: 0)
            )
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 1,
        resultEstimate: .zero
    )
}

private func objectReferenceFixtureDescriptor(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion
) -> SemanticOperationDescriptor {
    SemanticOperationDescriptor(
        operationID: operationID,
        version: version,
        inputs: [
            SemanticOperationInputDescriptor(
                id: SemanticArgumentID("payload"),
                type: .object
            )
        ],
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("feature"),
                type: .feature,
                selector: .feature(index: 0)
            )
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 1,
        resultEstimate: .zero
    )
}

private func fixtureSourceDescriptor(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion
) -> SemanticOperationDescriptor {
    SemanticOperationDescriptor(
        operationID: operationID,
        version: version,
        inputs: [
            SemanticOperationInputDescriptor(
                id: SemanticArgumentID("source"),
                type: .feature
            )
        ],
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("feature"),
                type: .feature,
                selector: .feature(index: 0)
            )
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 1,
        resultEstimate: .zero
    )
}

private func fixtureGraphDescriptor(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion
) -> SemanticOperationDescriptor {
    SemanticOperationDescriptor(
        operationID: operationID,
        version: version,
        inputs: [
            SemanticOperationInputDescriptor(
                id: SemanticArgumentID("length"),
                type: .number(unit: .meter)
            ),
            SemanticOperationInputDescriptor(
                id: SemanticArgumentID("dependency"),
                type: .feature,
                isRequired: false
            )
        ],
        outputs: [
            SemanticOperationOutputDescriptor(
                id: SemanticOutputID("feature"),
                type: .feature,
                selector: .feature(index: 0)
            )
        ],
        route: .source,
        effect: .sourceMutation,
        estimatedExpandedSourceWork: 1,
        resultEstimate: .zero
    )
}

private func fixtureRegistry(
    descriptor: SemanticOperationDescriptor,
    lowerer: any SemanticOperationLowerer
) throws -> SemanticOperationRegistry {
    try SemanticOperationRegistry(registrations: [
        SemanticOperationRegistration(descriptor: descriptor, lowerer: lowerer)
    ])
}

private func fixtureCompiler(
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion,
    descriptor: SemanticOperationDescriptor,
    invocationCount: InvocationCounter? = nil,
    resultEstimate: SemanticOperationResultEstimate = .zero
) throws -> DefaultSemanticProgramCompiler {
    let lowerer: any SemanticOperationLowerer
    if let invocationCount {
        lowerer = CountingLowerer(
            operationID: operationID,
            operationVersion: version,
            resultEstimate: resultEstimate,
            invocationCount: invocationCount
        )
    } else {
        lowerer = FixtureLowerer(
            operationID: operationID,
            operationVersion: version,
            resultEstimate: resultEstimate
        )
    }
    return DefaultSemanticProgramCompiler(
        registry: try fixtureRegistry(descriptor: descriptor, lowerer: lowerer)
    )
}

private func expectLimitFailure(
    compiler: DefaultSemanticProgramCompiler,
    program: SemanticProgram,
    limits: SemanticProgramLimitPolicy,
    metric: SemanticProgramLimitMetric,
    actual: UInt64,
    maximum: UInt64
) throws {
    do {
        _ = try compiler.compile(
            program,
            context: SemanticCompilationContext(),
            limits: limits
        )
        Issue.record("Limit boundary plus one unexpectedly compiled.")
    } catch let error as SemanticCompilationError {
        #expect(error == .limitExceeded(metric: metric, actual: actual, maximum: maximum))
    }
}

private func fixtureLimits(
    maximumDecodedValueCount: Int = 128,
    maximumDecodedNestingDepth: Int = 16,
    maximumNodeCount: Int = 16,
    maximumEdgeCount: Int = 32,
    maximumParameterCount: Int = 16,
    maximumRequestedOutputCount: Int = 16,
    maximumLocalOutputReferenceCount: Int = 32,
    maximumExpressionCount: Int = 64,
    maximumExpressionDepth: Int = 16,
    maximumExpressionWork: UInt64 = 64,
    maximumCommandCount: Int = 16,
    maximumExpandedSourceWork: UInt64 = 128,
    maximumPreparedInputSlotCount: Int = 64,
    maximumPreparedOutputSlotCount: Int = 64,
    resultLimits: SemanticResultLimits = fixtureResultLimits()
) -> SemanticProgramLimitPolicy {
    SemanticProgramLimitPolicy(
        maximumDecodedValueCount: maximumDecodedValueCount,
        maximumDecodedNestingDepth: maximumDecodedNestingDepth,
        maximumNodeCount: maximumNodeCount,
        maximumEdgeCount: maximumEdgeCount,
        maximumParameterCount: maximumParameterCount,
        maximumRequestedOutputCount: maximumRequestedOutputCount,
        maximumLocalOutputReferenceCount: maximumLocalOutputReferenceCount,
        maximumExpressionCount: maximumExpressionCount,
        maximumExpressionDepth: maximumExpressionDepth,
        maximumExpressionWork: maximumExpressionWork,
        maximumLoweredCommandCount: maximumCommandCount,
        maximumExpandedSourceWork: maximumExpandedSourceWork,
        maximumPreparedInputSlotCount: maximumPreparedInputSlotCount,
        maximumPreparedOutputSlotCount: maximumPreparedOutputSlotCount,
        resultLimits: resultLimits
    )
}

private func fixtureResultLimits(
    maximumRequestedOutputCount: UInt64 = 16,
    maximumDiagnosticRecordCount: UInt64 = 16,
    maximumDiagnosticScalarCount: UInt64 = 64,
    maximumDiagnosticStringUTF8ByteCount: UInt64 = 1024,
    maximumTelemetryRecordCount: UInt64 = 16,
    maximumTelemetryScalarCount: UInt64 = 128,
    maximumTelemetryStringUTF8ByteCount: UInt64 = 1024
) -> SemanticResultLimits {
    SemanticResultLimits(
        maximumRequestedOutputCount: maximumRequestedOutputCount,
        maximumDiagnosticRecordCount: maximumDiagnosticRecordCount,
        maximumDiagnosticScalarCount: maximumDiagnosticScalarCount,
        maximumDiagnosticStringUTF8ByteCount: maximumDiagnosticStringUTF8ByteCount,
        maximumTelemetryRecordCount: maximumTelemetryRecordCount,
        maximumTelemetryScalarCount: maximumTelemetryScalarCount,
        maximumTelemetryStringUTF8ByteCount: maximumTelemetryStringUTF8ByteCount
    )
}

private func graphNode(
    _ symbol: String,
    operationID: DomainCapabilityID,
    version: SemanticOperationVersion,
    pointsTo: String?,
    kind: SemanticReferenceKind = .feature
) -> SemanticProgramNode {
    var arguments: [SemanticArgumentID: SemanticArgument] = [
        SemanticArgumentID("length"): .literal(.number(1, unit: .meter))
    ]
    if let pointsTo {
        arguments[SemanticArgumentID("dependency")] = .local(
            SemanticOutputReference(
                node: ProgramNodeSymbol(pointsTo),
                output: SemanticOutputID("feature"),
                kind: kind
            )
        )
    }
    return SemanticProgramNode(
        symbol: ProgramNodeSymbol(symbol),
        invocation: SemanticOperationInvocation(
            operationID: operationID,
            operationVersion: version,
            arguments: arguments
        )
    )
}
