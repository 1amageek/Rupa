import Foundation

public struct GeometrySourceID: StableStringIdentifier {
    public static let identityName = "Geometry source IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID().uuidString)
    }
}
