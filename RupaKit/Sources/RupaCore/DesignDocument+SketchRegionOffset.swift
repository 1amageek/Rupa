import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func offsetRegions(
        targets: [SelectionTarget],
        distance: CADExpression,
        options: OffsetCurveOptions,
        combinesRegions: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        let distanceMeters = try resolvedLengthValue(distance, owner: "Offset Region distance")
        guard abs(distanceMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region distance must not be zero."
            )
        }
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region requires at least one selected region."
            )
        }

        let selections = try targets.map { target in
            try editableProfileRegion(
                for: target,
                operationName: "Offset Region",
                objectRegistry: objectRegistry
            )
        }

        if combinesRegions {
            guard selections.count >= 2 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Combined Offset Region requires multiple selected regions."
                )
            }
            return try appendCombinedOffsetRegions(
                selections: selections,
                distanceMeters: distanceMeters,
                options: options,
                objectRegistry: objectRegistry
            )
        }

        return try appendIndividualOffsetRegions(
            selections: selections,
            distanceMeters: distanceMeters,
            options: options,
            objectRegistry: objectRegistry
        )
    }

    mutating func offsetProfileRegion(
        target: SelectionTarget,
        distanceMeters: Double,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [FeatureID] {
        try validateOffsetRegionOptions(options, vertexHandle: vertexHandle)
        let selection = try editableProfileRegion(
            for: target,
            operationName: "Offset Region",
            objectRegistry: objectRegistry
        )
        return try appendIndividualOffsetRegions(
            selections: [selection],
            distanceMeters: distanceMeters,
            options: options,
            objectRegistry: objectRegistry
        )
    }

    private mutating func appendIndividualOffsetRegions(
        selections: [EditableProfileRegionSelection],
        distanceMeters: Double,
        options: OffsetCurveOptions,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [FeatureID] {
        let plannedResults = try selections.flatMap { selection in
            let name = selection.feature.name ?? "Region"
            if options.isSymmetric {
                return [
                    (
                        name: "\(name) Offset Positive",
                        result: try buildOffsetRegion(
                            profile: selection.profile,
                            distanceMeters: distanceMeters,
                            gapFill: options.gapFill
                        )
                    ),
                    (
                        name: "\(name) Offset Negative",
                        result: try buildOffsetRegion(
                            profile: selection.profile,
                            distanceMeters: -distanceMeters,
                            gapFill: options.gapFill
                        )
                    ),
                ]
            }
            return [
                (
                    name: "\(name) Offset",
                    result: try buildOffsetRegion(
                        profile: selection.profile,
                        distanceMeters: distanceMeters,
                        gapFill: options.gapFill
                    )
                ),
            ]
        }

        return try appendOffsetRegionFeatures(
            plannedResults,
            objectRegistry: objectRegistry
        )
    }

    private mutating func appendCombinedOffsetRegions(
        selections: [EditableProfileRegionSelection],
        distanceMeters: Double,
        options: OffsetCurveOptions,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [FeatureID] {
        let name = selections.first?.feature.name ?? "Regions"
        let profiles = selections.map(\.profile)
        if options.isSymmetric {
            let positiveResult = try buildCombinedOffsetRegion(
                profiles: profiles,
                distanceMeters: distanceMeters,
                gapFill: options.gapFill
            )
            let negativeResult = try buildCombinedOffsetRegion(
                profiles: profiles,
                distanceMeters: -distanceMeters,
                gapFill: options.gapFill
            )
            return try appendOffsetRegionFeatures(
                [
                    (
                        name: "\(name) Combined Offset Positive",
                        result: positiveResult
                    ),
                    (
                        name: "\(name) Combined Offset Negative",
                        result: negativeResult
                    ),
                ],
                objectRegistry: objectRegistry
            )
        }

        let result = try buildCombinedOffsetRegion(
            profiles: profiles,
            distanceMeters: distanceMeters,
            gapFill: options.gapFill
        )
        return try appendOffsetRegionFeatures(
            [
                (
                    name: "\(name) Combined Offset",
                    result: result
                ),
            ],
            objectRegistry: objectRegistry
        )
    }

    private func buildOffsetRegion(
        profile: Profile,
        distanceMeters: Double,
        gapFill: OffsetCurveGapFill
    ) throws -> OffsetRegionBuilder.Result {
        try OffsetRegionBuilder().buildOffset(
            profile: profile,
            gapFill: gapFill,
            distanceMeters: distanceMeters
        )
    }

    private func buildCombinedOffsetRegion(
        profiles: [Profile],
        distanceMeters: Double,
        gapFill: OffsetCurveGapFill
    ) throws -> OffsetRegionBuilder.Result {
        try OffsetRegionBuilder().buildCombinedOffset(
            profiles: profiles,
            gapFill: gapFill,
            distanceMeters: distanceMeters
        )
    }

    private mutating func appendOffsetRegionFeature(
        name: String,
        result: OffsetRegionBuilder.Result,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        return try appendSketchFeature(
            name: name,
            sketch: result.sketch,
            geometryRole: .sketchProfile,
            objectRegistry: objectRegistry
        )
    }

    private mutating func appendOffsetRegionFeatures(
        _ plannedResults: [PlannedOffsetRegionFeature],
        objectRegistry: ObjectTypeRegistry
    ) throws -> [FeatureID] {
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitAllFeatures = false
        defer {
            if didCommitAllFeatures == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        var featureIDs: [FeatureID] = []
        for plannedResult in plannedResults {
            let featureID = try appendOffsetRegionFeature(
                name: plannedResult.name,
                result: plannedResult.result,
                objectRegistry: objectRegistry
            )
            featureIDs.append(featureID)
        }
        didCommitAllFeatures = true
        return featureIDs
    }

    private func validateOffsetRegionOptions(
        _ options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?
    ) throws {
        guard vertexHandle == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region does not accept sketch vertex handles."
            )
        }
    }

    private func editableProfileRegion(
        for target: SelectionTarget,
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> EditableProfileRegionSelection {
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch scene node."
            )
        }
        guard case .region(let componentID) = target.component,
              let reference = componentID.profileRegionReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a source profile region selection target."
            )
        }
        guard reference.featureID == featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) selection target does not belong to the scene node sketch."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[featureID],
              feature.outputs.contains(where: { $0.role == .profile }),
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an editable sketch profile feature."
            )
        }
        guard sketch.entities.values.allSatisfy(Self.isLineSketchEntity) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports source regions made only from line sketch entities."
            )
        }

        let profiles: [Profile]
        do {
            let resolvedParameters = try ParameterResolver().resolve(cadDocument.parameters)
            profiles = try SketchProfileExtractor().extractProfiles(
                from: sketch,
                sourceFeatureID: featureID,
                parameters: resolvedParameters
            )
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a supported closed source region: \(String(describing: error))"
            )
        }
        guard profiles.indices.contains(reference.profileIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) references a missing source profile region."
            )
        }

        return (
            featureID: featureID,
            profileIndex: reference.profileIndex,
            feature: feature,
            sketch: sketch,
            profile: profiles[reference.profileIndex]
        )
    }

    private static func isLineSketchEntity(_ entity: SketchEntity) -> Bool {
        if case .line = entity {
            return true
        }
        return false
    }
}
