import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createBSplineSurface(
        name: String,
        surface: BSplineSurface3D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "B-spline surface")
        let surfaceFeature = BSplineSurfaceFeature(surface: surface)
        try surfaceFeature.validate()

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .bSplineSurface(surfaceFeature),
            outputs: [FeatureOutput(role: .sheet)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitSurface = false
        defer {
            if didCommitSurface == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: .bSplineSurface,
                geometryRole: .surface,
                properties: ObjectPropertySet(values: [
                    "surface.degree.u": .integer(surface.uDegree),
                    "surface.degree.v": .integer(surface.vDegree),
                    "control.point.u": .integer(surface.uControlPointCount),
                    "control.point.v": .integer(surface.vControlPointCount),
                    "surface.rational": .boolean(surface.isRational),
                ]),
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitSurface = true
        return featureID
    }

    @discardableResult
    public mutating func createPolySplineSurface(
        name: String,
        sourceMesh: Mesh,
        options: PolySplineOptions = PolySplineOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "PolySpline")
        let polySpline = PolySplineFeature(sourceMesh: sourceMesh, options: options)
        let analysis = PolySplineMeshAnalysisService().analyze(
            sourceMesh: sourceMesh,
            options: options
        )
        guard analysis.isSupported else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline requires a supported source mesh: \(analysis.failureMessage ?? "No supported patch candidate.")"
            )
        }

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .polySpline(polySpline),
            outputs: [FeatureOutput(role: .sheet)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitPolySpline = false
        defer {
            if didCommitPolySpline == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: .polySpline,
                geometryRole: .surface,
                properties: ObjectPropertySet(values: [
                    "patch.count": .integer(analysis.supportedPatchCount),
                    "control.point.u": .integer(4),
                    "control.point.v": .integer(4),
                    "merge.patches": .boolean(options.mergePatches),
                    "interpolate.boundary": .boolean(options.interpolateBoundaryExactly),
                ]),
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitPolySpline = true
        return featureID
    }

    public mutating func movePolySplineSurfaceVertex(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let surfaceVertexEditor = PolySplineSurfaceVertexEditingService()
        let resolvedTarget = try PolySplineSurfaceVertexTarget.resolve(target, in: self)
        let delta = Vector3D(
            x: try resolvedLengthValue(deltaX, owner: "PolySpline surface vertex delta x"),
            y: try resolvedLengthValue(deltaY, owner: "PolySpline surface vertex delta y"),
            z: try resolvedLengthValue(deltaZ, owner: "PolySpline surface vertex delta z")
        )
        guard delta.length > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex move requires a non-zero delta."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[resolvedTarget.featureID],
              case var .polySpline(polySpline) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "PolySpline surface vertex move requires an existing PolySpline source feature."
            )
        }

        let sourceVertexIndex = try surfaceVertexEditor.sourceVertexIndex(
            for: resolvedTarget,
            in: polySpline,
            owner: "PolySpline surface vertex move"
        )
        guard polySpline.sourceMesh.positions.indices.contains(sourceVertexIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "PolySpline surface vertex move references a missing source mesh vertex."
            )
        }

        polySpline.sourceMesh.positions[sourceVertexIndex] =
            polySpline.sourceMesh.positions[sourceVertexIndex] + delta
        try polySpline.validate()
        try surfaceVertexEditor.validateTargetStillStable(
            resolvedTarget,
            sourceVertexIndex: sourceVertexIndex,
            in: polySpline,
            owner: "PolySpline surface vertex move"
        )

        var updatedCADDocument = cadDocument
        feature.operation = .polySpline(polySpline)

        let previousCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
            cadDocument = updatedCADDocument
            try validate(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex move produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func moveSurfaceControlPoint(
        target: SelectionReference,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedTarget = try SurfaceControlPointSelectionTargetResolver().editTarget(
            for: target,
            in: self
        )
        switch resolvedTarget {
        case .boundaryVertex(let target):
            try movePolySplineSurfaceVertex(
                target: target,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaZ: deltaZ,
                objectRegistry: objectRegistry
            )
        case .interiorControlPoint(let target):
            try movePolySplineInteriorSurfaceControlPoint(
                target: target,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaZ: deltaZ,
                objectRegistry: objectRegistry
            )
        }
    }

    private mutating func movePolySplineInteriorSurfaceControlPoint(
        target: PolySplineSurfaceControlPointEditTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let delta = Vector3D(
            x: try resolvedLengthValue(deltaX, owner: "PolySpline surface control point delta x"),
            y: try resolvedLengthValue(deltaY, owner: "PolySpline surface control point delta y"),
            z: try resolvedLengthValue(deltaZ, owner: "PolySpline surface control point delta z")
        )
        guard delta.length > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface control point move requires a non-zero delta."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[target.featureID],
              case let .polySpline(polySpline) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "PolySpline surface control point move requires an existing PolySpline source feature."
            )
        }

        let controlPointEditor = PolySplineSurfaceControlPointEditingService()
        feature.operation = .polySpline(try controlPointEditor.updatedPolySpline(
            moving: target,
            by: delta,
            in: polySpline,
            owner: "PolySpline surface control point move"
        ))

        var updatedCADDocument = cadDocument
        let previousCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
            cadDocument = updatedCADDocument
            try validate(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface control point move produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func setSurfaceControlPointWeight(
        target: SelectionReference,
        weight: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedWeight = try resolvedPositiveScalarValue(
            weight,
            owner: "PolySpline surface control point weight"
        )
        let resolvedTarget = try SurfaceControlPointSelectionTargetResolver().editTarget(
            for: target,
            in: self
        )
        guard case .interiorControlPoint(let controlPointTarget) = resolvedTarget else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface control point weight currently requires a strict interior B-spline control point."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[controlPointTarget.featureID],
              case let .polySpline(polySpline) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "PolySpline surface control point weight requires an existing PolySpline source feature."
            )
        }

        let controlPointEditor = PolySplineSurfaceControlPointEditingService()
        feature.operation = .polySpline(try controlPointEditor.updatedPolySpline(
            settingWeight: resolvedWeight,
            for: controlPointTarget,
            in: polySpline,
            owner: "PolySpline surface control point weight"
        ))

        var updatedCADDocument = cadDocument
        let previousCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
            cadDocument = updatedCADDocument
            try validate(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface control point weight produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func slidePolySplineSurfaceVertices(
        targets: [SelectionTarget],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let surfaceVertexEditor = PolySplineSurfaceVertexEditingService()
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex slide requires at least one generated topology vertex selection."
            )
        }
        let resolvedDistance = try resolvedLengthValue(
            distance,
            owner: "PolySpline surface vertex slide distance"
        )
        guard abs(resolvedDistance) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex slide requires a non-zero distance."
            )
        }

        struct SlideUpdate {
            var featureID: FeatureID
            var target: PolySplineSurfaceVertexTarget
            var sourceVertexIndex: Int
            var delta: Vector3D
        }
        struct SourceVertexKey: Hashable {
            var featureID: FeatureID
            var sourceVertexIndex: Int
        }

        var featuresByID: [FeatureID: FeatureNode] = [:]
        var polySplinesByID: [FeatureID: PolySplineFeature] = [:]
        var seenSourceVertices: Set<SourceVertexKey> = []
        var updates: [SlideUpdate] = []
        updates.reserveCapacity(targets.count)

        for target in targets {
            let resolvedTarget = try PolySplineSurfaceVertexTarget.resolve(target, in: self)
            let polySpline: PolySplineFeature
            if let cachedPolySpline = polySplinesByID[resolvedTarget.featureID] {
                polySpline = cachedPolySpline
            } else {
                guard let sourceFeature = cadDocument.designGraph.nodes[resolvedTarget.featureID],
                      case let .polySpline(sourcePolySpline) = sourceFeature.operation else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "PolySpline surface vertex slide requires an existing PolySpline source feature."
                    )
                }
                polySpline = sourcePolySpline
                featuresByID[resolvedTarget.featureID] = sourceFeature
                polySplinesByID[resolvedTarget.featureID] = sourcePolySpline
            }

            let sourceVertexIndex = try surfaceVertexEditor.sourceVertexIndex(
                for: resolvedTarget,
                in: polySpline,
                owner: "PolySpline surface vertex slide"
            )
            guard polySpline.sourceMesh.positions.indices.contains(sourceVertexIndex) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "PolySpline surface vertex slide references a missing source mesh vertex."
                )
            }
            let duplicateKey = SourceVertexKey(
                featureID: resolvedTarget.featureID,
                sourceVertexIndex: sourceVertexIndex
            )
            guard seenSourceVertices.insert(duplicateKey).inserted else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "PolySpline surface vertex slide cannot receive duplicate targets for the same source mesh vertex."
                )
            }

            let unitDirection = try surfaceVertexEditor.slideUnitVector(
                for: resolvedTarget,
                in: polySpline,
                direction: direction
            )
            updates.append(
                SlideUpdate(
                    featureID: resolvedTarget.featureID,
                    target: resolvedTarget,
                    sourceVertexIndex: sourceVertexIndex,
                    delta: Vector3D(
                        x: unitDirection.x * resolvedDistance,
                        y: unitDirection.y * resolvedDistance,
                        z: unitDirection.z * resolvedDistance
                    )
                )
            )
        }

        for update in updates {
            guard var polySpline = polySplinesByID[update.featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "PolySpline surface vertex slide lost a resolved source feature."
                )
            }
            polySpline.sourceMesh.positions[update.sourceVertexIndex] =
                polySpline.sourceMesh.positions[update.sourceVertexIndex] + update.delta
            polySplinesByID[update.featureID] = polySpline
        }

        for (featureID, polySpline) in polySplinesByID {
            try polySpline.validate()
            for update in updates where update.featureID == featureID {
                try surfaceVertexEditor.validateTargetStillStable(
                    update.target,
                    sourceVertexIndex: update.sourceVertexIndex,
                    in: polySpline,
                    owner: "PolySpline surface vertex slide"
                )
            }
        }

        var updatedCADDocument = cadDocument
        var replacementFeatures: [FeatureNode] = []
        for (featureID, feature) in featuresByID {
            guard let polySpline = polySplinesByID[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "PolySpline surface vertex slide lost a resolved source mesh update."
                )
            }
            var updatedFeature = feature
            updatedFeature.operation = .polySpline(polySpline)
            replacementFeatures.append(updatedFeature)
        }

        let previousCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures(replacementFeatures)
            cadDocument = updatedCADDocument
            try validate(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex slide produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func slideSurfaceControlPoints(
        targets: [SelectionReference],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point slide requires at least one surface control point selection reference."
            )
        }
        let resolver = SurfaceControlPointSelectionTargetResolver()
        var boundaryTargets: [SelectionTarget] = []
        var interiorTargets: [PolySplineSurfaceControlPointEditTarget] = []
        boundaryTargets.reserveCapacity(targets.count)
        interiorTargets.reserveCapacity(targets.count)
        for target in targets {
            switch try resolver.editTarget(for: target, in: self) {
            case .boundaryVertex(let target):
                boundaryTargets.append(target)
            case .interiorControlPoint(let target):
                interiorTargets.append(target)
            }
        }
        let previousCADDocument = cadDocument
        do {
            if boundaryTargets.isEmpty == false {
                try slidePolySplineSurfaceVertices(
                    targets: boundaryTargets,
                    direction: direction,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
            }
            if interiorTargets.isEmpty == false {
                try slidePolySplineInteriorSurfaceControlPoints(
                    targets: interiorTargets,
                    direction: direction,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
            }
        } catch {
            cadDocument = previousCADDocument
            throw error
        }
    }

    private mutating func slidePolySplineInteriorSurfaceControlPoints(
        targets: [PolySplineSurfaceControlPointEditTarget],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface control point slide requires at least one interior control point target."
            )
        }
        let resolvedDistance = try resolvedLengthValue(
            distance,
            owner: "PolySpline surface control point slide distance"
        )
        guard abs(resolvedDistance) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface control point slide requires a non-zero distance."
            )
        }

        struct ControlPointKey: Hashable {
            var featureID: FeatureID
            var patchID: Int
            var uIndex: Int
            var vIndex: Int
        }

        var featuresByID: [FeatureID: FeatureNode] = [:]
        var polySplinesByID: [FeatureID: PolySplineFeature] = [:]
        var seenTargets: Set<ControlPointKey> = []
        let controlPointEditor = PolySplineSurfaceControlPointEditingService()

        for target in targets {
            let duplicateKey = ControlPointKey(
                featureID: target.featureID,
                patchID: target.patchID,
                uIndex: target.uIndex,
                vIndex: target.vIndex
            )
            guard seenTargets.insert(duplicateKey).inserted else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "PolySpline surface control point slide cannot receive duplicate targets."
                )
            }
            let polySpline: PolySplineFeature
            if let cachedPolySpline = polySplinesByID[target.featureID] {
                polySpline = cachedPolySpline
            } else {
                guard let sourceFeature = cadDocument.designGraph.nodes[target.featureID],
                      case let .polySpline(sourcePolySpline) = sourceFeature.operation else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "PolySpline surface control point slide requires an existing PolySpline source feature."
                    )
                }
                featuresByID[target.featureID] = sourceFeature
                polySpline = sourcePolySpline
            }

            let unitDirection = try controlPointEditor.slideUnitVector(
                for: target,
                in: polySpline,
                direction: direction
            )
            let delta = Vector3D(
                x: unitDirection.x * resolvedDistance,
                y: unitDirection.y * resolvedDistance,
                z: unitDirection.z * resolvedDistance
            )
            polySplinesByID[target.featureID] = try controlPointEditor.updatedPolySpline(
                moving: target,
                by: delta,
                in: polySpline,
                owner: "PolySpline surface control point slide"
            )
        }

        var replacementFeatures: [FeatureNode] = []
        for (featureID, feature) in featuresByID {
            guard let polySpline = polySplinesByID[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "PolySpline surface control point slide lost a resolved source update."
                )
            }
            var updatedFeature = feature
            updatedFeature.operation = .polySpline(polySpline)
            replacementFeatures.append(updatedFeature)
        }

        var updatedCADDocument = cadDocument
        let previousCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures(replacementFeatures)
            cadDocument = updatedCADDocument
            try validate(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface control point slide produced invalid source geometry: \(error)."
            )
        }
    }
}
