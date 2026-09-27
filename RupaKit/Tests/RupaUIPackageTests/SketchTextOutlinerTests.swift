import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// Text's outlines: closed cubic chains of each glyph contour, at the chosen size.
@MainActor
@Suite struct SketchTextOutlinerTests {
    private let outliner = SketchTextOutliner()

    @Test func eachGlyphContourIsAClosedChainAtTheSize() throws {
        let o = try outliner.contours(of: "O", fontName: "Helvetica", size: 0.01)
        #expect(o.count == 2)
        for contour in o {
            #expect(contour.count >= 7 && (contour.count - 1).isMultiple(of: 3))
            #expect(contour.first == contour.last)
        }
        let points = o.flatMap { $0 }
        let height = (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
        // A capital's height is below the font size and near three quarters of it.
        #expect(height > 0.005 && height < 0.01)
        #expect(try outliner.contours(of: "I", fontName: "Helvetica", size: 0.01).count == 1)
    }

    @Test func missingTextOrFontIsRefused() {
        #expect(throws: SketchTextOutliner.Failure.emptyText) { _ = try outliner.contours(of: "  ", fontName: "Helvetica", size: 0.01) }
        #expect(throws: SketchTextOutliner.Failure.invalidSize) { _ = try outliner.contours(of: "A", fontName: "Helvetica", size: 0) }
        #expect(throws: SketchTextOutliner.Failure.unknownFont("No Such Font 1234")) {
            _ = try outliner.contours(of: "A", fontName: "No Such Font 1234", size: 0.01)
        }
    }

    @Test func theCurvesMakeARegionEachLoopEncloses() throws {
        let contours = try outliner.contours(of: "I", fontName: "Helvetica", size: 0.01)
        var entities: [SketchEntityID: SketchEntity] = [:]
        for contour in contours {
            entities[SketchEntityID()] = .spline(SketchSpline(
                controlPoints: contour.map { SketchPoint(x: .length($0.x, .meter), y: .length($0.y, .meter)) },
                isClosed: true
            ))
        }
        let session = EditorSession()
        _ = try session.execute(.createSketch(name: "Text", sketch: Sketch(plane: .xy, entities: entities), geometryRole: .curve))
        let summary = try SketchEntitySnapshotService().snapshot(document: session.document)
        #expect(summary.regions.count == 1)
    }
}
