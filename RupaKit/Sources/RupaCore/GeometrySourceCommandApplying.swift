public protocol GeometrySourceCommandApplying: Sendable {
    func apply(
        _ command: GeometrySourceCommand,
        to document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> GeometrySourceCommandApplication
}

public extension GeometrySourceCommandApplying {
    func apply(
        _ command: GeometrySourceCommand,
        to document: DesignDocument
    ) throws -> GeometrySourceCommandApplication {
        try apply(command, to: document, objectRegistry: .builtIn)
    }
}
