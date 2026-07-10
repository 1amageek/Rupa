import Foundation
import SwiftCAD
import RupaCoreTypes

public struct DocumentExportPreflightContext: Sendable {
    public var document: DesignDocument
    public var evaluatedDocument: EvaluatedDocument
    public var generation: DocumentGeneration
    public var outputURL: URL
    public var format: ExchangeFileFormat
    public var outputUnit: LengthDisplayUnit
    public var destinationPolicy: ExportPreset.DestinationPolicy
    public var presetName: String?
    public var dryRun: Bool

    public init(
        document: DesignDocument,
        evaluatedDocument: EvaluatedDocument,
        generation: DocumentGeneration,
        outputURL: URL,
        format: ExchangeFileFormat,
        outputUnit: LengthDisplayUnit,
        destinationPolicy: ExportPreset.DestinationPolicy,
        presetName: String?,
        dryRun: Bool
    ) {
        self.document = document
        self.evaluatedDocument = evaluatedDocument
        self.generation = generation
        self.outputURL = outputURL
        self.format = format
        self.outputUnit = outputUnit
        self.destinationPolicy = destinationPolicy
        self.presetName = presetName
        self.dryRun = dryRun
    }
}
