import SwiftCAD
import RupaCoreTypes

public struct OriginalMassPropertyService: Sendable {
    private let measurerOverride: (any DocumentMassPropertyMeasuring)?
    public init(measurer: (any DocumentMassPropertyMeasuring)? = nil) { measurerOverride = measurer }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Original affine occurrence composition reaches the
    // public original-mass query. Required general curved-solid moment convergence and
    // public success/failure validation must close before full-domain completion.
    public func measure(document: DesignDocument, selection: SelectionModel? = nil,
                        options: BRepVolumeMomentOptions, maximumComponents: Int,
                        densityOverrides: [BodyID: Double] = [:], reference: Point3D = .origin,
                        objectRegistry: ObjectTypeRegistry = .builtIn,
                        currentEvaluation: DocumentEvaluationContext? = nil,
                        currentGeneration: DocumentGeneration? = nil) throws -> PlacedMassPropertyMeasurement {
        try Task.checkCancellation()
        guard maximumComponents > 0 else {
            throw EditorError(code: .commandInvalid, message: "Original mass component capacity must be positive.")
        }
        if let selection, !selection.selectedTargets.allSatisfy({ $0.component.isWholeSceneNode }) {
            throw EditorError(code: .commandInvalid, message: "Original solid mass requires whole scene objects.")
        }
        try document.validate(objectRegistry: objectRegistry, unlessEvaluatedBy: currentEvaluation, generation: currentGeneration)
        let evaluated = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
            document: document, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration, failurePrefix: "Original mass requires current exact CAD geometry")
        guard Set(densityOverrides.keys).isSubset(of: Set(evaluated.brep.bodies.keys)) else {
            throw EditorError(code: .referenceUnresolved, message: "A physical density override names a missing original body.")
        }
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        var selectedOwners: Set<SceneNodeID>?
        var selectedOccurrences: Set<SceneOccurrenceID> = []
        if let selection, !selection.selectedSceneNodeIDs.isEmpty {
            var closure: Set<SceneNodeID> = []
            let occurrenceResolver = try OriginalOccurrenceSelectionResolver(document: document)
            for target in selection.selectedTargets where target.occurrenceID != nil {
                if let occurrence = try occurrenceResolver.resolve(target) { selectedOccurrences.insert(occurrence.id) }
            }
            for owner in Set(selection.selectedTargets.filter { $0.occurrenceID == nil }.map(\.sceneNodeID)) {
                guard hierarchy.node(owner) != nil else {
                    throw EditorError(code: .referenceUnresolved, message: "Original mass selection names a missing scene owner.")
                }
                closure.formUnion(hierarchy.subtreeIDs(of: owner))
            }
            selectedOwners = closure
        }
        var bodiesByFeature: [FeatureID: Set<BodyID>] = [:]
        for (identity, topology) in evaluated.subshapes.entries {
            if case .body(let bodyID) = topology { bodiesByFeature[identity.featureID, default: []].insert(bodyID) }
        }
        var components: [MassPropertyComponent] = []
        var occurrenceIDs: [SceneOccurrenceID] = []
        for occurrence in try hierarchy.resolvedOccurrences() {
            try Task.checkCancellation()
            if let selectedOwners, !selectedOwners.contains(occurrence.sceneNodeID), !selectedOccurrences.contains(occurrence.id) { continue }
            guard occurrence.isVisible else { continue }
            guard let source = document.productMetadata.sceneNodes[occurrence.sourceSceneNodeID],
                  let feature = source.reference?.featureID,
                  let bodyIDs = bodiesByFeature[feature] else { continue }
            let transform = occurrence.worldTransform
            let placement = try AffineTransform3D(
                basisX: transform.applyingLinearPart(to: .unitX),
                basisY: transform.applyingLinearPart(to: .unitY),
                basisZ: transform.applyingLinearPart(to: .unitZ),
                translation: transform.applied(to: .origin) - Point3D.origin)
            for bodyID in bodyIDs.sorted(by: { $0.description < $1.description }) {
                guard evaluated.brep.bodies[bodyID]?.kind == .solid else {
                    throw EditorError(code: .commandInvalid, message: "Original volume mass requires solid CAD outputs.")
                }
                guard components.count < maximumComponents else {
                    throw EditorError(code: .commandFailed, message: "Original mass component capacity exhausted.")
                }
                components.append(MassPropertyComponent(bodyID: bodyID,
                    densityKilogramsPerCubicMeter: densityOverrides[bodyID], affinePlacement: placement))
                occurrenceIDs.append(occurrence.id)
            }
        }
        guard !components.isEmpty else {
            throw EditorError(code: .referenceUnresolved, message: "The requested scene has no original solid mass components.")
        }
        let measurer = measurerOverride ?? NativeDocumentMassPropertyMeasurer(tolerance: document.modelingSettings.tolerance)
        let values = try measurer.measure(components, in: evaluated, options: options, reference: reference)
        try Task.checkCancellation()
        return PlacedMassPropertyMeasurement(occurrenceIDs: occurrenceIDs, values: values)
    }
}
