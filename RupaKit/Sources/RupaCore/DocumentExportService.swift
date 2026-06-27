import Foundation
import SwiftCAD
import RupaCoreTypes

public struct DocumentExportService: Sendable {
    private let pipelineOverride: CADPipeline?
    private let exchange: OfficialFormatExchange

    public init(
        pipeline: CADPipeline? = nil,
        exchange: OfficialFormatExchange = OfficialFormatExchange()
    ) {
        self.pipelineOverride = pipeline
        self.exchange = exchange
    }

    public func export(
        document: DesignDocument,
        generation: DocumentGeneration,
        to outputURL: URL,
        options: ExportOptions = ExportOptions(),
        dryRun: Bool = false,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ExportResult {
        let plan = try resolvedExportPlan(
            for: document,
            outputURL: outputURL,
            options: options
        )

        let evaluatedDocument: EvaluatedDocument
        do {
            try document.validate(objectRegistry: objectRegistry)
            let pipeline = pipelineOverride ?? .modelingDefault(
                for: document,
                objectRegistry: objectRegistry
            )
            var exportSourceDocument = document.cadDocument
            exportSourceDocument.units = plan.unitSystem
            evaluatedDocument = try pipeline.evaluate(exportSourceDocument)
        } catch {
            throw EditorError(
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
                if plan.format == .stl, plan.outputUnit == .micrometer {
                    try exportBinarySTLInMicrometers(evaluatedDocument, to: destinationURL)
                } else {
                    try exchange.export(evaluatedDocument, to: destinationURL)
                }
            } catch {
                throw EditorError(
                    code: .exportFailed,
                    message: "Export failed: \(String(describing: error))"
                )
            }
        }

        let byteCount = dryRun ? 0 : try exportedByteCount(at: destinationURL)
        let message = dryRun
            ? "Export dry run completed for \(plan.format.displayName) at \(destinationURL.path)."
            : "Exported \(plan.format.displayName) to \(destinationURL.path)."
        return ExportResult(
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
                EditorDiagnostic(
                    severity: .info,
                    message: "Export completed with \(evaluatedDocument.meshes.count) generated bodies."
                ),
                EditorDiagnostic(
                    severity: .info,
                    message: "Export unit \(plan.outputUnit.rawValue), destination policy \(plan.destinationPolicy.rawValue)."
                ),
            ]
        )
    }

    private func resolvedExportPlan(
        for document: DesignDocument,
        outputURL: URL,
        options: ExportOptions
    ) throws -> ResolvedExportPlan {
        guard let extensionFormat = ExchangeFileFormat.format(forFileExtension: outputURL.pathExtension) else {
            throw EditorError(
                code: .exportFailed,
                message: "Unsupported export file extension .\(outputURL.pathExtension)."
            )
        }

        let hasPresetID = options.presetID != nil
        let hasPresetName = options.presetName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard !(hasPresetID && hasPresetName) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Export preset must be selected by ID or name, not both."
            )
        }

        if let preset = try resolvedPreset(in: document.productMetadata, options: options) {
            guard preset.format == extensionFormat else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Export preset \(preset.name) writes \(preset.format.displayName), but output path selects \(extensionFormat.displayName)."
                )
            }
            let outputUnit = preset.outputUnit
            return ResolvedExportPlan(
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
        return ResolvedExportPlan(
            format: extensionFormat,
            outputUnit: outputUnit,
            unitSystem: document.cadDocument.units,
            destinationPolicy: options.destinationPolicy ?? .overwrite,
            presetName: nil
        )
    }

    private func resolvedPreset(
        in metadata: ProductMetadata,
        options: ExportOptions
    ) throws -> ExportPreset? {
        if let presetID = options.presetID {
            guard let preset = metadata.exportPresets[presetID] else {
                throw EditorError(
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
            throw EditorError(
                code: .commandInvalid,
                message: "Export preset \(name) was not found."
            )
        }
        return preset
    }

    private func resolvedDestinationURL(
        for outputURL: URL,
        policy: ExportPreset.DestinationPolicy
    ) throws -> URL {
        switch policy {
        case .prompt:
            guard !FileManager.default.fileExists(atPath: outputURL.path) else {
                throw EditorError(
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

        throw EditorError(
            code: .exportFailed,
            message: "Could not find an available versioned export path for \(outputURL.path)."
        )
    }

    private func exportedByteCount(at url: URL) throws -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber else {
                throw EditorError(
                    code: .exportFailed,
                    message: "Exported file size is unavailable."
                )
            }
            return size.uint64Value
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .exportFailed,
                message: "Exported file could not be inspected: \(error.localizedDescription)"
            )
        }
    }

    private func exportBinarySTLInMicrometers(
        _ evaluatedDocument: EvaluatedDocument,
        to destinationURL: URL
    ) throws {
        try evaluatedDocument.validate()
        guard !evaluatedDocument.meshes.isEmpty else {
            throw EditorError(
                code: .exportFailed,
                message: "Export failed: STL export requires at least one mesh."
            )
        }
        let triangleCount = try evaluatedDocument.meshes.values.reduce(0) { partial, mesh in
            try mesh.validate()
            return partial + mesh.indices.count / 3
        }
        guard UInt64(triangleCount) <= UInt64(UInt32.max) else {
            throw EditorError(
                code: .exportFailed,
                message: "Export failed: STL triangle count exceeds UInt32."
            )
        }

        var data = Data("Swift-CAD binary STL unit=micrometer".utf8.prefix(80))
        if data.count < 80 {
            data.append(Data(repeating: 0, count: 80 - data.count))
        }
        appendLittleEndian(UInt32(triangleCount), to: &data)

        for (_, mesh) in evaluatedDocument.meshes.sorted(by: { $0.key.description < $1.key.description }) {
            var index = 0
            while index < mesh.indices.count {
                let firstIndex = Int(mesh.indices[index])
                let secondIndex = Int(mesh.indices[index + 1])
                let thirdIndex = Int(mesh.indices[index + 2])
                let first = mesh.positions[firstIndex]
                let second = mesh.positions[secondIndex]
                let third = mesh.positions[thirdIndex]
                let normal = try stlNormal(
                    for: mesh,
                    firstIndex: firstIndex,
                    first: first,
                    second: second,
                    third: third
                )
                try appendSTLVector(normal, to: &data)
                try appendSTLPointInMicrometers(first, to: &data)
                try appendSTLPointInMicrometers(second, to: &data)
                try appendSTLPointInMicrometers(third, to: &data)
                appendLittleEndian(UInt16(0), to: &data)
                index += 3
            }
        }
        try data.write(to: destinationURL, options: .atomic)
    }

    private func stlNormal(
        for mesh: Mesh,
        firstIndex: Int,
        first: Point3D,
        second: Point3D,
        third: Point3D
    ) throws -> Vector3D {
        if !mesh.normals.isEmpty {
            return mesh.normals[firstIndex]
        }
        return try (second - first).cross(third - first).normalized(tolerance: ModelingTolerance.standard.distance)
    }

    private func appendSTLPointInMicrometers(
        _ point: Point3D,
        to data: inout Data
    ) throws {
        try appendFloat32(point.x * 1_000_000.0, label: "point.x", to: &data)
        try appendFloat32(point.y * 1_000_000.0, label: "point.y", to: &data)
        try appendFloat32(point.z * 1_000_000.0, label: "point.z", to: &data)
    }

    private func appendSTLVector(
        _ vector: Vector3D,
        to data: inout Data
    ) throws {
        try appendFloat32(vector.x, label: "normal.x", to: &data)
        try appendFloat32(vector.y, label: "normal.y", to: &data)
        try appendFloat32(vector.z, label: "normal.z", to: &data)
    }

    private func appendFloat32(
        _ value: Double,
        label: String,
        to data: inout Data
    ) throws {
        let value32 = Float32(value)
        guard value32.isFinite else {
            throw EditorError(
                code: .exportFailed,
                message: "Export failed: STL \(label) is outside Float32 range."
            )
        }
        appendLittleEndian(value32.bitPattern, to: &data)
    }

    private func appendLittleEndian<T: FixedWidthInteger>(
        _ value: T,
        to data: inout Data
    ) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

private struct ResolvedExportPlan: Sendable {
    var format: ExchangeFileFormat
    var outputUnit: LengthDisplayUnit
    var unitSystem: UnitSystem
    var destinationPolicy: ExportPreset.DestinationPolicy
    var presetName: String?
}
