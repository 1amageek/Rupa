import Foundation

/// Explicit registered PostScript font authority for Native page glyph shaping.
public struct DrawingGlyphFont: Sendable {
    public let postScriptName: String
    public let allowedFallbackPostScriptNames: [String]

    public init(postScriptName: String, allowedFallbackPostScriptNames: [String] = []) throws {
        guard !postScriptName.isEmpty, !postScriptName.hasPrefix("."),
              allowedFallbackPostScriptNames.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") }) else {
            throw EditorError(code: .commandInvalid, message: "Drawing font names must be explicit registered PostScript names.")
        }
        self.postScriptName = postScriptName
        self.allowedFallbackPostScriptNames = allowedFallbackPostScriptNames
    }
}
