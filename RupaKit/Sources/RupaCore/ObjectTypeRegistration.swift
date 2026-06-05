import Foundation

public struct ObjectTypeRegistration: Sendable {
    public var definition: ObjectTypeDefinition

    public init<Type: ObjectType>(_ objectType: Type.Type) {
        self.definition = objectType.definition
    }

    public init(definition: ObjectTypeDefinition) {
        self.definition = definition
    }
}
