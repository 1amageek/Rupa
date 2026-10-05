import Foundation
import RupaCore
import SwiftCAD

/// Completed format publication; source metadata comes from the actual composed page.
public struct DrawingPageAutomationResult: Codable, Equatable, Sendable {
    public let savedViewID: SavedViewID
    public let generation: DocumentGeneration
    public let format: ExchangeFileFormat
    public let width: Double
    public let height: Double
    public let pathCount: Int
    public let regionCount: Int
    public let glyphCount: Int
    public let sectionCount: Int
    public let output: Output
    public let consumedWork: Int
    public let consumedBytes: Int
    public let consumedEntities: Int

    public enum Output: Codable, Equatable, Sendable {
        case bytes(Data)
        case file(URL)
    }

    init(page: DrawingGeometricPage, generation: DocumentGeneration, format: ExchangeFileFormat,
        output: Output, usage: DrawingExchangeUsage) {
        savedViewID = page.original.savedView.id; self.generation = generation; self.format = format
        width = page.page.width; height = page.page.height; pathCount = page.page.paths.count
        regionCount = page.page.regions.count; glyphCount = page.page.glyphs.count
        sectionCount = page.sections?.values.count ?? 0; self.output = output
        consumedWork = usage.consumedWork; consumedBytes = usage.consumedBytes
        consumedEntities = usage.consumedEntities
    }
}
