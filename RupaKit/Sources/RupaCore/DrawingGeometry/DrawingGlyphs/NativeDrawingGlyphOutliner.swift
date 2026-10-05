import Foundation
import SwiftCAD
#if canImport(CoreText) && canImport(CoreGraphics)
import CoreText
import CoreGraphics
#endif

/// Publishes actual Native shaped glyph paths, retaining requested/resolved font provenance.
public struct NativeDrawingGlyphOutliner: DrawingGlyphOutlining {
    public init() {}

    public func outlines(text: String, identity: String, font: DrawingGlyphFont, fontSize: Double,
                         baseline: Point2D, usage: inout DrawingExchangeUsage) throws -> [DrawingGlyphOutline] {
        guard !text.isEmpty, !identity.isEmpty, fontSize.isFinite, fontSize > 0,
              baseline.x.isFinite, baseline.y.isFinite else {
            throw invalid("Drawing glyph input must have text, identity, finite baseline and positive point size.")
        }
        #if canImport(CoreText) && canImport(CoreGraphics)
        let textBytes = text.utf8.count.multipliedReportingOverflow(by: 2)
        guard !textBytes.overflow else { throw invalid("Drawing text admission overflowed.") }
        try usage.charge(entities: 1, work: text.utf16.count, bytes: textBytes.partialValue)
        try usage.check()
        let requested = CTFontCreateWithName(font.postScriptName as CFString, CGFloat(fontSize), nil)
        guard CTFontCopyPostScriptName(requested) as String == font.postScriptName else {
            throw invalid("The requested drawing font did not resolve to its original PostScript identity.")
        }
        let attributed = NSAttributedString(string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): requested])
        let line = CTLineCreateWithAttributedString(attributed)
        let nativeRuns = CTLineGetGlyphRuns(line)
        let runCount = CFArrayGetCount(nativeRuns)
        let outputBytes = runCount.multipliedReportingOverflow(by:
            MemoryLayout<DrawingGlyphOutline>.stride + MemoryLayout<CTRun>.stride)
        guard !outputBytes.overflow else { throw invalid("Glyph run admission overflowed.") }
        try usage.charge(entities: runCount, bytes: outputBytes.partialValue)
        guard let runs = nativeRuns as? [CTRun], runs.count == runCount else {
            throw invalid("Native glyph runs are malformed.")
        }
        guard !runs.isEmpty || text.allSatisfy(\.isWhitespace) else {
            throw invalid("Native shaping produced no runs for non-whitespace text.")
        }
        var output: [DrawingGlyphOutline] = []
        output.reserveCapacity(runs.count)
        let nativeText = text as NSString
        for (ordinal, run) in runs.enumerated() {
            try usage.check(); try usage.charge(work: 1)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName],
                  CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else {
                throw invalid("Native glyph run has no original resolved font.")
            }
            // The SDK's immutable run dictionary is retained and its concrete CF
            // type was checked above; this bridge does not reinterpret arbitrary storage.
            let resolvedFont = value as! CTFont
            let nativeResolvedName = CTFontCopyPostScriptName(resolvedFont)
            let nameBytes = CFStringGetLength(nativeResolvedName).multipliedReportingOverflow(by: 4)
            guard !nameBytes.overflow else { throw invalid("Resolved font identity admission overflowed.") }
            try usage.charge(bytes: nameBytes.partialValue)
            let resolvedName = nativeResolvedName as String
            guard resolvedName == font.postScriptName || font.allowedFallbackPostScriptNames.contains(resolvedName) else {
                throw invalid("Native shaping selected an unapproved fallback font.")
            }
            let range = CTRunGetStringRange(run)
            guard range.location >= 0, range.length >= 0,
                  range.location <= nativeText.length, range.length <= nativeText.length - range.location else {
                throw invalid("Native glyph run exceeds original Unicode text.")
            }
            let runBytes = range.length.multipliedReportingOverflow(by: 4)
            guard !runBytes.overflow else { throw invalid("Native glyph run text admission overflowed.") }
            try usage.charge(bytes: runBytes.partialValue)
            let runText = nativeText.substring(with: NSRange(location: range.location, length: range.length))
            let count = CTRunGetGlyphCount(run)
            guard count >= 0 else { throw invalid("Native glyph count is negative.") }
            let matrix = CTRunGetTextMatrix(run)
            guard [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty].allSatisfy({ $0.isFinite }) else {
                throw invalid("Native glyph text matrix is nonfinite.")
            }
            var commands: [DrawingGlyphPathCommand] = []
            var commandCapacity = 0
            func appendCommand(_ command: DrawingGlyphPathCommand, usage: inout DrawingExchangeUsage) throws {
                try usage.charge(entities: 1, work: 1)
                if commands.count == commandCapacity {
                    let doubled = commandCapacity.multipliedReportingOverflow(by: 2)
                    guard !doubled.overflow else { throw invalid("Native glyph command capacity overflowed.") }
                    let capacity = max(1, doubled.partialValue)
                    let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<DrawingGlyphPathCommand>.stride)
                    guard !bytes.overflow else { throw invalid("Native glyph command storage overflowed.") }
                    try usage.charge(bytes: bytes.partialValue)
                    commands.reserveCapacity(capacity); commandCapacity = capacity
                }
                commands.append(command)
            }
            func consume(_ glyphs: UnsafeBufferPointer<CGGlyph>, _ positions: UnsafeBufferPointer<CGPoint>,
                         _ stringIndices: UnsafeBufferPointer<CFIndex>) throws {
                func isOriginalWhitespace(_ index: Int) throws -> Bool {
                    let start = stringIndices[index]
                    guard start >= range.location, start < range.location + range.length else {
                        throw invalid("Native glyph has no valid original Unicode cluster.")
                    }
                    var end = range.location + range.length
                    // Original cluster boundaries can be nonmonotonic (RTL/ligatures).
                    // Search the retained Native index array without a second index map.
                    for candidate in stringIndices {
                        try usage.charge(work: 1)
                        guard candidate >= range.location, candidate < range.location + range.length else {
                            throw invalid("Native glyph index exceeds the original run.")
                        }
                        if candidate > start { end = min(end, candidate) }
                    }
                    let clusterBytes = (end - start).multipliedReportingOverflow(by: 4)
                    guard !clusterBytes.overflow else { throw invalid("Glyph cluster admission overflowed.") }
                    try usage.charge(work: end - start, bytes: clusterBytes.partialValue)
                    let cluster = nativeText.substring(with: NSRange(location: start, length: end - start))
                    return !cluster.isEmpty && cluster.allSatisfy(\.isWhitespace)
                }
                for index in 0..<count {
                    try usage.check(); try usage.charge(work: 1)
                    guard glyphs[index] != 0 else {
                        guard try isOriginalWhitespace(index) else {
                            throw invalid("Native shaping could not produce an original glyph for the requested text.")
                        }
                        continue
                    }
                    let position = positions[index]
                    guard position.x.isFinite, position.y.isFinite else { throw invalid("Native glyph position is nonfinite.") }
                    var transform = matrix
                    transform.tx = matrix.a * position.x + matrix.c * position.y + CGFloat(baseline.x)
                    transform.ty = matrix.b * position.x + matrix.d * position.y + CGFloat(baseline.y)
                    guard transform.tx.isFinite, transform.ty.isFinite else {
                        throw invalid("Native glyph placement exceeds paper coordinate precision.")
                    }
                    guard let path = CTFontCreatePathForGlyph(resolvedFont, glyphs[index], &transform) else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Colored/non-outline glyph families
                        // need their original Native image producer in this page path. The
                        // public page glyph route cannot claim them complete or draw a blank.
                        guard try isOriginalWhitespace(index) else {
                            throw invalid("The original shaped glyph has no publishable vector outline.")
                        }
                        continue
                    }
                    var pathFailure: Error?
                    var originalStart: Point2D?
                    var activeContour = false
                    // CGPathApplyWithBlock is CF_NOESCAPE in the fixed Native SDK.
                    // Element/point pointers are borrowed only within this callback.
                    path.applyWithBlock { pointer in
                        guard pathFailure == nil else { return }
                        do {
                            let element = pointer.pointee
                            func point(_ index: Int) throws -> Point2D {
                                let value = element.points[index]
                                guard value.x.isFinite, value.y.isFinite else { throw invalid("Glyph outline coordinate is nonfinite.") }
                                return Point2D(x: Double(value.x), y: Double(value.y))
                            }
                            try usage.charge(work: 1)
                            let command: DrawingGlyphPathCommand
                            switch element.type {
                            case .moveToPoint: command = .move(try point(0))
                            case .addLineToPoint: command = .line(try point(0))
                            case .addQuadCurveToPoint: command = .quadratic(control: try point(0), end: try point(1))
                            case .addCurveToPoint: command = .cubic(firstControl: try point(0), secondControl: try point(1), end: try point(2))
                            case .closeSubpath: command = .close
                            @unknown default: throw invalid("Native glyph path command is unknown.")
                            }
                            switch command {
                            case .move(let start):
                                if activeContour { try appendCommand(.close, usage: &usage) }
                                originalStart = start; activeContour = true
                                try appendCommand(command, usage: &usage)
                            case .close:
                                if activeContour { try appendCommand(.close, usage: &usage); activeContour = false }
                            case .line, .quadratic, .cubic:
                                if !activeContour {
                                    guard let start = originalStart else { throw invalid("Native glyph drawing command has no original current point.") }
                                    try appendCommand(.move(start), usage: &usage); activeContour = true
                                }
                                try appendCommand(command, usage: &usage)
                            }
                        } catch { pathFailure = error }
                    }
                    if let pathFailure { throw pathFailure }
                    if activeContour { try appendCommand(.close, usage: &usage) }
                }
            }
            if count == 0 {
                guard runText.allSatisfy(\.isWhitespace) else {
                    throw invalid("Native shaping produced no glyphs for non-whitespace text.")
                }
            } else if let glyphs = CTRunGetGlyphsPtr(run), let positions = CTRunGetPositionsPtr(run),
                      let indices = CTRunGetStringIndicesPtr(run) {
                try consume(UnsafeBufferPointer(start: glyphs, count: count),
                    UnsafeBufferPointer(start: positions, count: count),
                    UnsafeBufferPointer(start: indices, count: count))
            } else {
                let bufferBytes = count.multipliedReportingOverflow(by: MemoryLayout<CGGlyph>.stride + MemoryLayout<CGPoint>.stride + MemoryLayout<CFIndex>.stride)
                guard !bufferBytes.overflow else { throw invalid("Native glyph buffer admission overflowed.") }
                try usage.charge(work: count, bytes: bufferBytes.partialValue)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                // This branch requires count > 0; all initialized buffers have storage.
                glyphs.withUnsafeMutableBufferPointer { CTRunGetGlyphs(run, CFRange(location: 0, length: count), $0.baseAddress!) }
                positions.withUnsafeMutableBufferPointer { CTRunGetPositions(run, CFRange(location: 0, length: count), $0.baseAddress!) }
                indices.withUnsafeMutableBufferPointer { CTRunGetStringIndices(run, CFRange(location: 0, length: count), $0.baseAddress!) }
                try glyphs.withUnsafeBufferPointer { glyphs in
                    try positions.withUnsafeBufferPointer { positions in
                        try indices.withUnsafeBufferPointer { indices in try consume(glyphs, positions, indices) }
                    }
                }
            }
            guard !commands.isEmpty || runText.allSatisfy(\.isWhitespace) else { throw invalid("A non-whitespace text run has no outlines.") }
            let identityBytes = identity.utf8.count.addingReportingOverflow(25)
            guard !identityBytes.overflow else { throw invalid("Glyph identity admission overflowed.") }
            try usage.charge(bytes: identityBytes.partialValue)
            let ordinalText = String(ordinal)
            let resolvedSize = Double(CTFontGetSize(resolvedFont))
            guard resolvedSize.isFinite, resolvedSize > 0 else { throw invalid("Native resolved glyph size is invalid.") }
            output.append(DrawingGlyphOutline(text: runText, fontPostScriptName: resolvedName,
                fontSize: resolvedSize, identity: identity + ".run." + ordinalText, commands: commands))
        }
        return output
        #else
        // FIXME(INCOMPLETE_IMPLEMENTATION): The public page glyph path requires
        // an original shaping/outlining backend on this platform before completion.
        throw invalid("Original Native glyph outlining is unavailable on this platform.")
        #endif
    }

    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .evaluationFailed, message: message)
    }
}
