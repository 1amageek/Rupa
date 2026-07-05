import Foundation

public struct DrawingProjectionQuery: Codable, Equatable, Sendable {
    public var savedViewID: SavedViewID
    public var toleranceMeters: Double?
    public var maximumStrokeCount: Int

    public init(
        savedViewID: SavedViewID,
        toleranceMeters: Double? = nil,
        maximumStrokeCount: Int = 10_000
    ) {
        self.savedViewID = savedViewID
        self.toleranceMeters = toleranceMeters
        self.maximumStrokeCount = maximumStrokeCount
    }
}
