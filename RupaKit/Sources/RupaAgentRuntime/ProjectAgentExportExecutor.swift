import Foundation
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaKit
import RupaProjectModel

/// Exports only projects whose complete geometry authority is representable by CAD export.
public struct ProjectAgentExportExecutor: Sendable {
    private let exportService: DocumentExportService

    public init(exportService: DocumentExportService = DocumentExportService()) {
        self.exportService = exportService
    }

    public func execute(
        outputPath: String,
        expectedGeneration: DocumentGeneration?,
        options: ExportOptions,
        dryRun: Bool,
        snapshot: ProjectViewSnapshot
    ) throws -> ExportResult {
        let prepared = try prepare(
            outputPath: outputPath,
            expectedGeneration: expectedGeneration,
            options: options,
            dryRun: dryRun,
            snapshot: snapshot
        )
        do {
            return try prepared.publish()
        } catch {
            do {
                try prepared.discard()
            } catch let cleanupError {
                throw EditorError(
                    code: .exportFailed,
                    message: "\(error.localizedDescription) Export staging cleanup also failed: \(cleanupError.localizedDescription)"
                )
            }
            throw error
        }
    }

    public func prepare(
        outputPath: String,
        expectedGeneration: DocumentGeneration?,
        options: ExportOptions,
        dryRun: Bool,
        snapshot: ProjectViewSnapshot
    ) throws -> PreparedDocumentExport {
        if let expectedGeneration,
           expectedGeneration != snapshot.documentGeneration {
            throw EditorError(
                code: .documentGenerationMismatch,
                message: "Export expected generation \(expectedGeneration.value), but the project is at generation \(snapshot.documentGeneration.value)."
            )
        }
        let document = snapshot.document.document
        let containsNonCADRepresentation = document.productMetadata.sceneNodes.values
            .compactMap(\.object)
            .contains { object in
                object.geometryRepresentations.representations.values.contains { representation in
                    switch representation.source {
                    case .cad:
                        false
                    case .authoredMesh, .external:
                        true
                    }
                }
        }
        guard document.hasAuthoritativeCADSource,
              document.authoredMeshAssets.isEmpty,
              !containsNonCADRepresentation else {
            throw EditorError(
                code: .commandUnsupported,
                message: "Agent export currently supports CAD-only project authority; Mesh-only, mixed CAD/Mesh, and external geometry require a representation-aware export route."
            )
        }
        return try exportService.prepareExport(
            document: document,
            generation: snapshot.documentGeneration,
            to: URL(fileURLWithPath: outputPath),
            options: options,
            dryRun: dryRun,
            objectRegistry: snapshot.objectRegistry
        )
    }
}
