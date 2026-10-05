import SwiftCAD

/// A section of one actual original body occurrence in the authored world frame.
public struct DrawingOccurrenceSection: Sendable {
    public let occurrence: DrawingOccurrenceBodyPlacement
    public let original: BRepDrawingSection
}
