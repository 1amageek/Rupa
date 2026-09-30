public protocol GeometrySourceCommandApplying: Sendable {
    /// Applies `command` to `document`, which was validated against `objectRegistry`, and returns
    /// the staged document validated once; a command that changes nothing returns `document`.
    func apply(
        _ command: GeometrySourceCommand,
        to document: ValidatedDesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> GeometrySourceCommandApplication
}

public extension GeometrySourceCommandApplying {
    /// Validates `document` once against `objectRegistry` and applies `command` to it.
    func apply(
        _ command: GeometrySourceCommand,
        to document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> GeometrySourceCommandApplication {
        try apply(
            command,
            to: document.validate(objectRegistry: objectRegistry),
            objectRegistry: objectRegistry
        )
    }
}
