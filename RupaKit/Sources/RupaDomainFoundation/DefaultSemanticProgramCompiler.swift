import Foundation
import RupaAutomation

public struct DefaultSemanticProgramCompiler: SemanticProgramCompiling, Sendable {
    private let registry: SemanticOperationRegistry

    public init(registry: SemanticOperationRegistry) {
        self.registry = registry
    }

    public func compile(
        _ request: SemanticDirectRequest,
        context: SemanticCompilationContext,
        limits: SemanticProgramLimitPolicy,
        cancellation: any SemanticCompilationCancellation
    ) throws -> SemanticCompilationResult {
        try checkCancellation(cancellation)
        guard request.schemaVersion == .current else {
            throw SemanticCompilationError.unsupportedSchema(request.schemaVersion)
        }
        let invocation = request.invocation
        for argumentID in invocation.arguments.keys.sorted() {
            guard let argument = invocation.arguments[argumentID] else { continue }
            if containsLocalReference(argument) {
                throw SemanticCompilationError.directLocalReference(argumentID)
            }
        }

        guard let registration = registry.resolve(
            operationID: invocation.operationID,
            version: invocation.operationVersion
        ) else {
            if registry.containsOperation(invocation.operationID) {
                throw SemanticCompilationError.unsupportedOperationVersion(
                    invocation.operationID,
                    invocation.operationVersion
                )
            }
            throw SemanticCompilationError.unknownOperation(
                invocation.operationID,
                invocation.operationVersion
            )
        }

        var seenRequestedOutputs: Set<SemanticOutputID> = []
        let requestedOutputs = try request.requestedOutputs.map { outputID -> SemanticOutputReference in
            guard seenRequestedOutputs.insert(outputID).inserted else {
                throw SemanticCompilationError.duplicateDirectOutput(outputID)
            }
            guard let output = registration.descriptor.outputs.first(where: { $0.id == outputID }) else {
                throw SemanticCompilationError.directOutputMissing(outputID)
            }
            return SemanticOutputReference(
                node: ProgramNodeSymbol("direct"),
                output: outputID,
                kind: output.type
            )
        }
        let program = SemanticProgram(
            schemaVersion: request.schemaVersion,
            parameters: [:],
            nodes: [
                SemanticProgramNode(
                    symbol: ProgramNodeSymbol("direct"),
                    invocation: invocation
                )
            ],
            requestedOutputs: requestedOutputs
        )
        return try compile(
            program,
            context: context,
            limits: limits,
            cancellation: cancellation
        )
    }

    public func compile(
        _ program: SemanticProgram,
        context: SemanticCompilationContext,
        limits: SemanticProgramLimitPolicy,
        cancellation: any SemanticCompilationCancellation
    ) throws -> SemanticCompilationResult {
        try checkCancellation(cancellation)
        try validateLimits(limits)
        guard program.schemaVersion == .current else {
            throw SemanticCompilationError.unsupportedSchema(program.schemaVersion)
        }
        guard !program.nodes.isEmpty else {
            throw SemanticCompilationError.emptyProgram
        }

        try checkCount(
            program.parameters.count,
            maximum: limits.maximumParameterCount,
            metric: .parameterCount
        )
        try checkCount(
            program.nodes.count,
            maximum: limits.maximumNodeCount,
            metric: .nodeCount
        )
        try checkCount(
            program.requestedOutputs.count,
            maximum: limits.maximumRequestedOutputCount,
            metric: .requestedOutputCount
        )

        var decodedValueCount = 0
        var decodedNestingDepth = 0
        for parameterID in program.parameters.keys.sorted() {
            try validateIdentifier(parameterID.rawValue)
            guard let value = program.parameters[parameterID] else { continue }
            let metrics = try validate(
                value,
                parameter: parameterID,
                limits: limits
            )
            decodedValueCount = try adding(
                decodedValueCount,
                metrics.count,
                metric: .decodedValueCount,
                maximum: limits.maximumDecodedValueCount
            )
            decodedNestingDepth = max(decodedNestingDepth, metrics.depth)
        }

        var nodeBySymbol: [ProgramNodeSymbol: SemanticProgramNode] = [:]
        var registrationBySymbol: [ProgramNodeSymbol: SemanticOperationRegistration] = [:]
        var outputByKey: [OutputKey: SemanticOperationOutputDescriptor] = [:]

        for node in program.nodes {
            try checkCancellation(cancellation)
            try validateIdentifier(node.symbol.rawValue)
            guard nodeBySymbol[node.symbol] == nil else {
                throw SemanticCompilationError.duplicateNode(node.symbol)
            }
            nodeBySymbol[node.symbol] = node

            let invocation = node.invocation
            guard let registration = registry.resolve(
                operationID: invocation.operationID,
                version: invocation.operationVersion
            ) else {
                if registry.containsOperation(invocation.operationID) {
                    throw SemanticCompilationError.unsupportedOperationVersion(
                        invocation.operationID,
                        invocation.operationVersion
                    )
                }
                throw SemanticCompilationError.unknownOperation(
                    invocation.operationID,
                    invocation.operationVersion
                )
            }
            guard registration.descriptor.route == .source else {
                throw SemanticCompilationError.routeIneligible(
                    node: node.symbol,
                    route: registration.descriptor.route
                )
            }
            guard registration.descriptor.effect == .sourceMutation else {
                throw SemanticCompilationError.effectIneligible(
                    node: node.symbol,
                    effect: registration.descriptor.effect
                )
            }
            registrationBySymbol[node.symbol] = registration

            for output in registration.descriptor.outputs {
                let key = OutputKey(node: node.symbol, output: output.id)
                guard outputByKey[key] == nil else {
                    throw SemanticCompilationError.duplicateOutput(output.id)
                }
                outputByKey[key] = output
            }
        }

        var resolvedBySymbol: [ProgramNodeSymbol: ResolvedNode] = [:]
        var outgoing: [ProgramNodeSymbol: Set<ProgramNodeSymbol>] = [:]
        var indegree: [ProgramNodeSymbol: Int] = [:]
        for symbol in nodeBySymbol.keys {
            outgoing[symbol] = []
            indegree[symbol] = 0
        }

        var edgeCount = 0
        var localReferenceCount = 0
        var expressionCount = 0
        var expressionDepth = 0
        var expressionWork: UInt64 = 0
        var declaredExpandedSourceWork: UInt64 = 0
        var preparedInputSlotCount = 0
        var preparedOutputSlotCount = 0

        for node in program.nodes {
            guard let registration = registrationBySymbol[node.symbol] else { continue }
            declaredExpandedSourceWork = try adding(
                declaredExpandedSourceWork,
                registration.descriptor.estimatedExpandedSourceWork,
                metric: .expandedSourceWork,
                maximum: limits.maximumExpandedSourceWork
            )
            let descriptorByID = Dictionary(
                uniqueKeysWithValues: registration.descriptor.inputs.map { ($0.id, $0) }
            )
            for argumentID in node.invocation.arguments.keys {
                guard descriptorByID[argumentID] != nil else {
                    throw SemanticCompilationError.unknownArgument(
                        node: node.symbol,
                        argument: argumentID
                    )
                }
            }

            var resolvedArguments: [SemanticArgumentID: SemanticResolvedArgument] = [:]
            for input in registration.descriptor.inputs.sorted(by: { $0.id < $1.id }) {
                guard let argument = node.invocation.arguments[input.id] else {
                    if input.isRequired {
                        throw SemanticCompilationError.missingArgument(
                            node: node.symbol,
                            argument: input.id
                        )
                    }
                    continue
                }
                let resolution = try resolveArgument(
                    argument,
                    node: node.symbol,
                    argumentID: input.id,
                    path: [input.id.rawValue],
                    expected: input.type,
                    parameters: program.parameters,
                    context: context,
                    nodeBySymbol: nodeBySymbol,
                    outputByKey: outputByKey,
                    limits: limits
                )
                resolvedArguments[input.id] = resolution.argument
                decodedValueCount = try adding(
                    decodedValueCount,
                    resolution.decodedValueCount,
                    metric: .decodedValueCount,
                    maximum: limits.maximumDecodedValueCount
                )
                decodedNestingDepth = max(decodedNestingDepth, resolution.decodedNestingDepth)
                localReferenceCount = try adding(
                    localReferenceCount,
                    resolution.localReferenceCount,
                    metric: .localOutputReferenceCount,
                    maximum: limits.maximumLocalOutputReferenceCount
                )
                edgeCount = try adding(
                    edgeCount,
                    resolution.edgeCount,
                    metric: .edgeCount,
                    maximum: limits.maximumEdgeCount
                )
                expressionCount = try adding(
                    expressionCount,
                    resolution.expressionCount,
                    metric: .expressionCount,
                    maximum: limits.maximumExpressionCount
                )
                expressionDepth = max(expressionDepth, resolution.expressionDepth)
                expressionWork = try adding(
                    expressionWork,
                    resolution.expressionWork,
                    metric: .expressionWork,
                    maximum: limits.maximumExpressionWork
                )
                for dependency in resolution.localDependencies {
                    if outgoing[dependency, default: []].insert(node.symbol).inserted {
                        indegree[node.symbol, default: 0] += 1
                    }
                }
            }
            preparedInputSlotCount = try adding(
                preparedInputSlotCount,
                resolutionPreparedInputSlotCount(resolvedArguments, limits: limits),
                metric: .preparedInputSlotCount,
                maximum: limits.maximumPreparedInputSlotCount
            )
            preparedOutputSlotCount = try adding(
                preparedOutputSlotCount,
                registration.descriptor.outputs.count,
                metric: .preparedOutputSlotCount,
                maximum: limits.maximumPreparedOutputSlotCount
            )
            resolvedBySymbol[node.symbol] = ResolvedNode(
                node: node,
                registration: registration,
                arguments: resolvedArguments
            )
        }

        try checkCount(
            decodedValueCount,
            maximum: limits.maximumDecodedValueCount,
            metric: .decodedValueCount
        )
        try checkCount(
            decodedNestingDepth,
            maximum: limits.maximumDecodedNestingDepth,
            metric: .decodedNestingDepth
        )
        try checkCount(
            expressionDepth,
            maximum: limits.maximumExpressionDepth,
            metric: .expressionDepth
        )
        // Every accepted semantic node lowers to exactly one prepared source
        // step. Charge command count and declared source work before invoking
        // any lowerer so limit failures cannot trigger a partial lowering.
        try checkCount(
            program.nodes.count,
            maximum: limits.maximumLoweredCommandCount,
            metric: .loweredCommandCount
        )
        guard declaredExpandedSourceWork <= limits.maximumExpandedSourceWork else {
            throw SemanticCompilationError.limitExceeded(
                metric: .expandedSourceWork,
                actual: declaredExpandedSourceWork,
                maximum: limits.maximumExpandedSourceWork
            )
        }

        var ready = nodeBySymbol.keys.filter { indegree[$0] == 0 }.sorted()
        var orderedSymbols: [ProgramNodeSymbol] = []
        while !ready.isEmpty {
            let symbol = ready.removeFirst()
            orderedSymbols.append(symbol)
            for consumer in outgoing[symbol, default: []].sorted() {
                indegree[consumer, default: 0] -= 1
                if indegree[consumer] == 0 {
                    ready.append(consumer)
                    ready.sort()
                }
            }
        }
        guard orderedSymbols.count == nodeBySymbol.count else {
            let cycle = nodeBySymbol.keys.filter { !orderedSymbols.contains($0) }.sorted()
            throw SemanticCompilationError.graphCycle(cycle)
        }

        // Requested-output validation is part of the no-lowering preflight.
        // A malformed output declaration must never invoke a trusted lowerer.
        var requestedOutputSet: Set<SemanticOutputReference> = []
        for requestedOutput in program.requestedOutputs {
            guard requestedOutputSet.insert(requestedOutput).inserted else {
                throw SemanticCompilationError.duplicateRequestedOutput(requestedOutput)
            }
            guard nodeBySymbol[requestedOutput.node] != nil else {
                throw SemanticCompilationError.requestedOutputNodeMissing(requestedOutput.node)
            }
            guard let output = outputByKey[
                OutputKey(node: requestedOutput.node, output: requestedOutput.output)
            ] else {
                throw SemanticCompilationError.requestedOutputMissing(
                    node: requestedOutput.node,
                    output: requestedOutput.output
                )
            }
            guard output.type == requestedOutput.kind else {
                throw SemanticCompilationError.requestedOutputKindMismatch(
                    node: requestedOutput.node,
                    output: requestedOutput.output,
                    expected: output.type,
                    actual: requestedOutput.kind
                )
            }
        }

        let resultCharge = try makeResultCharge(
            requestedOutputCount: program.requestedOutputs.count,
            orderedSymbols: orderedSymbols,
            registrations: registrationBySymbol,
            limits: limits.resultLimits
        )

        var requestedPreparedOutputs: [CompiledSemanticOutputRequest] = []
        var preparedSteps: [PreparedAutomationStep] = []
        var loweredCommandCount = 0
        var expandedSourceWork: UInt64 = 0

        for symbol in orderedSymbols {
            try checkCancellation(cancellation)
            guard let resolved = resolvedBySymbol[symbol] else {
                throw SemanticCompilationError.lowererContractViolation(
                    node: symbol,
                    message: "Resolved semantic node was not retained."
                )
            }
            let descriptor = resolved.registration.descriptor
            let inputDescriptors = descriptor.inputs.sorted(by: { $0.id < $1.id })
            var preparedInputs: [PreparedAutomationInputSlot] = []
            for input in inputDescriptors {
                guard let argument = resolved.arguments[input.id] else { continue }
                try appendPreparedInputs(
                    from: argument,
                    node: symbol,
                    path: [input.id.rawValue],
                    into: &preparedInputs
                )
            }

            let outputDescriptors = descriptor.outputs.sorted(by: { $0.id < $1.id })
            let preparedOutputs = outputDescriptors.map { output in
                PreparedAutomationOutputSlot(
                    id: preparedSlotID(node: symbol, output: output.id),
                    selector: output.selector.preparedSelector()
                )
            }

            let request = SemanticLoweringRequest(
                descriptor: descriptor,
                invocation: resolved.node.invocation,
                arguments: resolved.arguments,
                preparedInputs: preparedInputs,
                preparedOutputs: preparedOutputs
            )

            let lowered: SemanticLoweredOperation
            do {
                lowered = try resolved.registration.lowerer.lower(request)
            } catch {
                throw SemanticCompilationError.loweringFailed(
                    node: symbol,
                    operationID: descriptor.operationID,
                    message: String(describing: error)
                )
            }
            let step = lowered.step
            guard step.inputs == preparedInputs else {
                throw SemanticCompilationError.lowererContractViolation(
                    node: symbol,
                    message: "Lowerer changed validated input slots."
                )
            }
            guard step.outputs == preparedOutputs else {
                throw SemanticCompilationError.lowererContractViolation(
                    node: symbol,
                    message: "Lowerer changed validated output slots."
                )
            }
            guard step.estimatedGeneratedSourceWork == descriptor.estimatedExpandedSourceWork else {
                throw SemanticCompilationError.lowererContractViolation(
                    node: symbol,
                    message: "Lowerer work estimate does not match its descriptor."
                )
            }
            guard !step.commandBuilder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SemanticCompilationError.lowererContractViolation(
                    node: symbol,
                    message: "Lowerer returned an unnamed command builder."
                )
            }

            loweredCommandCount = try adding(
                loweredCommandCount,
                1,
                metric: .loweredCommandCount,
                maximum: limits.maximumLoweredCommandCount
            )
            expandedSourceWork = try adding(
                expandedSourceWork,
                step.estimatedGeneratedSourceWork,
                metric: .expandedSourceWork,
                maximum: limits.maximumExpandedSourceWork
            )
            preparedSteps.append(step)

            for output in outputDescriptors {
                let outputReference = SemanticOutputReference(
                    node: symbol,
                    output: output.id,
                    kind: output.type
                )
                if program.requestedOutputs.contains(outputReference) {
                    requestedPreparedOutputs.append(
                        CompiledSemanticOutputRequest(
                            source: outputReference,
                            preparedSlot: preparedSlotID(node: symbol, output: output.id)
                        )
                    )
                }
            }
        }

        loweredCommandCount = preparedSteps.count
        try checkCount(
            loweredCommandCount,
            maximum: limits.maximumLoweredCommandCount,
            metric: .loweredCommandCount
        )
        let preparedLimits = PreparedAutomationLimitPolicy(
            maximumStepCount: limits.maximumNodeCount,
            maximumInputSlotCount: limits.maximumPreparedInputSlotCount,
            maximumOutputSlotCount: limits.maximumPreparedOutputSlotCount,
            maximumCommandCount: limits.maximumLoweredCommandCount,
            maximumGeneratedSourceWork: limits.maximumExpandedSourceWork
        )
        let preparedProgram: PreparedAutomationProgram
        do {
            preparedProgram = try PreparedAutomationProgram(
                steps: preparedSteps,
                limits: preparedLimits
            )
        } catch {
            throw SemanticCompilationError.preparedPlanInvalid(
                node: nil,
                message: String(describing: error)
            )
        }

        let telemetry = SemanticCompilationTelemetry(
            decodedValueCount: decodedValueCount,
            decodedNestingDepth: decodedNestingDepth,
            nodeCount: program.nodes.count,
            edgeCount: edgeCount,
            parameterCount: program.parameters.count,
            requestedOutputCount: program.requestedOutputs.count,
            localOutputReferenceCount: localReferenceCount,
            expressionCount: expressionCount,
            expressionDepth: expressionDepth,
            expressionWork: expressionWork,
            loweredCommandCount: loweredCommandCount,
            expandedSourceWork: expandedSourceWork
        )
        return SemanticCompilationResult(
            preparedProgram: preparedProgram,
            orderedNodeSymbols: orderedSymbols,
            requestedOutputs: requestedPreparedOutputs,
            telemetry: telemetry,
            resultCharge: resultCharge
        )
    }
}

private extension DefaultSemanticProgramCompiler {
    struct OutputKey: Hashable {
        let node: ProgramNodeSymbol
        let output: SemanticOutputID
    }

    struct ResolvedNode {
        let node: SemanticProgramNode
        let registration: SemanticOperationRegistration
        let arguments: [SemanticArgumentID: SemanticResolvedArgument]
    }

    struct ExpressionAnalysis {
        let type: SemanticValueType
        let value: SemanticTypedValue
        let count: Int
        let depth: Int
        let work: UInt64
    }

    struct ArgumentResolution {
        let argument: SemanticResolvedArgument
        let decodedValueCount: Int
        let decodedNestingDepth: Int
        let localReferenceCount: Int
        let edgeCount: Int
        let expressionCount: Int
        let expressionDepth: Int
        let expressionWork: UInt64
        let localDependencies: Set<ProgramNodeSymbol>
    }

    func checkCancellation(_ cancellation: any SemanticCompilationCancellation) throws {
        guard !cancellation.isCancelled else {
            throw SemanticCompilationError.cancelled
        }
    }

    func containsLocalReference(_ argument: SemanticArgument) -> Bool {
        switch argument {
        case .local:
            return true
        case .array(let values):
            return values.contains(where: containsLocalReference)
        case .object(let entries):
            return entries.contains { containsLocalReference($0.value) }
        case .literal, .parameter, .existing, .expression:
            return false
        }
    }

    func validateLimits(_ limits: SemanticProgramLimitPolicy) throws {
        let values = [
            (limits.maximumDecodedValueCount, SemanticProgramLimitMetric.decodedValueCount),
            (limits.maximumDecodedNestingDepth, SemanticProgramLimitMetric.decodedNestingDepth),
            (limits.maximumNodeCount, SemanticProgramLimitMetric.nodeCount),
            (limits.maximumEdgeCount, SemanticProgramLimitMetric.edgeCount),
            (limits.maximumParameterCount, SemanticProgramLimitMetric.parameterCount),
            (limits.maximumRequestedOutputCount, SemanticProgramLimitMetric.requestedOutputCount),
            (limits.maximumLocalOutputReferenceCount, SemanticProgramLimitMetric.localOutputReferenceCount),
            (limits.maximumExpressionCount, SemanticProgramLimitMetric.expressionCount),
            (limits.maximumExpressionDepth, SemanticProgramLimitMetric.expressionDepth),
            (limits.maximumLoweredCommandCount, SemanticProgramLimitMetric.loweredCommandCount),
            (limits.maximumPreparedInputSlotCount, SemanticProgramLimitMetric.preparedInputSlotCount),
            (limits.maximumPreparedOutputSlotCount, SemanticProgramLimitMetric.preparedOutputSlotCount)
        ]
        for (value, metric) in values where value < 0 {
            throw SemanticCompilationError.limitExceeded(
                metric: metric,
                actual: 0,
                maximum: 0
            )
        }
    }

    func validateIdentifier(_ value: String) throws {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw SemanticCompilationError.invalidIdentifier(value)
        }
    }

    struct DecodedValueMetrics {
        let count: Int
        let depth: Int
    }

    enum ValueValidationError: Error {
        case invalid
    }

    func validate(
        _ value: SemanticTypedValue,
        parameter: ProgramParameterID,
        limits: SemanticProgramLimitPolicy
    ) throws -> DecodedValueMetrics {
        do {
            return try analyzeValue(value, limits: limits)
        } catch is ValueValidationError {
            throw SemanticCompilationError.invalidParameter(parameter)
        }
    }

    func validate(
        _ value: SemanticTypedValue,
        node: ProgramNodeSymbol,
        argument: SemanticArgumentID,
        limits: SemanticProgramLimitPolicy
    ) throws -> DecodedValueMetrics {
        do {
            return try analyzeValue(value, limits: limits)
        } catch let error as SemanticCompilationError {
            throw error
        } catch is ValueValidationError {
            throw SemanticCompilationError.invalidArgument(node: node, argument: argument)
        }
    }

    func analyzeValue(
        _ value: SemanticTypedValue,
        limits: SemanticProgramLimitPolicy
    ) throws -> DecodedValueMetrics {
        switch value {
        case .text(let text):
            guard !text.contains(where: { $0.isNewline }) else {
                throw ValueValidationError.invalid
            }
            return DecodedValueMetrics(count: 1, depth: 1)
        case .boolean, .integer:
            return DecodedValueMetrics(count: 1, depth: 1)
        case .number(let number, _):
            guard number.isFinite else {
                throw ValueValidationError.invalid
            }
            return DecodedValueMetrics(count: 1, depth: 1)
        case .point(let point):
            guard point.isFinite, point.isValidUnit else {
                throw ValueValidationError.invalid
            }
            return DecodedValueMetrics(count: 1, depth: 1)
        case .direction(let direction):
            guard direction.isFinite, direction.isNonZero else {
                throw ValueValidationError.invalid
            }
            return DecodedValueMetrics(count: 1, depth: 1)
        case .plane(let plane):
            guard plane.isFinite, plane.normal.isNonZero else {
                throw ValueValidationError.invalid
            }
            return DecodedValueMetrics(count: 1, depth: 1)
        case .transform(let transform):
            guard transform.isFinite, transform.rotationAxis.isNonZero else {
                throw ValueValidationError.invalid
            }
            return DecodedValueMetrics(count: 1, depth: 1)
        case .array(let values):
            var count = 1
            var depth = 1
            var elementType: SemanticValueType?
            for value in values {
                let metrics = try analyzeValue(value, limits: limits)
                count = try adding(
                    count,
                    metrics.count,
                    metric: .decodedValueCount,
                    maximum: limits.maximumDecodedValueCount
                )
                let valueDepth = try adding(
                    metrics.depth,
                    1,
                    metric: .decodedNestingDepth,
                    maximum: limits.maximumDecodedNestingDepth
                )
                depth = max(depth, valueDepth)
                if let elementType {
                    guard value.type == elementType else {
                        throw ValueValidationError.invalid
                    }
                } else {
                    elementType = value.type
                }
            }
            try checkCount(
                count,
                maximum: limits.maximumDecodedValueCount,
                metric: .decodedValueCount
            )
            try checkCount(
                depth,
                maximum: limits.maximumDecodedNestingDepth,
                metric: .decodedNestingDepth
            )
            return DecodedValueMetrics(count: count, depth: depth)
        case .object(let entries):
            var count = 1
            var depth = 1
            var keys: Set<String> = []
            for entry in entries {
                guard validObjectKey(entry.key), keys.insert(entry.key).inserted else {
                    throw ValueValidationError.invalid
                }
                let metrics = try analyzeValue(entry.value, limits: limits)
                count = try adding(
                    count,
                    metrics.count,
                    metric: .decodedValueCount,
                    maximum: limits.maximumDecodedValueCount
                )
                let valueDepth = try adding(
                    metrics.depth,
                    1,
                    metric: .decodedNestingDepth,
                    maximum: limits.maximumDecodedNestingDepth
                )
                depth = max(depth, valueDepth)
            }
            try checkCount(
                count,
                maximum: limits.maximumDecodedValueCount,
                metric: .decodedValueCount
            )
            try checkCount(
                depth,
                maximum: limits.maximumDecodedNestingDepth,
                metric: .decodedNestingDepth
            )
            return DecodedValueMetrics(count: count, depth: depth)
        }
    }

    func validObjectKey(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }

    func resolveArgument(
        _ argument: SemanticArgument,
        node: ProgramNodeSymbol,
        argumentID: SemanticArgumentID,
        path: [String],
        expected: SemanticValueType?,
        parameters: [ProgramParameterID: SemanticTypedValue],
        context: SemanticCompilationContext,
        nodeBySymbol: [ProgramNodeSymbol: SemanticProgramNode],
        outputByKey: [OutputKey: SemanticOperationOutputDescriptor],
        limits: SemanticProgramLimitPolicy
    ) throws -> ArgumentResolution {
        switch argument {
        case .literal(let value):
            if let expected, !typeMatches(value.type, expected: expected) {
                throw SemanticCompilationError.invalidArgument(
                    node: node,
                    argument: argumentID
                )
            }
            let metrics = try validate(
                value,
                node: node,
                argument: argumentID,
                limits: limits
            )
            return ArgumentResolution(
                argument: .value(value),
                decodedValueCount: metrics.count,
                decodedNestingDepth: metrics.depth,
                localReferenceCount: 0,
                edgeCount: 0,
                expressionCount: 0,
                expressionDepth: 0,
                expressionWork: 0,
                localDependencies: []
            )
        case .parameter(let parameterID):
            guard let value = parameters[parameterID] else {
                throw SemanticCompilationError.missingParameter(parameterID)
            }
            if let expected, !typeMatches(value.type, expected: expected) {
                throw SemanticCompilationError.parameterTypeMismatch(
                    parameterID,
                    expected: expected,
                    actual: value.type
                )
            }
            return ArgumentResolution(
                argument: .value(value),
                decodedValueCount: 1,
                decodedNestingDepth: 1,
                localReferenceCount: 0,
                edgeCount: 0,
                expressionCount: 0,
                expressionDepth: 0,
                expressionWork: 0,
                localDependencies: []
            )
        case .existing(let reference):
            guard context.contains(reference) else {
                throw SemanticCompilationError.sourceReferenceUnavailable(reference)
            }
            if let expected, reference.type != expected {
                throw SemanticCompilationError.sourceReferenceTypeMismatch(
                    node: node,
                    argument: argumentID,
                    expected: expected,
                    actual: reference.type
                )
            }
            return ArgumentResolution(
                argument: .source(
                    reference,
                    preparedSlot: preparedSlotID(node: node, path: path)
                ),
                decodedValueCount: 1,
                decodedNestingDepth: 1,
                localReferenceCount: 0,
                edgeCount: 0,
                expressionCount: 0,
                expressionDepth: 0,
                expressionWork: 0,
                localDependencies: []
            )
        case .local(let reference):
            guard nodeBySymbol[reference.node] != nil else {
                throw SemanticCompilationError.localReferenceNodeMissing(
                    node: node,
                    reference: reference.node
                )
            }
            guard let output = outputByKey[
                OutputKey(node: reference.node, output: reference.output)
            ] else {
                throw SemanticCompilationError.localReferenceOutputMissing(
                    node: reference.node,
                    output: reference.output
                )
            }
            guard reference.node != node else {
                throw SemanticCompilationError.localReferenceSelf(node: node)
            }
            guard reference.kind == output.type else {
                throw SemanticCompilationError.localReferenceKindMismatch(
                    node: node,
                    argument: argumentID,
                    expected: output.type,
                    actual: reference.kind
                )
            }
            if let expected, output.type != expected {
                throw SemanticCompilationError.localReferenceKindMismatch(
                    node: node,
                    argument: argumentID,
                    expected: expected,
                    actual: output.type
                )
            }
            return ArgumentResolution(
                argument: .local(
                    reference,
                    preparedSlot: preparedSlotID(node: node, path: path)
                ),
                decodedValueCount: 1,
                decodedNestingDepth: 1,
                localReferenceCount: 1,
                edgeCount: 1,
                expressionCount: 0,
                expressionDepth: 0,
                expressionWork: 0,
                localDependencies: [reference.node]
            )
        case .expression(let expression):
            let analysis = try analyze(
                expression,
                parameters: parameters,
                limits: limits
            )
            if let expected, !typeMatches(analysis.type, expected: expected) {
                throw SemanticCompilationError.invalidArgument(
                    node: node,
                    argument: argumentID
                )
            }
            return ArgumentResolution(
                argument: .value(analysis.value),
                decodedValueCount: analysis.count,
                decodedNestingDepth: analysis.depth,
                localReferenceCount: 0,
                edgeCount: 0,
                expressionCount: analysis.count,
                expressionDepth: analysis.depth,
                expressionWork: analysis.work,
                localDependencies: []
            )
        case .array(let values):
            let expectedElement: SemanticValueType?
            if let expected {
                guard case .array(let element) = expected else {
                    throw SemanticCompilationError.invalidArgument(
                        node: node,
                        argument: argumentID
                    )
                }
                expectedElement = element
            } else {
                expectedElement = nil
            }
            var resolvedValues: [SemanticResolvedArgument] = []
            resolvedValues.reserveCapacity(values.count)
            var decodedValueCount = 1
            var decodedNestingDepth = 1
            var localReferenceCount = 0
            var edgeCount = 0
            var expressionCount = 0
            var expressionDepth = 0
            var expressionWork: UInt64 = 0
            var elementType: SemanticValueType?
            var localDependencies: Set<ProgramNodeSymbol> = []
            for (index, value) in values.enumerated() {
                let child = try resolveArgument(
                    value,
                    node: node,
                    argumentID: argumentID,
                    path: path + ["index", String(index)],
                    expected: expectedElement,
                    parameters: parameters,
                    context: context,
                    nodeBySymbol: nodeBySymbol,
                    outputByKey: outputByKey,
                    limits: limits
                )
                if let elementType {
                    guard child.argument.type == elementType else {
                        throw SemanticCompilationError.invalidArgument(
                            node: node,
                            argument: argumentID
                        )
                    }
                } else {
                    elementType = child.argument.type
                }
                resolvedValues.append(child.argument)
                decodedValueCount = try adding(
                    decodedValueCount,
                    child.decodedValueCount,
                    metric: .decodedValueCount,
                    maximum: limits.maximumDecodedValueCount
                )
                decodedNestingDepth = max(
                    decodedNestingDepth,
                    try adding(
                        child.decodedNestingDepth,
                        1,
                        metric: .decodedNestingDepth,
                        maximum: limits.maximumDecodedNestingDepth
                    )
                )
                localReferenceCount = try adding(
                    localReferenceCount,
                    child.localReferenceCount,
                    metric: .localOutputReferenceCount,
                    maximum: limits.maximumLocalOutputReferenceCount
                )
                edgeCount = try adding(
                    edgeCount,
                    child.edgeCount,
                    metric: .edgeCount,
                    maximum: limits.maximumEdgeCount
                )
                expressionCount = try adding(
                    expressionCount,
                    child.expressionCount,
                    metric: .expressionCount,
                    maximum: limits.maximumExpressionCount
                )
                expressionDepth = max(expressionDepth, child.expressionDepth)
                expressionWork = try adding(
                    expressionWork,
                    child.expressionWork,
                    metric: .expressionWork,
                    maximum: limits.maximumExpressionWork
                )
                localDependencies.formUnion(child.localDependencies)
            }
            try checkCount(
                decodedValueCount,
                maximum: limits.maximumDecodedValueCount,
                metric: .decodedValueCount
            )
            try checkCount(
                decodedNestingDepth,
                maximum: limits.maximumDecodedNestingDepth,
                metric: .decodedNestingDepth
            )
            return ArgumentResolution(
                argument: .array(resolvedValues),
                decodedValueCount: decodedValueCount,
                decodedNestingDepth: decodedNestingDepth,
                localReferenceCount: localReferenceCount,
                edgeCount: edgeCount,
                expressionCount: expressionCount,
                expressionDepth: expressionDepth,
                expressionWork: expressionWork,
                localDependencies: localDependencies
            )
        case .object(let entries):
            if let expected, expected != .object {
                throw SemanticCompilationError.invalidArgument(
                    node: node,
                    argument: argumentID
                )
            }
            var resolvedEntries: [SemanticResolvedObjectEntry] = []
            resolvedEntries.reserveCapacity(entries.count)
            var keys: Set<String> = []
            var decodedValueCount = 1
            var decodedNestingDepth = 1
            var localReferenceCount = 0
            var edgeCount = 0
            var expressionCount = 0
            var expressionDepth = 0
            var expressionWork: UInt64 = 0
            var localDependencies: Set<ProgramNodeSymbol> = []
            for entry in entries {
                guard validObjectKey(entry.key), keys.insert(entry.key).inserted else {
                    throw SemanticCompilationError.invalidArgument(
                        node: node,
                        argument: argumentID
                    )
                }
                let child = try resolveArgument(
                    entry.value,
                    node: node,
                    argumentID: argumentID,
                    path: path + ["key", entry.key],
                    expected: nil,
                    parameters: parameters,
                    context: context,
                    nodeBySymbol: nodeBySymbol,
                    outputByKey: outputByKey,
                    limits: limits
                )
                resolvedEntries.append(
                    SemanticResolvedObjectEntry(key: entry.key, value: child.argument)
                )
                decodedValueCount = try adding(
                    decodedValueCount,
                    child.decodedValueCount,
                    metric: .decodedValueCount,
                    maximum: limits.maximumDecodedValueCount
                )
                decodedNestingDepth = max(
                    decodedNestingDepth,
                    try adding(
                        child.decodedNestingDepth,
                        1,
                        metric: .decodedNestingDepth,
                        maximum: limits.maximumDecodedNestingDepth
                    )
                )
                localReferenceCount = try adding(
                    localReferenceCount,
                    child.localReferenceCount,
                    metric: .localOutputReferenceCount,
                    maximum: limits.maximumLocalOutputReferenceCount
                )
                edgeCount = try adding(
                    edgeCount,
                    child.edgeCount,
                    metric: .edgeCount,
                    maximum: limits.maximumEdgeCount
                )
                expressionCount = try adding(
                    expressionCount,
                    child.expressionCount,
                    metric: .expressionCount,
                    maximum: limits.maximumExpressionCount
                )
                expressionDepth = max(expressionDepth, child.expressionDepth)
                expressionWork = try adding(
                    expressionWork,
                    child.expressionWork,
                    metric: .expressionWork,
                    maximum: limits.maximumExpressionWork
                )
                localDependencies.formUnion(child.localDependencies)
            }
            try checkCount(
                decodedValueCount,
                maximum: limits.maximumDecodedValueCount,
                metric: .decodedValueCount
            )
            try checkCount(
                decodedNestingDepth,
                maximum: limits.maximumDecodedNestingDepth,
                metric: .decodedNestingDepth
            )
            return ArgumentResolution(
                argument: .object(resolvedEntries),
                decodedValueCount: decodedValueCount,
                decodedNestingDepth: decodedNestingDepth,
                localReferenceCount: localReferenceCount,
                edgeCount: edgeCount,
                expressionCount: expressionCount,
                expressionDepth: expressionDepth,
                expressionWork: expressionWork,
                localDependencies: localDependencies
            )
        }
    }

    func typeMatches(
        _ actual: SemanticValueType,
        expected: SemanticValueType
    ) -> Bool {
        guard actual != expected else { return true }
        switch (actual, expected) {
        case (.array(element: nil), .array):
            // An empty array has no runtime element evidence and can satisfy a
            // typed array input. Heterogeneous arrays are rejected by
            // analyzeValue before this rule can be used as a wildcard.
            return true
        default:
            return false
        }
    }

    func checkCount(
        _ value: Int,
        maximum: Int,
        metric: SemanticProgramLimitMetric
    ) throws {
        guard value <= maximum else {
            throw SemanticCompilationError.limitExceeded(
                metric: metric,
                actual: UInt64(value),
                maximum: UInt64(maximum)
            )
        }
    }

    func adding(
        _ lhs: Int,
        _ rhs: Int,
        metric: SemanticProgramLimitMetric,
        maximum: Int
    ) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw SemanticCompilationError.limitExceeded(
                metric: metric,
                actual: UInt64.max,
                maximum: UInt64(maximum)
            )
        }
        try checkCount(value, maximum: maximum, metric: metric)
        return value
    }

    func adding(
        _ lhs: UInt64,
        _ rhs: UInt64,
        metric: SemanticProgramLimitMetric,
        maximum: UInt64
    ) throws -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw SemanticCompilationError.limitExceeded(
                metric: metric,
                actual: UInt64.max,
                maximum: maximum
            )
        }
        guard value <= maximum else {
            throw SemanticCompilationError.limitExceeded(
                metric: metric,
                actual: value,
                maximum: maximum
            )
        }
        return value
    }

    func makeResultCharge(
        requestedOutputCount: Int,
        orderedSymbols: [ProgramNodeSymbol],
        registrations: [ProgramNodeSymbol: SemanticOperationRegistration],
        limits: SemanticResultLimits
    ) throws -> SemanticResultCharge {
        let requestedOutputCount = UInt64(requestedOutputCount)
        var diagnosticRecordCount: UInt64 = 0
        var diagnosticScalarCount: UInt64 = 0
        var diagnosticStringUTF8ByteCount: UInt64 = 0
        // The compiler always emits one telemetry record containing the twelve
        // scalar compilation counters. Operation estimates are added below.
        var telemetryRecordCount: UInt64 = 1
        var telemetryScalarCount: UInt64 = 12
        var telemetryStringUTF8ByteCount: UInt64 = 0

        for symbol in orderedSymbols {
            guard let estimate = registrations[symbol]?.descriptor.resultEstimate else {
                throw SemanticCompilationError.lowererContractViolation(
                    node: symbol,
                    message: "Missing result estimate for a resolved semantic node."
                )
            }
            diagnosticRecordCount = try adding(
                diagnosticRecordCount,
                estimate.diagnosticRecordCount,
                metric: .resultDiagnosticRecordCount,
                maximum: limits.maximumDiagnosticRecordCount
            )
            diagnosticScalarCount = try adding(
                diagnosticScalarCount,
                estimate.diagnosticScalarCount,
                metric: .resultDiagnosticScalarCount,
                maximum: limits.maximumDiagnosticScalarCount
            )
            diagnosticStringUTF8ByteCount = try adding(
                diagnosticStringUTF8ByteCount,
                estimate.diagnosticStringUTF8ByteCount,
                metric: .resultDiagnosticStringUTF8ByteCount,
                maximum: limits.maximumDiagnosticStringUTF8ByteCount
            )
            telemetryRecordCount = try adding(
                telemetryRecordCount,
                estimate.telemetryRecordCount,
                metric: .resultTelemetryRecordCount,
                maximum: limits.maximumTelemetryRecordCount
            )
            telemetryScalarCount = try adding(
                telemetryScalarCount,
                estimate.telemetryScalarCount,
                metric: .resultTelemetryScalarCount,
                maximum: limits.maximumTelemetryScalarCount
            )
            telemetryStringUTF8ByteCount = try adding(
                telemetryStringUTF8ByteCount,
                estimate.telemetryStringUTF8ByteCount,
                metric: .resultTelemetryStringUTF8ByteCount,
                maximum: limits.maximumTelemetryStringUTF8ByteCount
            )
        }

        let charge = SemanticResultCharge(
            requestedOutputCount: requestedOutputCount,
            diagnosticRecordCount: diagnosticRecordCount,
            diagnosticScalarCount: diagnosticScalarCount,
            diagnosticStringUTF8ByteCount: diagnosticStringUTF8ByteCount,
            telemetryRecordCount: telemetryRecordCount,
            telemetryScalarCount: telemetryScalarCount,
            telemetryStringUTF8ByteCount: telemetryStringUTF8ByteCount
        )
        try validateResultCharge(charge, limits: limits)
        return charge
    }

    func validateResultCharge(
        _ charge: SemanticResultCharge,
        limits: SemanticResultLimits
    ) throws {
        let values: [
            (UInt64, UInt64, SemanticProgramLimitMetric)
        ] = [
            (
                charge.requestedOutputCount,
                limits.maximumRequestedOutputCount,
                .resultRequestedOutputCount
            ),
            (
                charge.diagnosticRecordCount,
                limits.maximumDiagnosticRecordCount,
                .resultDiagnosticRecordCount
            ),
            (
                charge.diagnosticScalarCount,
                limits.maximumDiagnosticScalarCount,
                .resultDiagnosticScalarCount
            ),
            (
                charge.diagnosticStringUTF8ByteCount,
                limits.maximumDiagnosticStringUTF8ByteCount,
                .resultDiagnosticStringUTF8ByteCount
            ),
            (
                charge.telemetryRecordCount,
                limits.maximumTelemetryRecordCount,
                .resultTelemetryRecordCount
            ),
            (
                charge.telemetryScalarCount,
                limits.maximumTelemetryScalarCount,
                .resultTelemetryScalarCount
            ),
            (
                charge.telemetryStringUTF8ByteCount,
                limits.maximumTelemetryStringUTF8ByteCount,
                .resultTelemetryStringUTF8ByteCount
            )
        ]
        for (actual, maximum, metric) in values where actual > maximum {
            throw SemanticCompilationError.limitExceeded(
                metric: metric,
                actual: actual,
                maximum: maximum
            )
        }
    }

    func resolutionPreparedInputSlotCount(
        _ arguments: [SemanticArgumentID: SemanticResolvedArgument],
        limits: SemanticProgramLimitPolicy
    ) throws -> Int {
        var count = 0
        for argument in arguments.values {
            count = try adding(
                count,
                try preparedInputSlotCount(argument, limits: limits),
                metric: .preparedInputSlotCount,
                maximum: limits.maximumPreparedInputSlotCount
            )
        }
        return count
    }

    func preparedInputSlotCount(
        _ argument: SemanticResolvedArgument,
        limits: SemanticProgramLimitPolicy
    ) throws -> Int {
        switch argument {
        case .value:
            return 0
        case .source, .local:
            return 1
        case .array(let values):
            var count = 0
            for value in values {
                count = try adding(
                    count,
                    try preparedInputSlotCount(value, limits: limits),
                    metric: .preparedInputSlotCount,
                    maximum: limits.maximumPreparedInputSlotCount
                )
            }
            return count
        case .object(let entries):
            var count = 0
            for entry in entries {
                count = try adding(
                    count,
                    try preparedInputSlotCount(entry.value, limits: limits),
                    metric: .preparedInputSlotCount,
                    maximum: limits.maximumPreparedInputSlotCount
                )
            }
            return count
        }
    }

    func appendPreparedInputs(
        from argument: SemanticResolvedArgument,
        node: ProgramNodeSymbol,
        path: [String],
        into inputs: inout [PreparedAutomationInputSlot]
    ) throws {
        switch argument {
        case .value:
            return
        case .source(let source, let preparedSlot):
            inputs.append(
                PreparedAutomationInputSlot(
                    id: preparedSlot,
                    expectedKind: try preparedKind(for: source.type),
                    reference: .existing(try preparedIdentity(for: source))
                )
            )
        case .local(let local, let preparedSlot):
            inputs.append(
                PreparedAutomationInputSlot(
                    id: preparedSlot,
                    expectedKind: try preparedKind(for: local.kind),
                    reference: .local(preparedSlotID(node: local.node, output: local.output))
                )
            )
        case .array(let values):
            for (index, value) in values.enumerated() {
                try appendPreparedInputs(
                    from: value,
                    node: node,
                    path: path + ["index", String(index)],
                    into: &inputs
                )
            }
        case .object(let entries):
            for entry in entries {
                try appendPreparedInputs(
                    from: entry.value,
                    node: node,
                    path: path + ["key", entry.key],
                    into: &inputs
                )
            }
        }
    }

    func preparedSlotID(node: ProgramNodeSymbol, path: [String]) -> PreparedAutomationSlotID {
        PreparedAutomationSlotID(
            canonicalSlotID(
                components: ["argument", node.rawValue] + path
            )
        )
    }

    func preparedSlotID(node: ProgramNodeSymbol, argument: SemanticArgumentID) -> PreparedAutomationSlotID {
        preparedSlotID(node: node, path: [argument.rawValue])
    }

    func preparedSlotID(node: ProgramNodeSymbol, output: SemanticOutputID) -> PreparedAutomationSlotID {
        PreparedAutomationSlotID(
            canonicalSlotID(
                components: ["output", node.rawValue, output.rawValue]
            )
        )
    }

    func canonicalSlotID(components: [String]) -> String {
        let encoded = components.map { component in
            "\(component.utf8.count)#\(component)"
        }.joined()
        return "semantic-slot-v1:\(encoded)"
    }

    func preparedIdentity(for reference: SemanticSourceReference) throws -> PreparedAutomationIdentity {
        switch reference {
        case .feature(let id): return .feature(id)
        case .sourceBody(let featureID, let role): return .sourceBody(featureID: featureID, role: role)
        case .sceneNode(let id): return .sceneNode(id)
        case .componentDefinition(let id): return .componentDefinition(id)
        case .componentInstance(let id): return .componentInstance(id)
        case .patternArraySource(let id): return .patternArraySource(id)
        }
    }

    func preparedKind(for type: SemanticValueType) throws -> PreparedAutomationIdentityKind {
        switch type {
        case .feature: return .feature
        case .sourceBody(let role): return .sourceBody(role: role)
        case .sceneNode: return .sceneNode
        case .componentDefinition: return .componentDefinition
        case .componentInstance: return .componentInstance
        case .patternArraySource: return .patternArraySource
        case .text, .boolean, .integer, .number, .point, .direction, .plane,
             .transform, .array, .object:
            throw SemanticCompilationError.lowererContractViolation(
                node: ProgramNodeSymbol("<input>"),
                message: "Prepared source inputs must use source identity kinds."
            )
        }
    }

    func analyze(
        _ expression: BoundedScalarExpression,
        parameters: [ProgramParameterID: SemanticTypedValue],
        limits: SemanticProgramLimitPolicy,
        depth: Int = 1
    ) throws -> ExpressionAnalysis {
        try checkCount(depth, maximum: limits.maximumExpressionDepth, metric: .expressionDepth)
        switch expression {
        case .literal(let value):
            let scalar = try scalar(value)
            return ExpressionAnalysis(
                type: .number(unit: scalar.unit),
                value: .number(scalar.magnitude, unit: scalar.unit),
                count: 1,
                depth: depth,
                work: 1
            )
        case .parameter(let id):
            guard let value = parameters[id] else {
                throw SemanticCompilationError.missingParameter(id)
            }
            let scalar = try scalar(value)
            return ExpressionAnalysis(
                type: .number(unit: scalar.unit),
                value: .number(scalar.magnitude, unit: scalar.unit),
                count: 1,
                depth: depth,
                work: 1
            )
        case .add(let lhs, let rhs):
            return try combine(lhs, rhs, parameters: parameters, limits: limits, depth: depth, operation: +, units: .same)
        case .subtract(let lhs, let rhs):
            return try combine(lhs, rhs, parameters: parameters, limits: limits, depth: depth, operation: -, units: .same)
        case .multiply(let lhs, let rhs):
            return try combine(lhs, rhs, parameters: parameters, limits: limits, depth: depth, operation: *, units: .oneUnitless)
        case .divide(let lhs, let rhs):
            return try divide(lhs, by: rhs, parameters: parameters, limits: limits, depth: depth)
        case .negate(let value):
            let operand = try analyze(value, parameters: parameters, limits: limits, depth: depth + 1)
            let scalar = try self.scalar(operand.value)
            return ExpressionAnalysis(
                type: operand.type,
                value: .number(-scalar.magnitude, unit: scalar.unit),
                count: try adding(1, operand.count, metric: .expressionCount, maximum: limits.maximumExpressionCount),
                depth: operand.depth,
                work: try adding(1, operand.work, metric: .expressionWork, maximum: limits.maximumExpressionWork)
            )
        }
    }

    enum UnitRule {
        case same
        case oneUnitless
        case rhsUnitless
    }

    func combine(
        _ lhs: BoundedScalarExpression,
        _ rhs: BoundedScalarExpression,
        parameters: [ProgramParameterID: SemanticTypedValue],
        limits: SemanticProgramLimitPolicy,
        depth: Int,
        operation: (Double, Double) -> Double,
        units: UnitRule
    ) throws -> ExpressionAnalysis {
        let left = try analyze(lhs, parameters: parameters, limits: limits, depth: depth + 1)
        let right = try analyze(rhs, parameters: parameters, limits: limits, depth: depth + 1)
        let leftScalar = try scalar(left.value)
        let rightScalar = try scalar(right.value)
        let unit: SemanticUnit
        switch units {
        case .same:
            guard leftScalar.unit == rightScalar.unit else {
                throw SemanticCompilationError.arithmeticInvalid
            }
            unit = leftScalar.unit
        case .oneUnitless:
            guard leftScalar.unit == .unitless || rightScalar.unit == .unitless else {
                throw SemanticCompilationError.arithmeticInvalid
            }
            unit = leftScalar.unit == .unitless ? rightScalar.unit : leftScalar.unit
        case .rhsUnitless:
            guard rightScalar.unit == .unitless else {
                throw SemanticCompilationError.arithmeticInvalid
            }
            unit = leftScalar.unit
        }
        let result = operation(leftScalar.magnitude, rightScalar.magnitude)
        guard result.isFinite else { throw SemanticCompilationError.arithmeticInvalid }
        return ExpressionAnalysis(
            type: .number(unit: unit),
            value: .number(result, unit: unit),
            count: try adding(
                1,
                try adding(left.count, right.count, metric: .expressionCount, maximum: limits.maximumExpressionCount),
                metric: .expressionCount,
                maximum: limits.maximumExpressionCount
            ),
            depth: max(left.depth, right.depth),
            work: try adding(
                1,
                try adding(left.work, right.work, metric: .expressionWork, maximum: limits.maximumExpressionWork),
                metric: .expressionWork,
                maximum: limits.maximumExpressionWork
            )
        )
    }

    func divide(
        _ lhs: BoundedScalarExpression,
        by rhs: BoundedScalarExpression,
        parameters: [ProgramParameterID: SemanticTypedValue],
        limits: SemanticProgramLimitPolicy,
        depth: Int
    ) throws -> ExpressionAnalysis {
        let left = try analyze(lhs, parameters: parameters, limits: limits, depth: depth + 1)
        let right = try analyze(rhs, parameters: parameters, limits: limits, depth: depth + 1)
        let leftScalar = try scalar(left.value)
        let rightScalar = try scalar(right.value)
        guard rightScalar.unit == .unitless, rightScalar.magnitude != 0 else {
            throw SemanticCompilationError.arithmeticInvalid
        }
        let result = leftScalar.magnitude / rightScalar.magnitude
        guard result.isFinite else {
            throw SemanticCompilationError.arithmeticInvalid
        }
        return ExpressionAnalysis(
            type: .number(unit: leftScalar.unit),
            value: .number(result, unit: leftScalar.unit),
            count: try adding(
                1,
                try adding(left.count, right.count, metric: .expressionCount, maximum: limits.maximumExpressionCount),
                metric: .expressionCount,
                maximum: limits.maximumExpressionCount
            ),
            depth: max(left.depth, right.depth),
            work: try adding(
                1,
                try adding(left.work, right.work, metric: .expressionWork, maximum: limits.maximumExpressionWork),
                metric: .expressionWork,
                maximum: limits.maximumExpressionWork
            )
        )
    }

    func scalar(_ value: SemanticTypedValue) throws -> (magnitude: Double, unit: SemanticUnit) {
        switch value {
        case .integer(let value): return (Double(value), .unitless)
        case .number(let value, let unit):
            guard value.isFinite else { throw SemanticCompilationError.arithmeticInvalid }
            return (value, unit)
        case .text, .boolean, .point, .direction, .plane, .transform, .array, .object:
            throw SemanticCompilationError.arithmeticInvalid
        }
    }
}
