import Foundation

public struct GeometryRepresentationID: StableStringIdentifier {
    public static let identityName = "Geometry representation IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID().uuidString)
    }
}
