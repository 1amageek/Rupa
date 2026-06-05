import Foundation
import SwiftCAD

public struct RupaDocumentExportService: Sendable {
    private let pipeline: CADPipeline
    private let exchange: OfficialFormatExchange

    public init(
        pipeline: CADPipeline = CADPipeline(),
        exchange: OfficialFormatExchange = OfficialFormatExchange()
    ) {
        self.pipeline = pipeline
        self.exchange = exchange
    }

    public func export(
        document: RupaDocument,
        generation: DocumentGeneration,
        to outputURL: URL,
        options: RupaExportOptions = RupaExportOptions(),
        dryRun: Bool = false
    ) throws -> RupaExportResult {
        let plan = try resolvedExportPlan(
            for: document,
            outputURL: outputURL,
            options: options
        )

        let evaluatedDocument: EvaluatedDocument
        do {
            try document.validate()
            evaluatedDocument = try pipeline.evaluate(document.cadDocument)
        } catch {
            throw RupaError(
                code: .evaluationFailed,
                message: "Document must evaluate successfully before export: \(String(describing: error))"
            )
        }
        let destinationURL = try resolvedDestinationURL(
            for: outputURL,
            policy: plan.destinationPolicy
        )

        if !dryRun {
            do {
                try exchange.export(
                    evaluatedDocument,
                    as: plan.format,
                    units: plan.unitSystem,
                    to: destinationURL
                )
            } catch {
                throw RupaError(
                    code: .exportFailed,
                    message: "Export failed: \(String(describing: error))"
                )
            }
        }

        let byteCount = dryRun ? 0 : try exportedByteCount(at: destinationURL)
        let message = dryRun
            ? "Export dry run completed for \(plan.format.displayName) at \(destinationURL.path)."
            : "Exported \(plan.format.displayName) to \(destinationURL.path)."
        return RupaExportResult(
            message: message,
            format: plan.format,
            outputPath: destinationURL.path,
            byteCount: byteCount,
            generation: generation,
            dryRun: dryRun,
            presetName: plan.presetName,
            outputUnit: plan.outputUnit,
            destinationPolicy: plan.destinationPolicy,
            diagnostics: [
                RupaDiagnostic(
                    severity: .info,
                    message: "Export completed with \(evaluatedDocument.meshes.count) generated bodies."
                ),
                RupaDiagnostic(
                    severity: .info,
                    message: "Export unit \(plan.outputUnit.rawValue), destination policy \(plan.destinationPolicy.rawValue)."
                ),
            ]
        )
    }

    private func resolvedExportPlan(
        for document: RupaDocument,
        outputURL: URL,
        options: RupaExportOptions
    ) throws -> RupaResolvedExportPlan {
        guard let extensionFormat = ExchangeFileFormat.format(forFileExtension: outputURL.pathExtension) else {
            throw RupaError(
                code: .exportFailed,
                message: "Unsupported export file extension .\(outputURL.pathExtension)."
            )
        }

        let hasPresetID = options.presetID != nil
        let hasPresetName = options.presetName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard !(hasPresetID && hasPresetName) else {
            throw RupaError(
                code: .commandInvalid,
                message: "Export preset must be selected by ID or name, not both."
            )
        }

        if let preset = try resolvedPreset(in: document.productMetadata, options: options) {
            guard preset.format == extensionFormat else {
                throw RupaError(
                    code: .commandInvalid,
                    message: "Export preset \(preset.name) writes \(preset.format.displayName), but output path selects \(extensionFormat.displayName)."
                )
            }
            let outputUnit = preset.outputUnit
            return RupaResolvedExportPlan(
                format: preset.format,
                outputUnit: outputUnit,
                unitSystem: UnitSystem(
                    length: outputUnit.swiftCADLengthUnit,
                    angle: document.cadDocument.units.angle
                ),
                destinationPolicy: options.destinationPolicy ?? preset.destinationPolicy,
                presetName: preset.name
            )
        }

        let outputUnit = document.cadDocument.units.length.rupaDisplayUnit
        return RupaResolvedExportPlan(
            format: extensionFormat,
            outputUnit: outputUnit,
            unitSystem: document.cadDocument.units,
            destinationPolicy: options.destinationPolicy ?? .overwrite,
            presetName: nil
        )
    }

    private func resolvedPreset(
        in metadata: RupaProductMetadata,
        options: RupaExportOptions
    ) throws -> RupaExportPreset? {
        if let presetID = options.presetID {
            guard let preset = metadata.exportPresets[presetID] else {
                throw RupaError(
                    code: .commandInvalid,
                    message: "Export preset ID \(presetID.rawValue.uuidString) was not found."
                )
            }
            return preset
        }

        guard let rawName = options.presetName else {
            return nil
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return nil
        }
        guard let preset = metadata.exportPresets.values.first(where: { $0.name == name }) else {
            throw RupaError(
                code: .commandInvalid,
                message: "Export preset \(name) was not found."
            )
        }
        return preset
    }

    private func resolvedDestinationURL(
        for outputURL: URL,
        policy: RupaExportPreset.DestinationPolicy
    ) throws -> URL {
        switch policy {
        case .prompt:
            guard !FileManager.default.fileExists(atPath: outputURL.path) else {
                throw RupaError(
                    code: .exportFailed,
                    message: "Export destination already exists at \(outputURL.path)."
                )
            }
            return outputURL
        case .overwrite:
            return outputURL
        case .versioned:
            return try versionedDestinationURL(for: outputURL)
        }
    }

    private func versionedDestinationURL(for outputURL: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return outputURL
        }

        let directory = outputURL.deletingLastPathComponent()
        let fileExtension = outputURL.pathExtension
        let basename = outputURL.deletingPathExtension().lastPathComponent
        for index in 1...9_999 {
            let filename = fileExtension.isEmpty
                ? "\(basename)-\(index)"
                : "\(basename)-\(index).\(fileExtension)"
            let candidate = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw RupaError(
            code: .exportFailed,
            message: "Could not find an available versioned export path for \(outputURL.path)."
        )
    }

    private func exportedByteCount(at url: URL) throws -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber else {
                throw RupaError(
                    code: .exportFailed,
                    message: "Exported file size is unavailable."
                )
            }
            return size.uint64Value
        } catch let error as RupaError {
            throw error
        } catch {
            throw RupaError(
                code: .exportFailed,
                message: "Exported file could not be inspected: \(error.localizedDescription)"
            )
        }
    }
}

private struct RupaResolvedExportPlan: Sendable {
    var format: ExchangeFileFormat
    var outputUnit: LengthDisplayUnit
    var unitSystem: UnitSystem
    var destinationPolicy: RupaExportPreset.DestinationPolicy
    var presetName: String?
}
