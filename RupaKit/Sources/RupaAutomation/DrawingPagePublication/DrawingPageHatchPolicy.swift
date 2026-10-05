import RupaCore
import SwiftCAD

/// Original cutting-UV hatch spacing and admission, without paper-dependent inference.
public struct DrawingPageHatchPolicy: Codable, Equatable, Sendable {
    public let spacing: Double
    public let maximumRows: Int
    public let maximumBoundaryCurves: Int
    public let maximumEventsPerRow: Int
    public let maximumSegments: Int
    public init(spacing: Double, maximumRows: Int, maximumBoundaryCurves: Int,
        maximumEventsPerRow: Int, maximumSegments: Int) {
        self.spacing = spacing; self.maximumRows = maximumRows
        self.maximumBoundaryCurves = maximumBoundaryCurves; self.maximumEventsPerRow = maximumEventsPerRow
        self.maximumSegments = maximumSegments
    }
    func validate() throws {
        guard spacing.isFinite, spacing > 0, maximumRows > 0, maximumBoundaryCurves > 0,
              maximumEventsPerRow > 0, maximumSegments > 0 else {
            throw EditorError(code: .commandInvalid, message: "Original hatch policy is invalid.")
        }
    }
}
