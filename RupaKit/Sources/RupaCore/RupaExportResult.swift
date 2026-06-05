import Foundation
import SwiftCAD

public struct RupaExportResult: Codable, Equatable, Sendable {
    public var message: String
    public var format: ExchangeFileFormat
    public var outputPath: String
    public var byteCount: UInt64
    public var generation: DocumentGeneration
    public var dryRun: Bool
    public var presetName: String?
    public var outputUnit: LengthDisplayUnit
    public var destinationPolicy: RupaExportPreset.DestinationPolicy
    public var diagnostics: [RupaDiagnostic]

    public init(
        message: String,
        format: ExchangeFileFormat,
        outputPath: String,
        byteCount: UInt64,
        generation: DocumentGeneration,
        dryRun: Bool = false,
        presetName: String? = nil,
        outputUnit: LengthDisplayUnit = .meter,
        destinationPolicy: RupaExportPreset.DestinationPolicy = .overwrite,
        diagnostics: [RupaDiagnostic]
    ) {
        self.message = message
        self.format = format
        self.outputPath = outputPath
        self.byteCount = byteCount
        self.generation = generation
        self.dryRun = dryRun
        self.presetName = presetName
        self.outputUnit = outputUnit
        self.destinationPolicy = destinationPolicy
        self.diagnostics = diagnostics
    }
}
