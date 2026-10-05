import SwiftCAD

/// Derived source publications for one indexed original occurrence section.
public struct DrawingSectionPageContribution: Sendable {
    public let sectionIndex: Int
    public let regions: [BRepDrawingMaterialRegion]
    public let hatchSegments: [BRepDrawingHatchSegment]

    public init(sectionIndex: Int, regions: [BRepDrawingMaterialRegion], hatchSegments: [BRepDrawingHatchSegment]) {
        self.sectionIndex = sectionIndex; self.regions = regions; self.hatchSegments = hatchSegments
    }
}
