import Foundation
import RupaAgentProtocol
import RupaAgentRuntime
import RupaCADDomain
import RupaCoreTypes
import RupaDomainFoundation
import RupaKit

func projectAgentSemanticCompiler() throws -> any SemanticProgramCompiling {
    DefaultSemanticProgramCompiler(registry: try RupaCADDomain.registry())
}

func projectAgentAuthority(
    _ view: ProjectViewSnapshot
) -> AgentProjectAuthorityCoordinate {
    AgentProjectAuthorityCoordinate(
        projectID: view.projectID,
        documentGeneration: view.documentGeneration,
        transactionRevision: view.transactionRevision,
        publicationSequence: view.publicationSequence,
        workspaceRevision: view.workspaceState.revision
    )
}

func projectAgentDirectBoxRequest(
    sessionID: UUID,
    authority: AgentProjectAuthorityCoordinate,
    name: String,
    dryRun: Bool = false
) -> AgentSemanticDirectExecutionRequest {
    AgentSemanticDirectExecutionRequest(
        sessionID: sessionID,
        authority: authority,
        dryRun: dryRun,
        request: AgentSemanticDirectRequest(
            schemaVersion: .init(major: 1, minor: 0, patch: 0),
            operationID: "cad.solid.box",
            operationVersion: .init(major: 1, minor: 0, patch: 0),
            arguments: projectAgentBoxArguments(name: name),
            requestedOutputs: ["body"]
        )
    )
}

func projectAgentBoxArguments(
    name: String,
    originX: Double = 0
) -> [AgentSemanticDirectRequest.ArgumentEntry] {
    [
        .init(name: "name", value: .literal(.text(name))),
        .init(
            name: "origin",
            value: .literal(
                .point(
                    AgentSemanticPoint3D(
                        x: originX,
                        y: 0,
                        z: 0,
                        unit: .meter
                    )
                )
            )
        ),
        .init(name: "width", value: .literal(.number(0.2, unit: .meter))),
        .init(name: "depth", value: .literal(.number(0.1, unit: .meter))),
        .init(name: "height", value: .literal(.number(0.05, unit: .meter))),
    ]
}

func projectAgentProgramBoxNode(
    symbol: String,
    name: String,
    originX: Double = 0
) -> AgentSemanticProgramRequest.Node {
    AgentSemanticProgramRequest.Node(
        symbol: symbol,
        operationID: "cad.solid.box",
        operationVersion: .init(major: 1, minor: 0, patch: 0),
        arguments: [
            .init(name: "name", value: .literal(.text(name))),
            .init(
                name: "origin",
                value: .literal(
                    .point(
                        AgentSemanticPoint3D(
                            x: originX,
                            y: 0,
                            z: 0,
                            unit: .meter
                        )
                    )
                )
            ),
            .init(name: "width", value: .literal(.number(0.2, unit: .meter))),
            .init(name: "depth", value: .literal(.number(0.1, unit: .meter))),
            .init(name: "height", value: .literal(.number(0.05, unit: .meter))),
        ]
    )
}

func projectAgentSemanticLimits(
    maximumNodeCount: Int
) -> SemanticProgramLimitPolicy {
    let standard = ProjectAgentSemanticProgramLimits.standard
    return SemanticProgramLimitPolicy(
        maximumDecodedValueCount: standard.maximumDecodedValueCount,
        maximumDecodedNestingDepth: standard.maximumDecodedNestingDepth,
        maximumNodeCount: maximumNodeCount,
        maximumEdgeCount: standard.maximumEdgeCount,
        maximumParameterCount: standard.maximumParameterCount,
        maximumRequestedOutputCount: standard.maximumRequestedOutputCount,
        maximumLocalOutputReferenceCount: standard.maximumLocalOutputReferenceCount,
        maximumExpressionCount: standard.maximumExpressionCount,
        maximumExpressionDepth: standard.maximumExpressionDepth,
        maximumExpressionWork: standard.maximumExpressionWork,
        maximumLoweredCommandCount: standard.maximumLoweredCommandCount,
        maximumExpandedSourceWork: standard.maximumExpandedSourceWork,
        maximumPreparedInputSlotCount: standard.maximumPreparedInputSlotCount,
        maximumPreparedOutputSlotCount: standard.maximumPreparedOutputSlotCount,
        resultLimits: standard.resultLimits
    )
}

extension ProjectAgentCommandController {
    func projectAgentHandle(
        _ request: AgentRequest,
        id: String = UUID().uuidString
    ) async -> AgentResponse {
        let handled = await handle(AgentRequestEnvelope(id: id, params: request))
        switch handled {
        case .ordinary(let response), .planned(let response, _):
            return response
        }
    }
}
