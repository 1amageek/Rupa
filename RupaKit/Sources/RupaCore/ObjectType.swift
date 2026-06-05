import Foundation

public protocol ObjectType: Sendable {
    static var definition: ObjectTypeDefinition { get }
}
