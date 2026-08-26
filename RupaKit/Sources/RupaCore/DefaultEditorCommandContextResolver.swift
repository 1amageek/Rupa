import Foundation

/// Resolves the context-dependent inputs required by the built-in editor commands.
public struct DefaultEditorCommandContextResolver: EditorCommandContextResolving, Sendable {
    public init() {}

    public func resolve(
        _ command: EditorCommand,
        in context: EditorCommandPlanningContext
    ) throws -> EditorCommand {
        switch command {
        case .offsetCurve(let target, let distance, var options, let vertexHandle):
            guard options.supportTarget == nil,
                  case .edge = target.component else {
                return command
            }

            let resolution = try EdgeOffsetSupportFaceResolver().resolve(
                edgeTarget: target,
                selection: context.selection,
                document: context.document,
                objectRegistry: context.objectRegistry
            )
            guard resolution.status != .ambiguous else {
                throw EditorError(
                    code: .commandInvalid,
                    message: resolution.diagnosticMessage
                        ?? EdgeOffsetSupportFaceResolver.missingSupportFaceMessage
                )
            }
            guard let supportTarget = resolution.supportTarget else {
                throw EditorError(
                    code: .commandInvalid,
                    message: resolution.diagnosticMessage
                        ?? EdgeOffsetSupportFaceResolver.missingSupportFaceMessage
                )
            }
            options.supportTarget = supportTarget
            return .offsetCurve(
                target: target,
                distance: distance,
                options: options,
                vertexHandle: vertexHandle
            )
        default:
            return command
        }
    }

    public func resolve(
        _ commands: [EditorCommand],
        in context: EditorCommandPlanningContext
    ) throws -> [EditorCommand] {
        try commands.map { command in
            try resolve(command, in: context)
        }
    }

    public func requireFullyResolved(_ command: EditorCommand) throws {
        guard case .offsetCurve(let target, _, let options, _) = command,
              case .edge = target.component,
              options.supportTarget == nil else {
            return
        }
        throw EditorError(
            code: .commandInvalid,
            message: EdgeOffsetSupportFaceResolver.missingSupportFaceMessage
        )
    }
}
