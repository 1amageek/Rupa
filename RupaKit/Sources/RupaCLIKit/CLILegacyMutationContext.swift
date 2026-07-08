import Foundation
import RupaAgentTransport
import RupaCore

struct CLILegacyMutationContext {
    let target: CLIDocumentTarget
    let writePolicy: CLIDocumentWritePolicy
    let forceFileEdit: Bool
    let agentClient: AgentClient?
}

enum CLILegacyMutationContextResolver {
    static func resolve(
        file: String?,
        mode: CLIEditMode,
        sessionID: UUID?,
        agentSocket: String?,
        forceFileEdit: Bool,
        writeDestination: CLIWriteDestinationOptions
    ) throws -> CLILegacyMutationContext {
        let writePolicy = try writeDestination.writePolicy(
            file: file,
            mode: mode,
            sessionID: sessionID
        )
        return CLILegacyMutationContext(
            target: CLIDocumentTarget(
                fileURL: file.map(URL.init(fileURLWithPath:)),
                sessionID: sessionID
            ),
            writePolicy: writePolicy,
            forceFileEdit: forceFileEdit || writePolicy.requiresFileMode,
            agentClient: CLIAgentClientFactory.makeAgentClient(
                mode: mode,
                sessionID: sessionID,
                socket: agentSocket
            )
        )
    }
}
