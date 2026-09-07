import Foundation
import RupaCADIntegration
import RupaCore
import RupaCoreTypes
import RupaProject
import SwiftCAD

enum ProjectGeometryImport {
    static func transaction(
        from url: URL,
        format: ProjectGeometryFileFormat,
        unitForUnmarkedData: LengthDisplayUnit?,
        snapshot: ProjectViewSnapshot
    ) throws -> ProjectSourceTransaction {
        let imported = try CADGeometryExchange().import(
            from: url, format: format.nativeFormat,
            unitForUnmarkedData: unitForUnmarkedData?.swiftCADLengthUnit,
            tolerance: snapshot.document.document.modelingSettings.tolerance
        )
        try Task.checkCancellation()
        let name = url.deletingPathExtension().lastPathComponent
        let commands: [EditorCommand]
        let meshCommands: [GeometrySourceCommand]
        if let document = imported.cadDocument {
            let features = try document.designGraph.order.map { id in
                guard let feature = document.designGraph.nodes[id] else {
                    throw EditorError(code: .commandInvalid, message: "Imported CAD graph has a missing feature.")
                }
                return feature
            }
            let properties = ObjectPropertySet(values: [
                "rupa.import.format": .text(format.rawValue),
                "rupa.import.unit": .text(imported.units.length.rawValue),
                "rupa.import.fingerprint-algorithm": .text(imported.provenance.fingerprint.algorithm),
                "rupa.import.fingerprint": .text(imported.provenance.fingerprint.value),
            ])
            let presentations = features.enumerated().map { index, feature in
                FeaturePresentation(
                    featureID: feature.id, sceneNodeID: SceneNodeID(),
                    name: features.count == 1 ? name : "\(name) \(index + 1)",
                    kind: .body(sourceSection: nil, typeID: nil,
                                geometryRole: feature.outputs.contains(where: { $0.role == .sheet }) ? .surface : .solid,
                                properties: properties)
                )
            }
            commands = [.appendFeatureGraph(FeatureGraphTransaction(features: features, presentations: presentations))]
            meshCommands = []
        } else {
            commands = []
            meshCommands = imported.meshes.enumerated().map { index, source in
                .importAuthoredMesh(ImportAuthoredMeshCommand(
                    source: source, provenance: .imported(imported.provenance),
                    name: imported.meshes.count == 1 ? name : "\(name) \(index + 1)"
                ))
            }
        }
        return try ProjectSourceTransaction(
            name: "Import \(format.title)", commands: commands, geometrySourceCommands: meshCommands,
            expectedProjectID: snapshot.projectID,
            expectedTransactionRevision: snapshot.transactionRevision,
            expectedPublicationSequence: snapshot.publicationSequence
        )
    }
}
