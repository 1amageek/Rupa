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
        case .bSplineSurfaceControlPoint(let target):
            try moveBSplineSurfaceControlPoint(
                target: target,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaZ: deltaZ,
                objectRegistry: objectRegistry
            )
        }
    }

    public mutating func moveSurfaceControlPointsInFrame(
        targets: [SelectionReference],
        frame: SurfaceFrameQuery,
        uDistance: CADExpression,
        vDistance: CADExpression,
        normalDistance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point frame move requires at least one surface control point selection reference."
            )
        }
        var seenTargets: Set<SelectionReference> = []
        for target in targets {
            guard seenTargets.insert(target).inserted else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Surface control point frame move cannot receive duplicate targets."
                )
            }
        }

        let resolvedFrame = try resolvedSurfaceFrame(
            frame,
            objectRegistry: objectRegistry,
            owner: "Surface control point frame move"
        )
        let delta = try surfaceFrameDelta(
            resolvedFrame,
            uDistance: uDistance,
            vDistance: vDistance,
            normalDistance: normalDistance
        )
        guard delta.length > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point frame move requires a non-zero UVN offset."
            )
        }

        let previousCADDocument = cadDocument
        do {
            for target in targets {
                try moveSurfaceControlPoint(target: target, delta: delta, objectRegistry: objectRegistry)
            }
        } catch {
            cadDocument = previousCADDocument
            throw error
        }
    }

    private mutating func moveSurfaceControlPoint(
        target: SelectionReference,
        delta: Vector3D,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        try moveSurfaceControlPoint(
            target: target,
            deltaX: .length(delta.x, .meter),
            deltaY: .length(delta.y, .meter),
            deltaZ: .length(delta.z, .meter),
            objectRegistry: objectRegistry
        )
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

    private mutating func moveBSplineSurfaceControlPoint(
        target: BSplineSurfaceControlPointEditTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let delta = Vector3D(
            x: try resolvedLengthValue(deltaX, owner: "B-spline surface control point delta x"),
            y: try resolvedLengthValue(deltaY, owner: "B-spline surface control point delta y"),
            z: try resolvedLengthValue(deltaZ, owner: "B-spline surface control point delta z")
        )
        guard delta.length > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface control point move requires a non-zero delta."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[target.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface control point move requires an existing direct B-spline surface source feature."
            )
        }

        let controlPointEditor = BSplineSurfaceControlPointEditingService()
        feature.operation = .bSplineSurface(try controlPointEditor.updatedFeature(
            moving: target,
            by: delta,
            in: surfaceFeature,
            owner: "B-spline surface control point move"
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
                message: "B-spline surface control point move produced invalid source geometry: \(error)."
            )
        }
    }

    private func resolvedSurfaceFrame(
        _ query: SurfaceFrameQuery,
        objectRegistry: ObjectTypeRegistry,
        owner: String
    ) throws -> SurfaceFrameResult.Frame {
        let result = try SurfaceFrameService().resolve(
            document: self,
            queries: [query],
            objectRegistry: objectRegistry
        )
        guard let frame = result.frames.first else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a resolvable surface frame."
            )
        }
        return frame
    }

    private func surfaceFrameDelta(
        _ frame: SurfaceFrameResult.Frame,
        uDistance: CADExpression,
        vDistance: CADExpression,
        normalDistance: CADExpression
    ) throws -> Vector3D {
        let resolvedU = try resolvedLengthValue(
            uDistance,
            owner: "Surface control point frame move U distance"
        )
        let resolvedV = try resolvedLengthValue(
            vDistance,
            owner: "Surface control point frame move V distance"
        )
        let resolvedNormal = try resolvedLengthValue(
            normalDistance,
            owner: "Surface control point frame move normal distance"
        )
        let uAxis = try vector(frame.uAxis, owner: "Surface control point frame move U axis")
        let vAxis = try vector(frame.vAxis, owner: "Surface control point frame move V axis")
        let normal = try vector(frame.normal, owner: "Surface control point frame move normal axis")
        return uAxis * resolvedU + vAxis * resolvedV + normal * resolvedNormal
    }

    private func vector(
        _ vector: SurfaceAnalysisResult.Vector,
        owner: String
    ) throws -> Vector3D {
        let result = Vector3D(
            x: vector.x,
            y: vector.y,
            z: vector.z
        )
        do {
            try result.validateUnitLength()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be a finite unit vector."
            )
        }
        return result
    }

    public mutating func setSurfaceControlPointWeight(
        target: SelectionReference,
        weight: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedWeight = try resolvedPositiveScalarValue(
            weight,
            owner: "Surface control point weight"
        )
        let resolvedTarget = try SurfaceControlPointSelectionTargetResolver().editTarget(
            for: target,
            in: self
        )
        switch resolvedTarget {
        case .interiorControlPoint(let controlPointTarget):
            try setPolySplineInteriorSurfaceControlPointWeight(
                target: controlPointTarget,
                weight: resolvedWeight,
                objectRegistry: objectRegistry
            )
        case .bSplineSurfaceControlPoint(let controlPointTarget):
            try setBSplineSurfaceControlPointWeight(
                target: controlPointTarget,
                weight: resolvedWeight,
                objectRegistry: objectRegistry
            )
        case .boundaryVertex:
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point weight requires a direct B-spline control point or a strict interior PolySpline B-spline control point."
            )
        }
    }

    private mutating func setPolySplineInteriorSurfaceControlPointWeight(
        target controlPointTarget: PolySplineSurfaceControlPointEditTarget,
        weight resolvedWeight: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
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

    private mutating func setBSplineSurfaceControlPointWeight(
        target controlPointTarget: BSplineSurfaceControlPointEditTarget,
        weight resolvedWeight: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard var feature = cadDocument.designGraph.nodes[controlPointTarget.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface control point weight requires an existing direct B-spline surface source feature."
            )
        }

        let controlPointEditor = BSplineSurfaceControlPointEditingService()
        feature.operation = .bSplineSurface(try controlPointEditor.updatedFeature(
            settingWeight: resolvedWeight,
            for: controlPointTarget,
            in: surfaceFeature,
            owner: "B-spline surface control point weight"
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
                message: "B-spline surface control point weight produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func setSurfaceKnotValue(
        target: SelectionReference,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedValue = try resolvedScalarValue(
            value,
            owner: "B-spline surface knot value"
        )
        let knotReference = try resolvedBSplineSurfaceKnotReference(
            target,
            owner: "B-spline surface knot value"
        )
        guard var feature = cadDocument.designGraph.nodes[knotReference.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface knot value requires an existing direct B-spline surface source feature."
            )
        }

        let knotEditor = BSplineSurfaceKnotEditingService()
        feature.operation = .bSplineSurface(try knotEditor.updatedFeature(
            settingValue: resolvedValue,
            for: knotReference.reference,
            in: surfaceFeature,
            owner: "B-spline surface knot value"
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
                message: "B-spline surface knot value produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func insertSurfaceKnot(
        target: SelectionReference,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedValue = try resolvedScalarValue(
            value,
            owner: "B-spline surface knot insertion"
        )
        let insertionResolution = try resolvedBSplineSurfaceKnotInsertionTarget(
            target,
            owner: "B-spline surface knot insertion"
        )
        guard var feature = cadDocument.designGraph.nodes[insertionResolution.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface knot insertion requires an existing direct B-spline surface source feature."
            )
        }
        let insertionValue = try resolvedBSplineSurfaceKnotInsertionValue(
            resolvedValue,
            target: insertionResolution,
            surface: surfaceFeature.surface,
            owner: "B-spline surface knot insertion"
        )

        let knotEditor = BSplineSurfaceKnotEditingService()
        feature.operation = .bSplineSurface(try knotEditor.updatedFeature(
            insertingKnot: insertionResolution.direction,
            value: insertionValue,
            in: surfaceFeature,
            owner: "B-spline surface knot insertion"
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
                message: "B-spline surface knot insertion produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func splitSurfaceSpan(
        target: SelectionReference,
        fraction: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedFraction = try resolvedScalarValue(
            fraction,
            owner: "B-spline surface span split"
        )
        guard resolvedFraction > 0.0, resolvedFraction < 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface span split fraction must be strictly between 0 and 1."
            )
        }
        let spanResolution = try resolvedBSplineSurfaceSpanReference(
            target,
            owner: "B-spline surface span split"
        )
        guard var feature = cadDocument.designGraph.nodes[spanResolution.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface span split requires an existing direct B-spline surface source feature."
            )
        }
        let spanBounds = try bSplineSurfaceSpanBounds(
            for: spanResolution.reference,
            in: surfaceFeature.surface,
            owner: "B-spline surface span split"
        )
        let insertionValue = spanBounds.lower
            + (spanBounds.upper - spanBounds.lower) * resolvedFraction

        let knotEditor = BSplineSurfaceKnotEditingService()
        feature.operation = .bSplineSurface(try knotEditor.updatedFeature(
            insertingKnot: spanResolution.reference.direction,
            value: insertionValue,
            in: surfaceFeature,
            owner: "B-spline surface span split"
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
                message: "B-spline surface span split produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func setSurfaceKnotMultiplicity(
        target: SelectionReference,
        multiplicity: Int,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let knotReference = try resolvedBSplineSurfaceKnotReference(
            target,
            owner: "B-spline surface knot multiplicity"
        )
        guard var feature = cadDocument.designGraph.nodes[knotReference.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface knot multiplicity requires an existing direct B-spline surface source feature."
            )
        }

        let knotEditor = BSplineSurfaceKnotEditingService()
        feature.operation = .bSplineSurface(try knotEditor.updatedFeature(
            settingMultiplicity: multiplicity,
            for: knotReference.reference,
            in: surfaceFeature,
            owner: "B-spline surface knot multiplicity"
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
                message: "B-spline surface knot multiplicity produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func setSurfaceTrimDomain(
        target: SelectionReference,
        uLowerBound: CADExpression,
        uUpperBound: CADExpression,
        vLowerBound: CADExpression,
        vUpperBound: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedULowerBound = try resolvedScalarValue(
            uLowerBound,
            owner: "B-spline surface trim domain U lower bound"
        )
        let resolvedUUpperBound = try resolvedScalarValue(
            uUpperBound,
            owner: "B-spline surface trim domain U upper bound"
        )
        let resolvedVLowerBound = try resolvedScalarValue(
            vLowerBound,
            owner: "B-spline surface trim domain V lower bound"
        )
        let resolvedVUpperBound = try resolvedScalarValue(
            vUpperBound,
            owner: "B-spline surface trim domain V upper bound"
        )
        let surfaceResolution = try resolvedBSplineSurfaceSourceReference(
            target,
            owner: "B-spline surface trim domain"
        )
        guard var feature = cadDocument.designGraph.nodes[surfaceResolution.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface trim domain requires an existing direct B-spline surface source feature."
            )
        }

        let trimDomain = BSplineSurfaceTrimDomain(
            uLowerBound: resolvedULowerBound,
            uUpperBound: resolvedUUpperBound,
            vLowerBound: resolvedVLowerBound,
            vUpperBound: resolvedVUpperBound
        )
        do {
            try trimDomain.validate(containedIn: surfaceFeature.surface)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim domain is outside the source surface domain or degenerate: \(error)."
            )
        }

        var updatedSurfaceFeature = surfaceFeature
        let storesFullSurfaceDomain = try trimDomain.isFullSurfaceDomain(of: surfaceFeature.surface)
        updatedSurfaceFeature.outerTrimDomain = storesFullSurfaceDomain ? nil : trimDomain
        updatedSurfaceFeature.trimLoops = []
        feature.operation = .bSplineSurface(updatedSurfaceFeature)

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
                message: "B-spline surface trim domain produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func setSurfaceTrimLoops(
        target: SelectionReference,
        trimLoops: [BSplineSurfaceTrimLoop],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let surfaceResolution = try resolvedBSplineSurfaceSourceReference(
            target,
            owner: "B-spline surface trim loops"
        )
        guard var feature = cadDocument.designGraph.nodes[surfaceResolution.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface trim loops require an existing direct B-spline surface source feature."
            )
        }

        do {
            for trimLoop in trimLoops {
                try trimLoop.validate(on: surfaceFeature.surface)
            }
            if trimLoops.isEmpty == false,
               trimLoops.filter({ $0.role == .outer }).count != 1 {
                throw EditorError(
                    code: .commandInvalid,
                    message: "B-spline surface trim loops require exactly one outer loop."
                )
            }
        } catch let editorError as EditorError {
            throw editorError
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim loops are invalid for the source surface: \(error)."
            )
        }

        var updatedSurfaceFeature = surfaceFeature
        updatedSurfaceFeature.outerTrimDomain = nil
        updatedSurfaceFeature.trimLoops = trimLoops
        feature.operation = .bSplineSurface(updatedSurfaceFeature)

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
                message: "B-spline surface trim loops produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func moveSurfaceTrimEndpoint(
        target: SelectionReference,
        endpoint: SurfaceTrimEndpoint,
        u: CADExpression,
        v: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedU = try resolvedScalarValue(
            u,
            owner: "B-spline surface trim endpoint U parameter"
        )
        let resolvedV = try resolvedScalarValue(
            v,
            owner: "B-spline surface trim endpoint V parameter"
        )
        let trimResolution = try resolvedBSplineSurfaceTrimReference(
            target,
            owner: "B-spline surface trim endpoint move"
        )
        guard var feature = cadDocument.designGraph.nodes[trimResolution.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface trim endpoint move requires an existing direct B-spline surface source feature."
            )
        }
        guard surfaceFeature.trimLoops.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim endpoint move requires authored UV trim loops; rectangular trim domains must be edited with setSurfaceTrimDomain."
            )
        }
        guard surfaceFeature.trimLoops.indices.contains(trimResolution.reference.loopIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface trim endpoint move references a missing trim loop."
            )
        }

        var updatedTrimLoops = surfaceFeature.trimLoops
        var trimLoop = updatedTrimLoops[trimResolution.reference.loopIndex]
        guard trimLoop.edges.indices.contains(trimResolution.reference.edgeIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface trim endpoint move references a missing trim edge."
            )
        }
        let movedParameter = SurfaceParameter(u: resolvedU, v: resolvedV)
        do {
            try movedParameter.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim endpoint move requires finite UV parameters: \(error)."
            )
        }

        let edgeIndex = trimResolution.reference.edgeIndex
        let adjacentEdgeIndex: Int
        let adjacentEndpoint: SurfaceTrimEndpoint
        switch endpoint {
        case .start:
            adjacentEdgeIndex = edgeIndex == trimLoop.edges.startIndex
                ? trimLoop.edges.index(before: trimLoop.edges.endIndex)
                : trimLoop.edges.index(before: edgeIndex)
            adjacentEndpoint = .end
        case .end:
            let nextIndex = trimLoop.edges.index(after: edgeIndex)
            adjacentEdgeIndex = nextIndex == trimLoop.edges.endIndex ? trimLoop.edges.startIndex : nextIndex
            adjacentEndpoint = .start
        }

        trimLoop.edges[edgeIndex].parameterCurve = try surfaceParameterCurve(
            trimLoop.edges[edgeIndex].parameterCurve,
            moving: endpoint,
            to: movedParameter,
            owner: "B-spline surface trim endpoint move"
        )
        trimLoop.edges[adjacentEdgeIndex].parameterCurve = try surfaceParameterCurve(
            trimLoop.edges[adjacentEdgeIndex].parameterCurve,
            moving: adjacentEndpoint,
            to: movedParameter,
            owner: "B-spline surface trim endpoint move"
        )

        do {
            try trimLoop.validate(on: surfaceFeature.surface)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim endpoint move produced an invalid closed UV trim loop: \(error)."
            )
        }
        updatedTrimLoops[trimResolution.reference.loopIndex] = trimLoop

        var updatedSurfaceFeature = surfaceFeature
        updatedSurfaceFeature.outerTrimDomain = nil
        updatedSurfaceFeature.trimLoops = updatedTrimLoops
        do {
            try updatedSurfaceFeature.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim endpoint move produced invalid source geometry: \(error)."
            )
        }
        feature.operation = .bSplineSurface(updatedSurfaceFeature)

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
                message: "B-spline surface trim endpoint move produced invalid rebuilt sheet topology: \(error)."
            )
        }
    }

    public mutating func moveSurfaceTrimControlPoint(
        target: SelectionReference,
        controlPointIndex: Int,
        u: CADExpression,
        v: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard controlPointIndex >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim control point move requires a non-negative control point index."
            )
        }
        let resolvedU = try resolvedScalarValue(
            u,
            owner: "B-spline surface trim control point U parameter"
        )
        let resolvedV = try resolvedScalarValue(
            v,
            owner: "B-spline surface trim control point V parameter"
        )
        let movedParameter = SurfaceParameter(u: resolvedU, v: resolvedV)
        do {
            try movedParameter.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim control point move requires finite UV parameters: \(error)."
            )
        }

        try updateBSplineSurfaceTrimParameterCurve(
            target: target,
            owner: "B-spline surface trim control point move",
            objectRegistry: objectRegistry
        ) { curve in
            try Self.surfaceParameterCurve(
                curve,
                movingControlPointAt: controlPointIndex,
                to: movedParameter,
                owner: "B-spline surface trim control point move"
            )
        }
    }

    public mutating func setSurfaceTrimControlPointWeight(
        target: SelectionReference,
        controlPointIndex: Int,
        weight: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard controlPointIndex >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim control point weight requires a non-negative control point index."
            )
        }
        let resolvedWeight = try resolvedPositiveScalarValue(
            weight,
            owner: "B-spline surface trim control point weight"
        )

        try updateBSplineSurfaceTrimParameterCurve(
            target: target,
            owner: "B-spline surface trim control point weight",
            objectRegistry: objectRegistry
        ) { curve in
            try Self.surfaceParameterCurve(
                curve,
                settingControlPointWeightAt: controlPointIndex,
                to: resolvedWeight,
                owner: "B-spline surface trim control point weight"
            )
        }
    }

    public mutating func insertSurfaceTrimKnot(
        target: SelectionReference,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedValue = try resolvedScalarValue(
            value,
            owner: "B-spline surface trim p-curve knot insertion"
        )
        let insertionTarget = try resolvedBSplineSurfaceTrimKnotInsertionTarget(
            target,
            owner: "B-spline surface trim p-curve knot insertion"
        )

        try updateBSplineSurfaceTrimParameterCurve(
            target: .surface(.trim(insertionTarget.trimReference)),
            owner: "B-spline surface trim p-curve knot insertion",
            objectRegistry: objectRegistry
        ) { curve in
            let insertionValue = try Self.resolvedSurfaceTrimKnotInsertionValue(
                resolvedValue,
                target: insertionTarget,
                curve: curve,
                owner: "B-spline surface trim p-curve knot insertion"
            )
            return try Self.surfaceParameterCurve(
                curve,
                insertingKnot: insertionValue,
                owner: "B-spline surface trim p-curve knot insertion"
            )
        }
    }

    public mutating func setSurfaceTrimKnotValue(
        target: SelectionReference,
        knotIndex: Int,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard knotIndex >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim p-curve knot value requires a non-negative knot index."
            )
        }
        let resolvedValue = try resolvedScalarValue(
            value,
            owner: "B-spline surface trim p-curve knot value"
        )
        let knotResolution = try resolvedBSplineSurfaceTrimKnotReference(
            target,
            fallbackKnotIndex: knotIndex,
            owner: "B-spline surface trim p-curve knot value"
        )

        try updateBSplineSurfaceTrimParameterCurve(
            target: .surface(.trim(knotResolution.reference.trim)),
            owner: "B-spline surface trim p-curve knot value",
            objectRegistry: objectRegistry
        ) { curve in
            try Self.surfaceParameterCurve(
                curve,
                settingKnotValueAt: knotResolution.reference.knotIndex,
                to: resolvedValue,
                owner: "B-spline surface trim p-curve knot value"
            )
        }
    }

    public mutating func setSurfaceTrimKnotMultiplicity(
        target: SelectionReference,
        knotIndex: Int,
        multiplicity: Int,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard knotIndex >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim p-curve knot multiplicity requires a non-negative knot index."
            )
        }
        guard multiplicity > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface trim p-curve knot multiplicity requires a positive multiplicity."
            )
        }
        let knotResolution = try resolvedBSplineSurfaceTrimKnotReference(
            target,
            fallbackKnotIndex: knotIndex,
            owner: "B-spline surface trim p-curve knot multiplicity"
        )

        try updateBSplineSurfaceTrimParameterCurve(
            target: .surface(.trim(knotResolution.reference.trim)),
            owner: "B-spline surface trim p-curve knot multiplicity",
            objectRegistry: objectRegistry
        ) { curve in
            try Self.surfaceParameterCurve(
                curve,
                settingKnotMultiplicityAt: knotResolution.reference.knotIndex,
                to: multiplicity,
                owner: "B-spline surface trim p-curve knot multiplicity"
            )
        }
    }

    public mutating func matchSurfaceBoundaryContinuity(
        target: SelectionReference,
        reference: SelectionReference,
        level: SurfaceBoundaryContinuityLevel,
        matchSide: SurfaceBoundaryMatchSide = .automatic,
        referenceDirection: SurfaceBoundaryReferenceDirection = .automatic,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let targetResolution = try resolvedBSplineSurfaceBoundaryReference(
            target,
            owner: "B-spline surface boundary continuity target"
        )
        let referenceResolution = try resolvedBSplineSurfaceBoundaryReference(
            reference,
            owner: "B-spline surface boundary continuity reference"
        )
        guard targetResolution.featureID != referenceResolution.featureID
                || targetResolution.side != referenceResolution.side else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface boundary continuity requires distinct target and reference boundaries."
            )
        }
        guard var targetFeature = cadDocument.designGraph.nodes[targetResolution.featureID],
              case let .bSplineSurface(targetSurfaceFeature) = targetFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface boundary continuity requires an existing target B-spline surface source feature."
            )
        }
        guard let referenceFeature = cadDocument.designGraph.nodes[referenceResolution.featureID],
              case let .bSplineSurface(referenceSurfaceFeature) = referenceFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface boundary continuity requires an existing reference B-spline surface source feature."
            )
        }
        try validateFullSurfaceTrimDomain(
            targetSurfaceFeature,
            owner: "B-spline surface boundary continuity target"
        )
        try validateFullSurfaceTrimDomain(
            referenceSurfaceFeature,
            owner: "B-spline surface boundary continuity reference"
        )

        let continuityEditor = BSplineSurfaceBoundaryContinuityEditingService()
        targetFeature.operation = .bSplineSurface(try continuityEditor.updatedFeature(
            matching: targetSurfaceFeature,
            targetSide: targetResolution.side,
            to: referenceSurfaceFeature,
            referenceSide: referenceResolution.side,
            level: level,
            matchSide: matchSide,
            referenceDirection: referenceDirection,
            owner: "B-spline surface boundary continuity"
        ))

        var updatedCADDocument = cadDocument
        let previousCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(targetFeature)
            cadDocument = updatedCADDocument
            try validate(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface boundary continuity produced invalid source geometry: \(error)."
            )
        }
    }

    public func surfaceBoundaryContinuityCompatibility(
        target: SelectionReference,
        reference: SelectionReference
    ) throws -> SurfaceBoundaryContinuityCompatibilityResult {
        let targetResolution = try resolvedBSplineSurfaceBoundaryReference(
            target,
            owner: "B-spline surface boundary continuity compatibility target"
        )
        let referenceResolution = try resolvedBSplineSurfaceBoundaryReference(
            reference,
            owner: "B-spline surface boundary continuity compatibility reference"
        )
        guard let targetFeature = cadDocument.designGraph.nodes[targetResolution.featureID],
              case let .bSplineSurface(targetSurfaceFeature) = targetFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface boundary continuity compatibility requires an existing target B-spline surface source feature."
            )
        }
        guard let referenceFeature = cadDocument.designGraph.nodes[referenceResolution.featureID],
              case let .bSplineSurface(referenceSurfaceFeature) = referenceFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "B-spline surface boundary continuity compatibility requires an existing reference B-spline surface source feature."
            )
        }
        try validateFullSurfaceTrimDomain(
            targetSurfaceFeature,
            owner: "B-spline surface boundary continuity compatibility target"
        )
        try validateFullSurfaceTrimDomain(
            referenceSurfaceFeature,
            owner: "B-spline surface boundary continuity compatibility reference"
        )

        return try SurfaceBoundaryContinuityCompatibilityService().compatibility(
            targetFeatureID: targetResolution.featureID,
            targetSelectionReference: target,
            targetFeature: targetSurfaceFeature,
            targetSide: targetResolution.side,
            referenceFeatureID: referenceResolution.featureID,
            referenceSelectionReference: reference,
            referenceFeature: referenceSurfaceFeature,
            referenceSide: referenceResolution.side
        )
    }

    private struct BSplineSurfaceKnotResolution {
        var featureID: FeatureID
        var reference: SurfaceKnotReference
    }

    private struct BSplineSurfaceBoundaryResolution {
        var featureID: FeatureID
        var reference: SurfaceTrimReference
        var side: BSplineSurfaceBoundarySide
    }

    private struct BSplineSurfaceSourceResolution {
        var featureID: FeatureID
        var reference: SurfaceReference
    }

    private struct BSplineSurfaceTrimResolution {
        var featureID: FeatureID
        var reference: SurfaceTrimReference
    }

    private struct BSplineSurfaceTrimSpanResolution {
        var featureID: FeatureID
        var reference: SurfaceTrimSpanReference
    }

    private struct BSplineSurfaceTrimKnotResolution {
        var featureID: FeatureID
        var reference: SurfaceTrimKnotReference
    }

    private struct BSplineSurfaceSpanResolution {
        var featureID: FeatureID
        var reference: SurfaceSpanReference
    }

    private enum BSplineSurfaceKnotInsertionResolution {
        case span(BSplineSurfaceSpanResolution)
        case knot(BSplineSurfaceKnotResolution)

        var featureID: FeatureID {
            switch self {
            case .span(let resolution):
                resolution.featureID
            case .knot(let resolution):
                resolution.featureID
            }
        }

        var direction: SurfaceParameterDirection {
            switch self {
            case .span(let resolution):
                resolution.reference.direction
            case .knot(let resolution):
                resolution.reference.direction
            }
        }
    }

    private enum BSplineSurfaceTrimKnotInsertionResolution {
        case trim(BSplineSurfaceTrimResolution)
        case span(BSplineSurfaceTrimSpanResolution)
        case knot(BSplineSurfaceTrimKnotResolution)

        var featureID: FeatureID {
            switch self {
            case .trim(let resolution):
                resolution.featureID
            case .span(let resolution):
                resolution.featureID
            case .knot(let resolution):
                resolution.featureID
            }
        }

        var trimReference: SurfaceTrimReference {
            switch self {
            case .trim(let resolution):
                resolution.reference
            case .span(let resolution):
                resolution.reference.trim
            case .knot(let resolution):
                resolution.reference.trim
            }
        }
    }

    private func resolvedBSplineSurfaceBoundaryReference(
        _ selection: SelectionReference,
        owner: String
    ) throws -> BSplineSurfaceBoundaryResolution {
        guard case .surface(.trim(let reference)) = selection else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a surface trim selection reference."
            )
        }
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a valid surface trim selection reference: \(error)."
            )
        }
        guard reference.loopIndex == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a direct B-spline outer trim edge."
            )
        }
        let patchFace = try resolvedSurfacePatchFace(
            from: reference.surface.faceName,
            owner: owner
        )
        guard patchFace.generatedRole == "bSplineSurface",
              patchFace.patchID == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a direct B-spline surface patch face selection reference."
            )
        }
        return BSplineSurfaceBoundaryResolution(
            featureID: patchFace.featureID,
            reference: reference,
            side: try BSplineSurfaceBoundarySide(
                trimEdgeIndex: reference.edgeIndex,
                owner: owner
            )
        )
    }

    private func resolvedBSplineSurfaceTrimReference(
        _ selection: SelectionReference,
        owner: String
    ) throws -> BSplineSurfaceTrimResolution {
        guard case .surface(.trim(let reference)) = selection else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a surface trim selection reference."
            )
        }
        return try resolvedBSplineSurfaceTrimReference(
            reference,
            owner: owner
        )
    }

    private func resolvedBSplineSurfaceTrimReference(
        _ reference: SurfaceTrimReference,
        owner: String
    ) throws -> BSplineSurfaceTrimResolution {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a valid surface trim selection reference: \(error)."
            )
        }
        let patchFace = try resolvedSurfacePatchFace(
            from: reference.surface.faceName,
            owner: owner
        )
        guard patchFace.generatedRole == "bSplineSurface",
              patchFace.patchID == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a direct B-spline surface patch face selection reference."
            )
        }
        return BSplineSurfaceTrimResolution(
            featureID: patchFace.featureID,
            reference: reference
        )
    }

    private func resolvedBSplineSurfaceTrimSpanReference(
        _ selection: SelectionReference,
        owner: String
    ) throws -> BSplineSurfaceTrimSpanResolution {
        guard case .surface(.trimSpan(let reference)) = selection else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a surface trim span selection reference."
            )
        }
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a valid surface trim span selection reference: \(error)."
            )
        }
        let trimResolution = try resolvedBSplineSurfaceTrimReference(
            reference.trim,
            owner: owner
        )
        return BSplineSurfaceTrimSpanResolution(
            featureID: trimResolution.featureID,
            reference: reference
        )
    }

    private func resolvedBSplineSurfaceTrimKnotReference(
        _ selection: SelectionReference,
        fallbackKnotIndex: Int,
        owner: String
    ) throws -> BSplineSurfaceTrimKnotResolution {
        let reference: SurfaceTrimKnotReference
        switch selection {
        case .surface(.trimKnot(let trimKnotReference)):
            guard fallbackKnotIndex == trimKnotReference.knotIndex else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) knot index must match the selected trim p-curve knot."
                )
            }
            reference = trimKnotReference
        case .surface(.trim(let trimReference)):
            reference = SurfaceTrimKnotReference(
                trim: trimReference,
                knotIndex: fallbackKnotIndex
            )
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a surface trim knot or surface trim selection reference."
            )
        }
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a valid surface trim knot selection reference: \(error)."
            )
        }
        let trimResolution = try resolvedBSplineSurfaceTrimReference(
            reference.trim,
            owner: owner
        )
        return BSplineSurfaceTrimKnotResolution(
            featureID: trimResolution.featureID,
            reference: reference
        )
    }

    private func resolvedBSplineSurfaceTrimKnotInsertionTarget(
        _ selection: SelectionReference,
        owner: String
    ) throws -> BSplineSurfaceTrimKnotInsertionResolution {
        switch selection {
        case .surface(.trim):
            return .trim(try resolvedBSplineSurfaceTrimReference(selection, owner: owner))
        case .surface(.trimSpan):
            return .span(try resolvedBSplineSurfaceTrimSpanReference(selection, owner: owner))
        case .surface(.trimKnot(let reference)):
            do {
                try reference.validate()
            } catch {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a valid surface trim knot selection reference: \(error)."
                )
            }
            let trimResolution = try resolvedBSplineSurfaceTrimReference(
                reference.trim,
                owner: owner
            )
            return .knot(BSplineSurfaceTrimKnotResolution(
                featureID: trimResolution.featureID,
                reference: reference
            ))
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a surface trim, trim span, or trim knot selection reference."
            )
        }
    }

    private func resolvedBSplineSurfaceSourceReference(
        _ selection: SelectionReference,
        owner: String
    ) throws -> BSplineSurfaceSourceResolution {
        let reference: SurfaceReference
        switch selection {
        case .surface(.whole(let surfaceReference)):
            reference = surfaceReference
        case .surface(.parameter(let parameterReference)):
            reference = parameterReference.surface
        case .surface(.span(let spanReference)):
            reference = spanReference.surface
        case .surface(.controlPoint(let controlPointReference)):
            reference = controlPointReference.surface
        case .surface(.knot(let knotReference)):
            reference = knotReference.surface
        case .surface(.trim(let trimReference)):
            reference = trimReference.surface
        case .surface(.trimSpan(let trimSpanReference)):
            reference = trimSpanReference.trim.surface
        case .surface(.trimKnot(let trimKnotReference)):
            reference = trimKnotReference.trim.surface
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a direct B-spline surface selection reference."
            )
        }
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a valid surface selection reference: \(error)."
            )
        }
        let patchFace = try resolvedSurfacePatchFace(
            from: reference.faceName,
            owner: owner
        )
        guard patchFace.generatedRole == "bSplineSurface",
              patchFace.patchID == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a direct B-spline surface patch face selection reference."
            )
        }
        return BSplineSurfaceSourceResolution(
            featureID: patchFace.featureID,
            reference: reference
        )
    }

    private func validateFullSurfaceTrimDomain(
        _ feature: BSplineSurfaceFeature,
        owner: String
    ) throws {
        guard feature.trimLoops.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a full-domain rectangular outer trim because authored trim loops do not expose boundary control rows for continuity matching."
            )
        }
        let trimDomain = try feature.resolvedOuterTrimDomain()
        guard try trimDomain.isFullSurfaceDomain(of: feature.surface) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a full-domain rectangular outer trim because interior trim domains do not expose boundary control rows for continuity matching."
            )
        }
    }

    private mutating func updateBSplineSurfaceTrimParameterCurve(
        target: SelectionReference,
        owner: String,
        objectRegistry: ObjectTypeRegistry,
        update: (SurfaceParameterCurve) throws -> SurfaceParameterCurve
    ) throws {
        let trimResolution = try resolvedBSplineSurfaceTrimReference(
            target,
            owner: owner
        )
        guard var feature = cadDocument.designGraph.nodes[trimResolution.featureID],
              case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires an existing direct B-spline surface source feature."
            )
        }
        guard surfaceFeature.trimLoops.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires authored UV trim loops; rectangular trim domains must be edited with setSurfaceTrimDomain."
            )
        }
        guard surfaceFeature.trimLoops.indices.contains(trimResolution.reference.loopIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing trim loop."
            )
        }

        var updatedTrimLoops = surfaceFeature.trimLoops
        var trimLoop = updatedTrimLoops[trimResolution.reference.loopIndex]
        guard trimLoop.edges.indices.contains(trimResolution.reference.edgeIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing trim edge."
            )
        }

        let edgeIndex = trimResolution.reference.edgeIndex
        trimLoop.edges[edgeIndex].parameterCurve = try update(trimLoop.edges[edgeIndex].parameterCurve)
        do {
            try trimLoop.validate(on: surfaceFeature.surface)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced an invalid closed UV trim loop: \(error)."
            )
        }
        updatedTrimLoops[trimResolution.reference.loopIndex] = trimLoop

        var updatedSurfaceFeature = surfaceFeature
        updatedSurfaceFeature.outerTrimDomain = nil
        updatedSurfaceFeature.trimLoops = updatedTrimLoops
        do {
            try updatedSurfaceFeature.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced invalid source geometry: \(error)."
            )
        }
        feature.operation = .bSplineSurface(updatedSurfaceFeature)

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
                message: "\(owner) produced invalid rebuilt sheet topology: \(error)."
            )
        }
    }

    private func surfaceParameterCurve(
        _ curve: SurfaceParameterCurve,
        moving endpoint: SurfaceTrimEndpoint,
        to parameter: SurfaceParameter,
        owner: String
    ) throws -> SurfaceParameterCurve {
        switch curve {
        case .constantU:
            let currentStart = try curve.startParameter()
            let currentEnd = try curve.endParameter()
            return linearSurfaceParameterCurve(
                from: endpoint == .start ? parameter : currentStart,
                to: endpoint == .end ? parameter : currentEnd
            )
        case .constantV:
            let currentStart = try curve.startParameter()
            let currentEnd = try curve.endParameter()
            return linearSurfaceParameterCurve(
                from: endpoint == .start ? parameter : currentStart,
                to: endpoint == .end ? parameter : currentEnd
            )
        case let .polyline(points):
            guard points.count >= 2 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires trim polyline p-curves with at least two points."
                )
            }
            var updatedPoints = points
            switch endpoint {
            case .start:
                updatedPoints[updatedPoints.startIndex] = parameter
            case .end:
                updatedPoints[updatedPoints.index(before: updatedPoints.endIndex)] = parameter
            }
            return .polyline(updatedPoints)
        case let .bSpline(curve):
            guard curve.controlPoints.isEmpty == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires trim B-spline p-curves with at least one control point."
                )
            }
            var updatedCurve = curve
            let point = Point2D(x: parameter.u, y: parameter.v)
            switch endpoint {
            case .start:
                updatedCurve.controlPoints[updatedCurve.controlPoints.startIndex] = point
            case .end:
                updatedCurve.controlPoints[updatedCurve.controlPoints.index(before: updatedCurve.controlPoints.endIndex)] = point
            }
            return .bSpline(updatedCurve)
        }
    }

    private static func surfaceParameterCurve(
        _ curve: SurfaceParameterCurve,
        movingControlPointAt index: Int,
        to parameter: SurfaceParameter,
        owner: String
    ) throws -> SurfaceParameterCurve {
        switch curve {
        case .constantU, .constantV:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a polyline or B-spline p-curve interior control point."
            )
        case let .polyline(points):
            guard points.indices.contains(index) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) references a missing trim polyline point."
                )
            }
            guard index != points.startIndex,
                  index != points.index(before: points.endIndex) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) must use moveSurfaceTrimEndpoint for trim polyline endpoints."
                )
            }
            var updatedPoints = points
            updatedPoints[index] = parameter
            return .polyline(updatedPoints)
        case let .bSpline(curve):
            guard curve.controlPoints.indices.contains(index) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) references a missing trim B-spline control point."
                )
            }
            guard index != curve.controlPoints.startIndex,
                  index != curve.controlPoints.index(before: curve.controlPoints.endIndex) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) must use moveSurfaceTrimEndpoint for trim B-spline endpoints."
                )
            }
            var updatedCurve = curve
            updatedCurve.controlPoints[index] = Point2D(x: parameter.u, y: parameter.v)
            return .bSpline(updatedCurve)
        }
    }

    private static func surfaceParameterCurve(
        _ curve: SurfaceParameterCurve,
        settingControlPointWeightAt index: Int,
        to weight: Double,
        owner: String
    ) throws -> SurfaceParameterCurve {
        switch curve {
        case .constantU, .constantV, .polyline:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a B-spline p-curve control point weight."
            )
        case let .bSpline(curve):
            guard curve.controlPoints.indices.contains(index) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) references a missing trim B-spline control point."
                )
            }
            guard curve.weights.indices.contains(index) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) references a missing trim B-spline control point weight."
                )
            }
            var updatedCurve = curve
            updatedCurve.weights[index] = weight
            do {
                try updatedCurve.validate()
            } catch {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) produced invalid trim B-spline p-curve weights: \(error)."
                )
            }
            return .bSpline(updatedCurve)
        }
    }

    private static func surfaceParameterCurve(
        _ curve: SurfaceParameterCurve,
        insertingKnot value: Double,
        owner: String
    ) throws -> SurfaceParameterCurve {
        switch curve {
        case .constantU, .constantV, .polyline:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a B-spline trim p-curve."
            )
        case let .bSpline(curve):
            do {
                return .bSpline(try curve.insertingKnot(value))
            } catch {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) could not insert the B-spline trim p-curve knot: \(error)."
                )
            }
        }
    }

    private static func resolvedSurfaceTrimKnotInsertionValue(
        _ value: Double,
        target: BSplineSurfaceTrimKnotInsertionResolution,
        curve: SurfaceParameterCurve,
        owner: String
    ) throws -> Double {
        switch target {
        case .trim:
            return value
        case .span(let resolution):
            let spanBounds = try surfaceTrimParameterCurveSpanBounds(
                for: resolution.reference,
                in: curve,
                owner: owner
            )
            guard value > spanBounds.lower,
                  value < spanBounds.upper else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) value must be strictly inside the selected trim p-curve span."
                )
            }
            return value
        case .knot(let resolution):
            let knotValue = try surfaceTrimParameterCurveKnotValue(
                for: resolution.reference,
                in: curve,
                owner: owner
            )
            let equalityTolerance = max(abs(knotValue), 1.0) * 1.0e-9
            guard abs(value - knotValue) <= equalityTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) value must match the selected trim p-curve knot value."
                )
            }
            return knotValue
        }
    }

    private static func surfaceTrimParameterCurveKnotValue(
        for reference: SurfaceTrimKnotReference,
        in curve: SurfaceParameterCurve,
        owner: String
    ) throws -> Double {
        guard case let .bSpline(bSpline) = curve else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a B-spline trim p-curve."
            )
        }
        guard bSpline.knots.indices.contains(reference.knotIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing B-spline trim p-curve knot."
            )
        }
        let firstInteriorKnotIndex = bSpline.degree + 1
        let lastInteriorKnotIndex = bSpline.knots.count - bSpline.degree - 2
        guard firstInteriorKnotIndex <= lastInteriorKnotIndex,
              (firstInteriorKnotIndex ... lastInteriorKnotIndex).contains(reference.knotIndex) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) can insert duplicate knots only at interior trim p-curve knots."
            )
        }
        return bSpline.knots[reference.knotIndex]
    }

    private static func surfaceTrimParameterCurveSpanBounds(
        for reference: SurfaceTrimSpanReference,
        in curve: SurfaceParameterCurve,
        owner: String
    ) throws -> (lower: Double, upper: Double) {
        guard case let .bSpline(bSpline) = curve else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a B-spline trim p-curve."
            )
        }
        let lowerIndex = bSpline.degree
        let upperIndex = bSpline.knots.count - bSpline.degree - 1
        var ordinal = 0
        guard lowerIndex < upperIndex else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) could not resolve a queryable B-spline trim p-curve span."
            )
        }
        for index in lowerIndex..<upperIndex {
            let lowerBound = bSpline.knots[index]
            let upperBound = bSpline.knots[index + 1]
            guard upperBound > lowerBound else {
                continue
            }
            if ordinal == reference.spanIndex {
                return (lowerBound, upperBound)
            }
            ordinal += 1
        }
        throw EditorError(
            code: .referenceUnresolved,
            message: "\(owner) references a missing B-spline trim p-curve span."
        )
    }

    private static func surfaceParameterCurve(
        _ curve: SurfaceParameterCurve,
        settingKnotValueAt index: Int,
        to value: Double,
        owner: String
    ) throws -> SurfaceParameterCurve {
        switch curve {
        case .constantU, .constantV, .polyline:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a B-spline trim p-curve."
            )
        case let .bSpline(curve):
            do {
                return .bSpline(try curve.settingKnotValue(at: index, to: value))
            } catch {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) could not set the B-spline trim p-curve knot value: \(error)."
                )
            }
        }
    }

    private static func surfaceParameterCurve(
        _ curve: SurfaceParameterCurve,
        settingKnotMultiplicityAt index: Int,
        to multiplicity: Int,
        owner: String
    ) throws -> SurfaceParameterCurve {
        switch curve {
        case .constantU, .constantV, .polyline:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a B-spline trim p-curve."
            )
        case let .bSpline(curve):
            do {
                return .bSpline(try curve.settingKnotMultiplicity(at: index, to: multiplicity))
            } catch {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) could not set the B-spline trim p-curve knot multiplicity: \(error)."
                )
            }
        }
    }

    private func linearSurfaceParameterCurve(
        from start: SurfaceParameter,
        to end: SurfaceParameter
    ) -> SurfaceParameterCurve {
        if abs(start.u - end.u) <= ModelingTolerance.standard.distance {
            return .constantU(u: start.u, vStart: start.v, vEnd: end.v)
        }
        if abs(start.v - end.v) <= ModelingTolerance.standard.distance {
            return .constantV(v: start.v, uStart: start.u, uEnd: end.u)
        }
        return .polyline([start, end])
    }

    private func resolvedBSplineSurfaceKnotReference(
        _ selection: SelectionReference,
        owner: String
    ) throws -> BSplineSurfaceKnotResolution {
        guard case .surface(.knot(let reference)) = selection else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a surface knot selection reference."
            )
        }
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a valid surface knot selection reference: \(error)."
            )
        }
        let patchFace = try resolvedSurfacePatchFace(
            from: reference.surface.faceName,
            owner: owner
        )
        guard patchFace.generatedRole == "bSplineSurface",
              patchFace.patchID == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a direct B-spline surface patch face selection reference."
            )
        }
        return BSplineSurfaceKnotResolution(
            featureID: patchFace.featureID,
            reference: reference
        )
    }

    private func resolvedBSplineSurfaceSpanReference(
        _ selection: SelectionReference,
        owner: String
    ) throws -> BSplineSurfaceSpanResolution {
        guard case .surface(.span(let reference)) = selection else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a surface span selection reference."
            )
        }
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a valid surface span selection reference: \(error)."
            )
        }
        let patchFace = try resolvedSurfacePatchFace(
            from: reference.surface.faceName,
            owner: owner
        )
        guard patchFace.generatedRole == "bSplineSurface",
              patchFace.patchID == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a direct B-spline surface patch face selection reference."
            )
        }
        return BSplineSurfaceSpanResolution(
            featureID: patchFace.featureID,
            reference: reference
        )
    }

    private func resolvedBSplineSurfaceKnotInsertionTarget(
        _ selection: SelectionReference,
        owner: String
    ) throws -> BSplineSurfaceKnotInsertionResolution {
        switch selection {
        case .surface(.span):
            return .span(try resolvedBSplineSurfaceSpanReference(selection, owner: owner))
        case .surface(.knot):
            return .knot(try resolvedBSplineSurfaceKnotReference(selection, owner: owner))
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a surface span or surface knot selection reference."
            )
        }
    }

    private func resolvedBSplineSurfaceKnotInsertionValue(
        _ value: Double,
        target: BSplineSurfaceKnotInsertionResolution,
        surface: BSplineSurface3D,
        owner: String
    ) throws -> Double {
        switch target {
        case .span(let resolution):
            let spanBounds = try bSplineSurfaceSpanBounds(
                for: resolution.reference,
                in: surface,
                owner: owner
            )
            guard value > spanBounds.lower,
                  value < spanBounds.upper else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) value must be strictly inside the selected surface span."
                )
            }
            return value
        case .knot(let resolution):
            let knotValue = try bSplineSurfaceKnotValue(
                for: resolution.reference,
                in: surface,
                owner: owner
            )
            let equalityTolerance = max(abs(knotValue), 1.0) * 1.0e-9
            guard abs(value - knotValue) <= equalityTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) value must match the selected existing surface knot value."
                )
            }
            return knotValue
        }
    }

    private func bSplineSurfaceKnotValue(
        for reference: SurfaceKnotReference,
        in surface: BSplineSurface3D,
        owner: String
    ) throws -> Double {
        let knots: [Double]
        let degree: Int
        switch reference.direction {
        case .u:
            knots = surface.uKnots
            degree = surface.uDegree
        case .v:
            knots = surface.vKnots
            degree = surface.vDegree
        }
        guard knots.indices.contains(reference.knotIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing B-spline surface knot."
            )
        }
        let firstInteriorKnotIndex = degree + 1
        let lastInteriorKnotIndex = knots.count - degree - 2
        guard firstInteriorKnotIndex <= lastInteriorKnotIndex,
              (firstInteriorKnotIndex ... lastInteriorKnotIndex).contains(reference.knotIndex) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) can insert duplicate knots only at interior B-spline surface knots."
            )
        }
        return knots[reference.knotIndex]
    }

    private func bSplineSurfaceSpanBounds(
        for reference: SurfaceSpanReference,
        in surface: BSplineSurface3D,
        owner: String
    ) throws -> (lower: Double, upper: Double) {
        let knots: [Double]
        let degree: Int
        switch reference.direction {
        case .u:
            knots = surface.uKnots
            degree = surface.uDegree
        case .v:
            knots = surface.vKnots
            degree = surface.vDegree
        }
        let lowerIndex = degree
        let upperIndex = knots.count - degree - 1
        var ordinal = 0
        guard lowerIndex < upperIndex else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) could not resolve a queryable B-spline surface span."
            )
        }
        for index in lowerIndex..<upperIndex {
            let lowerBound = knots[index]
            let upperBound = knots[index + 1]
            guard upperBound > lowerBound else {
                continue
            }
            if ordinal == reference.spanIndex {
                return (lowerBound, upperBound)
            }
            ordinal += 1
        }
        throw EditorError(
            code: .referenceUnresolved,
            message: "\(owner) references a missing B-spline surface span."
        )
    }

    private struct SurfacePatchFaceResolution {
        var featureID: FeatureID
        var generatedRole: String
        var patchID: Int
    }

    private func resolvedSurfacePatchFace(
        from name: PersistentName,
        owner: String
    ) throws -> SurfacePatchFaceResolution {
        var featureID: FeatureID?
        var generatedRole: String?
        var subshape: String?
        for component in name.components {
            switch component {
            case .feature(let id):
                featureID = id
            case .generated(let value):
                generatedRole = value
            case .subshape(let value):
                subshape = value
            case .index:
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a source-owned surface patch face selection reference."
                )
            }
        }
        guard let featureID,
              let generatedRole,
              let subshape else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a source-owned surface patch face selection reference."
            )
        }
        let parts = subshape.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              parts[0] == "patch",
              let patchID = Int(parts[1]),
              parts[2] == "face" else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a source-owned surface patch face selection reference."
            )
        }
        return SurfacePatchFaceResolution(
            featureID: featureID,
            generatedRole: generatedRole,
            patchID: patchID
        )
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
        var bSplineSurfaceTargets: [BSplineSurfaceControlPointEditTarget] = []
        boundaryTargets.reserveCapacity(targets.count)
        interiorTargets.reserveCapacity(targets.count)
        bSplineSurfaceTargets.reserveCapacity(targets.count)
        for target in targets {
            switch try resolver.editTarget(for: target, in: self) {
            case .boundaryVertex(let target):
                boundaryTargets.append(target)
            case .interiorControlPoint(let target):
                interiorTargets.append(target)
            case .bSplineSurfaceControlPoint(let target):
                bSplineSurfaceTargets.append(target)
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
            if bSplineSurfaceTargets.isEmpty == false {
                try slideBSplineSurfaceControlPoints(
                    targets: bSplineSurfaceTargets,
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

    private mutating func slideBSplineSurfaceControlPoints(
        targets: [BSplineSurfaceControlPointEditTarget],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface control point slide requires at least one control point target."
            )
        }
        let resolvedDistance = try resolvedLengthValue(
            distance,
            owner: "B-spline surface control point slide distance"
        )
        guard abs(resolvedDistance) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "B-spline surface control point slide requires a non-zero distance."
            )
        }

        struct ControlPointKey: Hashable {
            var featureID: FeatureID
            var uIndex: Int
            var vIndex: Int
        }

        var featuresByID: [FeatureID: FeatureNode] = [:]
        var surfaceFeaturesByID: [FeatureID: BSplineSurfaceFeature] = [:]
        var seenTargets: Set<ControlPointKey> = []
        let controlPointEditor = BSplineSurfaceControlPointEditingService()

        for target in targets {
            let duplicateKey = ControlPointKey(
                featureID: target.featureID,
                uIndex: target.uIndex,
                vIndex: target.vIndex
            )
            guard seenTargets.insert(duplicateKey).inserted else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "B-spline surface control point slide cannot receive duplicate targets."
                )
            }
            let surfaceFeature: BSplineSurfaceFeature
            if let cachedSurfaceFeature = surfaceFeaturesByID[target.featureID] {
                surfaceFeature = cachedSurfaceFeature
            } else {
                guard let sourceFeature = cadDocument.designGraph.nodes[target.featureID],
                      case let .bSplineSurface(sourceSurfaceFeature) = sourceFeature.operation else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "B-spline surface control point slide requires an existing direct B-spline surface source feature."
                    )
                }
                featuresByID[target.featureID] = sourceFeature
                surfaceFeature = sourceSurfaceFeature
            }

            let unitDirection = try controlPointEditor.slideUnitVector(
                for: target,
                in: surfaceFeature,
                direction: direction
            )
            let delta = Vector3D(
                x: unitDirection.x * resolvedDistance,
                y: unitDirection.y * resolvedDistance,
                z: unitDirection.z * resolvedDistance
            )
            surfaceFeaturesByID[target.featureID] = try controlPointEditor.updatedFeature(
                moving: target,
                by: delta,
                in: surfaceFeature,
                owner: "B-spline surface control point slide"
            )
        }

        var replacementFeatures: [FeatureNode] = []
        for (featureID, feature) in featuresByID {
            guard let surfaceFeature = surfaceFeaturesByID[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "B-spline surface control point slide lost a resolved source update."
                )
            }
            var updatedFeature = feature
            updatedFeature.operation = .bSplineSurface(surfaceFeature)
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
                message: "B-spline surface control point slide produced invalid source geometry: \(error)."
            )
        }
    }
}
