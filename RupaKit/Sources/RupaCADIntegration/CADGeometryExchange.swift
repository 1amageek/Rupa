import Foundation
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import SwiftCAD

/// The immutable result of one bounded CAD exchange import.
public struct CADGeometryImport: Sendable {
    public let cadDocument: CADDocument?
    public let meshes: [MeshSource]
    public let provenance: ContentIdentity
    public let units: UnitSystem

    init(
        cadDocument: CADDocument?,
        meshes: [MeshSource],
        provenance: ContentIdentity,
        units: UnitSystem
    ) {
        self.cadDocument = cadDocument
        self.meshes = meshes
        self.provenance = provenance
        self.units = units
    }
}

public enum CADGeometryExchangeError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedFormat(ExchangeFileFormat)
    case fileReadFailure(String)
    case fileTooLarge(actual: Int, maximum: Int)
    case invalidResult(ExchangeFileFormat, String)
    case unsupportedMaterial
    case resourceExhausted(String)
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "Rupa exchange does not support \(format.rawValue) imports."
        case .fileReadFailure(let message):
            "The exchange input could not be read: \(message)"
        case .fileTooLarge(let actual, let maximum):
            "The exchange input is \(actual) bytes, above the \(maximum)-byte limit."
        case .invalidResult(let format, let message):
            "The \(format.rawValue) exchange result is invalid: \(message)"
        case .unsupportedMaterial:
            "Exchange materials cannot be represented by the universal geometry contract."
        case .resourceExhausted(let message):
            "The exchange result exceeds the admitted geometry resources: \(message)"
        case .invalidConfiguration(let message):
            "The exchange import configuration is invalid: \(message)"
        }
    }
}

/// Bounded import of the exact STEP and mesh STL/OBJ formats understood by
/// Rupa's staging boundary. The URL is only an input capability; it is never
/// retained in the returned provenance or geometry values.
public struct CADGeometryExchange: Sendable {
    private let resourceLimits: ExchangeResourceLimits

    public init() {
        resourceLimits = .standard
    }

    /// Internal test construction keeps the production API on the standard
    /// exchange ceiling while allowing deterministic small-limit tests.
    init(resourceLimits: ExchangeResourceLimits) {
        self.resourceLimits = resourceLimits
    }

    public func `import`(
        from url: URL,
        format: ExchangeFileFormat,
        unitForUnmarkedData: LengthUnit? = nil,
        tolerance: ModelingTolerance,
        allowance: EvaluationAllowance = EvaluationAllowance(.standard)
    ) throws -> CADGeometryImport {
        try Task.checkCancellation()
        guard format == .step || format == .stl || format == .obj else {
            throw CADGeometryExchangeError.unsupportedFormat(format)
        }
        do {
            try resourceLimits.validate()
            try tolerance.validate()
            try allowance.validate()
        } catch {
            throw CADGeometryExchangeError.invalidConfiguration(String(describing: error))
        }

        let source: MappedFileByteSource
        do {
            source = try MappedFileByteSource(url: url)
        } catch {
            throw CADGeometryExchangeError.fileReadFailure(String(describing: error))
        }
        guard source.count <= resourceLimits.maximumBytes else {
            throw CADGeometryExchangeError.fileTooLarge(
                actual: source.count,
                maximum: resourceLimits.maximumBytes
            )
        }

        let digest: String
        do {
            digest = try source.withNoCopyData { data in
                try Task.checkCancellation()
                let value = StableDigest.sha256Hex(for: data)
                try Task.checkCancellation()
                return value
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw CADGeometryExchangeError.fileReadFailure(String(describing: error))
        }

        let imported: ImportedExchangeModel
        do {
            switch format {
            case .step:
                imported = try STEPExchange(
                    tolerance: tolerance,
                    resourceLimits: resourceLimits
                ).import(source)
            case .stl:
                imported = try STLExporter(tolerance: tolerance, resourceLimits: resourceLimits).importBinary(
                    source,
                    explicitUnit: unitForUnmarkedData
                )
            case .obj:
                imported = try OBJExchange(
                    tolerance: tolerance,
                    resourceLimits: resourceLimits
                ).import(
                    source,
                    explicitUnit: unitForUnmarkedData
                )
            default:
                throw CADGeometryExchangeError.unsupportedFormat(format)
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as ImportError {
            throw error
        } catch let error as ByteSourceError {
            throw CADGeometryExchangeError.fileReadFailure(String(describing: error))
        } catch let error as KernelError where error.code == .resourceLimitExceeded {
            throw CADGeometryExchangeError.resourceExhausted(error.message)
        } catch {
            throw error
        }
        try Task.checkCancellation()

        try validate(imported, for: format)
        let meshes = try materializeMeshes(
            imported.meshes,
            format: format,
            digest: digest,
            unit: imported.units.length,
            allowance: allowance
        )
        try Task.checkCancellation()

        do {
            let fingerprint = try ContentFingerprint(
                algorithm: "sha256-rupa-exchange-\(format.rawValue)-v1",
                value: digest
            )
            let provenance = try ContentIdentity(
                domain: "rupa.exchange.\(format.rawValue).\(imported.units.length.rawValue)",
                fingerprint: fingerprint
            )
            try imported.units.validate()
            try Task.checkCancellation()
            return CADGeometryImport(
                cadDocument: imported.document,
                meshes: meshes,
                provenance: provenance,
                units: imported.units
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw CADGeometryExchangeError.invalidResult(
                format,
                "The imported units or content identity could not be represented: \(error)"
            )
        }
    }

    /// Resolves an output coordinate using the same direct-body or unique
    /// feature-body semantics as the CAD source provider.
    package static func resolvedBodyID(
        outputID: String,
        in evaluatedDocument: EvaluatedDocument
    ) -> BodyID? {
        guard let uuid = UUID(uuidString: outputID) else {
            return nil
        }
        let directBodyID = BodyID(uuid)
        if evaluatedDocument.brep.bodies[directBodyID] != nil || evaluatedDocument.meshes[directBodyID] != nil {
            return directBodyID
        }

        let featureID = FeatureID(uuid)
        let bodyIDs = evaluatedDocument.subshapes.entries.compactMap {
            entry -> BodyID? in
            let (subshapeID, reference) = entry
            guard subshapeID.featureID == featureID,
                  case .body(let bodyID) = reference else {
                return nil
            }
            return bodyID
        }
        let uniqueBodyIDs = Set(bodyIDs)
        guard uniqueBodyIDs.count == 1 else {
            return nil
        }
        return uniqueBodyIDs.first
    }

    private func validate(
        _ imported: ImportedExchangeModel,
        for format: ExchangeFileFormat
    ) throws {
        guard imported.format == format else {
            throw CADGeometryExchangeError.invalidResult(
                format,
                "The parser returned \(imported.format.rawValue) for a \(format.rawValue) request."
            )
        }
        switch format {
        case .step:
            guard imported.document != nil,
                  imported.brep != nil,
                  imported.meshes.isEmpty else {
                throw CADGeometryExchangeError.invalidResult(
                    format,
                    "STEP must return one exact document and no mesh bodies."
                )
            }
        case .stl, .obj:
            guard imported.document == nil,
                  imported.brep == nil,
                  !imported.meshes.isEmpty else {
                throw CADGeometryExchangeError.invalidResult(
                    format,
                    "Mesh exchange must return mesh bodies without an exact document."
                )
            }
        default:
            throw CADGeometryExchangeError.unsupportedFormat(format)
        }
    }

    private func materializeMeshes(
        _ importedMeshes: [BodyID: Mesh],
        format: ExchangeFileFormat,
        digest: String,
        unit: LengthUnit,
        allowance: EvaluationAllowance
    ) throws -> [MeshSource] {
        guard importedMeshes.count <= allowance.sourceCount else {
            throw CADGeometryExchangeError.resourceExhausted(
                "\(importedMeshes.count) mesh sources exceed the \(allowance.sourceCount)-source allowance."
            )
        }
        guard !importedMeshes.isEmpty else {
            return []
        }

        var admission: CADTessellationAdmission
        do {
            admission = try CADTessellationAdmission(allowance: allowance)
        } catch let error as CADIntegrationError {
            throw CADGeometryExchangeError.resourceExhausted(error.message)
        }

        let orderedMeshes = importedMeshes.sorted {
            $0.key.description < $1.key.description
        }
        var results: [MeshSource] = []
        results.reserveCapacity(orderedMeshes.count)
        for (ordinal, (_, mesh)) in orderedMeshes.enumerated() {
            try Task.checkCancellation()
            guard mesh.material == nil else {
                throw CADGeometryExchangeError.unsupportedMaterial
            }
            let predicted: MeshResourceUsage
            do {
                predicted = try admission.admit(mesh)
            } catch let error as CADIntegrationError {
                if error.code == .resourceExhausted {
                    throw CADGeometryExchangeError.resourceExhausted(error.message)
                }
                throw CADGeometryExchangeError.invalidResult(format, error.message)
            }

            let identity = GeometrySourceID(
                rawValue: "exchange.\(format.rawValue).\(unit.rawValue).\(digest).\(ordinal)"
            )
            let materialized: CADMeshSourceMaterialization
            do {
                materialized = try CADMeshSourceConverter.makeMeshSource(
                    identity: identity,
                    mesh: mesh
                )
            } catch let error as CancellationError {
                throw error
            } catch CADMeshSourceConversionError.unsupportedMaterial {
                throw CADGeometryExchangeError.unsupportedMaterial
            } catch let error as CADMeshSourceConversionError {
                throw CADGeometryExchangeError.invalidResult(
                    format,
                    "Mesh conversion failed: \(error)"
                )
            }

            do {
                try admission.verify(
                    actual: materialized.source.resourceUsage(),
                    predicted: predicted
                )
            } catch let error as CADIntegrationError {
                throw CADGeometryExchangeError.invalidResult(format, error.message)
            } catch {
                throw CADGeometryExchangeError.invalidResult(
                    format,
                    "Mesh resource usage could not be verified: \(error)"
                )
            }
            results.append(materialized.source)
        }
        return results
    }
}
