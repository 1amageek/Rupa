import CoreText
import Foundation
import RupaCore
import SwiftCAD

/// The outlines of typed text as closed cubic Bezier chains, for Text's curves: the platform's
/// font engine lays the text out and gives each glyph's contours, and every contour becomes one
/// closed chain in the sketch plane's coordinates, in meters, with the text's baseline starting
/// at the origin.
///
/// A line element becomes a straight cubic span and a quadratic one its exact cubic elevation,
/// so the chains draw the glyphs exactly; elements shorter than the modeling distance are left
/// out, since a span may not collapse to a point.
struct SketchTextOutliner {
    enum Failure: Error, LocalizedError, Equatable {
        case emptyText
        case invalidSize
        case unknownFont(String)
        case noOutline

        var errorDescription: String? {
            switch self {
            case .emptyText: "Text needs something typed."
            case .invalidSize: "Text size must be positive and finite."
            case .unknownFont(let name): "Text: the font \(name) is not available."
            case .noOutline: "Text: the typed characters have no outline in this font."
            }
        }
    }

    /// Each closed contour's control points: 3n + 1 points whose last is its first.
    func contours(of text: String, fontName: String, size: Double) throws -> [[Point2D]] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.emptyText }
        guard size.isFinite, size > 0 else { throw Failure.invalidSize }
        // The font engine lays out at a reference size and the outline is scaled to `size`, so
        // no size-dependent hinting reaches the curves.
        let referenceSize = 1000.0
        let scale = size / referenceSize
        let font = CTFontCreateWithName(fontName as CFString, CGFloat(referenceSize), nil)
        guard (CTFontCopyFamilyName(font) as String) == fontName || (CTFontCopyPostScriptName(font) as String) == fontName else {
            throw Failure.unknownFont(fontName)
        }
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var contours: [[Point2D]] = []
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let runFont = runFont(run) ?? font
            for (glyph, position) in zip(glyphs, positions) {
                guard let path = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                contours += chains(of: path, offset: position, scale: scale)
            }
        }
        guard !contours.isEmpty else { throw Failure.noOutline }
        return contours
    }

    private func runFont(_ run: CTRun) -> CTFont? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName as String],
              CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { return nil }
        // The type identifier was checked above, so the cast cannot fail.
        return (value as! CTFont)
    }

    /// The path's closed contours as cubic chains moved by `offset` and scaled by `scale`.
    private func chains(of path: CGPath, offset: CGPoint, scale: Double) -> [[Point2D]] {
        let minimum = ModelingTolerance.standard.distance
        var result: [[Point2D]] = []
        var chain: [Point2D] = []
        func point(_ p: CGPoint) -> Point2D { Point2D(x: Double(p.x + offset.x) * scale, y: Double(p.y + offset.y) * scale) }
        func distance(_ a: Point2D, _ b: Point2D) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }
        func appendCubic(_ c1: Point2D, _ c2: Point2D, _ end: Point2D) {
            guard let start = chain.last, distance(start, end) > minimum else { return }
            chain += [c1, c2, end]
        }
        func appendLine(to end: Point2D) {
            guard let start = chain.last else { return }
            appendCubic(
                Point2D(x: start.x + (end.x - start.x) / 3, y: start.y + (end.y - start.y) / 3),
                Point2D(x: start.x + 2 * (end.x - start.x) / 3, y: start.y + 2 * (end.y - start.y) / 3),
                end
            )
        }
        func close() {
            if let first = chain.first, let last = chain.last, distance(first, last) > minimum {
                appendLine(to: first)
            } else if chain.count >= 4 {
                chain[chain.count - 1] = chain[0]
            }
            // A loop needs two spans at least; one span would start and end at one point.
            if chain.count >= 7 { result.append(chain) }
            chain = []
        }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                if chain.count >= 4 { close() }
                chain = [point(points[0])]
            case .addLineToPoint:
                appendLine(to: point(points[0]))
            case .addQuadCurveToPoint:
                guard let start = chain.last else { return }
                let control = point(points[0]), end = point(points[1])
                // A quadratic's exact cubic: its inner points lie two thirds of the way to its control.
                appendCubic(
                    Point2D(x: start.x + 2 * (control.x - start.x) / 3, y: start.y + 2 * (control.y - start.y) / 3),
                    Point2D(x: end.x + 2 * (control.x - end.x) / 3, y: end.y + 2 * (control.y - end.y) / 3),
                    end
                )
            case .addCurveToPoint:
                appendCubic(point(points[0]), point(points[1]), point(points[2]))
            case .closeSubpath:
                close()
            @unknown default:
                break
            }
        }
        if chain.count >= 4 { close() }
        return result
    }
}
