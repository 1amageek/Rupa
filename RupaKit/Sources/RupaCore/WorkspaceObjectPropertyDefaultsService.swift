public struct WorkspaceObjectPropertyDefaultsService: Sendable {
    public init() {}

    public func defaults(
        for id: ObjectTypeID?,
        ruler: RulerConfiguration,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> ObjectPropertySet {
        guard let id,
              let definition = objectRegistry.definition(for: id) else {
            return ObjectPropertySet()
        }
        let workspaceDefaults = WorkspaceScaleDefaults(ruler: ruler)
        var properties = definition.defaultProperties

        for property in definition.properties {
            guard property.valueKind == .length,
                  let scaleDefault = property.workspaceScaleDefault else {
                continue
            }
            properties[property.id] = .length(scaleDefault.meters(from: workspaceDefaults))
        }

        return definition.resolvedProperties(properties)
    }
}
